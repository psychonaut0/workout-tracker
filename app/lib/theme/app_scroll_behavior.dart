import 'package:flutter/material.dart';

/// App-wide scroll behavior with NO overscroll indicator.
///
/// Every Scaffold is transparent (the AmbientLayer paints the background via
/// `MaterialApp.builder`). Android's default stretch overscroll captures a
/// scrollable's OWN paint layer and stretches it — but near a list's edges that
/// layer is transparent, so the stretch shader samples transparent pixels and
/// composites them as a persistent gray box (it lingers because the calm
/// ambient layer isn't forcing repaints). A `ColoredBox` *behind* the list
/// can't fix this: the stretched layer is the list's own.
///
/// Returning the child unchanged from [buildOverscrollIndicator] removes the
/// stretch/glow entirely, eliminating the artifact across every list in the
/// app. Scrollbars and physics are unaffected.
class AppScrollBehavior extends MaterialScrollBehavior {
  const AppScrollBehavior();

  @override
  Widget buildOverscrollIndicator(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) =>
      child;
}
