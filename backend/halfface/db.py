"""SQLite store. Numbers only: no photo, mask or landmark is ever written here."""
import json
import os
import sqlite3
import time

from . import config

SCHEMA = '''
create table if not exists settings (key text primary key, value text);
create table if not exists products (
    code text primary key, shop text, name text, listing text, audit text, created_at real);
create table if not exists trials (
    id text primary key, device text, product text, code text, treated text,
    plan text, status text, decision text, verdict text, skin_type text, created_at real, started_at real);
create table if not exists scans (
    id integer primary key, trial_id text, phase text, at real,
    checks text, sides text, scores text, units integer);
create table if not exists agent_log (
    id integer primary key, trial_id text, at real, job text, step text);
create table if not exists units (id integer primary key, at real, units integer, what text);
create index if not exists scans_trial on scans (trial_id);
create index if not exists log_trial on agent_log (trial_id);
create index if not exists trials_device on trials (device);
'''

DEFAULTS = {
    'llm_provider': os.environ.get('HALFFACE_LLM', 'gemini'),
    'daily_unit_cap': '150',
    'fitzpatrick': 'on',
}


def connect():
    con = sqlite3.connect(config.DB_PATH, timeout=10, check_same_thread=False)
    con.row_factory = sqlite3.Row
    con.execute('pragma journal_mode=wal')
    con.executescript(SCHEMA)
    return con


def setting(con, key):
    row = con.execute('select value from settings where key = ?', (key,)).fetchone()
    return row['value'] if row else DEFAULTS.get(key)


def units_today(con):
    return con.execute('select coalesce(sum(units), 0) from units where at > ?', (time.time() - 86400,)).fetchone()[0]


def log_step(con, trial_id, job, step):
    con.execute('insert into agent_log (trial_id, at, job, step) values (?, ?, ?, ?)',
                (trial_id, time.time(), job, json.dumps(step)))
    con.commit()


def trial_row(con, trial_id):
    row = con.execute('select * from trials where id = ?', (trial_id,)).fetchone()
    if not row:
        return None
    t = dict(row)
    for k in ('plan', 'decision', 'verdict'):
        t[k] = json.loads(t[k]) if t[k] else None
    return t


def scans_of(con, trial_id):
    rows = con.execute('select * from scans where trial_id = ? order by at', (trial_id,)).fetchall()
    return [{'id': r['id'], 'phase': r['phase'], 'at': r['at'], 'checks': json.loads(r['checks']),
             'sides': json.loads(r['sides']), 'scores': json.loads(r['scores'])} for r in rows]


def log_of(con, trial_id):
    rows = con.execute('select at, job, step from agent_log where trial_id = ? order by id', (trial_id,)).fetchall()
    return [{'at': r['at'], 'job': r['job'], **json.loads(r['step'])} for r in rows]
