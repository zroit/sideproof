import 'dart:ui' show ImageFilter;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'api.dart';
import 'brand.dart';
import 'explainer.dart';
import 'new_trial.dart';
import 'theme.dart';
import 'trial_screen.dart';
import 'widgets.dart';

void main() => runApp(const SideProofApp());

class SideProofApp extends StatelessWidget {
  const SideProofApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SideProof',
      debugShowCheckedModeBanner: false,
      theme: spTheme(Brightness.light),
      darkTheme: spTheme(Brightness.dark),
      home: FutureBuilder<Api>(
        future: Api.open(),
        builder: (context, snap) => snap.hasData ? HomeScreen(api: snap.data!) : const Scaffold(body: Center(child: CircularProgressIndicator())),
      ),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.api});
  final Api api;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late Future<List<dynamic>> _trials = widget.api.trials();
  late final Future<List<Trial>> _demos = widget.api.demos();
  int? _pick, _pickPromise;

  @override
  void initState() {
    super.initState();
    // A shop's trial link (?product=CODE) opens straight into that product's trial.
    final code = kIsWeb ? Uri.base.queryParameters['product'] : null;
    if (code != null && code.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _startTrial(code: code));
    }
  }

  Future<void> _open(Widget screen) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => screen));
    setState(() => _trials = widget.api.trials());
  }

  /// The first trial starts with the explainer, so nobody puts a product on before they know why.
  Future<void> _startTrial({String? code}) async {
    if (!await ExplainerScreen.seen()) {
      if (!mounted) return;
      final ok = await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => const ExplainerScreen(doneLabel: 'Start my trial')));
      if (ok != true) return;
    }
    await _open(NewTrialScreen(api: widget.api, code: code));
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: SafeArea(
        child: Column560(
          child: ListView(padding: const EdgeInsets.fromLTRB(20, 12, 20, 32), children: [
            Row(children: [
              const Wordmark(size: 20),
              const Spacer(),
              TextButton(onPressed: () => _open(const ExplainerScreen()), child: const Text('How it works')),
            ]),
            const SizedBox(height: 18),
            Text.rich(TextSpan(style: display(40, color: Sp.ink), children: [
              const TextSpan(text: 'Did it '),
              WidgetSpan(
                alignment: PlaceholderAlignment.baseline,
                baseline: TextBaseline.alphabetic,
                child: ShimmerText('work', style: display(40, color: Sp.ink, italic: true)),
              ),
              const TextSpan(text: ', or was it the weather?'),
            ])),
            const SizedBox(height: 12),
            Text(
              'Put a skincare product on one half of your face and leave the other half alone. '
              'YouCam Skin AI measures both halves, so whatever differs is the product.',
              style: text.bodyLarge?.copyWith(height: 1.5, color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 20),
            GradientButton(onPressed: _startTrial, icon: Icons.add, label: 'Start a trial'),
            const SizedBox(height: 16),
            const Wrap(spacing: 8, runSpacing: 8, children: [
              ChromeChip('YouCam AI Skin Analysis'),
              ChromeChip('AI Skin Simulation'),
              ChromeChip('AI Fitzpatrick Skin Type'),
            ]),
            const SizedBox(height: 28),
            FutureBuilder<List<Trial>>(
              future: _demos,
              builder: (context, snap) {
                final demos = snap.data ?? const <Trial>[];
                if (demos.isEmpty) {
                  return Container(
                    decoration: BoxDecoration(color: scheme.surfaceContainerLowest, borderRadius: BorderRadius.circular(28)),
                    padding: const EdgeInsets.all(8),
                    child: const AspectRatio(aspectRatio: 1.25, child: _HeroFace()),
                  );
                }
                // The hero opens on a trial whose claim came out supported; the promise on another,
                // so both faces show at first glance.
                final supported = demos.indexWhere((d) => d.concerns.values.any((c) => c['verdict'] == 'better'));
                final hero = _pick ?? (supported < 0 ? 0 : supported);
                final promise = _pickPromise ?? (demos.length > 1 ? (hero + 1) % demos.length : 0);
                return _DemoShowcase(
                  api: widget.api,
                  demos: demos,
                  pick: hero,
                  promisePick: promise,
                  onPick: (i) => setState(() => _pick = i),
                  onPromisePick: (i) => setState(() => _pickPromise = i),
                  onOpen: (id) => _open(TrialScreen(api: widget.api, demo: true, demoId: id)),
                );
              },
            ),
            const SizedBox(height: 26),
            Text('Your trials', style: text.titleLarge),
            const SizedBox(height: 6),
            FutureBuilder<List<dynamic>>(
              future: _trials,
              builder: (context, snap) {
                if (snap.hasError) {
                  return Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: Text('Could not load your trials: ${snap.error}'));
                }
                if (!snap.hasData) return const Padding(padding: EdgeInsets.all(16), child: LinearProgressIndicator());
                if (snap.data!.isEmpty) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Text('Your trials will show here. A trial takes a day for fast products, up to four weeks for slow ones.', style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant)),
                  );
                }
                return Column(children: [
                  for (final t in snap.data!)
                    Card(
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                        leading: const SideProofMark(size: 26),
                        title: Text(t['product'], style: text.titleMedium),
                        subtitle: Text(statusWords(t['status'])),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => _open(TrialScreen(api: widget.api, trialId: t['id'])),
                      ),
                    ),
                ]);
              },
            ),
            const SizedBox(height: 28),
            Row(children: [
              Icon(Icons.lock_outline, size: 16, color: scheme.onSurfaceVariant),
              const SizedBox(width: 6),
              Expanded(child: Text('Photos are measured and dropped. Only the numbers are kept.', style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant))),
            ]),
          ]),
        ),
      ),
    );
  }
}

