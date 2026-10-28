import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import 'api.dart';
import 'theme.dart';
import 'widgets.dart';

/// Photos stay on this phone; the server keeps numbers only. Per trial: the first baseline,
/// the latest scan with YouCam's maps, and the claims' promise.
class _Pics {
  Uint8List? baseline, latest, promise;
  Map<String, Uint8List> overlays = {};
  List<double> midline = const [0.5, 0.5];
}

final Map<String, _Pics> _pics = {};

class TrialScreen extends StatefulWidget {
  const TrialScreen({
    super.key,
    required this.api,
    this.trialId,
    this.initial,
    this.demo = false,
    this.demoId = '',
  });
  final Api api;
  final String? trialId;
  final Trial? initial;
  final bool demo;
  final String demoId;

  @override
  State<TrialScreen> createState() => _TrialScreenState();
}

class _TrialScreenState extends State<TrialScreen> {
  Trial? _t;
  String? _error;
  String? _busy;
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    _t = widget.initial;
    _load();
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final t = widget.demo
          ? await widget.api.demo(widget.demoId)
          : await widget.api.trial(widget.trialId!);
      setState(() => _t = t);
      _poll?.cancel();
      if (t.thinking) {
        _poll = Timer(
          const Duration(seconds: 3),
          _load,
        ); // the agent is still deciding
      }
    } catch (e) {
      setState(() => _error = '$e');
    }
  }

  Future<void> _run(String label, Future<Trial> Function() action) async {
    setState(() {
      _busy = label;
      _error = null;
    });
    try {
      final t = await action();
      setState(() => _t = t);
      if (t.thinking) _poll = Timer(const Duration(seconds: 3), _load);
    } catch (e) {
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  Future<void> _scan() async {
    final f = await ImagePicker().pickImage(
      source: ImageSource.camera,
      preferredCameraDevice: CameraDevice.front,
      maxWidth: 2048,
      imageQuality: 92,
    );
    if (f == null) return;
    final photo = await f.readAsBytes();
    setState(() {
      _busy = 'YouCam Skin AI is measuring both halves';
      _error = null;
    });
    try {
      final r = await widget.api.scan(_t!.id, photo);
      if (r is Retake) {
        if (mounted) _retake(r.reasons);
        return;
      }
      final t = r as Trial;
      final pics = _pics.putIfAbsent(t.id, _Pics.new);
      pics.baseline ??= photo;
      pics.latest = photo;
      final media = t.media;
      if (media != null) {
        pics.overlays = {
          for (final e in (media['overlays'] as Map).entries)
            e.key as String: dataUrlBytes(e.value as String),
        };
        final line = media['midline'] as List;
        pics.midline = [
          (line[0][0] as num).toDouble(),
          (line[1][0] as num).toDouble(),
        ];
      }
      setState(() => _t = t);
      if (t.thinking) _poll = Timer(const Duration(seconds: 3), _load);
    } catch (e) {
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  Future<void> _promise() async {
    final pics = _pics[_t!.id];
    if (pics?.baseline == null) return;
    setState(() {
      _busy = 'YouCam AI Skin Simulation is drawing what the claims promise';
      _error = null;
    });
    try {
      final img = await widget.api.promise(_t!.id, pics!.baseline!);
      setState(() => pics.promise = img);
    } catch (e) {
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  void _retake(List<String> reasons) => showDialog(
    context: context,
    builder: (_) => AlertDialog(
      title: const Text('Take it again'),
      content: Text(
        '${reasons.join('\n')}\n\nThis photo was not sent for measuring, so it cost nothing.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('OK'),
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final t = _t;
    return Scaffold(
      appBar: AppBar(
        title: Text(t?.product ?? 'Trial'),
        actions: [
          IconButton(
            onPressed: _load,
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: t == null
          ? Center(
              child: _error != null
                  ? Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(_error!),
                    )
                  : const CircularProgressIndicator(),
            )
          : SafeArea(
              top: false,
              child: RefreshIndicator(
                onRefresh: _load,
                child: Column560(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
                    children: [
                      if (widget.demo)
                        _Note(
                          (t.media?['note'] as String?) ?? 'A finished trial recorded through the real API on one of YouCam\'s sample faces.',
                        ),
                      _header(t),
                      const SizedBox(height: 14),
                      TrialTimeline(
                        step: _stepOf(t),
                        notes: [
                          t.status == 'baseline' && !t.canStart
                              ? '${t.baselineScans} of 2'
                              : '',
                          '',
                          t.trialScans > 0 ? '${t.trialScans} done' : '',
                          '',
                        ],
                      ),
                      const SizedBox(height: 16),
                      if (!widget.demo) _stepCard(t),
                      if (t.verdict != null) _verdictCard(t),
                      _youCamCard(t),
                      for (final e in t.concerns.entries)
                        if (e.value['series'] != null) _concernCard(e.value),
                      _planCard(t),
                      _agentLog(t),
                    ],
                  ),
                ),
              ),
            ),
    );
  }

  int _stepOf(Trial t) {
    if (t.verdict != null) return 3;
    if (t.status == 'baseline') return t.canStart ? 1 : 0;
    return 2;
  }

  /// One result for the whole trial: worse wins, then better, else too early.
  String _overall(Trial t) {
    final v = t.concerns.values.map((c) => c['verdict']).toList();
    return v.contains('worse')
        ? 'worse'
        : v.contains('better')
        ? 'better'
        : 'unclear';
  }

  Widget _header(Trial t) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        _Pill(statusWords(t.status)),
        if (t.skinType != null) _Pill('Skin type ${t.skinType}'),
        Text.rich(
          TextSpan(
            children: [
              WidgetSpan(
                alignment: PlaceholderAlignment.middle,
                child: Container(
                  width: 10,
                  height: 10,
                  margin: const EdgeInsets.only(right: 6),
                  decoration: BoxDecoration(
                    color: scheme.primary,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
              TextSpan(text: 'Product on your ${t.treatedSide} side'),
            ],
          ),
          style: text.bodyMedium,
        ),
      ],
    );
  }

  Widget _planCard(Trial t) {
    final p = t.plan;
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final cautions = List<String>.from(p['cautions'] ?? []);
    final safe = p['safe_to_try'] != false;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('The plan', style: text.titleMedium),
            const SizedBox(height: 6),
            Text(
              p['summary'] ?? '',
              style: text.bodyMedium?.copyWith(height: 1.4),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _Pill(
                  '${p['days']} ${p['days'] == 1 ? 'day' : 'days'}',
                  icon: Icons.calendar_today_outlined,
                ),
                _Pill(
                  'A scan every ${p['scan_every_hours']} h',
                  icon: Icons.schedule,
                ),
                if (p['patch_first'] == true)
                  const _Pill(
                    'Small patch first',
                    icon: Icons.healing_outlined,
                  ),
              ],
            ),
            if (cautions.isNotEmpty) ...[
              const SizedBox(height: 12),
              if (!safe)
                const _Note('Do not try this without a doctor.', danger: true),
              for (final c in cautions)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.info_outline,
                        size: 16,
                        color: scheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 6),
                      Expanded(child: Text(c, style: text.bodySmall)),
                    ],
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _stepCard(Trial t) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final d = t.decision;
    final pics = _pics[t.id];
    final children = <Widget>[];
    if (_busy != null) {
      children.addAll([
        Text(_busy!, style: text.titleMedium),
        const SizedBox(height: 12),
        const LinearProgressIndicator(
          minHeight: 6,
          borderRadius: BorderRadius.all(Radius.circular(3)),
        ),
      ]);
    } else if (t.status == 'baseline' && !t.canStart) {
      children.addAll([
        Text(
          'Baseline photo ${t.baselineScans + 1} of 2',
          style: text.titleLarge,
        ),
        const SizedBox(height: 6),
        Text(
          t.baselineScans == 0
              ? 'Before any product. These two photos measure your face\'s own left-right difference.'
              : 'A few minutes after the first one, same place, same light.',
          style: text.bodyMedium?.copyWith(
            height: 1.4,
            color: scheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 14),
        const PhotoTips(),
        const SizedBox(height: 16),
        GradientButton(
          onPressed: _scan,
          icon: Icons.photo_camera_outlined,
          label: 'Take baseline photo',
        ),
      ]);
    } else if (t.canStart) {
      children.addAll([
        Text('Put the product on the shaded half only', style: text.titleLarge),
        const SizedBox(height: 14),
        pics?.baseline != null
            ? SplitPhoto(
                photo: MemoryImage(pics!.baseline!),
                midline: pics.midline,
                treatedLeft: t.treatedOnImageLeft,
                tint: true,
                treatedPhoto: pics.promise == null
                    ? null
                    : MemoryImage(pics.promise!),
              )
            : Center(child: HalfShade(imageLeft: t.treatedOnImageLeft)),
        const SizedBox(height: 14),
        Text(
          d?['message'] ?? '',
          style: text.bodyMedium?.copyWith(height: 1.4),
        ),
        if (pics?.baseline != null && pics?.promise == null) ...[
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _promise,
            icon: const Icon(Icons.auto_fix_high_outlined),
            label: const Text('See what the claims promise'),
          ),
        ],
        if (pics?.promise != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              'The shaded half shows the claims\' promise, drawn by YouCam AI Skin Simulation. The trial measures what really happens.',
              style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ),
        const SizedBox(height: 16),
        GradientButton(
          onPressed: () =>
              _run('Starting the trial', () => widget.api.start(t.id)),
          label: 'It\'s on: start the trial',
        ),
      ]);
    } else if (t.status == 'running' || t.status == 'concluding') {
      children.addAll([
        Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: const BoxDecoration(
                gradient: Sp.cta,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(color: Color(0xFFFBE3EC), spreadRadius: 6),
                ],
              ),
              child: const Icon(
                Icons.auto_awesome,
                size: 18,
                color: Colors.white,
              ),
            ),
            const SizedBox(width: 4),
            const SizedBox(width: 10),
            Text('Your trial agent', style: text.titleMedium),
          ],
        ),
        const SizedBox(height: 10),
        Text(
          t.thinking
              ? 'Looking at the new scan…'
              : (d?['message'] ?? 'Take your first scan when the plan says.'),
          style: text.bodyLarge?.copyWith(height: 1.4),
        ),
        if (d?['next_scan_in_hours'] != null) ...[
          const SizedBox(height: 8),
          _Pill(
            'Next scan in ${d!['next_scan_in_hours']} h',
            icon: Icons.schedule,
          ),
        ],
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              flex: 3,
              child: GradientButton(
                onPressed: _scan,
                icon: Icons.photo_camera_outlined,
                label: 'Take a scan',
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              flex: 2,
              child: OutlinedButton(
                onPressed: t.measured
                    ? () => _run(
                        'The agent is writing the verdict',
                        () => widget.api.finish(t.id),
                      )
                    : null,
                child: const Text('Finish'),
              ),
            ),
          ],
        ),
      ]);
    } else if (t.status == 'stopped') {
      children.addAll([
        const _Note('Stopped: the treated half got worse.', danger: true),
        Text(
          d?['message'] ??
              'Wash the product off. See a dermatologist if it stays.',
          style: text.bodyLarge,
        ),
        if (t.verdict == null) ...[
          const SizedBox(height: 16),
          OutlinedButton(
            onPressed: () => _run(
              'The agent is writing the verdict',
              () => widget.api.finish(t.id),
            ),
            child: const Text('See the verdict'),
          ),
        ],
      ]);
    }
    if (_error != null) {
      children.add(
        Padding(
          padding: const EdgeInsets.only(top: 12),
          child: _Note(_error!, danger: true),
        ),
      );
    }
    if (children.isEmpty) return const SizedBox.shrink();
    return ChromeBox(
      radius: 24,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    );
  }

  /// What YouCam saw: the latest photo with YouCam's map per concern, and the promise. The demo
  /// trial's pictures come from the server; a person's own stay on this phone.
  Widget _youCamCard(Trial t) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    ImageProvider? latest, baseline, promise;
    Map<String, ImageProvider> overlays = {};
    var midline = const [0.5, 0.5];
    final m = t.media;
    if (widget.demo && m != null && m['photos'] != null) {
      final photos = m['photos'] as Map;
      String url(String name) => widget.api.url('/demo-media/$name');
      latest = NetworkImage(url(photos['latest']));
      baseline = NetworkImage(url(photos['baseline']));
      if (photos['promise'] != null) {
        promise = NetworkImage(url(photos['promise']));
      }
      overlays = {
        for (final e in ((m['overlays'] as Map)['latest'] as Map).entries)
          e.key as String: NetworkImage(url(e.value as String)),
      };
      final line = m['midline'] as List;
      midline = [
        (line[0][0] as num).toDouble(),
        (line[1][0] as num).toDouble(),
      ];
    } else {
      final pics = _pics[t.id];
      if (pics?.latest == null || pics!.overlays.isEmpty) {
        return const SizedBox.shrink();
      }
      latest = MemoryImage(pics.latest!);
      if (pics.baseline != null) baseline = MemoryImage(pics.baseline!);
      if (pics.promise != null) promise = MemoryImage(pics.promise!);
      overlays = {
        for (final e in pics.overlays.entries) e.key: MemoryImage(e.value),
      };
      midline = pics.midline;
    }
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const AccentTitle('What ', 'YouCam', ' saw'),
          const SizedBox(height: 6),
          Text(
            'YouCam AI Skin Analysis returns a map for each concern. SideProof splits it at the midline and measures each half.',
            style: text.bodyMedium?.copyWith(
              color: scheme.onSurfaceVariant,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 14),
          YouCamView(
            photo: latest,
            overlays: overlays,
            midline: midline,
            treatedLeft: t.treatedOnImageLeft,
            concerns: t.concerns,
          ),
          if (promise != null && baseline != null) ...[
            const SizedBox(height: 22),
            const AccentTitle('The ', 'promise', '', color: Sp.lilac, size: 24),
            const SizedBox(height: 6),
            Text(
              'YouCam AI Skin Simulation on the treated half: what the claims would look like before any product went on.',
              style: text.bodyMedium?.copyWith(
                color: scheme.onSurfaceVariant,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 12),
            SplitPhoto(
              photo: baseline,
              treatedPhoto: promise,
              midline: midline,
              treatedLeft: t.treatedOnImageLeft,
            ),
          ],
        ],
      ),
    );
  }

  /// The concern the verdict ring shows: a claimed one that was measured, the one that moved
  /// most past its noise.
  Map<String, dynamic>? _lead(Trial t) {
    final claimed = [
      for (final c in t.plan['claims'] ?? const [])
        if (c['concern'] != null) c['concern'] as String,
    ];
    double moved(Map c) =>
        ((c['effect'] as num?) ?? 0).abs() /
        ((c['threshold'] as num?) ?? 1).toDouble();
    final measured =
        t.concerns.values
            .map((c) => c as Map<String, dynamic>)
            .where((c) => c['state'] == 'measured')
            .toList()
          ..sort((a, b) => moved(b).compareTo(moved(a)));
    return measured.where((c) => claimed.contains(c['concern'])).firstOrNull ??
        measured.firstOrNull;
  }

  Widget _verdictCard(Trial t) {
    final v = t.verdict!;
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final overall = _overall(t);
    final lead = _lead(t);
    String claimVerdict(String r) => r.startsWith('supported')
        ? 'better'
        : r.startsWith('not supported')
        ? 'worse'
        : 'unclear';
    return ChromeBox(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              VerdictRing(
                effect: (lead?['effect'] as num?)?.toDouble(),
                threshold: (lead?['threshold'] as num?)?.toDouble(),
                verdict: lead?['verdict'] ?? overall,
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    VerdictChip(overall),
                    const SizedBox(height: 8),
                    Text(
                      v['headline'] ?? '',
                      style: display(24, color: Sp.ink, height: 1.1),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if ((v['claims'] as List?)?.isNotEmpty == true) ...[
            const SizedBox(height: 14),
            for (final c in v['claims'])
              Container(
                margin: const EdgeInsets.only(top: 8),
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: Sp.sunk,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: Text(
                        '"${c['claim']}"',
                        style: text.bodyMedium?.copyWith(
                          fontStyle: FontStyle.italic,
                          height: 1.35,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Flexible(
                      flex: 2,
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: ResultPill(
                          '${c['result']}',
                          claimVerdict('${c['result']}'),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
          if ((v['next'] ?? '').toString().isNotEmpty) ...[
            const SizedBox(height: 14),
            Text(
              v['next'],
              style: text.bodyMedium?.copyWith(
                color: scheme.onSurfaceVariant,
                height: 1.4,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _concernCard(Map<String, dynamic> s) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final measured = s['state'] == 'measured';
    final small = text.bodySmall?.copyWith(
      color: scheme.onSurfaceVariant,
      height: 1.45,
    );
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    s['label'] ?? s['concern'],
                    style: text.titleMedium,
                  ),
                ),
                VerdictChip(measured ? s['verdict'] : null),
              ],
            ),
            const SizedBox(height: 12),
            EffectChart(stats: s),
            const SizedBox(height: 10),
            Text(
              'Your face\'s own left-right difference: ${s['asymmetry']}',
              style: small,
            ),
            Text(
              'Photo-to-photo noise: ${s['noise']}. A change counts past ±${s['threshold']}.',
              style: small,
            ),
            if (measured)
              Text(
                'Product effect: ${s['effect']}',
                style: small?.copyWith(
                  color: scheme.onSurface,
                  fontWeight: FontWeight.w600,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _agentLog(Trial t) {
    if (t.agentLog.isEmpty) return const SizedBox.shrink();
    final text = Theme.of(context).textTheme;
    const jobs = {
      'plan': 'Planning',
      'next_step': 'After a scan',
      'verdict': 'Verdict',
    };
    return Card(
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        leading: Icon(
          Icons.auto_awesome,
          color: Theme.of(context).colorScheme.primary,
        ),
        title: Text('How the agent worked', style: text.titleMedium),
        subtitle: Text(
          '${t.agentLog.length} steps. Every number comes from YouCam or the trial math.',
          style: text.bodySmall,
        ),
        children: [
          for (final s in t.agentLog)
            ListTile(
              dense: true,
              title: Text(
                '${jobs[s['job']] ?? s['job']}: ${s['tool'] != null
                    ? 'looked at ${s['tool']}'
                    : s['rejected'] != null
                    ? 'answer sent back'
                    : 'answered'}',
              ),
              subtitle: Text(
                [
                  s['thought'] ?? '',
                  if (s['rejected'] != null) 'Why: ${s['rejected']}',
                ].join('\n'),
              ),
            ),
        ],
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill(this.label, {this.icon});
  final String label;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: scheme.surfaceContainer,
        borderRadius: BorderRadius.circular(99),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: scheme.onSurfaceVariant),
            const SizedBox(width: 5),
          ],
          Text(label, style: body(13, weight: 700, color: scheme.onSurface)),
        ],
      ),
    );
  }
}

class _Note extends StatelessWidget {
  const _Note(this.text, {this.danger = false});
  final String text;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: (danger ? Sp.worse : scheme.primary).withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: danger ? Sp.worse : scheme.onSurface,
          height: 1.4,
        ),
      ),
    );
  }
}
