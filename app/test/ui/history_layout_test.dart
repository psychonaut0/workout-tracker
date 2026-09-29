import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:workout_tracker/data/models.dart';
import 'package:workout_tracker/data/session_repository.dart';
import 'package:workout_tracker/ui/history_screen.dart';
import 'package:workout_tracker/units/unit_service.dart';
import 'package:workout_tracker/util/dates.dart';

import '../support/app_fonts.dart';
import '../support/l10n_harness.dart';
import '../support/layout_expect.dart';
import '../support/pump_until.dart';
import '../support/screen_harness.dart';

class _NoSets implements SessionRepository {
  @override
  Future<List<LoggedSet>> setsForSession(String sessionId) =>
      Future.value(const []);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  setUpAll(() async {
    await initializeDateFormatting();
    await preloadAppFonts();
  });

  testWidgets('a session card holds at 320dp and 2.0x (PR badge, long name)',
      (tester) async {
    tester.view.physicalSize = const Size(320, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final yesterday =
        isoDate(DateTime.now().subtract(const Duration(days: 1)));
    await tester.pumpWidget(MediaQuery(
      data: const MediaQueryData(
          size: Size(320, 900), textScaler: TextScaler.linear(2.0)),
      child: wrapL10n(SingleChildScrollView(
        child: SessionCard(
          session: HistorySessionRow(
            id: 'S', date: yesterday,
            splitLabel: 'Oberkörper Schwerpunkt Brust & Schultern · Brust',
            durationMin: 71, exerciseCount: 4, prCount: 1, tonnageKg: 5000,
          ),
          catalogMap: const {},
          sessionRepo: _NoSets(),
          units: UnitService(),
        ),
      )),
    ));
    expect(tester.takeException(), isNull);
    expectNoSplitWords(tester, within: find.byType(SessionCard));
  });

  group('HistoryScreen', () {
    final harness = ScreenHarness();
    tearDown(harness.close);

    testWidgets('week header, cards and 4-week summary hold at 320dp, 2.0x',
        (tester) async {
      await harness.open(tester);
      setPhone(tester, width: 320, textScale: 2.0);
      await tester.pumpWidget(
          harness.wrap(const Scaffold(body: HistoryScreen())));
      await pumpUntilFound(tester, find.byType(SessionCard));
      await settleReal(tester, ticks: 5);
      expectLayoutHolds(tester, 'History 320dp 2.0x');
      await harness.unmount(tester);
    });
  });
}
