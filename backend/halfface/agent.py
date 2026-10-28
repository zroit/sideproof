"""The trial agent: plans a trial from a label, picks the next step after each scan, and
writes the verdict. It decides and explains; it never measures. Every number comes from
YouCam or trial.py, and an answer quoting a number the tools didn't give is sent back.
"""
import json
import re

from . import llm as llms
from . import trial

ROLE = ('You are the HalfFace trial agent. A person tests a skincare product on one half of '
        'their face; the other half is the control. YouCam Skin AI measures both halves. '
        'Be plain, brief and honest: "too early to tell" is a good answer. Never diagnose. '
        'Use only numbers that the context or a tool gave; add no times, dates or figures of '
        'your own. Write in English.')

PROTOCOL = ('Answer with ONE JSON object and nothing else.\n'
            'To use a tool: {"thought": "<one short sentence>", "tool": "<name>", "args": {}}\n'
            'To finish:     {"thought": "<one short sentence>", "final": {...}}')


class AgentError(RuntimeError):
    pass


def _numbers(text):
    return [float(n) for n in re.findall(r'-?\d+(?:\.\d+)?', text)]


def _collect(value, into):
    if isinstance(value, bool):
        return into
    if isinstance(value, (int, float)):
        into.add(float(value))
    elif isinstance(value, dict):
        for v in value.values():
            _collect(v, into)
    elif isinstance(value, (list, tuple)):
        for v in value:
            _collect(v, into)
    return into


def unsupported_numbers(text, sources):
    """Numbers in text that no tool output or context gave (allowing rounding and sign)."""
    known = _collect(sources, set())
    bad = []
    for n in _numbers(text):
        if n.is_integer() and 0 <= n <= 10:
            continue        # counts and small steps: "2 scans", "3 days"
        if not any(abs(abs(n) - abs(v)) <= 0.051 or round(abs(v)) == abs(n) for v in known):
            bad.append(n)
    return bad


def run(provider, job, task, context, tools, validate, log, image=None, max_steps=5):
    """Tool loop. tools: name -> (description, fn() -> json-able). log(job, step) records each step."""
    tool_doc = '\n'.join(f'- {name}: {desc}' for name, (desc, _) in tools.items())
    system = f'{ROLE}\n\nTASK: {task}\n\nTools (no arguments):\n{tool_doc}\n\n{PROTOCOL}'
    transcript = ['CONTEXT: ' + json.dumps(context)]
    seen = [context]
    for _ in range(max_steps):
        reply = llms.parse_json(provider.complete(system, '\n\n'.join(transcript), image))
        transcript.append('YOU: ' + json.dumps(reply))
        if 'tool' not in reply:
            # Some models drop the {"final": ...} wrapper; anything that is not a tool call is an answer.
            final = reply['final'] if isinstance(reply.get('final'), dict) else {k: v for k, v in reply.items() if k != 'thought'}
            problem = validate(final, seen)
            log(job, {'thought': reply.get('thought'), 'final': final, 'rejected': problem})
            if not problem:
                return final
            transcript.append('REJECTED: ' + problem + ' Answer again.')
            continue
        name = reply.get('tool')
        if name not in tools:
            transcript.append(f'REJECTED: there is no tool "{name}".')
            continue
        result = tools[name][1]()
        seen.append(result)
        log(job, {'thought': reply.get('thought'), 'tool': name})
        transcript.append(f'TOOL {name}: ' + json.dumps(result))
    raise AgentError(f'{job}: no acceptable answer in {max_steps} steps')


# ---- jobs ------------------------------------------------------------------------------

