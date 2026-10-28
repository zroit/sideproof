"""The API flow with YouCam, the face checks and the model replaced by fakes."""
import io
import json

import pytest
from fastapi.testclient import TestClient
from PIL import Image

from sideproof import api, config, face, llm

DEV = {'X-Device': 'test-device-0123456789'}
PHOTO = io.BytesIO()
Image.new('RGB', (600, 800), (180, 150, 130)).save(PHOTO, 'JPEG')


class FakeFace:
    """Stands in for a found face: measure() returns the next queued side values."""
    queue = []

    def measure(self, masks):
        return FakeFace.queue.pop(0)

    def midline(self):
        return [[0.5, 0.0], [0.5, 1.0]]


class FakeAnalysis:
    def __init__(self, concerns):
        self.raw = {c: 50.0 for c in concerns}
        self.ui = {c: 70 for c in concerns}
        self.masks = {}
        self.overall, self.skin_age = 70.0, 30
        self.file_id = 'file-1'


class ScriptedModel:
    """Replies in order; records what it was asked."""
    def __init__(self, replies):
        self.replies, self.prompts = list(replies), []

    def complete(self, system, prompt, image=None):
        self.prompts.append(prompt)
        return json.dumps(self.replies.pop(0))


PLAN = {'product': 'Matte Gel', 'claims': [{'text': 'controls shine', 'concern': 'oiliness'}],
        'concerns': ['oiliness'], 'days': 1, 'scan_every_hours': 2, 'patch_first': False,
        'safe_to_try': True, 'cautions': [], 'summary': 'Check shine on the treated half for a day.'}


@pytest.fixture
def client(tmp_path, monkeypatch):
    monkeypatch.setattr(config, 'DB_PATH', str(tmp_path / 'test.db'))
    monkeypatch.setattr(face, 'check', lambda img: (FakeFace(), [], {'yaw': 0.5}))
    monkeypatch.setattr(api.youcam, 'analyze', lambda jpeg, concerns: FakeAnalysis(concerns))
    monkeypatch.setattr(api.youcam, 'fitzpatrick', lambda file_id: 'V')
    monkeypatch.setattr(api.secrets, 'choice', lambda options: 'img_left')
    with TestClient(api.app) as c:      # runs the app's startup, as uvicorn does
        yield c


def use_model(monkeypatch, replies):
    model = ScriptedModel(replies)
    monkeypatch.setattr(llm, 'get', lambda name: model)
    return model


def send_scan(client, tid, treated, control):
    FakeFace.queue.append({'oiliness': {'img_left': treated, 'img_right': control}})
    r = client.post(f'/api/trials/{tid}/scans', headers=DEV, files={'photo': ('p.jpg', PHOTO.getvalue(), 'image/jpeg')})
    assert r.status_code == 200, r.text
    return r.json()


