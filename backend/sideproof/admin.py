"""Owner and shop dashboard: settings, unit budget, products with trial links, what the trials
measured per product and per skin type, and the claim audit. /admin is served only on the admin
host; /dashboard is the same pages read-only, on any host, for a view token (judges, a shop)."""
import html
import json
import os
import secrets
import time

from fastapi import APIRouter, Depends, Form, HTTPException, Request
from fastapi.responses import HTMLResponse, RedirectResponse

from . import agent, config, db, llm, trial
from .youcam import YouCamError

router = APIRouter(prefix='/admin', include_in_schema=False)
view = APIRouter(prefix='/dashboard', include_in_schema=False)
COOKIE = 'sp_admin'
VIEW_COOKIE = 'sp_view'
PUBLIC_URL = os.environ.get('SIDEPROOF_PUBLIC_URL', '')
ADMIN_HOST = os.environ.get('SIDEPROOF_ADMIN_HOST', '')


def get_db():
    con = db.connect()
    try:
        yield con
    finally:
        con.close()


def gate(request: Request):
    if ADMIN_HOST and request.url.hostname != ADMIN_HOST:
        raise HTTPException(404)


def signed_in(request, cookie, secret_name, base):
    token = config.secret(secret_name)
    given = request.cookies.get(cookie, '')
    if not token or not secrets.compare_digest(given, token):
        raise HTTPException(303, headers={'Location': base + '/login'})


def authed(request: Request):
    gate(request)
    signed_in(request, COOKIE, 'SIDEPROOF_ADMIN_TOKEN', '/admin')


def viewer(request: Request):
    signed_in(request, VIEW_COOKIE, 'SIDEPROOF_VIEW_TOKEN', '/dashboard')


def outcomes(con, code):
    """Every trial of a product, reduced to verdict counts per concern and per skin type."""
    rows = con.execute('select * from trials where code = ?', (code,)).fetchall()
    out = {'trials': len(rows), 'finished': 0, 'stopped': 0, 'concerns': {}, 'by_skin_type': {}}
    for r in rows:
        t = db.trial_row(con, r['id'])
        out['finished'] += t['status'] == 'done'
        out['stopped'] += t['status'] == 'stopped'
        stats = trial.summary(db.scans_of(con, t['id']), t['plan']['concerns'], t['treated'])
        for c, s in stats['concerns'].items():
            if s.get('state') != 'measured':
                continue
            for bucket in (out['concerns'], out['by_skin_type'].setdefault(t['skin_type'] or 'unknown', {})):
                counts = bucket.setdefault(c, {'better': 0, 'unclear': 0, 'worse': 0})
                counts[s['verdict']] += 1
    return out


CSS = '''
:root{--bg:#f2f4f3;--card:#fff;--ink:#15232a;--mute:#5d6b70;--line:#dde3e2;--good:#1f8a5b;--bad:#c2412d;--mid:#c5cdcb;--accent:#2f5bea}
@media (prefers-color-scheme:dark){:root{--bg:#0f171b;--card:#172228;--ink:#e8eeec;--mute:#a5b2b5;--line:#2a383e;--mid:#3b4a4f;--accent:#8aa4ff}}
*{box-sizing:border-box}body{margin:0;background:var(--bg);color:var(--ink);font:15px/1.5 system-ui,sans-serif}
main{max-width:980px;margin:0 auto;padding:24px 16px 64px}h1{font-size:22px;margin:0 0 4px}h2{font-size:16px;margin:28px 0 10px}
.mute{color:var(--mute)}.card{background:var(--card);border:1px solid var(--line);border-radius:12px;padding:16px;margin:12px 0}
.row{display:flex;gap:12px;flex-wrap:wrap}.row>.card{flex:1;min-width:200px;margin:0}.big{font-size:26px;font-weight:650}
table{width:100%;border-collapse:collapse}td,th{text-align:left;padding:7px 6px;border-bottom:1px solid var(--line);vertical-align:top}
th{font-size:12px;text-transform:uppercase;letter-spacing:.04em;color:var(--mute);font-weight:600}
input,select,textarea{font:inherit;padding:7px 9px;border:1px solid var(--line);border-radius:8px;background:var(--bg);color:var(--ink);width:100%}
button{font:inherit;padding:8px 14px;border:0;border-radius:8px;background:var(--accent);color:#fff;cursor:pointer}
form.inline{display:flex;gap:8px;align-items:end;flex-wrap:wrap}form.inline label{flex:1;min-width:140px}label{font-size:13px;color:var(--mute)}
.bar{display:flex;height:12px;border-radius:6px;overflow:hidden;background:var(--line);min-width:160px}.bar span{display:block}
.g{background:var(--good)}.m{background:var(--mid)}.b{background:var(--bad)}code{font-size:13px;word-break:break-all}
.pill{display:inline-block;padding:1px 8px;border-radius:99px;font-size:12px;border:1px solid var(--line)}
.backed{color:var(--good);border-color:var(--good)}.not.backed,.notbacked{color:var(--bad);border-color:var(--bad)}
a{color:var(--accent)}h1{display:flex;align-items:center;gap:10px}.mark{flex:none}
'''


