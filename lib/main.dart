import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

void main() {
  runApp(const EKoshApp());
}

/// Global text scale so the dense dashboard typography stays readable on
/// desktop browsers without having to zoom the page.
const double kPortalTextScale = 1.2;

/// Applies the portal's global text scale. Shared with widget tests so they
/// exercise the same typography as the running app.
Widget applyPortalTextScale(BuildContext context, Widget child) {
  final media = MediaQuery.of(context);
  return MediaQuery(
    data: media.copyWith(textScaler: const TextScaler.linear(kPortalTextScale)),
    child: child,
  );
}

// -----------------------------------------------------------------------------
// Design tokens
// -----------------------------------------------------------------------------

abstract final class AppColors {
  static const navy = Color(0xFF1E3A8A);
  static const navyDeep = Color(0xFF132A66);
  static const navyInk = Color(0xFF0B1B43);
  static const gold = Color(0xFFD97706);
  static const emerald = Color(0xFF16A34A);
  static const emeraldDark = Color(0xFF047857);
  static const orange = Color(0xFFEA580C);
  static const red = Color(0xFFDC2626);
  static const indigo = Color(0xFF4338CA);
  static const teal = Color(0xFF0F766E);
  static const slate = Color(0xFFF1F5F9);
  static const ink = Color(0xFF0F172A);
  static const muted = Color(0xFF64748B);
  static const border = Color(0xFFE2E8F0);
  static const softBorder = Color(0xFFEDF2F7);
  static const surfaceSoft = Color(0xFFF8FAFC);
  static const cream = Color(0xFFFFFBEB);
}

const _monthsShort = <String>[
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

String _two(int value) => value.toString().padLeft(2, '0');

String formatDate(DateTime date) =>
    '${_two(date.day)} ${_monthsShort[date.month - 1]} ${date.year}';

String formatDateTime(DateTime date) =>
    '${formatDate(date)} • ${_two(date.hour)}:${_two(date.minute)}';

String formatIndianNumber(num value) {
  final negative = value < 0;
  final raw = value.abs().round().toString();
  if (raw.length <= 3) {
    return '${negative ? '-' : ''}$raw';
  }
  final lastThree = raw.substring(raw.length - 3);
  var rest = raw.substring(0, raw.length - 3);
  final groups = <String>[];
  while (rest.length > 2) {
    groups.insert(0, rest.substring(rest.length - 2));
    rest = rest.substring(0, rest.length - 2);
  }
  if (rest.isNotEmpty) {
    groups.insert(0, rest);
  }
  return '${negative ? '-' : ''}${groups.join(',')},$lastThree';
}

String inr(num value) => '₹${formatIndianNumber(value)}';

String inrCompact(num value) {
  if (value >= 10000000) {
    return '₹${(value / 10000000).toStringAsFixed(2)} Cr';
  }
  if (value >= 100000) {
    return '₹${(value / 100000).toStringAsFixed(2)} L';
  }
  return inr(value);
}

String timeAgo(DateTime timestamp) {
  final diff = DateTime.now().difference(timestamp);
  if (diff.inMinutes < 1) return 'Just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
  if (diff.inHours < 24) return '${diff.inHours} hr ago';
  if (diff.inDays == 1) return 'Yesterday';
  if (diff.inDays < 7) return '${diff.inDays} days ago';
  return formatDate(timestamp);
}

// -----------------------------------------------------------------------------
// Roles & statuses
// -----------------------------------------------------------------------------

enum UserRole {
  institute(
    label: 'Institute / College Admin',
    shortLabel: 'Institute Admin',
    personName: 'Dr. R. Kumar',
    initials: 'RK',
    org: 'KPR Institute of Technology',
    location: 'Coimbatore, Tamil Nadu',
    icon: Icons.school_rounded,
    accent: AppColors.navy,
  ),
  bank(
    label: 'Partner Bank Node',
    shortLabel: 'Partner Bank',
    personName: 'S. Menon',
    initials: 'SM',
    org: 'State Bank of India',
    location: 'IFSC SBIN0004321 • Chennai',
    icon: Icons.account_balance_rounded,
    accent: AppColors.teal,
  ),
  ro(
    label: 'AICTE Regional Officer (RO)',
    shortLabel: 'Regional Officer',
    personName: 'R. Iyer',
    initials: 'RI',
    org: 'Southern Regional Office',
    location: 'Chennai, Tamil Nadu',
    icon: Icons.travel_explore_rounded,
    accent: AppColors.gold,
  ),
  finance(
    label: 'AICTE Finance Bureau HQ',
    shortLabel: 'Finance Admin',
    personName: 'A. Sharma',
    initials: 'AS',
    org: 'AICTE Finance Bureau',
    location: 'New Delhi HQ',
    icon: Icons.account_balance_wallet_rounded,
    accent: AppColors.indigo,
  );

  const UserRole({
    required this.label,
    required this.shortLabel,
    required this.personName,
    required this.initials,
    required this.org,
    required this.location,
    required this.icon,
    required this.accent,
  });

  final String label;
  final String shortLabel;
  final String personName;
  final String initials;
  final String org;
  final String location;
  final IconData icon;
  final Color accent;
}

enum FDRStatus {
  pendingBankVerification(
    label: 'Pending Bank Verification',
    fg: Color(0xFFC2410C),
    bg: Color(0xFFFFF7ED),
    border: Color(0xFFFED7AA),
    icon: Icons.hourglass_top_rounded,
  ),
  activeLienLocked(
    label: 'Active - Lien Locked',
    fg: Color(0xFF047857),
    bg: Color(0xFFECFDF5),
    border: Color(0xFFA7F3D0),
    icon: Icons.lock_rounded,
  ),
  maturedPendingRO(
    label: 'Matured - Pending RO Scrutiny',
    fg: Color(0xFFB45309),
    bg: Color(0xFFFFFBEB),
    border: Color(0xFFFDE68A),
    icon: Icons.rule_folder_rounded,
  ),
  roClearedPendingFinance(
    label: 'RO Cleared - Pending Finance Approval',
    fg: Color(0xFF4338CA),
    bg: Color(0xFFEEF2FF),
    border: Color(0xFFC7D2FE),
    icon: Icons.verified_rounded,
  ),
  releasedENOC(
    label: 'Released - e-NOC Issued',
    fg: Color(0xFF0F766E),
    bg: Color(0xFFF0FDFA),
    border: Color(0xFF99F6E4),
    icon: Icons.description_rounded,
  ),
  fundsDisbursed(
    label: 'Settled - Funds Disbursed',
    fg: Color(0xFF15803D),
    bg: Color(0xFFF0FDF4),
    border: Color(0xFFBBF7D0),
    icon: Icons.check_circle_rounded,
  ),
  onHoldExtension(
    label: 'On Hold - Extension Required',
    fg: Color(0xFFBE123C),
    bg: Color(0xFFFFF1F2),
    border: Color(0xFFFECDD3),
    icon: Icons.pause_circle_filled_rounded,
  ),
  rejectedByBank(
    label: 'Rejected by Bank',
    fg: Color(0xFFB91C1C),
    bg: Color(0xFFFEF2F2),
    border: Color(0xFFFECACA),
    icon: Icons.cancel_rounded,
  ),
  forfeited(
    label: 'Forfeited to AICTE Account',
    fg: Color(0xFF7F1D1D),
    bg: Color(0xFFFEF2F2),
    border: Color(0xFFFCA5A5),
    icon: Icons.gavel_rounded,
  );

  const FDRStatus({
    required this.label,
    required this.fg,
    required this.bg,
    required this.border,
    required this.icon,
  });

  final String label;
  final Color fg;
  final Color bg;
  final Color border;
  final IconData icon;

  bool get isClosed =>
      this == fundsDisbursed || this == forfeited || this == rejectedByBank;

  int get completedSteps => switch (this) {
    FDRStatus.pendingBankVerification => 1,
    FDRStatus.activeLienLocked => 2,
    FDRStatus.maturedPendingRO => 3,
    FDRStatus.roClearedPendingFinance => 4,
    FDRStatus.releasedENOC => 5,
    FDRStatus.fundsDisbursed => 5,
    FDRStatus.onHoldExtension => 3,
    FDRStatus.rejectedByBank => 1,
    FDRStatus.forfeited => 4,
  };

  int get activeStep => switch (this) {
    FDRStatus.pendingBankVerification => 1,
    FDRStatus.activeLienLocked => 2,
    FDRStatus.maturedPendingRO => 3,
    FDRStatus.roClearedPendingFinance => 4,
    FDRStatus.releasedENOC => 4,
    FDRStatus.fundsDisbursed => 4,
    FDRStatus.onHoldExtension => 3,
    FDRStatus.rejectedByBank => 1,
    FDRStatus.forfeited => 4,
  };

  bool get isIssueState =>
      this == rejectedByBank || this == forfeited || this == onHoldExtension;
}

String bankAbbreviation(String bankName) {
  return switch (bankName) {
    'State Bank of India' => 'SBI',
    'Bank of Baroda' => 'BOB',
    'Punjab National Bank' => 'PNB',
    'Canara Bank' => 'CAN',
    'HDFC Bank' => 'HDFC',
    _ =>
      bankName
          .split(' ')
          .where((part) => part.isNotEmpty)
          .take(3)
          .map((part) => part[0])
          .join(),
  };
}

String bankCode(String bankName) {
  return switch (bankName) {
    'State Bank of India' => 'SBI',
    'Bank of Baroda' => 'BOB',
    'Punjab National Bank' => 'PNB',
    'Canara Bank' => 'CAN',
    'HDFC Bank' => 'HDFC',
    _ => 'FDR',
  };
}

Color bankColor(String bankName) {
  return switch (bankName) {
    'State Bank of India' => AppColors.navy,
    'Bank of Baroda' => const Color(0xFFB45309),
    'Punjab National Bank' => const Color(0xFF9F1239),
    'Canara Bank' => const Color(0xFF0369A1),
    'HDFC Bank' => const Color(0xFF1D4ED8),
    _ => AppColors.teal,
  };
}

// -----------------------------------------------------------------------------
// Core models
// -----------------------------------------------------------------------------

class FDRRecord {
  FDRRecord({
    required this.id,
    required this.bankName,
    required this.ifsc,
    required this.instituteName,
    required this.instituteId,
    required this.program,
    required this.intake,
    required this.amount,
    required this.issueDate,
    required this.maturityDate,
    required this.status,
    required this.lastUpdated,
    this.penalty = 0,
    this.deductedPenalty = 0,
    this.deficiency = false,
    this.remarks = '',
    this.submittedAt,
    this.releaseAppliedAt,
    this.roClearedAt,
    this.releasedAt,
    this.releasedAmount,
    this.enocNumber,
    this.holdReason,
    this.holdDate,
  });

  final String id;
  final String bankName;
  final String ifsc;
  final String instituteName;
  final String instituteId;
  final String program;
  final int intake;
  final double amount;
  final DateTime issueDate;
  final DateTime maturityDate;
  FDRStatus status;
  double penalty;
  double deductedPenalty;
  bool deficiency;
  String remarks;
  DateTime lastUpdated;
  DateTime? submittedAt;
  DateTime? releaseAppliedAt;
  DateTime? roClearedAt;
  DateTime? releasedAt;
  double? releasedAmount;
  String? enocNumber;
  String? holdReason;
  DateTime? holdDate;

  bool get isMatured => !maturityDate.isAfter(DateTime.now());

  double get netPayable => amount > penalty ? amount - penalty : 0;

  double get settlementValue => releasedAmount ?? netPayable;

  String get complianceLabel =>
      deficiency ? 'Deficiency / Time Exceeded' : 'Zero Deficiency';
}

class ActivityLog {
  ActivityLog({
    required this.title,
    required this.detail,
    required this.timestamp,
    required this.icon,
    required this.color,
    this.read = false,
  });

  final String title;
  final String detail;
  final DateTime timestamp;
  final IconData icon;
  final Color color;
  bool read;
}

// -----------------------------------------------------------------------------
// Centralized state controller
// -----------------------------------------------------------------------------

class PortalState extends ChangeNotifier {
  PortalState() {
    _seed();
  }

  static const kprId = '1-492831';

  UserRole _role = UserRole.institute;
  int _navIndex = 0;
  int _enocSequence = 4127;

  final List<FDRRecord> records = [];
  final List<ActivityLog> activities = [];

  UserRole get role => _role;
  int get navIndex => _navIndex;

  void switchRole(UserRole value) {
    if (_role == value) return;
    _role = value;
    _navIndex = 0;
    notifyListeners();
  }

  void selectNav(int index) {
    if (_navIndex == index) return;
    _navIndex = index;
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Seed data
  // ---------------------------------------------------------------------------

  void _seed() {
    final now = DateTime.now();

    records.addAll([
      FDRRecord(
        id: 'FDR-SBI-2026-101',
        bankName: 'State Bank of India',
        ifsc: 'SBIN0004321',
        instituteName: 'KPR Institute of Technology',
        instituteId: kprId,
        program: 'B.Tech - Computer Science',
        intake: 180,
        amount: 1500000,
        issueDate: DateTime(2026, 1, 15),
        maturityDate: DateTime(2027, 1, 14),
        status: FDRStatus.pendingBankVerification,
        lastUpdated: now.subtract(const Duration(hours: 3)),
        submittedAt: DateTime(2026, 10, 24, 10, 15),
        remarks:
            'Joint FDR receipt uploaded by the institute. Awaiting lien verification by the partner bank.',
      ),
      FDRRecord(
        id: 'FDR-BOB-2018-204',
        bankName: 'Bank of Baroda',
        ifsc: 'BARB0COIMBA',
        instituteName: 'KPR Institute of Technology',
        instituteId: kprId,
        program: 'B.Tech - Electronics & Communication',
        intake: 120,
        amount: 3500000,
        issueDate: DateTime(2018, 4, 10),
        maturityDate: DateTime(2026, 8, 31),
        status: FDRStatus.activeLienLocked,
        lastUpdated: now.subtract(const Duration(days: 2)),
        submittedAt: DateTime(2018, 4, 12),
        remarks:
            'Lien marked in favour of AICTE. The deposit has crossed maturity; institute release application is pending.',
      ),
      FDRRecord(
        id: 'FDR-PNB-2016-309',
        bankName: 'Punjab National Bank',
        ifsc: 'PUNB0COIMBT',
        instituteName: 'KPR Institute of Technology',
        instituteId: kprId,
        program: 'MBA - General Management',
        intake: 60,
        amount: 1500000,
        issueDate: DateTime(2016, 6, 18),
        maturityDate: DateTime(2026, 6, 17),
        status: FDRStatus.maturedPendingRO,
        lastUpdated: now.subtract(const Duration(days: 1, hours: 4)),
        submittedAt: DateTime(2016, 6, 20),
        releaseAppliedAt: DateTime(2026, 9, 28),
        remarks:
            'Release application received with all original documents. No compliance deficiency observed.',
      ),
      FDRRecord(
        id: 'FDR-CAN-2016-412',
        bankName: 'Canara Bank',
        ifsc: 'CNRB0COIMBT',
        instituteName: 'PSG College of Technology',
        instituteId: '1-492832',
        program: 'B.Tech - Mechanical Engineering',
        intake: 120,
        amount: 2500000,
        issueDate: DateTime(2016, 8, 5),
        maturityDate: DateTime(2026, 8, 4),
        status: FDRStatus.maturedPendingRO,
        lastUpdated: now.subtract(const Duration(hours: 9)),
        submittedAt: DateTime(2016, 8, 8),
        releaseAppliedAt: DateTime(2026, 9, 2),
        deficiency: true,
        remarks:
            'Approval time exceeded by 47 days. Clarification on intake shortfall is pending from the institute.',
      ),
      FDRRecord(
        id: 'FDR-HDFC-2016-588',
        bankName: 'HDFC Bank',
        ifsc: 'HDFC0COIMBA',
        instituteName: 'Government College of Engineering, Salem',
        instituteId: '1-492833',
        program: 'M.Tech - Structural Engineering',
        intake: 36,
        amount: 3000000,
        issueDate: DateTime(2016, 9, 12),
        maturityDate: DateTime(2026, 9, 11),
        status: FDRStatus.roClearedPendingFinance,
        lastUpdated: now.subtract(const Duration(days: 3)),
        submittedAt: DateTime(2016, 9, 15),
        releaseAppliedAt: DateTime(2026, 9, 18),
        roClearedAt: DateTime(2026, 10, 18),
        penalty: 300000,
        remarks:
            'RO clearance granted. ₹3,00,000 penalty assessed for delayed release submission; final approval rests with AICTE Finance.',
      ),
    ]);

    activities.addAll([
      ActivityLog(
        title: 'Lien verification requested',
        detail:
            'KPR Institute of Technology submitted FDR-SBI-2026-101 for bank verification.',
        timestamp: now.subtract(const Duration(hours: 3)),
        icon: Icons.upload_file_rounded,
        color: AppColors.orange,
      ),
      ActivityLog(
        title: 'RO clearance granted',
        detail:
            'FDR-HDFC-2016-588 was forwarded to AICTE Finance after regional scrutiny.',
        timestamp: now.subtract(const Duration(days: 1, hours: 5)),
        icon: Icons.verified_rounded,
        color: AppColors.indigo,
      ),
      ActivityLog(
        title: 'Deficiency flagged',
        detail:
            'PSG College of Technology application FDR-CAN-2016-412 requires clarification.',
        timestamp: now.subtract(const Duration(days: 2)),
        icon: Icons.flag_rounded,
        color: AppColors.red,
      ),
      ActivityLog(
        title: 'Release application in scrutiny',
        detail: 'FDR-PNB-2016-309 is pending RO scrutiny with zero deficiency.',
        timestamp: now.subtract(const Duration(days: 3)),
        icon: Icons.rule_folder_rounded,
        color: AppColors.gold,
      ),
    ]);
  }

  // ---------------------------------------------------------------------------
  // Derived collections & metrics
  // ---------------------------------------------------------------------------

  List<FDRRecord> _withStatuses(Set<FDRStatus> statuses) =>
      records.where((record) => statuses.contains(record.status)).toList();

  List<FDRRecord> get instituteRecords =>
      records.where((record) => record.instituteId == kprId).toList();

  List<FDRRecord> get pendingBankVerification =>
      _withStatuses({FDRStatus.pendingBankVerification});

  List<FDRRecord> get activeLiens =>
      _withStatuses({FDRStatus.activeLienLocked});

  List<FDRRecord> get releaseReady => _withStatuses({FDRStatus.releasedENOC});

  List<FDRRecord> get roScrutiny => _withStatuses({FDRStatus.maturedPendingRO});

  List<FDRRecord> get onHoldRecords =>
      _withStatuses({FDRStatus.onHoldExtension});

  List<FDRRecord> get financeQueue =>
      _withStatuses({FDRStatus.roClearedPendingFinance});

  List<FDRRecord> get disbursedRecords =>
      _withStatuses({FDRStatus.fundsDisbursed});

  List<FDRRecord> get rejectedRecords =>
      _withStatuses({FDRStatus.rejectedByBank});

  List<FDRRecord> get forfeitedRecords => _withStatuses({FDRStatus.forfeited});

  List<FDRRecord> get releasedRecords =>
      _withStatuses({FDRStatus.releasedENOC, FDRStatus.fundsDisbursed});

  List<FDRRecord> get instituteActiveDeposits => instituteRecords
      .where(
        (record) =>
            record.status != FDRStatus.rejectedByBank &&
            record.status != FDRStatus.forfeited &&
            record.status != FDRStatus.fundsDisbursed,
      )
      .toList();

  List<FDRRecord> get instituteLockedDeposits => instituteRecords
      .where(
        (record) => {
          FDRStatus.pendingBankVerification,
          FDRStatus.activeLienLocked,
          FDRStatus.maturedPendingRO,
          FDRStatus.roClearedPendingFinance,
          FDRStatus.releasedENOC,
          FDRStatus.onHoldExtension,
        }.contains(record.status),
      )
      .toList();

  List<FDRRecord> get institutePendingRequests => instituteRecords
      .where(
        (record) => {
          FDRStatus.pendingBankVerification,
          FDRStatus.maturedPendingRO,
          FDRStatus.roClearedPendingFinance,
          FDRStatus.onHoldExtension,
        }.contains(record.status),
      )
      .toList();

  List<FDRRecord> get instituteMaturingSoon => instituteRecords.where((record) {
    final days = record.maturityDate.difference(DateTime.now()).inDays;
    return record.status == FDRStatus.activeLienLocked &&
        days >= 0 &&
        days <= 180;
  }).toList();

  double get instituteLockedValue =>
      instituteLockedDeposits.fold(0, (total, record) => total + record.amount);

  double get totalLienValue => records
      .where(
        (record) => {
          FDRStatus.activeLienLocked,
          FDRStatus.maturedPendingRO,
          FDRStatus.roClearedPendingFinance,
          FDRStatus.releasedENOC,
          FDRStatus.onHoldExtension,
        }.contains(record.status),
      )
      .fold(0, (total, record) => total + record.amount);

  double get nationalCorpus => records
      .where((record) => record.status != FDRStatus.rejectedByBank)
      .fold(0, (total, record) => total + record.amount);

  double get totalPenaltiesDeducted =>
      records.fold(0, (total, record) => total + record.deductedPenalty);

  double get totalPenaltyAssessed =>
      records.fold(0, (total, record) => total + record.penalty);

  double get totalForfeited =>
      forfeitedRecords.fold(0, (total, record) => total + record.amount);

  int get regionalInstituteCount =>
      records.map((record) => record.instituteId).toSet().length;

  int get zeroDeficiencyCleared => records
      .where(
        (record) =>
            !record.deficiency &&
            {
              FDRStatus.roClearedPendingFinance,
              FDRStatus.releasedENOC,
              FDRStatus.fundsDisbursed,
            }.contains(record.status),
      )
      .length;

  int get flaggedInstituteCount => records
      .where(
        (record) =>
            record.deficiency || record.status == FDRStatus.onHoldExtension,
      )
      .map((record) => record.instituteId)
      .toSet()
      .length;

  int get unreadNotifications =>
      activities.where((activity) => !activity.read).length;

  List<FDRRecord> recordsForInstitute(String instituteId) =>
      records.where((record) => record.instituteId == instituteId).toList();

  bool fdrNumberExists(String fdrNumber) => records.any(
    (record) => record.id.toLowerCase() == fdrNumber.trim().toLowerCase(),
  );

  String suggestFdrNumber(String bankName) {
    final year = DateTime.now().year;
    var sequence = 700 + records.length;
    while (true) {
      final candidate = 'FDR-${bankCode(bankName)}-$year-$sequence';
      if (!fdrNumberExists(candidate)) return candidate;
      sequence++;
    }
  }

  // ---------------------------------------------------------------------------
  // Workflow actions
  // ---------------------------------------------------------------------------

  void addFdr({
    required String bankName,
    required String ifsc,
    required String fdrNumber,
    required double amount,
    required DateTime issueDate,
    required DateTime maturityDate,
    required String program,
    required int intake,
  }) {
    final now = DateTime.now();
    final record = FDRRecord(
      id: fdrNumber.trim(),
      bankName: bankName,
      ifsc: ifsc.trim().toUpperCase(),
      instituteName: 'KPR Institute of Technology',
      instituteId: kprId,
      program: program,
      intake: intake,
      amount: amount,
      issueDate: issueDate,
      maturityDate: maturityDate,
      status: FDRStatus.pendingBankVerification,
      lastUpdated: now,
      submittedAt: now,
      remarks:
          'Joint FDR submitted by the institute through the e-Kosh portal. Awaiting receipt inspection and lien marking by $bankName.',
    );
    records.insert(0, record);
    _log(
      title: 'New joint FDR submitted',
      detail:
          '${record.id} • ${inr(record.amount)} routed to $bankName for lien verification.',
      icon: Icons.add_card_rounded,
      color: AppColors.orange,
    );
    notifyListeners();
  }

  void applyForRelease(FDRRecord record) {
    record.status = FDRStatus.maturedPendingRO;
    record.releaseAppliedAt = DateTime.now();
    record.lastUpdated = DateTime.now();
    record.deficiency = false;
    record.remarks =
        'Institute applied for release / refund after maturity. Application moved to the Southern Regional Office for scrutiny.';
    _log(
      title: 'Release application submitted',
      detail:
          '${record.id} • ${record.instituteName} moved to RO scrutiny for ${inr(record.amount)}.',
      icon: Icons.assignment_turned_in_rounded,
      color: AppColors.gold,
    );
    notifyListeners();
  }

  void verifyLien(FDRRecord record) {
    record.status = FDRStatus.activeLienLocked;
    record.lastUpdated = DateTime.now();
    record.remarks =
        'Receipt details verified by ${record.bankName}. Joint lien marked in favour of AICTE under IFSC ${record.ifsc}.';
    _log(
      title: 'Joint lien locked',
      detail:
          '${record.bankName} verified ${record.id} and marked the AICTE lien.',
      icon: Icons.lock_rounded,
      color: AppColors.emerald,
    );
    notifyListeners();
  }

  void rejectFdr(FDRRecord record, String reason) {
    record.status = FDRStatus.rejectedByBank;
    record.lastUpdated = DateTime.now();
    record.remarks = 'Rejected by ${record.bankName}: $reason';
    _log(
      title: 'FDR rejected by bank',
      detail: '${record.id} was rejected. Reason: $reason',
      icon: Icons.cancel_rounded,
      color: AppColors.red,
    );
    notifyListeners();
  }

  void disburseFunds(FDRRecord record) {
    record.status = FDRStatus.fundsDisbursed;
    record.lastUpdated = DateTime.now();
    record.releasedAt = DateTime.now();
    record.remarks =
        'Funds released to ${record.instituteName} against e-NOC ${record.enocNumber ?? '—'}. Settlement completed by ${record.bankName}.';
    _log(
      title: 'Funds disbursed to institute',
      detail:
          '${record.bankName} settled ${inr(record.settlementValue)} for ${record.id}.',
      icon: Icons.payments_rounded,
      color: AppColors.emerald,
    );
    notifyListeners();
  }

  void forwardToFinance(FDRRecord record) {
    final previousFlag = record.deficiency;
    record.status = FDRStatus.roClearedPendingFinance;
    record.roClearedAt = DateTime.now();
    record.lastUpdated = DateTime.now();
    record.deficiency = false;
    record.remarks = previousFlag
        ? 'RO scrutiny completed. Previous time-exceeded flag resolved after institutional clarification. Forwarded to AICTE Finance.'
        : 'RO scrutiny completed with zero deficiency. Clearance granted and forwarded to AICTE Finance.';
    _log(
      title: 'RO clearance granted',
      detail:
          '${record.id} • ${record.instituteName} forwarded to Finance for final settlement.',
      icon: Icons.verified_rounded,
      color: AppColors.indigo,
    );
    notifyListeners();
  }

  void putOnHold(FDRRecord record, String reason) {
    record.status = FDRStatus.onHoldExtension;
    record.lastUpdated = DateTime.now();
    record.holdDate = DateTime.now();
    record.holdReason = reason;
    record.remarks =
        'Application placed on hold by the Regional Office. Extension / clarification required: $reason';
    _log(
      title: 'RO placed application on hold',
      detail: '${record.id} • Extension mandated. $reason',
      icon: Icons.pause_circle_filled_rounded,
      color: AppColors.orange,
    );
    notifyListeners();
  }

  void reopenScrutiny(FDRRecord record) {
    record.status = FDRStatus.maturedPendingRO;
    record.lastUpdated = DateTime.now();
    record.holdReason = null;
    record.holdDate = null;
    record.remarks =
        'Institute response received. RO scrutiny reopened for a fresh decision.';
    _log(
      title: 'RO scrutiny reopened',
      detail: '${record.id} returned to the active scrutiny queue.',
      icon: Icons.refresh_rounded,
      color: AppColors.gold,
    );
    notifyListeners();
  }

  void approveFullRelease(FDRRecord record) {
    final waived = record.penalty;
    record.releasedAmount = record.amount;
    record.deductedPenalty = 0;
    record.enocNumber = _nextEnoc();
    record.releasedAt = DateTime.now();
    record.lastUpdated = DateTime.now();
    record.status = FDRStatus.releasedENOC;
    record.remarks = waived > 0
        ? 'Full release approved by AICTE Finance. Assessed penalty of ${inr(waived)} waived. e-NOC issued to ${record.bankName}.'
        : 'Full release approved by AICTE Finance. e-NOC issued to ${record.bankName} for disbursement.';
    _log(
      title: 'Full release approved',
      detail:
          'e-NOC ${record.enocNumber} issued for ${record.id} • ${inr(record.amount)}.',
      icon: Icons.description_rounded,
      color: AppColors.emerald,
    );
    notifyListeners();
  }

  void approvePartialRelease(FDRRecord record, double deduction) {
    final safeDeduction = deduction.clamp(0.0, record.amount).toDouble();
    record.releasedAmount = record.amount - safeDeduction;
    record.deductedPenalty = safeDeduction;
    record.enocNumber = _nextEnoc();
    record.releasedAt = DateTime.now();
    record.lastUpdated = DateTime.now();
    record.status = FDRStatus.releasedENOC;
    record.remarks =
        'Partial release approved by AICTE Finance. Penalty of ${inr(safeDeduction)} deducted; net ${inr(record.releasedAmount!)} released via e-NOC ${record.enocNumber}.';
    _log(
      title: 'Partial release approved',
      detail:
          '${inr(safeDeduction)} penalty deducted from ${record.id}. Net release ${inr(record.releasedAmount!)}.',
      icon: Icons.account_balance_wallet_rounded,
      color: AppColors.gold,
    );
    notifyListeners();
  }

  void forfeitFdr(FDRRecord record) {
    record.status = FDRStatus.forfeited;
    record.releasedAmount = 0;
    record.lastUpdated = DateTime.now();
    record.remarks =
        'FDR encashed and forfeited to the AICTE account following final review. No funds released to the institute.';
    _log(
      title: 'FDR forfeited to AICTE',
      detail:
          '${record.id} • ${inr(record.amount)} encashed to the AICTE account.',
      icon: Icons.gavel_rounded,
      color: AppColors.red,
    );
    notifyListeners();
  }

  void markAllNotificationsRead() {
    for (final activity in activities) {
      activity.read = true;
    }
    notifyListeners();
  }

  String _nextEnoc() => 'AICTE/eNOC/${DateTime.now().year}/${_enocSequence++}';

  void _log({
    required String title,
    required String detail,
    required IconData icon,
    required Color color,
  }) {
    activities.insert(
      0,
      ActivityLog(
        title: title,
        detail: detail,
        timestamp: DateTime.now(),
        icon: icon,
        color: color,
      ),
    );
    if (activities.length > 40) {
      activities.removeLast();
    }
  }
}

// -----------------------------------------------------------------------------
// Application shell
// -----------------------------------------------------------------------------

class EKoshApp extends StatefulWidget {
  const EKoshApp({super.key});

  @override
  State<EKoshApp> createState() => _EKoshAppState();
}

class _EKoshAppState extends State<EKoshApp> {
  late final PortalState _state;

  @override
  void initState() {
    super.initState();
    _state = PortalState();
  }

  @override
  void dispose() {
    _state.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'e-Kosh AICTE',
      debugShowCheckedModeBanner: false,
      theme: _buildTheme(),
      builder: (context, child) =>
          applyPortalTextScale(context, child ?? const SizedBox.shrink()),
      home: AnimatedBuilder(
        animation: _state,
        builder: (context, _) => PortalShell(state: _state),
      ),
    );
  }
}

ThemeData _buildTheme() {
  final base = ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: AppColors.navy,
      brightness: Brightness.light,
      primary: AppColors.navy,
      secondary: AppColors.gold,
      surface: Colors.white,
      error: AppColors.red,
    ),
    scaffoldBackgroundColor: AppColors.slate,
  );

  return base.copyWith(
    textTheme: base.textTheme
        .apply(bodyColor: AppColors.ink, displayColor: AppColors.navyInk)
        .copyWith(
          headlineSmall: const TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.6,
            color: AppColors.navyInk,
            height: 1.12,
          ),
          titleLarge: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            color: AppColors.navyInk,
          ),
          titleMedium: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: AppColors.navyInk,
          ),
          bodyMedium: const TextStyle(
            fontSize: 13,
            color: AppColors.ink,
            height: 1.45,
          ),
          bodySmall: const TextStyle(
            fontSize: 11.5,
            color: AppColors.muted,
            height: 1.4,
          ),
        ),
    dividerTheme: const DividerThemeData(
      color: AppColors.softBorder,
      thickness: 1,
      space: 1,
    ),
    inputDecorationTheme: InputDecorationThemeData(
      filled: true,
      fillColor: AppColors.surfaceSoft,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      labelStyle: const TextStyle(
        fontSize: 12,
        color: AppColors.muted,
        fontWeight: FontWeight.w600,
      ),
      hintStyle: const TextStyle(fontSize: 12, color: Color(0xFF94A3B8)),
      errorStyle: const TextStyle(fontSize: 10.5, color: AppColors.red),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: AppColors.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: AppColors.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: AppColors.gold, width: 1.6),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: AppColors.red),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: AppColors.red, width: 1.6),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: AppColors.navyInk,
      contentTextStyle: const TextStyle(
        color: Colors.white,
        fontSize: 12.5,
        fontWeight: FontWeight.w500,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: AppColors.navyInk,
        borderRadius: BorderRadius.circular(7),
      ),
      textStyle: const TextStyle(color: Colors.white, fontSize: 11),
    ),
  );
}

