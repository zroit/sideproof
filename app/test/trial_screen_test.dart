import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sideproof/api.dart';
import 'package:sideproof/trial_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// trial_fixture.json is a finished dev trial as the backend returns it (numbers only).
Map<String, dynamic> fixture() => jsonDecode(File('test/trial_fixture.json').readAsStringSync());

Future<void> show(WidgetTester tester, Map<String, dynamic> json) async {
  SharedPreferences.setMockInitialValues({});
  final api = await Api.open();
  await tester.binding.setSurfaceSize(const Size(420, 2400));
  await tester.pumpWidget(MaterialApp(home: TrialScreen(api: api, trialId: json['id'], initial: Trial(json))));
  await tester.pump();
}

void main() {
  testWidgets('a finished trial shows the verdict, each concern and the agent steps', (tester) async {
    await show(tester, fixture());
    expect(find.text('Verdict'), findsOneWidget);
    expect(find.text('Oiliness'), findsOneWidget);
    expect(find.text('Better'), findsWidgets);
    await tester.scrollUntilVisible(find.text('How the agent worked'), 400);   // the list builds lazily
    expect(find.text('How the agent worked'), findsOneWidget);
  });

  testWidgets('a running trial offers a scan and shows what the agent said', (tester) async {
    final json = fixture()
      ..['status'] = 'running'
      ..['verdict'] = null
      ..['decision'] = {'state': 'done', 'action': 'continue', 'message': 'Scan again tomorrow.', 'next_scan_in_hours': 24, 'allowed': ['continue']};
    await show(tester, json);
    expect(find.text('Scan again tomorrow.'), findsOneWidget);
    expect(find.text('Take a scan'), findsOneWidget);
    expect(find.text('Next scan in 24 h'), findsOneWidget);
  });

  testWidgets('after two baselines it shows which half gets the product', (tester) async {
    final json = fixture()
      ..['status'] = 'baseline'
      ..['verdict'] = null
      ..['decision'] = {'state': 'done', 'action': 'start', 'message': 'Baseline done.', 'allowed': ['start', 'another_baseline']};
    await show(tester, json);
    expect(find.text('Put the product on the shaded half only'), findsOneWidget);
    expect(find.text('It\'s on: start the trial'), findsOneWidget);
  });
}