def page(title, body):
    return HTMLResponse(f'<!doctype html><html lang="en"><head><meta charset="utf-8">'
                        f'<meta name="viewport" content="width=device-width,initial-scale=1"><title>{html.escape(title)}</title>'
                        f'<style>{CSS}</style></head><body><main>{body}</main></body></html>')


def bar(counts):
    total = sum(counts.values()) or 1
    return ('<div class="bar">' + ''.join(f'<span class="{cls}" style="width:{counts[k] / total * 100:.0f}%"></span>'
                                          for k, cls in (('better', 'g'), ('unclear', 'm'), ('worse', 'b'))) + '</div>')


def counts_cell(counts):
    return f'{bar(counts)}<div class="mute">{counts["better"]} better · {counts["unclear"]} unclear · {counts["worse"]} worse</div>'


def login_form(title, base, label):
    return page(title, f'<h1>{title}</h1><form class="card" method="post" action="{base}/login">'
                f'<label>{label}<input name="token" type="password" autofocus></label><p><button>Sign in</button></p></form>')


def sign_in(request, token, cookie, secret_name, base):
    real = config.secret(secret_name)
    if not real or not secrets.compare_digest(token, real):
        raise HTTPException(403, 'wrong token')
    r = RedirectResponse(base, 303)
    r.set_cookie(cookie, token, httponly=True, samesite='strict', secure=request.url.scheme == 'https', max_age=30 * 86400)
    return r


@router.get('/login')
def admin_login_form(request: Request):
    gate(request)
    return login_form('SideProof admin', '/admin', 'Admin token')


@router.post('/login')
def admin_login(request: Request, token: str = Form(...)):
    gate(request)
    return sign_in(request, token, COOKIE, 'SIDEPROOF_ADMIN_TOKEN', '/admin')


@view.get('/login')
def view_login_form():
    return login_form('SideProof dashboard', '/dashboard', 'Access token')


@view.post('/login')
def view_login(request: Request, token: str = Form(...)):
    return sign_in(request, token, VIEW_COOKIE, 'SIDEPROOF_VIEW_TOKEN', '/dashboard')


@router.get('', dependencies=[Depends(authed)])
def admin_home(con=Depends(get_db)):
    return home(con, '/admin', read_only=False)


@view.get('', dependencies=[Depends(viewer)])
def view_home(con=Depends(get_db)):
    return home(con, '/dashboard', read_only=True)


