import 'package:flutter/widgets.dart';

import 'ruler_picker.dart';

/// Commits every in-flight edit synchronously, before a control acts on the
/// values being edited: a focused text field (its commit-on-focus-loss runs
/// now, not in a later microtask) and any ruler still gliding after a fling
/// (stopped on the value it shows).
///
/// On Android a tap on a non-text widget neither drops focus nor stops a
/// scroll, so without this the action reads — or the glide later
/// overwrites — a value other than the one on screen.
void commitPendingInput() {
  FocusManager.instance.primaryFocus?.unfocus();
  FocusManager.instance.applyFocusChangesIfNeeded();
  RulerPicker.settleAll();
}
