/* Copyright 2023 Rubicon Rowe

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
*/
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fruit/widgets.dart';
import 'package:fruit/signals.dart';

class CounterWidget extends FruitWidget {
  final counter = Signal(0);

  CounterWidget({super.key}) {
    Timer? timer;

    onMount(() {
      timer = Timer.periodic(const Duration(seconds: 1),
          (timer) => counter.apply((old) => old + 1));
    });

    onCleanup(() {
      if (timer != null) {
        timer!.cancel();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Text("Counter: ${counter()}");
  }
}

void main() {
  testWidgets("Counter can tick", (widgetTester) async {
    await widgetTester.pumpWidget(
      MaterialApp(
        home: createRootAndReturn((_) => CounterWidget()),
      )
      
    );
    await widgetTester.pump(const Duration(seconds: 2));
    final finder = find.byType(CounterWidget);
    expect(finder, findsOneWidget);
    final element = finder.first.evaluate().first;
    assert(element is FruitElement);
    final widget = element.widget;
    assert(widget is CounterWidget);
    assert((widget as CounterWidget).counter() != 0);
  });
}
