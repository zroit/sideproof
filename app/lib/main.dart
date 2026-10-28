import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'api.dart';
import 'new_trial.dart';
import 'trial_screen.dart';

void main() => runApp(const HalfFaceApp());

class HalfFaceApp extends StatelessWidget {
  const HalfFaceApp({super.key});

  @override
  Widget build(BuildContext context) {
    ThemeData theme(Brightness b) => ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF7A4BD0), brightness: b),
          useMaterial3: true,
          cardTheme: const CardThemeData(margin: EdgeInsets.symmetric(vertical: 6)),
        );
    return MaterialApp(
      title: 'HalfFace',
      debugShowCheckedModeBanner: false,
      theme: theme(Brightness.light),
      darkTheme: theme(Brightness.dark),
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

  @override
  void initState() {
    super.initState();
    // A shop's trial link (?product=CODE) opens straight into that product's trial.
    final code = kIsWeb ? Uri.base.queryParameters['product'] : null;
    if (code != null && code.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _open(NewTrialScreen(api: widget.api, code: code)));
    }
  }

  Future<void> _open(Widget screen) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => screen));
    setState(() => _trials = widget.api.trials());
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('HalfFace')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Text('Is it working?\nTest it on half your face.', style: text.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        Text(
          'Put a product on one half of your face and leave the other half as it is. YouCam Skin AI measures both halves; '
          'light, sleep and weather hit both alike, so what is left is the product.',
          style: text.bodyMedium,
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: () => _open(NewTrialScreen(api: widget.api)),
          icon: const Icon(Icons.add),
          label: const Text('Start a trial'),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: () => _open(TrialScreen(api: widget.api, demo: true)),
          icon: const Icon(Icons.play_circle_outline),
          label: const Text('Open the demo trial'),
        ),
        const SizedBox(height: 24),
        Text('Your trials', style: text.titleMedium),
        FutureBuilder<List<dynamic>>(
          future: _trials,
          builder: (context, snap) {
            if (snap.hasError) return Padding(padding: const EdgeInsets.all(8), child: Text('${snap.error}'));
            if (!snap.hasData) return const Padding(padding: EdgeInsets.all(16), child: LinearProgressIndicator());
            if (snap.data!.isEmpty) return const Padding(padding: EdgeInsets.all(8), child: Text('None yet.'));
            return Column(children: [
              for (final t in snap.data!)
                Card(
                  child: ListTile(
                    title: Text(t['product']),
                    subtitle: Text(t['status']),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => _open(TrialScreen(api: widget.api, trialId: t['id'])),
                  ),
                ),
            ]);
          },
        ),
        const SizedBox(height: 24),
        Text('Photos are measured and dropped. Only numbers are kept.', style: text.bodySmall, textAlign: TextAlign.center),
      ]),
    );
  }
}
