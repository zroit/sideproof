import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import 'api.dart';
import 'widgets.dart';

/// Photos stay on this phone, for showing the shaded half; the server keeps numbers only.
final Map<String, Uint8List> _lastPhoto = {};

class TrialScreen extends StatefulWidget {
  const TrialScreen({super.key, required this.api, this.trialId, this.initial, this.demo = false});
  final Api api;
  final String? trialId;
  final Trial? initial;
  final bool demo;

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
      final t = widget.demo ? await widget.api.demo() : await widget.api.trial(widget.trialId!);
      setState(() => _t = t);
      _poll?.cancel();
      if (t.thinking) _poll = Timer(const Duration(seconds: 3), _load);     // the agent is still deciding
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
    final f = await ImagePicker().pickImage(source: ImageSource.camera, preferredCameraDevice: CameraDevice.front, maxWidth: 2048, imageQuality: 92);
    if (f == null) return;
    final photo = await f.readAsBytes();
    setState(() {
      _busy = 'YouCam Skin AI is measuring both halves…';
      _error = null;
    });
    try {
      final r = await widget.api.scan(_t!.id, photo);
      if (r is Retake) {
        if (mounted) _retake(r.reasons);
        return;
      }
      _lastPhoto[_t!.id] = photo;
      final t = r as Trial;
      setState(() => _t = t);
      if (t.thinking) _poll = Timer(const Duration(seconds: 3), _load);
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
          content: Text('${reasons.join('\n')}\n\nThis photo was not sent for measuring, so it cost nothing.'),
          actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK'))],
        ),
      );

  @override
  Widget build(BuildContext context) {
    final t = _t;
    return Scaffold(
      appBar: AppBar(title: Text(t?.product ?? 'Trial'), actions: [IconButton(onPressed: _load, icon: const Icon(Icons.refresh))]),
      body: t == null
          ? Center(child: _error != null ? Text(_error!) : const CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(padding: const EdgeInsets.all(16), children: [
                if (widget.demo) const _Note('Demo trial: YouCam\'s sample face, with a digital matte filter on one half playing the product.'),
                _header(t),
                _planCard(t),
                if (!widget.demo) _stepCard(t),
                if (t.verdict != null) _verdictCard(t.verdict!),
                for (final e in t.concerns.entries) _concernCard(e.value),
                _agentLog(t),
              ]),
            ),
    );
  }

  Widget _header(Trial t) {
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Wrap(spacing: 8, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
        Chip(label: Text(t.status)),
        if (t.skinType != null) Chip(label: Text('Skin type ${t.skinType}')),
        Text('Product on your ${t.treatedSide} side', style: text.bodyMedium),
      ]),
    );
  }

  Widget _planCard(Trial t) {
    final p = t.plan;
    final text = Theme.of(context).textTheme;
    final cautions = List<String>.from(p['cautions'] ?? []);
    final safe = p['safe_to_try'] != false;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('The plan', style: text.titleMedium),
          const SizedBox(height: 6),
          Text(p['summary'] ?? ''),
          const SizedBox(height: 8),
          Text('${p['days']} day(s), a scan every ${p['scan_every_hours']} h${p['patch_first'] == true ? ', small patch first' : ''}', style: text.bodySmall),
          if (cautions.isNotEmpty) ...[
            const SizedBox(height: 10),
            if (!safe) _Note('Do not try this without a doctor.', danger: true),
            for (final c in cautions) Padding(padding: const EdgeInsets.only(top: 4), child: Text('• $c', style: text.bodySmall)),
          ],
        ]),
      ),
    );
  }

  Widget _stepCard(Trial t) {
    final text = Theme.of(context).textTheme;
    final d = t.decision;
    final photo = _lastPhoto[t.id];
    final children = <Widget>[];
    if (_busy != null) {
      children.addAll([const LinearProgressIndicator(), const SizedBox(height: 8), Text(_busy!)]);
    } else if (t.status == 'baseline' && !t.canStart) {
      children.addAll([
        Text('Baseline ${t.baselineScans + 1} of 2', style: text.titleMedium),
        const SizedBox(height: 6),
        const Text('Before any product: face a window, hair back, no makeup. Take the photo in the same place and light every time.'),
        const SizedBox(height: 12),
        FilledButton.icon(onPressed: _scan, icon: const Icon(Icons.photo_camera), label: const Text('Take baseline photo')),
      ]);
    } else if (t.canStart) {
      children.addAll([
        Text('Put the product on the shaded half only', style: text.titleMedium),
        const SizedBox(height: 10),
        Center(child: HalfShade(imageLeft: t.treatedOnImageLeft, photo: photo)),
        const SizedBox(height: 10),
        Text(d?['message'] ?? ''),
        const SizedBox(height: 12),
        FilledButton(onPressed: () => _run('Starting…', () => widget.api.start(t.id)), child: const Text('It\'s on: start the trial')),
      ]);
    } else if (t.status == 'running' || t.status == 'concluding') {
      children.addAll([
        Row(children: [
          Icon(Icons.auto_awesome, size: 18, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 6),
          Text('Agent', style: text.titleMedium),
        ]),
        const SizedBox(height: 6),
        Text(t.thinking ? 'Looking at the new scan…' : (d?['message'] ?? 'Take your first scan when the plan says.')),
        if (d?['next_scan_in_hours'] != null) Text('Next scan in ${d!['next_scan_in_hours']} h', style: text.bodySmall),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: FilledButton.icon(onPressed: _scan, icon: const Icon(Icons.photo_camera), label: const Text('Take a scan'))),
          const SizedBox(width: 8),
          OutlinedButton(onPressed: t.measured ? () => _run('The agent is writing the verdict…', () => widget.api.finish(t.id)) : null, child: const Text('Finish')),
        ]),
      ]);
    } else if (t.status == 'stopped') {
      children.addAll([
        const _Note('Stopped: the treated half got worse.', danger: true),
        Text(d?['message'] ?? 'Wash the product off. See a dermatologist if it stays.'),
        if (t.verdict == null) ...[
          const SizedBox(height: 12),
          OutlinedButton(onPressed: () => _run('The agent is writing the verdict…', () => widget.api.finish(t.id)), child: const Text('See the verdict')),
        ],
      ]);
    }
    if (_error != null) children.add(Padding(padding: const EdgeInsets.only(top: 8), child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error))));
    if (children.isEmpty) return const SizedBox.shrink();
    return Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children)));
  }

  Widget _verdictCard(Map<String, dynamic> v) {
    final text = Theme.of(context).textTheme;
    return Card(
      color: Theme.of(context).colorScheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Verdict', style: text.labelLarge),
          const SizedBox(height: 4),
          Text(v['headline'] ?? '', style: text.titleMedium),
          const SizedBox(height: 10),
          for (final c in v['claims'] ?? [])
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text.rich(TextSpan(children: [
                TextSpan(text: '"${c['claim']}"  ', style: const TextStyle(fontStyle: FontStyle.italic)),
                TextSpan(text: '${c['result']}', style: const TextStyle(fontWeight: FontWeight.w600)),
              ])),
            ),
          if ((v['next'] ?? '').toString().isNotEmpty) ...[const SizedBox(height: 6), Text(v['next'])],
        ]),
      ),
    );
  }

  Widget _concernCard(Map<String, dynamic> s) {
    final text = Theme.of(context).textTheme;
    final measured = s['state'] == 'measured';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text(s['label'] ?? s['concern'], style: text.titleMedium)),
            VerdictChip(measured ? s['verdict'] : null),
          ]),
          if (s['series'] != null) ...[
            const SizedBox(height: 10),
            EffectChart(stats: s),
            const SizedBox(height: 6),
            Text(
              'Your face\'s own difference: ${s['asymmetry']} · photo-to-photo noise: ${s['noise']}'
              '${measured ? ' · product effect: ${s['effect']} (counts past ±${s['threshold']})' : ''}',
              style: text.bodySmall,
            ),
          ] else
            Padding(padding: const EdgeInsets.only(top: 6), child: Text('Needs two baseline photos.', style: text.bodySmall)),
        ]),
      ),
    );
  }

  Widget _agentLog(Trial t) {
    if (t.agentLog.isEmpty) return const SizedBox.shrink();
    final text = Theme.of(context).textTheme;
    const jobs = {'plan': 'Planning', 'next_step': 'After a scan', 'verdict': 'Verdict'};
    return Card(
      child: ExpansionTile(
        leading: const Icon(Icons.auto_awesome),
        title: const Text('How the agent worked'),
        subtitle: Text('${t.agentLog.length} steps · numbers come only from YouCam and the trial math', style: text.bodySmall),
        children: [
          for (final s in t.agentLog)
            ListTile(
              dense: true,
              title: Text('${jobs[s['job']] ?? s['job']}: ${s['tool'] != null ? 'looked at ${s['tool']}' : s['rejected'] != null ? 'answer sent back' : 'answered'}'),
              subtitle: Text([s['thought'] ?? '', if (s['rejected'] != null) 'Why: ${s['rejected']}'].join('\n')),
            ),
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
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: danger ? scheme.errorContainer : scheme.secondaryContainer, borderRadius: BorderRadius.circular(10)),
      child: Text(text, style: TextStyle(color: danger ? scheme.onErrorContainer : scheme.onSecondaryContainer)),
    );
  }
}