class PortalShell extends StatelessWidget {
  const PortalShell({super.key, required this.state});

  final PortalState state;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          PortalTopBar(state: state),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final collapsed = constraints.maxWidth < 1180;
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    PortalSidebar(state: state, collapsed: collapsed),
                    Expanded(
                      child: Container(
                        color: AppColors.slate,
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 220),
                          switchInCurve: Curves.easeOut,
                          switchOutCurve: Curves.easeIn,
                          transitionBuilder: (child, animation) {
                            return FadeTransition(
                              opacity: animation,
                              child: child,
                            );
                          },
                          child: KeyedSubtree(
                            key: ValueKey(
                              '${state.role.name}-${state.navIndex}',
                            ),
                            child: _pageForState(context, state),
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

Widget _pageForState(BuildContext context, PortalState state) {
  return switch (state.role) {
    UserRole.institute =>
      state.navIndex == 0
          ? InstitutePortfolioPage(state: state)
          : InstituteSubmissionPage(state: state),
    UserRole.bank =>
      state.navIndex == 0
          ? BankVerificationPage(state: state)
          : BankSettlementPage(state: state),
    UserRole.ro =>
      state.navIndex == 0
          ? RoScrutinyPage(state: state)
          : RoOnHoldPage(state: state),
    UserRole.finance =>
      state.navIndex == 0
          ? FinanceSettlementPage(state: state)
          : FinanceLedgerPage(state: state),
  };
}

// -----------------------------------------------------------------------------
// Top app bar
// -----------------------------------------------------------------------------

class PortalTopBar extends StatelessWidget {
  const PortalTopBar({super.key, required this.state});

  final PortalState state;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: AppColors.border)),
        boxShadow: [
          BoxShadow(
            color: Color(0x0F0F172A),
            blurRadius: 20,
            offset: Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        children: [
          Container(
            height: 3,
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [AppColors.gold, Color(0xFFF59E0B), AppColors.navy],
              ),
            ),
          ),
          SizedBox(
            height: 78,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final width = constraints.maxWidth;
                final compact = width < 1120;
                final veryCompact = width < 820;
                final ultraCompact = width < 560;
                return Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: ultraCompact ? 12 : 24,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: _PortalBrand(
                            showSubtitle: width >= 940,
                            showWordmark: !ultraCompact,
                          ),
                        ),
                      ),
                      if (width >= 1260) ...[
                        const _LiveDemoPill(),
                        const SizedBox(width: 14),
                      ],
                      _NotificationButton(state: state),
                      if (!compact) ...[
                        const SizedBox(width: 12),
                        _ActiveUserBadge(state: state),
                      ],
                      const SizedBox(width: 12),
                      _RoleSwitcher(state: state, compact: veryCompact),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _PortalBrand extends StatelessWidget {
  const _PortalBrand({required this.showSubtitle, required this.showWordmark});

  final bool showSubtitle;
  final bool showWordmark;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [AppColors.navy, AppColors.navyDeep],
            ),
            borderRadius: BorderRadius.circular(13),
            border: Border.all(color: AppColors.gold.withValues(alpha: 0.55)),
            boxShadow: [
              BoxShadow(
                color: AppColors.navy.withValues(alpha: 0.18),
                blurRadius: 12,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          child: const Icon(
            Icons.account_balance_rounded,
            color: AppColors.gold,
            size: 25,
          ),
        ),
        if (showWordmark) ...[
          const SizedBox(width: 12),
          Flexible(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'AICTE  •  GOVERNMENT OF INDIA',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 8.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.25,
                    color: AppColors.gold,
                  ),
                ),
                const SizedBox(height: 2),
                const Text(
                  'e-Kosh AICTE',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 21,
                    fontWeight: FontWeight.w900,
                    color: AppColors.navyInk,
                    letterSpacing: -0.5,
                    height: 1.0,
                  ),
                ),
                if (showSubtitle) ...[
                  const SizedBox(height: 3),
                  const Text(
                    'Security Deposit & FDR Lifecycle Management',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 9.5,
                      color: AppColors.muted,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _LiveDemoPill extends StatelessWidget {
  const _LiveDemoPill();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.emerald.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppColors.emerald.withValues(alpha: 0.24)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: const BoxDecoration(
              color: AppColors.emerald,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          const Text(
            'LIVE DEMO',
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.8,
              color: AppColors.emeraldDark,
            ),
          ),
        ],
      ),
    );
  }
}

class _NotificationButton extends StatelessWidget {
  const _NotificationButton({required this.state});

  final PortalState state;