def test_a_whole_trial(client, monkeypatch):
    model = use_model(monkeypatch, [
        {'thought': 'Check the catalog.', 'tool': 'concern_catalog', 'args': {}},
        {'thought': 'Shine is oiliness.', 'final': PLAN},
    ])
    t = client.post('/api/trials', headers=DEV, data={'product': 'Matte Gel', 'listing': 'Controls shine all day'}).json()
    assert t['status'] == 'baseline' and t['treated_side'] == 'right'
    assert [s['tool'] for s in t['agent_log'] if 'tool' in s] == ['concern_catalog']

    assert client.post(f'/api/trials/{t["id"]}/start', headers=DEV).status_code == 409
    assert send_scan(client, t['id'], 12.2, 9.6)['skin_type'] == 'V'
    t = send_scan(client, t['id'], 12.4, 9.7)
    assert 'your right side' in t['decision']['message'] and t['treated_image_side'] == 'img_left'
    assert client.post(f'/api/trials/{t["id"]}/start', headers=DEV).json()['status'] == 'running'

    model.replies += [
        {'thought': 'Look at the numbers.', 'tool': 'trial_stats', 'args': {}},
        {'thought': 'Invented a number.', 'final': {'action': 'continue', 'message': 'Shine is down 60%.', 'next_scan_in_hours': 2}},
        {'thought': 'Fixed.', 'final': {'action': 'continue', 'message': 'Shine on the treated side is down well past the noise. Scan again in 2 hours.', 'next_scan_in_hours': 2}},
    ]
    assert send_scan(client, t['id'], 5.0, 9.9)['decision']['state'] == 'thinking'
    t = client.get(f'/api/trials/{t["id"]}', headers=DEV).json()     # the agent ran after the reply
    assert t['decision']['action'] == 'continue'
    assert any(s.get('rejected') for s in t['agent_log'])
    assert t['stats']['concerns']['oiliness']['verdict'] == 'better'

    model.replies += [{'thought': 'Write it.', 'final': {
        'headline': 'The gel cut shine on the treated half.',
        'concerns': [{'concern': 'oiliness', 'verdict': 'better', 'text': 'Less shine than the control half.'}],
        'claims': [{'claim': 'controls shine', 'result': 'supported'}], 'next': 'Use it on both sides.'}}]
    t = client.post(f'/api/trials/{t["id"]}/verdict', headers=DEV).json()
    assert t['status'] == 'done' and t['verdict']['claims'][0]['result'] == 'supported'


def test_a_bad_photo_costs_nothing(client, monkeypatch):
    use_model(monkeypatch, [{'thought': 'ok', 'final': PLAN}])
    t = client.post('/api/trials', headers=DEV, data={'product': 'Matte Gel'}).json()
    monkeypatch.setattr(face, 'check', lambda img: (None, ['uneven_light'], {}))
    r = client.post(f'/api/trials/{t["id"]}/scans', headers=DEV, files={'photo': ('p.jpg', PHOTO.getvalue(), 'image/jpeg')}).json()
    assert r['issues'] == ['uneven_light']
    assert client.get(f'/api/trials/{t["id"]}', headers=DEV).json()['scans'] == []


def test_another_device_cannot_read_a_trial(client, monkeypatch):
    use_model(monkeypatch, [{'thought': 'ok', 'final': PLAN}])
    t = client.post('/api/trials', headers=DEV, data={'product': 'Matte Gel'}).json()
    assert client.get(f'/api/trials/{t["id"]}', headers={'X-Device': 'someone-else-0123456789'}).status_code == 404


def test_a_shop_sees_its_trials_and_the_claim_audit(client, monkeypatch):
    monkeypatch.setenv('SIDEPROOF_ADMIN_TOKEN', 'admin-token-for-tests')
    assert client.get('/admin', follow_redirects=False).headers['location'] == '/admin/login'
    client.post('/admin/login', data={'token': 'admin-token-for-tests'})
    r = client.post('/admin/products', data={'shop': 'Glow Lab', 'name': 'Matte Gel', 'listing': 'Controls shine all day.'})
    code = r.url.path.rsplit('/', 1)[1]
    assert client.get(f'/api/products/{code}').json()['name'] == 'Matte Gel'
    assert f'href="/?product={code}"' in client.get(f'/shop/{code}').text

    use_model(monkeypatch, [{'thought': 'ok', 'final': PLAN}])
    t = client.post('/api/trials', headers=DEV, data={'code': code}).json()
    for treated, control in ((12.2, 9.6), (12.4, 9.7)):
        send_scan(client, t['id'], treated, control)
    client.post(f'/api/trials/{t["id"]}/start', headers=DEV)
    llm.get('x').replies += [{'thought': 'ok', 'final': {'action': 'continue', 'message': 'Keep going.', 'next_scan_in_hours': 2}}]
    send_scan(client, t['id'], 5.0, 9.9)

    page = client.get(f'/admin/p/{code}').text
    assert '1 better' in page and 'Type V' in page
    llm.get('x').replies += [
        {'thought': 'Overclaim.', 'final': {'claims': [{'claim': 'Controls shine all day', 'concern': 'oiliness', 'status': 'backed', 'evidence': '1 of 1 trials better'}], 'suggested_wording': 'x'}},
        {'thought': 'Honest.', 'final': {'claims': [{'claim': 'Controls shine all day', 'concern': 'oiliness', 'status': 'not enough trials', 'evidence': '1 trial so far, better'}], 'suggested_wording': 'Early trials show less shine.'}},
    ]
    assert 'not enough trials' in client.post(f'/admin/p/{code}/audit').text


