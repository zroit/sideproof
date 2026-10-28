"""Language model providers behind one call: complete(system, prompt, image=None) -> text.

claude-cli runs Claude Code headless on the host (development only: it needs that machine's
login). gemini and deepseek take API keys and are what the public demo uses. The models
never see a face: only label photos and numbers.
"""
import base64
import json
import os
import pathlib
import re
import subprocess
import tempfile

import httpx

from . import config


class LLMError(RuntimeError):
    pass


class ClaudeCli:
    name = 'claude-cli'

    def __init__(self, model=None):
        self.model = model or os.environ.get('CLAUDE_CLI_MODEL', 'sonnet')

    def complete(self, system, prompt, image=None):
        with tempfile.TemporaryDirectory() as tmp:
            args = ['claude', '-p', '--model', self.model, '--output-format', 'json', '--system-prompt', system,
                    '--no-session-persistence', '--disable-slash-commands', '--strict-mcp-config']
            if image:
                label = pathlib.Path(tmp, 'label.jpg')
                label.write_bytes(image)
                prompt += f'\n\nThe product label photo is the file {label}. Read it.'
                args += ['--tools', 'Read', '--allowedTools', 'Read']
            else:
                args += ['--tools', '']
            run = subprocess.run(args, input=prompt, capture_output=True, text=True, cwd=tmp, timeout=180)
        try:
            out = json.loads(run.stdout)
        except ValueError:
            raise LLMError(f'claude-cli: {run.stderr.strip()[:200] or "no output"}')
        if out.get('is_error'):
            raise LLMError('claude-cli: ' + str(out.get('result'))[:200])
        return out.get('result', '')


class Gemini:
    name = 'gemini'

    def __init__(self, model=None):
        self.model = model or os.environ.get('GEMINI_MODEL', 'gemini-2.5-flash')

    def complete(self, system, prompt, image=None):
        key = config.secret('GEMINI_API_KEY')
        if not key:
            raise LLMError('gemini: no key configured')
        parts = [{'text': prompt}]
        if image:
            parts.append({'inline_data': {'mime_type': 'image/jpeg', 'data': base64.b64encode(image).decode()}})
        r = httpx.post(f'https://generativelanguage.googleapis.com/v1beta/models/{self.model}:generateContent',
                       headers={'x-goog-api-key': key}, timeout=90, json={
                           'system_instruction': {'parts': [{'text': system}]},
                           'contents': [{'role': 'user', 'parts': parts}],
                           'generationConfig': {'responseMimeType': 'application/json', 'temperature': 0.2}})
        if r.status_code != 200:
            raise LLMError(f'gemini: HTTP {r.status_code}')
        try:
            return r.json()['candidates'][0]['content']['parts'][0]['text']
        except (KeyError, IndexError):
            raise LLMError('gemini: empty answer')


class DeepSeek:
    name = 'deepseek'

    def __init__(self, model=None):
        self.model = model or os.environ.get('DEEPSEEK_MODEL', 'deepseek-chat')

    def complete(self, system, prompt, image=None):
        if image:
            raise LLMError('deepseek: cannot read images')
        key = config.secret('DEEPSEEK_API_KEY')
        if not key:
            raise LLMError('deepseek: no key configured')
        r = httpx.post('https://api.deepseek.com/chat/completions', headers={'Authorization': 'Bearer ' + key}, timeout=90, json={
            'model': self.model, 'temperature': 0.2, 'response_format': {'type': 'json_object'},
            'messages': [{'role': 'system', 'content': system}, {'role': 'user', 'content': prompt}]})
        if r.status_code != 200:
            raise LLMError(f'deepseek: HTTP {r.status_code}')
        return r.json()['choices'][0]['message']['content']


PROVIDERS = {p.name: p for p in (ClaudeCli, Gemini, DeepSeek)}


def get(name):
    if name not in PROVIDERS:
        raise LLMError(f'unknown provider {name}')
    return PROVIDERS[name]()


def parse_json(text):
    text = re.sub(r'^```(?:json)?|```$', '', text.strip(), flags=re.M).strip()
    start, end = text.find('{'), text.rfind('}')
    if start < 0 or end < start:
        raise LLMError('answer was not JSON')
    try:
        return json.loads(text[start:end + 1])
    except ValueError as e:
        raise LLMError(f'answer was not JSON: {e}')