def home(con, base, read_only):
    from .api import youcam
    try:
        balance = f'{youcam.credit():.0f}'
    except YouCamError as e:
        balance = f'<span class="mute">{html.escape(str(e))}</span>'
    used, cap = db.units_today(con), int(db.setting(con, 'daily_unit_cap'))
    prov = db.setting(con, 'llm_provider')
    n_trials = con.execute("select count(*) from trials where device != 'demo'").fetchone()[0]
    products = con.execute('select * from products order by created_at desc').fetchall()
    recent = con.execute("select t.*, (select count(*) from scans s where s.trial_id = t.id) n from trials t "
                         "where device != 'demo' order by created_at desc limit 20").fetchall()

    prow = ''.join(f'<tr><td><a href="{base}/p/{p["code"]}">{html.escape(p["name"])}</a><div class="mute">{html.escape(p["shop"] or "")}</div></td>'
                   f'<td><code>{p["code"]}</code></td><td>{outcomes(con, p["code"])["trials"]}</td></tr>' for p in products)
    trow = ''.join(f'<tr><td><code>{r["id"]}</code></td><td>{html.escape(r["product"])}</td><td>{r["status"]}</td>'
                   f'<td>{r["skin_type"] or "-"}</td><td>{r["n"]}</td><td class="mute">{time.strftime("%b %d %H:%M", time.localtime(r["created_at"]))}</td></tr>'
                   for r in recent)
    options = ''.join(f'<option {"selected" if name == prov else ""}>{name}</option>' for name in llm.PROVIDERS)
    fitz = db.setting(con, 'fitzpatrick')
    settings = (f'<div class="card">Agent model <b>{prov}</b> · daily unit cap <b>{cap}</b> · skin type (Fitzpatrick) <b>{fitz}</b></div>'
                if read_only else f'''<form class="card inline" method="post" action="/admin/settings">
<label>Agent model<select name="llm_provider">{options}</select></label>
<label>Daily unit cap<input name="daily_unit_cap" type="number" min="0" value="{cap}"></label>
<label>Skin type (Fitzpatrick, 10 units per trial)<select name="fitzpatrick"><option {"selected" if fitz == "on" else ""}>on</option><option {"selected" if fitz == "off" else ""}>off</option></select></label>
<button>Save</button></form>''')
    add_product = '' if read_only else '''<form class="inline" method="post" action="/admin/products" style="margin-top:14px">
<label>Shop<input name="shop" required></label><label>Product<input name="name" required></label>
<label style="flex-basis:100%">Listing text (the claims as the shop sells it)<textarea name="listing" rows="3" required></textarea></label><button>Add product</button></form>'''
    note = ' Read-only view.' if read_only else ''
    body = f'''<h1><svg class="mark" viewBox="0 0 32 32" width="24" height="24" aria-hidden="true"><path d="M15 3A13 13 0 0 0 15 29Z" fill="#2F5BEA"/><path d="M18.4 4.4A11.6 11.6 0 0 1 18.4 27.6Z" fill="none" stroke="currentColor" stroke-width="2.8" stroke-linejoin="round"/></svg>SideProof</h1><p class="mute">Split-face product trials on YouCam Skin AI. Numbers only: no photo is kept.{note}</p>
<div class="row"><div class="card"><div class="mute">YouCam units left</div><div class="big">{balance}</div></div>
<div class="card"><div class="mute">Used in the last 24 h</div><div class="big">{used} / {cap}</div></div>
<div class="card"><div class="mute">Trials</div><div class="big">{n_trials}</div></div></div>
<h2>Settings</h2>{settings}
<h2>Products</h2><div class="card"><table><tr><th>Product</th><th>Trial code</th><th>Trials</th></tr>{prow or '<tr><td colspan=3 class="mute">None yet.</td></tr>'}</table>
{add_product}</div>
<h2>Recent trials</h2><div class="card"><table><tr><th>Trial</th><th>Product</th><th>Status</th><th>Skin type</th><th>Scans</th><th>Started</th></tr>{trow or '<tr><td colspan=6 class="mute">None yet.</td></tr>'}</table></div>'''
    return page('SideProof dashboard' if read_only else 'SideProof admin', body)


@router.post('/settings', dependencies=[Depends(authed)])
def save_settings(llm_provider: str = Form(...), daily_unit_cap: int = Form(...), fitzpatrick: str = Form(...), con=Depends(get_db)):
    if llm_provider not in llm.PROVIDERS or fitzpatrick not in ('on', 'off') or daily_unit_cap < 0:
        raise HTTPException(422, 'bad setting')
    for k, v in (('llm_provider', llm_provider), ('daily_unit_cap', str(daily_unit_cap)), ('fitzpatrick', fitzpatrick)):
        con.execute('insert into settings (key, value) values (?, ?) on conflict(key) do update set value = excluded.value', (k, v))
    con.commit()
    return RedirectResponse('/admin', 303)


@router.post('/products', dependencies=[Depends(authed)])
def add_product(shop: str = Form(..., max_length=80), name: str = Form(..., max_length=120),
                listing: str = Form(..., max_length=4000), con=Depends(get_db)):
    code = secrets.token_hex(3).upper()
    con.execute('insert into products (code, shop, name, listing, created_at) values (?, ?, ?, ?, ?)',
                (code, shop.strip(), name.strip(), listing.strip(), time.time()))
    con.commit()
    return RedirectResponse(f'/admin/p/{code}', 303)


