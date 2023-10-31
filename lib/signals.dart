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

class Owner {
  Owner? owner;
  List<Computation>? owned;
  List<void Function()>? cleanups;
  Map<Context, dynamic>? context;
  List<Dependency>? _sources;

  Owner({this.owner});

  List<Computation> useOwned() {
    owned ??= [];
    return owned!;
  }

  List<void Function()> useCleanups() {
    cleanups ??= [];
    return cleanups!;
  }

  List<Dependency> _useSources() {
    _sources ??= [];
    return _sources!;
  }

  (Context<T>, dynamic)? _findContext<T>(Context<T> context) {
    if (this.context != null) {
      if (this.context!.containsKey(context)) {
        return (context, this.context![context]);
      }
    }
    if (owner != null) {
      return owner!._findContext(context);
    }
    return null;
  }

  void _setContext<T>(Context<T> context, T value) {
    if (this.context == null) {
      this.context = {};
    }

    this.context![context] = value;
  }
}

Owner? _currentListener;

Owner? _currentOwner;

List<Computation>? _updates;

List<Computation>? _effects;

abstract class Computation extends Owner {
  bool get user;
  bool get pure;
  void run();
}

typedef EffectFn<Prev, Next extends Prev> = Next Function(Prev v);

typedef Accessor<T> = T Function();

class ComputeFn<Init, Next extends Init> extends Owner implements Computation {
  Init? value;
  final EffectFn<Init, Next> fn;
  @override
  final bool user;
  @override
  final bool pure;
  ComputeFn(this.fn, {this.value, this.user = false, this.pure = false}) {
    owner = _currentOwner;
  }

  @override
  void run() {
    value = fn(value as Init);
  }
}

T runWithOwner<T>(Owner? owner, Accessor<T> callback) {
  var oldOwner = _currentOwner;
  try {
    _currentOwner = owner;
    return callback();
  } finally {
    _currentOwner = oldOwner;
  }
}

void _execComputation(Computation compute) {
  final oldOwner = _currentOwner, oldListener = _currentListener;
  _currentOwner = compute;
  _currentListener = compute;
  try {
    compute.run();
  } catch (e) {
    rethrow;
  } finally {
    _currentOwner = oldOwner;
    _currentListener = oldListener;
  }
}

void _cleanNode(Owner node) {
  if (node._sources != null) {
    for (final source in node._sources!) {
      source.tracker.remove(node as Computation);
    }
    node._sources?.clear();
  }

  if (node.owned != null) {
    for (final owned in node.owned!) {
      _cleanNode(owned);
      node.owned = null;
    }
  }
}

void _runCleanups(Owner node) {
  final owneds = node.owned;
  if (owneds != null) {
    for (final owned in owneds) {
      _runCleanups(owned);
    }
  }

  final cleanups = node.cleanups;
  if (cleanups != null) {
    for (final f in cleanups) {
      f();
    }
  }
}

void _updateComputation(Computation computation) {
  _cleanNode(computation);
  _execComputation(computation);
}

T _runUpdates<T>(T Function() fn, [bool init = false]) {
  if (_updates != null) {
    return fn();
  }
  if (!init) _updates = [];
  final wait = _effects != null;
  if (!wait) {
    _effects = [];
  }
  try {
    final ret = fn();
    _completeUpdates(wait);
    return ret;
  } catch (e) {
    if (!wait) _effects = null;
    _updates = null;
    rethrow; // TODO: handle error correctly
  }
}

void _completeUpdates(bool wait) {
  if (_updates != null) {
    _runQueue();
    _updates = null;
  }
  if (wait) {
    return;
  }
  final e = _effects!;
  _effects = null;
  if (e.isNotEmpty) {
    _runUpdates(() => _runUserEffects(e));
  }
}

/// Execute user effects (compuations) in `queue`.
/// The `queue` will be modified in this function.
void _runUserEffects(List<Computation> queue) {
  var i = 0, userLength = 0;
  for (i = 0; i < queue.length; i++) {
    final e = queue[i];
    if (!e.user) {
      _updateComputation(e);
    } else {
      queue[userLength++] = e;
    }
  }
  for (i = 0; i < userLength; i++) {
    final e = queue[i];
    _updateComputation(e);
  }
}

void _runQueue() {
  for (final task in _updates!) {
    _updateComputation(task);
  }
}

class DependencyTracker {
  List<Computation> observers = [];

  bool tryTrack(Dependency dependency) {
    var listener = _currentListener;
    if (listener is Computation) {
      observers.add(listener);
      listener._useSources().add(dependency);
      return true;
    }
    return false;
  }