  @override
  Widget build(BuildContext context) {
    final unread = state.unreadNotifications;
    return Tooltip(
      message: 'Notifications',
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => showNotificationsDialog(context, state),
        child: Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(
            color: AppColors.surfaceSoft,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.border),
          ),
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.center,
            children: [
              const Icon(
                Icons.notifications_none_rounded,
                color: AppColors.navyDeep,
                size: 23,
              ),
              if (unread > 0)
                Positioned(
                  top: 8,
                  right: 8,
                  child: Container(
                    constraints: const BoxConstraints(minWidth: 17),
                    height: 17,
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    decoration: BoxDecoration(
                      color: AppColors.red,
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: Colors.white, width: 1.5),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      unread > 9 ? '9+' : '$unread',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 9,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ActiveUserBadge extends StatelessWidget {
  const _ActiveUserBadge({required this.state});

  final PortalState state;

  @override
  Widget build(BuildContext context) {
    final role = state.role;
    return Container(
      height: 50,
      padding: const EdgeInsets.fromLTRB(7, 5, 12, 5),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: role.accent.withValues(alpha: 0.10),
              shape: BoxShape.circle,
              border: Border.all(color: role.accent.withValues(alpha: 0.18)),
            ),
            alignment: Alignment.center,
            child: Text(
              role.initials,
              style: TextStyle(
                color: role.accent,
                fontSize: 12,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          const SizedBox(width: 9),
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                role.personName,
                style: const TextStyle(
                  fontSize: 11.5,
                  color: AppColors.navyInk,
                  fontWeight: FontWeight.w800,
                ),
              ),
              Text(
                role.shortLabel,
                style: const TextStyle(
                  fontSize: 9.5,
                  color: AppColors.muted,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _RoleSwitcher extends StatelessWidget {
  const _RoleSwitcher({required this.state, required this.compact});

  final PortalState state;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 58,
      padding: EdgeInsets.fromLTRB(compact ? 10 : 12, 5, 8, 5),
      decoration: BoxDecoration(
        color: AppColors.cream,
        borderRadius: BorderRadius.circular(13),
        border: Border.all(
          color: AppColors.gold.withValues(alpha: 0.55),
          width: 1.4,
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.gold.withValues(alpha: 0.08),
            blurRadius: 14,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: AppColors.gold.withValues(alpha: 0.13),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(
              Icons.swap_horiz_rounded,
              color: AppColors.gold,
              size: 19,
            ),
          ),
          const SizedBox(width: 9),
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!compact)
                const Text(
                  'SWITCH DEMO ROLE',
                  style: TextStyle(
                    fontSize: 7.5,
                    letterSpacing: 0.9,
                    fontWeight: FontWeight.w900,
                    color: AppColors.gold,
                  ),
                ),
              if (!compact) const SizedBox(height: 1),
              DropdownButtonHideUnderline(
                child: DropdownButton<UserRole>(
                  value: state.role,
                  isDense: true,
                  isExpanded: false,
                  borderRadius: BorderRadius.circular(12),
                  dropdownColor: Colors.white,
                  itemHeight: 52,
                  icon: const Icon(
                    Icons.keyboard_arrow_down_rounded,
                    color: AppColors.gold,
                    size: 19,
                  ),
                  style: const TextStyle(
                    color: AppColors.navyInk,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w800,
                  ),
                  selectedItemBuilder: (context) {
                    return UserRole.values
                        .map(
                          (role) => Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(role.icon, size: 15, color: role.accent),
                              const SizedBox(width: 6),
                              Text(
                                role.shortLabel,
                                style: const TextStyle(
                                  color: AppColors.navyInk,
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ],
                          ),
                        )
                        .toList();
                  },
                  items: UserRole.values
                      .map(
                        (role) => DropdownMenuItem<UserRole>(
                          value: role,
                          child: Row(
                            children: [
                              Icon(role.icon, size: 17, color: role.accent),
                              const SizedBox(width: 9),
                              Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    role.shortLabel,
                                    style: const TextStyle(
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w700,
                                      color: AppColors.navyInk,
                                    ),
                                  ),
                                  Text(
                                    role.location,
                                    style: const TextStyle(
                                      fontSize: 9,
                                      color: AppColors.muted,
                                      fontWeight: FontWeight.w400,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: (role) {
                    if (role != null) state.switchRole(role);
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Sidebar
// -----------------------------------------------------------------------------

class PortalNavItem {
  const PortalNavItem({required this.label, required this.icon, this.badge});

  final String label;
  final IconData icon;
  final int? badge;
}

List<PortalNavItem> _navigationFor(PortalState state) {
  return switch (state.role) {
    UserRole.institute => [
      PortalNavItem(
        label: 'Portfolio & Tracker',
        icon: Icons.space_dashboard_rounded,
        badge: state.institutePendingRequests.length,
      ),
      const PortalNavItem(
        label: 'New FDR Submission',
        icon: Icons.add_card_rounded,
      ),
    ],
    UserRole.bank => [
      PortalNavItem(
        label: 'Verification Desk',
        icon: Icons.fact_check_rounded,
        badge: state.pendingBankVerification.length,
      ),
      PortalNavItem(
        label: 'Release Settlement',
        icon: Icons.payments_rounded,
        badge: state.releaseReady.length,
      ),
    ],
    UserRole.ro => [
      PortalNavItem(
        label: 'Scrutiny Queue',
        icon: Icons.rule_folder_rounded,
        badge: state.roScrutiny.length,
      ),
      PortalNavItem(
        label: 'On-Hold Tracker',
        icon: Icons.pause_circle_rounded,
        badge: state.onHoldRecords.length,
      ),
    ],
    UserRole.finance => [
      PortalNavItem(
        label: 'Final Settlement',
        icon: Icons.account_balance_wallet_rounded,
        badge: state.financeQueue.length,
      ),
      const PortalNavItem(
        label: 'Master Ledger',
        icon: Icons.table_chart_rounded,
      ),
    ],
  };
}

class PortalSidebar extends StatelessWidget {
  const PortalSidebar({
    super.key,
    required this.state,
    required this.collapsed,
  });

  final PortalState state;
  final bool collapsed;

  @override
  Widget build(BuildContext context) {
    final items = _navigationFor(state);
    final role = state.role;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      width: collapsed ? 84 : 268,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF102A5C), Color(0xFF1E3A8A)],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(height: collapsed ? 18 : 22),
          if (!collapsed)
            const Padding(
              padding: EdgeInsets.fromLTRB(22, 0, 18, 12),
              child: Text(
                'WORKSPACE',
                style: TextStyle(
                  fontSize: 8.5,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.6,
                  color: Color(0xFF93A7D4),
                ),
              ),
            ),
          if (collapsed) const SizedBox(height: 2),
          ...List.generate(items.length, (index) {
            final item = items[index];
            final selected = state.navIndex == index;
            return _SidebarTile(
              item: item,
              selected: selected,
              collapsed: collapsed,
              onTap: () => state.selectNav(index),
            );
          }),
          const Spacer(),
          _SidebarFooter(role: role, collapsed: collapsed),
        ],
      ),
    );
  }
}

class _SidebarTile extends StatelessWidget {
  const _SidebarTile({
    required this.item,
    required this.selected,
    required this.collapsed,
    required this.onTap,
  });

  final PortalNavItem item;
  final bool selected;
  final bool collapsed;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tile = Padding(
      padding: EdgeInsets.symmetric(
        horizontal: collapsed ? 12 : 14,
        vertical: 3,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(11),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 170),
            height: 48,
            padding: EdgeInsets.symmetric(horizontal: collapsed ? 0 : 12),
            decoration: BoxDecoration(
              color: selected
                  ? Colors.white.withValues(alpha: 0.11)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(11),
              border: Border.all(
                color: selected
                    ? Colors.white.withValues(alpha: 0.08)
                    : Colors.transparent,
              ),
            ),
            child: Row(
              mainAxisAlignment: collapsed
                  ? MainAxisAlignment.center
                  : MainAxisAlignment.start,
              children: [
                if (selected && !collapsed) ...[
                  Container(
                    width: 3,
                    height: 19,
                    decoration: BoxDecoration(
                      color: AppColors.gold,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  const SizedBox(width: 11),
                ],
                Icon(
                  item.icon,
                  size: 20,
                  color: selected
                      ? AppColors.gold
                      : Colors.white.withValues(alpha: 0.68),
                ),
                if (!collapsed) ...[
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      item.label,
                      style: TextStyle(
                        fontSize: 11.8,
                        fontWeight: selected
                            ? FontWeight.w800
                            : FontWeight.w500,
                        color: selected
                            ? Colors.white
                            : Colors.white.withValues(alpha: 0.72),
                      ),
                    ),
                  ),
                  if (item.badge != null && item.badge! > 0)
                    Container(
                      constraints: const BoxConstraints(minWidth: 20),
                      height: 20,
                      padding: const EdgeInsets.symmetric(horizontal: 5),
                      decoration: BoxDecoration(
                        color: selected ? AppColors.gold : Colors.white,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        '${item.badge}',
                        style: TextStyle(
                          color: selected
                              ? AppColors.navyInk
                              : AppColors.navyDeep,
                          fontSize: 9.5,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                ],
                if (collapsed && item.badge != null && item.badge! > 0) ...[
                  const SizedBox(width: 3),
                  Container(
                    constraints: const BoxConstraints(minWidth: 14),
                    height: 14,
                    padding: const EdgeInsets.symmetric(horizontal: 3),
                    decoration: BoxDecoration(
                      color: AppColors.gold,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      '${item.badge}',
                      style: const TextStyle(
                        color: AppColors.navyInk,
                        fontSize: 7.5,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );

    return collapsed
        ? Tooltip(
            message: item.badge != null && item.badge! > 0
                ? '${item.label} (${item.badge})'
                : item.label,
            child: tile,
          )
        : tile;
  }
}

class _SidebarFooter extends StatelessWidget {
  const _SidebarFooter({required this.role, required this.collapsed});

  final UserRole role;
  final bool collapsed;

  @override
  Widget build(BuildContext context) {
    if (collapsed) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 20, top: 12),
        child: Column(
          children: [
            Tooltip(
              message: '${role.label} • Secure session',
              child: Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(11),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.10),
                  ),
                ),
                child: const Icon(
                  Icons.shield_rounded,
                  color: AppColors.gold,
                  size: 20,
                ),
              ),
            ),
            const SizedBox(height: 9),
            Container(
              width: 7,
              height: 7,
              decoration: const BoxDecoration(
                color: Color(0xFF4ADE80),
                shape: BoxShape.circle,
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.fromLTRB(14, 12, 14, 18),
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 33,
                height: 33,
                decoration: BoxDecoration(
                  color: role.accent.withValues(alpha: 0.20),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Icon(role.icon, color: Colors.white, size: 17),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      role.personName,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11.3,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      role.shortLabel,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.58),
                        fontSize: 9.2,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            role.org,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.76),
              fontSize: 9.5,
              fontWeight: FontWeight.w600,
            ),
          ),
          Text(
            role.location,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.44),
              fontSize: 8.8,
            ),
          ),
          const SizedBox(height: 11),
          Divider(color: Colors.white.withValues(alpha: 0.10), height: 1),
          const SizedBox(height: 9),
          Row(
            children: [
              Container(
                width: 6,
                height: 6,
                decoration: const BoxDecoration(
                  color: Color(0xFF4ADE80),
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'SECURE SESSION • TLS 1.3',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.48),
                    fontSize: 7.2,
                    letterSpacing: 0.45,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Shared workspace widgets
// -----------------------------------------------------------------------------

class WorkspacePage extends StatelessWidget {
  const WorkspacePage({
    super.key,
    required this.header,
    required this.children,
  });

  final Widget header;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.sizeOf(context).width;
    final horizontal = screenWidth < 700
        ? 16.0
        : screenWidth < 1200
        ? 22.0
        : 28.0;
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(horizontal, 24, horizontal, 40),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1580),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              header,
              const SizedBox(height: 22),
              for (var index = 0; index < children.length; index++) ...[
                children[index],
                if (index != children.length - 1) const SizedBox(height: 18),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class WorkspaceHeader extends StatelessWidget {
  const WorkspaceHeader({
    super.key,
    required this.eyebrow,
    required this.title,
    required this.subtitle,
    this.actions = const [],
  });

  final String eyebrow;
  final String title;
  final String subtitle;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final titleBlock = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 3,
              height: 13,
              decoration: BoxDecoration(
                color: AppColors.gold,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                eyebrow.toUpperCase(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 9.2,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.15,
                  color: AppColors.gold,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          title,
          style: const TextStyle(
            fontSize: 28,
            height: 1.12,
            letterSpacing: -0.7,
            fontWeight: FontWeight.w900,
            color: AppColors.navyInk,
          ),
        ),
        const SizedBox(height: 6),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 850),
          child: Text(
            subtitle,
            style: const TextStyle(
              fontSize: 12.2,
              color: AppColors.muted,
              height: 1.5,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );

    if (actions.isEmpty) return titleBlock;

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 850) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              titleBlock,
              const SizedBox(height: 15),
              Wrap(spacing: 10, runSpacing: 10, children: actions),
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(child: titleBlock),
            const SizedBox(width: 24),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              alignment: WrapAlignment.end,
              children: actions,
            ),
          ],
        );
      },
    );
  }
}

class KpiGrid extends StatelessWidget {
  const KpiGrid({super.key, required this.cards});

  final List<Widget> cards;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final columns = width >= 1000
            ? 4
            : width >= 650
            ? 2
            : 1;
        final itemWidth = (width - 16 * (columns - 1)) / columns;
        return Wrap(
          spacing: 16,
          runSpacing: 16,
          children: cards
              .map((card) => SizedBox(width: itemWidth, child: card))
              .toList(),
        );
      },
    );
  }
}

class KpiCard extends StatelessWidget {
  const KpiCard({
    super.key,
    required this.label,
    required this.value,
    required this.helper,
    required this.icon,
    required this.color,
    this.pill,
  });

  final String label;
  final String value;
  final String helper;
  final IconData icon;
  final Color color;
  final Widget? pill;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
        boxShadow: [
          BoxShadow(
            color: AppColors.navy.withValues(alpha: 0.045),
            blurRadius: 18,
            offset: const Offset(0, 7),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.09),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: color.withValues(alpha: 0.12)),
                ),
                child: Icon(icon, size: 21, color: color),
              ),
              const Spacer(),
              pill ?? const SizedBox.shrink(),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            label.toUpperCase(),
            style: const TextStyle(
              fontSize: 9.2,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.95,
              color: AppColors.muted,
            ),
          ),
          const SizedBox(height: 5),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              maxLines: 1,
              style: const TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.w900,
                letterSpacing: -0.8,
                color: AppColors.navyInk,
                height: 1.05,
              ),
            ),
          ),
          const SizedBox(height: 5),
          Text(
            helper,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 10.5,
              color: AppColors.muted,
              height: 1.35,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

class SectionCard extends StatelessWidget {
  const SectionCard({
    super.key,
    this.title,
    this.subtitle,
    this.trailing,
    required this.child,
    this.contentPadding = EdgeInsets.zero,
    this.accentColor = AppColors.gold,
  });

  final String? title;
  final String? subtitle;
  final Widget? trailing;
  final Widget child;
  final EdgeInsets contentPadding;
  final Color accentColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
        boxShadow: [
          BoxShadow(
            color: AppColors.navy.withValues(alpha: 0.035),
            blurRadius: 18,
            offset: const Offset(0, 7),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (title != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 18, 14),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Container(
                      width: 3,
                      height: 25,
                      decoration: BoxDecoration(
                        color: accentColor,
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                    const SizedBox(width: 11),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title!,
                            style: const TextStyle(
                              fontSize: 14.5,
                              fontWeight: FontWeight.w800,
                              color: AppColors.navyInk,
                            ),
                          ),
                          if (subtitle != null) ...[
                            const SizedBox(height: 2),
                            Text(
                              subtitle!,
                              style: const TextStyle(
                                fontSize: 10.8,
                                color: AppColors.muted,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    if (trailing != null) ...[
                      const SizedBox(width: 12),
                      trailing!,
                    ],
                  ],
                ),
              ),
            if (title != null) const Divider(height: 1),
            Padding(padding: contentPadding, child: child),
          ],
        ),
      ),
    );
  }
}

class AppButton extends StatelessWidget {
  const AppButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.primary = true,
    this.color = AppColors.navy,
    this.dense = false,
    this.fullWidth = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool primary;
  final Color color;
  final bool dense;
  final bool fullWidth;

  @override
  Widget build(BuildContext context) {
    final height = dense ? 34.0 : 44.0;
    final padding = EdgeInsets.symmetric(horizontal: dense ? 12 : 17);
    final textStyle = TextStyle(
      fontSize: dense ? 10.8 : 12.2,
      fontWeight: FontWeight.w700,
      letterSpacing: 0.05,
    );

    final content = Row(
      mainAxisSize: fullWidth ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (icon != null) ...[
          Icon(icon, size: dense ? 14 : 17),
          const SizedBox(width: 6),
        ],
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: textStyle,
          ),
        ),
      ],
    );

    final button = primary
        ? FilledButton(
            onPressed: onPressed,
            style: FilledButton.styleFrom(
              backgroundColor: color,
              foregroundColor: Colors.white,
              disabledBackgroundColor: color.withValues(alpha: 0.28),
              disabledForegroundColor: Colors.white.withValues(alpha: 0.7),
              padding: padding,
              minimumSize: Size(0, height),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(9),
              ),
              elevation: 0,
            ),
            child: content,
          )
        : OutlinedButton(
            onPressed: onPressed,
            style: OutlinedButton.styleFrom(
              foregroundColor: color,
              side: BorderSide(color: color.withValues(alpha: 0.32)),
              padding: padding,
              minimumSize: Size(0, height),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(9),
              ),
            ),
            child: content,
          );

    return SizedBox(
      height: height,
      width: fullWidth ? double.infinity : null,
      child: button,
    );
  }
}

class StatusPill extends StatelessWidget {
  const StatusPill({super.key, required this.status});

  final FDRStatus status;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5.5),
      decoration: BoxDecoration(
        color: status.bg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: status.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(status.icon, size: 12, color: status.fg),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              status.label,
              style: TextStyle(
                color: status.fg,
                fontSize: 9.4,
                fontWeight: FontWeight.w800,
                height: 1.2,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class ComplianceBadge extends StatelessWidget {
  const ComplianceBadge({super.key, required this.deficiency});

  final bool deficiency;

  @override
  Widget build(BuildContext context) {
    final color = deficiency ? AppColors.red : AppColors.emeraldDark;
    final bg = deficiency ? const Color(0xFFFEF2F2) : const Color(0xFFECFDF5);
    final border = deficiency
        ? const Color(0xFFFECACA)
        : const Color(0xFFA7F3D0);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            deficiency
                ? Icons.warning_amber_rounded
                : Icons.verified_user_rounded,
            size: 13,
            color: color,
          ),
          const SizedBox(width: 5),
          Text(
            deficiency ? 'Deficiency / Time Exceeded' : 'Zero Deficiency',
            style: TextStyle(
              fontSize: 9.4,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class BankMark extends StatelessWidget {
  const BankMark({super.key, required this.bankName, this.size = 36});

  final String bankName;
  final double size;

  @override
  Widget build(BuildContext context) {
    final color = bankColor(bankName);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(size * 0.27),
        border: Border.all(color: color.withValues(alpha: 0.17)),
      ),
      alignment: Alignment.center,
      child: Text(
        bankAbbreviation(bankName),
        style: TextStyle(
          color: color,
          fontSize: size * 0.27,
          fontWeight: FontWeight.w900,
          letterSpacing: -0.2,
        ),
      ),
    );
  }
}

class SoftChip extends StatelessWidget {
  const SoftChip({
    super.key,
    required this.label,
    this.icon,
    this.color = AppColors.navy,
  });

  final String label;
  final IconData? icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: color.withValues(alpha: 0.14)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: color),
            const SizedBox(width: 4),
          ],
          Flexible(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 9.2,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class InfoBanner extends StatelessWidget {
  const InfoBanner({
    super.key,
    required this.title,
    required this.message,
    this.icon = Icons.info_outline_rounded,
    this.color = AppColors.navy,
    this.trailing,
  });

  final String title;
  final String message;
  final IconData icon;
  final Color color;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.045),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.13)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 17, color: color),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w800,
                    color: color,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  message,
                  style: const TextStyle(
                    fontSize: 10.5,
                    color: AppColors.muted,
                    height: 1.45,
                  ),
                ),
              ],
            ),
          ),
          if (trailing != null) ...[const SizedBox(width: 12), trailing!],
        ],
      ),
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.title,
    required this.message,
    this.icon = Icons.inbox_rounded,
    this.color = AppColors.navy,
    this.action,
  });

  final String title;
  final String message;
  final IconData icon;
  final Color color;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 38),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.06),
              shape: BoxShape.circle,
              border: Border.all(color: color.withValues(alpha: 0.12)),
            ),
            child: Icon(icon, color: color, size: 25),
          ),
          const SizedBox(height: 13),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: AppColors.navyInk,
            ),
          ),
          const SizedBox(height: 4),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 10.8,
                color: AppColors.muted,
                height: 1.5,
              ),
            ),
          ),
          if (action != null) ...[const SizedBox(height: 16), action!],
        ],
      ),
    );
  }
}

class TableScroll extends StatelessWidget {
  const TableScroll({super.key, required this.minWidth, required this.child});

  final double minWidth;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: ConstrainedBox(
        constraints: BoxConstraints(minWidth: minWidth),
        child: child,
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Shared helpers & dialogs
// -----------------------------------------------------------------------------

void showAppToast(
  BuildContext context,
  String message, {
  IconData icon = Icons.check_circle_rounded,
  Color color = AppColors.navyInk,
}) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return;
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 4),
        margin: const EdgeInsets.all(18),
        backgroundColor: color,
        content: Row(
          children: [
            Icon(icon, color: Colors.white, size: 18),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
}

Future<bool> showConfirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
  String cancelLabel = 'Cancel',
  Color confirmColor = AppColors.navy,
  IconData icon = Icons.info_outline_rounded,
  Widget? extra,
}) async {
  final result = await showDialog<bool>(
    context: context,
    barrierColor: AppColors.navyInk.withValues(alpha: 0.46),
    builder: (dialogContext) {
      return AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        backgroundColor: Colors.white,
        insetPadding: const EdgeInsets.all(24),
        title: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: confirmColor.withValues(alpha: 0.09),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: confirmColor, size: 20),
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: AppColors.navyInk,
                ),
              ),
            ),
          ],
        ),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                message,
                style: const TextStyle(
                  fontSize: 12,
                  height: 1.55,
                  color: AppColors.ink,
                ),
              ),
              if (extra != null) ...[const SizedBox(height: 14), extra],
            ],
          ),
        ),
        actionsPadding: const EdgeInsets.fromLTRB(20, 4, 20, 18),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(
              cancelLabel,
              style: const TextStyle(
                color: AppColors.muted,
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: confirmColor,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(9),
              ),
            ),
            child: Text(
              confirmLabel,
              style: const TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      );
    },
  );
  return result ?? false;
}

Future<String?> showReasonDialog(
  BuildContext context, {
  required String title,
  required String message,
  required String fieldLabel,
  required String initialReason,
  required String confirmLabel,
  Color confirmColor = AppColors.navy,
  IconData icon = Icons.edit_note_rounded,
}) async {
  return showDialog<String>(
    context: context,
    barrierColor: AppColors.navyInk.withValues(alpha: 0.46),
    builder: (context) => _ReasonDialog(
      title: title,
      message: message,
      fieldLabel: fieldLabel,
      initialReason: initialReason,
      confirmLabel: confirmLabel,
      confirmColor: confirmColor,
      icon: icon,
    ),
  );
}

class _ReasonDialog extends StatefulWidget {
  const _ReasonDialog({
    required this.title,
    required this.message,
    required this.fieldLabel,
    required this.initialReason,
    required this.confirmLabel,
    required this.confirmColor,
    required this.icon,
  });

  final String title;
  final String message;
  final String fieldLabel;
  final String initialReason;
  final String confirmLabel;
  final Color confirmColor;
  final IconData icon;

  @override
  State<_ReasonDialog> createState() => _ReasonDialogState();
}

class _ReasonDialogState extends State<_ReasonDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialReason);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reason = _controller.text.trim();
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      insetPadding: const EdgeInsets.all(24),
      title: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: widget.confirmColor.withValues(alpha: 0.09),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(widget.icon, color: widget.confirmColor, size: 20),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Text(
              widget.title,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: AppColors.navyInk,
              ),
            ),
          ),
        ],
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.message,
              style: const TextStyle(
                fontSize: 12,
                height: 1.55,
                color: AppColors.ink,
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _controller,
              maxLines: 3,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: widget.fieldLabel,
                alignLabelWithHint: true,
              ),
            ),
          ],
        ),
      ),
      actionsPadding: const EdgeInsets.fromLTRB(20, 4, 20, 18),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text(
            'Cancel',
            style: TextStyle(
              color: AppColors.muted,
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        FilledButton(
          onPressed: reason.isEmpty
              ? null
              : () => Navigator.of(context).pop(reason),
          style: FilledButton.styleFrom(
            backgroundColor: widget.confirmColor,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(9),
            ),
          ),
          child: Text(
            widget.confirmLabel,
            style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700),
          ),
        ),
      ],
    );
  }
}

class PortalDialogFrame extends StatelessWidget {
  const PortalDialogFrame({
    super.key,
    required this.title,
    required this.icon,
    required this.body,
    this.eyebrow = 'E-KOSH AICTE',
    this.subtitle,
    this.actions = const [],
    this.maxWidth = 940,
    this.accent = AppColors.gold,
    this.bodyPadding = const EdgeInsets.all(22),
  });

  final String title;
  final String icon;
  final Widget body;
  final String eyebrow;
  final String? subtitle;
  final List<Widget> actions;
  final double maxWidth;
  final Color accent;
  final EdgeInsets bodyPadding;

