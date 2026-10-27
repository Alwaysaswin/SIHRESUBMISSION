import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fdr_security_deposit/main.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

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

  testWidgets('digital e-NOC certificate shows QR and verification footer', (
    tester,
  ) async {
    final state = PortalState();
    await pump(tester, state);
    final button = find.text('View / Download Digital e-NOC').first;
    await tester.ensureVisible(button);
    await tester.pumpAndSettle();
    await tester.tap(button);
    await tester.pumpAndSettle();

    expect(
      find.text('DIGITAL NO OBJECTION CERTIFICATE (e-NOC)'),
      findsOneWidget,
    );
    expect(
      find.text('NET AMOUNT AUTHORIZED FOR RELEASE TO INSTITUTE'),
      findsOneWidget,
    );
    expect(
      find.text('Scan to Verify Authenticity on AICTE Blockchain/Portal'),
      findsOneWidget,
    );
    expect(
      find.text(
        'Digitally Signed by Member Secretary & Finance Bureau, AICTE HQ',
      ),
      findsOneWidget,
    );
    expect(find.byType(QrVerificationCode), findsOneWidget);
    expect(find.text('Simulate PDF Download'), findsOneWidget);
    expect(find.text('Verify QR Hash'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('bank QR scan unlocks disbursement and closes the lifecycle', (
    tester,
  ) async {
    final state = PortalState()
      ..switchRole(UserRole.bank)
      ..selectNav(1);
    final target = state.releaseReady.first;
    await pump(tester, state);

    final scan = find.text('Scan & Verify e-NOC QR').first;
    await tester.ensureVisible(scan);
    await tester.pumpAndSettle();
    await tester.tap(scan);
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();

    expect(
      find.text('e-NOC Signature Verified: Authentic AICTE Release Order'),
      findsOneWidget,
    );

    await tester.tap(find.text('Enable Disbursement'));
    await tester.pumpAndSettle();

    final release = find
        .text('Release Lien & Disburse Funds to Institute Account')
        .first;
    await tester.ensureVisible(release);
    await tester.pumpAndSettle();
    await tester.tap(release);
    await tester.pumpAndSettle();

    expect(find.text('Confirm Disbursement'), findsOneWidget);
    await tester.tap(find.text('Confirm Disbursement'));
    await tester.pumpAndSettle();

    expect(target.status, FDRStatus.fundsDisbursed);
    expect(state.disbursedRecords, contains(target));
    expect(state.auditLog.first.action, 'Funds disbursed to institute');
    expect(tester.takeException(), isNull);
  });

  testWidgets('finance analytics and audit log render live data', (
    tester,
  ) async {
    final state = PortalState()
      ..switchRole(UserRole.finance)
      ..selectNav(2);
    await pump(tester, state);

    expect(
      find.text('Executive Analytics & Immutable Audit Trail'),
      findsOneWidget,
    );
    expect(find.text('National FDR Status Breakdown'), findsOneWidget);
    expect(find.text('Regional Corpus Distribution'), findsOneWidget);
    expect(find.text('Immutable Security Audit Log'), findsOneWidget);
    expect(
      find.text('e-NOC generated • Full release authorised'),
      findsOneWidget,
    );

    final before = state.auditEventCount;
    state.runMaturityCron();
    await tester.pumpAndSettle();
    expect(state.auditEventCount, greaterThan(before));
    expect(state.auditLog.first.action, 'Daily maturity cron executed');
    expect(find.text('Daily maturity cron executed'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('finance issued e-NOC registry lists certificates', (
    tester,
  ) async {
    final state = PortalState()..switchRole(UserRole.finance);
    await pump(tester, state);

    expect(find.text('Issued Digital e-NOC Registry'), findsOneWidget);
    expect(
      find.text('View / Download Digital e-NOC'),
      findsNWidgets(state.issuedEnocs.length),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('e-Kosh AI drawer answers status and Tanglish prompts', (
    tester,
  ) async {
    final state = PortalState();
    await pump(tester, state);

    await tester.tap(find.text('Ask e-Kosh AI'));
    await tester.pumpAndSettle();

    expect(find.text('e-Kosh AI Assistant'), findsOneWidget);
    expect(
      find.text(
        'Supports English & Tanglish • Powered by Gemini RAG + Live DB',
      ),
      findsOneWidget,
    );

    await tester.tap(find.text('Check live status of my FDRs'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Live DB reply'), findsOneWidget);
    expect(state.auditLog.first.action, 'e-Kosh AI consulted');

    await tester.tap(
      find.text('What happens if project time exceeds limit? (Tanglish)'),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('Auto-Hold'), findsOneWidget);
    expect(find.textContaining('2-Year FDR Renewal'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('finance analytics page lays out at every breakpoint', (
    tester,
  ) async {
    for (final size in const [
      Size(1440, 1000),
      Size(1180, 800),
      Size(900, 1000),
    ]) {
      final state = PortalState()
        ..switchRole(UserRole.finance)
        ..selectNav(2);
      await pump(tester, state, size: size);
      expect(
        tester.takeException(),
        isNull,
        reason: 'finance analytics failed at $size',
      );
    }
  });
}
