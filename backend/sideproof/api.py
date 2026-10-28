"""SideProof API: start a trial, add scans, read the result. Three calls are enough for a shop
to put a split-face trial on its own page."""
import html
import json
import os
import secrets
import time
from contextlib import asynccontextmanager

from fastapi import BackgroundTasks, Depends, FastAPI, File, Form, Header, HTTPException, UploadFile
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import HTMLResponse
from fastapi.staticfiles import StaticFiles

from . import admin, agent, config, db, demo, face, llm, trial
from .youcam import YouCam, YouCamError, unit_cost

@asynccontextmanager
async def lifespan(_):
    con = db.connect()
    demo.load(con)
    con.close()
    yield


app = FastAPI(title='SideProof API', version='0.1.0', lifespan=lifespan, description=(
    'Split-face product trials on YouCam Skin AI. The product goes on one half of the face; '
    'the other half is the control. Photos are measured and dropped; only numbers are kept.'))
app.add_middleware(CORSMiddleware, allow_origins=['*'], allow_methods=['*'], allow_headers=['*'])
youcam = YouCam()

PERSON_SIDE = {'img_left': 'right', 'img_right': 'left'}    # unmirrored photo


def get_db():
    con = db.connect()
    try:
        yield con
    finally:
        con.close()


def device(x_device: str = Header(..., min_length=16, max_length=64)):
    return x_device


def own_trial(con, trial_id, dev):
    t = db.trial_row(con, trial_id)
    if not t or t['device'] != dev:
        raise HTTPException(404, 'no such trial')
    return t


def state(con, t):
    scans = db.scans_of(con, t['id'])
    stats = trial.summary(scans, t['plan']['concerns'], t['treated'])
    hours_in = (time.time() - t['started_at']) / 3600 if t['started_at'] else 0
    return scans, stats, round(hours_in, 1)


def view(con, t):
    scans, stats, hours_in = state(con, t)
    return {**{k: t[k] for k in ('id', 'product', 'code', 'plan', 'status', 'decision', 'verdict', 'skin_type', 'created_at', 'started_at')},
            'treated_side': PERSON_SIDE[t['treated']], 'treated_image_side': t['treated'], 'hours_in': hours_in, 'stats': stats,
            'scans': [{k: s[k] for k in ('id', 'phase', 'at', 'checks')} for s in scans],
            'agent_log': db.log_of(con, t['id'])}


def provider(con):
    return llm.get(db.setting(con, 'llm_provider'))


@app.get('/api/health')
def health():
    return {'ok': True}


@app.get('/api/catalog')
def catalog():
    return {k: {'shows': v[0], 'speed': v[1]} for k, v in trial.CATALOG.items()}


@app.post('/api/trials')
def create_trial(product: str = Form('', max_length=120), listing: str = Form('', max_length=4000),
                 code: str = Form('', max_length=32), label: UploadFile | None = File(None),
                 dev=Depends(device), con=Depends(get_db)):
    """Start a trial. The agent reads the label photo or listing and plans what to measure."""
    if code:
        p = con.execute('select * from products where code = ?', (code,)).fetchone()
        if not p:
            raise HTTPException(404, 'unknown product code')
        product, listing = p['name'], p['listing']
    if not product.strip():
        raise HTTPException(422, 'product name needed')
    image = None
    if label:
        if not provider(con).reads_images:
            raise HTTPException(422, "This agent model can't read photos. Type the claims instead.")
        image = face.jpeg(face.prepare(label.file.read()))
    tid = secrets.token_urlsafe(9)
    budget = {'units_left_today': int(db.setting(con, 'daily_unit_cap')) - db.units_today(con), 'cost_per_scan': unit_cost(4)}
    log = lambda job, step: db.log_step(con, tid, job, step)
    try:
        plan = agent.plan(provider(con), product.strip(), listing.strip(), image, budget, log)
    except (agent.AgentError, llm.LLMError) as e:
        raise HTTPException(502, f'the agent could not plan this trial: {e}')
    con.execute('insert into trials (id, device, product, code, treated, plan, status, created_at) values (?, ?, ?, ?, ?, ?, ?, ?)',
                (tid, dev, product.strip(), code or None, secrets.choice(['img_left', 'img_right']), json.dumps(plan), 'baseline', time.time()))
    con.commit()
    return view(con, db.trial_row(con, tid))


@app.get('/api/trials')
def my_trials(dev=Depends(device), con=Depends(get_db)):
    rows = con.execute('select id, product, status, created_at from trials where device = ? order by created_at desc', (dev,)).fetchall()
    return [dict(r) for r in rows]


@app.get('/api/trials/{trial_id}')
def get_trial(trial_id: str, dev=Depends(device), con=Depends(get_db)):
    return view(con, own_trial(con, trial_id, dev))


