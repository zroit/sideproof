"""Split-face trial math. Product on one half, the other half is the control.

For each concern, d = treated - control (mask coverage, percent of the half). Baseline scans,
taken before the product goes on, give the face's own asymmetry (their mean) and how much d
moves between photos (the noise). The product's effect is the later d minus the baseline
mean: daylight, sleep, season and the camera hit both halves alike and cancel out.

Every mask marks where a concern shows, so more coverage is worse, for moisture (dry areas)
and radiance (dull areas) too.
"""
import statistics

# concern -> (what the mask shows, how fast a product can move it)
CATALOG = {
    'oiliness': ('Oiliness', 'hours'),
    'moisture': ('Dryness', 'hours'),
    'radiance': ('Dullness', 'hours'),
    'redness': ('Redness', 'days'),
    'acne': ('Breakouts', 'weeks'),
    'pore': ('Visible pores', 'weeks'),
    'texture': ('Rough texture', 'weeks'),
    'age_spot': ('Dark spots', 'weeks'),
    'wrinkle': ('Wrinkles', 'weeks'),
    'dark_circle_v2': ('Dark circles', 'weeks'),
    'eye_bag': ('Eye bags', 'weeks'),
}
HARM = ('redness', 'acne')   # getting worse here means stop
MAX_CONCERNS = 4             # 4 concerns cost the same as 1 (9 units, SD)
NOISE_FLOOR = 0.5            # coverage points; identical photos still differ this much
K = 2.5                      # an effect counts when it is K times the noise


def other(side):
    return 'img_right' if side == 'img_left' else 'img_left'


def concern_stats(scans, concern, treated):
    """scans: [{'phase', 'at', 'sides'}] in time order; treated: 'img_left' or 'img_right'."""
    rows = [s for s in scans if concern in s['sides']]
    diff = lambda s: s['sides'][concern][treated] - s['sides'][concern][other(treated)]
    base = [diff(s) for s in rows if s['phase'] == 'baseline']
    after = [s for s in rows if s['phase'] == 'trial']
    out = {'concern': concern, 'label': CATALOG[concern][0], 'baseline_scans': len(base)}
    if len(base) < 2:
        return {**out, 'state': 'need_baseline'}
    mean = statistics.fmean(base)
    noise = max(statistics.stdev(base), NOISE_FLOOR)
    t0 = rows[0]['at']
    out.update(asymmetry=round(mean, 2), noise=round(noise, 2), threshold=round(K * noise, 2), series=[{
        'phase': s['phase'], 'hours': round((s['at'] - t0) / 3600, 1),
        'treated': s['sides'][concern][treated], 'control': s['sides'][concern][other(treated)],
        'effect': round(diff(s) - mean, 2)} for s in rows])
    if not after:
        return {**out, 'state': 'ready'}
    recent = [diff(s) for s in after[-2:]]
    effect = statistics.fmean(recent) - mean
    verdict = 'better' if effect <= -K * noise else 'worse' if effect >= K * noise else 'unclear'
    return {**out, 'state': 'measured', 'effect': round(effect, 2), 'verdict': verdict}


def summary(scans, concerns, treated):
    stats = {c: concern_stats(scans, c, treated) for c in concerns}
    harm = [c for c in concerns if c in HARM and stats[c].get('verdict') == 'worse']
    return {'concerns': stats, 'harm': harm}


def allowed_actions(status, stats, hours_in, plan_days, trial_scans):
    """What the agent may choose after a scan. Safety and the baseline are not its call."""
    if status == 'baseline':
        n = min((s['baseline_scans'] for s in stats['concerns'].values()), default=0)
        return ['another_baseline'] if n < 2 else ['start', 'another_baseline']
    if stats['harm']:
        return ['stop']
    clear = all(s.get('verdict') in ('better', 'worse') for s in stats['concerns'].values())
    if hours_in >= plan_days * 24:
        return ['conclude', 'extend']
    return ['continue', 'conclude'] if clear and trial_scans >= 2 else ['continue']
