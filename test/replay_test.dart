import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shravelle_flutter/shravelle.dart';

void main() {
  testWidgets('wireframe has positioned boxes, colours and masked text', (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        appBar: AppBar(title: const Text('Checkout')),
        body: Column(children: [
          Container(width: 120, height: 40, decoration: BoxDecoration(color: const Color(0xFF635BFF), borderRadius: BorderRadius.circular(8))),
          const Text('Total 42 EUR', style: TextStyle(fontSize: 18, color: Color(0xFF111111))),
          SizedBox(width: 300, child: TextField(controller: TextEditingController(text: 'secret card'))),
          const ShravelleMask(child: Text('IBAN DE89')),
          const Opacity(opacity: 0, child: Text('Invisible99')),
        ]),
      ),
    ));
    final snap = ShravelleReplay.wireframe(tester.binding.renderViews.first, maskText: true);
    final json = jsonEncode(snap);
    expect(snap['w'], 400);
    expect(snap['h'], 800);
    expect(json, contains('background:rgba(99,91,255,1.00);border-radius:8px'));
    expect(json, contains('width:120.0px;height:40.0px'));
    expect(json, contains('"x":"***** ** ***"')); // "Total 42 EUR" masked
    expect(json, contains('"x":"****** ****"')); // text field always masked
    expect(json, contains('background:#9CA3AF')); // ShravelleMask
    expect(json, isNot(contains('Total')));
    expect(json, isNot(contains('secret')));
    expect(json, isNot(contains('IBAN')));

    final dump = Platform.environment['SHRAVELLE_REPLAY_DUMP'];
    if (dump != null) File(dump).writeAsStringSync(json);
    final open = ShravelleReplay.wireframe(tester.binding.renderViews.first, maskText: false);
    final o = jsonEncode(open);
    expect(o, contains('"x":"Total 42 EUR"'));
    expect(o, contains('"x":"Checkout"'));
    expect(o, contains('"x":"****** ****"')); // inputs stay masked
    expect(o, isNot(contains('IBAN'))); // masked widget stays a box
    expect(o, isNot(contains('Invisible99')), reason: 'opacity 0 is not drawn');
  });

  test('replay chunk payload', () {
    final p = ShravelleReplay.payload([{'k': 'c', 'x': 1, 'y': 2, 't': 1}]);
    for (final k in ['app', 'session_id', 'user_id', 'seq', 'start', 'end', 'page_url', 'has_error', 'clicks', 'rage_clicks', 'events']) {
      expect(p.containsKey(k), isTrue, reason: k);
    }
    expect((p['events'] as List).length, 1);
  });
}
