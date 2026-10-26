import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fdr_security_deposit/main.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> pumpShell(
    WidgetTester tester,
    PortalState state,
    Size size,
  ) async {
    await tester.binding.setSurfaceSize(size);
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(useMaterial3: true),
        builder: (context, child) =>
            applyPortalTextScale(context, child ?? const SizedBox.shrink()),
        home: PortalShell(state: state),
      ),
    );
    await tester.pumpAndSettle();
  }

  final sizes = <String, Size>{
    'desktop': const Size(1440, 1000),
    'laptop': const Size(1180, 800),
    'tablet': const Size(900, 1000),
  };

  for (final entry in sizes.entries) {
    testWidgets('all role dashboards lay out at ${entry.key}', (tester) async {
      final state = PortalState();
      for (final role in UserRole.values) {
        state.switchRole(role);
        for (var nav = 0; nav < 2; nav++) {
          state.selectNav(nav);
          await pumpShell(tester, state, entry.value);
          expect(
            tester.takeException(),
            isNull,
            reason: '${role.name} page $nav failed at ${entry.key}',
          );
        }
      }
    });
  }

  testWidgets('institute tracker dialog opens', (tester) async {
    final state = PortalState();
    await pumpShell(tester, state, const Size(1440, 1000));
    final recordFinder = find.text('FDR-BOB-2018-204').first;
    await tester.ensureVisible(recordFinder);
    await tester.pumpAndSettle();
    await tester.tap(recordFinder);
    await tester.pumpAndSettle();
    expect(find.text('LIFECYCLE TRACKER'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('bank receipt dialog opens', (tester) async {
    final state = PortalState()..switchRole(UserRole.bank);
    await pumpShell(tester, state, const Size(1440, 1000));
    final receiptFinder = find.text('Inspect Receipt').first;
    await tester.ensureVisible(receiptFinder);
    await tester.pumpAndSettle();
    await tester.tap(receiptFinder);
    await tester.pumpAndSettle();
    expect(find.text('JOINT FIXED DEPOSIT RECEIPT'), findsOneWidget);
    expect(find.text('Verify & Lock Joint Lien'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('finance partial release dialog opens', (tester) async {
    final state = PortalState()..switchRole(UserRole.finance);
    await pumpShell(tester, state, const Size(1440, 1000));
    final releaseFinder = find.text('Approve Partial Release').first;
    await tester.ensureVisible(releaseFinder);
    await tester.pumpAndSettle();
    await tester.tap(releaseFinder);
    await tester.pumpAndSettle();
    expect(find.text('NET AMOUNT TO RELEASE'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('role switcher and notifications work', (tester) async {
    final state = PortalState();
    await pumpShell(tester, state, const Size(1440, 1000));
    expect(find.text('SWITCH DEMO ROLE'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.notifications_none_rounded));
    await tester.pumpAndSettle();
    expect(find.text('Notification Centre'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
