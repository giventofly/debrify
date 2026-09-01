import 'package:flutter/widgets.dart';

/// Adapts a post-removal `(from, to)` move handler to [ReorderCallback], the
/// contract `ReorderableListView.onReorder` expects.
///
/// **Why the app targets `onReorder` and not `onReorderItem`.** The webOS
/// Flutter SDK (`flutter-webos`) is pinned to Flutter 3.38, which predates
/// `onReorderItem`. `onReorder` exists on both 3.38 and 3.44, so writing to it
/// keeps one code path compiling on every toolchain we ship from. It is
/// deprecated on 3.44 (after v3.41.0-0.0.pre) — that is deliberate, and this is
/// the reason. See `WEBOS_IPK_PLAN.md` §6.
///
/// **The off-by-one this exists to absorb.** `onReorder` reports `newIndex`
/// computed *before* the dragged item is lifted out of the list, so dragging an
/// item downward overshoots by one. Every move handler in this app is written
/// against post-removal indices:
///
/// ```dart
/// final item = list.removeAt(from);
/// list.insert(to, item);
/// ```
///
/// which is exactly what `onReorderItem` supplies and what this adapter
/// reconstructs. Flutter's own deprecation notice says as much: *"The
/// onReorderItem callback adjusts the newIndex parameter for a removed item at
/// the oldIndex."*
///
/// An end-of-list drop arrives as `newIndex == length`; the adjustment brings it
/// back to `length - 1`, inside the range every handler already guards for.
ReorderCallback postRemovalReorder(void Function(int from, int to) onMove) {
  return (int oldIndex, int newIndex) {
    onMove(oldIndex, newIndex > oldIndex ? newIndex - 1 : newIndex);
  };
}
