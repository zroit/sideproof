"""The demo trials: finished trials anyone can open without spending units. Each is a recording
of numbers only (scores, per-half coverage, the agent's steps), stored as demo/*.json; their
pictures are in demo/media/<trial id>/."""
import json
import pathlib

DEMO_DIR = pathlib.Path(__file__).resolve().parent.parent / 'demo'
DEMO_FILE = DEMO_DIR / 'demo_trial.json'
TABLES = {'trials': 'id', 'scans': 'trial_id', 'agent_log': 'trial_id'}


def export(con, trial_id, path=DEMO_FILE):
    rec = {}
    for table, key in TABLES.items():
        rows = con.execute(f'select * from {table} where {key} = ?', (trial_id,)).fetchall()
        rec[table] = [{k: r[k] for k in r.keys() if k != 'id' or table == 'trials'} for r in rows]
    for t in rec['trials']:
        t['device'] = 'demo'
    path.parent.mkdir(exist_ok=True)
    path.write_text(json.dumps(rec, indent=1))


def load_all(con):
    for path in sorted(DEMO_DIR.glob('*.json')):
        load(con, path)


def load(con, path=DEMO_FILE):
    if not path.exists():
        return
    rec = json.loads(path.read_text())
    tid = rec['trials'][0]['id']
    if con.execute('select 1 from trials where id = ?', (tid,)).fetchone():
        return
    for table, rows in rec.items():
        for r in rows:
            con.execute(f'insert into {table} ({", ".join(r)}) values ({", ".join("?" * len(r))})', list(r.values()))
    con.commit()
