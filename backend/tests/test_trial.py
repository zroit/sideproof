from halfface import agent, trial


def scan(phase, hours, treated, control, concern='oiliness', side='img_left'):
    other = trial.other(side)
    return {'phase': phase, 'at': hours * 3600, 'sides': {concern: {side: treated, other: control}}}


def test_effect_is_measured_against_the_faces_own_asymmetry():
    # The treated half starts 2.6 points oilier; after the product it is 7 points less oily.
    scans = [scan('baseline', 0, 12.2, 9.6), scan('baseline', 0.1, 12.4, 9.7),
             scan('trial', 2, 5.0, 9.9), scan('trial', 4, 4.6, 9.5)]
    s = trial.concern_stats(scans, 'oiliness', 'img_left')
    assert s['asymmetry'] == 2.65
    assert s['effect'] < -s['threshold']
    assert s['verdict'] == 'better'


def test_a_change_on_both_halves_is_not_the_product():
    # A humid day: both halves got oilier by the same amount.
    scans = [scan('baseline', 0, 12.2, 9.6), scan('baseline', 0.1, 12.3, 9.6),
             scan('trial', 24, 18.3, 15.7)]
    assert trial.concern_stats(scans, 'oiliness', 'img_left')['verdict'] == 'unclear'


def test_noisy_baseline_raises_the_bar():
    scans = [scan('baseline', 0, 12.0, 9.0), scan('baseline', 0.1, 15.0, 9.0),
             scan('trial', 2, 11.0, 9.0)]
    s = trial.concern_stats(scans, 'oiliness', 'img_left')
    assert s['noise'] > 2 and s['verdict'] == 'unclear'


def test_one_baseline_is_not_enough():
    s = trial.concern_stats([scan('baseline', 0, 12, 9)], 'oiliness', 'img_left')
    assert s['state'] == 'need_baseline'


def test_redness_rising_on_the_treated_half_forces_a_stop():
    scans = [scan('baseline', 0, 1.0, 1.0, 'redness'), scan('baseline', 0.1, 1.1, 1.0, 'redness'),
             scan('trial', 24, 6.0, 1.1, 'redness')]
    stats = trial.summary(scans, ['redness'], 'img_left')
    assert stats['harm'] == ['redness']
    assert trial.allowed_actions('running', stats, 24, 7, 1) == ['stop']


def test_the_agent_may_not_conclude_early_on_one_scan():
    scans = [scan('baseline', 0, 12.2, 9.6), scan('baseline', 0.1, 12.4, 9.7), scan('trial', 2, 5.0, 9.9)]
    stats = trial.summary(scans, ['oiliness'], 'img_left')
    assert trial.allowed_actions('running', stats, 2, 1, 1) == ['continue']
    assert trial.allowed_actions('running', stats, 2, 1, 2) == ['continue', 'conclude']


def test_numbers_the_tools_never_gave_are_caught():
    sources = [{'effect': -7.35, 'noise': 0.5, 'threshold': 1.25}]
    assert agent.unsupported_numbers('Oiliness fell by 7.4 points, well past the 1.25 bar.', sources) == []
    assert agent.unsupported_numbers('Oiliness fell by 7 points after 2 scans.', sources) == []
    assert agent.unsupported_numbers('Oiliness fell 40% in a week.', sources) == [40.0]


def test_the_verdict_cannot_change_or_skip_a_measured_result():
    stats = {'concerns': {'oiliness': {'verdict': 'unclear'}, 'redness': {'verdict': 'better'}}, 'harm': []}
    answers = [
        {'thought': 'Round up.', 'final': {'headline': 'It works.', 'next': '', 'claims': [],
                                           'concerns': [{'concern': 'Oiliness', 'verdict': 'better', 'text': ''},
                                                        {'concern': 'redness', 'verdict': 'better', 'text': ''}]}},
        {'thought': 'Skip one.', 'final': {'headline': 'Less redness.', 'next': '', 'claims': [],
                                           'concerns': [{'concern': 'redness', 'verdict': 'better', 'text': ''}]}},
        {'thought': 'As measured.', 'final': {'headline': 'Less redness; shine too early to tell.', 'next': '', 'claims': [],
                                              'concerns': [{'concern': 'Oiliness', 'verdict': 'unclear', 'text': ''},
                                                           {'concern': 'redness', 'verdict': 'better', 'text': ''}]}},
    ]

    class Model:
        def complete(self, system, prompt, image=None):
            import json
            return json.dumps(answers.pop(0))

    steps = []
    v = agent.verdict(Model(), {'status': 'running', 'hours_in': 30, 'plan': {}, 'stats': stats},
                      lambda job, step: steps.append(step))
    assert v['concerns'][0]['verdict'] == 'unclear'
    assert [bool(s['rejected']) for s in steps] == [True, True, False]