  void notify() {
    _runUpdates(() {
      for (final ob in observers) {
        if (ob.pure) {
          _updates!.add(ob);
        } else {
          _effects!.add(ob);
        }
      }
    });
  }

  void remove(Computation computation) {
    observers.remove(computation);
  }
}

abstract class Dependency {
  DependencyTracker get tracker;
}

class Signal<T> implements Dependency {
  T value;

  @override
  final tracker = DependencyTracker();

  Signal(this.value);

  T call() {
    tracker.tryTrack(this);
    return value;
  }

  void set(T newValue) {
    if (value != newValue) {
      this.value = newValue;
      tracker.notify();
    }
  }

  void apply(T Function(T old) transformer) {
    final oldValue = value;
    final newValue = transformer(oldValue);
    set(newValue);
  }

  void track() {
    tracker.tryTrack(this);
  }
}

class _RootComputation extends Owner implements Computation {
  void Function(RootDisposer dispose) scope;

  _RootComputation(this.scope, {super.owner});

  @override
  void run() {
    scope(dispose);
  }

  void dispose() {
    untrack(() {
      _cleanNode(this);
      _runCleanups(this);
    });
  }

  @override
  bool get user => false;

  @override
  bool get pure => false;
}

typedef RootDisposer = void Function();

void createRoot(void Function(RootDisposer) scope, {Owner? owner}) {
  _updateComputation(_RootComputation(scope, owner: owner));
}

T createRootAndReturn<T>(T Function(RootDisposer) scope, {Owner? owner}) {
  T? result;
  _updateComputation(_RootComputation((owner) {
    result = scope(owner);
  }, owner: owner));
  return result as T;
}

void createEffect<Next extends Init, Init>(EffectFn<Init, Next> fn,
    {Init? initial}) {
  if (null is! Init && initial == null) {
    throw TypeError();
  }
  final owner = _currentOwner;
  if (owner == null) {
    throw StateError("no owner found");
  }

  final computation = ComputeFn(fn, value: initial, user: true);
  if (_effects != null) {
    _effects!.add(computation);
  } else {
    _updateComputation(computation);
  }
}

void createRenderEffect<Next extends Init, Init>(EffectFn<Init, Next> fn,
    {Init? initial}) {
  if (null is! Init && initial == null) {
    throw TypeError();
  }
  final owner = _currentOwner;
  if (owner == null) {
    throw StateError("no owner found");
  }

  final computation = ComputeFn(fn, value: initial, user: true);
  if (_updates != null) {
    _updates!.add(computation);
  } else {
    _updateComputation(computation);
  }
}

T untrack<T>(Accessor<T> fn) {
  final oldListener = _currentListener;
  try {
    _currentListener = null;
    return fn();
  } finally {
    _currentListener = oldListener;
  }
}

void onMount(void Function() fn) {
  return createEffect((_) => untrack(fn));
}

void onCleanup(void Function() fn) {
  final owner = _currentOwner;
  if (owner == null) {
    throw StateError("no owner found");
  }

  owner.useCleanups().add(fn);
}

T batch<T>(T Function() fn) {
  return _runUpdates(fn, false);
}

Owner? getOwner() {
  return _currentOwner;
}

class Memo<T> extends Owner implements Computation, Dependency {
  var dirty = true;
  T? _cache;
  final Accessor<T> fn;
  @override
  final tracker = DependencyTracker();

  Memo(this.fn) {
    owner = _currentOwner;
    assert(owner != null, "Memo should be created inside `createRoot`");
    owner!.useOwned().add(this);
  }

  T call() {
    if (dirty) {
      _runUpdates(() {
        _updates!.add(this);
      });
    }
    tracker.tryTrack(this);
    return _cache as T;
  }

  void update() {
    final value = fn();
    if (value != _cache) {
      _cache = value;
      tracker.notify();
    }
    dirty = false;
  }

  @override
  void run() {
    dirty = true;
    update();
  }

  @override
  bool get user => true;

  @override
  bool get pure => true;

  void track() {
    tracker.tryTrack(this);
  }
}

class Context<T> {
  final T defaultValue;

  const Context(this.defaultValue);

  T find({Owner? owner}) {
    owner ??= _currentOwner;
    final ret = owner?._findContext<T>(this);
    if (ret == null) {
      return defaultValue;
    }
    final (_, value) = ret;
    return value as T;
  }

  void set(T value, {Owner? owner}) {
    owner ??= _currentOwner;
    owner?._setContext(this, value);
  }

  R provide<R>(T value, R Function() scope) {
    final owner = Owner(owner: _currentOwner);
    set(value, owner: owner);
    return runWithOwner(owner, scope);
  }
}
