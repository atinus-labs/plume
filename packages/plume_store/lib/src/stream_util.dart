import 'dart:async';

extension SwitchMap<T> on Stream<T> {
  /// Maps each event to a stream and forwards the events of the most recent
  /// one, cancelling the previous inner stream. Completes when this stream and
  /// the current inner stream are both done.
  Stream<R> switchMap<R>(Stream<R> Function(T value) convert) {
    late final StreamController<R> controller;
    StreamSubscription<T>? outer;
    StreamSubscription<R>? inner;
    var outerDone = false;

    void listenInner(T value) {
      final previous = inner;
      inner = null;
      if (previous != null) unawaited(previous.cancel());
      final Stream<R> stream;
      try {
        stream = convert(value);
      } catch (e, s) {
        controller.addError(e, s);
        return;
      }
      late final StreamSubscription<R> sub;
      sub = stream.listen(
        controller.add,
        onError: controller.addError,
        onDone: () {
          if (inner == sub) inner = null;
          if (outerDone && inner == null) unawaited(controller.close());
        },
      );
      inner = sub;
      if (controller.isPaused) sub.pause();
    }

    controller = StreamController<R>(
      sync: true,
      onListen: () {
        outer = listen(
          listenInner,
          onError: controller.addError,
          onDone: () {
            outerDone = true;
            if (inner == null) unawaited(controller.close());
          },
        );
      },
      onPause: () {
        outer?.pause();
        inner?.pause();
      },
      onResume: () {
        outer?.resume();
        inner?.resume();
      },
      onCancel: () async {
        final futures = [outer?.cancel(), inner?.cancel()].nonNulls;
        outer = null;
        inner = null;
        await Future.wait(futures);
      },
    );
    return controller.stream;
  }
}
