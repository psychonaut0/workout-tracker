/// What the shell should do with an Android back press.
enum BackAction { none, goHome, exit }

/// Priority: a tab that consumed the press wins; otherwise non-home tabs go
/// home; home exits the app.
BackAction decideBack({required bool tabHandled, required int tabIndex}) {
  if (tabHandled) return BackAction.none;
  return tabIndex == 0 ? BackAction.exit : BackAction.goHome;
}
