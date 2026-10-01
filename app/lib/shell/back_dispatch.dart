/// What the shell should do with an Android back press.
enum BackAction { none, goHome, exit, confirmExit }

/// Priority: a tab that consumed the press wins; otherwise non-home tabs go
/// home; home exits the app, or first asks to discard a Plan editor's
/// unsaved edits ([planEditsAtRisk]), which the exit would lose.
BackAction decideBack({
  required bool tabHandled,
  required int tabIndex,
  required bool planEditsAtRisk,
}) {
  if (tabHandled) return BackAction.none;
  if (tabIndex != 0) return BackAction.goHome;
  return planEditsAtRisk ? BackAction.confirmExit : BackAction.exit;
}