def plan(provider, product, listing, image, budget, log):
    task = ('Plan a split-face trial for this product. Find what it claims (label photo and/or '
            'listing text) and map each claim to a concern from the catalog, or to null when '
            'YouCam cannot measure it. Measure at most 4 concerns, claimed ones first; add '
            '"redness" when the product has strong actives, to catch irritation. Trial length '
            'follows the slowest chosen concern: hours -> 1 day, days -> 3 to 7 days, weeks -> 14 '
            'to 28 days. patch_first is true for strong actives (retinoids, AHA/BHA, benzoyl '
            'peroxide, vitamin C) and for unknown products. In cautions, flag anything that '
            'should not go on a face without a doctor (steroids such as clobetasol or '
            'betamethasone, mercury or mercurous chloride, hydroquinone above 2%) and set '
            'safe_to_try false then. Final: {"product": str, "claims": [{"text": str, '
            '"concern": str|null}], "concerns": [str], "days": int, "scan_every_hours": int, '
            '"patch_first": bool, "safe_to_try": bool, "cautions": [str], "summary": str}')
    tools = {
        'concern_catalog': ('the concerns YouCam measures, with what the mask shows and how fast a product can move it',
                            lambda: {k: {'shows': v[0], 'speed': v[1]} for k, v in trial.CATALOG.items()}),
        'unit_budget': ('units left today and the cost of one scan', lambda: budget),
    }

    def validate(final, _):
        concerns = final.get('concerns') or []
        if not concerns or len(concerns) > trial.MAX_CONCERNS:
            return f'choose 1 to {trial.MAX_CONCERNS} concerns.'
        unknown = [c for c in concerns if c not in trial.CATALOG]
        if unknown:
            return f'not in the catalog: {unknown}.'
        if not 1 <= int(final.get('days') or 0) <= 28:
            return 'days must be 1 to 28.'
        if not 1 <= int(final.get('scan_every_hours') or 0) <= 72:
            return 'scan_every_hours must be 1 to 72.'
        return None

    context = {'product': product, 'listing': listing or None, 'label_photo': bool(image)}
    return run(provider, 'plan', task, context, tools, validate, log, image=image)


def next_step(provider, state, allowed, log):
    """state: {'status', 'hours_in', 'plan', 'stats'}; allowed from trial.allowed_actions."""
    task = ('A scan was just added. Look at the trial, then choose the next step from '
            'allowed_actions and tell the person, in 1 to 3 plain sentences, what changed and '
            'what to do now. "effect" is the treated side minus the control, after removing '
            'the face\'s own asymmetry; below zero means less of the concern on the treated '
            'side. An effect inside the threshold is noise. If you stop for redness or '
            'breakouts, tell them to wash the product off and see a dermatologist if it stays. '
            'Final: {"action": str, "message": str, "next_scan_in_hours": int|null}')
    tools = {
        'trial_stats': ('per concern: baseline asymmetry, noise, threshold, effect, verdict, and every scan',
                        lambda: state['stats']),
        'trial_plan': ('the plan: product, claims, concerns, days, scan interval, cautions', lambda: state['plan']),
    }

    def validate(final, seen):
        if final.get('action') not in allowed:
            return f'action must be one of {allowed}.'
        message = str(final.get('message') or '')
        if not message or len(message) > 600:
            return 'message must be 1 to 600 characters.'
        bad = unsupported_numbers(message, seen)
        return f'these numbers are not in the tool results: {bad}. Leave them out rather than change them.' if bad else None

    context = {'status': state['status'], 'hours_in': state['hours_in'], 'allowed_actions': allowed}
    return run(provider, 'next_step', task, context, tools, validate, log)


