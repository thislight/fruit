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
library fruit;

import 'package:flutter/widgets.dart';
import 'package:fruit/signals.dart';

@immutable
abstract class FruitWidget extends Widget {
  late final Owner? capturedOwner;
  FruitWidget({super.key}) {
    capturedOwner = getOwner();
  }

  @override
  Element createElement() {
    return FruitElement(this);
  }

  FruitState<FruitWidget> createState();
}

const _buildContextCx = Context<BuildContext?>(null);

class FruitElement extends ComponentElement {
  // Fields below available after mount()
  late Memo<Widget> cachedBuild;
  late FruitState state;
  late Owner reactiveOwner;
  late RootDisposer disposer;
  FruitElement(super.widget);

  void _trackCachedBuild(_) {
    cachedBuild.track();
    markNeedsBuild();
  }

  void _lazyInit() {
    createRoot((dispose) {
      disposer = dispose;
      reactiveOwner = getOwner()!;
      _buildContextCx.set(this);
      state = typedWidget.createState();
      cachedBuild = Memo(() {
        return state.build(this);
      });
    }, owner: typedWidget.capturedOwner);
  }

  @override
  void mount(Element? parent, Object? newSlot) {
    _lazyInit();
    super.mount(parent, newSlot);
    runWithOwner(reactiveOwner, () {
      createRenderEffect(_trackCachedBuild);
    });
  }

  @override
  void update(covariant Widget newWidget) {
    super.update(newWidget);
    disposer();
    _lazyInit();
    runWithOwner(reactiveOwner, () {
      createRenderEffect(_trackCachedBuild);
    });
  }

  @override
  void unmount() {
    super.unmount();
    disposer();
  }

  FruitWidget get typedWidget => widget as FruitWidget;

  @override
  Widget build() {
    return untrack<Widget>(cachedBuild);
  }
}

abstract class FruitState<T extends FruitWidget> {
  T widget;

  FruitState(this.widget);

  Widget build(BuildContext context);

  BuildContext useBuildContext() {
    return _buildContextCx.find()!;
  }
}
