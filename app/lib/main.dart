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
  late final Future<Trial> _demo = widget.api.demo();

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
            const SizedBox(height: 14),
            Container(
              decoration: BoxDecoration(color: scheme.surfaceContainerLowest, borderRadius: BorderRadius.circular(28)),
              padding: const EdgeInsets.all(8),
              child: const AspectRatio(aspectRatio: 1.25, child: _HeroFace()),
            ),
            const SizedBox(height: 22),
            Text('Did it work, or was it the weather?', style: text.headlineMedium),
            const SizedBox(height: 10),
            Text(
              'Put a skincare product on one half of your face and leave the other half alone. '
              'YouCam Skin AI measures both halves, so whatever differs is the product.',
              style: text.bodyLarge?.copyWith(height: 1.45, color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 22),
            FilledButton.icon(onPressed: _startTrial, icon: const Icon(Icons.add), label: const Text('Start a trial')),
            const SizedBox(height: 18),
            FutureBuilder<Trial>(
              future: _demo,
              builder: (context, snap) => snap.hasData
                  ? _DemoCard(trial: snap.data!, onTap: () => _open(TrialScreen(api: widget.api, demo: true)))
                  : const SizedBox.shrink(),
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

/// The home picture: on first load a drop lands on one cheek and that half takes the colour.
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

/// The recorded demo trial, so a first-time visitor sees a result before starting their own.
class _DemoCard extends StatelessWidget {
  const _DemoCard({required this.trial, required this.onTap});
  final Trial trial;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final measured = trial.concerns.values.where((c) => c['state'] == 'measured').toList();
    final first = measured.isEmpty ? null : measured.first as Map<String, dynamic>;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text('See a finished trial', style: text.titleMedium)),
              const Icon(Icons.chevron_right),
            ]),
            const SizedBox(height: 4),
            Text(
              '${trial.product} on YouCam\'s sample face, with a digital matte filter playing the product.',
              style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
            ),
            if (first != null) ...[
              const SizedBox(height: 12),
              Row(children: [
                Text(first['label'] ?? first['concern'], style: text.labelLarge),
                const SizedBox(width: 8),
                VerdictChip(first['verdict']),
              ]),
              const SizedBox(height: 6),
              SizedBox(height: 96, child: EffectChart(stats: first, compact: true)),
            ],
          ]),
        ),
      ),
    );
  }
}