/// The finished demo trials on real faces: YouCam's map split at the midline with each half's
/// share, then the claims' promise against the measured proof.
class _DemoShowcase extends StatelessWidget {
  const _DemoShowcase({required this.api, required this.demos, required this.pick, required this.promisePick, required this.onPick, required this.onPromisePick, required this.onOpen});
  final Api api;
  final List<Trial> demos;
  final int pick, promisePick;
  final ValueChanged<int> onPick, onPromisePick;
  final ValueChanged<String> onOpen;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final d = demos[pick.clamp(0, demos.length - 1)];
    final m = d.media ?? const {};
    final photos = (m['photos'] as Map?) ?? const {};
    final overlays = ((m['overlays'] as Map?)?['latest'] as Map?) ?? const {};
    final line = (m['midline'] as List?) ?? const [[0.5, 0], [0.5, 1]];
    final midline = [(line[0][0] as num).toDouble(), (line[1][0] as num).toDouble()];
    String url(String name) => api.url('/demo-media/$name');
    final claimed = [for (final c in d.plan['claims'] ?? const []) if (c['concern'] != null) c['concern'] as String];
    final shown = d.concerns.entries.where((e) => claimed.contains(e.key) && overlays.containsKey(e.key)).map((e) => e.value as Map<String, dynamic>).firstOrNull;
    final series = (shown?['series'] as List?) ?? const [];
    final last = series.isEmpty ? null : series.last as Map<String, dynamic>;
    final hours = series.isEmpty ? 0 : (last!['hours'] as num).toDouble();
    final span = hours >= 48 ? '${(hours / 24).round()} days' : '${hours.round()} hours';

