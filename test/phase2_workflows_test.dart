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

  testWidgets('partial release calculator approves penalty deduction', (
    tester,
  ) async {
    final state = PortalState()..switchRole(UserRole.finance);
    final record = state.records.firstWhere(
      (item) => item.id == 'FDR-HDFC-2016-588',
    );
    await pump(tester, state);
    final open = find.text('Process Settlement & Deduct Penalty').first;
    await tester.ensureVisible(open);
    await tester.pumpAndSettle();
    await tester.tap(open);
    await tester.pumpAndSettle();
    expect(find.text('Settlement & Penalty Calculator'), findsOneWidget);
    expect(find.text('NET REFUNDABLE TO INSTITUTE'), findsOneWidget);
    expect(find.text('AMOUNT CREDITED TO AICTE CORPUS'), findsOneWidget);
    final approve = find.text('Approve Partial Release & Deduct Penalty');
    await tester.tap(approve);
    await tester.pumpAndSettle();
    expect(record.status, FDRStatus.partialReleaseApproved);
    expect(record.deductedPenalty, 300000);
    expect(record.releasedAmount, 2700000);
    expect(tester.takeException(), isNull);
  });

  testWidgets('renewal confirmation routes the FDR back to the bank', (
    tester,
  ) async {
    final state = PortalState();
    final record = state.records.firstWhere(
      (item) => item.id == 'FDR-CAN-2016-412',
    );
    final oldMaturity = record.maturityDate;
    await pump(tester, state);
    final renew = find.text('Upload Extended / Renewed FDR (2 Years)').first;
    await tester.ensureVisible(renew);
    await tester.pumpAndSettle();
    await tester.tap(renew);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Upload & Route to Bank'));
    await tester.pumpAndSettle();
    expect(record.status, FDRStatus.pendingBankVerification);
    expect(record.maturityDate.year, oldMaturity.year + 2);
    expect(record.renewalCount, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('rule engine fast-tracks a zero-deficiency application', (
    tester,
  ) async {
    final state = PortalState()..switchRole(UserRole.ro);
    final record = state.records.firstWhere(
      (item) => item.id == 'FDR-PNB-2016-309',
    );
    await pump(tester, state);
    final inspect = find.text('Inspect & Run Scrutiny').first;
    await tester.ensureVisible(inspect);
    await tester.pumpAndSettle();
    await tester.tap(inspect);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Grant Fast-Track RO Clearance'));
    await tester.pumpAndSettle();
    expect(record.status, FDRStatus.roClearedPendingFinance);
    expect(tester.takeException(), isNull);
  });
}