@app.post('/api/trials/{trial_id}/start')
def start(trial_id: str, dev=Depends(device), con=Depends(get_db)):
    """The person has put the product on the treated half."""
    t = own_trial(con, trial_id, dev)
    _, stats, _ = state(con, t)
    if t['status'] != 'baseline' or 'start' not in trial.allowed_actions('baseline', stats, 0, 0, 0):
        raise HTTPException(409, 'take two baseline scans first')
    con.execute("update trials set status = 'running', started_at = ?, decision = null where id = ?", (time.time(), trial_id))
    con.commit()
    return view(con, db.trial_row(con, trial_id))


@app.post('/api/trials/{trial_id}/scans')
def add_scan(trial_id: str, background: BackgroundTasks, photo: UploadFile = File(...),
             dev=Depends(device), con=Depends(get_db)):
    """Check the photo, measure both halves with YouCam, then let the agent pick the next step."""
    t = own_trial(con, trial_id, dev)
    if t['status'] not in ('baseline', 'running'):
        raise HTTPException(409, f'trial is {t["status"]}')
    try:
        img = face.prepare(photo.file.read())
    except ValueError as e:
        raise HTTPException(422, str(e))
    found, issues, checks = face.check(img)
    if issues:
        return {'retake': [face.ISSUES[i] for i in issues], 'issues': issues, 'checks': checks}

    concerns = t['plan']['concerns']
    cost = unit_cost(len(concerns))
    if db.units_today(con) + cost > int(db.setting(con, 'daily_unit_cap')):
        raise HTTPException(429, "today's scan budget is used up; try again tomorrow or open the demo trial")
    try:
        result = youcam.analyze(face.jpeg(img), concerns)
    except YouCamError as e:
        raise HTTPException(502, f'YouCam: {e}')
    sides = found.measure(result.masks)
    media = {'overlays': face.overlays(result.masks), 'midline': found.midline()}    # for this answer only
    del img, result.masks
    now = time.time()
    if not t['skin_type'] and db.setting(con, 'fitzpatrick') == 'on' and db.units_today(con) + cost + 10 <= int(db.setting(con, 'daily_unit_cap')):
        try:    # once per trial, on the photo YouCam already has: lets a brand see results per skin type
            skin_type = youcam.fitzpatrick(result.file_id)
            con.execute('update trials set skin_type = ? where id = ?', (skin_type, trial_id))
            con.execute('insert into units (at, units, what) values (?, ?, ?)', (now, 10, 'fitzpatrick'))
        except YouCamError:
            pass
    phase = 'baseline' if t['status'] == 'baseline' else 'trial'
    con.execute('insert into scans (trial_id, phase, at, checks, sides, scores, units) values (?, ?, ?, ?, ?, ?, ?)',
                (trial_id, phase, now, json.dumps(checks), json.dumps(sides),
                 json.dumps({'raw': result.raw, 'ui': result.ui, 'overall': result.overall}), cost))
    con.execute('insert into units (at, units, what) values (?, ?, ?)', (now, cost, 'scan'))
    con.commit()

    _, stats, hours_in = state(con, t)
    trial_scans = sum(1 for s in db.scans_of(con, trial_id) if s['phase'] == 'trial')
    allowed = trial.allowed_actions('baseline' if phase == 'baseline' else 'running', stats, hours_in, t['plan']['days'], trial_scans)
    if stats['harm']:
        con.execute("update trials set status = 'stopped' where id = ?", (trial_id,))
    con.execute("update trials set decision = ? where id = ?", (json.dumps({'state': 'thinking', 'allowed': allowed}), trial_id))
    con.commit()
    if phase == 'trial':
        background.add_task(decide, trial_id, allowed)
    else:
        n = min(s['baseline_scans'] for s in stats['concerns'].values())
        msg = ('Baseline 1 of 2 saved. Take one more in a few minutes, same place, same light.' if n < 2 else
               f'Baseline done. Now put the product only on the shaded half of your face (your {PERSON_SIDE[t["treated"]]} side), then tap Start.')
        con.execute('update trials set decision = ? where id = ?', (json.dumps({'state': 'done', 'action': allowed[0], 'message': msg, 'allowed': allowed}), trial_id))
        con.commit()
    return {**view(con, db.trial_row(con, trial_id)), 'media': media}


# Trial concern -> AI Skin Simulation setting. Dryness has no simulation.
SIMULATE = {'oiliness': 'oiliness', 'radiance': 'radiance', 'redness': 'redness', 'acne': 'acne', 'pore': 'pores',
            'texture': 'texture', 'age_spot': 'spots', 'wrinkle': 'wrinkle', 'dark_circle_v2': 'dark_circle', 'eye_bag': 'eye_bags'}
PROMISE_STRENGTH = 0.7