def test_the_view_token_reads_the_dashboard_but_changes_nothing(client, monkeypatch):
    monkeypatch.setenv('SIDEPROOF_ADMIN_TOKEN', 'admin-token-for-tests')
    monkeypatch.setenv('SIDEPROOF_VIEW_TOKEN', 'view-token-for-tests')
    client.post('/admin/login', data={'token': 'admin-token-for-tests'})
    code = client.post('/admin/products', data={'shop': 'Glow Lab', 'name': 'Matte Gel', 'listing': 'x'}).url.path.rsplit('/', 1)[1]
    client.cookies.clear()

    assert client.get('/dashboard', follow_redirects=False).headers['location'] == '/dashboard/login'
    assert client.post('/dashboard/login', data={'token': 'admin-token-for-tests'}).status_code == 403
    client.post('/dashboard/login', data={'token': 'view-token-for-tests'})
    home = client.get('/dashboard').text
    assert 'Matte Gel' in home and f'href="/dashboard/p/{code}"' in home
    assert '<form' not in home and '<form' not in client.get(f'/dashboard/p/{code}').text
    for path, data in (('/admin', None), ('/admin/settings', {'llm_provider': 'gemini', 'daily_unit_cap': 0, 'fitzpatrick': 'off'}),
                       ('/admin/products', {'shop': 'a', 'name': 'b', 'listing': 'c'}), (f'/admin/p/{code}/audit', {})):
        r = client.post(path, data=data, follow_redirects=False) if data is not None else client.get(path, follow_redirects=False)
        assert r.headers['location'] == '/admin/login'


def test_a_scan_answer_carries_the_overlays_but_the_trial_keeps_numbers_only(client, monkeypatch):
    import numpy as np
    use_model(monkeypatch, [{'thought': 'ok', 'final': PLAN}])
    t = client.post('/api/trials', headers=DEV, data={'product': 'Matte Gel'}).json()
    monkeypatch.setattr(api.youcam, 'analyze', lambda jpeg, concerns: type('A', (FakeAnalysis,), {})(concerns))
    real = FakeAnalysis.__init__

    def with_mask(self, concerns):
        real(self, concerns)
        self.masks = {c: np.full((40, 30), 0.5, np.float32) for c in concerns}
    monkeypatch.setattr(FakeAnalysis, '__init__', with_mask)
    r = send_scan(client, t['id'], 12.2, 9.6)
    assert r['media']['midline'] == [[0.5, 0.0], [0.5, 1.0]]
    assert all(v.startswith('data:image/png;base64,') for v in r['media']['overlays'].values())
    assert 'media' not in client.get(f'/api/trials/{t["id"]}', headers=DEV).json()


def test_the_promise_simulates_only_claimed_concerns_and_counts_units(client, monkeypatch):
    use_model(monkeypatch, [{'thought': 'ok', 'final': PLAN}])
    t = client.post('/api/trials', headers=DEV, data={'product': 'Matte Gel'}).json()
    seen = {}

    def simulate(jpeg, settings):
        seen.update(settings)
        return PHOTO.getvalue()
    monkeypatch.setattr(api.youcam, 'simulate', simulate)
    r = client.post(f'/api/trials/{t["id"]}/promise', headers=DEV, files={'photo': ('p.jpg', PHOTO.getvalue(), 'image/jpeg')}).json()
    assert r['image'].startswith('data:image/jpeg;base64,')
    assert set(seen) == {api.SIMULATE[c] for c in r['concerns']} and all(v == api.PROMISE_STRENGTH for v in seen.values())
