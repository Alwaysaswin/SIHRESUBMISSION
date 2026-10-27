import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fdr_security_deposit/main.dart';

void main() {
  Future<void> pump(
    WidgetTester tester,
    PortalState state, {
    Size size = const Size(1440, 1000),
  }) async {
    await tester.binding.setSurfaceSize(size);
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) =>
            applyPortalTextScale(context, child ?? const SizedBox.shrink()),
        home: PortalShell(state: state),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('ocr auto extraction fills the form', (tester) async {
    final state = PortalState()..selectNav(1);
    await pump(tester, state);
    final runFinder = find.text('Run AI OCR Auto-Extraction').first;
    await tester.ensureVisible(runFinder);
    await tester.pumpAndSettle();
    await tester.tap(runFinder);
    await tester.pump();
    expect(
      find.textContaining('Scanning document via Tesseract OCR'),
      findsWidgets,
    );
    await tester.pump(const Duration(milliseconds: 1600));
    await tester.pumpAndSettle();
    expect(find.textContaining('98.4% OCR MATCH'), findsOneWidget);
    expect(find.text('FDR-SBI-2026-88392'), findsWidgets);
    expect(
      find.text('Verified: Institute + AICTE Member Secretary'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('rule engine dialog opens and enables the right path', (
    tester,
  ) async {
    final state = PortalState()..switchRole(UserRole.ro);
    await pump(tester, state);
    final inspect = find.text('Inspect & Run Scrutiny').first;
    await tester.ensureVisible(inspect);
    await tester.pumpAndSettle();
    await tester.tap(inspect);
    await tester.pumpAndSettle();
    expect(
      find.text('Automated Compliance & Vigilance Rule Engine'),
      findsOneWidget,
    );
    expect(find.text('Grant Fast-Track RO Clearance'), findsOneWidget);
    expect(
      find.text('Lock Release & Mandate 2-Year Extension'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('renewal dialog opens from the institute portfolio', (
    tester,
  ) async {
    final state = PortalState();
    await pump(tester, state);
    final renew = find.text('Upload Extended / Renewed FDR (2 Years)').first;
    await tester.ensureVisible(renew);
    await tester.pumpAndSettle();
    await tester.tap(renew);
    await tester.pumpAndSettle();
    expect(find.text('Upload & Route to Bank'), findsOneWidget);
    expect(find.text('RENEWED JOINT FDR DOCUMENT'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('cron simulation dispatches alerts', (tester) async {
    final state = PortalState();
    await pump(tester, state);
    await tester.tap(find.byIcon(Icons.schedule_send_rounded).first);
    await tester.pumpAndSettle();
    expect(state.maturityCronRuns, 1);
    expect(find.textContaining('Daily maturity cron complete'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
