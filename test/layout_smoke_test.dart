import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fdr_security_deposit/main.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  void signInAs(PortalState state, UserRole role) {
    final account = credentialFor(role);
    expect(
      state.signIn(role, account.userId, account.password),
      isTrue,
      reason: 'could not sign in as ${role.name}',
    );
  }

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
        signInAs(state, role);
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
    final state = PortalState();
    signInAs(state, UserRole.bank);
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
    final state = PortalState();
    signInAs(state, UserRole.finance);
    await pumpShell(tester, state, const Size(1440, 1000));
    final releaseFinder = find
        .text('Process Settlement & Deduct Penalty')
        .first;
    await tester.ensureVisible(releaseFinder);
    await tester.pumpAndSettle();
    await tester.tap(releaseFinder);
    await tester.pumpAndSettle();
    expect(find.text('NET AMOUNT TO RELEASE'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('authenticated header exposes logout and notifications', (
    tester,
  ) async {
    final state = PortalState();
    signInAs(state, UserRole.institute);
    await pumpShell(tester, state, const Size(1440, 1000));

    // Role switching is only possible by signing out and back in.
    expect(find.text('SWITCH DEMO ROLE'), findsNothing);
    expect(find.byType(DropdownButton<UserRole>), findsNothing);
    expect(find.text('LOGOUT / SWITCH ACCOUNT'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.notifications_none_rounded));
    await tester.pumpAndSettle();
    expect(find.text('Notification Centre'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
