"""Language model providers behind one call: complete(system, prompt, image=None) -> text.

claude-cli runs Claude Code headless on the host (development only: it needs that machine's
login). gemini and deepseek take API keys and are what the public demo uses. modal is an open
model (Qwen3-VL, served by vLLM) on our own Modal endpoint: Gemini falls back to it when every
Gemini model is busy or out of quota. The models never see a face: only label photos and
numbers.
"""
import base64
import json
import os
import pathlib
import re
import shutil
import subprocess
import tempfile
import threading
import time

import httpx

from . import config


class LLMError(RuntimeError):
    pass


class ClaudeCli:
    name = 'claude-cli'
    reads_images = True

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
            try:
                run = subprocess.run(args, input=prompt, capture_output=True, text=True, cwd=tmp, timeout=180)
            except FileNotFoundError:
                raise LLMError('claude-cli: Claude Code is not installed on this server')
            except subprocess.TimeoutExpired:
                raise LLMError('claude-cli: no answer in 3 minutes')
        try:
            out = json.loads(run.stdout)
        except ValueError:
            raise LLMError(f'claude-cli: {run.stderr.strip()[:200] or "no output"}')
        if out.get('is_error'):
            raise LLMError('claude-cli: ' + str(out.get('result'))[:200])
        return out.get('result', '')


class Gemini:
    name = 'gemini'
    reads_images = True

    # Busy answers (429, 500, 503) are common and short-lived: wait and retry, last try on the
    # lighter model. gemini-2.5-flash is closed to new keys.
    RETRY = (429, 500, 503)

    def __init__(self, model=None):
        self.model = model or os.environ.get('GEMINI_MODEL', 'gemini-3.5-flash')
        self.fallback = os.environ.get('GEMINI_FALLBACK_MODEL', 'gemini-3.1-flash-lite')

    def complete(self, system, prompt, image=None):
        prewake()       # the fallback starts waking now, so it is up if Gemini fails
        try:
            return self._ask(system, prompt, image)
        except LLMError as e:
            if not LabModel.configured():
                raise
            try:
                return LabModel().complete(system, prompt, image)
            except LLMError as lab:
                raise LLMError(f'{e}; {lab}') from lab

    def _ask(self, system, prompt, image):
        key = config.secret('GEMINI_API_KEY')
        if not key:
            raise LLMError('gemini: no key configured')
        parts = [{'text': prompt}]
        if image:
            parts.append({'inline_data': {'mime_type': 'image/jpeg', 'data': base64.b64encode(image).decode()}})
        body = {'system_instruction': {'parts': [{'text': system}]},
                'contents': [{'role': 'user', 'parts': parts}],
                'generationConfig': {'responseMimeType': 'application/json', 'temperature': 0.2}}
        daily = False     # a per-day quota won't come back in seconds: go straight to the fallback
        for wait, model in ((0, self.model), (3, self.model), (6, self.fallback)):
            if daily and model == self.model:
                continue
            time.sleep(wait)
            try:
                r = httpx.post(f'https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent',
                               headers={'x-goog-api-key': key}, timeout=90, json=body)
            except httpx.TimeoutException:
                continue
            if r.status_code == 429 and 'PerDay' in r.text:
                daily = True
                continue
            if r.status_code not in self.RETRY:
                break
        else:
            raise LLMError("gemini: today's quota is used up" if daily else 'gemini: busy, try again in a minute')
        if r.status_code != 200:
            raise LLMError(f'gemini: HTTP {r.status_code}')
        try:
            return r.json()['candidates'][0]['content']['parts'][0]['text']
        except (KeyError, IndexError):
            raise LLMError('gemini: empty answer')


class DeepSeek:
    name = 'deepseek'
    reads_images = False

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


class LabModel:
    """An open model on our own Modal endpoint: vLLM's OpenAI-style API, an API key, model "lab".
    It sleeps when idle and wakes on a request in a minute or two; a request that waits past
    Modal's 150 s is redirected and its answer lost, so it is woken with /health first."""
    name = 'modal'
    reads_images = True
    WAKE_S = 240

    @staticmethod
    def configured():
        return bool(config.secret('SIDEPROOF_MODAL_URL') and config.secret('SIDEPROOF_MODAL_KEY'))

    def complete(self, system, prompt, image=None):
        base, key = config.secret('SIDEPROOF_MODAL_URL'), config.secret('SIDEPROOF_MODAL_KEY')
        if not (base and key):
            raise LLMError('modal: no endpoint configured')
        base = base.rstrip('/')
        start = time.time()
        while not _awake(base):
            if time.time() - start > self.WAKE_S:
                raise LLMError('modal: the model did not wake up')
            time.sleep(5)
        content = [{'type': 'text', 'text': prompt}]
        if image:
            content.append({'type': 'image_url', 'image_url': {'url': 'data:image/jpeg;base64,' + base64.b64encode(image).decode()}})
        try:
            r = httpx.post(f'{base}/v1/chat/completions', headers={'Authorization': 'Bearer ' + key}, timeout=140, json={
                'model': 'lab', 'temperature': 0.2, 'max_tokens': 1500, 'response_format': {'type': 'json_object'},
                'messages': [{'role': 'system', 'content': system}, {'role': 'user', 'content': content}]})
        except httpx.HTTPError as e:
            raise LLMError(f'modal: {type(e).__name__}')
        if r.status_code != 200:
            raise LLMError(f'modal: HTTP {r.status_code}')
        return r.json()['choices'][0]['message']['content']


def _awake(base):
    """True once the model answers /health. While it starts, the request is held (up to Modal's
    150 s), which is what wakes it."""
    try:
        return httpx.get(f'{base}/health', timeout=150).status_code == 200
    except httpx.HTTPError:
        return False


_last_wake = 0.0


def prewake():
    """Start waking the fallback model in the background, at most once a minute, so it is up by
    the time Gemini fails. It costs a few minutes of GPU when Gemini answers after all."""
    global _last_wake
    base = config.secret('SIDEPROOF_MODAL_URL')
    if not base or time.time() - _last_wake < 60:
        return
    _last_wake = time.time()
    threading.Thread(target=_awake, args=(base.rstrip('/'),), daemon=True).start()


PROVIDERS = {p.name: p for p in (ClaudeCli, Gemini, DeepSeek, LabModel)}


def available():
    """The providers this server can run: claude-cli only where Claude Code is installed."""
    return [name for name in PROVIDERS if name != 'claude-cli' or shutil.which('claude')]


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