    final p = demos[promisePick.clamp(0, demos.length - 1)];
    final pm = p.media ?? const {};
    final pphotos = (pm['photos'] as Map?) ?? const {};
    final pclaimed = [for (final c in p.plan['claims'] ?? const []) if (c['concern'] != null) c['concern'] as String];
    final pshown = p.concerns.entries.where((e) => pclaimed.contains(e.key) && ((e.value as Map)['series'] as List?)?.isNotEmpty == true).map((e) => e.value as Map<String, dynamic>).firstOrNull;
    Widget chips(int current, ValueChanged<int> choose) => SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(children: [
            for (var i = 0; i < demos.length; i++)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  selected: i == current,
                  onSelected: (_) => choose(i),
                  avatar: ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: Image.network(url(((demos[i].media?['photos'] as Map?)?['latest']) ?? ''), width: 24, height: 24, fit: BoxFit.cover, errorBuilder: (_, _, _) => const SizedBox(width: 24)),
                  ),
                  label: Text(demos[i].product),
                ),
              ),
          ]),
        );

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('See finished trials', style: text.titleLarge),
      const SizedBox(height: 10),
      if (demos.length > 1) chips(pick, onPick),
      const SizedBox(height: 10),
      if (photos['latest'] != null)
        GestureDetector(
          onTap: () => onOpen(d.id),
          // The demo photos are 3:4, so the card holds its place while they load.
          child: ClipRRect(
            borderRadius: BorderRadius.circular(22),
            child: AspectRatio(
              aspectRatio: 3 / 4,
              child: Stack(fit: StackFit.expand, children: [
                const ColoredBox(color: Sp.sunk),
                SplitPhoto(
                  key: ValueKey(d.id),
                  photo: NetworkImage(url(photos['latest'])),
                  overlay: shown == null ? null : NetworkImage(url(overlays[shown['concern']])),
                  midline: midline,
                  treatedLeft: d.treatedOnImageLeft,
                ),
                if (shown != null && last != null) Positioned(left: 12, right: 12, bottom: 12, child: _GlassResult(key: ValueKey('glass-${d.id}'), stats: shown, last: last)),
              ]),
            ),
          ),
        ),
      const SizedBox(height: 8),
      Text(
        '${shown == null ? '' : 'YouCam\'s ${(shown['label'] as String).toLowerCase()} map $span in: the share of each half YouCam marked. '}${m['note'] ?? ''}',
        style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant, height: 1.4),
      ),
      const SizedBox(height: 10),
      OutlinedButton(onPressed: () => onOpen(d.id), child: const Text('Open this trial')),
      if (pphotos['promise'] != null && pphotos['baseline'] != null) ...[
        const SizedBox(height: 30),
        const AccentTitle('The ', 'promise', ', then the proof', color: Sp.lilac),
        const SizedBox(height: 6),
        Text('YouCam AI Skin Simulation draws what the claims promise on this face. Drag to compare.', style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant, height: 1.4)),
        const SizedBox(height: 10),
        if (demos.length > 1) chips(promisePick, onPromisePick),
        const SizedBox(height: 10),
        CompareSlider(
          key: ValueKey('promise-${p.id}'),
          before: NetworkImage(url(pphotos['baseline'])),
          after: NetworkImage(url(pphotos['promise'])),
          beforeLabel: 'Before',
          afterLabel: 'The promise',
          closeUp: closeUpFor(pclaimed, p.treatedOnImageLeft),
        ),
        if (pshown != null) ...[
          const SizedBox(height: 16),
          Row(children: [
            Expanded(child: Text('${pshown['label']}, treated half against control', style: text.titleMedium)),
            VerdictChip(pshown['verdict']),
          ]),
          const SizedBox(height: 8),
          EffectChart(stats: pshown),
          const SizedBox(height: 10),
          OutlinedButton(onPressed: () => onOpen(p.id), child: const Text('Open this trial')),
        ],
      ],
    ]);
  }
}

/// The hero's result on frosted glass: how much less of the concern the treated half has, the
/// verdict, and each half's share. It slides up from the photo's edge once.
class _GlassResult extends StatelessWidget {
  const _GlassResult({super.key, required this.stats, required this.last});
  final Map<String, dynamic> stats, last;

  @override
  Widget build(BuildContext context) {
    final control = (last['control'] as num).toDouble(), treated = (last['treated'] as num).toDouble();
    final label = stats['label'] as String;
    final headline = stats['verdict'] == 'better' && control > 0 ? '${((1 - treated / control) * 100).round()}% less ${label.toLowerCase()}' : label;
    Widget half(String text, bool isTreated) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(color: isTreated ? null : Sp.sunk, gradient: isTreated ? Sp.cta : null, borderRadius: BorderRadius.circular(12)),
          child: Text(text, style: body(12.5, weight: 700, color: isTreated ? Colors.white : Sp.ink)),
        );
    final still = MediaQuery.of(context).disableAnimations;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: still ? 1 : 0, end: 1),
      duration: const Duration(milliseconds: 1100),
      curve: const Interval(0.35, 1, curve: Curves.easeOutCubic),
      builder: (context, v, child) => FractionalTranslation(translation: Offset(0, 1.4 * (1 - v)), child: child),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
          child: Container(
            color: Colors.white.withValues(alpha: 0.84),
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(children: [
                Expanded(child: Text(headline, style: display(26, color: Sp.ink, height: 1))),
                const SizedBox(width: 8),
                VerdictChip(stats['verdict']),
              ]),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(child: half('Control ${control.toStringAsFixed(1)}%', false)),
                const SizedBox(width: 6),
                Expanded(child: half('Treated ${treated.toStringAsFixed(1)}%', true)),
              ]),
            ]),
          ),
        ),
      ),
    );
  }
}

/// While the demos load: the face drawing takes the product.
class _HeroFace extends StatefulWidget {
  const _HeroFace();

  @override
  State<_HeroFace> createState() => _HeroFaceState();
}

class _HeroFaceState extends State<_HeroFace> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1800));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.of(context).disableAnimations) {
      _c.value = 1;
    } else if (_c.value == 0) {
      _c.forward();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        final t = _c.value;
        return CustomPaint(
          painter: FaceScene(
            line: scheme.onSurface.withValues(alpha: 0.78),
            treated: Sp.treated(context),
            control: Sp.control(context),
            drop: (t / 0.4).clamp(0, 1),
            tint: t > 0.4 ? 1 : 0,
            spread: ((t - 0.4) / 0.6).clamp(0, 1),
          ),
        );
      },
    );
  }
}