@router.get('/p/{code}', dependencies=[Depends(authed)])
def admin_product(code: str, con=Depends(get_db)):
    return product_page(con, code, '/admin', read_only=False)


@view.get('/p/{code}', dependencies=[Depends(viewer)])
def view_product(code: str, con=Depends(get_db)):
    return product_page(con, code, '/dashboard', read_only=True)


def product_page(con, code, base, read_only):
    p = con.execute('select * from products where code = ?', (code,)).fetchone()
    if not p:
        raise HTTPException(404)
    o = outcomes(con, code)
    link = f'{PUBLIC_URL}/?product={code}'
    rows = ''.join(f'<tr><td>{trial.CATALOG[c][0]}</td><td>{counts_cell(k)}</td></tr>' for c, k in o['concerns'].items())
    types = sorted(o['by_skin_type'])
    type_rows = ''.join(f'<tr><td>{trial.CATALOG[c][0]}</td>' + ''.join(
        f'<td>{counts_cell(o["by_skin_type"][t][c]) if c in o["by_skin_type"][t] else "-"}</td>' for t in types) + '</tr>'
        for c in o['concerns'])
    audit = json.loads(p['audit']) if p['audit'] else None
    audit_html = ''
    if audit:
        audit_html = ''.join(f'<tr><td>{html.escape(a.get("claim", ""))}</td><td><span class="pill {a.get("status", "").replace(" ", "")}">{html.escape(a.get("status", ""))}</span></td>'
                             f'<td class="mute">{html.escape(a.get("evidence", ""))}</td></tr>' for a in audit.get('claims', []))
        audit_html = (f'<table><tr><th>Claim</th><th>Status</th><th>Evidence</th></tr>{audit_html}</table>'
                      f'<p><b>Wording the evidence supports:</b> {html.escape(audit.get("suggested_wording", ""))}</p>')
    if read_only:
        audit_button = '' if audit else '<p class="mute">Not run yet.</p>'
    else:
        audit_button = f'<form method="post" action="/admin/p/{code}/audit"><button>{"Run again" if audit else "Run claim audit"}</button></form>'
    body = f'''<p><a href="{base}">← All products</a></p><h1>{html.escape(p["name"])}</h1><p class="mute">{html.escape(p["shop"] or "")} · code <code>{code}</code></p>
<div class="card"><div class="mute">Trial link for the sample pack or the product page</div><code>{html.escape(link)}</code>
<div class="mute" style="margin-top:8px">Embed</div><code>{html.escape(f'<iframe src="{link}" width="420" height="760" allow="camera"></iframe>')}</code></div>
<div class="row"><div class="card"><div class="mute">Trials</div><div class="big">{o["trials"]}</div></div>
<div class="card"><div class="mute">Finished</div><div class="big">{o["finished"]}</div></div>
<div class="card"><div class="mute">Stopped for irritation</div><div class="big">{o["stopped"]}</div></div></div>
<h2>What the trials measured</h2><div class="card"><table><tr><th>Concern</th><th>Treated half vs control half</th></tr>{rows or '<tr><td colspan=2 class="mute">No measured trials yet.</td></tr>'}</table></div>
<h2>By skin type (Fitzpatrick)</h2><div class="card"><table><tr><th>Concern</th>{''.join(f'<th>Type {t}</th>' for t in types)}</tr>{type_rows}</table></div>
<h2>Claim audit</h2><div class="card"><p class="mute">The agent checks each claim in the listing against these trials.</p>{audit_html}
{audit_button}</div>
<h2>Listing</h2><div class="card mute">{html.escape(p["listing"] or "")}</div>'''
    return page(p['name'], body)


@router.post('/p/{code}/audit', dependencies=[Depends(authed)])
def run_audit(code: str, con=Depends(get_db)):
    p = con.execute('select * from products where code = ?', (code,)).fetchone()
    if not p:
        raise HTTPException(404)
    try:
        result = agent.audit(llm.get(db.setting(con, 'llm_provider')), p['name'], p['listing'], outcomes(con, code),
                             lambda job, step: db.log_step(con, f'product:{code}', job, step))
    except (agent.AgentError, llm.LLMError) as e:
        raise HTTPException(502, f'the agent could not audit: {e}')
    con.execute('update products set audit = ? where code = ?', (json.dumps(result), code))
    con.commit()
    return RedirectResponse(f'/admin/p/{code}', 303)