@app.post('/api/trials/{trial_id}/promise')
def promise(trial_id: str, photo: UploadFile = File(...), dev=Depends(device), con=Depends(get_db)):
    """What the claims promise: YouCam AI Skin Simulation on the person's baseline photo, for the
    concerns the product claims to improve. The app shows it on the treated half; nothing is kept."""
    t = own_trial(con, trial_id, dev)
    claimed = [c['concern'] for c in t['plan'].get('claims', []) if c.get('concern')] or t['plan']['concerns']
    settings = {SIMULATE[c]: PROMISE_STRENGTH for c in dict.fromkeys(claimed) if c in SIMULATE}
    if not settings:
        raise HTTPException(422, "YouCam can't simulate what this product claims")
    cost = 4 if len(settings) <= 4 else 6
    if db.units_today(con) + cost > int(db.setting(con, 'daily_unit_cap')):
        raise HTTPException(429, "today's scan budget is used up; try again tomorrow")
    try:
        img = face.prepare(photo.file.read())
    except ValueError as e:
        raise HTTPException(422, str(e))
    try:
        out = youcam.simulate(face.jpeg(img), settings)
    except YouCamError as e:
        raise HTTPException(502, f'YouCam: {e}')
    con.execute('insert into units (at, units, what) values (?, ?, ?)', (time.time(), cost, 'simulation'))
    con.commit()
    return {'image': face.data_url(out, 1080), 'concerns': [c for c in dict.fromkeys(claimed) if c in SIMULATE]}


def decide(trial_id, allowed):
    con = db.connect()
    try:
        t = db.trial_row(con, trial_id)
        _, stats, hours_in = state(con, t)
        s = {'status': t['status'], 'hours_in': hours_in, 'plan': t['plan'], 'stats': stats}
        try:
            d = agent.next_step(provider(con), s, allowed, lambda job, step: db.log_step(con, trial_id, job, step))
            d = {'state': 'done', **d, 'allowed': allowed}
        except (agent.AgentError, llm.LLMError) as e:
            d = {'state': 'failed', 'error': str(e), 'action': allowed[0], 'allowed': allowed}
        con.execute('update trials set decision = ? where id = ?', (json.dumps(d), trial_id))
        if d.get('action') == 'conclude':
            con.execute("update trials set status = 'concluding' where id = ? and status = 'running'", (trial_id,))
        con.commit()
    finally:
        con.close()


@app.get('/api/products/{code}')
def product(code: str, con=Depends(get_db)):
    """What a shop's trial link opens with."""
    p = con.execute('select code, shop, name from products where code = ?', (code,)).fetchone()
    if not p:
        raise HTTPException(404, 'unknown product code')
    return dict(p)


@app.get('/shop/{code}', include_in_schema=False)
def example_shop(code: str, con=Depends(get_db)):
    """A made-up shop's product page with the trial link on it, to show where SideProof sits."""
    p = con.execute('select * from products where code = ?', (code,)).fetchone()
    if not p:
        raise HTTPException(404, 'unknown product code')
    page = (config.HERE / 'static' / 'shop.html').read_text()
    for key, value in (('name', p['name']), ('shop', p['shop'] or ''), ('listing', p['listing'] or ''), ('link', f'/?product={code}')):
        page = page.replace('{' + key + '}', html.escape(value))
    return HTMLResponse(page)


@app.get('/api/demo')
def demo_trial(con=Depends(get_db)):
    """A finished trial to look around in. Costs no units."""
    t = con.execute("select id from trials where device = 'demo' order by created_at desc").fetchone()
    if not t:
        raise HTTPException(404, 'no demo trial loaded')
    return view(con, db.trial_row(con, t['id']))


@app.post('/api/trials/{trial_id}/verdict')
def write_verdict(trial_id: str, dev=Depends(device), con=Depends(get_db)):
    """End the trial: the agent writes the verdict from the measured numbers."""
    t = own_trial(con, trial_id, dev)
    _, stats, hours_in = state(con, t)
    if not any(s.get('state') == 'measured' for s in stats['concerns'].values()):
        raise HTTPException(409, 'no scans after the product went on yet')
    s = {'status': t['status'], 'hours_in': hours_in, 'plan': t['plan'], 'stats': stats}
    try:
        v = agent.verdict(provider(con), s, lambda job, step: db.log_step(con, trial_id, job, step))
    except (agent.AgentError, llm.LLMError) as e:
        raise HTTPException(502, f'the agent could not write the verdict: {e}')
    con.execute("update trials set verdict = ?, status = case when status = 'stopped' then status else 'done' end where id = ?",
                (json.dumps(v), trial_id))
    con.commit()
    return view(con, db.trial_row(con, trial_id))


app.include_router(admin.router)
app.include_router(admin.view)
WEB_DIR = os.environ.get('SIDEPROOF_WEB_DIR', '')
if WEB_DIR and os.path.isdir(WEB_DIR):     # the Flutter web build, served from the same host
    app.mount('/', StaticFiles(directory=WEB_DIR, html=True), name='web')
