import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fdr_security_deposit/main.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  PortalState signedInAs(UserRole role) {
    final state = PortalState();
    final account = credentialFor(role);
    expect(state.signIn(role, account.userId, account.password), isTrue);
    return state;
  }

  Future<void> pump(
    WidgetTester tester,
    PortalState state, {
    Size size = const Size(1440, 1000),
  }) async {
    await tester.binding.setSurfaceSize(size);
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(useMaterial3: true),
        builder: (context, child) =>
            applyPortalTextScale(context, child ?? const SizedBox.shrink()),
        home: AnimatedBuilder(
          animation: state,
          builder: (context, _) => PortalShell(state: state),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  test('notification log parses the gateway payload', () {
    final log = MaturityNotificationLog.fromApi({
      'fdr_number': 'FDR-AICTE-ALERT-030',
      'aicte_id': '1-492831',
      'institute_name': 'KPR Institute of Technology',
      'recipient_email': 'principal@kpr.edu.in',
      'recipient_mobile': '+91-9840012310',
      'milestone_window': '30_DAYS',
      'channels': ['EMAIL', 'SMS'],
      'message_preview': 'EMAIL GATEWAY (SMTP)',
      'delivery_status': 'DELIVERED',
      'triggered_by': 'AUTO_CRON_SCHEDULER',
      'timestamp': '2026-10-27T08:00:00.000Z',
      'days_to_maturity': 15,
    });

    expect(log.fdrNumber, 'FDR-AICTE-ALERT-030');
    expect(log.milestoneShort, '30D');
    expect(log.milestoneLabel, '30-Day Critical');
    expect(log.channels, containsAll(<String>['EMAIL', 'SMS']));
    expect(log.isAutomatic, isTrue);
    expect(log.daysToMaturity, 15);
  });

  test('local gateway ledger seeds an advisory for the 90-day window', () {
    final state = PortalState();
    expect(state.notificationLogs, isNotEmpty);
    expect(state.notificationWithin90, greaterThan(0));
    expect(
      state.notificationLogs.any((log) => log.channels.contains('SMS')),
      isTrue,
    );
  });

  testWidgets('finance HQ dispatches through the automated alert engine', (
    tester,
  ) async {
    final state = signedInAs(UserRole.finance);
    await pump(tester, state);

    expect(
      find.textContaining('Automated Pre-Maturity Email & SMS Dispatch Engine'),
      findsOneWidget,
    );
    expect(find.text('90-Day Advisory Window'.toUpperCase()), findsWidgets);
    expect(find.text('60-Day Follow-Up Window'.toUpperCase()), findsWidgets);
    expect(find.text('30-Day Critical Window'.toUpperCase()), findsWidgets);
    expect(find.text('URGENT AUTO-ALERT'), findsOneWidget);
    expect(
      find.text('⚡ Run 90/60/30-Day Auto-Dispatch Scan Now'),
      findsOneWidget,
    );
    expect(find.text('DISPATCHED EMAIL & SMS GATEWAY LOG'), findsOneWidget);
    expect(find.text('View Official Message'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('gateway log opens the exact official Email and SMS template', (
    tester,
  ) async {
    final state = signedInAs(UserRole.finance);
    await pump(tester, state);

    final preview = find.text('View Official Message').first;
    await tester.ensureVisible(preview);
    await tester.pumpAndSettle();
    await tester.tap(preview);
    await tester.pumpAndSettle();

    expect(
      find.textContaining('NIC-SMS / SMTP GATEWAY • DELIVERY PROOF'),
      findsOneWidget,
    );
    expect(find.textContaining('EMAIL GATEWAY (SMTP)'), findsOneWidget);
    expect(find.textContaining('SMS GATEWAY (NIC-SMS)'), findsOneWidget);
    expect(find.text('Close Preview'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('institute dashboard raises the pre-maturity advisory banner', (
    tester,
  ) async {
    final state = signedInAs(UserRole.institute);
    await pump(tester, state);

    expect(
      find.textContaining('AICTE FINANCE BUREAU • 90-Day Pre-Maturity Advisory'),
      findsOneWidget,
    );
    expect(find.textContaining('matures in'), findsWidgets);
    expect(
      find.textContaining('Official advisory already dispatched'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}
