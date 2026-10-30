import httpx
import pytest

from sideproof import llm


class Answer:
    def __init__(self, status, text='{"ok": true}'):
        self.status_code = status
        self.text = text

    def json(self):
        return {'candidates': [{'content': {'parts': [{'text': self.text}]}}]}


def gemini_with(monkeypatch, answers):
    calls = []

    def post(url, **_):
        calls.append(url.split('/models/')[1].split(':')[0])
        a = answers.pop(0)
        if isinstance(a, Exception):
            raise a
        return a

    monkeypatch.setenv('GEMINI_API_KEY', 'test-key')
    monkeypatch.setattr(llm.httpx, 'post', post)
    monkeypatch.setattr(llm.time, 'sleep', lambda s: None)
    return llm.Gemini(model='main'), calls


def test_gemini_retries_busy_then_falls_back(monkeypatch):
    g, calls = gemini_with(monkeypatch, [Answer(503), httpx.ReadTimeout('slow'), Answer(200)])
    g.fallback = 'lite'
    assert g.complete('sys', 'hi') == '{"ok": true}'
    assert calls == ['main', 'main', 'lite']


def test_gemini_gives_up_when_always_busy(monkeypatch):
    g, _ = gemini_with(monkeypatch, [Answer(429), Answer(503), Answer(503)])
    with pytest.raises(llm.LLMError, match='busy'):
        g.complete('sys', 'hi')


def test_gemini_does_not_retry_a_bad_request(monkeypatch):
    g, calls = gemini_with(monkeypatch, [Answer(400)])
    with pytest.raises(llm.LLMError, match='HTTP 400'):
        g.complete('sys', 'hi')
    assert calls == ['main']


def test_gemini_skips_to_the_fallback_when_the_daily_quota_is_gone(monkeypatch):
    g, calls = gemini_with(monkeypatch, [Answer(429, 'GenerateRequestsPerDayPerProjectPerModel-FreeTier'), Answer(200)])
    g.fallback = 'lite'
    assert g.complete('sys', 'hi') == '{"ok": true}'
    assert calls == ['main', 'lite']


def test_gemini_says_when_the_daily_quota_is_gone_everywhere(monkeypatch):
    daily = 'GenerateRequestsPerDayPerProjectPerModel-FreeTier'
    g, _ = gemini_with(monkeypatch, [Answer(429, daily), Answer(429, daily)])
    with pytest.raises(llm.LLMError, match="quota is used up"):
        g.complete('sys', 'hi')


def test_claude_cli_without_claude_code_is_an_agent_error_not_a_crash(monkeypatch):
    def missing(*_, **__):
        raise FileNotFoundError('claude')
    monkeypatch.setattr(llm.subprocess, 'run', missing)
    with pytest.raises(llm.LLMError, match='not installed'):
        llm.ClaudeCli().complete('sys', 'hi')
    monkeypatch.setattr(llm.shutil, 'which', lambda _: None)
    assert 'claude-cli' not in llm.available()


class LabAnswer:
    status_code = 200

    def json(self):
        return {'choices': [{'message': {'content': '{"from": "lab"}'}}]}


def test_gemini_falls_back_to_the_lab_model_when_every_model_is_busy(monkeypatch):
    sent = []

    def post(url, **kw):
        if '/models/' in url:
            return Answer(503)
        sent.append((url, kw['headers']['Authorization'], kw['json']['messages'][1]['content'][-1]['type']))
        return LabAnswer()

    monkeypatch.setenv('GEMINI_API_KEY', 'test-key')
    monkeypatch.setenv('SIDEPROOF_MODAL_URL', 'https://lab.example/')
    monkeypatch.setenv('SIDEPROOF_MODAL_KEY', 'lab-key')
    monkeypatch.setattr(llm.httpx, 'post', post)
    monkeypatch.setattr(llm.httpx, 'get', lambda url, **_: type('H', (), {'status_code': 200})())
    monkeypatch.setattr(llm.time, 'sleep', lambda s: None)
    assert llm.Gemini(model='main').complete('sys', 'hi', image=b'jpeg') == '{"from": "lab"}'
    assert sent == [('https://lab.example/v1/chat/completions', 'Bearer lab-key', 'image_url')]


def test_without_a_lab_model_gemini_fails_as_before(monkeypatch):
    monkeypatch.delenv('SIDEPROOF_MODAL_URL', raising=False)
    g, _ = gemini_with(monkeypatch, [Answer(503), Answer(503), Answer(503)])
    with pytest.raises(llm.LLMError, match='busy'):
        g.complete('sys', 'hi')


def test_the_lab_model_gives_up_when_it_does_not_wake(monkeypatch):
    monkeypatch.setenv('SIDEPROOF_MODAL_URL', 'https://lab.example')
    monkeypatch.setenv('SIDEPROOF_MODAL_KEY', 'lab-key')
    monkeypatch.setattr(llm.httpx, 'get', lambda url, **_: type('H', (), {'status_code': 503})())
    monkeypatch.setattr(llm.time, 'sleep', lambda s: None)
    monkeypatch.setattr(llm.LabModel, 'WAKE_S', -1)
    with pytest.raises(llm.LLMError, match='did not wake'):
        llm.LabModel().complete('sys', 'hi')


def test_prewake_does_nothing_without_an_endpoint(monkeypatch):
    monkeypatch.delenv('SIDEPROOF_MODAL_URL', raising=False)
    started = []
    monkeypatch.setattr(llm.threading, 'Thread', lambda **kw: started.append(kw))
    llm._last_wake = 0.0
    llm.prewake()
    assert started == []
