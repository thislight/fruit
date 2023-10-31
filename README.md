# Experimental UI data management for Flutter
Experimental breathe-taking UI data management for Flutter. This package is an experiment.

## Features

- [x] Basic primitives
    - `createRoot`, `untrack`, `batch`
    - `Signal` and `Memo`
    - `createRenderEffect`, `createEffect`
    - `onMount` and `onCleanup`
- [ ] Handle errors
- [ ] `Resource`

## Getting started

Download this repository and use as dependency.

## Usage


```dart
import 'package:flutter/material.dart';
import 'package:fruit/signals.dart';
import 'package:fruit/widgets.dart';

class Clock extends FruitWidget {
  final Duration offset;
  Clock(this.offset, {super.key});

  @override
  FruitState<FruitWidget> createState() {
    return ClockState(this);
  }
}

class ClockState extends FruitState<Clock> {
  final time = Signal(DateTime.now());

  ClockState(super.widget) {
    Timer? timer;

    onMount(() {
      timer = Timer.periodic(const Duration(seconds: 1), (timer) {
        time.set(DateTime.now());
      });
    });

    onCleanup(() {
      timer?.cancel();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [Text("Offset: ${widget.offset}"), Text(time().toIso8601String())],
    );
  }
}
```

## Known Behaviour

- After the widget reconstructed, the effects will be executed again.
    - That's expected behaviour because we reinitialised the element when the widget changed.
    - The key is the widget is not integrated within the reactive system, so the effects could not automatically notified when an exact value is changed.

## License

```
Copyright 2023 Rubicon Rowe

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.

```
