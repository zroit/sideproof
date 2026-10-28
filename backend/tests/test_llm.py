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