  @override
  Widget build(BuildContext context) {
    final maxHeight = MediaQuery.sizeOf(context).height * 0.9;
    return Dialog(
      insetPadding: const EdgeInsets.all(22),
      backgroundColor: Colors.transparent,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth, maxHeight: maxHeight),
        child: Material(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          clipBehavior: Clip.antiAlias,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.fromLTRB(22, 18, 12, 17),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [AppColors.navyDeep, AppColors.navy],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(11),
                        border: Border.all(
                          color: accent.withValues(alpha: 0.35),
                        ),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        icon,
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w900,
                          color: accent,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            eyebrow.toUpperCase(),
                            style: TextStyle(
                              fontSize: 8.4,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 1.1,
                              color: accent,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            title,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                              height: 1.15,
                            ),
                          ),
                          if (subtitle != null) ...[
                            const SizedBox(height: 4),
                            Text(
                              subtitle!,
                              style: TextStyle(
                                fontSize: 10.5,
                                color: Colors.white.withValues(alpha: 0.65),
                                height: 1.4,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: Icon(
                        Icons.close_rounded,
                        color: Colors.white.withValues(alpha: 0.75),
                        size: 20,
                      ),
                      tooltip: 'Close',
                    ),
                  ],
                ),
              ),
              Flexible(
                child: SingleChildScrollView(padding: bodyPadding, child: body),
              ),
              if (actions.isNotEmpty) ...[
                const Divider(height: 1),
                Container(
                  padding: const EdgeInsets.fromLTRB(20, 13, 20, 14),
                  color: Colors.white,
                  child: Wrap(
                    alignment: WrapAlignment.end,
                    spacing: 10,
                    runSpacing: 8,
                    children: actions,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Dashboard 1: Institute / College Admin
// -----------------------------------------------------------------------------

class InstitutePortfolioPage extends StatelessWidget {
  const InstitutePortfolioPage({super.key, required this.state});

  final PortalState state;

  @override
  Widget build(BuildContext context) {
    final records = state.instituteRecords;
    return WorkspacePage(
      header: WorkspaceHeader(
        eyebrow: 'Institute workspace • KPR / ${state.role.org}',
        title: 'My FDR Portfolio & Live Tracker',
        subtitle:
            'Track every joint security deposit from upload to final settlement across AICTE and partner banks. Click any record to open its five-stage lifecycle tracker.',
        actions: [
          AppButton(
            label: 'Download Portfolio',
            icon: Icons.download_rounded,
            primary: false,
            onPressed: () => showAppToast(
              context,
              'Portfolio summary prepared for download (demo).',
              icon: Icons.download_done_rounded,
            ),
          ),
          AppButton(
            label: 'New FDR Submission',
            icon: Icons.add_rounded,
            color: AppColors.gold,
            onPressed: () => state.selectNav(1),
          ),
        ],
      ),
      children: [
        KpiGrid(
          cards: [
            KpiCard(
              label: 'Total Active FDRs',
              value: '${state.instituteActiveDeposits.length}',
              helper:
                  '${state.instituteLockedDeposits.length} instruments held across partner banks',
              icon: Icons.account_balance_rounded,
              color: AppColors.navy,
            ),
            KpiCard(
              label: 'Total Deposit Locked',
              value: inr(state.instituteLockedValue),
              helper: 'Bank-held security deposit in the institute portfolio',
              icon: Icons.lock_rounded,
              color: AppColors.gold,
            ),
            KpiCard(
              label: 'Maturing Soon',
              value: '${state.instituteMaturingSoon.length}',
              helper: 'Deposits reaching maturity within the next 180 days',
              icon: Icons.event_available_rounded,
              color: AppColors.orange,
            ),
            KpiCard(
              label: 'Pending Requests',
              value: '${state.institutePendingRequests.length}',
              helper: 'Awaiting action from bank, RO or AICTE Finance',
              icon: Icons.pending_actions_rounded,
              color: AppColors.indigo,
            ),
          ],
        ),
        InfoBanner(
          title: 'Release window open for matured deposits',
          message:
              'Only an FDR that has crossed its maturity date is eligible for a release / refund application. Submitting an application moves the record to the Southern Regional Office for scrutiny.',
          icon: Icons.info_outline_rounded,
          color: AppColors.gold,
          trailing: SoftChip(
            label: '5-stage tracker enabled',
            icon: Icons.timeline_rounded,
            color: AppColors.gold,
          ),
        ),
        SectionCard(
          title: 'My FDR Portfolio & Live Tracker',
          subtitle:
              'Joint FDRs registered by KPR Institute of Technology • ID 1-492831',
          trailing: SoftChip(
            label: '${records.length} FDR${records.length == 1 ? '' : 's'}',
            icon: Icons.folder_copy_rounded,
            color: AppColors.navy,
          ),
          contentPadding: const EdgeInsets.only(bottom: 8),
          child: records.isEmpty
              ? EmptyState(
                  title: 'No FDRs in the portfolio yet',
                  message:
                      'Submit a new joint FDR to begin the bank verification and lien-locking workflow.',
                  icon: Icons.account_balance_rounded,
                  color: AppColors.navy,
                  action: AppButton(
                    label: 'Create a new submission',
                    icon: Icons.add_card_rounded,
                    color: AppColors.gold,
                    onPressed: () => state.selectNav(1),
                  ),
                )
              : TableScroll(
                  minWidth: 1130,
                  child: DataTable(
                    showCheckboxColumn: false,
                    horizontalMargin: 20,
                    columnSpacing: 22,
                    headingRowHeight: 46,
                    dataRowMinHeight: 72,
                    dataRowMaxHeight: 90,
                    headingRowColor: const WidgetStatePropertyAll(
                      AppColors.surfaceSoft,
                    ),
                    headingTextStyle: const TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.8,
                      color: AppColors.muted,
                    ),
                    dataTextStyle: const TextStyle(
                      fontSize: 11.5,
                      color: AppColors.ink,
                    ),
                    dividerThickness: 1,
                    border: const TableBorder(
                      horizontalInside: BorderSide(color: AppColors.softBorder),
                    ),
                    columns: const [
                      DataColumn(label: Text('FDR / BANK')),
                      DataColumn(label: Text('PROGRAM & INTAKE')),
                      DataColumn(label: Text('DEPOSIT AMOUNT')),
                      DataColumn(label: Text('MATURITY')),
                      DataColumn(label: Text('LIFECYCLE STATUS')),
                      DataColumn(label: Text('ACTION')),
                    ],
                    rows: records.map((record) {
                      final canApply =
                          record.status == FDRStatus.activeLienLocked &&
                          record.isMatured;
                      return DataRow(
                        onSelectChanged: (_) =>
                            showTrackerDialog(context, record),
                        cells: [
                          DataCell(
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                BankMark(bankName: record.bankName),
                                const SizedBox(width: 10),
                                Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      record.id,
                                      style: const TextStyle(
                                        fontSize: 11.5,
                                        fontWeight: FontWeight.w800,
                                        color: AppColors.navyInk,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      '${record.bankName} • ${record.ifsc}',
                                      style: const TextStyle(
                                        fontSize: 9.2,
                                        color: AppColors.muted,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          DataCell(
                            Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  record.program,
                                  style: const TextStyle(
                                    fontSize: 10.8,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'Intake ${record.intake} seats',
                                  style: const TextStyle(
                                    fontSize: 9.2,
                                    color: AppColors.muted,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          DataCell(
                            Text(
                              inr(record.amount),
                              style: const TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w900,
                                color: AppColors.navyInk,
                              ),
                            ),
                          ),
                          DataCell(
                            Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  formatDate(record.maturityDate),
                                  style: const TextStyle(
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  record.isMatured
                                      ? 'Maturity reached'
                                      : '${record.maturityDate.difference(DateTime.now()).inDays} days remaining',
                                  style: TextStyle(
                                    fontSize: 9.2,
                                    color: record.isMatured
                                        ? AppColors.gold
                                        : AppColors.muted,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          DataCell(StatusPill(status: record.status)),
                          DataCell(
                            canApply
                                ? AppButton(
                                    label: 'Apply for Release',
                                    icon: Icons.assignment_turned_in_rounded,
                                    dense: true,
                                    color: AppColors.gold,
                                    onPressed: () => _applyForRelease(
                                      context,
                                      state,
                                      record,
                                    ),
                                  )
                                : AppButton(
                                    label: 'Track lifecycle',
                                    icon: Icons.arrow_forward_rounded,
                                    primary: false,
                                    dense: true,
                                    onPressed: () =>
                                        showTrackerDialog(context, record),
                                  ),
                          ),
                        ],
                      );
                    }).toList(),
                  ),
                ),
        ),
        SectionCard(
          title: 'How the release lifecycle works',
          subtitle:
              'A single audit trail from the bank receipt to AICTE Finance settlement.',
          contentPadding: const EdgeInsets.all(20),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final columns = constraints.maxWidth >= 980
                  ? 5
                  : constraints.maxWidth >= 560
                  ? 2
                  : 1;
              final itemWidth =
                  (constraints.maxWidth - 12 * (columns - 1)) / columns;
              const stages = [
                (
                  Icons.upload_file_rounded,
                  'Upload',
                  'Institute files the joint FDR',
                ),
                (
                  Icons.lock_rounded,
                  'Lien Lock',
                  'Bank verifies and marks AICTE lien',
                ),
                (
                  Icons.event_available_rounded,
                  'Maturity',
                  'Deposit completes its tenure',
                ),
                (
                  Icons.rule_folder_rounded,
                  'RO Scrutiny',
                  'Regional office checks compliance',
                ),
                (
                  Icons.account_balance_wallet_rounded,
                  'Settlement',
                  'Finance issues e-NOC and bank pays',
                ),
              ];
              return Wrap(
                spacing: 12,
                runSpacing: 12,
                children: List.generate(stages.length, (index) {
                  final stage = stages[index];
                  return SizedBox(
                    width: itemWidth,
                    child: Container(
                      padding: const EdgeInsets.all(13),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceSoft,
                        borderRadius: BorderRadius.circular(11),
                        border: Border.all(color: AppColors.softBorder),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                width: 30,
                                height: 30,
                                decoration: BoxDecoration(
                                  color: AppColors.navy.withValues(alpha: 0.07),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Icon(
                                  stage.$1,
                                  size: 15,
                                  color: AppColors.navy,
                                ),
                              ),
                              const Spacer(),
                              Text(
                                '0${index + 1}',
                                style: const TextStyle(
                                  color: AppColors.gold,
                                  fontSize: 9,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 9),
                          Text(
                            stage.$2,
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              color: AppColors.navyInk,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            stage.$3,
                            style: const TextStyle(
                              fontSize: 9.2,
                              color: AppColors.muted,
                              height: 1.35,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }),
              );
            },
          ),
        ),
      ],
    );
  }
}

Future<void> _applyForRelease(
  BuildContext context,
  PortalState state,
  FDRRecord record,
) async {
  final confirmed = await showConfirmDialog(
    context,
    title: 'Apply for release / refund?',
    message:
        '${record.id} has reached maturity. The release application will be submitted to the Southern Regional Office and the FDR will move to "Matured - Pending RO Scrutiny".',
    confirmLabel: 'Submit Application',
    confirmColor: AppColors.gold,
    icon: Icons.assignment_turned_in_rounded,
    extra: _DialogAmountBox(
      label: 'Deposit amount',
      value: inr(record.amount),
      helper: '${record.bankName} • ${record.ifsc}',
    ),
  );
  if (!confirmed || !context.mounted) return;
  state.applyForRelease(record);
  showAppToast(
    context,
    'Release application for ${record.id} submitted to the Regional Office.',
    icon: Icons.assignment_turned_in_rounded,
    color: AppColors.emeraldDark,
  );
}

class InstituteSubmissionPage extends StatefulWidget {
  const InstituteSubmissionPage({super.key, required this.state});

  final PortalState state;

  @override
  State<InstituteSubmissionPage> createState() =>
      _InstituteSubmissionPageState();
}

class _InstituteSubmissionPageState extends State<InstituteSubmissionPage> {
  static const _programs = [
    'B.Tech - Computer Science',
    'B.Tech - Electronics & Communication',
    'B.Tech - Mechanical Engineering',
    'B.Tech - Information Technology',
    'MBA - General Management',
    'M.Tech - Structural Engineering',
  ];
  static const _intakes = [36, 60, 90, 120, 180, 240, 300];
  static const _bankIfsc = {
    'State Bank of India': 'SBIN0004321',
    'Bank of Baroda': 'BARB0COIMBA',
    'Punjab National Bank': 'PUNB0COIMBT',
    'Canara Bank': 'CNRB0COIMBT',
    'HDFC Bank': 'HDFC0COIMBA',
  };

  final _formKey = GlobalKey<FormState>();
  final _ifscController = TextEditingController();
  final _fdrController = TextEditingController();
  final _amountController = TextEditingController();
  final _issueController = TextEditingController();
  final _maturityController = TextEditingController();

  String _bank = 'State Bank of India';
  String _program = 'B.Tech - Computer Science';
  int _intake = 120;
  late DateTime _issueDate;
  late DateTime _maturityDate;

  static const _baseDeposit = 500000.0;
  static const _perSeat = 10000.0;

  double get _calculatedDeposit => _baseDeposit + (_perSeat * _intake);

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _issueDate = DateTime(now.year, now.month, now.day);
    _maturityDate = DateTime(now.year + 1, now.month, now.day);
    _ifscController.text = _bankIfsc[_bank]!;
    _fdrController.text = widget.state.suggestFdrNumber(_bank);
    _amountController.text = _calculatedDeposit.toStringAsFixed(0);
    _issueController.text = formatDate(_issueDate);
    _maturityController.text = formatDate(_maturityDate);
  }

  @override
  void dispose() {
    _ifscController.dispose();
    _fdrController.dispose();
    _amountController.dispose();
    _issueController.dispose();
    _maturityController.dispose();
    super.dispose();
  }

  void _onBankChanged(String? bank) {
    if (bank == null) return;
    setState(() {
      _bank = bank;
      _ifscController.text = _bankIfsc[bank]!;
      _fdrController.text = widget.state.suggestFdrNumber(bank);
    });
  }

  Future<void> _pickDate({required bool issue}) async {
    final initial = issue ? _issueDate : _maturityDate;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2015),
      lastDate: DateTime(2040),
      helpText: issue ? 'Select FDR issue date' : 'Select FDR maturity date',
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: Theme.of(context).colorScheme.copyWith(
              primary: AppColors.navy,
              secondary: AppColors.gold,
            ),
          ),
          child: child ?? const SizedBox.shrink(),
        );
      },
    );
    if (picked == null) return;
    setState(() {
      if (issue) {
        _issueDate = picked;
        _issueController.text = formatDate(picked);
      } else {
        _maturityDate = picked;
        _maturityController.text = formatDate(picked);
      }
    });
  }

  void _applyCalculatedAmount() {
    _amountController.text = _calculatedDeposit.toStringAsFixed(0);
    showAppToast(
      context,
      'Calculated deposit of ${inr(_calculatedDeposit)} copied to the form.',
      icon: Icons.calculate_rounded,
      color: AppColors.navy,
    );
  }

  void _submit() {
    final formValid = _formKey.currentState?.validate() ?? false;
    if (!formValid) return;
    if (!_maturityDate.isAfter(_issueDate)) {
      showAppToast(
        context,
        'Maturity date must be later than the issue date.',
        icon: Icons.warning_amber_rounded,
        color: AppColors.red,
      );
      return;
    }
    final amount = double.tryParse(_amountController.text) ?? 0;
    final fdrNumber = _fdrController.text.trim();
    widget.state.addFdr(
      bankName: _bank,
      ifsc: _ifscController.text,
      fdrNumber: fdrNumber,
      amount: amount,
      issueDate: _issueDate,
      maturityDate: _maturityDate,
      program: _program,
      intake: _intake,
    );
    showAppToast(
      context,
      '$fdrNumber submitted to $_bank for lien verification.',
      icon: Icons.upload_file_rounded,
      color: AppColors.emeraldDark,
    );
    widget.state.selectNav(0);
  }

  @override
  Widget build(BuildContext context) {
    return WorkspacePage(
      header: WorkspaceHeader(
        eyebrow: 'Institute workspace • joint FDR onboarding',
        title: 'New Joint FDR Submission',
        subtitle:
            'Calculate the mandated security deposit, capture the bank instrument details, and route the FDR for digital lien verification.',
        actions: [
          AppButton(
            label: 'Back to Portfolio',
            icon: Icons.arrow_back_rounded,
            primary: false,
            onPressed: () => widget.state.selectNav(0),
          ),
        ],
      ),
      children: [
        InfoBanner(
          title: 'Joint holding mandate',
          message:
              'Every FDR must be held jointly in the name of AICTE and KPR Institute of Technology, with a lien marked in favour of AICTE. The partner bank will validate the receipt before the lien is locked.',
          icon: Icons.shield_rounded,
          color: AppColors.emeraldDark,
          trailing: const SoftChip(
            label: 'AICTE + Institute',
            icon: Icons.people_alt_rounded,
            color: AppColors.emeraldDark,
          ),
        ),
        LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 980;
            final calculator = _DepositCalculatorCard(
              program: _program,
              intake: _intake,
              programs: _programs,
              intakes: _intakes,
              baseDeposit: _baseDeposit,
              perSeat: _perSeat,
              calculatedDeposit: _calculatedDeposit,
              onProgramChanged: (value) {
                if (value == null) return;
                setState(() => _program = value);
              },
              onIntakeChanged: (value) {
                if (value == null) return;
                setState(() => _intake = value);
              },
              onApply: _applyCalculatedAmount,
            );
            final form = _buildSubmissionForm(context);
            if (!wide) {
              return Column(
                children: [calculator, const SizedBox(height: 18), form],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 4, child: calculator),
                const SizedBox(width: 18),
                Expanded(flex: 6, child: form),
              ],
            );
          },
        ),
        SectionCard(
          title: 'Verification journey after submission',
          subtitle:
              'No manual follow-up is required — each stakeholder receives the request in their queue.',
          contentPadding: const EdgeInsets.all(20),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth >= 860;
              final width = wide
                  ? (constraints.maxWidth - 24) / 3
                  : constraints.maxWidth;
              const steps = [
                (
                  Icons.account_balance_rounded,
                  'Bank verification',
                  'The bank inspects the digital receipt and locks the joint lien.',
                  AppColors.orange,
                ),
                (
                  Icons.timeline_rounded,
                  'Live lifecycle tracking',
                  'The deposit remains visible in the portfolio until maturity.',
                  AppColors.navy,
                ),
                (
                  Icons.verified_user_rounded,
                  'RO & Finance settlement',
                  'Release applications pass through RO scrutiny and Finance e-NOC.',
                  AppColors.emeraldDark,
                ),
              ];
              return Wrap(
                spacing: 12,
                runSpacing: 12,
                children: steps.map((step) {
                  return SizedBox(
                    width: width,
                    child: Container(
                      padding: const EdgeInsets.all(15),
                      decoration: BoxDecoration(
                        color: step.$4.withValues(alpha: 0.045),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: step.$4.withValues(alpha: 0.13),
                        ),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: 34,
                            height: 34,
                            decoration: BoxDecoration(
                              color: step.$4.withValues(alpha: 0.10),
                              borderRadius: BorderRadius.circular(9),
                            ),
                            child: Icon(step.$1, size: 17, color: step.$4),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  step.$2,
                                  style: const TextStyle(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w800,
                                    color: AppColors.navyInk,
                                  ),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  step.$3,
                                  style: const TextStyle(
                                    fontSize: 9.8,
                                    color: AppColors.muted,
                                    height: 1.4,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildSubmissionForm(BuildContext context) {
    return SectionCard(
      title: 'Joint FDR Details',
      subtitle:
          'Enter the bank instrument particulars exactly as printed on the FDR.',
      trailing: SoftChip(
        label: _program,
        icon: Icons.school_rounded,
        color: AppColors.navy,
      ),
      contentPadding: const EdgeInsets.all(20),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            LayoutBuilder(
              builder: (context, constraints) {
                final fieldWidth = constraints.maxWidth >= 560
                    ? (constraints.maxWidth - 14) / 2
                    : constraints.maxWidth;
                return Wrap(
                  spacing: 14,
                  runSpacing: 14,
                  children: [
                    SizedBox(
                      width: fieldWidth,
                      child: DropdownButtonFormField<String>(
                        initialValue: _bank,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'Bank Name',
                          prefixIcon: Icon(
                            Icons.account_balance_rounded,
                            size: 18,
                          ),
                        ),
                        items: _bankIfsc.keys
                            .map(
                              (bank) => DropdownMenuItem(
                                value: bank,
                                child: Text(
                                  bank,
                                  style: const TextStyle(fontSize: 11.5),
                                ),
                              ),
                            )
                            .toList(),
                        onChanged: _onBankChanged,
                      ),
                    ),
                    SizedBox(
                      width: fieldWidth,
                      child: TextFormField(
                        controller: _ifscController,
                        textCapitalization: TextCapitalization.characters,
                        inputFormatters: [
                          LengthLimitingTextInputFormatter(11),
                          _UpperCaseFormatter(),
                        ],
                        decoration: const InputDecoration(
                          labelText: 'IFSC Code',
                          hintText: 'SBIN0004321',
                          prefixIcon: Icon(Icons.tag_rounded, size: 18),
                        ),
                        validator: (value) {
                          final ifsc = value?.trim().toUpperCase() ?? '';
                          if (ifsc.isEmpty) {
                            return 'IFSC code is required';
                          }
                          if (!RegExp(
                            r'^[A-Z]{4}0[A-Z0-9]{6}$',
                          ).hasMatch(ifsc)) {
                            return 'Enter a valid 11-character IFSC';
                          }
                          return null;
                        },
                      ),
                    ),
                    SizedBox(
                      width: fieldWidth,
                      child: TextFormField(
                        controller: _fdrController,
                        textCapitalization: TextCapitalization.characters,
                        inputFormatters: [_UpperCaseFormatter()],
                        decoration: const InputDecoration(
                          labelText: 'FDR Number',
                          hintText: 'FDR-SBI-2026-733',
                          prefixIcon: Icon(
                            Icons.confirmation_number_rounded,
                            size: 18,
                          ),
                        ),
                        validator: (value) {
                          final fdr = value?.trim() ?? '';
                          if (fdr.isEmpty) {
                            return 'FDR number is required';
                          }
                          if (widget.state.fdrNumberExists(fdr)) {
                            return 'This FDR number already exists';
                          }
                          return null;
                        },
                      ),
                    ),
                    SizedBox(
                      width: fieldWidth,
                      child: TextFormField(
                        controller: _amountController,
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                          LengthLimitingTextInputFormatter(10),
                        ],
                        decoration: InputDecoration(
                          labelText: 'Deposit Amount (₹)',
                          hintText: '1700000',
                          prefixIcon: const Icon(
                            Icons.currency_rupee_rounded,
                            size: 18,
                          ),
                          suffixText: 'INR',
                          helperText: inr(
                            double.tryParse(_amountController.text) ?? 0,
                          ),
                        ),
                        onChanged: (_) => setState(() {}),
                        validator: (value) {
                          final amount = double.tryParse(value ?? '') ?? 0;
                          if (amount <= 0) {
                            return 'Enter a valid deposit amount';
                          }
                          if (amount > 100000000) {
                            return 'Amount exceeds portal validation limit';
                          }
                          return null;
                        },
                      ),
                    ),
                    SizedBox(
                      width: fieldWidth,
                      child: TextFormField(
                        controller: _issueController,
                        readOnly: true,
                        onTap: () => _pickDate(issue: true),
                        decoration: const InputDecoration(
                          labelText: 'Issue Date',
                          prefixIcon: Icon(
                            Icons.calendar_today_rounded,
                            size: 17,
                          ),
                          suffixIcon: Icon(
                            Icons.edit_calendar_rounded,
                            size: 17,
                          ),
                        ),
                      ),
                    ),
                    SizedBox(
                      width: fieldWidth,
                      child: TextFormField(
                        controller: _maturityController,
                        readOnly: true,
                        onTap: () => _pickDate(issue: false),
                        decoration: const InputDecoration(
                          labelText: 'Maturity Date',
                          prefixIcon: Icon(
                            Icons.event_available_rounded,
                            size: 18,
                          ),
                          suffixIcon: Icon(
                            Icons.edit_calendar_rounded,
                            size: 17,
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: 15),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.surfaceSoft,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.softBorder),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.assignment_rounded,
                    size: 16,
                    color: AppColors.navy,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Selected for submission: $_program • Intake $_intake seats • Calculated deposit ${inr(_calculatedDeposit)}',
                      style: const TextStyle(
                        fontSize: 9.8,
                        color: AppColors.muted,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            AppButton(
              label: 'Submit to Bank for Verification',
              icon: Icons.upload_rounded,
              color: AppColors.navy,
              fullWidth: true,
              onPressed: _submit,
            ),
            const SizedBox(height: 9),
            const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.lock_outline_rounded,
                  size: 12,
                  color: AppColors.muted,
                ),
                SizedBox(width: 5),
                Flexible(
                  child: Text(
                    'Submission creates a verifiable audit entry and notifies the selected bank.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 8.8, color: AppColors.muted),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _DepositCalculatorCard extends StatelessWidget {
  const _DepositCalculatorCard({
    required this.program,
    required this.intake,
    required this.programs,
    required this.intakes,
    required this.baseDeposit,
    required this.perSeat,
    required this.calculatedDeposit,
    required this.onProgramChanged,
    required this.onIntakeChanged,
    required this.onApply,
  });

  final String program;
  final int intake;
  final List<String> programs;
  final List<int> intakes;
  final double baseDeposit;
  final double perSeat;
  final double calculatedDeposit;
  final ValueChanged<String?> onProgramChanged;
  final ValueChanged<int?> onIntakeChanged;
  final VoidCallback onApply;

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      title: 'Deposit Calculator',
      subtitle:
          'Estimate the security deposit mandated for the selected intake.',
      contentPadding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DropdownButtonFormField<String>(
            initialValue: program,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'Program',
              prefixIcon: Icon(Icons.school_rounded, size: 18),
            ),
            items: programs
                .map(
                  (value) => DropdownMenuItem(
                    value: value,
                    child: Text(value, style: const TextStyle(fontSize: 11.5)),
                  ),
                )
                .toList(),
            onChanged: onProgramChanged,
          ),
          const SizedBox(height: 13),
          DropdownButtonFormField<int>(
            initialValue: intake,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'Intake',
              prefixIcon: Icon(Icons.groups_rounded, size: 18),
            ),
            items: intakes
                .map(
                  (value) => DropdownMenuItem(
                    value: value,
                    child: Text(
                      '$value seats',
                      style: const TextStyle(fontSize: 11.5),
                    ),
                  ),
                )
                .toList(),
            onChanged: onIntakeChanged,
          ),
          const SizedBox(height: 17),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFFFFFBEB), Color(0xFFFFF7ED)],
              ),
              borderRadius: BorderRadius.circular(13),
              border: Border.all(color: AppColors.gold.withValues(alpha: 0.28)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'REQUIRED SECURITY DEPOSIT',
                  style: TextStyle(
                    fontSize: 8.6,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.95,
                    color: AppColors.gold,
                  ),
                ),
                const SizedBox(height: 5),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    inr(calculatedDeposit),
                    style: const TextStyle(
                      fontSize: 30,
                      height: 1.05,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -1,
                      color: AppColors.navyInk,
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${formatIndianNumber(calculatedDeposit)} INR • ${program.split(' - ').first}',
                  style: const TextStyle(
                    fontSize: 9.5,
                    color: AppColors.muted,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _CalculatorLine(
            label: 'AICTE base compliance deposit',
            value: inr(baseDeposit),
          ),
          const SizedBox(height: 8),
          _CalculatorLine(
            label: 'Per-seat component',
            value: '${inr(perSeat)} × $intake',
          ),
          const SizedBox(height: 8),
          _CalculatorLine(
            label: 'Per-seat subtotal',
            value: inr(perSeat * intake),
          ),
          const SizedBox(height: 11),
          const Divider(height: 1),
          const SizedBox(height: 11),
          _CalculatorLine(
            label: 'Total payable',
            value: inr(calculatedDeposit),
            bold: true,
          ),
          const SizedBox(height: 17),
          AppButton(
            label: 'Apply Amount to Form',
            icon: Icons.calculate_rounded,
            color: AppColors.gold,
            fullWidth: true,
            onPressed: onApply,
          ),
          const SizedBox(height: 10),
          const Text(
            'Indicative calculation for the Phase 1 demo. Final deposit is subject to AICTE norms and programme approval.',
            style: TextStyle(
              fontSize: 8.8,
              color: AppColors.muted,
              height: 1.45,
            ),
          ),
        ],
      ),
    );
  }
}

class _CalculatorLine extends StatelessWidget {
  const _CalculatorLine({
    required this.label,
    required this.value,
    this.bold = false,
  });

  final String label;
  final String value;
  final bool bold;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 10,
              color: bold ? AppColors.navyInk : AppColors.muted,
              fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Text(
          value,
          style: TextStyle(
            fontSize: bold ? 11.5 : 10.5,
            color: bold ? AppColors.navyInk : AppColors.ink,
            fontWeight: bold ? FontWeight.w900 : FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _UpperCaseFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    return newValue.copyWith(text: newValue.text.toUpperCase());
  }
}

// -----------------------------------------------------------------------------
// Five-step lifecycle tracker
// -----------------------------------------------------------------------------

Future<void> showTrackerDialog(BuildContext context, FDRRecord record) async {
  await showDialog<void>(
    context: context,
    barrierColor: AppColors.navyInk.withValues(alpha: 0.48),
    builder: (context) => FDRTrackerDialog(record: record),
  );
}

class FDRTrackerDialog extends StatelessWidget {
  const FDRTrackerDialog({super.key, required this.record});

  final FDRRecord record;

  @override
  Widget build(BuildContext context) {
    return PortalDialogFrame(
      title: record.id,
      subtitle: '${record.instituteName} • ${record.bankName} • ${record.ifsc}',
      icon: 'FDR',
      maxWidth: 980,
      actions: [
        AppButton(
          label: 'Close Tracker',
          icon: Icons.close_rounded,
          primary: false,
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.surfaceSoft,
              borderRadius: BorderRadius.circular(13),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(
              children: [
                BankMark(bankName: record.bankName, size: 46),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        record.program,
                        style: const TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w800,
                          color: AppColors.navyInk,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Intake ${record.intake} seats • ${record.instituteId}',
                        style: const TextStyle(
                          fontSize: 9.8,
                          color: AppColors.muted,
                        ),
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      inr(record.amount),
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                        color: AppColors.navyInk,
                        letterSpacing: -0.5,
                      ),
                    ),
                    const SizedBox(height: 3),
                    StatusPill(status: record.status),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            'LIFECYCLE TRACKER',
            style: TextStyle(
              fontSize: 8.8,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.1,
              color: AppColors.gold,
            ),
          ),
          const SizedBox(height: 13),
          LifecycleTracker(record: record),
          const SizedBox(height: 22),
          const Divider(height: 1),
          const SizedBox(height: 18),
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = constraints.maxWidth >= 760
                  ? 3
                  : constraints.maxWidth >= 480
                  ? 2
                  : 1;
              final width =
                  (constraints.maxWidth - 18 * (columns - 1)) / columns;
              final details = <(String, String)>[
                ('Institution', record.instituteName),
                ('Institute ID', record.instituteId),
                ('Program / Intake', '${record.program} • ${record.intake}'),
                ('Issue Date', formatDate(record.issueDate)),
                ('Maturity Date', formatDate(record.maturityDate)),
                ('Last Updated', formatDateTime(record.lastUpdated)),
                if (record.penalty > 0)
                  ('Assessed Penalty', inr(record.penalty)),
                if (record.deductedPenalty > 0)
                  ('Penalty Deducted', inr(record.deductedPenalty)),
                if (record.enocNumber != null)
                  ('e-NOC Reference', record.enocNumber!),
                if (record.releasedAmount != null)
                  ('Released Amount', inr(record.releasedAmount!)),
              ];
              return Wrap(
                spacing: 18,
                runSpacing: 14,
                children: details.map((detail) {
                  return SizedBox(
                    width: width,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          detail.$1.toUpperCase(),
                          style: const TextStyle(
                            fontSize: 7.8,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0.7,
                            color: AppColors.muted,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          detail.$2,
                          style: const TextStyle(
                            fontSize: 10.6,
                            fontWeight: FontWeight.w600,
                            color: AppColors.navyInk,
                            height: 1.35,
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              );
            },
          ),
          const SizedBox(height: 19),
          if (record.status == FDRStatus.onHoldExtension &&
              record.holdReason != null)
            InfoBanner(
              title: 'Extension mandated by RO',
              message: record.holdReason!,
              icon: Icons.pause_circle_filled_rounded,
              color: AppColors.orange,
            ),
          if (record.remarks.isNotEmpty) ...[
            if (record.status == FDRStatus.onHoldExtension &&
                record.holdReason != null)
              const SizedBox(height: 12),
            InfoBanner(
              title: 'Audit remark',
              message: record.remarks,
              icon: Icons.notes_rounded,
              color: record.deficiency ? AppColors.red : AppColors.navy,
            ),
          ],
        ],
      ),
    );
  }
}

class LifecycleTracker extends StatelessWidget {
  const LifecycleTracker({super.key, required this.record});

  final FDRRecord record;

  static const _labels = [
    'Uploaded',
    'Bank Lien Locked',
    'Maturity Reached',
    'RO Scrutiny',
    'Finance Settlement',
  ];

  String _caption(int index) {
    final status = record.status;
    switch (index) {
      case 0:
        return record.submittedAt == null
            ? 'Receipt uploaded'
            : formatDate(record.submittedAt!);
      case 1:
        if (status == FDRStatus.rejectedByBank) return 'Rejected by bank';
        if (status == FDRStatus.pendingBankVerification) {
          return 'Awaiting bank';
        }
        return 'Lien marked';
      case 2:
        if (record.isMatured) return formatDate(record.maturityDate);
        return 'Matures ${formatDate(record.maturityDate)}';
      case 3:
        if (status == FDRStatus.onHoldExtension) return 'On hold';
        if (status == FDRStatus.maturedPendingRO) return 'Under scrutiny';
        if (status.completedSteps > 3) return 'Cleared';
        return 'Pending';
      case 4:
        if (status == FDRStatus.forfeited) return 'Forfeited';
        if (status == FDRStatus.fundsDisbursed) return 'Funds disbursed';
        if (status == FDRStatus.releasedENOC) return 'e-NOC issued';
        if (status == FDRStatus.roClearedPendingFinance) {
          return 'Awaiting Finance';
        }
        return 'Pending';
      default:
        return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 620) {
          return _VerticalTracker(record: record);
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: List.generate(5, (index) {
            return Expanded(
              child: Column(
                children: [
                  Row(
                    children: [
                      if (index > 0)
                        Expanded(
                          child: Container(
                            height: 2.5,
                            color: index < record.status.completedSteps
                                ? AppColors.navy
                                : AppColors.border,
                          ),
                        ),
                      _TrackerCircle(record: record, index: index),
                      if (index < 4)
                        Expanded(
                          child: Container(
                            height: 2.5,
                            color: index + 1 < record.status.completedSteps
                                ? AppColors.navy
                                : AppColors.border,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 9),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Text(
                      _labels[index],
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 9.5,
                        fontWeight: index <= record.status.activeStep
                            ? FontWeight.w800
                            : FontWeight.w600,
                        color:
                            index < record.status.completedSteps ||
                                index == record.status.activeStep
                            ? AppColors.navyInk
                            : AppColors.muted,
                        height: 1.2,
                      ),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _caption(index),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 8.2,
                      color: AppColors.muted,
                      height: 1.25,
                    ),
                  ),
                ],
              ),
            );
          }),
        );
      },
    );
  }
}

class _VerticalTracker extends StatelessWidget {
  const _VerticalTracker({required this.record});

  final FDRRecord record;

  String _caption(int index) {
    return switch (index) {
      0 =>
        record.submittedAt == null
            ? 'Receipt uploaded'
            : formatDate(record.submittedAt!),
      1 =>
        record.status == FDRStatus.pendingBankVerification
            ? 'Awaiting bank verification'
            : 'Lien marked in favour of AICTE',
      2 =>
        record.isMatured
            ? 'Matured on ${formatDate(record.maturityDate)}'
            : 'Matures on ${formatDate(record.maturityDate)}',
      3 =>
        record.status == FDRStatus.onHoldExtension
            ? 'Extension mandated'
            : 'Regional office review',
      _ => record.enocNumber ?? 'Finance settlement pending',
    };
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: List.generate(LifecycleTracker._labels.length, (index) {
        final isLast = index == LifecycleTracker._labels.length - 1;
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 36,
              child: Column(
                children: [
                  _TrackerCircle(record: record, index: index),
                  if (!isLast)
                    Container(
                      width: 2.5,
                      height: 36,
                      color: index + 1 < record.status.completedSteps
                          ? AppColors.navy
                          : AppColors.border,
                    ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(top: 5, bottom: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      LifecycleTracker._labels[index],
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color:
                            index < record.status.completedSteps ||
                                index == record.status.activeStep
                            ? AppColors.navyInk
                            : AppColors.muted,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _caption(index),
                      style: const TextStyle(
                        fontSize: 9,
                        color: AppColors.muted,
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      }),
    );
  }
}

class _TrackerCircle extends StatelessWidget {
  const _TrackerCircle({required this.record, required this.index});

  final FDRRecord record;
  final int index;

  @override
  Widget build(BuildContext context) {
    final status = record.status;
    final complete = index < status.completedSteps;
    final active = index == status.activeStep && !complete;
    final issue = status.isIssueState && index == status.activeStep;
    final color = issue
        ? (status == FDRStatus.rejectedByBank || status == FDRStatus.forfeited
              ? AppColors.red
              : AppColors.orange)
        : complete
        ? AppColors.navy
        : active
        ? AppColors.gold
        : AppColors.border;
    final fill = issue
        ? color.withValues(alpha: 0.11)
        : complete
        ? AppColors.navy
        : active
        ? AppColors.gold.withValues(alpha: 0.11)
        : Colors.white;
    final icon = complete
        ? Icons.check_rounded
        : issue
        ? (status == FDRStatus.onHoldExtension
              ? Icons.pause_rounded
              : Icons.close_rounded)
        : index == 0
        ? Icons.upload_rounded
        : index == 1
        ? Icons.lock_rounded
        : index == 2
        ? Icons.event_available_rounded
        : index == 3
        ? Icons.rule_folder_rounded
        : Icons.account_balance_wallet_rounded;
    return Container(
      width: 30,
      height: 30,
      decoration: BoxDecoration(
        color: fill,
        shape: BoxShape.circle,
        border: Border.all(color: color, width: 1.6),
      ),
      child: Icon(icon, size: 14, color: complete ? Colors.white : color),
    );
  }
}

class _DialogAmountBox extends StatelessWidget {
  const _DialogAmountBox({
    required this.label,
    required this.value,
    required this.helper,
  });

  final String label;
  final String value;
  final String helper;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: AppColors.surfaceSoft,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label.toUpperCase(),
                  style: const TextStyle(
                    fontSize: 7.8,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.7,
                    color: AppColors.muted,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  helper,
                  style: const TextStyle(fontSize: 9.5, color: AppColors.muted),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Text(
            value,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w900,
              color: AppColors.navyInk,
            ),
          ),
        ],
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Dashboard 2: Partner Bank Node
// -----------------------------------------------------------------------------

class BankVerificationPage extends StatelessWidget {
  const BankVerificationPage({super.key, required this.state});

  final PortalState state;

  @override
  Widget build(BuildContext context) {
    final queue = state.pendingBankVerification;
    return WorkspacePage(
      header: WorkspaceHeader(
        eyebrow:
            'Partner bank node • ${state.role.org} / ${state.role.location}',
        title: 'Lien Verification Desk',
        subtitle:
            'Inspect digital FDR receipts, validate joint holding details, and lock the AICTE lien against each institute deposit.',
        actions: [
          AppButton(
            label: 'Refresh Queue',
            icon: Icons.refresh_rounded,
            primary: false,
            onPressed: () => showAppToast(
              context,
              'Verification queue refreshed. All pending receipts are up to date.',
              icon: Icons.refresh_rounded,
            ),
          ),
          AppButton(
            label: 'Consortium View',
            icon: Icons.hub_rounded,
            color: AppColors.teal,
            onPressed: () => showAppToast(
              context,
              'Lead bank consortium view is active for all AICTE partner banks.',
              icon: Icons.hub_rounded,
              color: AppColors.teal,
            ),
          ),
        ],
      ),
      children: [
        KpiGrid(
          cards: [
            KpiCard(
              label: 'Pending Lien Verifications',
              value: '${queue.length}',
              helper: 'Receipts awaiting inspection at the nodal desk',
              icon: Icons.fact_check_rounded,
              color: AppColors.orange,
            ),
            KpiCard(
              label: 'Active Joint Liens',
              value: '${state.activeLiens.length}',
              helper: 'Instruments with AICTE lien successfully locked',
              icon: Icons.lock_rounded,
              color: AppColors.emerald,
            ),
            KpiCard(
              label: 'Pending Release Orders',
              value: '${state.releaseReady.length}',
              helper: 'e-NOC orders awaiting bank disbursement',
              icon: Icons.payments_rounded,
              color: AppColors.indigo,
            ),
            KpiCard(
              label: 'Total Lien Value',
              value: inr(state.totalLienValue),
              helper: 'Aggregate value of active and matured lien instruments',
              icon: Icons.account_balance_rounded,
              color: AppColors.navy,
            ),
          ],
        ),
        InfoBanner(
          title: 'Lead bank nodal desk • consortium-enabled',
          message:
              'State Bank of India operates as the settlement node for this demo consortium. Verification and release queues consolidate instruments from all AICTE partner banks so every lifecycle hand-off can be demonstrated end to end.',
          icon: Icons.hub_rounded,
          color: AppColors.teal,
          trailing: SoftChip(
            label: 'SBIN0004321',
            icon: Icons.tag_rounded,
            color: AppColors.teal,
          ),
        ),
        SectionCard(
          title: 'Pending Lien Verification Queue',
          subtitle:
              'Inspect the digital receipt and verify the joint holding before locking the lien.',
          trailing: SoftChip(
            label: '${queue.length} pending',
            icon: Icons.hourglass_top_rounded,
            color: queue.isEmpty ? AppColors.emerald : AppColors.orange,
          ),
          contentPadding: const EdgeInsets.only(bottom: 8),
          child: queue.isEmpty
              ? const EmptyState(
                  title: 'Verification queue is clear',
                  message:
                      'There are no new bank receipts awaiting lien verification. New institute submissions will appear here automatically.',
                  icon: Icons.verified_user_rounded,
                  color: AppColors.emerald,
                )
              : TableScroll(
                  minWidth: 1140,
                  child: DataTable(
                    showCheckboxColumn: false,
                    horizontalMargin: 20,
                    columnSpacing: 22,
                    headingRowHeight: 46,
                    dataRowMinHeight: 72,
                    dataRowMaxHeight: 88,
                    headingRowColor: const WidgetStatePropertyAll(
                      AppColors.surfaceSoft,
                    ),
                    headingTextStyle: const TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.8,
                      color: AppColors.muted,
                    ),
                    dataTextStyle: const TextStyle(
                      fontSize: 11.5,
                      color: AppColors.ink,
                    ),
                    dividerThickness: 1,
                    border: const TableBorder(
                      horizontalInside: BorderSide(color: AppColors.softBorder),
                    ),
                    columns: const [
                      DataColumn(label: Text('FDR / INSTITUTE')),
                      DataColumn(label: Text('BANK / IFSC')),
                      DataColumn(label: Text('PROGRAM / DEPOSIT')),
                      DataColumn(label: Text('SUBMITTED')),
                      DataColumn(label: Text('STATUS')),
                      DataColumn(label: Text('ACTION')),
                    ],
                    rows: queue.map((record) {
                      return DataRow(
                        onSelectChanged: (_) =>
                            showReceiptDialog(context, state, record),
                        cells: [
                          DataCell(
                            Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  record.id,
                                  style: const TextStyle(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w800,
                                    color: AppColors.navyInk,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  record.instituteName,
                                  style: const TextStyle(
                                    fontSize: 9.2,
                                    color: AppColors.muted,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          DataCell(
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                BankMark(bankName: record.bankName),
                                const SizedBox(width: 9),
                                Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      record.bankName,
                                      style: const TextStyle(
                                        fontSize: 10.5,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      record.ifsc,
                                      style: const TextStyle(
                                        fontSize: 9.2,
                                        color: AppColors.muted,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          DataCell(
                            Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  record.program,
                                  style: const TextStyle(
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  '${inr(record.amount)} • ${record.intake} seats',
                                  style: const TextStyle(
                                    fontSize: 9.2,
                                    color: AppColors.muted,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          DataCell(
                            Text(
                              record.submittedAt == null
                                  ? '—'
                                  : formatDate(record.submittedAt!),
                              style: const TextStyle(fontSize: 10.5),
                            ),
                          ),
                          DataCell(StatusPill(status: record.status)),
                          DataCell(
                            AppButton(
                              label: 'Inspect Receipt',
                              icon: Icons.receipt_long_rounded,
                              dense: true,
                              color: AppColors.teal,
                              onPressed: () =>
                                  showReceiptDialog(context, state, record),
                            ),
                          ),
                        ],
                      );
                    }).toList(),
                  ),
                ),
        ),
        if (state.rejectedRecords.isNotEmpty)
          SectionCard(
            title: 'Recent Bank Decisions',
            subtitle:
                'Receipts rejected due to data mismatch or invalid joint holding.',
            trailing: SoftChip(
              label: '${state.rejectedRecords.length} rejected',
              icon: Icons.cancel_rounded,
              color: AppColors.red,
            ),
            contentPadding: const EdgeInsets.all(18),
            child: Column(
              children: [
                for (
                  var index = 0;
                  index < state.rejectedRecords.length;
                  index++
                ) ...[
                  if (index > 0) const Divider(height: 20),
                  Row(
                    children: [
                      BankMark(
                        bankName: state.rejectedRecords[index].bankName,
                        size: 34,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              state.rejectedRecords[index].id,
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                                color: AppColors.navyInk,
                              ),
                            ),
                            Text(
                              state.rejectedRecords[index].remarks,
                              style: const TextStyle(
                                fontSize: 9.5,
                                color: AppColors.muted,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      StatusPill(status: state.rejectedRecords[index].status),
                    ],
                  ),
                ],
              ],
            ),
          ),
      ],
    );
  }
}

Future<void> showReceiptDialog(
  BuildContext context,
  PortalState state,
  FDRRecord record,
) async {
  await showDialog<void>(
    context: context,
    barrierColor: AppColors.navyInk.withValues(alpha: 0.55),
    builder: (context) => ReceiptInspectionDialog(state: state, record: record),
  );
}

class ReceiptInspectionDialog extends StatelessWidget {
  const ReceiptInspectionDialog({
    super.key,
    required this.state,
    required this.record,
  });

  final PortalState state;
  final FDRRecord record;

  Future<void> _verify(BuildContext context) async {
    state.verifyLien(record);
    showAppToast(
      context,
      'Joint lien locked for ${record.id}. The FDR is now active.',
      icon: Icons.lock_rounded,
      color: AppColors.emeraldDark,
    );
    Navigator.of(context).pop();
  }

  Future<void> _reject(BuildContext context) async {
    final reason = await showReasonDialog(
      context,
      title: 'Reject FDR (mismatch)',
      message:
          'Record the discrepancy found during receipt inspection. The institute will see this reason and the FDR will be marked "Rejected by Bank".',
      fieldLabel: 'Reason for rejection',
      initialReason:
          'FDR number or joint holding does not match the submitted details.',
      confirmLabel: 'Reject FDR',
      confirmColor: AppColors.red,
      icon: Icons.cancel_rounded,
    );
    if (reason == null || reason.trim().isEmpty || !context.mounted) return;
    state.rejectFdr(record, reason.trim());
    showAppToast(
      context,
      '${record.id} rejected and returned to the institute.',
      icon: Icons.cancel_rounded,
      color: AppColors.red,
    );
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return PortalDialogFrame(
      title: 'Inspect Digital FDR Receipt',
      subtitle: '${record.id} • ${record.instituteName} • ${record.bankName}',
      icon: 'FDR',
      maxWidth: 1080,
      bodyPadding: const EdgeInsets.all(20),
      actions: [
        AppButton(
          label: 'Close',
          primary: false,
          onPressed: () => Navigator.of(context).pop(),
        ),
        AppButton(
          label: 'Reject (Mismatch)',
          icon: Icons.cancel_rounded,
          color: AppColors.red,
          onPressed: () => _reject(context),
        ),
        AppButton(
          label: 'Verify & Lock Joint Lien',
          icon: Icons.lock_rounded,
          color: AppColors.emeraldDark,
          onPressed: () => _verify(context),
        ),
      ],
      body: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= 790;
          final preview = _DigitalReceiptPreview(record: record);
          final metadata = _ReceiptMetadata(record: record);
          if (!wide) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [preview, const SizedBox(height: 18), metadata],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 6, child: preview),
              const SizedBox(width: 18),
              Expanded(flex: 4, child: metadata),
            ],
          );
        },
      ),
    );
  }
}

class _DigitalReceiptPreview extends StatelessWidget {
  const _DigitalReceiptPreview({required this.record});

  final FDRRecord record;

  @override
  Widget build(BuildContext context) {
    final color = bankColor(record.bankName);
    return Container(
      padding: const EdgeInsets.all(7),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFFFFCF5), Colors.white],
        ),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: AppColors.gold.withValues(alpha: 0.55),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.navy.withValues(alpha: 0.08),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Container(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
        decoration: BoxDecoration(
          border: Border.all(color: AppColors.navy.withValues(alpha: 0.15)),
          borderRadius: BorderRadius.circular(7),
        ),
        child: Stack(
          children: [
            Positioned(
              right: -15,
              bottom: 4,
              child: Opacity(
                opacity: 0.035,
                child: Icon(
                  Icons.account_balance_rounded,
                  size: 190,
                  color: color,
                ),
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    BankMark(bankName: record.bankName, size: 42),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            record.bankName.toUpperCase(),
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 0.5,
                              color: color,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'IFSC ${record.ifsc} • AUTHORISED BRANCH',
                            style: const TextStyle(
                              fontSize: 8,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.45,
                              color: AppColors.muted,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.emerald.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: AppColors.emerald.withValues(alpha: 0.22),
                        ),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.verified_rounded,
                            size: 10,
                            color: AppColors.emeraldDark,
                          ),
                          SizedBox(width: 4),
                          Text(
                            'DIGITAL COPY',
                            style: TextStyle(
                              fontSize: 7,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 0.5,
                              color: AppColors.emeraldDark,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 13),
                Divider(
                  color: AppColors.gold.withValues(alpha: 0.45),
                  height: 1,
                ),
                const SizedBox(height: 13),
                const Center(
                  child: Text(
                    'JOINT FIXED DEPOSIT RECEIPT',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.35,
                      color: AppColors.navyInk,
                    ),
                  ),
                ),
                const SizedBox(height: 3),
                const Center(
                  child: Text(
                    'AICTE SECURITY DEPOSIT • CERTIFIED INSTRUMENT',
                    style: TextStyle(
                      fontSize: 7.4,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.05,
                      color: AppColors.gold,
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  'This is to certify that a fixed deposit has been placed with ${record.bankName} in the joint names of the institute and the All India Council for Technical Education, with a lien marked in favour of AICTE.',
                  style: const TextStyle(
                    fontSize: 8.8,
                    height: 1.55,
                    color: AppColors.muted,
                  ),
                ),
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.035),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: color.withValues(alpha: 0.11)),
                  ),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: _ReceiptField(
                              label: 'FDR NUMBER',
                              value: record.id,
                            ),
                          ),
                          Expanded(
                            child: _ReceiptField(
                              label: 'ISSUE DATE',
                              value: formatDate(record.issueDate),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: _ReceiptField(
                              label: 'MATURITY DATE',
                              value: formatDate(record.maturityDate),
                            ),
                          ),
                          Expanded(
                            child: _ReceiptField(
                              label: 'TENURE',
                              value:
                                  '${record.maturityDate.year - record.issueDate.year} years',
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 11,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.navy,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      const Text(
                        'DEPOSIT AMOUNT',
                        style: TextStyle(
                          fontSize: 7.8,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.8,
                          color: Color(0xFFB7C5E8),
                        ),
                      ),
                      const Spacer(),
                      Text(
                        inr(record.amount),
                        style: const TextStyle(
                          fontSize: 20,
                          height: 1,
                          letterSpacing: -0.5,
                          fontWeight: FontWeight.w900,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _ReceiptField(
                            label: 'JOINT HOLDERS',
                            value: 'AICTE + ${record.instituteName}',
                          ),
                          const SizedBox(height: 9),
                          const _ReceiptField(
                            label: 'LIEN STATUS',
                            value: 'MARKED IN FAVOUR OF AICTE',
                          ),
                          const SizedBox(height: 11),
                          _Barcode(color: color),
                          const SizedBox(height: 4),
                          Text(
                            record.id.replaceAll('-', ''),
                            style: const TextStyle(
                              fontSize: 6.5,
                              letterSpacing: 1.5,
                              color: AppColors.muted,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    _DigitalSeal(color: color),
                  ],
                ),
                const SizedBox(height: 11),
                Text(
                  'System-generated digital preview for verification. Original FDR receipt remains the instrument of record.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 6.8,
                    color: AppColors.muted.withValues(alpha: 0.9),
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ReceiptField extends StatelessWidget {
  const _ReceiptField({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 6.8,
            fontWeight: FontWeight.w900,
            letterSpacing: 0.7,
            color: AppColors.muted,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontSize: 9.6,
            fontWeight: FontWeight.w800,
            color: AppColors.navyInk,
            height: 1.3,
          ),
        ),
      ],
    );
  }
}

class _Barcode extends StatelessWidget {
  const _Barcode({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 22,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: List.generate(50, (index) {
          final widths = [1.0, 1.5, 3.0, 1.0, 2.0];
          return Container(
            width: widths[index % widths.length],
            margin: const EdgeInsets.only(right: 1.6),
            color: color.withValues(alpha: 0.72),
          );
        }),
      ),
    );
  }
}

class _DigitalSeal extends StatelessWidget {
  const _DigitalSeal({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 72,
      height: 72,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white,
        border: Border.all(color: color, width: 2),
        boxShadow: [
          BoxShadow(color: color.withValues(alpha: 0.12), blurRadius: 8),
        ],
      ),
      padding: const EdgeInsets.all(4),
      child: Container(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
            color: AppColors.gold.withValues(alpha: 0.8),
            width: 1,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.account_balance_rounded, size: 16, color: color),
            const SizedBox(height: 1),
            const Text(
              'AICTE',
              style: TextStyle(
                fontSize: 8,
                fontWeight: FontWeight.w900,
                letterSpacing: 0.6,
                color: AppColors.navyInk,
              ),
            ),
            const Text(
              'LIEN',
              style: TextStyle(
                fontSize: 6,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.9,
                color: AppColors.gold,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReceiptMetadata extends StatelessWidget {
  const _ReceiptMetadata({required this.record});

  final FDRRecord record;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surfaceSoft,
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'RECEIPT METADATA',
            style: TextStyle(
              fontSize: 8.8,
              fontWeight: FontWeight.w900,
              letterSpacing: 1,
              color: AppColors.gold,
            ),
          ),
          const SizedBox(height: 12),
          _MetaLine(label: 'Institute', value: record.instituteName),
          _MetaLine(label: 'Institute ID', value: record.instituteId),
          _MetaLine(label: 'Program', value: record.program),
          _MetaLine(label: 'Intake', value: '${record.intake} seats'),
          _MetaLine(label: 'Principal', value: inr(record.amount)),
          _MetaLine(
            label: 'Bank / IFSC',
            value: '${record.bankName}\n${record.ifsc}',
          ),
          _MetaLine(
            label: 'Submitted on',
            value: record.submittedAt == null
                ? '—'
                : formatDateTime(record.submittedAt!),
          ),
          const SizedBox(height: 13),
          const Divider(height: 1),
          const SizedBox(height: 13),
          const Text(
            'VERIFICATION CHECKLIST',
            style: TextStyle(
              fontSize: 8.8,
              fontWeight: FontWeight.w900,
              letterSpacing: 1,
              color: AppColors.gold,
            ),
          ),
          const SizedBox(height: 9),
          const _CheckLine('FDR number matches institute submission'),
          const _CheckLine('Deposit amount matches declared value'),
          const _CheckLine('Joint holding includes AICTE'),
          const _CheckLine('IFSC belongs to a partner branch'),
          const _CheckLine('Maturity date is after issue date'),
          const SizedBox(height: 13),
          InfoBanner(
            title: 'Simulated digital certificate',
            message:
                'This preview is generated from the submitted FDR metadata for the Phase 1 demo. In production it will be rendered from the uploaded bank receipt PDF.',
            icon: Icons.info_outline_rounded,
            color: AppColors.navy,
          ),
        ],
      ),
    );
  }
}

class _MetaLine extends StatelessWidget {
  const _MetaLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 82,
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 9,
                color: AppColors.muted,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 9.8,
                color: AppColors.navyInk,
                fontWeight: FontWeight.w700,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CheckLine extends StatelessWidget {
  const _CheckLine(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 16,
            height: 16,
            decoration: BoxDecoration(
              color: AppColors.emerald.withValues(alpha: 0.09),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.check_rounded,
              size: 10,
              color: AppColors.emeraldDark,
            ),
          ),
          const SizedBox(width: 7),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 9.4,
                color: AppColors.ink,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class BankSettlementPage extends StatelessWidget {
  const BankSettlementPage({super.key, required this.state});

  final PortalState state;

  @override
  Widget build(BuildContext context) {
    final releaseQueue = state.releaseReady;
    final releaseValue = releaseQueue.fold(
      0.0,
      (total, record) => total + record.settlementValue,
    );
    final disbursedValue = state.disbursedRecords.fold(
      0.0,
      (total, record) => total + record.settlementValue,
    );
    return WorkspacePage(
      header: WorkspaceHeader(
        eyebrow: 'Partner bank node • release operations',
        title: 'Release Settlement Queue',
        subtitle:
            'Disburse funds to institutes against AICTE-issued e-NOC orders and close the FDR lifecycle with a verifiable settlement trail.',
        actions: [
          AppButton(
            label: 'Settlement Ledger',
            icon: Icons.receipt_long_rounded,
            primary: false,
            onPressed: () => showAppToast(
              context,
              'Bank settlement ledger is up to date (demo).',
              icon: Icons.receipt_long_rounded,
            ),
          ),
        ],
      ),
      children: [
        KpiGrid(
          cards: [
            KpiCard(
              label: 'Release Orders Ready',
              value: '${releaseQueue.length}',
              helper: 'e-NOC orders awaiting fund transfer',
              icon: Icons.description_rounded,
              color: AppColors.indigo,
            ),
            KpiCard(
              label: 'Amount Awaiting Disbursement',
              value: inr(releaseValue),
              helper: 'Net of penalties deducted by AICTE Finance',
              icon: Icons.payments_rounded,
              color: AppColors.gold,
            ),
            KpiCard(
              label: 'Settlements Completed',
              value: '${state.disbursedRecords.length}',
              helper: 'Instant transfers with settlement reference',
              icon: Icons.check_circle_rounded,
              color: AppColors.emerald,
            ),
            KpiCard(
              label: 'Disbursed Value',
              value: inr(disbursedValue),
              helper: 'Funds returned to institutes in this demo cycle',
              icon: Icons.account_balance_wallet_rounded,
              color: AppColors.navy,
            ),
          ],
        ),
        InfoBanner(
          title: 'e-NOC verified settlement workflow',
          message:
              'Disbursement is permitted only after AICTE Finance grants final approval and generates an e-NOC. The bank records the settlement reference and returns the funds to the institute account.',
          icon: Icons.verified_user_rounded,
          color: AppColors.emeraldDark,
          trailing: SoftChip(
            label:
                '${releaseQueue.length} order${releaseQueue.length == 1 ? '' : 's'}',
            icon: Icons.payments_rounded,
            color: releaseQueue.isEmpty ? AppColors.emerald : AppColors.gold,
          ),
        ),
        SectionCard(
          title: 'Release Settlement Queue',
          subtitle:
              'AICTE Finance approved releases waiting for bank disbursement.',
          trailing: const SoftChip(
            label: 'e-NOC issued',
            icon: Icons.description_rounded,
            color: AppColors.indigo,
          ),
          contentPadding: releaseQueue.isEmpty
              ? EdgeInsets.zero
              : const EdgeInsets.all(18),
          child: releaseQueue.isEmpty
              ? const EmptyState(
                  title: 'No release orders pending',
                  message:
                      'When AICTE Finance issues an e-NOC, the approved settlement will appear here with a one-click disbursement action.',
                  icon: Icons.payments_rounded,
                  color: AppColors.indigo,
                )
              : Column(
                  children: [
                    for (
                      var index = 0;
                      index < releaseQueue.length;
                      index++
                    ) ...[
                      if (index > 0) const SizedBox(height: 12),
                      BankReleaseCard(
                        record: releaseQueue[index],
                        onDisburse: () =>
                            _disburse(context, state, releaseQueue[index]),
                      ),
                    ],
                  ],
                ),
        ),
        SectionCard(
          title: 'Settlement History',
          subtitle:
              'Funds disbursed by this nodal desk against AICTE e-NOC orders.',
          trailing: SoftChip(
            label: '${state.disbursedRecords.length} settled',
            icon: Icons.check_circle_rounded,
            color: AppColors.emeraldDark,
          ),
          contentPadding: const EdgeInsets.only(bottom: 8),
          child: state.disbursedRecords.isEmpty
              ? const EmptyState(
                  title: 'No settlements recorded yet',
                  message:
                      'Completed disbursements will be retained here for the audit trail.',
                  icon: Icons.history_rounded,
                  color: AppColors.muted,
                )
              : TableScroll(
                  minWidth: 940,
                  child: DataTable(
                    horizontalMargin: 20,
                    columnSpacing: 24,
                    headingRowHeight: 44,
                    dataRowMinHeight: 58,
                    dataRowMaxHeight: 68,
                    headingRowColor: const WidgetStatePropertyAll(
                      AppColors.surfaceSoft,
                    ),
                    headingTextStyle: const TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.8,
                      color: AppColors.muted,
                    ),
                    dividerThickness: 1,
                    border: const TableBorder(
                      horizontalInside: BorderSide(color: AppColors.softBorder),
                    ),
                    columns: const [
                      DataColumn(label: Text('e-NOC / FDR')),
                      DataColumn(label: Text('INSTITUTE')),
                      DataColumn(label: Text('SETTLED AMOUNT')),
                      DataColumn(label: Text('SETTLED ON')),
                      DataColumn(label: Text('STATUS')),
                    ],
                    rows: state.disbursedRecords.map((record) {
                      return DataRow(
                        cells: [
                          DataCell(
                            Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  record.enocNumber ?? '—',
                                  style: const TextStyle(
                                    fontSize: 9.8,
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.navyInk,
                                  ),
                                ),
                                Text(
                                  record.id,
                                  style: const TextStyle(
                                    fontSize: 9.2,
                                    color: AppColors.muted,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          DataCell(
                            Text(
                              record.instituteName,
                              style: const TextStyle(fontSize: 10),
                            ),
                          ),
                          DataCell(
                            Text(
                              inr(record.settlementValue),
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                                color: AppColors.navyInk,
                              ),
                            ),
                          ),
                          DataCell(
                            Text(
                              record.releasedAt == null
                                  ? '—'
                                  : formatDate(record.releasedAt!),
                              style: const TextStyle(fontSize: 10),
                            ),
                          ),
                          DataCell(StatusPill(status: record.status)),
                        ],
                      );
                    }).toList(),
                  ),
                ),
        ),
      ],
    );
  }
}

Future<void> _disburse(
  BuildContext context,
  PortalState state,
  FDRRecord record,
) async {
  final confirmed = await showConfirmDialog(
    context,
    title: 'Disburse funds to institute?',
    message:
        'The bank will transfer the approved amount against e-NOC ${record.enocNumber ?? '—'} and mark ${record.id} as settled. This action cannot be reversed.',
    confirmLabel: 'Confirm Disbursement',
    confirmColor: AppColors.emeraldDark,
    icon: Icons.payments_rounded,
    extra: _DialogAmountBox(
      label: 'Net settlement amount',
      value: inr(record.settlementValue),
      helper:
          '${record.instituteName}\n${record.enocNumber ?? 'e-NOC pending'}',
    ),
  );
  if (!confirmed || !context.mounted) return;
  state.disburseFunds(record);
  showAppToast(
    context,
    '${inr(record.settlementValue)} disbursed for ${record.id}. Settlement closed.',
    icon: Icons.check_circle_rounded,
    color: AppColors.emeraldDark,
  );
}

class BankReleaseCard extends StatelessWidget {
  const BankReleaseCard({
    super.key,
    required this.record,
    required this.onDisburse,
  });

  final FDRRecord record;
  final VoidCallback onDisburse;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
        boxShadow: [
          BoxShadow(
            color: AppColors.navy.withValues(alpha: 0.03),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= 800;
          final identity = Row(
            children: [
              BankMark(bankName: record.bankName, size: 42),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      record.id,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: AppColors.navyInk,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      record.instituteName,
                      style: const TextStyle(
                        fontSize: 9.5,
                        color: AppColors.muted,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Wrap(
                      spacing: 6,
                      runSpacing: 5,
                      children: [
                        SoftChip(
                          label: record.enocNumber ?? 'e-NOC pending',
                          icon: Icons.description_rounded,
                          color: AppColors.indigo,
                        ),
                        StatusPill(status: record.status),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          );

          final financeSummary = Column(
            crossAxisAlignment: wide
                ? CrossAxisAlignment.end
                : CrossAxisAlignment.start,
            children: [
              const Text(
                'NET RELEASE',
                style: TextStyle(
                  fontSize: 7.8,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.8,
                  color: AppColors.muted,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                inr(record.settlementValue),
                style: const TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.4,
                  color: AppColors.navyInk,
                ),
              ),
              if (record.deductedPenalty > 0)
                Text(
                  '${inr(record.deductedPenalty)} penalty deducted',
                  style: const TextStyle(
                    fontSize: 8.8,
                    color: AppColors.orange,
                    fontWeight: FontWeight.w600,
                  ),
                ),
            ],
          );

          final action = AppButton(
            label: 'Disburse Funds to Institute',
            icon: Icons.payments_rounded,
            color: AppColors.emeraldDark,
            onPressed: onDisburse,
          );

          if (!wide) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                identity,
                const SizedBox(height: 12),
                financeSummary,
                const SizedBox(height: 12),
                action,
              ],
            );
          }
          return Row(
            children: [
              Expanded(flex: 5, child: identity),
              const SizedBox(width: 20),
              Expanded(flex: 3, child: financeSummary),
              const SizedBox(width: 18),
              action,
            ],
          );
        },
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Dashboard 3: AICTE Regional Officer (RO)
// -----------------------------------------------------------------------------

class RoScrutinyPage extends StatelessWidget {
  const RoScrutinyPage({super.key, required this.state});

  final PortalState state;

  @override
  Widget build(BuildContext context) {
    final queue = state.roScrutiny;
    final instituteGroups = <String, List<FDRRecord>>{};
    for (final record in state.records) {
      instituteGroups.putIfAbsent(record.instituteId, () => []).add(record);
    }

    return WorkspacePage(
      header: WorkspaceHeader(
        eyebrow:
            'AICTE regional officer • ${state.role.org} / ${state.role.location}',
        title: 'Regional Scrutiny & Deficiency Queue',
        subtitle:
            'Review matured FDR release applications for Southern Region institutes. Grant RO clearance to Finance or mandate an extension where compliance remains unresolved.',
        actions: [
          AppButton(
            label: 'Regional Summary',
            icon: Icons.assessment_rounded,
            primary: false,
            onPressed: () => showAppToast(
              context,
              'Regional scrutiny summary generated for the live demo.',
              icon: Icons.assessment_rounded,
            ),
          ),
          AppButton(
            label: 'On-Hold Tracker',
            icon: Icons.pause_circle_rounded,
            color: AppColors.orange,
            onPressed: () => state.selectNav(1),
          ),
        ],
      ),
      children: [
        KpiGrid(
          cards: [
            KpiCard(
              label: 'Total Regional Institutes',
              value: '${state.regionalInstituteCount}',
              helper: 'Institutes mapped to the Southern Regional Office',
              icon: Icons.account_balance_rounded,
              color: AppColors.navy,
            ),
            KpiCard(
              label: 'Applications Under Scrutiny',
              value: '${queue.length}',
              helper: 'Matured FDR release requests awaiting RO action',
              icon: Icons.rule_folder_rounded,
              color: AppColors.gold,
            ),
            KpiCard(
              label: 'Zero-Deficiency Cleared',
              value: '${state.zeroDeficiencyCleared}',
              helper: 'Applications granted RO clearance for Finance',
              icon: Icons.verified_rounded,
              color: AppColors.emerald,
            ),
            KpiCard(
              label: 'Flagged / On-Hold',
              value: '${state.flaggedInstituteCount}',
              helper: 'Institutes requiring clarification or extension',
              icon: Icons.flag_rounded,
              color: AppColors.red,
            ),
          ],
        ),
        SectionCard(
          title: 'Regional Institute Coverage',
          subtitle:
              'Live compliance posture of institutes mapped to the Chennai regional office.',
          trailing: SoftChip(
            label: 'Southern Region',
            icon: Icons.location_on_rounded,
            color: AppColors.gold,
          ),
          contentPadding: const EdgeInsets.all(18),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final columns = constraints.maxWidth >= 980
                  ? 3
                  : constraints.maxWidth >= 620
                  ? 2
                  : 1;
              final width =
                  (constraints.maxWidth - 12 * (columns - 1)) / columns;
              return Wrap(
                spacing: 12,
                runSpacing: 12,
                children: instituteGroups.entries.map((entry) {
                  final records = entry.value;
                  final flagged = records.any(
                    (record) =>
                        record.deficiency ||
                        record.status == FDRStatus.onHoldExtension,
                  );
                  final inScrutiny = records
                      .where(
                        (record) => record.status == FDRStatus.maturedPendingRO,
                      )
                      .length;
                  final lockedValue = records
                      .where((record) => !record.status.isClosed)
                      .fold(0.0, (total, record) => total + record.amount);
                  return SizedBox(
                    width: width,
                    child: Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: flagged
                            ? AppColors.red.withValues(alpha: 0.025)
                            : AppColors.surfaceSoft,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: flagged
                              ? AppColors.red.withValues(alpha: 0.18)
                              : AppColors.border,
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                width: 35,
                                height: 35,
                                decoration: BoxDecoration(
                                  color: AppColors.navy.withValues(alpha: 0.07),
                                  borderRadius: BorderRadius.circular(9),
                                ),
                                child: const Icon(
                                  Icons.school_rounded,
                                  size: 17,
                                  color: AppColors.navy,
                                ),
                              ),
                              const SizedBox(width: 9),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      records.first.instituteName,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontSize: 10.5,
                                        height: 1.25,
                                        fontWeight: FontWeight.w800,
                                        color: AppColors.navyInk,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      'ID ${entry.key}',
                                      style: const TextStyle(
                                        fontSize: 8.8,
                                        color: AppColors.muted,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              _CoverageMetric(
                                value: '${records.length}',
                                label: 'FDRs',
                              ),
                              const SizedBox(width: 16),
                              _CoverageMetric(
                                value: inrCompact(lockedValue),
                                label: 'Locked',
                              ),
                              const Spacer(),
                              SoftChip(
                                label: flagged
                                    ? 'Flagged'
                                    : '$inScrutiny in queue',
                                icon: flagged
                                    ? Icons.flag_rounded
                                    : Icons.rule_folder_rounded,
                                color: flagged
                                    ? AppColors.red
                                    : inScrutiny > 0
                                    ? AppColors.gold
                                    : AppColors.emeraldDark,
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              );
            },
          ),
        ),
        InfoBanner(
          title: 'Review before granting clearance',
          message:
              'Verify the compliance dossier, institute response and maturity evidence before forwarding an application. Time-exceeded or deficiency-flagged cases should normally be placed on hold with a mandated extension.',
          icon: Icons.gavel_rounded,
          color: AppColors.gold,
          trailing: SoftChip(
            label: '${queue.length} pending',
            icon: Icons.pending_actions_rounded,
            color: queue.isEmpty ? AppColors.emerald : AppColors.gold,
          ),
        ),
        SectionCard(
          title: 'Regional Scrutiny & Deficiency Queue',
          subtitle:
              'Matured FDRs awaiting a decision by the Regional Officer, Chennai.',
          trailing: SoftChip(
            label: 'RO decision required',
            icon: Icons.rule_folder_rounded,
            color: AppColors.gold,
          ),
          contentPadding: const EdgeInsets.only(bottom: 8),
          child: queue.isEmpty
              ? const EmptyState(
                  title: 'No applications pending scrutiny',
                  message:
                      'All matured FDR release applications have been decided. New institute release requests will appear here automatically.',
                  icon: Icons.task_alt_rounded,
                  color: AppColors.emerald,
                )
              : TableScroll(
                  minWidth: 1320,
                  child: DataTable(
                    horizontalMargin: 20,
                    columnSpacing: 20,
                    headingRowHeight: 46,
                    dataRowMinHeight: 82,
                    dataRowMaxHeight: 102,
                    headingRowColor: const WidgetStatePropertyAll(
                      AppColors.surfaceSoft,
                    ),
                    headingTextStyle: const TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.8,
                      color: AppColors.muted,
                    ),
                    dataTextStyle: const TextStyle(
                      fontSize: 11.5,
                      color: AppColors.ink,
                    ),
                    dividerThickness: 1,
                    border: const TableBorder(
                      horizontalInside: BorderSide(color: AppColors.softBorder),
                    ),
                    columns: const [
                      DataColumn(label: Text('INSTITUTE')),
                      DataColumn(label: Text('FDR / BANK')),
                      DataColumn(label: Text('AMOUNT')),
                      DataColumn(label: Text('MATURITY')),
                      DataColumn(label: Text('COMPLIANCE STATUS')),
                      DataColumn(label: Text('RO ACTION')),
                    ],
                    rows: queue.map((record) {
                      return DataRow(
                        cells: [
                          DataCell(
                            Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  record.instituteName,
                                  style: const TextStyle(
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.w800,
                                    color: AppColors.navyInk,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'ID ${record.instituteId}',
                                  style: const TextStyle(
                                    fontSize: 9.2,
                                    color: AppColors.muted,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          DataCell(
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                BankMark(bankName: record.bankName, size: 34),
                                const SizedBox(width: 9),
                                Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      record.id,
                                      style: const TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      record.bankName,
                                      style: const TextStyle(
                                        fontSize: 9,
                                        color: AppColors.muted,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          DataCell(
                            Text(
                              inr(record.amount),
                              style: const TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w800,
                                color: AppColors.navyInk,
                              ),
                            ),
                          ),
                          DataCell(
                            Text(
                              formatDate(record.maturityDate),
                              style: const TextStyle(fontSize: 10.5),
                            ),
                          ),
                          DataCell(
                            Tooltip(
                              message: record.remarks,
                              child: ComplianceBadge(
                                deficiency: record.deficiency,
                              ),
                            ),
                          ),
                          DataCell(
                            Wrap(
                              spacing: 7,
                              runSpacing: 6,
                              children: [
                                AppButton(
                                  label: 'Forward to Finance',
                                  icon: Icons.arrow_forward_rounded,
                                  dense: true,
                                  color: AppColors.navy,
                                  onPressed: () =>
                                      _forwardToFinance(context, state, record),
                                ),
                                AppButton(
                                  label: 'Put On Hold',
                                  icon: Icons.pause_circle_rounded,
                                  primary: false,
                                  dense: true,
                                  color: AppColors.orange,
                                  onPressed: () =>
                                      _putOnHold(context, state, record),
                                ),
                              ],
                            ),
                          ),
                        ],
                      );
                    }).toList(),
                  ),
                ),
        ),
      ],
    );
  }
}

class _CoverageMetric extends StatelessWidget {
  const _CoverageMetric({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          value,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w900,
            color: AppColors.navyInk,
          ),
        ),
        Text(
          label,
          style: const TextStyle(
            fontSize: 7.8,
            color: AppColors.muted,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

Future<void> _forwardToFinance(
  BuildContext context,
  PortalState state,
  FDRRecord record,
) async {
  final confirmed = await showConfirmDialog(
    context,
    title: 'Grant RO clearance?',
    message:
        '${record.id} will be forwarded to AICTE Finance with RO clearance. Finance will then decide on full release, partial release with penalty, or forfeiture.',
    confirmLabel: 'Forward to Finance',
    confirmColor: AppColors.navy,
    icon: Icons.verified_rounded,
    extra: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _DialogAmountBox(
          label: 'Deposit amount',
          value: inr(record.amount),
          helper: '${record.instituteName}\n${record.bankName}',
        ),
        if (record.deficiency) ...[
          const SizedBox(height: 10),
          InfoBanner(
            title: 'Deficiency flag present',
            message:
                'This application is flagged for time exceeded / pending inquiry. Forwarding records your decision that the flag is resolved.',
            icon: Icons.warning_amber_rounded,
            color: AppColors.red,
          ),
        ],
      ],
    ),
  );
  if (!confirmed || !context.mounted) return;
  state.forwardToFinance(record);
  showAppToast(
    context,
    'RO clearance granted for ${record.id}. Forwarded to AICTE Finance.',
    icon: Icons.verified_rounded,
    color: AppColors.indigo,
  );
}

Future<void> _putOnHold(
  BuildContext context,
  PortalState state,
  FDRRecord record,
) async {
  final reason = await showReasonDialog(
    context,
    title: 'Put application on hold?',
    message:
        '${record.id} will be moved to "On Hold - Extension Required". The institute will see the mandated extension reason in their portfolio.',
    fieldLabel: 'Extension / clarification required',
    initialReason:
        'Clarification required on intake deficiency and pending compliance documents.',
    confirmLabel: 'Mandate Extension',
    confirmColor: AppColors.orange,
    icon: Icons.pause_circle_rounded,
  );
  if (reason == null || reason.trim().isEmpty || !context.mounted) return;
  state.putOnHold(record, reason.trim());
  showAppToast(
    context,
    '${record.id} placed on hold. Extension mandated to the institute.',
    icon: Icons.pause_circle_rounded,
    color: AppColors.orange,
  );
}

class RoOnHoldPage extends StatelessWidget {
  const RoOnHoldPage({super.key, required this.state});

  final PortalState state;

  @override
  Widget build(BuildContext context) {
    final records = state.onHoldRecords;
    final affectedInstitutes = records
        .map((record) => record.instituteId)
        .toSet()
        .length;
    var longestHold = 0;
    for (final record in records) {
      final days = record.holdDate == null
          ? 0
          : DateTime.now().difference(record.holdDate!).inDays;
      if (days > longestHold) longestHold = days;
    }

    return WorkspacePage(
      header: WorkspaceHeader(
        eyebrow: 'AICTE regional officer • extension tracker',
        title: 'On-Hold & Extension Tracker',
        subtitle:
            'Monitor applications where RO clearance is withheld pending institutional action, and reopen scrutiny once a satisfactory response is received.',
        actions: [
          AppButton(
            label: 'Back to Scrutiny',
            icon: Icons.arrow_back_rounded,
            primary: false,
            onPressed: () => state.selectNav(0),
          ),
        ],
      ),
      children: [
        KpiGrid(
          cards: [
            KpiCard(
              label: 'On-Hold Applications',
              value: '${records.length}',
              helper: 'Release requests awaiting institute response',
              icon: Icons.pause_circle_rounded,
              color: AppColors.orange,
            ),
            KpiCard(
              label: 'Institutes Affected',
              value: '$affectedInstitutes',
              helper: 'Institutes with at least one extension mandate',
              icon: Icons.school_rounded,
              color: AppColors.red,
            ),
            KpiCard(
              label: 'Longest Hold',
              value: '$longestHold days',
              helper: 'Age of the oldest unresolved extension',
              icon: Icons.timer_rounded,
              color: AppColors.gold,
            ),
            KpiCard(
              label: 'Active Scrutiny Queue',
              value: '${state.roScrutiny.length}',
              helper: 'Applications still awaiting an RO decision',
              icon: Icons.rule_folder_rounded,
              color: AppColors.navy,
            ),
          ],
        ),
        InfoBanner(
          title: 'Extension mandates protect the audit trail',
          message:
              'An application placed on hold remains visible to the institute and AICTE Finance. Reopen scrutiny only after the requested clarification or compliance evidence is received.',
          icon: Icons.info_outline_rounded,
          color: AppColors.orange,
        ),
        SectionCard(
          title: 'On-Hold & Extension Tracker',
          subtitle:
              'Applications where RO clearance is withheld pending institutional action.',
          trailing: SoftChip(
            label: '${records.length} on hold',
            icon: Icons.pause_circle_rounded,
            color: records.isEmpty ? AppColors.emerald : AppColors.orange,
          ),
          contentPadding: records.isEmpty
              ? EdgeInsets.zero
              : const EdgeInsets.all(18),
          child: records.isEmpty
              ? EmptyState(
                  title: 'No applications on hold',
                  message:
                      'All regional applications are moving through the normal scrutiny path. If an RO mandates an extension, the record will appear here.',
                  icon: Icons.task_alt_rounded,
                  color: AppColors.emerald,
                  action: AppButton(
                    label: 'Open Scrutiny Queue',
                    icon: Icons.rule_folder_rounded,
                    onPressed: () => state.selectNav(0),
                  ),
                )
              : Column(
                  children: [
                    for (var index = 0; index < records.length; index++) ...[
                      if (index > 0) const SizedBox(height: 12),
                      _OnHoldCard(
                        record: records[index],
                        onReopen: () =>
                            _reopenScrutiny(context, state, records[index]),
                        onView: () =>
                            showTrackerDialog(context, records[index]),
                      ),
                    ],
                  ],
                ),
        ),
      ],
    );
  }
}

Future<void> _reopenScrutiny(
  BuildContext context,
  PortalState state,
  FDRRecord record,
) async {
  final confirmed = await showConfirmDialog(
    context,
    title: 'Reopen RO scrutiny?',
    message:
        'Confirm that the institute response has been received. ${record.id} will return to the active scrutiny queue for a fresh decision.',
    confirmLabel: 'Reopen Scrutiny',
    confirmColor: AppColors.gold,
    icon: Icons.refresh_rounded,
  );
  if (!confirmed || !context.mounted) return;
  state.reopenScrutiny(record);
  showAppToast(
    context,
    '${record.id} returned to the active RO scrutiny queue.',
    icon: Icons.refresh_rounded,
    color: AppColors.gold,
  );
}

class _OnHoldCard extends StatelessWidget {
  const _OnHoldCard({
    required this.record,
    required this.onReopen,
    required this.onView,
  });

  final FDRRecord record;
  final VoidCallback onReopen;
  final VoidCallback onView;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
        boxShadow: [
          BoxShadow(
            color: AppColors.orange.withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth >= 760;
              final identity = Row(
                children: [
                  BankMark(bankName: record.bankName, size: 42),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          record.id,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            color: AppColors.navyInk,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${record.instituteName} • ID ${record.instituteId}',
                          style: const TextStyle(
                            fontSize: 9.5,
                            color: AppColors.muted,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              );
              final meta = Column(
                crossAxisAlignment: wide
                    ? CrossAxisAlignment.end
                    : CrossAxisAlignment.start,
                children: [
                  Text(
                    inr(record.amount),
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w900,
                      color: AppColors.navyInk,
                    ),
                  ),
                  const SizedBox(height: 3),
                  StatusPill(status: record.status),
                ],
              );
              if (!wide) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [identity, const SizedBox(height: 10), meta],
                );
              }
              return Row(
                children: [
                  Expanded(child: identity),
                  const SizedBox(width: 18),
                  meta,
                ],
              );
            },
          ),
          const SizedBox(height: 13),
          Container(
            padding: const EdgeInsets.all(11),
            decoration: BoxDecoration(
              color: AppColors.orange.withValues(alpha: 0.045),
              borderRadius: BorderRadius.circular(9),
              border: Border.all(
                color: AppColors.orange.withValues(alpha: 0.13),
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.pause_circle_filled_rounded,
                  size: 16,
                  color: AppColors.orange,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'MANDATED EXTENSION REASON',
                        style: TextStyle(
                          fontSize: 7.5,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.7,
                          color: AppColors.orange,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        record.holdReason ?? record.remarks,
                        style: const TextStyle(
                          fontSize: 10,
                          color: AppColors.ink,
                          height: 1.45,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              if (record.holdDate != null)
                Text(
                  'Held since ${formatDate(record.holdDate!)}',
                  style: const TextStyle(
                    fontSize: 9.2,
                    color: AppColors.muted,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              const Spacer(),
              AppButton(
                label: 'View Tracker',
                icon: Icons.timeline_rounded,
                primary: false,
                dense: true,
                onPressed: onView,
              ),
              const SizedBox(width: 8),
              AppButton(
                label: 'Reopen Scrutiny',
                icon: Icons.refresh_rounded,
                dense: true,
                color: AppColors.gold,
                onPressed: onReopen,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Dashboard 4: AICTE Finance Bureau HQ
// -----------------------------------------------------------------------------

class FinanceSettlementPage extends StatelessWidget {
  const FinanceSettlementPage({super.key, required this.state});

  final PortalState state;

  @override
  Widget build(BuildContext context) {
    final queue = state.financeQueue;
    return WorkspacePage(
      header: WorkspaceHeader(
        eyebrow:
            'AICTE finance bureau • ${state.role.org} / ${state.role.location}',
        title: 'Final Settlement & Disbursement Queue',
        subtitle:
            'Approve final e-NOC releases, deduct assessed penalties, or encash an FDR to the AICTE account after regional clearance.',
        actions: [
          AppButton(
            label: 'Penalty Register',
            icon: Icons.receipt_long_rounded,
            primary: false,
            onPressed: () => showAppToast(
              context,
              'Penalty register compiled: ${inr(state.totalPenaltyAssessed)} assessed across the national ledger.',
              icon: Icons.gavel_rounded,
            ),
          ),
          AppButton(
            label: 'Open Master Ledger',
            icon: Icons.table_chart_rounded,
            color: AppColors.indigo,
            onPressed: () => state.selectNav(1),
          ),
        ],
      ),
      children: [
        KpiGrid(
          cards: [
            KpiCard(
              label: 'National FDR Corpus',
              value:
                  '₹${(state.nationalCorpus / 10000000).toStringAsFixed(2)} Cr',
              helper:
                  '${inr(state.nationalCorpus)} across ${state.records.length} recorded instruments',
              icon: Icons.account_balance_rounded,
              color: AppColors.navy,
            ),
            KpiCard(
              label: 'Pending Final Releases',
              value: '${queue.length}',
              helper: 'RO-cleared applications awaiting Finance approval',
              icon: Icons.pending_actions_rounded,
              color: AppColors.gold,
            ),
            KpiCard(
              label: 'Penalties Deducted',
              value: inr(state.totalPenaltiesDeducted),
              helper: state.totalPenaltiesDeducted == 0
                  ? '${inr(state.totalPenaltyAssessed)} assessed in the open queue'
                  : 'Recovered into the AICTE account',
              icon: Icons.gavel_rounded,
              color: AppColors.orange,
            ),
            KpiCard(
              label: 'Forfeited Funds',
              value: inr(state.totalForfeited),
              helper: 'Encashed to AICTE following final review',
              icon: Icons.account_balance_wallet_rounded,
              color: AppColors.red,
            ),
          ],
        ),
        InfoBanner(
          title: 'Final approval authority',
          message:
              'Finance approval generates a digitally verifiable e-NOC and routes the net settlement to the bank. Full release waives any assessed penalty; partial release deducts the confirmed amount; forfeiture closes the deposit without institute payment.',
          icon: Icons.verified_user_rounded,
          color: AppColors.indigo,
          trailing: SoftChip(
            label: '${queue.length} awaiting action',
            icon: Icons.account_balance_wallet_rounded,
            color: queue.isEmpty ? AppColors.emerald : AppColors.indigo,
          ),
        ),
        SectionCard(
          title: 'Final Settlement & Disbursement Queue',
          subtitle:
              'RO-cleared FDRs awaiting the final decision from AICTE Finance.',
          trailing: const SoftChip(
            label: 'RO cleared',
            icon: Icons.verified_rounded,
            color: AppColors.indigo,
          ),
          contentPadding: queue.isEmpty
              ? EdgeInsets.zero
              : const EdgeInsets.all(18),
          child: queue.isEmpty
              ? const EmptyState(
                  title: 'Final settlement queue is clear',
                  message:
                      'All RO-cleared applications have been settled. New Finance approvals will appear here as soon as the Regional Office forwards them.',
                  icon: Icons.task_alt_rounded,
                  color: AppColors.emerald,
                )
              : Column(
                  children: [
                    for (var index = 0; index < queue.length; index++) ...[
                      if (index > 0) const SizedBox(height: 12),
                      FinanceSettlementCard(
                        record: queue[index],
                        onFullRelease: () =>
                            _approveFullRelease(context, state, queue[index]),
                        onPartialRelease: () => _approvePartialRelease(
                          context,
                          state,
                          queue[index],
                        ),
                        onForfeit: () =>
                            _forfeitFdr(context, state, queue[index]),
                      ),
                    ],
                  ],
                ),
        ),
        SectionCard(
          title: 'Settlement Controls & Guardrails',
          subtitle:
              'Policy checks applied before an FDR can leave the Finance queue.',
          contentPadding: const EdgeInsets.all(20),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth >= 880;
              final width = wide
                  ? (constraints.maxWidth - 24) / 3
                  : constraints.maxWidth;
              const rules = [
                (
                  Icons.verified_rounded,
                  'RO clearance required',
                  'Only applications marked "RO Cleared - Pending Finance Approval" can be settled.',
                  AppColors.indigo,
                ),
                (
                  Icons.gavel_rounded,
                  'Penalty audit',
                  'Deduct or explicitly waive any assessed penalty before issuing the e-NOC.',
                  AppColors.gold,
                ),
                (
                  Icons.payments_rounded,
                  'Bank disbursement',
                  'The e-NOC routes the net amount to the partner bank settlement queue.',
                  AppColors.emeraldDark,
                ),
              ];
              return Wrap(
                spacing: 12,
                runSpacing: 12,
                children: rules.map((rule) {
                  return SizedBox(
                    width: width,
                    child: Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: rule.$4.withValues(alpha: 0.04),
                        borderRadius: BorderRadius.circular(11),
                        border: Border.all(
                          color: rule.$4.withValues(alpha: 0.12),
                        ),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(rule.$1, size: 18, color: rule.$4),
                          const SizedBox(width: 9),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  rule.$2,
                                  style: const TextStyle(
                                    fontSize: 10.8,
                                    fontWeight: FontWeight.w800,
                                    color: AppColors.navyInk,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  rule.$3,
                                  style: const TextStyle(
                                    fontSize: 9.3,
                                    color: AppColors.muted,
                                    height: 1.4,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              );
            },
          ),
        ),
      ],
    );
  }
}

class FinanceSettlementCard extends StatelessWidget {
  const FinanceSettlementCard({
    super.key,
    required this.record,
    required this.onFullRelease,
    required this.onPartialRelease,
    required this.onForfeit,
  });

  final FDRRecord record;
  final VoidCallback onFullRelease;
  final VoidCallback onPartialRelease;
  final VoidCallback onForfeit;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: AppColors.border),
        boxShadow: [
          BoxShadow(
            color: AppColors.indigo.withValues(alpha: 0.035),
            blurRadius: 14,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 13),
            decoration: const BoxDecoration(
              color: AppColors.surfaceSoft,
              borderRadius: BorderRadius.vertical(top: Radius.circular(13)),
              border: Border(bottom: BorderSide(color: AppColors.softBorder)),
            ),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final wide = constraints.maxWidth >= 560;
                final identity = Row(
                  children: [
                    BankMark(bankName: record.bankName, size: 42),
                    const SizedBox(width: 11),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            record.id,
                            style: const TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w800,
                              color: AppColors.navyInk,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${record.instituteName} • ID ${record.instituteId}',
                            style: const TextStyle(
                              fontSize: 9.5,
                              color: AppColors.muted,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                );
                final chips = Wrap(
                  spacing: 7,
                  runSpacing: 5,
                  alignment: WrapAlignment.end,
                  children: [
                    if (record.roClearedAt != null)
                      SoftChip(
                        label: 'RO cleared ${formatDate(record.roClearedAt!)}',
                        icon: Icons.verified_rounded,
                        color: AppColors.indigo,
                      ),
                    StatusPill(status: record.status),
                  ],
                );
                if (!wide) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      identity,
                      const SizedBox(height: 9),
                      Align(alignment: Alignment.centerRight, child: chips),
                    ],
                  );
                }
                return Row(
                  children: [
                    Expanded(child: identity),
                    const SizedBox(width: 10),
                    Flexible(child: chips),
                  ],
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                LayoutBuilder(
                  builder: (context, constraints) {
                    final wide = constraints.maxWidth >= 620;
                    final width = wide
                        ? (constraints.maxWidth - 20) / 3
                        : constraints.maxWidth;
                    return Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        SizedBox(
                          width: width,
                          child: _FinanceMetricBox(
                            label: 'Gross deposit',
                            value: inr(record.amount),
                            helper: record.bankName,
                            color: AppColors.navy,
                          ),
                        ),
                        SizedBox(
                          width: width,
                          child: _FinanceMetricBox(
                            label: 'Assessed penalty',
                            value: inr(record.penalty),
                            helper: record.penalty > 0
                                ? 'Awaiting deduction or waiver'
                                : 'No penalty on this FDR',
                            color: AppColors.orange,
                          ),
                        ),
                        SizedBox(
                          width: width,
                          child: _FinanceMetricBox(
                            label: 'Net releasable',
                            value: inr(record.netPayable),
                            helper: 'Before final Finance decision',
                            color: AppColors.emeraldDark,
                          ),
                        ),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 14),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final wide = constraints.maxWidth >= 760;
                    final actions = Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      alignment: wide ? WrapAlignment.end : WrapAlignment.start,
                      children: [
                        AppButton(
                          label: 'Approve Full Release & Issue e-NOC',
                          icon: Icons.task_alt_rounded,
                          dense: true,
                          color: AppColors.emeraldDark,
                          onPressed: onFullRelease,
                        ),
                        AppButton(
                          label: 'Approve Partial Release',
                          icon: Icons.content_cut_rounded,
                          dense: true,
                          color: AppColors.gold,
                          onPressed: onPartialRelease,
                        ),
                        AppButton(
                          label: 'Forfeit & Encash FDR',
                          icon: Icons.gavel_rounded,
                          primary: false,
                          dense: true,
                          color: AppColors.red,
                          onPressed: onForfeit,
                        ),
                      ],
                    );
                    if (!wide) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            'FINAL DECISION',
                            style: const TextStyle(
                              fontSize: 7.8,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 0.8,
                              color: AppColors.muted,
                            ),
                          ),
                          const SizedBox(height: 7),
                          actions,
                        ],
                      );
                    }
                    return Row(
                      children: [
                        const Text(
                          'FINAL DECISION',
                          style: TextStyle(
                            fontSize: 7.8,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0.8,
                            color: AppColors.muted,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(child: actions),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FinanceMetricBox extends StatelessWidget {
  const _FinanceMetricBox({
    required this.label,
    required this.value,
    required this.helper,
    required this.color,
  });

  final String label;
  final String value;
  final String helper;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.11)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            style: TextStyle(
              fontSize: 7.4,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.7,
              color: color,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            value,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w900,
              color: AppColors.navyInk,
              letterSpacing: -0.3,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            helper,
            style: const TextStyle(
              fontSize: 8.4,
              color: AppColors.muted,
              height: 1.3,
            ),
          ),
        ],
      ),
    );
  }
}

Future<void> _approveFullRelease(
  BuildContext context,
  PortalState state,
  FDRRecord record,
) async {
  final hasPenalty = record.penalty > 0;
  final confirmed = await showConfirmDialog(
    context,
    title: 'Approve full release?',
    message:
        'A full e-NOC will be generated for ${record.id}. ${hasPenalty ? 'The assessed penalty of ${inr(record.penalty)} will be waived because this is a full release.' : 'The full deposit will be released to the institute through the partner bank.'}',
    confirmLabel: 'Issue e-NOC',
    confirmColor: AppColors.emeraldDark,
    icon: Icons.task_alt_rounded,
    extra: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _DialogAmountBox(
          label: 'Full release amount',
          value: inr(record.amount),
          helper: '${record.instituteName}\n${record.bankName}',
        ),
        if (hasPenalty) ...[
          const SizedBox(height: 10),
          InfoBanner(
            title: 'Penalty waiver confirmation',
            message:
                'Use "Approve Partial Release" instead if the assessed penalty should be deducted before settlement.',
            icon: Icons.warning_amber_rounded,
            color: AppColors.orange,
          ),
        ],
      ],
    ),
  );
  if (!confirmed || !context.mounted) return;
  state.approveFullRelease(record);
  showAppToast(
    context,
    'Full release approved. e-NOC ${record.enocNumber} issued for ${record.id}.',
    icon: Icons.description_rounded,
    color: AppColors.emeraldDark,
  );
}

Future<void> _approvePartialRelease(
  BuildContext context,
  PortalState state,
  FDRRecord record,
) async {
  final deduction = await showDialog<double>(
    context: context,
    barrierColor: AppColors.navyInk.withValues(alpha: 0.5),
    builder: (context) => PartialReleaseDialog(record: record),
  );
  if (deduction == null || !context.mounted) return;
  state.approvePartialRelease(record, deduction);
  showAppToast(
    context,
    '${inr(deduction)} penalty deducted. Net ${inr(record.releasedAmount ?? 0)} released via e-NOC ${record.enocNumber}.',
    icon: Icons.account_balance_wallet_rounded,
    color: AppColors.gold,
  );
}

Future<void> _forfeitFdr(
  BuildContext context,
  PortalState state,
  FDRRecord record,
) async {
  final confirmed = await showConfirmDialog(
    context,
    title: 'Forfeit and encash this FDR?',
    message:
        '${record.id} will be encashed to the AICTE account. No funds will be released to ${record.instituteName}. This closes the FDR lifecycle and cannot be undone.',
    confirmLabel: 'Forfeit FDR',
    confirmColor: AppColors.red,
    icon: Icons.gavel_rounded,
    extra: _DialogAmountBox(
      label: 'Amount to be forfeited',
      value: inr(record.amount),
      helper: '${record.instituteName}\nAICTE Finance Bureau',
    ),
  );
  if (!confirmed || !context.mounted) return;
  state.forfeitFdr(record);
  showAppToast(
    context,
    '${record.id} forfeited and encashed to the AICTE account.',
    icon: Icons.gavel_rounded,
    color: AppColors.red,
  );
}

class PartialReleaseDialog extends StatefulWidget {
  const PartialReleaseDialog({super.key, required this.record});

  final FDRRecord record;

  @override
  State<PartialReleaseDialog> createState() => _PartialReleaseDialogState();
}

class _PartialReleaseDialogState extends State<PartialReleaseDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(
      text: widget.record.penalty.toStringAsFixed(0),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  double get _deduction => (double.tryParse(_controller.text) ?? 0)
      .clamp(0.0, widget.record.amount)
      .toDouble();

  bool get _isValid => _deduction >= 0 && _deduction <= widget.record.amount;

  @override
  Widget build(BuildContext context) {
    final record = widget.record;
    final net = record.amount - _deduction;
    return PortalDialogFrame(
      title: 'Approve Partial Release',
      subtitle: '${record.id} • ${record.instituteName} • ${record.bankName}',
      icon: '₹',
      maxWidth: 600,
      bodyPadding: const EdgeInsets.all(20),
      actions: [
        AppButton(
          label: 'Cancel',
          primary: false,
          onPressed: () => Navigator.of(context).pop(),
        ),
        AppButton(
          label: 'Deduct & Issue e-NOC',
          icon: Icons.description_rounded,
          color: AppColors.gold,
          onPressed: _isValid
              ? () => Navigator.of(context).pop(_deduction)
              : null,
        ),
      ],
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InfoBanner(
            title: 'Penalty deduction',
            message:
                'Confirm the amount to be deducted from the deposit before issuing the e-NOC. The net amount will be routed to the bank settlement queue.',
            icon: Icons.content_cut_rounded,
            color: AppColors.gold,
          ),
          const SizedBox(height: 16),
          _DialogAmountBox(
            label: 'Gross deposit',
            value: inr(record.amount),
            helper:
                '${record.instituteName}\nAssessed penalty ${inr(record.penalty)}',
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _controller,
            keyboardType: TextInputType.number,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(9),
            ],
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              labelText: 'Penalty deduction (₹)',
              prefixIcon: const Icon(Icons.gavel_rounded, size: 18),
              suffixText: 'INR',
              helperText: 'Assessed penalty: ${inr(record.penalty)}',
              errorText: _deduction > record.amount
                  ? 'Deduction cannot exceed the deposit amount'
                  : null,
            ),
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(15),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFFECFDF5), Color(0xFFF0FDF4)],
              ),
              borderRadius: BorderRadius.circular(11),
              border: Border.all(
                color: AppColors.emerald.withValues(alpha: 0.22),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'NET AMOUNT TO RELEASE',
                  style: TextStyle(
                    fontSize: 7.8,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.8,
                    color: AppColors.emeraldDark,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  inr(net),
                  style: const TextStyle(
                    fontSize: 27,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.7,
                    color: AppColors.navyInk,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  'Penalty deducted: ${inr(_deduction)} • e-NOC issued immediately',
                  style: const TextStyle(fontSize: 9.2, color: AppColors.muted),
                ),
              ],
            ),
          ),
          const SizedBox(height: 13),
          const Text(
            'The deduction will be recorded against the national penalty ledger and reflected in the master audit trail.',
            style: TextStyle(fontSize: 9, color: AppColors.muted, height: 1.45),
          ),
        ],
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Master ledger
// -----------------------------------------------------------------------------

class FinanceLedgerPage extends StatefulWidget {
  const FinanceLedgerPage({super.key, required this.state});

  final PortalState state;

  @override
  State<FinanceLedgerPage> createState() => _FinanceLedgerPageState();
}

class _FinanceLedgerPageState extends State<FinanceLedgerPage> {
  final _searchController = TextEditingController();
  FDRStatus? _statusFilter;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<FDRRecord> get _filteredRecords {
    final query = _searchController.text.trim().toLowerCase();
    return widget.state.records.where((record) {
      final matchesQuery =
          query.isEmpty ||
          [
            record.id,
            record.instituteName,
            record.instituteId,
            record.bankName,
            record.ifsc,
            record.program,
            record.enocNumber ?? '',
          ].any((value) => value.toLowerCase().contains(query));
      final matchesStatus =
          _statusFilter == null || record.status == _statusFilter;
      return matchesQuery && matchesStatus;
    }).toList();
  }

  Future<void> _copyCsv(BuildContext context) async {
    final rows = <List<String>>[
      [
        'FDR Number',
        'Institute',
        'Institute ID',
        'Bank',
        'IFSC',
        'Program',
        'Intake',
        'Amount',
        'Penalty',
        'Penalty Deducted',
        'Status',
        'Issue Date',
        'Maturity Date',
        'e-NOC',
      ],
      for (final record in widget.state.records)
        [
          record.id,
          record.instituteName,
          record.instituteId,
          record.bankName,
          record.ifsc,
          record.program,
          '${record.intake}',
          record.amount.toStringAsFixed(0),
          record.penalty.toStringAsFixed(0),
          record.deductedPenalty.toStringAsFixed(0),
          record.status.label,
          formatDate(record.issueDate),
          formatDate(record.maturityDate),
          record.enocNumber ?? '',
        ],
    ];
    final csv = rows
        .map(
          (row) =>
              row.map((value) => '"${value.replaceAll('"', '""')}"').join(','),
        )
        .join('\n');
    await Clipboard.setData(ClipboardData(text: csv));
    if (!context.mounted) return;
    showAppToast(
      context,
      'Master ledger copied as CSV to the clipboard.',
      icon: Icons.copy_all_rounded,
      color: AppColors.indigo,
    );
  }

  @override
  Widget build(BuildContext context) {
    final records = _filteredRecords;
    return WorkspacePage(
      header: WorkspaceHeader(
        eyebrow: 'AICTE finance bureau • national master ledger',
        title: 'National FDR Master Ledger',
        subtitle:
            'Read-only consolidated view of every security deposit instrument across institutes, partner banks, regions and lifecycle states.',
        actions: [
          AppButton(
            label: 'Copy Ledger as CSV',
            icon: Icons.copy_all_rounded,
            primary: false,
            onPressed: () => _copyCsv(context),
          ),
          AppButton(
            label: 'Final Settlement Queue',
            icon: Icons.account_balance_wallet_rounded,
            color: AppColors.gold,
            onPressed: () => widget.state.selectNav(0),
          ),
        ],
      ),
      children: [
        KpiGrid(
          cards: [
            KpiCard(
              label: 'Ledger Instruments',
              value: '${widget.state.records.length}',
              helper: 'All FDRs recorded across the national portal',
              icon: Icons.dataset_rounded,
              color: AppColors.navy,
            ),
            KpiCard(
              label: 'National Corpus',
              value: inrCompact(widget.state.nationalCorpus),
              helper: inr(widget.state.nationalCorpus),
              icon: Icons.account_balance_rounded,
              color: AppColors.indigo,
            ),
            KpiCard(
              label: 'Filtered Records',
              value: '${records.length}',
              helper: _statusFilter == null
                  ? 'No status filter applied'
                  : 'Filtered by ${_statusFilter!.label}',
              icon: Icons.filter_alt_rounded,
              color: AppColors.gold,
            ),
            KpiCard(
              label: 'Audit Mutability',
              value: 'Read Only',
              helper: 'Ledger entries cannot be edited from Finance HQ',
              icon: Icons.lock_rounded,
              color: AppColors.emerald,
            ),
          ],
        ),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.border),
            boxShadow: [
              BoxShadow(
                color: AppColors.navy.withValues(alpha: 0.03),
                blurRadius: 14,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth >= 760;
              final search = SizedBox(
                width: wide ? 330 : double.infinity,
                child: TextField(
                  controller: _searchController,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    hintText: 'Search FDR, institute, bank, IFSC or e-NOC',
                    prefixIcon: const Icon(Icons.search_rounded, size: 19),
                    suffixIcon: _searchController.text.isEmpty
                        ? null
                        : IconButton(
                            onPressed: () {
                              _searchController.clear();
                              setState(() {});
                            },
                            icon: const Icon(Icons.close_rounded, size: 17),
                          ),
                  ),
                ),
              );
              final statusFilter = SizedBox(
                width: wide ? 300 : double.infinity,
                height: 48,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceSoft,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<FDRStatus?>(
                      value: _statusFilter,
                      isExpanded: true,
                      borderRadius: BorderRadius.circular(10),
                      dropdownColor: Colors.white,
                      hint: const Text(
                        'All lifecycle statuses',
                        style: TextStyle(fontSize: 11, color: AppColors.muted),
                      ),
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.navyInk,
                        fontWeight: FontWeight.w600,
                      ),
                      items: [
                        const DropdownMenuItem<FDRStatus?>(
                          value: null,
                          child: Text(
                            'All lifecycle statuses',
                            style: TextStyle(fontSize: 11),
                          ),
                        ),
                        ...FDRStatus.values.map(
                          (status) => DropdownMenuItem<FDRStatus?>(
                            value: status,
                            child: Text(
                              status.label,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 11),
                            ),
                          ),
                        ),
                      ],
                      onChanged: (value) {
                        setState(() => _statusFilter = value);
                      },
                    ),
                  ),
                ),
              );
              final reset = TextButton.icon(
                onPressed:
                    (_searchController.text.isEmpty && _statusFilter == null)
                    ? null
                    : () {
                        _searchController.clear();
                        setState(() => _statusFilter = null);
                      },
                icon: const Icon(Icons.restart_alt_rounded, size: 16),
                label: const Text(
                  'Reset filters',
                  style: TextStyle(fontSize: 10.5),
                ),
              );
              return Wrap(
                spacing: 12,
                runSpacing: 10,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  search,
                  statusFilter,
                  reset,
                  SoftChip(
                    label:
                        '${records.length} of ${widget.state.records.length} records',
                    icon: Icons.table_rows_rounded,
                    color: AppColors.navy,
                  ),
                ],
              );
            },
          ),
        ),
        SectionCard(
          title: 'Consolidated FDR Register',
          subtitle:
              'Complete read-only ledger • click any row to inspect the lifecycle tracker.',
          trailing: const SoftChip(
            label: 'Immutable audit view',
            icon: Icons.lock_outline_rounded,
            color: AppColors.emeraldDark,
          ),
          contentPadding: const EdgeInsets.only(bottom: 8),
          child: records.isEmpty
              ? const EmptyState(
                  title: 'No records match the filters',
                  message:
                      'Adjust the search keyword or lifecycle status filter to see ledger entries.',
                  icon: Icons.search_off_rounded,
                  color: AppColors.muted,
                )
              : TableScroll(
                  minWidth: 1510,
                  child: DataTable(
                    showCheckboxColumn: false,
                    horizontalMargin: 20,
                    columnSpacing: 22,
                    headingRowHeight: 46,
                    dataRowMinHeight: 66,
                    dataRowMaxHeight: 82,
                    headingRowColor: const WidgetStatePropertyAll(
                      AppColors.surfaceSoft,
                    ),
                    headingTextStyle: const TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.8,
                      color: AppColors.muted,
                    ),
                    dataTextStyle: const TextStyle(
                      fontSize: 11,
                      color: AppColors.ink,
                    ),
                    dividerThickness: 1,
                    border: const TableBorder(
                      horizontalInside: BorderSide(color: AppColors.softBorder),
                    ),
                    columns: const [
                      DataColumn(label: Text('FDR / BANK')),
                      DataColumn(label: Text('INSTITUTE')),
                      DataColumn(label: Text('PROGRAM')),
                      DataColumn(label: Text('AMOUNT')),
                      DataColumn(label: Text('PENALTY')),
                      DataColumn(label: Text('MATURITY')),
                      DataColumn(label: Text('STATUS')),
                      DataColumn(label: Text('e-NOC / UPDATED')),
                    ],
                    rows: records.map((record) {
                      return DataRow(
                        onSelectChanged: (_) =>
                            showTrackerDialog(context, record),
                        cells: [
                          DataCell(
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                BankMark(bankName: record.bankName, size: 34),
                                const SizedBox(width: 9),
                                Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      record.id,
                                      style: const TextStyle(
                                        fontSize: 10.5,
                                        fontWeight: FontWeight.w800,
                                        color: AppColors.navyInk,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      '${record.bankName} • ${record.ifsc}',
                                      style: const TextStyle(
                                        fontSize: 8.8,
                                        color: AppColors.muted,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          DataCell(
                            Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  record.instituteName,
                                  style: const TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                Text(
                                  'ID ${record.instituteId}',
                                  style: const TextStyle(
                                    fontSize: 8.8,
                                    color: AppColors.muted,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          DataCell(
                            Text(
                              record.program,
                              style: const TextStyle(fontSize: 9.8),
                            ),
                          ),
                          DataCell(
                            Text(
                              inr(record.amount),
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                                color: AppColors.navyInk,
                              ),
                            ),
                          ),
                          DataCell(
                            Text(
                              record.penalty > 0 ? inr(record.penalty) : '—',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: record.penalty > 0
                                    ? FontWeight.w700
                                    : FontWeight.w400,
                                color: record.penalty > 0
                                    ? AppColors.orange
                                    : AppColors.muted,
                              ),
                            ),
                          ),
                          DataCell(
                            Text(
                              formatDate(record.maturityDate),
                              style: const TextStyle(fontSize: 9.8),
                            ),
                          ),
                          DataCell(StatusPill(status: record.status)),
                          DataCell(
                            Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  record.enocNumber ?? 'No e-NOC',
                                  style: TextStyle(
                                    fontSize: 9,
                                    fontWeight: record.enocNumber != null
                                        ? FontWeight.w700
                                        : FontWeight.w400,
                                    color: record.enocNumber != null
                                        ? AppColors.indigo
                                        : AppColors.muted,
                                  ),
                                ),
                                Text(
                                  timeAgo(record.lastUpdated),
                                  style: const TextStyle(
                                    fontSize: 8.8,
                                    color: AppColors.muted,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      );
                    }).toList(),
                  ),
                ),
        ),
      ],
    );
  }
}

// -----------------------------------------------------------------------------
// Notification centre
// -----------------------------------------------------------------------------

Future<void> showNotificationsDialog(
  BuildContext context,
  PortalState state,
) async {
  await showDialog<void>(
    context: context,
    barrierColor: AppColors.navyInk.withValues(alpha: 0.48),
    builder: (context) {
      return AnimatedBuilder(
        animation: state,
        builder: (context, _) {
          final unread = state.unreadNotifications;
          return PortalDialogFrame(
            title: 'Notification Centre',
            subtitle:
                '$unread unread • ${state.activities.length} recent portal events',
            icon: 'i',
            maxWidth: 640,
            accent: AppColors.gold,
            bodyPadding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
            actions: [
              if (unread > 0)
                AppButton(
                  label: 'Mark All Read',
                  icon: Icons.done_all_rounded,
                  color: AppColors.gold,
                  onPressed: state.markAllNotificationsRead,
                ),
              AppButton(
                label: 'Close',
                primary: false,
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
            body: state.activities.isEmpty
                ? const EmptyState(
                    title: 'No notifications yet',
                    message:
                        'Portal activity from all four stakeholder roles will appear here.',
                    icon: Icons.notifications_none_rounded,
                  )
                : Column(
                    children: [
                      for (
                        var index = 0;
                        index < state.activities.length;
                        index++
                      ) ...[
                        if (index > 0) const Divider(height: 1),
                        _NotificationTile(activity: state.activities[index]),
                      ],
                    ],
                  ),
          );
        },
      );
    },
  );
}

class _NotificationTile extends StatelessWidget {
  const _NotificationTile({required this.activity});

  final ActivityLog activity;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: activity.color.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: activity.color.withValues(alpha: 0.13)),
            ),
            child: Icon(activity.icon, size: 18, color: activity.color),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        activity.title,
                        style: const TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w800,
                          color: AppColors.navyInk,
                        ),
                      ),
                    ),
                    if (!activity.read)
                      Container(
                        width: 7,
                        height: 7,
                        decoration: const BoxDecoration(
                          color: AppColors.gold,
                          shape: BoxShape.circle,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  activity.detail,
                  style: const TextStyle(
                    fontSize: 10,
                    color: AppColors.muted,
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  timeAgo(activity.timestamp),
                  style: TextStyle(
                    fontSize: 8.3,
                    color: AppColors.muted.withValues(alpha: 0.8),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