def verdict(provider, state, log):
    task = ('Write the trial verdict. CONTEXT.results has each measured concern\'s verdict '
            '(better, worse, unclear); keep it unchanged, and make each concern\'s text agree '
            'with it: better means the treated half improved past the noise, unclear means no '
            'change beyond the noise yet. trial_stats has the scans if you need them. The '
            'headline is one sentence with the main result. Then check each claim in '
            'CONTEXT.claims, copying its text exactly into "claim": supported (its concern is better and the '
            'trial has run as long as the claim says), not supported (worse, or unclear after '
            'that long), not measured (no concern for it), or too early. Final: '
            '{"headline": str, "concerns": [{"concern": str, "verdict": str, "text": str}], '
            '"claims": [{"claim": str, "result": str}], "next": str}')
    tools = {
        'trial_stats': ('per concern: baseline asymmetry, noise, threshold, effect, verdict, and every scan',
                        lambda: state['stats']),
        'trial_plan': ('the plan: product, claims, concerns, days, scan interval, cautions', lambda: state['plan']),
    }
    truth = {c: s.get('verdict', 'unclear') for c, s in state['stats']['concerns'].items()}
    names = {**{c: c for c in truth}, **{trial.CATALOG[c][0].lower(): c for c in truth}}
    claims = [str(c.get('text', '')) for c in state['plan'].get('claims') or []]
    plain = lambda text: re.sub(r'[^a-z0-9]+', ' ', str(text).lower()).strip()

    def validate(final, seen):
        given = [str(c.get('claim', '')) for c in final.get('claims') or [] if isinstance(c, dict)]
        if sorted(map(plain, given)) != sorted(map(plain, claims)):
            return f'claims must be exactly the product\'s claims, once each: {claims}.'
        given = {}
        for item in final.get('concerns') or []:
            key = names.get(str(item.get('concern', '')).lower())
            if not key:
                return f'"{item.get("concern")}" is not a measured concern; use one of {list(truth)}.'
            given[key] = item.get('verdict')
        for key, verdict in truth.items():
            if given.get(key) != verdict:
                return f'{key} verdict is "{verdict}" (from trial_stats), not "{given.get(key)}".'
        text = ' '.join([str(final.get('headline', '')), str(final.get('next', ''))] +
                        [str(i.get('text', '')) for i in final.get('concerns') or []])
        bad = unsupported_numbers(text, seen)
        return f'these numbers are not in the tool results: {bad}. Leave them out rather than change them.' if bad else None

    results = {c: {k: s.get(k) for k in ('label', 'verdict', 'effect', 'threshold')}
               for c, s in state['stats']['concerns'].items() if s.get('state') == 'measured'}
    context = {'status': state['status'], 'hours_in': state['hours_in'], 'results': results,
               'claims': [{'text': c.get('text'), 'concern': c.get('concern')} for c in state['plan'].get('claims') or []]}
    return run(provider, 'verdict', task, context, tools, validate, log, max_steps=7)


def audit(provider, product, listing, outcomes, log):
    """Check a shop's listing claims against what its customers' trials measured."""
    task = ('A shop sells this product. Check each claim in its listing against the anonymous '
            'split-face trial outcomes of its customers (product_outcomes). For each claim give '
            'the matching concern (or null) and a status: "backed" (most trials measuring it came '
            'out better), "not backed" (most unclear or worse), "mixed", "not enough trials" '
            '(fewer than 3 trials measured it), or "not measurable". Give the counts as evidence. '
            'Then suggest listing wording the evidence supports. Final: {"claims": [{"claim": str, '
            '"concern": str|null, "status": str, "evidence": str}], "suggested_wording": str}')
    tools = {
        'product_listing': ('the product name and the listing text the shop uses', lambda: {'product': product, 'listing': listing}),
        'product_outcomes': ('per concern, how many trials came out better, unclear or worse; also by skin type', lambda: outcomes),
    }

    def validate(final, seen):
        for item in final.get('claims') or []:
            c = item.get('concern')
            counts = outcomes['concerns'].get(c) if c else None
            measured = sum(counts.values()) if counts else 0
            if item.get('status') in ('backed', 'not backed', 'mixed') and measured < 3:
                return f'"{item.get("claim")}": only {measured} trials measured {c}, so it is "not enough trials".'
        text = ' '.join(str(i.get('evidence', '')) for i in final.get('claims') or [])
        bad = unsupported_numbers(text, seen)
        return f'these numbers are not in the tool results: {bad}. Leave them out rather than change them.' if bad else None

    return run(provider, 'audit', task, {'product': product}, tools, validate, log)
