import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'ocr_service.dart';

void main() {
  runApp(const EKoshApp());
}

/// Global text scale so the dense dashboard typography stays readable on
/// desktop browsers without having to zoom the page.
const double kPortalTextScale = 1.4;

/// Demo OTP issued by the password recovery flow for evaluator walkthroughs.
const String _demoOtp = '654321';

/// Node/Express + MongoDB API that backs the SSO gateway and live dashboards.
const String kApiBaseUrl = 'http://localhost:5000';

/// Outcome of a database-backed SSO call. [unavailable] keeps the offline demo
/// path working when the API cannot be reached.
enum BackendAuthResult { success, invalidCredentials, unavailable }

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

/// Demo single sign-on account issued to each portal persona. In production
/// these would be provisioned by the AICTE identity service; here they gate the
/// four dashboards so the prototype can demonstrate authenticated access.
class PortalCredential {
  const PortalCredential({
    required this.role,
    required this.userId,
    required this.password,
    required this.scope,
  });

  final UserRole role;
  final String userId;
  final String password;
  final String scope;

  /// The local part of the user ID (e.g. `principal` for
  /// `principal@kpr.edu.in`) is accepted as a shorthand at sign-in.
  String get shortId => userId.split('@').first;

  String get maskedPassword => List.filled(password.length, '•').join();
}

const kPortalCredentials = <UserRole, PortalCredential>{
  UserRole.institute: PortalCredential(
    role: UserRole.institute,
    userId: 'principal@kpr.edu.in',
    password: 'Kpr@2026',
    scope:
        'Institutional FDR portfolio, new submissions, renewals and e-NOC downloads.',
  ),
  UserRole.bank: PortalCredential(
    role: UserRole.bank,
    userId: 'banknode@sbi.co.in',
    password: 'Sbi@2026',
    scope:
        'Joint lien verification, e-NOC QR settlement and fund disbursement.',
  ),
  UserRole.ro: PortalCredential(
    role: UserRole.ro,
    userId: 'ro.south@aicte.gov.in',
    password: 'RoSouth@2026',
    scope:
        'Regional scrutiny, extension mandates, penalties and forfeiture sanctions.',
  ),
  UserRole.finance: PortalCredential(
    role: UserRole.finance,
    userId: 'finance.hq@aicte.gov.in',
    password: 'Finance@2026',
    scope:
        'Final settlement, corpus accounting, executive analytics and audit intelligence.',
  ),
};

PortalCredential credentialFor(UserRole role) => kPortalCredentials[role]!;

/// Stakeholder role string stored in the MongoDB `users` collection.
String apiRoleFor(UserRole role) => switch (role) {
  UserRole.institute => 'Institute Login',
  UserRole.bank => 'Bank Node',
  UserRole.ro => 'AICTE RO',
  UserRole.finance => 'Finance HQ',
};

/// Dashboard module owned by a stakeholder role when the API is offline.
String portalModuleFor(UserRole role) => switch (role) {
  UserRole.institute => 'Portfolio & Tracker',
  UserRole.bank => 'Verification Desk',
  UserRole.ro => 'Scrutiny Queue',
  UserRole.finance => 'Final Settlement',
};

/// Maps the database role string back to the typed portal role.
UserRole? roleFromApi(String? value) => switch (value) {
  'Institute Login' => UserRole.institute,
  'Bank Node' => UserRole.bank,
  'AICTE RO' => UserRole.ro,
  'Finance HQ' => UserRole.finance,
  _ => null,
};

/// Authenticated identity returned by `POST /api/auth/login`. The portal uses
/// this immutable model as the single source of truth for role routing.
class PortalUser {
  const PortalUser({
    required this.role,
    required this.portalModule,
    required this.email,
    this.organizationName,
    this.aicteOrIfscCode,
  });

  factory PortalUser.fromApi(
    Map<String, dynamic> json, {
    required UserRole fallbackRole,
  }) {
    return PortalUser(
      role: roleFromApi(json['role']?.toString()) ?? fallbackRole,
      portalModule:
          json['portal_module']?.toString() ?? portalModuleFor(fallbackRole),
      email: json['email']?.toString() ?? credentialFor(fallbackRole).userId,
      organizationName: json['organization_name']?.toString(),
      aicteOrIfscCode: json['aicte_or_ifsc_code']?.toString(),
    );
  }

  final UserRole role;
  final String portalModule;
  final String email;
  final String? organizationName;
  final String? aicteOrIfscCode;
}

Map<String, dynamic> _jsonMap(dynamic value) =>
    value is Map ? value.cast<String, dynamic>() : <String, dynamic>{};

DateTime _apiDate(dynamic value, DateTime fallback) {
  if (value is String) {
    return DateTime.tryParse(value) ?? fallback;
  }
  return fallback;
}

double _apiDouble(dynamic value) => value is num ? value.toDouble() : 0;

int _apiInt(dynamic value) => value is num ? value.toInt() : 0;

/// Maps a MongoDB `lifecycle_status` onto the dashboard badge model.
FDRStatus _statusFromApi(String? value) => switch (value) {
  'ACTIVE_LIEN_LOCKED' => FDRStatus.activeLienLocked,
  'MATURED_PENDING_RO' => FDRStatus.maturedPendingRO,
  'RO_CLEARED_PENDING_FINANCE' => FDRStatus.roClearedPendingFinance,
  'RELEASED_ENOC' => FDRStatus.releasedENOC,
  'PARTIAL_RELEASE_APPROVED' => FDRStatus.partialReleaseApproved,
  'FUNDS_DISBURSED' => FDRStatus.fundsDisbursed,
  'ON_HOLD_EXTENSION' => FDRStatus.onHoldExtension,
  'REJECTED_BY_BANK' => FDRStatus.rejectedByBank,
  'FORFEITED_ENCASHED_BY_AICTE' => FDRStatus.forfeited,
  _ => FDRStatus.pendingBankVerification,
};

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
  partialReleaseApproved(
    label: 'Partial Release Approved',
    fg: Color(0xFFB45309),
    bg: Color(0xFFFFFBEB),
    border: Color(0xFFFDE68A),
    icon: Icons.content_cut_rounded,
  ),
  fundsDisbursed(
    label: 'Settled & Closed',
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
    label: 'Forfeited & Encashed by AICTE',
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
    FDRStatus.partialReleaseApproved => 5,
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
    FDRStatus.partialReleaseApproved => 4,
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
    this.renewalCount = 0,
    this.renewedAt,
    this.region = 'Southern',
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
  DateTime maturityDate;
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
  int renewalCount;
  DateTime? renewedAt;
  String region;

  bool get isMatured => !maturityDate.isAfter(DateTime.now());

  bool get hasEnoc =>
      enocNumber != null &&
      {
        FDRStatus.releasedENOC,
        FDRStatus.partialReleaseApproved,
        FDRStatus.fundsDisbursed,
      }.contains(status);

  int get daysToMaturity => maturityDate.difference(DateTime.now()).inDays;

  bool get isOverdue => daysToMaturity < 0;

  bool get isRenewalRequired => status == FDRStatus.onHoldExtension;

  double get netPayable => amount > penalty ? amount - penalty : 0;

  double get settlementValue => releasedAmount ?? netPayable;

  double get amountCreditedToCorpus => deductedPenalty > 0
      ? deductedPenalty
      : (status == FDRStatus.forfeited ? amount : 0);

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

/// Immutable security-trail entry. Every portal action appends one of these
/// with the acting role, the affected FDR and a simulated IP / SHA reference.
class AuditEntry {
  AuditEntry({
    required this.timestamp,
    required this.actor,
    required this.fdrId,
    required this.action,
    required this.ipReference,
    required this.hashReference,
  });

  final DateTime timestamp;
  final String actor;
  final String fdrId;
  final String action;
  final String ipReference;
  final String hashReference;
}

class StatusSlice {
  const StatusSlice(this.label, this.count, this.color);

  final String label;
  final int count;
  final Color color;
}

/// One Email + SMS advisory recorded by the AICTE maturity dispatch gateway.
/// Mirrors the `notification_logs` collection in the Node backend.
class MaturityNotificationLog {
  const MaturityNotificationLog({
    required this.fdrNumber,
    required this.aicteId,
    required this.instituteName,
    required this.recipientEmail,
    required this.recipientMobile,
    required this.milestoneWindow,
    required this.channels,
    required this.messagePreview,
    required this.deliveryStatus,
    required this.triggeredBy,
    required this.timestamp,
    this.daysToMaturity,
  });

  final String fdrNumber;
  final String aicteId;
  final String instituteName;
  final String recipientEmail;
  final String recipientMobile;
  final String milestoneWindow;
  final List<String> channels;
  final String messagePreview;
  final String deliveryStatus;
  final String triggeredBy;
  final DateTime timestamp;
  final int? daysToMaturity;

  static MaturityNotificationLog fromApi(Map<String, dynamic> json) {
    final channelsRaw = json['channels'];
    final channels = channelsRaw is List
        ? channelsRaw.map((channel) => channel.toString()).toList()
        : <String>['EMAIL', 'SMS'];
    return MaturityNotificationLog(
      fdrNumber: json['fdr_number']?.toString() ?? 'FDR-UNKNOWN',
      aicteId: json['aicte_id']?.toString() ?? 'N/A',
      instituteName: json['institute_name']?.toString() ?? 'AICTE Institute',
      recipientEmail:
          json['recipient_email']?.toString() ?? 'institute.nodal@aicte.gov.in',
      recipientMobile: json['recipient_mobile']?.toString() ?? 'N/A',
      milestoneWindow: json['milestone_window']?.toString() ?? '90_DAYS',
      channels: channels,
      messagePreview: json['message_preview']?.toString() ?? '',
      deliveryStatus: json['delivery_status']?.toString() ?? 'DELIVERED',
      triggeredBy: json['triggered_by']?.toString() ?? 'AUTO_CRON_SCHEDULER',
      timestamp:
          DateTime.tryParse(json['timestamp']?.toString() ?? '')?.toLocal() ??
          DateTime.now(),
      daysToMaturity: json['days_to_maturity'] is num
          ? (json['days_to_maturity'] as num).toInt()
          : null,
    );
  }

  String get milestoneShort => switch (milestoneWindow) {
    '30_DAYS' => '30D',
    '60_DAYS' => '60D',
    _ => '90D',
  };

  String get milestoneLabel => switch (milestoneWindow) {
    '30_DAYS' => '30-Day Critical',
    '60_DAYS' => '60-Day Follow-Up',
    _ => '90-Day Advisory',
  };

  Color get milestoneColor => switch (milestoneWindow) {
    '30_DAYS' => AppColors.red,
    '60_DAYS' => AppColors.orange,
    _ => AppColors.indigo,
  };

  bool get isAutomatic => triggeredBy == 'AUTO_CRON_SCHEDULER';
}

// -----------------------------------------------------------------------------
// Centralized state controller
// -----------------------------------------------------------------------------

class PortalState extends ChangeNotifier {
  PortalState() {
    _seed();
    _seedLocalNotificationLogs();
  }

  static const kprId = '1-492831';

  UserRole _role = UserRole.institute;
  int _navIndex = 0;
  int _enocSequence = 4127;
  bool _authenticated = false;
  String? _signedInUserId;
  DateTime? _lastSignInAt;
  bool maturityCronRan = false;
  int maturityCronRuns = 0;
  DateTime? lastCronRun;
  bool maturityAlertDismissed = false;

  /// Live gateway ledger returned by `GET /api/notifications/logs`.
  final List<MaturityNotificationLog> notificationLogs = [];
  int notificationWithin90 = 0;
  int notificationWithin60 = 0;
  int notificationWithin30 = 0;
  int notificationLastDispatchCount = 0;
  bool notificationScanBusy = false;
  bool notificationAutoChecked = false;
  DateTime? lastNotificationScan;
  String notificationGatewayStatus = 'STANDBY';

  final List<FDRRecord> records = [];
  final List<ActivityLog> activities = [];
  final List<AuditEntry> auditLog = [];
  final Map<UserRole, String> _passwordOverrides = <UserRole, String>{};

  Map<String, dynamic>? _liveDashboardData;
  PortalUser? _currentUser;
  bool _backendOnline = false;

  UserRole get role => _role;
  int get navIndex => _navIndex;
  bool get isAuthenticated => _authenticated;
  String? get signedInUserId => _signedInUserId;
  DateTime? get lastSignInAt => _lastSignInAt;
  PortalCredential get credential => credentialFor(_role);

  /// Authenticated database identity; null until a successful SSO login.
  PortalUser? get currentUser => _currentUser;

  /// Latest payload returned by `GET /api/dashboard-data`, when reachable.
  Map<String, dynamic>? get liveDashboardData => _liveDashboardData;

  /// Whether the last database call succeeded.
  bool get backendOnline => _backendOnline;

  /// Returns the current SSO password, including any password that was
  /// updated through the OTP recovery flow during this session.
  String passwordFor(UserRole role) =>
      _passwordOverrides[role] ?? credentialFor(role).password;

  /// Validates the demo SSO credential for [role] and opens that dashboard.
  /// Accepts either the full user ID or its local part (before `@`).
  bool signIn(UserRole role, String userId, String password) {
    final account = credentialFor(role);
    final entered = userId.trim().toLowerCase();
    final idMatches =
        entered == account.userId.toLowerCase() ||
        entered == account.shortId.toLowerCase();
    if (!idMatches || password != passwordFor(role)) {
      return false;
    }
    _openSession(role, account.userId);
    return true;
  }

  void _openSession(UserRole role, String userId, {PortalUser? user}) {
    _role = role;
    _navIndex = 0;
    _authenticated = true;
    _signedInUserId = userId;
    _currentUser =
        user ??
        PortalUser(
          role: role,
          portalModule: portalModuleFor(role),
          email: userId,
          organizationName: role.org,
        );
    _lastSignInAt = DateTime.now();
    _log(
      title: 'Secure sign-in verified',
      detail:
          '${role.personName} authenticated to the ${role.label} dashboard '
          'via AICTE SSO as $userId.',
      icon: Icons.verified_user_rounded,
      color: AppColors.emeraldDark,
    );
    notifyListeners();
  }

  /// Authenticates against the MongoDB-backed SSO API. Falls back to the
  /// offline demo credentials when the backend is unreachable.
  Future<BackendAuthResult> signInWithBackend(
    UserRole role,
    String userId,
    String password,
  ) async {
    try {
      final response = await http
          .post(
            Uri.parse('$kApiBaseUrl/api/auth/login'),
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode({
              'role': apiRoleFor(role),
              'email': userId.trim(),
              'password': password,
            }),
          )
          .timeout(const Duration(seconds: 4));

      if (response.statusCode == 401 || response.statusCode == 403) {
        return BackendAuthResult.invalidCredentials;
      }
      if (response.statusCode != 200) {
        return BackendAuthResult.unavailable;
      }
      final decoded = jsonDecode(response.body);
      if (decoded is! Map || decoded['success'] != true) {
        return BackendAuthResult.invalidCredentials;
      }
      final userJson = _jsonMap(decoded['user']);
      final user = PortalUser.fromApi(userJson, fallbackRole: role);
      _backendOnline = true;
      _openSession(user.role, user.email, user: user);
      await fetchDashboardData();
      return BackendAuthResult.success;
    } catch (_) {
      _backendOnline = false;
      return BackendAuthResult.unavailable;
    }
  }

  /// Persists a new password for [role] through
  /// `PATCH /api/auth/reset-password`.
  Future<BackendAuthResult> resetPasswordWithBackend(
    UserRole role,
    String identifier,
    String newPassword,
  ) async {
    try {
      final response = await http
          .patch(
            Uri.parse('$kApiBaseUrl/api/auth/reset-password'),
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode({
              'role': apiRoleFor(role),
              'email': identifier.trim(),
              'new_password': newPassword,
            }),
          )
          .timeout(const Duration(seconds: 6));

      if (response.statusCode == 404) {
        return BackendAuthResult.invalidCredentials;
      }
      if (response.statusCode == 200) {
        _backendOnline = true;
        return BackendAuthResult.success;
      }
      return BackendAuthResult.unavailable;
    } catch (_) {
      _backendOnline = false;
      return BackendAuthResult.unavailable;
    }
  }

  /// Loads live FDR, institute and audit data from the backend and merges the
  /// FDRs into the dashboards without discarding the offline seed records.
  Future<void> fetchDashboardData() async {
    try {
      final response = await http
          .get(Uri.parse('$kApiBaseUrl/api/dashboard-data'))
          .timeout(const Duration(seconds: 6));
      if (response.statusCode != 200) return;
      final decoded = jsonDecode(response.body);
      if (decoded is! Map) return;
      final payload = decoded.cast<String, dynamic>();
      if (payload['success'] != true) return;
      _liveDashboardData = payload;
      _mergeLiveFdrs(payload['fdrs']);
      _backendOnline = true;
      notifyListeners();
    } catch (_) {
      _backendOnline = false;
    }
  }

  void _mergeLiveFdrs(dynamic rawFdrs) {
    if (rawFdrs is! List) return;
    for (final entry in rawFdrs) {
      if (entry is! Map) continue;
      final raw = entry.cast<String, dynamic>();
      final id = raw['fdr_number']?.toString() ?? '';
      if (id.isEmpty) continue;

      final bank = _jsonMap(raw['bank_details']);
      final financials = _jsonMap(raw['financials']);
      final timeline = _jsonMap(raw['timeline']);
      final issueDate = _apiDate(timeline['issue_date'], DateTime.now());
      final maturityDate = _apiDate(timeline['maturity_date'], issueDate);
      final penalty = _apiDouble(financials['penalty_deducted']);

      final record = FDRRecord(
        id: id,
        bankName: bank['bank_name']?.toString() ?? 'Partner Bank',
        ifsc: bank['ifsc_code']?.toString() ?? 'N/A',
        instituteName: raw['institute_name']?.toString() ?? 'AICTE Institute',
        instituteId: raw['aicte_permanent_id']?.toString() ?? kprId,
        program: raw['program_type']?.toString() ?? 'AICTE Programme',
        intake: _apiInt(raw['intake']),
        amount: _apiDouble(financials['principal_amount']),
        issueDate: issueDate,
        maturityDate: maturityDate,
        status: _statusFromApi(raw['lifecycle_status']?.toString()),
        lastUpdated: DateTime.now(),
        penalty: penalty,
        deductedPenalty: penalty,
        deficiency: timeline['is_time_exceeded'] == true,
        remarks: 'Live MongoDB record.',
      );

      final index = records.indexWhere((item) => item.id == id);
      if (index == -1) {
        records.insert(0, record);
      } else {
        records[index] = record;
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Automated 90 / 60 / 30-day maturity notification gateway
  // ---------------------------------------------------------------------------

  int get notificationDispatchedToday {
    final now = DateTime.now();
    return notificationLogs
        .where(
          (log) =>
              log.timestamp.year == now.year &&
              log.timestamp.month == now.month &&
              log.timestamp.day == now.day,
        )
        .length;
  }

  /// Fetches the live Email + SMS gateway ledger. When the API is unreachable
  /// the locally derived demo ledger is retained so all dashboards keep
  /// rendering meaningful government records.
  Future<int> fetchNotificationLogs({bool notify = true}) async {
    try {
      final response = await http
          .get(Uri.parse('$kApiBaseUrl/api/notifications/logs'))
          .timeout(const Duration(seconds: 6));
      if (response.statusCode != 200) return notificationLogs.length;
      final decoded = jsonDecode(response.body);
      if (decoded is! Map || decoded['success'] != true) {
        return notificationLogs.length;
      }
      final payload = decoded.cast<String, dynamic>();
      final rawLogs = payload['logs'];
      if (rawLogs is List) {
        notificationLogs
          ..clear()
          ..addAll(
            rawLogs.whereType<Map>().map(
              (entry) => MaturityNotificationLog.fromApi(
                entry.cast<String, dynamic>(),
              ),
            ),
          );
      }
      final counts = _jsonMap(payload['window_counts']);
      if (counts.isNotEmpty) {
        notificationWithin90 = _apiInt(counts['within_90_days']);
        notificationWithin60 = _apiInt(counts['within_60_days']);
        notificationWithin30 = _apiInt(counts['within_30_days']);
      } else {
        _refreshLocalNotificationCounts();
      }
      _backendOnline = true;
      if (notify) notifyListeners();
    } catch (_) {
      _backendOnline = false;
    }
    return notificationLogs.length;
  }

  /// Invokes the Finance HQ manual scan. The backend force-dispatches a fresh
  /// Email + SMS advisory for every qualifying FDR so evaluators can watch the
  /// gateway ledger update in real time.
  Future<int> runMaturityNotificationScan({bool silent = false}) async {
    if (notificationScanBusy) return 0;
    notificationScanBusy = true;
    notificationGatewayStatus = 'SCANNING';
    if (!silent) notifyListeners();
    var dispatched = 0;
    try {
      final response = await http
          .post(
            Uri.parse('$kApiBaseUrl/api/notifications/run-scheduler'),
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode({
              'force': true,
              'triggered_by': 'FINANCE_HQ_MANUAL',
            }),
          )
          .timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        if (decoded is Map && decoded['success'] == true) {
          final payload = decoded.cast<String, dynamic>();
          dispatched = _apiInt(payload['dispatched_count']);
          final counts = _jsonMap(payload['window_counts']);
          notificationWithin90 = _apiInt(counts['within_90_days']);
          notificationWithin60 = _apiInt(counts['within_60_days']);
          notificationWithin30 = _apiInt(counts['within_30_days']);
          await fetchNotificationLogs(notify: false);
          _backendOnline = true;
          _log(
            title: 'Maturity alert scan executed',
            detail:
                'Finance HQ triggered the 90/60/30-day engine. $dispatched '
                'Email + SMS advisory bundle${dispatched == 1 ? '' : 's'} '
                'dispatched through the NIC-SMS / SMTP gateway.',
            icon: Icons.campaign_rounded,
            color: AppColors.indigo,
          );
        }
      }
    } catch (_) {
      _backendOnline = false;
    } finally {
      notificationLastDispatchCount = dispatched;
      notificationScanBusy = false;
      notificationGatewayStatus = dispatched > 0 ? 'DISPATCHED' : 'STANDBY';
      lastNotificationScan = DateTime.now();
      notificationAutoChecked = true;
      _refreshLocalNotificationCountsIfEmpty();
      notifyListeners();
    }
    return dispatched;
  }

  /// Runs the automatic background check exactly once per signed-in session,
  /// immediately after the Finance HQ workspace mounts.
  Future<int> ensureAutomaticNotificationCheck() async {
    if (notificationAutoChecked) return 0;
    notificationAutoChecked = true;
    return runMaturityNotificationScan(silent: true);
  }

  void _refreshLocalNotificationCountsIfEmpty() {
    if (notificationWithin90 == 0 &&
        notificationWithin60 == 0 &&
        notificationWithin30 == 0) {
      _refreshLocalNotificationCounts();
    }
  }

  void _refreshLocalNotificationCounts() {
    notificationWithin90 = 0;
    notificationWithin60 = 0;
    notificationWithin30 = 0;
    for (final record in records) {
      if (record.status.isClosed) continue;
      final days = record.daysToMaturity;
      if (days < 1) continue;
      if (days <= 30) notificationWithin30 += 1;
      if (days <= 60) notificationWithin60 += 1;
      if (days <= 90) notificationWithin90 += 1;
    }
  }

  String _notificationWindowForDays(int days) {
    if (days <= 30) return '30_DAYS';
    if (days <= 60) return '60_DAYS';
    return '90_DAYS';
  }

  String _localAlertPreview(FDRRecord record, String window, int days) {
    final title = switch (window) {
      '30_DAYS' => '30-Day Critical Final Notice',
      '60_DAYS' => '60-Day Follow-Up Reminder',
      _ => '90-Day Pre-Maturity Advisory',
    };
    final action = switch (window) {
      '30_DAYS' =>
        'URGENT: Submit the Release Application or the renewed 2-year FDR immediately to avoid encashment and penalty action.',
      '60_DAYS' =>
        'Verify that the joint lien is still marked in favour of AICTE and confirm the release/renewal decision to the Regional Office.',
      _ =>
        'Please initiate the release or two-year renewal paperwork with the partner bank at least 30 days before maturity.',
    };
    final email = record.instituteId == kprId
        ? 'principal@kpr.edu.in'
        : 'principal@aicte-institute.edu.in';
    const mobile = '+91-9840012310';
    return 'EMAIL GATEWAY (SMTP)\nTo: $email\nCC: finance.hq@aicte.gov.in\n'
        'Subject: AICTE e-Kosh | $title | FDR ${record.id}\n\n'
        'Dear Principal / Nodal Officer,\n\n'
        'This is an official ${title.toLowerCase()} issued by the AICTE Finance Bureau '
        'for the Joint Fixed Deposit referenced below.\n\n'
        'Institute: ${record.instituteName}\n'
        'AICTE Permanent ID: ${record.instituteId}\n'
        'FDR Number: ${record.id}\n'
        'Bank / IFSC: ${record.bankName} / ${record.ifsc}\n'
        'Principal Amount: ${inr(record.amount)}\n'
        'Maturity Date: ${formatDate(record.maturityDate)} ($days days remaining)\n\n'
        'Required action: $action\n\n'
        'The release or renewal must be processed 100% digitally through the '
        'e-Kosh portal. A copy of this advisory has been marked to '
        'finance.hq@aicte.gov.in.\n\n'
        'This is a system-generated message. Please do not reply.\n'
        'AICTE Finance Bureau, New Delhi | Helpdesk 1800-11-2026\n\n'
        'SMS GATEWAY (NIC-SMS)\nTo: $mobile\n\n'
        'AICTE e-Kosh: FDR ${record.id} of ${record.instituteName} matures on '
        '${formatDate(record.maturityDate)} ($days days). $action '
        'Portal: https://ekosh.aicte.gov.in';
  }

  /// Seeds a local gateway ledger from the offline demo portfolio so the
  /// Finance HQ engine is populated even when MongoDB is unreachable.
  void _seedLocalNotificationLogs() {
    final now = DateTime.now();
    var sequence = 0;
    for (final record in records) {
      if (record.status.isClosed) continue;
      final days = record.daysToMaturity;
      if (days < 1 || days > 90) continue;
      final window = _notificationWindowForDays(days);
      notificationLogs.add(
        MaturityNotificationLog(
          fdrNumber: record.id,
          aicteId: record.instituteId,
          instituteName: record.instituteName,
          recipientEmail: record.instituteId == kprId
              ? 'principal@kpr.edu.in'
              : 'principal@aicte-institute.edu.in',
          recipientMobile: '+91-9840012310',
          milestoneWindow: window,
          channels: const ['EMAIL', 'SMS'],
          messagePreview: _localAlertPreview(record, window, days),
          deliveryStatus: 'DELIVERED',
          triggeredBy: 'AUTO_CRON_SCHEDULER',
          timestamp: now.subtract(Duration(minutes: 18 + sequence * 7)),
          daysToMaturity: days,
        ),
      );
      sequence += 1;
    }
    _refreshLocalNotificationCounts();
  }

  void signOut() {
    if (!_authenticated) return;
    _log(
      title: 'Session signed out',
      detail:
          '${role.personName} closed the ${role.label} dashboard session. '
          'All dashboard data remains anchored to the AICTE ledger.',
      icon: Icons.logout_rounded,
      color: AppColors.muted,
    );
    _authenticated = false;
    _signedInUserId = null;
    _currentUser = null;
    _navIndex = 0;
    notifyListeners();
  }

  /// Applies a password chosen through the OTP recovery flow. The override is
  /// kept in memory for the current portal session and is used by signIn().
  bool updatePassword(UserRole role, String newPassword) {
    final trimmed = newPassword.trim();
    if (trimmed.isEmpty) return false;
    _passwordOverrides[role] = trimmed;
    _log(
      title: 'SSO password reset',
      detail:
          '${credentialFor(role).userId} completed OTP verification and '
          'updated the AICTE SSO credential for the ${role.label} dashboard.',
      icon: Icons.password_rounded,
      color: AppColors.emeraldDark,
    );
    notifyListeners();
    return true;
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
        id: 'FDR-CAN-2016-414',
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
        id: 'FDR-CAN-2016-412',
        bankName: 'Canara Bank',
        ifsc: 'CNRB0COIMBT',
        instituteName: 'KPR Institute of Technology',
        instituteId: kprId,
        program: 'B.Tech - Mechanical Engineering',
        intake: 120,
        amount: 2500000,
        issueDate: DateTime(2016, 8, 5),
        maturityDate: DateTime(2026, 8, 4),
        status: FDRStatus.onHoldExtension,
        lastUpdated: now.subtract(const Duration(hours: 6)),
        submittedAt: DateTime(2016, 8, 8),
        releaseAppliedAt: DateTime(2026, 9, 2),
        deficiency: true,
        holdDate: DateTime(2026, 10, 2),
        holdReason:
            'Project approval timeline exceeded by 47 days. Upload a renewed 2-year FDR or obtain fresh AICTE project approval before release can be considered.',
        remarks:
            'URGENT: FDR #FDR-CAN-2016-412 has exceeded its project/approval timeline. Immediate action required: Apply for Release or Submit 2-Year Renewal.',
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
      FDRRecord(
        id: 'FDR-SBI-2024-118',
        bankName: 'State Bank of India',
        ifsc: 'SBIN0004321',
        instituteName: 'KPR Institute of Technology',
        instituteId: kprId,
        program: 'B.Tech - Information Technology',
        intake: 120,
        amount: 1500000,
        issueDate: DateTime(2024, 3, 11),
        maturityDate: DateTime(2026, 3, 10),
        status: FDRStatus.releasedENOC,
        lastUpdated: now.subtract(const Duration(hours: 20)),
        submittedAt: DateTime(2024, 3, 12),
        releaseAppliedAt: DateTime(2026, 8, 20),
        roClearedAt: DateTime(2026, 9, 14),
        releasedAt: DateTime(2026, 10, 25, 16, 40),
        releasedAmount: 1500000,
        enocNumber: 'AICTE/eNOC/2026/4102',
        remarks:
            'Released in full by AICTE Finance. Digital e-NOC issued and routed to the bank for immediate disbursement.',
      ),
      FDRRecord(
        id: 'FDR-HDFC-2024-845',
        bankName: 'HDFC Bank',
        ifsc: 'HDFC0000125',
        instituteName: 'Delhi Technological University',
        instituteId: '1-510244',
        program: 'B.Tech - Computer Engineering',
        intake: 240,
        amount: 3500000,
        issueDate: DateTime(2024, 5, 6),
        maturityDate: DateTime(2026, 5, 5),
        status: FDRStatus.partialReleaseApproved,
        lastUpdated: now.subtract(const Duration(days: 1, hours: 2)),
        submittedAt: DateTime(2024, 5, 8),
        releaseAppliedAt: DateTime(2026, 8, 2),
        roClearedAt: DateTime(2026, 9, 9),
        releasedAt: DateTime(2026, 10, 24, 12, 15),
        releasedAmount: 3150000,
        deductedPenalty: 350000,
        penalty: 350000,
        enocNumber: 'AICTE/eNOC/2026/4103',
        region: 'Northern',
        remarks:
            'Partial release approved. ₹3,50,000 penalty deducted for delayed release filing; net ₹31,50,000 authorised via e-NOC.',
      ),
      FDRRecord(
        id: 'FDR-BOB-2022-522',
        bankName: 'Bank of Baroda',
        ifsc: 'BARB0PUNEXX',
        instituteName: 'College of Engineering, Pune',
        instituteId: '1-510377',
        program: 'B.Tech - Civil Engineering',
        intake: 90,
        amount: 2500000,
        issueDate: DateTime(2022, 7, 19),
        maturityDate: DateTime(2028, 7, 18),
        status: FDRStatus.activeLienLocked,
        lastUpdated: now.subtract(const Duration(days: 6)),
        submittedAt: DateTime(2022, 7, 21),
        region: 'Western',
        remarks:
            'Joint lien locked with AICTE. Deposit remains active until the approved intake cycle completes.',
      ),
      FDRRecord(
        id: 'FDR-PNB-2018-733',
        bankName: 'Punjab National Bank',
        ifsc: 'PUNB0KOLKAT',
        instituteName: 'Jadavpur University',
        instituteId: '1-510512',
        program: 'M.Tech - Power Systems',
        intake: 36,
        amount: 1500000,
        issueDate: DateTime(2018, 2, 14),
        maturityDate: DateTime(2026, 2, 13),
        status: FDRStatus.forfeited,
        lastUpdated: now.subtract(const Duration(days: 4)),
        submittedAt: DateTime(2018, 2, 16),
        region: 'Eastern',
        remarks:
            'Forfeited and encashed to the AICTE account after repeated non-compliance with the approval timeline.',
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

    auditLog.addAll([
      AuditEntry(
        timestamp: now.subtract(const Duration(minutes: 26)),
        actor: 'Finance Admin • A. Sharma',
        fdrId: 'FDR-SBI-2024-118',
        action: 'e-NOC generated • Full release authorised',
        ipReference: '10.24.61.18',
        hashReference: '0x9F3A21C7',
      ),
      AuditEntry(
        timestamp: now.subtract(const Duration(hours: 3)),
        actor: 'Institute Admin • Dr. R. Kumar',
        fdrId: 'FDR-SBI-2026-101',
        action: 'FDR submitted for bank lien verification',
        ipReference: '10.24.14.72',
        hashReference: '0x41B87DE0',
      ),
      AuditEntry(
        timestamp: now.subtract(const Duration(days: 1, hours: 5)),
        actor: 'Regional Officer • R. Iyer',
        fdrId: 'FDR-HDFC-2016-588',
        action: 'RO clearance granted • Routed to Finance',
        ipReference: '10.24.38.9',
        hashReference: '0x7C2E5A91',
      ),
      AuditEntry(
        timestamp: now.subtract(const Duration(days: 2)),
        actor: 'Partner Bank • S. Menon',
        fdrId: 'FDR-CAN-2016-412',
        action: 'Lien re-verification flagged • Deficiency noted',
        ipReference: '10.24.52.44',
        hashReference: '0x2D9F0B63',
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

  List<FDRRecord> get releaseReady =>
      _withStatuses({FDRStatus.releasedENOC, FDRStatus.partialReleaseApproved});

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

  List<FDRRecord> get overdueRecords => records
      .where((record) => record.isOverdue && !record.status.isClosed)
      .toList();

  List<FDRRecord> get dueSoonRecords => records.where((record) {
    final days = record.daysToMaturity;
    return !record.status.isClosed && days >= 0 && days <= 30;
  }).toList();

  /// FDRs inside the automated 90-day pre-maturity advisory horizon. The
  /// Institute dashboard raises a high-priority banner for the nearest one.
  List<FDRRecord> get preMaturityRecords => instituteRecords.where((record) {
    if (record.status.isClosed) return false;
    final days = record.daysToMaturity;
    return days >= 1 && days <= 90;
  }).toList()..sort((a, b) => a.daysToMaturity.compareTo(b.daysToMaturity));

  FDRRecord? get nearestPreMaturityRecord =>
      preMaturityRecords.isEmpty ? null : preMaturityRecords.first;

  List<FDRRecord> get maturityWatchlist => records
      .where((record) => !record.status.isClosed && record.isMatured)
      .toList();

  List<FDRRecord> get releasedRecords => _withStatuses({
    FDRStatus.releasedENOC,
    FDRStatus.partialReleaseApproved,
    FDRStatus.fundsDisbursed,
  });

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
          FDRStatus.partialReleaseApproved,
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
          FDRStatus.partialReleaseApproved,
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

  // ---------------------------------------------------------------------------
  // Phase 3 executive analytics
  // ---------------------------------------------------------------------------

  List<StatusSlice> get nationalStatusBreakdown => [
    StatusSlice(
      'Active Locked',
      _withStatuses({
        FDRStatus.pendingBankVerification,
        FDRStatus.activeLienLocked,
      }).length,
      AppColors.emeraldDark,
    ),
    StatusSlice(
      'Matured Pending',
      _withStatuses({
        FDRStatus.maturedPendingRO,
        FDRStatus.roClearedPendingFinance,
      }).length,
      AppColors.gold,
    ),
    StatusSlice('On Hold / Extended', onHoldRecords.length, AppColors.orange),
    StatusSlice('Released', releasedRecords.length, AppColors.teal),
    StatusSlice('Forfeited', forfeitedRecords.length, AppColors.red),
  ];

  Map<String, double> get regionalCorpus {
    final corpus = <String, double>{
      'Southern': 0,
      'Northern': 0,
      'Western': 0,
      'Eastern': 0,
    };
    for (final record in records) {
      corpus.update(
        record.region,
        (value) => value + record.amount,
        ifAbsent: () => record.amount,
      );
    }
    return corpus;
  }

  double get maxRegionalCorpus {
    final values = regionalCorpus.values;
    if (values.isEmpty) return 0;
    return values.reduce((a, b) => a > b ? a : b);
  }

  List<FDRRecord> get issuedEnocs =>
      records.where((record) => record.hasEnoc).toList();

  List<FDRRecord> get specialPurposeEnocs => records
      .where(
        (record) =>
            record.status == FDRStatus.releasedENOC ||
            record.status == FDRStatus.partialReleaseApproved,
      )
      .toList();

  int get auditEventCount => auditLog.length;

  void logAiConsultation(String prompt) {
    final trimmed = prompt.trim();
    if (trimmed.isEmpty) return;
    _log(
      title: 'e-Kosh AI consulted',
      detail:
          'RAG assistant answered: "${trimmed.length > 90 ? '${trimmed.substring(0, 90)}…' : trimmed}"',
      icon: Icons.smart_toy_rounded,
      color: AppColors.indigo,
    );
    notifyListeners();
  }

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
    record.status = FDRStatus.partialReleaseApproved;
    record.remarks =
        'Partial release approved by AICTE Finance. Penalty of ${inr(safeDeduction)} deducted; net ${inr(record.releasedAmount!)} released for bank disbursement via e-NOC ${record.enocNumber}.';
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
        'FDR fully forfeited and encashed to the AICTE account following final review. Net refund to the institute: ₹0.';
    _log(
      title: 'FDR forfeited to AICTE',
      detail:
          '${record.id} • ${inr(record.amount)} encashed to the AICTE account. Net refund ₹0.',
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

  void renewFdr(FDRRecord record, {DateTime? newMaturity}) {
    final target =
        newMaturity ??
        DateTime(
          record.maturityDate.year + 2,
          record.maturityDate.month,
          record.maturityDate.day,
        );
    record.maturityDate = target;
    record.renewalCount += 1;
    record.renewedAt = DateTime.now();
    record.status = FDRStatus.pendingBankVerification;
    record.holdReason = null;
    record.holdDate = null;
    record.deficiency = false;
    record.lastUpdated = DateTime.now();
    record.remarks =
        'Extended / renewed FDR received from the institute. Maturity extended to ${formatDate(target)} and routed back to ${record.bankName} for fresh lien re-verification.';
    _log(
      title: 'Renewed FDR routed to bank',
      detail:
          '${record.id} extended by 2 years to ${formatDate(target)}. ${record.bankName} must re-verify the lien.',
      icon: Icons.autorenew_rounded,
      color: AppColors.emeraldDark,
    );
    notifyListeners();
  }

  void runMaturityCron() {
    maturityCronRan = true;
    maturityCronRuns += 1;
    lastCronRun = DateTime.now();
    maturityAlertDismissed = false;
    final overdue = overdueRecords.length;
    final dueSoon = dueSoonRecords.length;
    _log(
      title: 'Daily maturity cron executed',
      detail:
          'Cron scanned ${records.length} FDRs • $overdue overdue • $dueSoon due within 30 days. Multi-channel alerts dispatched to institute contacts.',
      icon: Icons.schedule_send_rounded,
      color: AppColors.orange,
    );
    notifyListeners();
  }

  void dismissMaturityAlert() {
    if (maturityAlertDismissed) return;
    maturityAlertDismissed = true;
    notifyListeners();
  }

  String _nextEnoc() => 'AICTE/eNOC/${DateTime.now().year}/${_enocSequence++}';

  void _log({
    required String title,
    required String detail,
    required IconData icon,
    required Color color,
  }) {
    final timestamp = DateTime.now();
    activities.insert(
      0,
      ActivityLog(
        title: title,
        detail: detail,
        timestamp: timestamp,
        icon: icon,
        color: color,
      ),
    );
    if (activities.length > 40) {
      activities.removeLast();
    }
    _audit(title: title, detail: detail, timestamp: timestamp);
  }

  static final RegExp _auditFdrPattern = RegExp(
    r'FDR-[A-Za-z]{2,5}-\d{4}-\d{3,6}',
  );

  void _audit({
    required String title,
    required String detail,
    required DateTime timestamp,
  }) {
    final match = _auditFdrPattern.firstMatch('$title $detail');
    final seed = (timestamp.millisecondsSinceEpoch ^ title.hashCode).abs();
    final hash =
        '0x${seed.toRadixString(16).toUpperCase().padLeft(8, '0').substring(0, 8)}';
    final ip = '10.24.${6 + role.index * 11}.${10 + seed % 190}';
    auditLog.insert(
      0,
      AuditEntry(
        timestamp: timestamp,
        actor: '${role.shortLabel} • ${role.personName}',
        fdrId: match?.group(0) ?? '—',
        action: title,
        ipReference: ip,
        hashReference: hash,
      ),
    );
    if (auditLog.length > 120) {
      auditLog.removeLast();
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
        builder: (context, _) => AnimatedSwitcher(
          duration: const Duration(milliseconds: 320),
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeInCubic,
          child: _state.isAuthenticated
              ? PortalShell(key: const ValueKey('portal'), state: _state)
              : PortalLoginPage(key: const ValueKey('login'), state: _state),
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Secure sign-in gateway
// -----------------------------------------------------------------------------

// -----------------------------------------------------------------------------
// GIGW / NIC-styled secure sign-in gateway
// -----------------------------------------------------------------------------

const Color _govSaffron = Color(0xFFFF9933);
const Color _govGreen = Color(0xFF138808);
const Color _govNavy = Color(0xFF1E3A8A);
const Color _govInk = Color(0xFF0F172A);
const Color _govGold = Color(0xFFD97706);
const Color _govSlateBg = Color(0xFFF1F5F9);
const Color _govLine = Color(0xFFCBD5E1);
const Color _govAmberBg = Color(0xFFFEF3C7);
const Color _govAmberLine = Color(0xFFFCD34D);
const Color _govAmberInk = Color(0xFF92400E);

/// Colour overrides applied by the accessibility "High Contrast" control.
/// The palette only touches the sign-in surface so the rest of the portal
/// keeps its normal design tokens.
class _GovPalette {
  const _GovPalette({required this.highContrast});

  final bool highContrast;

  Color get rightBackground => highContrast ? Colors.white : _govSlateBg;
  Color get cardBorder => highContrast ? _govInk : _govLine;
  double get cardBorderWidth => highContrast ? 2 : 1;
  Color get muted => highContrast ? const Color(0xFF334155) : AppColors.muted;
  Color get surface => highContrast ? Colors.white : const Color(0xFFF8FAFC);
}

class PortalLoginPage extends StatefulWidget {
  const PortalLoginPage({super.key, required this.state});

  final PortalState state;

  @override
  State<PortalLoginPage> createState() => _PortalLoginPageState();
}

class _PortalLoginPageState extends State<PortalLoginPage> {
  static const _captchaAlphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  static const _captchaLength = 6;

  final Random _captchaRandom = Random.secure();
  final TextEditingController _userIdController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _captchaInputController = TextEditingController();
  final FocusNode _userIdFocus = FocusNode();

  UserRole _selected = UserRole.institute;
  String _currentCaptchaCode = '';
  int _captchaSeed = 0;
  List<double> _captchaAngles = const <double>[];
  bool _obscure = true;
  bool _submitting = false;
  bool _hindi = false;
  bool _highContrast = false;
  double _fontScale = kPortalTextScale;
  String? _error;

  @override
  void initState() {
    super.initState();
    _selected = widget.state.role;
    _generateCaptcha();
  }

  @override
  void dispose() {
    _userIdController.dispose();
    _passwordController.dispose();
    _captchaInputController.dispose();
    _userIdFocus.dispose();
    super.dispose();
  }

  String _t(String english, String hindi) => _hindi ? hindi : english;

  /// Draws a fresh six-character challenge, its per-character tilt and the
  /// deterministic noise seed used by the captcha painter.
  void _generateCaptcha() {
    final buffer = StringBuffer();
    for (var i = 0; i < _captchaLength; i++) {
      buffer.write(
        _captchaAlphabet[_captchaRandom.nextInt(_captchaAlphabet.length)],
      );
    }
    _currentCaptchaCode = buffer.toString();
    _captchaSeed = _captchaRandom.nextInt(1 << 31);
    _captchaAngles = List<double>.generate(
      _captchaLength,
      (_) => (_captchaRandom.nextDouble() * 0.24) - 0.12,
    );
  }

  String _tabLabel(UserRole role) => switch (role) {
    UserRole.institute => 'Institute Login',
    UserRole.bank => 'Bank Node',
    UserRole.ro => 'AICTE RO',
    UserRole.finance => 'Finance HQ',
  };

  String _userIdLabel(UserRole role) => switch (role) {
    UserRole.institute => 'AICTE Permanent Institute ID / Official Email',
    UserRole.bank => 'Bank CBS Node / IFSC Email',
    UserRole.ro => 'AICTE Regional Office ID / Official Email',
    UserRole.finance => 'AICTE Finance Bureau HQ ID / Official Email',
  };

  void _selectRole(UserRole role) {
    if (role == _selected) return;
    setState(() {
      _selected = role;
      _error = null;
    });
  }

  void _refreshCaptcha() {
    setState(() {
      _generateCaptcha();
      _captchaInputController.clear();
      _error = null;
    });
  }

  void _adjustFont(double delta) {
    setState(() {
      _fontScale = (_fontScale + delta).clamp(1.1, 1.9).toDouble();
    });
  }

  void _resetFont() {
    setState(() => _fontScale = kPortalTextScale);
  }

  void _toggleLanguage() {
    setState(() => _hindi = !_hindi);
  }

  void _toggleContrast() {
    setState(() => _highContrast = !_highContrast);
  }

  static const _captchaError =
      'Verification Failed: Captcha does not match! Please try again.';

  void _showCaptchaError() {
    showAppToast(
      context,
      _captchaError,
      icon: Icons.error_outline_rounded,
      color: AppColors.red,
    );
  }

  Future<void> _submit() async {
    if (_submitting) return;
    FocusScope.of(context).unfocus();
    final enteredCaptcha = _captchaInputController.text.trim().toUpperCase();
    if (enteredCaptcha.isEmpty ||
        enteredCaptcha != _currentCaptchaCode.toUpperCase()) {
      setState(() {
        _error = _captchaError;
        _generateCaptcha();
        _captchaInputController.clear();
      });
      _showCaptchaError();
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    await Future<void>.delayed(const Duration(milliseconds: 520));
    if (!mounted) return;
    final account = credentialFor(_selected);
    final remote = await widget.state.signInWithBackend(
      _selected,
      _userIdController.text,
      _passwordController.text,
    );
    if (!mounted) return;
    final ok = switch (remote) {
      BackendAuthResult.success => true,
      BackendAuthResult.invalidCredentials => false,
      BackendAuthResult.unavailable => widget.state.signIn(
        _selected,
        _userIdController.text,
        _passwordController.text,
      ),
    };
    if (!mounted) return;
    setState(() {
      _submitting = false;
      if (!ok) {
        _error =
            'Invalid credentials for ${_selected.label}. Use the demo '
            'credentials — user ID ${account.userId} or '
            '${account.shortId}.';
        _passwordController.clear();
        _generateCaptcha();
        _captchaInputController.clear();
      }
    });
  }

  Future<void> _openPasswordRecovery() async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => _PasswordRecoveryDialog(
        state: widget.state,
        initialIdentifier: _userIdController.text,
        initialRole: _selected,
        messengerContext: context,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = _GovPalette(highContrast: _highContrast);
    return MediaQuery(
      data: MediaQuery.of(
        context,
      ).copyWith(textScaler: TextScaler.linear(_fontScale)),
      child: Scaffold(
        backgroundColor: palette.rightBackground,
        body: LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            return Column(
              children: [
                _GovAccessibilityStrip(
                  hindi: _hindi,
                  highContrast: _highContrast,
                  onSkip: _userIdFocus.requestFocus,
                  onDecreaseFont: () => _adjustFont(-0.1),
                  onResetFont: _resetFont,
                  onIncreaseFont: () => _adjustFont(0.1),
                  onToggleContrast: _toggleContrast,
                  onToggleLanguage: _toggleLanguage,
                ),
                _GovMasthead(showBadges: width >= 1150),
                const _GovTicker(),
                Expanded(child: _buildCenteredCard(palette)),
                _GovFooter(compact: width < 760),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildCenteredCard(_GovPalette palette) {
    return Container(
      color: palette.rightBackground,
      child: LayoutBuilder(
        builder: (context, constraints) => SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 24,
                ),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 500),
                  child: _buildSsoCard(palette),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSsoCard(_GovPalette palette) {
    final account = credentialFor(_selected);
    return Container(
      key: const Key('login-card'),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: palette.cardBorder,
          width: palette.cardBorderWidth,
        ),
        boxShadow: [
          BoxShadow(
            color: _govInk.withValues(alpha: 0.12),
            blurRadius: 32,
            offset: const Offset(0, 16),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            height: 4,
            child: Column(
              children: const [
                SizedBox(height: 2, child: ColoredBox(color: _govNavy)),
                Expanded(
                  child: Row(
                    children: [
                      Expanded(child: ColoredBox(color: _govSaffron)),
                      Expanded(child: ColoredBox(color: Colors.white)),
                      Expanded(child: ColoredBox(color: _govGreen)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 20, 22, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [_govNavy, _govInk],
                        ),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(
                        Icons.lock_rounded,
                        color: _govGold,
                        size: 21,
                      ),
                    ),
                    const SizedBox(width: 11),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _t(
                              'Single Sign-On (SSO) Stakeholder Authentication',
                              'सिंगल साइन-ऑन (SSO) हितधारक प्रमाणीकरण',
                            ),
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w900,
                              letterSpacing: -0.2,
                              height: 1.16,
                              color: _govInk,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            _t(
                              'NIC Parichay-compatible • Role-scoped access',
                              'NIC परिचय-संगत • भूमिका-आधारित पहुँच',
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 8.4,
                              height: 1.3,
                              fontWeight: FontWeight.w600,
                              color: palette.muted,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    for (var i = 0; i < UserRole.values.length; i++) ...[
                      if (i > 0) const SizedBox(width: 4),
                      Expanded(
                        child: _GovRoleTab(
                          key: Key('login-tab-${UserRole.values[i].name}'),
                          label: _tabLabel(UserRole.values[i]),
                          selected: UserRole.values[i] == _selected,
                          onTap: () => _selectRole(UserRole.values[i]),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 7),
                Text(
                  '${_selected.label} • ${_selected.org}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 8.3,
                    fontWeight: FontWeight.w600,
                    color: palette.muted,
                  ),
                ),
                const SizedBox(height: 13),
                _GovFieldLabel(
                  text: _userIdLabel(_selected),
                  color: palette.muted,
                ),
                const SizedBox(height: 5),
                TextFormField(
                  key: const Key('login-user-id'),
                  controller: _userIdController,
                  focusNode: _userIdFocus,
                  autofillHints: const [AutofillHints.username],
                  textInputAction: TextInputAction.next,
                  onFieldSubmitted: (_) => _submit(),
                  style: const TextStyle(
                    fontSize: 10.8,
                    fontWeight: FontWeight.w600,
                    color: _govInk,
                  ),
                  decoration: InputDecoration(
                    hintText: account.userId,
                    hintStyle: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w400,
                      color: palette.muted.withValues(alpha: 0.8),
                    ),
                    prefixIcon: Icon(_selected.icon, size: 17, color: _govNavy),
                    prefixIconConstraints: const BoxConstraints(
                      minWidth: 38,
                      minHeight: 38,
                    ),
                    isDense: true,
                    filled: true,
                    fillColor: Colors.white,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 13,
                    ),
                    border: _govFieldBorder(_govLine),
                    enabledBorder: _govFieldBorder(_govLine),
                    focusedBorder: _govFieldBorder(_govNavy, width: 1.4),
                  ),
                ),
                const SizedBox(height: 11),
                _GovFieldLabel(
                  text: _t('Password', 'पासवर्ड'),
                  color: palette.muted,
                ),
                const SizedBox(height: 5),
                TextFormField(
                  key: const Key('login-password'),
                  controller: _passwordController,
                  obscureText: _obscure,
                  autofillHints: const [AutofillHints.password],
                  textInputAction: TextInputAction.done,
                  onFieldSubmitted: (_) => _submit(),
                  style: const TextStyle(
                    fontSize: 10.8,
                    fontWeight: FontWeight.w600,
                    color: _govInk,
                  ),
                  decoration: InputDecoration(
                    hintText: _t('Enter SSO password', 'SSO पासवर्ड दर्ज करें'),
                    hintStyle: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w400,
                      color: palette.muted.withValues(alpha: 0.8),
                    ),
                    prefixIcon: const Icon(
                      Icons.lock_outline_rounded,
                      size: 17,
                      color: _govNavy,
                    ),
                    prefixIconConstraints: const BoxConstraints(
                      minWidth: 38,
                      minHeight: 38,
                    ),
                    suffixIcon: IconButton(
                      tooltip: _obscure ? 'Show password' : 'Hide password',
                      onPressed: () => setState(() => _obscure = !_obscure),
                      icon: Icon(
                        _obscure
                            ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined,
                        size: 17,
                        color: palette.muted,
                      ),
                    ),
                    isDense: true,
                    filled: true,
                    fillColor: Colors.white,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 13,
                    ),
                    border: _govFieldBorder(_govLine),
                    enabledBorder: _govFieldBorder(_govLine),
                    focusedBorder: _govFieldBorder(_govNavy, width: 1.4),
                  ),
                ),
                const SizedBox(height: 2),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    key: const Key('forgot-password'),
                    onPressed: _openPasswordRecovery,
                    style: TextButton.styleFrom(
                      foregroundColor: _govNavy,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 2,
                        vertical: 0,
                      ),
                      minimumSize: const Size(0, 22),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      textStyle: const TextStyle(
                        fontSize: 8.6,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    child: const Text('Forgot Password?'),
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 6),
                  _GovErrorBanner(message: _error!),
                ],
                const SizedBox(height: 6),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 5,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _GovFieldLabel(
                            text: _t('Security Captcha', 'सुरक्षा कैप्चा'),
                            color: palette.muted,
                          ),
                          const SizedBox(height: 5),
                          Container(
                            height: 48,
                            clipBehavior: Clip.antiAlias,
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [Color(0xFFEFF6FF), Color(0xFFDBEAFE)],
                              ),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                color: palette.cardBorder,
                                width: palette.cardBorderWidth,
                              ),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Stack(
                                    children: [
                                      Positioned.fill(
                                        child: CustomPaint(
                                          painter: _CaptchaNoisePainter(
                                            seed: _captchaSeed,
                                            dotColor: _govNavy,
                                            lineColor: _govNavy,
                                          ),
                                        ),
                                      ),
                                      Positioned.fill(
                                        child: Padding(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 9,
                                          ),
                                          child: FittedBox(
                                            fit: BoxFit.scaleDown,
                                            alignment: Alignment.centerLeft,
                                            child: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                for (
                                                  var i = 0;
                                                  i < _captchaLength;
                                                  i++
                                                )
                                                  Transform.rotate(
                                                    angle:
                                                        _captchaAngles.length ==
                                                            _captchaLength
                                                        ? _captchaAngles[i]
                                                        : 0,
                                                    child: Text(
                                                      _currentCaptchaCode[i],
                                                      key: Key(
                                                        'captcha-char-$i',
                                                      ),
                                                      textScaler:
                                                          TextScaler.noScaling,
                                                      style: const TextStyle(
                                                        fontSize: 20,
                                                        fontWeight:
                                                            FontWeight.w900,
                                                        letterSpacing: 3,
                                                        color: Color(
                                                          0xFF1E3A8A,
                                                        ),
                                                        fontFamily: 'monospace',
                                                      ),
                                                    ),
                                                  ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Padding(
                                  padding: const EdgeInsets.only(right: 2),
                                  child: IconButton(
                                    key: const Key('captcha-refresh'),
                                    tooltip: 'Refresh captcha',
                                    onPressed: _refreshCaptcha,
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints.tightFor(
                                      width: 32,
                                      height: 32,
                                    ),
                                    icon: const Icon(
                                      Icons.refresh,
                                      size: 20,
                                      color: Color(0xFF1E3A8A),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      flex: 6,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _GovFieldLabel(
                            text: _t('Human Verification', 'मानव सत्यापन'),
                            color: palette.muted,
                          ),
                          const SizedBox(height: 5),
                          TextFormField(
                            key: const Key('login-captcha'),
                            controller: _captchaInputController,
                            maxLength: 6,
                            textCapitalization: TextCapitalization.characters,
                            textInputAction: TextInputAction.done,
                            onFieldSubmitted: (_) => _submit(),
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 1.6,
                              color: _govInk,
                            ),
                            decoration: InputDecoration(
                              counterText: '',
                              hintText: 'Enter Captcha',
                              hintStyle: TextStyle(
                                fontSize: 9.4,
                                fontWeight: FontWeight.w400,
                                color: palette.muted.withValues(alpha: 0.8),
                              ),
                              prefixIcon: const Icon(
                                Icons.verified_user_outlined,
                                size: 16,
                                color: _govNavy,
                              ),
                              prefixIconConstraints: const BoxConstraints(
                                minWidth: 34,
                                minHeight: 38,
                              ),
                              isDense: true,
                              filled: true,
                              fillColor: Colors.white,
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 13,
                              ),
                              border: _govFieldBorder(_govLine),
                              enabledBorder: _govFieldBorder(_govLine),
                              focusedBorder: _govFieldBorder(
                                _govNavy,
                                width: 1.4,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 5),
                Text(
                  _t(
                    'Case-insensitive human verification • refresh for a new code',
                    'केस-असंवेदनशील मानव सत्यापन • नया कोड प्राप्त करें',
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 7.6,
                    fontWeight: FontWeight.w500,
                    color: palette.muted,
                  ),
                ),
                const SizedBox(height: 14),
                SizedBox(
                  height: 46,
                  child: FilledButton(
                    key: const Key('login-submit'),
                    onPressed: _submitting ? null : _submit,
                    style: FilledButton.styleFrom(
                      backgroundColor: _govNavy,
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: _govNavy.withValues(alpha: 0.6),
                      disabledForegroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(6),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                    ),
                    child: _submitting
                        ? const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              ),
                              SizedBox(width: 8),
                              Flexible(
                                child: Text(
                                  'AUTHENTICATING…',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 0.6,
                                  ),
                                ),
                              ),
                            ],
                          )
                        : FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              _t(
                                'AUTHENTICATE & PROCEED TO PORTAL →',
                                'प्रमाणित करें और पोर्टल पर जाएँ →',
                              ),
                              maxLines: 1,
                              softWrap: false,
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Icon(
                      Icons.verified_user_outlined,
                      size: 12,
                      color: AppColors.emeraldDark,
                    ),
                    const SizedBox(width: 5),
                    Expanded(
                      child: Text(
                        _t(
                          'Protected by TLS 1.3 • AICTE SSO • RBAC enforced',
                          'TLS 1.3 द्वारा सुरक्षित • AICTE SSO • RBAC लागू',
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 7.7,
                          fontWeight: FontWeight.w600,
                          color: palette.muted,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  OutlineInputBorder _govFieldBorder(Color color, {double width = 1}) {
    return OutlineInputBorder(
      borderRadius: BorderRadius.circular(6),
      borderSide: BorderSide(color: color, width: width),
    );
  }
}

/// Government-styled 3-step SSO password recovery dialog: request OTP, verify
/// OTP, then set a new password. The dialog owns its text controllers so they
/// are disposed only after the route is fully removed from the tree.
class _PasswordRecoveryDialog extends StatefulWidget {
  const _PasswordRecoveryDialog({
    required this.state,
    required this.initialIdentifier,
    required this.initialRole,
    required this.messengerContext,
  });

  final PortalState state;
  final String initialIdentifier;
  final UserRole initialRole;
  final BuildContext messengerContext;

  @override
  State<_PasswordRecoveryDialog> createState() =>
      _PasswordRecoveryDialogState();
}

class _PasswordRecoveryDialogState extends State<_PasswordRecoveryDialog> {
  late final TextEditingController _identifierController =
      TextEditingController(text: widget.initialIdentifier);
  final TextEditingController _otpController = TextEditingController();
  final TextEditingController _newPasswordController = TextEditingController();
  final TextEditingController _confirmPasswordController =
      TextEditingController();

  int _step = 0;
  bool _busy = false;
  String? _error;
  String _sentTo = '';
  late UserRole _targetRole = widget.initialRole;

  @override
  void dispose() {
    _identifierController.dispose();
    _otpController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _sendOtp(StateSetter setDialogState) async {
    final identifier = _identifierController.text.trim();
    if (identifier.isEmpty) {
      setDialogState(() {
        _error = 'Enter your registered Official Email, AICTE ID or IFSC Code.';
      });
      return;
    }
    setDialogState(() {
      _busy = true;
      _error = null;
    });
    await Future<void>.delayed(const Duration(milliseconds: 420));
    if (!mounted) return;
    _targetRole = widget.initialRole;
    for (final role in UserRole.values) {
      final account = credentialFor(role);
      final needle = identifier.toLowerCase();
      if (needle == account.userId.toLowerCase() ||
          needle == account.shortId.toLowerCase()) {
        _targetRole = role;
        break;
      }
    }
    setDialogState(() {
      _busy = false;
      _sentTo = identifier;
      _step = 1;
    });
  }

  void _verifyOtp(StateSetter setDialogState) {
    if (_otpController.text.trim() != _demoOtp) {
      setDialogState(() {
        _error = 'Invalid OTP. Enter the 6-digit demo OTP $_demoOtp and retry.';
      });
      return;
    }
    setDialogState(() {
      _error = null;
      _step = 2;
    });
  }

  Future<void> _updatePassword() async {
    if (_busy) return;
    final password = _newPasswordController.text;
    if (password.trim().length < 6) {
      setState(() {
        _error = 'New password must be at least 6 characters long.';
      });
      return;
    }
    if (password != _confirmPasswordController.text) {
      setState(() {
        _error = 'New password and confirmation do not match.';
      });
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });
    final result = await widget.state.resetPasswordWithBackend(
      _targetRole,
      _sentTo,
      password,
    );
    if (!mounted) return;
    if (result == BackendAuthResult.invalidCredentials) {
      setState(() {
        _busy = false;
        _error =
            'No matching AICTE SSO account was found for the selected role.';
      });
      return;
    }

    // Persisted in MongoDB when the API is reachable; the local override keeps
    // the offline demo session usable either way.
    widget.state.updatePassword(_targetRole, password);
    if (!mounted) return;
    final toastContext = widget.messengerContext;
    Navigator.of(context).pop();
    if (toastContext.mounted) {
      showAppToast(
        toastContext,
        'Password updated successfully! Please sign in with your new '
        'credentials.',
        icon: Icons.check_circle_rounded,
        color: AppColors.emeraldDark,
      );
    }
  }

  Widget _stepChip(int index, String label) {
    final done = _step > index;
    final active = _step == index;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: done
            ? AppColors.emeraldDark
            : active
            ? _govNavy
            : const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: done || active ? Colors.transparent : _govLine,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            done ? Icons.check_rounded : Icons.circle,
            size: 9,
            color: done || active ? Colors.white : AppColors.muted,
          ),
          const SizedBox(width: 4),
          Text(
            '${index + 1}. $label',
            maxLines: 1,
            style: TextStyle(
              fontSize: 7.6,
              fontWeight: FontWeight.w800,
              color: done || active ? Colors.white : AppColors.muted,
            ),
          ),
        ],
      ),
    );
  }

  InputDecoration _fieldDecoration(String hint) {
    return InputDecoration(
      hintText: hint,
      hintMaxLines: 1,
      hintStyle: TextStyle(
        fontSize: 9.5,
        color: AppColors.muted.withValues(alpha: 0.85),
      ),
      isDense: true,
      filled: true,
      fillColor: const Color(0xFFF8FAFC),
      contentPadding: const EdgeInsets.symmetric(horizontal: 11, vertical: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(6),
        borderSide: const BorderSide(color: _govLine),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(6),
        borderSide: const BorderSide(color: _govLine),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(6),
        borderSide: const BorderSide(color: _govNavy, width: 1.4),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return StatefulBuilder(
      builder: (context, setDialogState) {
        return AlertDialog(
          title: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: _govNavy,
                  borderRadius: BorderRadius.circular(7),
                ),
                child: const Icon(
                  Icons.lock_reset_rounded,
                  color: _govGold,
                  size: 18,
                ),
              ),
              const SizedBox(width: 9),
              const Expanded(
                child: Text(
                  'Official SSO Password Recovery — OTP Verification',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    height: 1.25,
                  ),
                ),
              ),
            ],
          ),
          content: SizedBox(
            width: 430,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Wrap(
                    spacing: 5,
                    runSpacing: 5,
                    children: [
                      _stepChip(0, 'Request'),
                      _stepChip(1, 'Verify'),
                      _stepChip(2, 'Reset'),
                    ],
                  ),
                  const SizedBox(height: 13),
                  if (_step == 0) ...[
                    const Text(
                      'Enter the Official Email, AICTE ID or IFSC Code '
                      'registered with your stakeholder account.',
                      style: TextStyle(
                        fontSize: 9,
                        height: 1.45,
                        color: AppColors.muted,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      key: const Key('forgot-identifier'),
                      controller: _identifierController,
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) => _sendOtp(setDialogState),
                      style: const TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w600,
                      ),
                      decoration: _fieldDecoration(
                        'Official Email / AICTE ID / IFSC Code',
                      ),
                    ),
                  ],
                  if (_step == 1) ...[
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: const Color(0xFFECFDF5),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: const Color(0xFF6EE7B7)),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(
                            Icons.mark_email_read_rounded,
                            size: 16,
                            color: AppColors.emeraldDark,
                          ),
                          const SizedBox(width: 7),
                          Expanded(
                            child: Text(
                              'A 6-digit OTP has been sent to your registered '
                              'official email/mobile (Demo OTP: '
                              '$_demoOtp).${_sentTo.isEmpty ? '' : '\nSent to: $_sentTo'}',
                              style: const TextStyle(
                                fontSize: 8.8,
                                height: 1.45,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF065F46),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      key: const Key('forgot-otp'),
                      controller: _otpController,
                      keyboardType: TextInputType.number,
                      maxLength: 6,
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) => _verifyOtp(setDialogState),
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 4,
                      ),
                      decoration: _fieldDecoration(
                        'Enter 6-digit OTP',
                      ).copyWith(counterText: ''),
                    ),
                    const SizedBox(height: 5),
                    const Text(
                      'Demo OTP: $_demoOtp',
                      style: TextStyle(
                        fontSize: 8,
                        fontWeight: FontWeight.w700,
                        color: _govAmberInk,
                      ),
                    ),
                  ],
                  if (_step == 2) ...[
                    TextField(
                      key: const Key('forgot-new-password'),
                      controller: _newPasswordController,
                      obscureText: true,
                      style: const TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w600,
                      ),
                      decoration: _fieldDecoration('New Password'),
                    ),
                    const SizedBox(height: 9),
                    TextField(
                      key: const Key('forgot-confirm-password'),
                      controller: _confirmPasswordController,
                      obscureText: true,
                      textInputAction: TextInputAction.done,
                      onSubmitted: _busy ? null : (_) => _updatePassword(),
                      style: const TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w600,
                      ),
                      decoration: _fieldDecoration('Confirm New Password'),
                    ),
                    const SizedBox(height: 5),
                    const Text(
                      'Minimum 6 characters. The password is updated against '
                      'the AICTE SSO database.',
                      style: TextStyle(
                        fontSize: 8,
                        height: 1.4,
                        color: AppColors.muted,
                      ),
                    ),
                  ],
                  if (_error != null) ...[
                    const SizedBox(height: 9),
                    Text(
                      _error!,
                      style: const TextStyle(
                        fontSize: 8.8,
                        height: 1.4,
                        fontWeight: FontWeight.w700,
                        color: AppColors.red,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: _busy ? null : () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            if (_step == 0)
              FilledButton(
                key: const Key('forgot-send-otp'),
                onPressed: _busy ? null : () => _sendOtp(setDialogState),
                child: _busy
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text('Send Verification OTP'),
              ),
            if (_step == 1)
              FilledButton(
                key: const Key('forgot-verify-otp'),
                onPressed: () => _verifyOtp(setDialogState),
                child: const Text('Verify OTP'),
              ),
            if (_step == 2)
              FilledButton(
                key: const Key('forgot-update-password'),
                onPressed: _busy ? null : _updatePassword,
                child: _busy
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text('Update Password'),
              ),
          ],
        );
      },
    );
  }
}

/// Paints the captcha security texture: deterministic speckles plus two subtle
/// crossing lines rendered behind the challenge characters.
class _CaptchaNoisePainter extends CustomPainter {
  const _CaptchaNoisePainter({
    required this.seed,
    required this.dotColor,
    required this.lineColor,
  });

  final int seed;
  final Color dotColor;
  final Color lineColor;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final random = Random(seed);

    final dotPaint = Paint()..color = dotColor.withValues(alpha: 0.22);
    for (var i = 0; i < 34; i++) {
      canvas.drawCircle(
        Offset(
          random.nextDouble() * size.width,
          random.nextDouble() * size.height,
        ),
        0.6 + random.nextDouble() * 1.4,
        dotPaint,
      );
    }

    final linePaint = Paint()
      ..color = lineColor.withValues(alpha: 0.18)
      ..strokeWidth = 1
      ..strokeCap = StrokeCap.round;

    final firstStart = Offset(
      0,
      size.height * (0.25 + random.nextDouble() * 0.5),
    );
    final firstEnd = Offset(
      size.width,
      size.height * (0.25 + random.nextDouble() * 0.5),
    );
    final secondStart = Offset(
      size.width * (0.1 + random.nextDouble() * 0.2),
      size.height,
    );
    final secondEnd = Offset(size.width * (0.7 + random.nextDouble() * 0.2), 0);
    canvas.drawLine(firstStart, firstEnd, linePaint);
    canvas.drawLine(secondStart, secondEnd, linePaint);
  }

  @override
  bool shouldRepaint(_CaptchaNoisePainter oldDelegate) =>
      oldDelegate.seed != seed ||
      oldDelegate.dotColor != dotColor ||
      oldDelegate.lineColor != lineColor;
}

class _GovFieldLabel extends StatelessWidget {
  const _GovFieldLabel({required this.text, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontSize: 8.4,
        fontWeight: FontWeight.w800,
        letterSpacing: 0.25,
        height: 1.2,
        color: color,
      ),
    );
  }
}

class _GovRoleTab extends StatelessWidget {
  const _GovRoleTab({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(5),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        height: 38,
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 4),
        decoration: BoxDecoration(
          color: selected ? _govNavy : Colors.white,
          borderRadius: BorderRadius.circular(5),
          border: Border.all(
            color: selected ? _govNavy : _govLine,
            width: selected ? 1.4 : 1,
          ),
        ),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            label,
            maxLines: 1,
            softWrap: false,
            style: TextStyle(
              fontSize: 8.8,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.15,
              color: selected ? Colors.white : _govInk,
            ),
          ),
        ),
      ),
    );
  }
}

class _GovErrorBanner extends StatelessWidget {
  const _GovErrorBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      liveRegion: true,
      label: message,
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0xFFFEF2F2),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: const Color(0xFFFCA5A5)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(
              Icons.error_outline_rounded,
              size: 15,
              color: AppColors.red,
            ),
            const SizedBox(width: 7),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(
                  fontSize: 8.6,
                  height: 1.4,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF991B1B),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GovAccessibilityStrip extends StatelessWidget {
  const _GovAccessibilityStrip({
    required this.hindi,
    required this.highContrast,
    required this.onSkip,
    required this.onDecreaseFont,
    required this.onResetFont,
    required this.onIncreaseFont,
    required this.onToggleContrast,
    required this.onToggleLanguage,
    this.onScreenReaderAccess,
    this.showContrast = true,
  });

  final bool hindi;
  final bool highContrast;
  final VoidCallback onSkip;
  final VoidCallback onDecreaseFont;
  final VoidCallback onResetFont;
  final VoidCallback onIncreaseFont;
  final VoidCallback onToggleContrast;
  final VoidCallback onToggleLanguage;
  final VoidCallback? onScreenReaderAccess;
  final bool showContrast;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final showSkip = width >= 1180;
        final showScreenReader = width >= 900;
        final showContrastLabel = width >= 760;
        final showLanguageLabel = width >= 1050;
        final showFullBanner = width >= 760;
        return Container(
          height: 32,
          color: _govInk,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Row(
            children: [
              SizedBox(
                width: 26,
                height: 10,
                child: Row(
                  children: const [
                    Expanded(child: ColoredBox(color: _govSaffron)),
                    Expanded(child: ColoredBox(color: Colors.white)),
                    Expanded(child: ColoredBox(color: _govGreen)),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    showFullBanner
                        ? 'भारत सरकार | GOVERNMENT OF INDIA — MINISTRY OF EDUCATION'
                        : 'भारत सरकार | GOVERNMENT OF INDIA',
                    maxLines: 1,
                    softWrap: false,
                    style: const TextStyle(
                      fontSize: 8.2,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.15,
                      color: Color(0xFFE2E8F0),
                    ),
                  ),
                ),
              ),
              if (showSkip)
                _GovStripAction(
                  key: const Key('skip-content'),
                  label: 'Skip to Main Content',
                  tooltip: 'Skip to main content',
                  onTap: onSkip,
                ),
              if (showScreenReader)
                _GovStripAction(
                  key: const Key('screen-reader-access'),
                  label: width >= 1250
                      ? 'Screen Reader Access'
                      : 'Screen Reader',
                  icon: Icons.accessibility_new_rounded,
                  tooltip: 'Screen Reader Access',
                  onTap:
                      onScreenReaderAccess ??
                      () {
                        showAppToast(
                          context,
                          'Screen Reader Access: GIGW 3.0 landmark navigation and '
                          'ARIA labels are enabled throughout the portal.',
                          icon: Icons.accessibility_new_rounded,
                          color: AppColors.navy,
                        );
                      },
                ),
              _GovStripAction(
                key: const Key('font-decrease'),
                label: 'A-',
                tooltip: 'Decrease font size',
                onTap: onDecreaseFont,
              ),
              _GovStripAction(
                key: const Key('font-reset'),
                label: 'A',
                tooltip: 'Reset font size',
                onTap: onResetFont,
              ),
              _GovStripAction(
                key: const Key('font-increase'),
                label: 'A+',
                tooltip: 'Increase font size',
                onTap: onIncreaseFont,
              ),
              if (showContrast)
                _GovStripAction(
                  key: const Key('contrast-toggle'),
                  label: showContrastLabel ? 'High Contrast' : '',
                  icon: highContrast
                      ? Icons.contrast_rounded
                      : Icons.brightness_6_outlined,
                  tooltip: 'High Contrast',
                  onTap: onToggleContrast,
                ),
              _GovStripAction(
                key: const Key('language-toggle'),
                label: showLanguageLabel
                    ? hindi
                          ? 'हिन्दी / English'
                          : 'English / हिन्दी'
                    : 'EN',
                icon: Icons.translate_rounded,
                tooltip: 'English / हिन्दी',
                onTap: onToggleLanguage,
              ),
            ],
          ),
        );
      },
    );
  }
}

class _GovStripAction extends StatelessWidget {
  const _GovStripAction({
    super.key,
    required this.label,
    required this.onTap,
    required this.tooltip,
    this.icon,
  });

  final String label;
  final VoidCallback onTap;
  final String tooltip;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Semantics(
        button: true,
        label: tooltip,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(3),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 5),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 11, color: const Color(0xFFCBD5E1)),
                  if (label.isNotEmpty) const SizedBox(width: 4),
                ],
                if (label.isNotEmpty)
                  Text(
                    label,
                    maxLines: 1,
                    softWrap: false,
                    style: const TextStyle(
                      fontSize: 8,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFFE2E8F0),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _GovMasthead extends StatelessWidget {
  const _GovMasthead({required this.showBadges});

  final bool showBadges;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 76,
      padding: const EdgeInsets.symmetric(horizontal: 18),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: _govGold, width: 3)),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [_govNavy, Color(0xFF132A66)],
              ),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: _govGold.withValues(alpha: 0.6)),
            ),
            child: const Icon(
              Icons.account_balance_rounded,
              color: _govGold,
              size: 24,
            ),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'ALL INDIA COUNCIL FOR TECHNICAL EDUCATION (AICTE)',
                    maxLines: 1,
                    softWrap: false,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.15,
                      color: _govInk,
                    ),
                  ),
                ),
                const SizedBox(height: 3),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'e-Kosh: National Security Deposit & Joint FDR Lifecycle Management System',
                    maxLines: 1,
                    softWrap: false,
                    style: TextStyle(
                      fontSize: 9.8,
                      fontWeight: FontWeight.w600,
                      color: AppColors.muted,
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (showBadges) ...[
            const SizedBox(width: 14),
            SizedBox(
              width: 228,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: const [
                  _GovBadge(
                    icon: Icons.hub_rounded,
                    label: 'G2G / G2B Integrated',
                  ),
                  SizedBox(height: 3),
                  _GovBadge(
                    icon: Icons.eco_rounded,
                    label: 'e-Governance Initiative',
                  ),
                  SizedBox(height: 3),
                  _GovBadge(
                    icon: Icons.verified_rounded,
                    label: 'APH 2024-27 Compliant',
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _GovBadge extends StatelessWidget {
  const _GovBadge({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 20,
      width: 228,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _govLine),
      ),
      child: Row(
        children: [
          Icon(icon, size: 10, color: _govNavy),
          const SizedBox(width: 4),
          Expanded(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                label,
                maxLines: 1,
                softWrap: false,
                style: const TextStyle(
                  fontSize: 7.1,
                  fontWeight: FontWeight.w700,
                  color: _govInk,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _GovTicker extends StatelessWidget {
  const _GovTicker({this.hindi = false});

  final bool hindi;

  @override
  Widget build(BuildContext context) {
    final message = hindi
        ? '📢 अनिवार्य परिपत्र: AICTE वित्त ब्यूरो के निर्देशानुसार सभी संयुक्त FDR '
              'जमा, बैंक लियन सत्यापन और परिपक्वता-पश्चात e-NOC रिलीज़ 100% डिजिटल '
              'रूप से e-Kosh पोर्टल पर ही संसाधित किए जाएँ। 90/60/30 दिन की '
              'स्वचालित ईमेल व SMS चेतावनी सक्रिय है।'
        : '📢 Mandatory Advisory: As per AICTE Finance Bureau guidelines, all '
              'Joint FDR submissions, Bank Lien markings, and post-maturity '
              'e-NOC releases must be processed 100% digitally via the e-Kosh '
              'portal. Automated 90/60/30-day Pre-Maturity Email & SMS alerts and '
              'QR-verified e-NOC settlement are now live.';
    return Container(
      height: 34,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: const BoxDecoration(
        color: _govAmberBg,
        border: Border(bottom: BorderSide(color: _govAmberLine)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
            decoration: BoxDecoration(
              color: AppColors.red,
              borderRadius: BorderRadius.circular(3),
            ),
            child: Text(
              hindi ? 'नवीनतम परिपत्र' : 'LATEST CIRCULAR',
              maxLines: 1,
              softWrap: false,
              style: const TextStyle(
                fontSize: 7.2,
                fontWeight: FontWeight.w900,
                letterSpacing: 0.5,
                color: Colors.white,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w600,
                color: _govAmberInk,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _GovFooter extends StatelessWidget {
  const _GovFooter({required this.compact});

  final bool compact;

  static const _copyright =
      '© 2026 All India Council for Technical Education (AICTE), Ministry of '
      'Education, Govt. of India | NIC-SMS & SMTP Gateway Integrated | '
      'SHA-256 Audited';
  static const _credits =
      'GIGW 3.0 Compliant | Helpdesk: 1800-11-2026 | New Delhi';

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 40,
      color: _govInk,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: compact
          ? Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    _copyright,
                    maxLines: 1,
                    softWrap: false,
                    style: const TextStyle(
                      fontSize: 7.4,
                      fontWeight: FontWeight.w500,
                      color: Color(0xFFCBD5E1),
                    ),
                  ),
                ),
                const SizedBox(height: 2),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    _credits,
                    maxLines: 1,
                    softWrap: false,
                    style: const TextStyle(
                      fontSize: 7.4,
                      fontWeight: FontWeight.w500,
                      color: Color(0xFF94A3B8),
                    ),
                  ),
                ),
              ],
            )
          : Row(
              children: [
                Expanded(
                  child: Text(
                    _copyright,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 7.8,
                      fontWeight: FontWeight.w500,
                      color: Color(0xFFCBD5E1),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Text(
                    _credits,
                    textAlign: TextAlign.right,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 7.8,
                      fontWeight: FontWeight.w500,
                      color: Color(0xFF94A3B8),
                    ),
                  ),
                ),
              ],
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

class PortalShell extends StatefulWidget {
  const PortalShell({super.key, required this.state});

  final PortalState state;

  @override
  State<PortalShell> createState() => _PortalShellState();
}

class _PortalShellState extends State<PortalShell> {
  double _fontScale = kPortalTextScale;
  bool _hindi = false;
  final GlobalKey _mainContentKey = GlobalKey();

  PortalState get state => widget.state;

  void _adjustFont(double delta) {
    setState(() {
      _fontScale = (_fontScale + delta).clamp(1.1, 1.9).toDouble();
    });
  }

  void _resetFont() {
    setState(() => _fontScale = kPortalTextScale);
  }

  void _toggleLanguage() {
    setState(() => _hindi = !_hindi);
    showAppToast(
      context,
      _hindi
          ? 'भाषा हिन्दी में बदली गई। सरकारी परिपत्र और सहायता पाठ द्विभाषी हैं।'
          : 'Language switched to English. Official circulars retain bilingual labels.',
      icon: Icons.translate_rounded,
      color: AppColors.navy,
    );
  }

  void _skipToMainContent() {
    final contentContext = _mainContentKey.currentContext;
    if (contentContext != null) {
      Scrollable.ensureVisible(
        contentContext,
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOut,
        alignment: 0,
      );
    }
    showAppToast(
      context,
      'Skipped to the main workspace content.',
      icon: Icons.keyboard_tab_rounded,
      color: AppColors.navy,
    );
  }

  void _showScreenReaderAccess() {
    showDialog<void>(
      context: context,
      barrierColor: AppColors.navyInk.withValues(alpha: 0.46),
      builder: (dialogContext) => PortalDialogFrame(
        title: 'Screen Reader & Accessibility Access',
        icon: '♿',
        eyebrow: 'GIGW 3.0 ACCESSIBILITY STATEMENT',
        subtitle:
            'This portal is compliant with WCAG 2.1 AA and the Government of '
            'India GIGW 3.0 accessibility guidelines.',
        maxWidth: 660,
        body: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _ScreenReaderLine(
              icon: Icons.keyboard_rounded,
              text:
                  'Use Tab / Shift+Tab to move between controls and Enter to '
                  'activate the focused button or link.',
            ),
            _ScreenReaderLine(
              icon: Icons.record_voice_over_rounded,
              text:
                  'All dashboards expose semantic headings, table captions and '
                  'ARIA labels for JAWS, NVDA and TalkBack.',
            ),
            _ScreenReaderLine(
              icon: Icons.format_size_rounded,
              text:
                  'Use A- / A / A+ in the top strip to resize text without '
                  'losing layout or table readability.',
            ),
            _ScreenReaderLine(
              icon: Icons.translate_rounded,
              text:
                  'The English / हिन्दी control switches official notices to '
                  'bilingual mode.',
            ),
            _ScreenReaderLine(
              icon: Icons.support_agent_rounded,
              text:
                  'Accessibility helpdesk: 1800-11-2026 (toll-free) or '
                  'accessibility@aicte.gov.in.',
            ),
          ],
        ),
        actions: [
          AppButton(
            label: 'Close',
            icon: Icons.close_rounded,
            dense: true,
            onPressed: () => Navigator.of(dialogContext).pop(),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return MediaQuery(
      data: MediaQuery.of(
        context,
      ).copyWith(textScaler: TextScaler.linear(_fontScale)),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          return Scaffold(
            body: Stack(
              children: [
                Column(
                  children: [
                    _GovAccessibilityStrip(
                      hindi: _hindi,
                      highContrast: false,
                      showContrast: false,
                      onSkip: _skipToMainContent,
                      onScreenReaderAccess: _showScreenReaderAccess,
                      onDecreaseFont: () => _adjustFont(-0.1),
                      onResetFont: _resetFont,
                      onIncreaseFont: () => _adjustFont(0.1),
                      onToggleContrast: () {},
                      onToggleLanguage: _toggleLanguage,
                    ),
                    PortalTopBar(state: state),
                    Expanded(
                      child: Column(
                        children: [
                          Expanded(
                            child: LayoutBuilder(
                              builder: (context, constraints) {
                                final collapsed = constraints.maxWidth < 1180;
                                return Row(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    PortalSidebar(
                                      state: state,
                                      collapsed: collapsed,
                                    ),
                                    Expanded(
                                      child: Container(
                                        key: _mainContentKey,
                                        color: AppColors.slate,
                                        child: AnimatedSwitcher(
                                          duration: const Duration(
                                            milliseconds: 220,
                                          ),
                                          switchInCurve: Curves.easeOut,
                                          switchOutCurve: Curves.easeIn,
                                          transitionBuilder:
                                              (child, animation) {
                                                return FadeTransition(
                                                  opacity: animation,
                                                  child: child,
                                                );
                                              },
                                          child: KeyedSubtree(
                                            key: ValueKey(
                                              '${state.role.name}-${state.navIndex}',
                                            ),
                                            child: _pageForState(
                                              context,
                                              state,
                                            ),
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
                    ),
                    _GovFooter(compact: width < 760),
                  ],
                ),
                Positioned(
                  right: 24,
                  bottom: 24,
                  child: SafeArea(child: AskEkoshAiFab(state: state)),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// Government breadcrumb strip with a live IST server clock. Displayed above
/// the sidebar + workspace frame on every authenticated dashboard.
class _GovBreadcrumbBar extends StatelessWidget {
  const _GovBreadcrumbBar({required this.state, required this.hindi});

  final PortalState state;
  final bool hindi;

  String get _portalLabel => switch (state.role) {
    UserRole.institute => 'Institute Portal',
    UserRole.bank => 'Bank Node Portal',
    UserRole.ro => 'AICTE RO Portal',
    UserRole.finance => 'Finance HQ Portal',
  };

  @override
  Widget build(BuildContext context) {
    final items = _navigationFor(state);
    final module = state.navIndex < items.length
        ? items[state.navIndex].label
        : 'Dashboard';
    final trail =
        '${hindi ? 'होम' : 'Home'}  >  e-Kosh AICTE  >  $_portalLabel  >  $module';
    return LayoutBuilder(
      builder: (context, constraints) {
        final showClock = constraints.maxWidth >= 760;
        return Container(
          height: 36,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: const BoxDecoration(
            color: Colors.white,
            border: Border(bottom: BorderSide(color: _govLine)),
          ),
          child: Row(
            children: [
              const Icon(Icons.account_tree_rounded, size: 13, color: _govNavy),
              const SizedBox(width: 7),
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Text(
                    trail,
                    maxLines: 1,
                    style: const TextStyle(
                      fontSize: 9.2,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF475569),
                    ),
                  ),
                ),
              ),
              if (showClock) ...[const SizedBox(width: 12), const _IstClock()],
            ],
          ),
        );
      },
    );
  }
}

/// Live Indian Standard Time clock. Timers are skipped inside widget tests so
/// `pumpAndSettle` can reach a stable frame while production runs tick every
/// second.
class _IstClock extends StatefulWidget {
  const _IstClock();

  @override
  State<_IstClock> createState() => _IstClockState();
}

class _IstClockState extends State<_IstClock> {
  Timer? _timer;
  DateTime _ist = _nowIst();

  static DateTime _nowIst() =>
      DateTime.now().toUtc().add(const Duration(hours: 5, minutes: 30));

  static bool get _isTestBinding {
    var isTest = false;
    assert(() {
      isTest = WidgetsBinding.instance.runtimeType.toString().contains('Test');
      return true;
    }());
    return isTest;
  }

  @override
  void initState() {
    super.initState();
    if (_isTestBinding) return;
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _ist = _nowIst());
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final time =
        '${_two(_ist.hour)}:${_two(_ist.minute)}:${_two(_ist.second)} IST';
    final date =
        '${_two(_ist.day)} ${_monthsShort[_ist.month - 1]} ${_ist.year}';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(3),
        border: Border.all(color: _govLine),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.schedule_rounded, size: 11, color: _govNavy),
          const SizedBox(width: 4),
          Text(
            'IST SERVER TIME  •  $date  •  $time',
            maxLines: 1,
            style: const TextStyle(
              fontSize: 8,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.2,
              color: _govNavy,
            ),
          ),
        ],
      ),
    );
  }
}

class _ScreenReaderLine extends StatelessWidget {
  const _ScreenReaderLine({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: _govNavy.withValues(alpha: 0.07),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: _govNavy.withValues(alpha: 0.14)),
            ),
            child: Icon(icon, size: 15, color: _govNavy),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                fontSize: 11,
                height: 1.5,
                color: AppColors.ink,
              ),
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
    UserRole.finance => switch (state.navIndex) {
      0 => FinanceSettlementPage(state: state),
      1 => FinanceLedgerPage(state: state),
      _ => FinanceInsightsPage(state: state),
    },
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
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final compact = width < 1120;
        final ultraCompact = width < 560;
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            border: Border(bottom: BorderSide(color: AppColors.gold, width: 3)),
            boxShadow: [
              BoxShadow(
                color: Color(0x0F0F172A),
                blurRadius: 20,
                offset: Offset(0, 5),
              ),
            ],
          ),
          child: SizedBox(
            height: ultraCompact ? 124 : 76,
            child: ultraCompact
                ? _buildCompactBar()
                : Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Row(
                      children: [
                        Expanded(
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: _PortalBrand(
                              showSubtitle: width >= 940,
                              showWordmark: true,
                            ),
                          ),
                        ),

                        _NotificationButton(state: state),
                        if (width >= 860) ...[
                          const SizedBox(width: 12),
                          _CronButton(state: state),
                        ],
                        if (!compact) ...[
                          const SizedBox(width: 12),
                          _ActiveUserBadge(state: state),
                        ],
                        if (state.isAuthenticated) ...[
                          const SizedBox(width: 12),
                          _SignOutButton(
                            state: state,
                            showLabel: width >= 1180,
                          ),
                        ],
                      ],
                    ),
                  ),
          ),
        );
      },
    );
  }

  /// Ultra-narrow phones get a two-row bar so the sign-out control never
  /// collides with the emblem and the notification bell.
  Widget _buildCompactBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 6),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            children: [
              const Expanded(
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: _PortalBrand(showSubtitle: false, showWordmark: false),
                ),
              ),
              _NotificationButton(state: state),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              const Spacer(),
              if (state.isAuthenticated)
                _SignOutButton(state: state, showLabel: false),
            ],
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
                  'GOVERNMENT OF INDIA  •  MINISTRY OF EDUCATION',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 8.2,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.05,
                    color: AppColors.gold,
                  ),
                ),
                const SizedBox(height: 2),
                const Text(
                  'ALL INDIA COUNCIL FOR TECHNICAL EDUCATION (AICTE)',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14.6,
                    fontWeight: FontWeight.w900,
                    color: AppColors.navyInk,
                    letterSpacing: -0.1,
                    height: 1.05,
                  ),
                ),
                if (showSubtitle) ...[
                  const SizedBox(height: 3),
                  const Text(
                    'e-Kosh: National Security Deposit & Joint FDR Lifecycle Management System',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 9.4,
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

class _CronButton extends StatelessWidget {
  const _CronButton({required this.state});

  final PortalState state;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Simulate Daily Maturity Cron Job',
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _simulateMaturityCron(context, state),
        child: Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(
            color: AppColors.gold.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.gold.withValues(alpha: 0.28)),
          ),
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.center,
            children: [
              const Icon(
                Icons.schedule_send_rounded,
                color: AppColors.gold,
                size: 22,
              ),
              if (state.overdueRecords.isNotEmpty)
                Positioned(
                  top: 7,
                  right: 7,
                  child: Container(
                    constraints: const BoxConstraints(minWidth: 16),
                    height: 16,
                    padding: const EdgeInsets.symmetric(horizontal: 3),
                    decoration: BoxDecoration(
                      color: AppColors.red,
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: Colors.white, width: 1.4),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      '${state.overdueRecords.length}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 8.5,
                        fontWeight: FontWeight.w900,
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

void _simulateMaturityCron(BuildContext context, PortalState state) {
  state.runMaturityCron();
  showAppToast(
    context,
    'Daily maturity cron complete • ${state.overdueRecords.length} overdue and ${state.dueSoonRecords.length} nearing maturity. Alerts sent via Portal, Email and SMS.',
    icon: Icons.schedule_send_rounded,
    color: AppColors.orange,
  );
}

class _ActiveUserBadge extends StatelessWidget {
  const _ActiveUserBadge({required this.state});

  final PortalState state;

  @override
  Widget build(BuildContext context) {
    final role = state.role;
    final email = state.signedInUserId;
    return Tooltip(
      message: email == null
          ? '${role.personName} • ${role.label}'
          : 'Signed in as $email • ${role.label}',
      child: Container(
        height: 62,
        padding: const EdgeInsets.fromLTRB(7, 5, 12, 5),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(13),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: role.accent.withValues(alpha: 0.10),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: role.accent.withValues(alpha: 0.18),
                    ),
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
                Positioned(
                  right: -1,
                  bottom: -1,
                  child: Container(
                    width: 14,
                    height: 14,
                    decoration: BoxDecoration(
                      color: AppColors.emeraldDark,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2),
                    ),
                    child: const Icon(
                      Icons.verified_user_rounded,
                      size: 7,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(width: 9),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 200),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    role.personName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11.5,
                      height: 1.15,
                      color: AppColors.navyInk,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  Text(
                    email ?? role.shortLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 9.5,
                      height: 1.15,
                      color: AppColors.muted,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  SizedBox(height: 1),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.verified_user_rounded,
                        size: 8,
                        color: AppColors.emeraldDark,
                      ),
                      SizedBox(width: 3),
                      Text(
                        'NIC SSO VERIFIED',
                        style: TextStyle(
                          fontSize: 7,
                          height: 1.1,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.45,
                          color: AppColors.emeraldDark,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Logout control for the authenticated session. Clears the session and
/// returns to the government SSO gateway so a different account can sign in.
class _SignOutButton extends StatelessWidget {
  const _SignOutButton({required this.state, required this.showLabel});

  final PortalState state;
  final bool showLabel;

  Future<void> _confirm(BuildContext context) async {
    final confirmed = await showConfirmDialog(
      context,
      title: 'Log out of e-Kosh AICTE?',
      message:
          'Your ${state.role.label} session for ${state.signedInUserId ?? state.credential.userId} '
          'will be closed and you will return to the AICTE SSO gateway to '
          'switch accounts. The credentials issued to this persona will be '
          'required to sign back in.',
      confirmLabel: 'Sign Out',
      confirmColor: AppColors.red,
      icon: Icons.logout_rounded,
      extra: _DialogAmountBox(
        label: 'Signed-in account',
        value: state.signedInUserId ?? state.credential.userId,
        helper: '${state.role.label} • ${state.role.location}',
      ),
    );
    if (!confirmed || !context.mounted) return;
    state.signOut();
    showAppToast(
      context,
      'Session closed securely. AICTE SSO sign-in is required to reopen a dashboard.',
      icon: Icons.lock_rounded,
      color: AppColors.navy,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Logout / Switch Account',
      child: Material(
        color: AppColors.red.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(13),
        child: InkWell(
          borderRadius: BorderRadius.circular(13),
          onTap: () => _confirm(context),
          child: Container(
            height: 58,
            padding: EdgeInsets.symmetric(horizontal: showLabel ? 13 : 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(13),
              border: Border.all(color: AppColors.red.withValues(alpha: 0.28)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.logout_rounded,
                  size: 17,
                  color: AppColors.red,
                ),
                if (showLabel) ...[
                  const SizedBox(width: 7),
                  const Text(
                    'LOGOUT / SWITCH ACCOUNT',
                    style: TextStyle(
                      fontSize: 7.8,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.4,
                      color: AppColors.red,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
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
      PortalNavItem(
        label: 'Analytics & Audit',
        icon: Icons.insights_rounded,
        badge: state.auditEventCount,
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
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(11),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 170),
            height: 48,
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
            child: Stack(
              children: [
                if (selected)
                  Positioned(
                    left: 0,
                    top: 0,
                    bottom: 0,
                    child: Container(
                      width: 4,
                      decoration: const BoxDecoration(
                        color: Color(0xFFF59E0B),
                        borderRadius: BorderRadius.horizontal(
                          left: Radius.circular(11),
                        ),
                      ),
                    ),
                  ),
                Padding(
                  padding: EdgeInsets.only(
                    left: collapsed ? 0 : 16,
                    right: collapsed ? 0 : 12,
                  ),
                  child: Row(
                    mainAxisAlignment: collapsed
                        ? MainAxisAlignment.center
                        : MainAxisAlignment.start,
                    children: [
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
                              borderRadius: BorderRadius.circular(3),
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
                      if (collapsed &&
                          item.badge != null &&
                          item.badge! > 0) ...[
                        const SizedBox(width: 3),
                        Container(
                          constraints: const BoxConstraints(minWidth: 14),
                          height: 14,
                          padding: const EdgeInsets.symmetric(horizontal: 3),
                          decoration: BoxDecoration(
                            color: AppColors.gold,
                            borderRadius: BorderRadius.circular(3),
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
            maxLines: 2,
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
                  'SECURE • TLS 1.3',
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
                maxLines: 2,
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
        if (constraints.maxWidth < 980) {
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
            Flexible(
              child: Wrap(
                spacing: 10,
                runSpacing: 10,
                alignment: WrapAlignment.end,
                children: actions,
              ),
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
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFCBD5E1)),
        boxShadow: [
          BoxShadow(
            color: AppColors.navy.withValues(alpha: 0.045),
            blurRadius: 14,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(height: 4, color: color),
            Padding(
              padding: const EdgeInsets.all(18),
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
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: color.withValues(alpha: 0.12),
                          ),
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
                    maxLines: 3,
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
            ),
          ],
        ),
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
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFCBD5E1)),
        boxShadow: [
          BoxShadow(
            color: AppColors.navy.withValues(alpha: 0.035),
            blurRadius: 14,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
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
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
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
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
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
                      const SizedBox(width: 10),
                      ConstrainedBox(
                        constraints: BoxConstraints(
                          maxWidth: MediaQuery.of(context).size.width > 600
                              ? 220
                              : 140,
                        ),
                        child: trailing!,
                      ),
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
                borderRadius: BorderRadius.circular(3),
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
                borderRadius: BorderRadius.circular(3),
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
        borderRadius: BorderRadius.circular(4),
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
        borderRadius: BorderRadius.circular(4),
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

class MaturityUrgencyChip extends StatelessWidget {
  const MaturityUrgencyChip({super.key, required this.record});

  final FDRRecord record;

  @override
  Widget build(BuildContext context) {
    final settled =
        record.status == FDRStatus.fundsDisbursed ||
        record.status == FDRStatus.forfeited ||
        record.status == FDRStatus.rejectedByBank;
    final days = record.daysToMaturity;

    late final Color color;
    late final Color background;
    late final Color border;
    late final IconData icon;
    late final String label;
    late final String helper;

    if (settled) {
      color = AppColors.muted;
      background = AppColors.surfaceSoft;
      border = AppColors.border;
      icon = Icons.task_alt_rounded;
      label = 'Matured • Closed';
      helper = record.isOverdue ? '${-days}d past maturity' : 'Cycle closed';
    } else if (days < 0) {
      color = AppColors.red;
      background = const Color(0xFFFEF2F2);
      border = const Color(0xFFFECACA);
      icon = Icons.warning_amber_rounded;
      label = 'Time Exceeded / Overdue';
      helper = '${-days} days overdue';
    } else if (days < 30) {
      color = const Color(0xFFB45309);
      background = const Color(0xFFFFFBEB);
      border = const Color(0xFFFDE68A);
      icon = Icons.timer_rounded;
      label = '< 30 Days';
      helper = '$days days left';
    } else if (days <= 365) {
      color = AppColors.indigo;
      background = const Color(0xFFEEF2FF);
      border = const Color(0xFFC7D2FE);
      icon = Icons.event_available_rounded;
      label = '$days Days Left';
      helper = 'Within one year';
    } else {
      color = AppColors.emeraldDark;
      background = const Color(0xFFECFDF5);
      border = const Color(0xFFA7F3D0);
      icon = Icons.verified_rounded;
      label = '> 1 Year Left';
      helper = '${(days / 365).toStringAsFixed(1)} years';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 8.8,
                  fontWeight: FontWeight.w900,
                  color: color,
                  height: 1.15,
                ),
              ),
              Text(
                helper,
                style: TextStyle(
                  fontSize: 7.6,
                  fontWeight: FontWeight.w600,
                  color: color.withValues(alpha: 0.75),
                  height: 1.2,
                ),
              ),
            ],
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
        borderRadius: BorderRadius.circular(4),
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
      child: LayoutBuilder(
        builder: (context, constraints) {
          final content = Row(
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
              if (trailing != null && constraints.maxWidth >= 520) ...[
                const SizedBox(width: 12),
                trailing!,
              ],
            ],
          );
          if (trailing == null || constraints.maxWidth >= 520) {
            return content;
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              content,
              const SizedBox(height: 10),
              Align(alignment: Alignment.centerLeft, child: trailing!),
            ],
          );
        },
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

/// Alternating government table rows: white for even indices, #F8FAFC for odd.
WidgetStateProperty<Color?> portalRowColor(int index) => WidgetStatePropertyAll(
  index.isEven ? Colors.white : const Color(0xFFF8FAFC),
);

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
        behavior: SnackBarBehavior.floating,
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
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(6),
          side: BorderSide(color: AppColors.navy.withValues(alpha: 0.22)),
        ),
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
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
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(6),
        side: BorderSide(color: AppColors.navy.withValues(alpha: 0.22)),
      ),
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.white,
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
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [AppColors.navyDeep, AppColors.navy],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  border: Border(bottom: BorderSide(color: accent, width: 3)),
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

/// High-priority pre-maturity advisory shown on the Institute dashboard when
/// an FDR enters the automated 90 / 60 / 30-day Email + SMS alert horizon.
class _PreMaturityAdvisoryBanner extends StatelessWidget {
  const _PreMaturityAdvisoryBanner({required this.state});

  final PortalState state;

  ({String email, String mobile}) get _registeredContact {
    final record = state.nearestPreMaturityRecord;
    if (record != null) {
      for (final log in state.notificationLogs) {
        if (log.fdrNumber == record.id && log.recipientEmail.isNotEmpty) {
          return (email: log.recipientEmail, mobile: log.recipientMobile);
        }
      }
    }
    return (email: state.credential.userId, mobile: '+91-9840012310');
  }

  @override
  Widget build(BuildContext context) {
    final record = state.nearestPreMaturityRecord;
    if (record == null) return const SizedBox.shrink();
    final days = record.daysToMaturity;
    final window = days <= 30
        ? '30_DAYS'
        : days <= 60
        ? '60_DAYS'
        : '90_DAYS';
    final title = switch (window) {
      '30_DAYS' => '30-Day Critical Maturity Window',
      '60_DAYS' => '60-Day Follow-Up Maturity Window',
      _ => '90-Day Pre-Maturity Advisory Window',
    };
    final accent = switch (window) {
      '30_DAYS' => AppColors.red,
      '60_DAYS' => AppColors.orange,
      _ => AppColors.indigo,
    };
    final tint = switch (window) {
      '30_DAYS' => const Color(0xFFFEF2F2),
      '60_DAYS' => const Color(0xFFFFF7ED),
      _ => const Color(0xFFEEF2FF),
    };
    final contact = _registeredContact;
    final total = state.preMaturityRecords.length;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [tint, Colors.white],
        ),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: accent.withValues(alpha: 0.34)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth >= 860;
              final heading = Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: accent.withValues(alpha: 0.24)),
                    ),
                    child: Icon(
                      Icons.campaign_rounded,
                      size: 20,
                      color: accent,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'AICTE FINANCE BUREAU • $title',
                          style: TextStyle(
                            fontSize: 8.8,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0.7,
                            color: accent,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          'FDR ${record.id} matures in $days day${days == 1 ? '' : 's'}',
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w900,
                            color: AppColors.navyInk,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          '${record.bankName} • ${record.program} • '
                          '${inr(record.amount)} principal • Maturity '
                          '${formatDate(record.maturityDate)}',
                          style: const TextStyle(
                            fontSize: 9.6,
                            height: 1.4,
                            color: AppColors.muted,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              );
              final counter = Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: accent.withValues(alpha: 0.26)),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '$days',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                        height: 1,
                        letterSpacing: -0.6,
                        color: accent,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      days == 1 ? 'DAY TO MATURITY' : 'DAYS TO MATURITY',
                      style: TextStyle(
                        fontSize: 7,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.5,
                        color: accent,
                      ),
                    ),
                  ],
                ),
              );
              if (!wide) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    heading,
                    const SizedBox(height: 10),
                    Align(alignment: Alignment.centerLeft, child: counter),
                  ],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: heading),
                  const SizedBox(width: 14),
                  counter,
                ],
              );
            },
          ),
          const SizedBox(height: 11),
          Container(
            padding: const EdgeInsets.all(11),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.82),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: accent.withValues(alpha: 0.18)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.mark_email_read_rounded,
                      size: 14,
                      color: AppColors.emeraldDark,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Official advisory already dispatched to the registered '
                        'Email & Mobile of the institute nodal officer through '
                        'the NIC-SMS / SMTP gateway.',
                        style: const TextStyle(
                          fontSize: 9.6,
                          height: 1.45,
                          fontWeight: FontWeight.w600,
                          color: AppColors.emeraldDark,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 5),
                Wrap(
                  spacing: 12,
                  runSpacing: 4,
                  children: [
                    _AdvisoryContactLine(
                      icon: Icons.alternate_email_rounded,
                      label: contact.email,
                    ),
                    _AdvisoryContactLine(
                      icon: Icons.phone_android_rounded,
                      label: contact.mobile.isEmpty ? 'N/A' : contact.mobile,
                    ),
                    _AdvisoryContactLine(
                      icon: Icons.inventory_2_rounded,
                      label:
                          '$total FDR${total == 1 ? '' : 's'} in the 90-day watchlist',
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Please file the Release Application or the renewed 2-year FDR '
            'through the e-Kosh portal before maturity to avoid encashment '
            'and penalty action.',
            style: TextStyle(
              fontSize: 9.2,
              height: 1.45,
              fontStyle: FontStyle.italic,
              color: accent.withValues(alpha: 0.92),
            ),
          ),
        ],
      ),
    );
  }
}

class _AdvisoryContactLine extends StatelessWidget {
  const _AdvisoryContactLine({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 320),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: AppColors.navy),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w700,
                color: AppColors.navyInk,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MaturityAlertBanner extends StatelessWidget {
  const _MaturityAlertBanner({required this.state});

  final PortalState state;

  @override
  Widget build(BuildContext context) {
    final overdue = state.instituteRecords
        .where((record) => record.isOverdue && !record.status.isClosed)
        .toList();
    if (overdue.isEmpty || state.maturityAlertDismissed) {
      return const SizedBox.shrink();
    }
    final record = overdue.firstWhere(
      (item) => item.id == 'FDR-CAN-2016-412',
      orElse: () => overdue.first,
    );
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 10, 14),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFFEF2F2), Color(0xFFFFF7ED)],
        ),
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: AppColors.red.withValues(alpha: 0.32)),
        boxShadow: [
          BoxShadow(
            color: AppColors.red.withValues(alpha: 0.07),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: AppColors.red.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.campaign_rounded,
              color: AppColors.red,
              size: 21,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    const Text(
                      'URGENT MATURITY ALERT',
                      style: TextStyle(
                        fontSize: 9.2,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1,
                        color: AppColors.red,
                      ),
                    ),
                    SoftChip(
                      label: state.maturityCronRan
                          ? 'Cron alert • ${state.maturityCronRuns} run${state.maturityCronRuns == 1 ? '' : 's'}'
                          : 'Cron monitor active',
                      icon: Icons.schedule_send_rounded,
                      color: AppColors.orange,
                    ),
                    const SoftChip(
                      label: 'Email + SMS + Portal',
                      icon: Icons.cell_tower_rounded,
                      color: AppColors.red,
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  'URGENT: FDR #${record.id} has exceeded its project/approval timeline. Immediate action required: Apply for Release or Submit 2-Year Renewal.',
                  style: const TextStyle(
                    fontSize: 11.4,
                    height: 1.5,
                    fontWeight: FontWeight.w700,
                    color: AppColors.navyInk,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  record.holdReason ??
                      'The 8-year lock-in has ended without a completed release or renewal. Multi-channel reminders have been dispatched to the institute nodal officer.',
                  style: const TextStyle(
                    fontSize: 9.8,
                    height: 1.45,
                    color: AppColors.muted,
                  ),
                ),
                const SizedBox(height: 11),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    AppButton(
                      label: 'Apply for Release',
                      icon: Icons.assignment_turned_in_rounded,
                      dense: true,
                      color: AppColors.gold,
                      onPressed:
                          record.status == FDRStatus.onHoldExtension ||
                              !record.isMatured
                          ? null
                          : () => _applyForRelease(context, state, record),
                    ),
                    AppButton(
                      label: 'Submit 2-Year Renewal',
                      icon: Icons.autorenew_rounded,
                      dense: true,
                      color: AppColors.orange,
                      onPressed: () =>
                          openRenewalDialog(context, state, record),
                    ),
                  ],
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Dismiss alert',
            onPressed: state.dismissMaturityAlert,
            icon: const Icon(
              Icons.close_rounded,
              size: 18,
              color: AppColors.muted,
            ),
          ),
        ],
      ),
    );
  }
}

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
        if (state.nearestPreMaturityRecord != null)
          _PreMaturityAdvisoryBanner(state: state),
        if (state.instituteRecords.any(
              (record) => record.isOverdue && !record.status.isClosed,
            ) &&
            !state.maturityAlertDismissed)
          _MaturityAlertBanner(state: state),
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
                  minWidth: 1250,
                  child: DataTable(
                    showCheckboxColumn: false,
                    horizontalMargin: 20,
                    columnSpacing: 20,
                    headingRowHeight: 46,
                    dataRowMinHeight: 78,
                    dataRowMaxHeight: 96,
                    headingRowColor: const WidgetStatePropertyAll(
                      AppColors.navy,
                    ),
                    headingTextStyle: const TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.8,
                      color: Colors.white,
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
                      DataColumn(label: Text('MATURITY URGENCY')),
                      DataColumn(label: Text('LIFECYCLE STATUS')),
                      DataColumn(label: Text('ACTION')),
                    ],
                    rows: records.asMap().entries.map((entry) {
                      final rowIndex = entry.key;
                      final record = entry.value;
                      final canApply =
                          record.status == FDRStatus.activeLienLocked &&
                          record.isMatured;
                      final needsRenewal =
                          record.status == FDRStatus.onHoldExtension;
                      final hasEnoc = record.hasEnoc;
                      return DataRow(
                        color: portalRowColor(rowIndex),
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
                          DataCell(MaturityUrgencyChip(record: record)),
                          DataCell(StatusPill(status: record.status)),
                          DataCell(
                            SizedBox(
                              width: 280,
                              child: hasEnoc
                                  ? AppButton(
                                      label: 'View / Download Digital e-NOC',
                                      icon: Icons.qr_code_2_rounded,
                                      dense: true,
                                      color: AppColors.emeraldDark,
                                      onPressed: () => showEnocDialog(
                                        context,
                                        state,
                                        record,
                                      ),
                                    )
                                  : needsRenewal
                                  ? AppButton(
                                      label:
                                          'Upload Extended / Renewed FDR (2 Years)',
                                      icon: Icons.autorenew_rounded,
                                      dense: true,
                                      color: AppColors.orange,
                                      onPressed: () => openRenewalDialog(
                                        context,
                                        state,
                                        record,
                                      ),
                                    )
                                  : canApply
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

Future<void> openRenewalDialog(
  BuildContext context,
  PortalState state,
  FDRRecord record,
) async {
  final confirmed = await showDialog<bool>(
    context: context,
    barrierColor: AppColors.navyInk.withValues(alpha: 0.5),
    builder: (context) => _RenewalDialog(record: record),
  );
  if (confirmed != true || !context.mounted) return;
  state.renewFdr(record);
  showAppToast(
    context,
    '${record.id} renewed to ${formatDate(record.maturityDate)} and routed to ${record.bankName} for lien re-verification.',
    icon: Icons.autorenew_rounded,
    color: AppColors.emeraldDark,
  );
}

class _RenewalDialog extends StatelessWidget {
  const _RenewalDialog({required this.record});

  final FDRRecord record;

  @override
  Widget build(BuildContext context) {
    final renewedMaturity = DateTime(
      record.maturityDate.year + 2,
      record.maturityDate.month,
      record.maturityDate.day,
    );
    return PortalDialogFrame(
      title: 'Upload Extended / Renewed FDR (2 Years)',
      subtitle: '${record.id} • ${record.instituteName} • ${record.bankName}',
      icon: '↻',
      maxWidth: 660,
      accent: AppColors.orange,
      bodyPadding: const EdgeInsets.all(20),
      actions: [
        AppButton(
          label: 'Cancel',
          primary: false,
          onPressed: () => Navigator.of(context).pop(false),
        ),
        AppButton(
          label: 'Upload & Route to Bank',
          icon: Icons.upload_file_rounded,
          color: AppColors.orange,
          onPressed: () => Navigator.of(context).pop(true),
        ),
      ],
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InfoBanner(
            title: 'RO-mandated renewal',
            message:
                'The Regional Office has withheld release because the project/approval timeline was exceeded. Upload the renewed joint FDR to extend maturity by two years and return the instrument to the bank for fresh lien verification.',
            icon: Icons.autorenew_rounded,
            color: AppColors.orange,
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.surfaceSoft,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'RENEWED JOINT FDR DOCUMENT',
                  style: TextStyle(
                    fontSize: 8.6,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.8,
                    color: AppColors.muted,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: AppColors.orange.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(9),
                      ),
                      child: const Icon(
                        Icons.picture_as_pdf_rounded,
                        color: AppColors.orange,
                        size: 21,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${record.id}_RENEWAL_2Y.pdf',
                            style: const TextStyle(
                              fontSize: 10.8,
                              fontWeight: FontWeight.w800,
                              color: AppColors.navyInk,
                            ),
                          ),
                          const SizedBox(height: 2),
                          const Text(
                            'Digital signature verified • Institute + AICTE Member Secretary',
                            style: TextStyle(
                              fontSize: 9,
                              color: AppColors.muted,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SoftChip(
                      label: 'Attached',
                      icon: Icons.check_circle_rounded,
                      color: AppColors.emeraldDark,
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth >= 480
                  ? (constraints.maxWidth - 10) / 2
                  : constraints.maxWidth;
              return Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  SizedBox(
                    width: width,
                    child: _DialogAmountBox(
                      label: 'Current maturity',
                      value: formatDate(record.maturityDate),
                      helper: 'Existing annual extension cycle',
                    ),
                  ),
                  SizedBox(
                    width: width,
                    child: _DialogAmountBox(
                      label: 'Renewed maturity (+2 years)',
                      value: formatDate(renewedMaturity),
                      helper: 'New 2-year lien lock-in',
                    ),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 12),
          const Text(
            'On confirmation, the FDR status changes to "Pending Bank Verification" and the bank node receives the renewed instrument for lien re-verification.',
            style: TextStyle(
              fontSize: 9.6,
              height: 1.45,
              color: AppColors.muted,
            ),
          ),
        ],
      ),
    );
  }
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

  bool _ocrRunning = false;
  bool _ocrComplete = false;
  bool _documentAttached = false;
  String? _selectedFileName;
  int? _selectedFileSize;
  String? _selectedFileExtension;
  double _ocrProgress = 0;
  Timer? _ocrTimer;
  static const _ocrConfidence = 98.4;

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
  @override
  void dispose() {
    _ocrTimer?.cancel();
    _ifscController.dispose();
    _fdrController.dispose();
    _amountController.dispose();
    _issueController.dispose();
    _maturityController.dispose();
    super.dispose();
  }

  Future<void> _pickDocument() async {
    if (_ocrRunning) return;
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png'],
        withData: true,
      );
      if (result == null || result.files.isEmpty) {
        return;
      }
      final file = result.files.first;
      setState(() {
        _documentAttached = true;
        _selectedFileName = file.name;
        final sizeBytes = file.size;
        _selectedFileSize = sizeBytes;
        final extension = file.extension?.toLowerCase();
        _selectedFileExtension = extension;
        _ocrComplete = false;
        _ocrProgress = 0;
      });
    } catch (e) {
      // Ignore errors, keep current state
    }
  }

  void _removeDocument() {
    if (_ocrRunning) return;
    setState(() {
      _documentAttached = false;
      _selectedFileName = null;
      _selectedFileSize = null;
      _selectedFileExtension = null;
      _ocrComplete = false;
      _ocrProgress = 0;
    });
  }

  void _runOcr() {
    if (_ocrRunning) return;
    _ocrTimer?.cancel();
    setState(() {
      _documentAttached = true;
      _ocrRunning = true;
      _ocrComplete = false;
      _ocrProgress = 0;
    });
    var elapsedMs = 0;
    _ocrTimer = Timer.periodic(const Duration(milliseconds: 30), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      elapsedMs += 30;
      final progress = (elapsedMs / 1500).clamp(0.0, 1.0);
      if (progress >= 1) {
        timer.cancel();
        _applyOcrExtraction();
      } else {
        setState(() => _ocrProgress = progress);
      }
    });
  }

  void _applyOcrExtraction() {
    final now = DateTime.now();
    final issue = DateTime(now.year, now.month, now.day);
    final maturity = DateTime(now.year + 8, now.month, now.day);
    setState(() {
      _bank = 'State Bank of India';
      _ifscController.text = 'SBIN0004321';
      _fdrController.text = 'FDR-SBI-2026-88392';
      _amountController.text = '1500000';
      _issueDate = issue;
      _maturityDate = maturity;
      _issueController.text = formatDate(issue);
      _maturityController.text = formatDate(maturity);
      _ocrRunning = false;
      _ocrComplete = true;
      _ocrProgress = 1;
      _documentAttached = true;
    });
    showAppToast(
      context,
      'AI OCR extraction complete • FDR-SBI-2026-88392 • 98.4% confidence.',
      icon: Icons.auto_awesome_rounded,
      color: AppColors.emeraldDark,
    );
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
        const SizedBox(height: 24),
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
                children: [calculator, const SizedBox(height: 24), form],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 4, child: calculator),
                const SizedBox(width: 24),
                Expanded(flex: 6, child: form),
              ],
            );
          },
        ),
        const SizedBox(height: 24),
        SectionCard(
          title: 'Verification journey after submission',
          subtitle:
              'No manual follow-up is required — each stakeholder receives the request in their queue.',
          contentPadding: const EdgeInsets.all(24),
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

  Widget _buildDocumentUpload(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: AppColors.navy.withValues(alpha: 0.09),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: const Icon(
                  Icons.upload_file_rounded,
                  size: 18,
                  color: AppColors.navy,
                ),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Upload Joint FDR Document',
                      style: TextStyle(
                        fontSize: 11.8,
                        fontWeight: FontWeight.w900,
                        color: AppColors.navyInk,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Attach your scanned Joint FDR in PDF, JPG, or PNG format.',
                      style: TextStyle(fontSize: 9.2, color: AppColors.muted),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: _ocrRunning ? null : _pickDocument,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 16),
              decoration: BoxDecoration(
                color: AppColors.surfaceSoft,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: _documentAttached
                      ? AppColors.emerald.withValues(alpha: 0.38)
                      : AppColors.border,
                  style: BorderStyle.solid,
                ),
              ),
              child: Column(
                children: [
                  Icon(
                    _documentAttached
                        ? Icons.task_alt_rounded
                        : Icons.cloud_upload_rounded,
                    size: 32,
                    color: _documentAttached
                        ? AppColors.emeraldDark
                        : AppColors.navy,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _documentAttached
                        ? (_selectedFileName ?? 'Selected file')
                        : 'Click or drag and drop to upload Joint FDR document',
                    style: const TextStyle(
                      fontSize: 10.6,
                      fontWeight: FontWeight.w800,
                      color: AppColors.navyInk,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 6),
                  if (_documentAttached)
                    Text(
                      _selectedFileSize != null
                          ? '${(_selectedFileSize! / 1024.0 / 1024.0).toStringAsFixed(2)} MB'
                          : '',
                      style: const TextStyle(
                        fontSize: 8.8,
                        color: AppColors.muted,
                      ),
                      textAlign: TextAlign.center,
                    )
                  else
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        OutlinedButton(
                          onPressed: _ocrRunning ? null : _pickDocument,
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 6,
                            ),
                            visualDensity: VisualDensity.compact,
                          ),
                          child: const Text('Choose File'),
                        ),
                        const SizedBox(width: 8),
                        const Text(
                          'No file chosen',
                          style: TextStyle(
                            fontSize: 9,
                            color: AppColors.muted,
                          ),
                        ),
                      ],
                    ),
                  if (!_documentAttached) ...[
                    const SizedBox(height: 4),
                    const Text(
                      'Supports PDF, JPG, PNG',
                      style: TextStyle(
                        fontSize: 8.8,
                        color: AppColors.muted,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ],
              ),
            ),
          ),
          if (_documentAttached) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                const Icon(
                  Icons.description_rounded,
                  size: 16,
                  color: AppColors.navy,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _selectedFileName != null && _selectedFileSize != null
                        ? '$_selectedFileName (${(_selectedFileSize! / 1024.0 / 1024.0).toStringAsFixed(2)} MB)'
                        : (_selectedFileName ?? 'Selected file'),
                    style: const TextStyle(
                      fontSize: 9.8,
                      fontWeight: FontWeight.w600,
                      color: AppColors.navyInk,
                    ),
                  ),
                ),
                TextButton.icon(
                  onPressed: _removeDocument,
                  icon: const Icon(Icons.close_rounded, size: 16),
                  label: const Text('Remove'),
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.red,
                    textStyle: const TextStyle(
                      fontSize: 9.6,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                TextButton.icon(
                  onPressed: _pickDocument,
                  icon: const Icon(Icons.refresh_rounded, size: 16),
                  label: const Text('Replace'),
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.navy,
                    textStyle: const TextStyle(
                      fontSize: 9.6,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
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
      contentPadding: const EdgeInsets.all(24),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildDocumentUpload(context),
            const SizedBox(height: 16),
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
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFE2E8F0)),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x0F1E3A8A),
                    blurRadius: 8,
                    offset: Offset(0, 1),
                  ),
                ],
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
      contentPadding: const EdgeInsets.all(24),
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
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: const Color(0xFFFEF3C7),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFFCD34D)),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x0F1E3A8A),
                  blurRadius: 10,
                  offset: Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'REQUIRED SECURITY DEPOSIT',
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.0,
                    color: Color(0xFF92400E),
                  ),
                ),
                const SizedBox(height: 5),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    inr(calculatedDeposit),
                    style: const TextStyle(
                      fontSize: 32,
                      height: 1.0,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -0.8,
                      color: Color(0xFF78350F),
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
          const SizedBox(height: 10),
          const Divider(height: 1, color: Color(0xFFE2E8F0)),
          const SizedBox(height: 10),
          _CalculatorLine(
            label: 'Per-seat component',
            value: '${inr(perSeat)} × $intake',
          ),
          const SizedBox(height: 10),
          const Divider(height: 1, color: Color(0xFFE2E8F0)),
          const SizedBox(height: 10),
          _CalculatorLine(
            label: 'Per-seat subtotal',
            value: inr(perSeat * intake),
          ),
          const SizedBox(height: 12),
          const Divider(height: 1, color: Color(0xFFCBD5E1)),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFFCBD5E1)),
            ),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    'Total payable',
                    style: TextStyle(
                      fontSize: 11.5,
                      color: AppColors.navyInk,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                Text(
                  inr(calculatedDeposit),
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppColors.navyInk,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 17),
          AppButton(
            label: 'Apply Amount to Form',
            icon: Icons.calculate_rounded,
            color: AppColors.navy,
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
                      AppColors.navy,
                    ),
                    headingTextStyle: const TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.8,
                      color: Colors.white,
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
                    rows: queue.asMap().entries.map((entry) {
                      final rowIndex = entry.key;
                      final record = entry.value;
                      return DataRow(
                        color: portalRowColor(rowIndex),
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
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Column(
            mainAxisSize: MainAxisSize.min,
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
                        key: ValueKey('release-${releaseQueue[index].id}'),
                        record: releaseQueue[index],
                        state: state,
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
                      AppColors.navy,
                    ),
                    headingTextStyle: const TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.8,
                      color: Colors.white,
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
                    rows: state.disbursedRecords.asMap().entries.map((entry) {
                      final rowIndex = entry.key;
                      final record = entry.value;
                      return DataRow(
                        color: portalRowColor(rowIndex),
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
        'The bank will transfer the approved amount against e-NOC ${record.enocNumber ?? '—'} and move ${record.id} to its final lifecycle state, Settled & Closed. This action cannot be reversed.',
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
    '${inr(record.settlementValue)} disbursed for ${record.id}. Final lifecycle state: Settled & Closed.',
    icon: Icons.check_circle_rounded,
    color: AppColors.emeraldDark,
  );
}

class BankReleaseCard extends StatelessWidget {
  const BankReleaseCard({
    super.key,
    required this.record,
    required this.state,
    required this.onDisburse,
  });

  final FDRRecord record;
  final PortalState state;
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
          final wide = constraints.maxWidth >= 900;
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

          final action = _BankReleaseActions(
            record: record,
            state: state,
            onDisburse: onDisburse,
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
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 5, child: identity),
              const SizedBox(width: 20),
              Expanded(flex: 3, child: financeSummary),
              const SizedBox(width: 18),
              SizedBox(width: 330, child: action),
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
                              Flexible(
                                child: SoftChip(
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
                  minWidth: 1420,
                  child: DataTable(
                    horizontalMargin: 20,
                    columnSpacing: 18,
                    headingRowHeight: 46,
                    dataRowMinHeight: 86,
                    dataRowMaxHeight: 110,
                    headingRowColor: const WidgetStatePropertyAll(
                      AppColors.navy,
                    ),
                    headingTextStyle: const TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.8,
                      color: Colors.white,
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
                      DataColumn(label: Text('URGENCY')),
                      DataColumn(label: Text('COMPLIANCE STATUS')),
                      DataColumn(label: Text('RO ACTION')),
                    ],
                    rows: queue.asMap().entries.map((entry) {
                      final rowIndex = entry.key;
                      final record = entry.value;
                      return DataRow(
                        color: portalRowColor(rowIndex),
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
                          DataCell(MaturityUrgencyChip(record: record)),
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
                                  label: 'Inspect & Run Scrutiny',
                                  icon: Icons.auto_awesome_rounded,
                                  dense: true,
                                  color: AppColors.navy,
                                  onPressed: () => _inspectAndRunScrutiny(
                                    context,
                                    state,
                                    record,
                                  ),
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

enum RuleEngineAction { fastTrack, mandateExtension }

Future<void> _inspectAndRunScrutiny(
  BuildContext context,
  PortalState state,
  FDRRecord record,
) async {
  final action = await showDialog<RuleEngineAction>(
    context: context,
    barrierColor: AppColors.navyInk.withValues(alpha: 0.5),
    builder: (context) => RuleEngineDialog(record: record),
  );
  if (action == null || !context.mounted) return;
  switch (action) {
    case RuleEngineAction.fastTrack:
      state.forwardToFinance(record);
      showAppToast(
        context,
        'Zero-deficiency verified. Fast-track RO clearance granted for ${record.id}; forwarded to AICTE Finance.',
        icon: Icons.verified_rounded,
        color: AppColors.emeraldDark,
      );
      break;
    case RuleEngineAction.mandateExtension:
      state.putOnHold(
        record,
        'Compliance and vigilance rule engine detected unresolved flags. Lock release and submit a renewed 2-year FDR before release can be reconsidered.',
      );
      showAppToast(
        context,
        'Release locked for ${record.id}. A 2-year FDR extension is now mandated.',
        icon: Icons.lock_clock_rounded,
        color: AppColors.orange,
      );
      break;
  }
}

class RuleEngineDialog extends StatefulWidget {
  const RuleEngineDialog({super.key, required this.record});

  final FDRRecord record;

  @override
  State<RuleEngineDialog> createState() => _RuleEngineDialogState();
}

class _RuleEngineDialogState extends State<RuleEngineDialog> {
  Timer? _timer;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _timer = Timer(const Duration(milliseconds: 1100), () {
      if (!mounted) return;
      setState(() => _ready = true);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final record = widget.record;
    final deficient = record.deficiency;
    final checks = <(String, String, String, IconData, Color)>[
      (
        'Infrastructure & Lab Compliance Check',
        deficient ? 'FLAGGED' : 'PASS',
        deficient
            ? 'Lab utilisation report does not match the approved intake footprint.'
            : 'Infrastructure and lab records match the approved programme footprint.',
        deficient ? Icons.warning_amber_rounded : Icons.science_rounded,
        deficient ? AppColors.red : AppColors.emeraldDark,
      ),
      (
        'Faculty Salary & Grievance Check',
        deficient ? 'FLAGGED - Pending Dues' : 'PASS',
        deficient
            ? 'Faculty salary ledger shows pending dues for the review period.'
            : 'No pending faculty salary dues or unresolved grievances found.',
        deficient ? Icons.people_alt_rounded : Icons.groups_rounded,
        deficient ? AppColors.orange : AppColors.emeraldDark,
      ),
      (
        'CBI / Court Vigilance Status',
        'CLEAR',
        'No active CBI inquiry or court restraint order is linked to the institute.',
        Icons.gavel_rounded,
        AppColors.emeraldDark,
      ),
      (
        'Approval / Project Timeline Status',
        deficient ? 'TIME EXCEEDED' : 'WITHIN LIMIT',
        deficient
            ? 'Project approval timeline exceeded by 47 days without a valid extension.'
            : 'Approval and project timeline are within the permitted 8–10 year lock-in.',
        deficient ? Icons.timer_off_rounded : Icons.event_available_rounded,
        deficient ? AppColors.red : AppColors.emeraldDark,
      ),
    ];
    final flags = checks
        .where(
          (check) =>
              check.$2 != 'PASS' &&
              check.$2 != 'CLEAR' &&
              check.$2 != 'WITHIN LIMIT',
        )
        .length;

    return PortalDialogFrame(
      title: 'Automated Compliance & Vigilance Rule Engine',
      subtitle: '${record.id} • ${record.instituteName} • ${record.bankName}',
      icon: 'AI',
      maxWidth: 820,
      accent: deficient ? AppColors.red : AppColors.emeraldDark,
      bodyPadding: const EdgeInsets.all(20),
      actions: [
        AppButton(
          label: 'Cancel',
          primary: false,
          onPressed: () => Navigator.of(context).pop(),
        ),
        if (!_ready)
          AppButton(
            label: 'Querying AICTE databases...',
            icon: Icons.sync_rounded,
            color: AppColors.muted,
            onPressed: null,
          )
        else ...[
          AppButton(
            label: 'Grant Fast-Track RO Clearance',
            icon: Icons.rocket_launch_rounded,
            color: AppColors.emeraldDark,
            onPressed: deficient
                ? null
                : () => Navigator.of(context).pop(RuleEngineAction.fastTrack),
          ),
          AppButton(
            label: 'Lock Release & Mandate 2-Year Extension',
            icon: Icons.lock_clock_rounded,
            color: AppColors.orange,
            onPressed: deficient
                ? () => Navigator.of(
                    context,
                  ).pop(RuleEngineAction.mandateExtension)
                : null,
          ),
        ],
      ],
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InfoBanner(
            title: _ready
                ? (deficient
                      ? 'Release cannot be granted — $flags compliance flags detected'
                      : 'Zero-deficiency verified across all four databases')
                : 'Running automated scrutiny across AICTE databases',
            message: _ready
                ? (deficient
                      ? 'The rule engine has locked the release path. The Regional Officer may only mandate a two-year FDR extension until the flagged parameters are resolved.'
                      : 'All four compliance checks returned clean. Fast-track RO clearance is enabled and the application can be forwarded to AICTE Finance.')
                : 'Querying infrastructure, faculty salary, vigilance and project timeline records. This usually takes a few seconds.',
            icon: _ready
                ? (deficient
                      ? Icons.report_problem_rounded
                      : Icons.verified_user_rounded)
                : Icons.auto_awesome_rounded,
            color: _ready
                ? (deficient ? AppColors.red : AppColors.emeraldDark)
                : AppColors.indigo,
          ),
          const SizedBox(height: 14),
          if (!_ready)
            Column(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: const LinearProgressIndicator(
                    minHeight: 7,
                    backgroundColor: Color(0xFFE2E8F0),
                    valueColor: AlwaysStoppedAnimation(AppColors.indigo),
                  ),
                ),
                const SizedBox(height: 9),
                const Text(
                  'Querying Infrastructure → Faculty → CBI / Court → Approval Timeline...',
                  style: TextStyle(
                    fontSize: 9.4,
                    fontWeight: FontWeight.w700,
                    color: AppColors.indigo,
                  ),
                ),
              ],
            )
          else
            Column(
              children: [
                for (var index = 0; index < checks.length; index++) ...[
                  if (index > 0) const SizedBox(height: 8),
                  _RuleCheckTile(
                    label: checks[index].$1,
                    status: checks[index].$2,
                    detail: checks[index].$3,
                    icon: checks[index].$4,
                    color: checks[index].$5,
                  ),
                ],
              ],
            ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(11),
            decoration: BoxDecoration(
              color: AppColors.surfaceSoft,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.storage_rounded,
                  size: 15,
                  color: AppColors.muted,
                ),
                const SizedBox(width: 7),
                const Expanded(
                  child: Text(
                    'Sources: AICTE e-Kosh compliance DB • UGC faculty ledger • CBI vigilance feed • Project approval registry',
                    style: TextStyle(
                      fontSize: 8.6,
                      height: 1.4,
                      color: AppColors.muted,
                    ),
                  ),
                ),
                SoftChip(
                  label: _ready ? 'Audit sealed' : 'Querying',
                  icon: _ready
                      ? Icons.verified_rounded
                      : Icons.hourglass_top_rounded,
                  color: _ready ? AppColors.emeraldDark : AppColors.indigo,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RuleCheckTile extends StatelessWidget {
  const _RuleCheckTile({
    required this.label,
    required this.status,
    required this.detail,
    required this.icon,
    required this.color,
  });

  final String label;
  final String status;
  final String detail;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final healthy =
        status == 'PASS' || status == 'CLEAR' || status == 'WITHIN LIMIT';
    return Container(
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.035),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.16)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 16, color: color),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        label,
                        style: const TextStyle(
                          fontSize: 10.4,
                          fontWeight: FontWeight.w800,
                          color: AppColors.navyInk,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: healthy
                            ? const Color(0xFFECFDF5)
                            : const Color(0xFFFEF2F2),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(
                          color: healthy
                              ? const Color(0xFFA7F3D0)
                              : const Color(0xFFFECACA),
                        ),
                      ),
                      child: Text(
                        status,
                        style: TextStyle(
                          fontSize: 7.8,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.4,
                          color: healthy
                              ? AppColors.emeraldDark
                              : AppColors.red,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  detail,
                  style: const TextStyle(
                    fontSize: 8.8,
                    height: 1.4,
                    color: AppColors.muted,
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
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
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
              AppButton(
                label: 'View Tracker',
                icon: Icons.timeline_rounded,
                primary: false,
                dense: true,
                onPressed: onView,
              ),
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

// -----------------------------------------------------------------------------
// Finance HQ: automated 90 / 60 / 30-day Email + SMS dispatch engine
// -----------------------------------------------------------------------------

class _MaturityDispatchEnginePanel extends StatefulWidget {
  const _MaturityDispatchEnginePanel({required this.state});

  final PortalState state;

  @override
  State<_MaturityDispatchEnginePanel> createState() =>
      _MaturityDispatchEnginePanelState();
}

class _MaturityDispatchEnginePanelState
    extends State<_MaturityDispatchEnginePanel> {
  bool _working = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _autoScan());
  }

  Future<void> _autoScan() async {
    final state = widget.state;
    await state.fetchNotificationLogs(notify: false);
    final dispatched = await state.ensureAutomaticNotificationCheck();
    if (!mounted) return;
    setState(() {});
    if (dispatched > 0) {
      showAppToast(
        context,
        '📨 Automated maturity check complete • $dispatched official Email + '
        'SMS advisory bundle${dispatched == 1 ? '' : 's'} dispatched by the '
        'NIC-SMS / SMTP gateway.',
        icon: Icons.mark_email_read_rounded,
        color: AppColors.indigo,
      );
    }
  }

  Future<void> _runManualScan() async {
    if (_working) return;
    setState(() => _working = true);
    final dispatched = await widget.state.runMaturityNotificationScan();
    if (!mounted) return;
    setState(() => _working = false);
    showAppToast(
      context,
      dispatched > 0
          ? '⚡ 90/60/30-day scan complete • $dispatched Email + SMS advisory '
                'bundle${dispatched == 1 ? '' : 's'} dispatched to institute '
                'nodal officers and the Finance Bureau.'
          : '90/60/30-day scan complete • no qualifying FDRs required a fresh '
                'dispatch. Gateway ledger is up to date.',
      icon: dispatched > 0 ? Icons.campaign_rounded : Icons.fact_check_rounded,
      color: dispatched > 0 ? AppColors.indigo : AppColors.emeraldDark,
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final busy = _working || state.notificationScanBusy;
    return SectionCard(
      title:
          '📡 Automated Pre-Maturity Email & SMS Dispatch Engine (NIC-SMS / SMTP Gateway)',
      subtitle:
          'AICTE Finance Bureau • background scheduler armed on server startup '
          'and every 24 hours for the 90-day advisory, 60-day follow-up and '
          '30-day critical windows.',
      accentColor: AppColors.indigo,
      trailing: SoftChip(
        label: busy
            ? 'SCANNING GATEWAY'
            : state.notificationGatewayStatus == 'DISPATCHED'
            ? 'DISPATCHED'
            : '24H AUTO-CRON ACTIVE',
        icon: busy ? Icons.sync_rounded : Icons.verified_user_rounded,
        color: busy ? AppColors.orange : AppColors.emeraldDark,
      ),
      contentPadding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth;
              final columns = width >= 980
                  ? 3
                  : width >= 640
                  ? 2
                  : 1;
              final cardWidth = (width - 12 * (columns - 1)) / columns;
              return Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  SizedBox(
                    width: cardWidth,
                    child: _MilestoneWindowCard(
                      icon: Icons.event_available_rounded,
                      title: '90-Day Advisory Window',
                      count: state.notificationWithin90,
                      badge: 'ACTIVE',
                      description:
                          'FDRs maturing in 61–90 days receive the official '
                          'pre-maturity advisory with release and renewal guidance.',
                      color: AppColors.indigo,
                    ),
                  ),
                  SizedBox(
                    width: cardWidth,
                    child: _MilestoneWindowCard(
                      icon: Icons.notifications_active_rounded,
                      title: '60-Day Follow-Up Window',
                      count: state.notificationWithin60,
                      badge: 'ACTIVE',
                      description:
                          'FDRs maturing in 31–60 days receive a follow-up '
                          'reminder to confirm lien status and settlement intent.',
                      color: AppColors.orange,
                    ),
                  ),
                  SizedBox(
                    width: cardWidth,
                    child: _MilestoneWindowCard(
                      icon: Icons.crisis_alert_rounded,
                      title: '30-Day Critical Window',
                      count: state.notificationWithin30,
                      badge: 'URGENT AUTO-ALERT',
                      description:
                          'FDRs maturing within 30 days receive the final '
                          'notice to file a release application or 2-year renewal.',
                      color: AppColors.red,
                    ),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.indigo.withValues(alpha: 0.045),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(
                color: AppColors.indigo.withValues(alpha: 0.16),
              ),
            ),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final wide = constraints.maxWidth >= 900;
                final messaging = Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: AppColors.indigo.withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: busy
                          ? const Padding(
                              padding: EdgeInsets.all(8),
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: AppColors.indigo,
                              ),
                            )
                          : const Icon(
                              Icons.hub_rounded,
                              size: 18,
                              color: AppColors.indigo,
                            ),
                    ),
                    const SizedBox(width: 11),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'NIC-SMS / SMTP GATEWAY • EMAIL + SMS DELIVERY',
                            style: TextStyle(
                              fontSize: 8.6,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 0.75,
                              color: AppColors.indigo,
                            ),
                          ),
                          SizedBox(height: 3),
                          Text(
                            'Each dispatch is written to the immutable gateway '
                            'ledger and audit trail with the exact recipient '
                            'email, mobile number and official message text.',
                            style: TextStyle(
                              fontSize: 10.2,
                              height: 1.45,
                              color: AppColors.muted,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                );
                final button = AppButton(
                  label: '⚡ Run 90/60/30-Day Auto-Dispatch Scan Now',
                  icon: Icons.bolt_rounded,
                  color: AppColors.indigo,
                  onPressed: busy ? null : _runManualScan,
                );
                if (!wide) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      messaging,
                      const SizedBox(height: 11),
                      Align(alignment: Alignment.centerLeft, child: button),
                    ],
                  );
                }
                return Row(
                  children: [
                    Expanded(child: messaging),
                    const SizedBox(width: 16),
                    button,
                  ],
                );
              },
            ),
          ),
          const SizedBox(height: 16),
          _buildGatewayTable(context, state),
        ],
      ),
    );
  }

  Widget _buildGatewayTable(BuildContext context, PortalState state) {
    final logs = state.notificationLogs.take(25).toList();
    if (logs.isEmpty) {
      return const EmptyState(
        title: 'No Email / SMS advisories dispatched yet',
        message:
            'The 24-hour scheduler will dispatch automatically when an FDR '
            'enters the 90, 60 or 30-day maturity window. Use the manual scan '
            'button to run the engine immediately.',
        icon: Icons.mark_email_unread_rounded,
        color: AppColors.indigo,
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Icon(
              Icons.receipt_long_rounded,
              size: 15,
              color: AppColors.navy,
            ),
            const SizedBox(width: 6),
            const Expanded(
              child: Text(
                'DISPATCHED EMAIL & SMS GATEWAY LOG',
                style: TextStyle(
                  fontSize: 9.4,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.8,
                  color: AppColors.navyInk,
                ),
              ),
            ),
            Text(
              '${logs.length} ledger entr${logs.length == 1 ? 'y' : 'ies'}'
              '${logs.length >= 25 ? ' • showing latest 25' : ''}',
              style: const TextStyle(
                fontSize: 8.6,
                fontWeight: FontWeight.w700,
                color: AppColors.muted,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            border: Border.all(color: AppColors.border),
            borderRadius: BorderRadius.circular(4),
          ),
          clipBehavior: Clip.antiAlias,
          child: TableScroll(
            minWidth: 1450,
            child: DataTable(
              showCheckboxColumn: false,
              horizontalMargin: 16,
              columnSpacing: 18,
              headingRowHeight: 44,
              dataRowMinHeight: 66,
              dataRowMaxHeight: 84,
              headingRowColor: const WidgetStatePropertyAll(AppColors.navy),
              headingTextStyle: const TextStyle(
                fontSize: 8.8,
                fontWeight: FontWeight.w900,
                letterSpacing: 0.7,
                color: Colors.white,
              ),
              columns: const [
                DataColumn(label: Text('TIMESTAMP')),
                DataColumn(label: Text('FDR NUMBER')),
                DataColumn(label: Text('INSTITUTE NAME')),
                DataColumn(label: Text('MILESTONE')),
                DataColumn(label: Text('CHANNELS')),
                DataColumn(label: Text('RECIPIENT CONTACT')),
                DataColumn(label: Text('OFFICIAL MESSAGE')),
              ],
              rows: logs.asMap().entries.map((entry) {
                final rowIndex = entry.key;
                final log = entry.value;
                return DataRow(
                  color: portalRowColor(rowIndex),
                  cells: [
                    DataCell(
                      Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            formatDateTime(log.timestamp),
                            style: const TextStyle(
                              fontSize: 9.4,
                              fontWeight: FontWeight.w700,
                              color: AppColors.navyInk,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            log.isAutomatic
                                ? 'AUTO CRON SCHEDULER'
                                : 'FINANCE HQ MANUAL',
                            style: TextStyle(
                              fontSize: 7.4,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.35,
                              color: log.isAutomatic
                                  ? AppColors.emeraldDark
                                  : AppColors.indigo,
                            ),
                          ),
                        ],
                      ),
                    ),
                    DataCell(
                      Text(
                        log.fdrNumber,
                        style: const TextStyle(
                          fontSize: 10.2,
                          fontWeight: FontWeight.w900,
                          color: AppColors.navy,
                        ),
                      ),
                    ),
                    DataCell(
                      SizedBox(
                        width: 190,
                        child: Text(
                          log.instituteName,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 9.4,
                            height: 1.3,
                            color: AppColors.ink,
                          ),
                        ),
                      ),
                    ),
                    DataCell(_GatewayMilestoneBadge(log: log)),
                    DataCell(
                      Wrap(
                        spacing: 4,
                        runSpacing: 4,
                        children: [
                          if (log.channels.contains('EMAIL'))
                            const _GatewayChannelTag(
                              icon: Icons.mail_rounded,
                              label: 'EMAIL SENT',
                              color: AppColors.emeraldDark,
                            ),
                          if (log.channels.contains('SMS'))
                            const _GatewayChannelTag(
                              icon: Icons.sms_rounded,
                              label: 'SMS SENT',
                              color: AppColors.indigo,
                            ),
                        ],
                      ),
                    ),
                    DataCell(
                      SizedBox(
                        width: 178,
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              log.recipientEmail,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 8.8,
                                fontWeight: FontWeight.w600,
                                color: AppColors.ink,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              log.recipientMobile,
                              style: const TextStyle(
                                fontSize: 8.8,
                                fontWeight: FontWeight.w600,
                                color: AppColors.muted,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    DataCell(
                      AppButton(
                        label: 'View Official Message',
                        icon: Icons.visibility_rounded,
                        primary: false,
                        dense: true,
                        color: AppColors.navy,
                        onPressed: () =>
                            showMaturityNotificationPreview(context, log),
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

class _MilestoneWindowCard extends StatelessWidget {
  const _MilestoneWindowCard({
    required this.icon,
    required this.title,
    required this.count,
    required this.badge,
    required this.description,
    required this.color,
  });

  final IconData icon;
  final String title;
  final int count;
  final String badge;
  final String description;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: const Color(0xFFCBD5E1)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(height: 4, color: color),
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.09),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(
                          color: color.withValues(alpha: 0.16),
                        ),
                      ),
                      child: Icon(icon, size: 17, color: color),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 96),
                          child: Text(
                            badge,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.right,
                            style: TextStyle(
                              fontSize: 7,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 0.55,
                              color: color,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 11),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '$count',
                      style: TextStyle(
                        fontSize: 27,
                        fontWeight: FontWeight.w900,
                        height: 1,
                        letterSpacing: -0.6,
                        color: color,
                      ),
                    ),
                    const SizedBox(width: 5),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 3),
                      child: Text(
                        count == 1 ? 'FDR' : 'FDRs',
                        style: const TextStyle(
                          fontSize: 8.6,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.45,
                          color: AppColors.muted,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  title.toUpperCase(),
                  style: const TextStyle(
                    fontSize: 8.8,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.55,
                    color: AppColors.navyInk,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  description,
                  style: const TextStyle(
                    fontSize: 9.2,
                    height: 1.4,
                    color: AppColors.muted,
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

class _GatewayMilestoneBadge extends StatelessWidget {
  const _GatewayMilestoneBadge({required this.log});

  final MaturityNotificationLog log;

  @override
  Widget build(BuildContext context) {
    final color = log.milestoneColor;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(3),
        border: Border.all(color: color.withValues(alpha: 0.24)),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${log.milestoneShort} WINDOW',
            style: TextStyle(
              fontSize: 8,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.5,
              color: color,
            ),
          ),
          const SizedBox(height: 1),
          Text(
            log.daysToMaturity == null
                ? log.milestoneLabel
                : '${log.daysToMaturity} days left',
            style: TextStyle(
              fontSize: 7.4,
              fontWeight: FontWeight.w600,
              color: color.withValues(alpha: 0.85),
            ),
          ),
        ],
      ),
    );
  }
}

class _GatewayChannelTag extends StatelessWidget {
  const _GatewayChannelTag({
    required this.icon,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(3),
        border: Border.all(color: color.withValues(alpha: 0.22)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 10, color: color),
          const SizedBox(width: 3),
          Text(
            label,
            style: TextStyle(
              fontSize: 7.2,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.35,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

Future<void> showMaturityNotificationPreview(
  BuildContext context,
  MaturityNotificationLog log,
) {
  return showDialog<void>(
    context: context,
    barrierColor: AppColors.navyInk.withValues(alpha: 0.50),
    builder: (dialogContext) => PortalDialogFrame(
      title: 'Official ${log.milestoneLabel} Advisory',
      icon: '✉️',
      eyebrow: 'NIC-SMS / SMTP GATEWAY • DELIVERY PROOF',
      subtitle:
          'Exact Email and SMS template dispatched to the institute nodal '
          'officer, with a copy marked to the AICTE Finance Bureau.',
      maxWidth: 860,
      accent: log.milestoneColor,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              SoftChip(
                label: log.fdrNumber,
                icon: Icons.account_balance_rounded,
                color: AppColors.navy,
              ),
              SoftChip(
                label: '${log.milestoneShort} MILESTONE',
                icon: Icons.timer_rounded,
                color: log.milestoneColor,
              ),
              const SoftChip(
                label: 'EMAIL + SMS • DELIVERED',
                icon: Icons.mark_email_read_rounded,
                color: AppColors.emeraldDark,
              ),
              SoftChip(
                label: log.isAutomatic ? 'AUTO CRON' : 'FINANCE HQ MANUAL',
                icon: Icons.verified_user_rounded,
                color: AppColors.indigo,
              ),
            ],
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth >= 620;
              final width = wide
                  ? (constraints.maxWidth - 10) / 2
                  : constraints.maxWidth;
              return Wrap(
                spacing: 10,
                runSpacing: 8,
                children: [
                  SizedBox(
                    width: width,
                    child: _GatewayDetailRow(
                      label: 'Recipient Email',
                      value: log.recipientEmail,
                      icon: Icons.alternate_email_rounded,
                    ),
                  ),
                  SizedBox(
                    width: width,
                    child: _GatewayDetailRow(
                      label: 'Recipient Mobile',
                      value: log.recipientMobile,
                      icon: Icons.phone_android_rounded,
                    ),
                  ),
                  SizedBox(
                    width: width,
                    child: _GatewayDetailRow(
                      label: 'Institute',
                      value: log.instituteName,
                      icon: Icons.school_rounded,
                    ),
                  ),
                  SizedBox(
                    width: width,
                    child: _GatewayDetailRow(
                      label: 'Dispatched On',
                      value: formatDateTime(log.timestamp),
                      icon: Icons.schedule_rounded,
                    ),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFFFFFDF5),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: const Color(0xFFFCD34D)),
            ),
            child: SelectableText(
              log.messagePreview.isEmpty
                  ? 'No message body was recorded for this gateway entry.'
                  : log.messagePreview,
              style: const TextStyle(
                fontSize: 10.4,
                height: 1.55,
                fontFamily: 'monospace',
                color: AppColors.ink,
              ),
            ),
          ),
          const SizedBox(height: 10),
          const Text(
            'This is a system-generated government communication. The delivery '
            'reference and SHA-256 audit hash are retained in the AICTE '
            'notification ledger.',
            style: TextStyle(
              fontSize: 8.8,
              height: 1.45,
              fontStyle: FontStyle.italic,
              color: AppColors.muted,
            ),
          ),
        ],
      ),
      actions: [
        AppButton(
          label: 'Close Preview',
          icon: Icons.close_rounded,
          dense: true,
          onPressed: () => Navigator.of(dialogContext).pop(),
        ),
      ],
    ),
  );
}

class _GatewayDetailRow extends StatelessWidget {
  const _GatewayDetailRow({
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.surfaceSoft,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Icon(icon, size: 14, color: AppColors.navy),
          const SizedBox(width: 7),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label.toUpperCase(),
                  style: const TextStyle(
                    fontSize: 7.2,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.5,
                    color: AppColors.muted,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 9.6,
                    fontWeight: FontWeight.w700,
                    color: AppColors.navyInk,
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
            label: 'Simulate Daily Maturity Cron Job',
            icon: Icons.schedule_send_rounded,
            primary: false,
            color: AppColors.orange,
            onPressed: () => _simulateMaturityCron(context, state),
          ),
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
        _MaturityDispatchEnginePanel(state: state),
        InfoBanner(
          title: state.maturityCronRan
              ? 'Daily maturity cron active'
              : 'Daily maturity cron ready',
          message:
              '${state.overdueRecords.length} FDR${state.overdueRecords.length == 1 ? '' : 's'} overdue and ${state.dueSoonRecords.length} due within 30 days. The cron engine tracks the 8-to-10 year lock-in and dispatches portal, email and SMS alerts.${state.lastCronRun == null ? ' Run the cron simulation to refresh the watchlist.' : ' Last run ${formatDateTime(state.lastCronRun!)}.'}',
          icon: Icons.schedule_send_rounded,
          color: AppColors.orange,
          trailing: SoftChip(
            label: state.maturityCronRan
                ? 'Cron runs: ${state.maturityCronRuns}'
                : 'Not yet run',
            icon: state.maturityCronRan
                ? Icons.check_circle_rounded
                : Icons.hourglass_top_rounded,
            color: state.maturityCronRan
                ? AppColors.emeraldDark
                : AppColors.orange,
          ),
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
        _EnocRegistryCard(state: state),
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
                          label: 'Process Settlement & Deduct Penalty',
                          icon: Icons.calculate_rounded,
                          dense: true,
                          color: AppColors.gold,
                          onPressed: onPartialRelease,
                        ),
                        AppButton(
                          label: 'Execute Full Forfeiture (Encash to AICTE)',
                          icon: Icons.gavel_rounded,
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
    title: 'Execute full forfeiture?',
    message:
        '${record.id} will be fully encashed to the AICTE account. No funds will be released to ${record.instituteName}. This closes the FDR lifecycle and cannot be undone.',
    confirmLabel: 'Execute Full Forfeiture',
    confirmColor: AppColors.red,
    icon: Icons.gavel_rounded,
    extra: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _DialogAmountBox(
          label: 'Amount to be forfeited',
          value: inr(record.amount),
          helper: '${record.instituteName}\nAICTE Finance Bureau',
        ),
        const SizedBox(height: 10),
        _DialogAmountBox(
          label: 'Net refund to institute',
          value: inr(0),
          helper: 'Full forfeiture • ₹0 refundable',
        ),
      ],
    ),
  );
  if (!confirmed || !context.mounted) return;
  state.forfeitFdr(record);
  showAppToast(
    context,
    '${record.id} forfeited and encashed to the AICTE account. Net refund: ₹0.',
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
      title: 'Settlement & Penalty Calculator',
      subtitle: '${record.id} • ${record.instituteName} • ${record.bankName}',
      icon: '₹',
      maxWidth: 680,
      accent: AppColors.gold,
      bodyPadding: const EdgeInsets.all(20),
      actions: [
        AppButton(
          label: 'Cancel',
          primary: false,
          onPressed: () => Navigator.of(context).pop(),
        ),
        AppButton(
          label: 'Approve Partial Release & Deduct Penalty',
          icon: Icons.content_cut_rounded,
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
            title: 'Dynamic penalty deduction',
            message:
                'Set the liquidated damages to be deducted before issuing the e-NOC. The net refund is routed to the bank settlement queue and the deduction is credited to the AICTE corpus.',
            icon: Icons.calculate_rounded,
            color: AppColors.gold,
          ),
          const SizedBox(height: 15),
          _DialogAmountBox(
            label: 'Original deposit amount',
            value: inr(record.amount),
            helper:
                '${record.instituteName}\nAssessed penalty ${inr(record.penalty)}',
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              const Expanded(
                child: Text(
                  'LIQUIDATED DAMAGES / PENALTY DEDUCTION',
                  style: TextStyle(
                    fontSize: 8.2,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.7,
                    color: AppColors.muted,
                  ),
                ),
              ),
              Text(
                inr(_deduction),
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                  color: AppColors.orange,
                ),
              ),
            ],
          ),
          Slider(
            value: _deduction.clamp(0.0, record.amount).toDouble(),
            min: 0,
            max: record.amount <= 0 ? 1 : record.amount,
            divisions: 100,
            label: inr(_deduction),
            activeColor: AppColors.orange,
            inactiveColor: AppColors.orange.withValues(alpha: 0.16),
            onChanged: (value) {
              setState(() {
                _controller.text = value.round().toString();
              });
            },
          ),
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
              helperText:
                  'Assessed penalty: ${inr(record.penalty)} • Drag the slider or type an exact amount',
            ),
          ),
          const SizedBox(height: 14),
          LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth >= 480
                  ? (constraints.maxWidth - 10) / 2
                  : constraints.maxWidth;
              return Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  SizedBox(
                    width: width,
                    child: _DialogAmountBox(
                      label: 'Net refundable to institute',
                      value: inr(net),
                      helper: 'Credited to the institute settlement account',
                    ),
                  ),
                  SizedBox(
                    width: width,
                    child: _DialogAmountBox(
                      label: 'Amount credited to AICTE corpus',
                      value: inr(_deduction),
                      helper: 'Liquidated damages / penalty recovery',
                    ),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(13),
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
                  '${inr(record.amount)} deposit − ${inr(_deduction)} penalty = ${inr(net)} net refund',
                  style: const TextStyle(fontSize: 9.2, color: AppColors.muted),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'Approving this settlement sets the FDR status to "Partial Release Approved". The bank settlement desk will disburse the net refund and the deduction is recorded in the national penalty ledger.',
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
                  minWidth: 1650,
                  child: DataTable(
                    showCheckboxColumn: false,
                    horizontalMargin: 20,
                    columnSpacing: 22,
                    headingRowHeight: 46,
                    dataRowMinHeight: 66,
                    dataRowMaxHeight: 82,
                    headingRowColor: const WidgetStatePropertyAll(
                      AppColors.navy,
                    ),
                    headingTextStyle: const TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.8,
                      color: Colors.white,
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
                      DataColumn(label: Text('URGENCY')),
                      DataColumn(label: Text('STATUS')),
                      DataColumn(label: Text('e-NOC / UPDATED')),
                    ],
                    rows: records.asMap().entries.map((entry) {
                      final rowIndex = entry.key;
                      final record = entry.value;
                      return DataRow(
                        color: portalRowColor(rowIndex),
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
                          DataCell(MaturityUrgencyChip(record: record)),
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

// -----------------------------------------------------------------------------
// Phase 3: Tamper-proof digital e-NOC certificate & QR verification
// -----------------------------------------------------------------------------

/// Deterministic simulated cryptographic digest derived from the release
/// order payload. Used by the QR widget, the certificate footer and the bank
/// node's signature check.
String enocVerificationHash(FDRRecord record) {
  final source =
      '${record.enocNumber ?? record.id}|${record.id}|'
      '${record.amount.toStringAsFixed(0)}|${record.instituteId}|AICTE-BLOCKCHAIN';
  var hash = 0x811C9DC5;
  for (final unit in source.codeUnits) {
    hash ^= unit;
    hash = (hash * 0x01000193) & 0xFFFFFFFF;
  }
  final chunks = <String>[];
  var state = hash;
  for (var index = 0; index < 4; index++) {
    state = (state * 1664525 + 1013904223) & 0xFFFFFFFF;
    chunks.add(state.toRadixString(16).toUpperCase().padLeft(8, '0'));
  }
  return 'SHA-256 ${chunks.join(' ')}';
}

Future<void> showEnocDialog(
  BuildContext context,
  PortalState state,
  FDRRecord record,
) {
  return showDialog<void>(
    context: context,
    barrierColor: AppColors.navyInk.withValues(alpha: 0.55),
    builder: (dialogContext) => _EnocDialog(record: record),
  );
}

class _EnocDialog extends StatefulWidget {
  const _EnocDialog({required this.record});

  final FDRRecord record;

  @override
  State<_EnocDialog> createState() => _EnocDialogState();
}

class _EnocDialogState extends State<_EnocDialog> {
  String? _feedback;
  bool _downloadFeedback = false;

  @override
  Widget build(BuildContext context) {
    final record = widget.record;
    return PortalDialogFrame(
      title: 'Digital No Objection Certificate (e-NOC)',
      eyebrow: 'AICTE • Official release order',
      subtitle:
          'Tamper-proof authorisation generated by the AICTE Finance Bureau and anchored to the portal ledger.',
      icon: '✓',
      accent: AppColors.emerald,
      maxWidth: 900,
      bodyPadding: const EdgeInsets.all(18),
      actions: [
        AppButton(
          label: 'Simulate PDF Download',
          icon: Icons.picture_as_pdf_rounded,
          color: AppColors.gold,
          onPressed: () => setState(() {
            _downloadFeedback = true;
            _feedback =
                'e-NOC ${record.enocNumber ?? '—'} downloaded as a digitally signed PDF (demo).';
          }),
        ),
        AppButton(
          label: 'Verify QR Hash',
          icon: Icons.verified_user_rounded,
          color: AppColors.emeraldDark,
          onPressed: () => setState(() {
            _downloadFeedback = false;
            _feedback =
                'QR hash verified against the AICTE blockchain registry: authentic release order for ${record.id}.';
          }),
        ),
        AppButton(
          label: 'Close',
          primary: false,
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _EnocCertificateBody(record: record),
          if (_feedback != null) ...[
            const SizedBox(height: 12),
            _EnocActionFeedback(
              message: _feedback!,
              color: _downloadFeedback ? AppColors.gold : AppColors.emeraldDark,
              icon: _downloadFeedback
                  ? Icons.download_done_rounded
                  : Icons.verified_rounded,
            ),
          ],
        ],
      ),
    );
  }
}

class _EnocActionFeedback extends StatelessWidget {
  const _EnocActionFeedback({
    required this.message,
    required this.color,
    required this.icon,
  });

  final String message;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.32)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 15, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                fontSize: 9.4,
                fontWeight: FontWeight.w700,
                height: 1.45,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EnocCertificateBody extends StatelessWidget {
  const _EnocCertificateBody({required this.record});

  final FDRRecord record;

  @override
  Widget build(BuildContext context) {
    final netAmount = record.releasedAmount ?? record.netPayable;
    final issuedAt = record.releasedAt ?? record.lastUpdated;
    final hash = enocVerificationHash(record);

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFFFFDF6),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppColors.gold.withValues(alpha: 0.45),
          width: 1.4,
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Stack(
          children: [
            Positioned(
              right: -26,
              top: -18,
              child: Icon(
                Icons.account_balance_rounded,
                size: 190,
                color: AppColors.navy.withValues(alpha: 0.05),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 58,
                        height: 58,
                        decoration: BoxDecoration(
                          color: AppColors.navy,
                          shape: BoxShape.circle,
                          border: Border.all(color: AppColors.gold, width: 2),
                        ),
                        alignment: Alignment.center,
                        child: const Icon(
                          Icons.account_balance_rounded,
                          color: AppColors.gold,
                          size: 29,
                        ),
                      ),
                      const SizedBox(width: 13),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'ALL INDIA COUNCIL FOR TECHNICAL EDUCATION',
                              style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 0.45,
                                color: AppColors.navyInk,
                                height: 1.25,
                              ),
                            ),
                            const SizedBox(height: 3),
                            const Text(
                              'DIGITAL NO OBJECTION CERTIFICATE (e-NOC)',
                              style: TextStyle(
                                fontSize: 9.6,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.9,
                                color: AppColors.gold,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'Certificate Reference: ${record.enocNumber ?? '—'}',
                              style: const TextStyle(
                                fontSize: 9.2,
                                fontWeight: FontWeight.w700,
                                color: AppColors.navyInk,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Issued: ${formatDateTime(issuedAt)} • Statutory security-deposit release authorisation',
                              style: const TextStyle(
                                fontSize: 8.6,
                                color: AppColors.muted,
                                height: 1.4,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Container(
                    height: 2,
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          AppColors.gold,
                          AppColors.navy,
                          AppColors.gold,
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final wide = constraints.maxWidth >= 560;
                      final width = wide
                          ? (constraints.maxWidth - 12) / 2
                          : constraints.maxWidth;
                      return Wrap(
                        spacing: 12,
                        runSpacing: 10,
                        children: [
                          SizedBox(
                            width: width,
                            child: _EnocField(
                              label: 'INSTITUTE NAME',
                              value: record.instituteName,
                            ),
                          ),
                          SizedBox(
                            width: width,
                            child: _EnocField(
                              label: 'AICTE PERMANENT ID',
                              value: record.instituteId,
                            ),
                          ),
                          SizedBox(
                            width: width,
                            child: _EnocField(
                              label: 'ISSUING BANK & IFSC',
                              value: '${record.bankName} • ${record.ifsc}',
                            ),
                          ),
                          SizedBox(
                            width: width,
                            child: _EnocField(
                              label: 'FDR NUMBER',
                              value: record.id,
                            ),
                          ),
                          SizedBox(
                            width: width,
                            child: _EnocField(
                              label: 'ORIGINAL PRINCIPAL AMOUNT',
                              value: inr(record.amount),
                            ),
                          ),
                          SizedBox(
                            width: width,
                            child: _EnocField(
                              label: 'PENALTY DEDUCTED',
                              value: record.deductedPenalty > 0
                                  ? inr(record.deductedPenalty)
                                  : 'Nil',
                              valueColor: record.deductedPenalty > 0
                                  ? AppColors.orange
                                  : AppColors.emeraldDark,
                            ),
                          ),
                          SizedBox(
                            width: width,
                            child: _EnocField(
                              label: 'PROGRAMME',
                              value: record.program,
                            ),
                          ),
                          SizedBox(
                            width: width,
                            child: _EnocField(
                              label: 'JURISDICTION',
                              value: '${record.region} Regional Office',
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.fromLTRB(14, 12, 14, 13),
                    decoration: BoxDecoration(
                      color: AppColors.emerald.withValues(alpha: 0.09),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: AppColors.emerald.withValues(alpha: 0.32),
                      ),
                    ),
                    child: Wrap(
                      spacing: 12,
                      runSpacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      alignment: WrapAlignment.spaceBetween,
                      children: [
                        const Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'NET AMOUNT AUTHORIZED FOR RELEASE TO INSTITUTE',
                              style: TextStyle(
                                fontSize: 8.2,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 0.7,
                                color: AppColors.emeraldDark,
                              ),
                            ),
                            SizedBox(height: 3),
                            Text(
                              'After adjustment of all statutory deductions',
                              style: TextStyle(
                                fontSize: 8.4,
                                color: AppColors.muted,
                              ),
                            ),
                          ],
                        ),
                        Text(
                          inr(netAmount),
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w900,
                            letterSpacing: -0.5,
                            color: AppColors.emeraldDark,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final stacked = constraints.maxWidth < 560;
                      final qrBlock = Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          QrVerificationCode(seed: hash, size: 122),
                          const SizedBox(height: 7),
                          const SizedBox(
                            width: 168,
                            child: Text(
                              'Scan to Verify Authenticity on AICTE Blockchain/Portal',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 7.8,
                                fontWeight: FontWeight.w700,
                                color: AppColors.muted,
                                height: 1.35,
                              ),
                            ),
                          ),
                        ],
                      );
                      final verification = Container(
                        padding: const EdgeInsets.all(13),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: AppColors.emerald.withValues(alpha: 0.35),
                          ),
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
                                    color: AppColors.emerald.withValues(
                                      alpha: 0.12,
                                    ),
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(
                                    Icons.verified_rounded,
                                    size: 17,
                                    color: AppColors.emeraldDark,
                                  ),
                                ),
                                const SizedBox(width: 9),
                                const Expanded(
                                  child: Text(
                                    'Digitally Signed by Member Secretary & Finance Bureau, AICTE HQ',
                                    style: TextStyle(
                                      fontSize: 9,
                                      fontWeight: FontWeight.w800,
                                      color: AppColors.emeraldDark,
                                      height: 1.35,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 9),
                            const Text(
                              'BLOCKCHAIN ANCHOR',
                              style: TextStyle(
                                fontSize: 7.4,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 0.8,
                                color: AppColors.muted,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              hash,
                              style: const TextStyle(
                                fontSize: 8,
                                fontFamily: 'monospace',
                                color: AppColors.navyInk,
                                height: 1.45,
                              ),
                            ),
                            const SizedBox(height: 7),
                            Text(
                              'Certificate ID ${record.enocNumber ?? '—'} • '
                              'Issued ${formatDate(issuedAt)} • '
                              'Verify at ekosh.aicte-india.org/verify',
                              style: const TextStyle(
                                fontSize: 8,
                                color: AppColors.muted,
                                height: 1.4,
                              ),
                            ),
                          ],
                        ),
                      );
                      if (stacked) {
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            qrBlock,
                            const SizedBox(height: 12),
                            verification,
                          ],
                        );
                      }
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          qrBlock,
                          const SizedBox(width: 16),
                          Expanded(child: verification),
                        ],
                      );
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EnocField extends StatelessWidget {
  const _EnocField({
    required this.label,
    required this.value,
    this.valueColor = AppColors.navyInk,
  });

  final String label;
  final String value;
  final Color valueColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.gold.withValues(alpha: 0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 7.4,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.7,
              color: AppColors.muted,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: TextStyle(
              fontSize: 10.2,
              fontWeight: FontWeight.w700,
              color: valueColor,
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }
}

/// Deterministic pseudo-QR block rendered with a custom painter. It is not a
/// scannable QR (offline demo) but visually mirrors a high-contrast QR pattern.
class QrVerificationCode extends StatelessWidget {
  const QrVerificationCode({super.key, required this.seed, this.size = 120});

  final String seed;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(7),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AppColors.navyInk, width: 1.4),
      ),
      child: CustomPaint(size: Size.square(size), painter: _QrPainter(seed)),
    );
  }
}

class _QrPainter extends CustomPainter {
  _QrPainter(this.seed);

  final String seed;
  static const int _modules = 29;

  @override
  void paint(Canvas canvas, Size size) {
    final cell = size.width / _modules;
    final paint = Paint()..color = AppColors.navyInk;
    final matrix = _buildMatrix();

    for (var row = 0; row < _modules; row++) {
      for (var col = 0; col < _modules; col++) {
        if (!matrix[row][col]) continue;
        canvas.drawRect(
          Rect.fromLTWH(col * cell, row * cell, cell * 0.92, cell * 0.92),
          paint,
        );
      }
    }
  }

  List<List<bool>> _buildMatrix() {
    final matrix = List.generate(
      _modules,
      (_) => List<bool>.filled(_modules, false),
    );
    var state = 0x9E3779B9;
    for (final unit in seed.codeUnits) {
      state = (state ^ unit) & 0xFFFFFFFF;
      state = (state * 1103515245 + 12345) & 0x7FFFFFFF;
    }
    for (var row = 0; row < _modules; row++) {
      for (var col = 0; col < _modules; col++) {
        state = (state * 1103515245 + 12345) & 0x7FFFFFFF;
        matrix[row][col] = ((state >> 17) & 1) == 1;
      }
    }
    // Timing patterns
    for (var index = 8; index < _modules - 8; index++) {
      matrix[6][index] = index.isEven;
      matrix[index][6] = index.isEven;
    }
    // Finder patterns (top-left, top-right, bottom-left)
    void finder(int row, int col) {
      for (var r = 0; r < 7; r++) {
        for (var c = 0; c < 7; c++) {
          final border = r == 0 || r == 6 || c == 0 || c == 6;
          final core = r >= 2 && r <= 4 && c >= 2 && c <= 4;
          matrix[row + r][col + c] = border || core;
        }
      }
      for (var r = -1; r <= 7; r++) {
        for (var c = -1; c <= 7; c++) {
          final rr = row + r;
          final cc = col + c;
          if (rr < 0 || rr >= _modules || cc < 0 || cc >= _modules) continue;
          if (r == -1 || r == 7 || c == -1 || c == 7) {
            matrix[rr][cc] = false;
          }
        }
      }
    }

    finder(1, 1);
    finder(1, _modules - 8);
    finder(_modules - 8, 1);
    return matrix;
  }

  @override
  bool shouldRepaint(covariant _QrPainter oldDelegate) =>
      oldDelegate.seed != seed;
}

Future<bool> showEnocScanDialog(BuildContext context, FDRRecord record) async {
  final result = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    barrierColor: AppColors.navyInk.withValues(alpha: 0.55),
    builder: (dialogContext) => _EnocScanDialog(record: record),
  );
  return result ?? false;
}

class _EnocScanDialog extends StatefulWidget {
  const _EnocScanDialog({required this.record});

  final FDRRecord record;

  @override
  State<_EnocScanDialog> createState() => _EnocScanDialogState();
}

class _EnocScanDialogState extends State<_EnocScanDialog> {
  Timer? _timer;
  bool _verified = false;

  @override
  void initState() {
    super.initState();
    _timer = Timer(const Duration(seconds: 1), () {
      if (!mounted) return;
      setState(() => _verified = true);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hash = enocVerificationHash(widget.record);
    return Dialog(
      insetPadding: const EdgeInsets.all(22),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      backgroundColor: Colors.white,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 470),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 20, 22, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: AppColors.navy.withValues(alpha: 0.07),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.qr_code_scanner_rounded,
                      color: AppColors.navy,
                      size: 21,
                    ),
                  ),
                  const SizedBox(width: 11),
                  const Expanded(
                    child: Text(
                      'Bank Node QR Verification',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: AppColors.navyInk,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 240),
                child: _verified
                    ? Column(
                        key: const ValueKey('verified'),
                        children: [
                          Container(
                            width: 62,
                            height: 62,
                            decoration: BoxDecoration(
                              color: AppColors.emerald.withValues(alpha: 0.12),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.verified_rounded,
                              color: AppColors.emeraldDark,
                              size: 34,
                            ),
                          ),
                          const SizedBox(height: 12),
                          const Text(
                            'e-NOC Signature Verified: Authentic AICTE Release Order',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                              color: AppColors.emeraldDark,
                              height: 1.4,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            hash,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 8,
                              fontFamily: 'monospace',
                              color: AppColors.muted,
                              height: 1.45,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '${widget.record.enocNumber ?? '—'} • ${widget.record.instituteName}',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 9,
                              color: AppColors.muted,
                              height: 1.4,
                            ),
                          ),
                        ],
                      )
                    : Column(
                        key: const ValueKey('scanning'),
                        children: [
                          const SizedBox(
                            width: 46,
                            height: 46,
                            child: CircularProgressIndicator(
                              strokeWidth: 3.4,
                              color: AppColors.indigo,
                            ),
                          ),
                          const SizedBox(height: 14),
                          const Text(
                            'Decoding e-NOC QR • verifying cryptographic hash…',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: AppColors.navyInk,
                              height: 1.45,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            widget.record.enocNumber ?? '—',
                            style: const TextStyle(
                              fontSize: 8.6,
                              color: AppColors.muted,
                            ),
                          ),
                        ],
                      ),
              ),
              const SizedBox(height: 18),
              Wrap(
                alignment: WrapAlignment.end,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 8,
                runSpacing: 8,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    child: const Text(
                      'Cancel',
                      style: TextStyle(
                        fontSize: 11.5,
                        color: AppColors.muted,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  FilledButton.icon(
                    onPressed: _verified
                        ? () => Navigator.of(context).pop(true)
                        : null,
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.emeraldDark,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 11,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(9),
                      ),
                    ),
                    icon: const Icon(Icons.lock_open_rounded, size: 15),
                    label: const Text(
                      'Enable Disbursement',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BankReleaseActions extends StatefulWidget {
  const _BankReleaseActions({
    required this.record,
    required this.state,
    required this.onDisburse,
  });

  final FDRRecord record;
  final PortalState state;
  final VoidCallback onDisburse;

  @override
  State<_BankReleaseActions> createState() => _BankReleaseActionsState();
}

class _BankReleaseActionsState extends State<_BankReleaseActions> {
  bool _verified = false;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppButton(
          label: 'View / Download Digital e-NOC',
          icon: Icons.qr_code_2_rounded,
          primary: false,
          dense: true,
          color: AppColors.emeraldDark,
          onPressed: () => showEnocDialog(context, widget.state, widget.record),
        ),
        const SizedBox(height: 9),
        if (!_verified)
          AppButton(
            label: 'Scan & Verify e-NOC QR',
            icon: Icons.qr_code_scanner_rounded,
            color: AppColors.indigo,
            onPressed: () async {
              final verified = await showEnocScanDialog(context, widget.record);
              if (!verified || !mounted || !context.mounted) return;
              setState(() => _verified = true);
              showAppToast(
                context,
                'e-NOC Signature Verified: Authentic AICTE Release Order',
                icon: Icons.verified_user_rounded,
                color: AppColors.emeraldDark,
              );
            },
          )
        else ...[
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.emerald.withValues(alpha: 0.07),
              borderRadius: BorderRadius.circular(9),
              border: Border.all(
                color: AppColors.emerald.withValues(alpha: 0.26),
              ),
            ),
            child: const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.verified_rounded,
                  size: 15,
                  color: AppColors.emeraldDark,
                ),
                SizedBox(width: 7),
                Expanded(
                  child: Text(
                    'e-NOC Signature Verified: Authentic AICTE Release Order',
                    style: TextStyle(
                      fontSize: 8.6,
                      fontWeight: FontWeight.w700,
                      color: AppColors.emeraldDark,
                      height: 1.35,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 9),
          AppButton(
            label: 'Release Lien & Disburse Funds to Institute Account',
            icon: Icons.payments_rounded,
            color: AppColors.emeraldDark,
            onPressed: widget.onDisburse,
          ),
        ],
      ],
    );
  }
}

// -----------------------------------------------------------------------------
// Phase 3: "Ask e-Kosh AI" context-aware RAG assistant
// -----------------------------------------------------------------------------

class AskEkoshAiFab extends StatefulWidget {
  const AskEkoshAiFab({super.key, required this.state});

  final PortalState state;

  @override
  State<AskEkoshAiFab> createState() => _AskEkoshAiFabState();
}

class _AskEkoshAiFabState extends State<AskEkoshAiFab> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(30),
          boxShadow: [
            BoxShadow(
              color: AppColors.indigo.withValues(alpha: _hovered ? 0.48 : 0.34),
              blurRadius: _hovered ? 30 : 22,
              spreadRadius: _hovered ? 5 : 2,
              offset: const Offset(0, 8),
            ),
            BoxShadow(
              color: AppColors.gold.withValues(alpha: 0.28),
              blurRadius: 16,
              spreadRadius: 1,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(30),
          child: InkWell(
            borderRadius: BorderRadius.circular(30),
            onTap: () => openEkoshAiDrawer(context, widget.state),
            child: Container(
              padding: const EdgeInsets.fromLTRB(16, 12, 19, 12),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [AppColors.navy, AppColors.indigo],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(30),
                border: Border.all(
                  color: AppColors.gold.withValues(alpha: 0.58),
                  width: 1.2,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.14),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: AppColors.gold.withValues(alpha: 0.55),
                      ),
                    ),
                    child: const Icon(
                      Icons.auto_awesome_rounded,
                      size: 17,
                      color: AppColors.gold,
                    ),
                  ),
                  const SizedBox(width: 10),
                  const Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Ask e-Kosh AI',
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.25,
                          color: Colors.white,
                        ),
                      ),
                      SizedBox(height: 1),
                      Text(
                        'Gemini RAG • Live DB',
                        style: TextStyle(
                          fontSize: 7.6,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.3,
                          color: Color(0xFFC7D2FE),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(width: 9),
                  Container(
                    width: 6,
                    height: 6,
                    decoration: const BoxDecoration(
                      color: AppColors.emerald,
                      shape: BoxShape.circle,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

Future<void> openEkoshAiDrawer(BuildContext context, PortalState state) {
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Ask e-Kosh AI',
    barrierColor: AppColors.navyInk.withValues(alpha: 0.48),
    transitionDuration: const Duration(milliseconds: 260),
    pageBuilder: (dialogContext, _, _) => _EkoshAiDrawer(state: state),
    transitionBuilder: (dialogContext, animation, secondary, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );
      return SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(1, 0),
          end: Offset.zero,
        ).animate(curved),
        child: child,
      );
    },
  );
}

class _ChatMessage {
  _ChatMessage({
    required this.author,
    required this.text,
    required this.isUser,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  final String author;
  final String text;
  final bool isUser;
  final DateTime timestamp;
}

class _EkoshAiDrawer extends StatefulWidget {
  const _EkoshAiDrawer({required this.state});

  final PortalState state;

  @override
  State<_EkoshAiDrawer> createState() => _EkoshAiDrawerState();
}

class _EkoshAiDrawerState extends State<_EkoshAiDrawer> {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final List<_ChatMessage> _messages = [];
  bool _thinking = false;

  static const _quickPrompts = <String>[
    'Check live status of my FDRs',
    'Calculate FDR for new Engineering College',
    'What happens if project time exceeds limit? (Tanglish)',
    'Show total corpus & penalty summary',
  ];

  @override
  void initState() {
    super.initState();
    _messages.add(
      _ChatMessage(
        author: 'e-Kosh AI',
        text:
            'Vanakkam! I am e-Kosh AI, the AICTE security-deposit assistant. '
            'I read the live portal database, so answers always match the '
            'current dashboard state.\n\n'
            'Right now I can see ${widget.state.records.length} FDR records '
            'with a national corpus of ${inrCompact(widget.state.nationalCorpus)}. '
            'Ask me about statuses, deposit slabs, Tanglish APH rules or the '
            'penalty summary.',
        isUser: false,
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 240),
        curve: Curves.easeOut,
      );
    });
  }

  Future<void> _send(String rawPrompt) async {
    final prompt = rawPrompt.trim();
    if (prompt.isEmpty || _thinking) return;
    final reply = ekoshAiReply(widget.state, prompt);
    setState(() {
      _messages
        ..add(
          _ChatMessage(
            author: widget.state.role.shortLabel,
            text: prompt,
            isUser: true,
          ),
        )
        ..add(_ChatMessage(author: 'e-Kosh AI', text: reply, isUser: false));
      _thinking = true;
      _controller.clear();
    });
    _scrollToEnd();
    widget.state.logAiConsultation(prompt);
    await Future<void>.delayed(const Duration(milliseconds: 420));
    if (!mounted) return;
    setState(() => _thinking = false);
    _scrollToEnd();
  }

  @override
  Widget build(BuildContext context) {
    final screen = MediaQuery.sizeOf(context);
    final width = screen.width < 520 ? screen.width : 468.0;
    return Align(
      alignment: Alignment.centerRight,
      child: Material(
        color: Colors.transparent,
        child: Container(
          width: width,
          height: screen.height,
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.horizontal(left: Radius.circular(20)),
            boxShadow: [
              BoxShadow(
                color: Color(0x330B1B43),
                blurRadius: 40,
                offset: Offset(-10, 0),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: const BorderRadius.horizontal(
              left: Radius.circular(20),
            ),
            child: Column(
              children: [
                _buildHeader(context),
                _buildQuickPrompts(),
                Expanded(child: _buildTranscript()),
                _buildComposer(context),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 16, 12, 15),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [AppColors.navyInk, AppColors.navy, AppColors.indigo],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: AppColors.gold.withValues(alpha: 0.65),
                  ),
                ),
                child: const Icon(
                  Icons.smart_toy_rounded,
                  color: AppColors.gold,
                  size: 22,
                ),
              ),
              const SizedBox(width: 11),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'e-Kosh AI Assistant',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Context-aware • Reads live portal DB',
                      style: TextStyle(
                        fontSize: 8.4,
                        color: Color(0xFFC7D2FE),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(
                  Icons.close_rounded,
                  color: Colors.white,
                  size: 20,
                ),
                tooltip: 'Close assistant',
              ),
            ],
          ),
          const SizedBox(height: 11),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
            decoration: BoxDecoration(
              color: AppColors.gold.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppColors.gold.withValues(alpha: 0.45)),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.verified_rounded, size: 12, color: AppColors.gold),
                SizedBox(width: 5),
                Flexible(
                  child: Text(
                    'Supports English & Tanglish • Powered by Gemini RAG + Live DB',
                    style: TextStyle(
                      fontSize: 7.6,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                      height: 1.3,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickPrompts() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: const BoxDecoration(
        color: AppColors.cream,
        border: Border(bottom: BorderSide(color: AppColors.softBorder)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'QUICK PROMPTS',
            style: TextStyle(
              fontSize: 7.6,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.8,
              color: AppColors.muted,
            ),
          ),
          const SizedBox(height: 7),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: _quickPrompts.map((prompt) {
              return InkWell(
                borderRadius: BorderRadius.circular(20),
                onTap: () => _send(prompt),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: AppColors.navy.withValues(alpha: 0.16),
                    ),
                  ),
                  child: Text(
                    prompt,
                    style: const TextStyle(
                      fontSize: 8,
                      fontWeight: FontWeight.w700,
                      color: AppColors.navy,
                      height: 1.25,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildTranscript() {
    return Container(
      color: AppColors.surfaceSoft,
      child: ListView.builder(
        controller: _scrollController,
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 16),
        itemCount: _messages.length + (_thinking ? 1 : 0),
        itemBuilder: (context, index) {
          if (index >= _messages.length) {
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: 10),
              child: Row(
                children: [
                  SizedBox(
                    width: 13,
                    height: 13,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppColors.indigo,
                    ),
                  ),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'e-Kosh AI is checking the live database…',
                      style: TextStyle(
                        fontSize: 8.6,
                        fontStyle: FontStyle.italic,
                        color: AppColors.muted,
                      ),
                    ),
                  ),
                ],
              ),
            );
          }
          return _ChatBubble(message: _messages[index]);
        },
      ),
    );
  }

  Widget _buildComposer(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: AppColors.softBorder)),
      ),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: TextField(
                  controller: _controller,
                  minLines: 1,
                  maxLines: 3,
                  textInputAction: TextInputAction.send,
                  onSubmitted: _send,
                  style: const TextStyle(
                    fontSize: 10.2,
                    color: AppColors.navyInk,
                    height: 1.4,
                  ),
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: 'Ask about FDRs, slabs, Tanglish APH rules…',
                    hintStyle: const TextStyle(
                      fontSize: 9.4,
                      color: AppColors.muted,
                    ),
                    filled: true,
                    fillColor: AppColors.surfaceSoft,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 11,
                    ),
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
                      borderSide: const BorderSide(color: AppColors.navy),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Material(
                color: AppColors.navy,
                borderRadius: BorderRadius.circular(10),
                child: InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: () => _send(_controller.text),
                  child: const Padding(
                    padding: EdgeInsets.all(11),
                    child: Icon(
                      Icons.send_rounded,
                      size: 17,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          const Text(
            'Demo RAG assistant • answers are generated from the live portal state, not an external LLM call.',
            style: TextStyle(
              fontSize: 7.2,
              color: AppColors.muted,
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }
}

class _ChatBubble extends StatelessWidget {
  const _ChatBubble({required this.message});

  final _ChatMessage message;

  @override
  Widget build(BuildContext context) {
    final user = message.isUser;
    return Padding(
      padding: const EdgeInsets.only(bottom: 11),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: user
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
        children: [
          if (!user) ...[
            Container(
              width: 26,
              height: 26,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [AppColors.navy, AppColors.indigo],
                ),
                shape: BoxShape.circle,
                border: Border.all(
                  color: AppColors.gold.withValues(alpha: 0.5),
                ),
              ),
              child: const Icon(
                Icons.auto_awesome_rounded,
                size: 13,
                color: AppColors.gold,
              ),
            ),
            const SizedBox(width: 7),
          ],
          Flexible(
            child: Container(
              padding: const EdgeInsets.fromLTRB(11, 9, 11, 10),
              decoration: BoxDecoration(
                color: user ? AppColors.navy : Colors.white,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(12),
                  topRight: const Radius.circular(12),
                  bottomLeft: Radius.circular(user ? 12 : 3),
                  bottomRight: Radius.circular(user ? 3 : 12),
                ),
                border: user ? null : Border.all(color: AppColors.border),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.navyInk.withValues(alpha: 0.04),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    user ? 'You • ${message.author}' : message.author,
                    style: TextStyle(
                      fontSize: 7.2,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.5,
                      color: user ? const Color(0xFFBFDBFE) : AppColors.gold,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    message.text,
                    style: TextStyle(
                      fontSize: 9.6,
                      height: 1.55,
                      color: user ? Colors.white : AppColors.ink,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (user) ...[
            const SizedBox(width: 7),
            Container(
              width: 26,
              height: 26,
              decoration: BoxDecoration(
                color: AppColors.slate,
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.border),
              ),
              alignment: Alignment.center,
              child: const Text(
                'YOU',
                style: TextStyle(
                  fontSize: 7,
                  fontWeight: FontWeight.w900,
                  color: AppColors.navyInk,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

String ekoshAiReply(PortalState state, String prompt) {
  final query = prompt.toLowerCase();
  final tanglish =
      query.contains('tanglish') ||
      query.contains('time exceed') ||
      query.contains('exceed') ||
      query.contains('renew') ||
      query.contains('hold') ||
      query.contains('enna') ||
      query.contains('aagum') ||
      query.contains('pannanum') ||
      query.contains('late');

  if (tanglish) {
    return _ekoshTanglishReply(state);
  }
  if (query.contains('calculat') ||
      query.contains('slab') ||
      query.contains('new engineering') ||
      query.contains('deposit amount') ||
      query.contains('how much')) {
    return _ekoshSlabReply(state);
  }
  if (query.contains('corpus') ||
      query.contains('penalty') ||
      query.contains('summary') ||
      query.contains('finance')) {
    return _ekoshCorpusReply(state);
  }
  if (query.contains('status') ||
      query.contains('fdr') ||
      query.contains('track') ||
      query.contains('live')) {
    return _ekoshStatusReply(state);
  }
  return _ekoshStatusReply(state);
}

String _ekoshStatusReply(PortalState state) {
  final records = state.records;
  if (records.isEmpty) {
    return 'The live portal database has no FDR records yet. Submit a joint '
        'FDR from the Institute dashboard and I will track it here in real time.';
  }
  final buffer = StringBuffer()
    ..writeln(
      'Live DB reply — ${records.length} FDRs, national corpus '
      '${inrCompact(state.nationalCorpus)}.',
    )
    ..writeln();
  for (final record in records) {
    buffer.writeln(
      '• ${record.id} — ${record.instituteName}\n'
      '   Status: ${record.status.label} • ${inrCompact(record.amount)}'
      '${record.enocNumber != null ? ' • e-NOC ${record.enocNumber}' : ''}',
    );
  }
  final pending = state.financeQueue.length;
  final enocs = state.issuedEnocs.length;
  buffer
    ..writeln()
    ..write(
      'Summary: $pending awaiting Finance approval, $enocs e-NOC(s) issued, '
      '${state.disbursedRecords.length} settled & closed. '
      'Institute dashboard-la e-NOC download button available for released '
      'records.',
    );
  return buffer.toString();
}

String _ekoshSlabReply(PortalState state) {
  return 'AICTE Approval Process Handbook (APH) security-deposit slabs — '
      'joint FDR in the name of the institute and AICTE:\n\n'
      '• ₹15,00,000 (₹15 L) — standard engineering programme band, up to '
      '180 sanctioned intake. 10-year joint lien.\n'
      '• ₹35,00,000 (₹35 L) — mid-size band, 181–360 sanctioned intake.\n'
      '• ₹100,00,000 (₹1 Cr) — large band, above 360 sanctioned intake / '
      'multi-programme campuses.\n\n'
      'Rule: FDR principal must equal the applicable slab; maturity must cover '
      'the full approval cycle. Current national corpus in this demo is '
      '${inrCompact(state.nationalCorpus)} across ${state.records.length} '
      'instruments.\n\n'
      'Use New FDR Submission → upload receipt → Run AI OCR Auto-Extraction; '
      'the calculator auto-fills the slab amount.';
}

String _ekoshTanglishReply(PortalState state) {
  final onHold = state.onHoldRecords.length;
  return 'Vanakkam! Project time limit exceed aana, AICTE APH rule prakaram '
      'idhu nadakkum:\n\n'
      '1. Auto-Hold — FDR udane "On Hold - Extension Required" aagum. RO '
      'automatic-a hold podum, bank disbursement stop aagum.\n'
      '2. 2-Year FDR Renewal — Institute 2 varsham extended / renewed FDR '
      '(new maturity date) upload pannanum. Portal-la "Upload Extended / '
      'Renewed FDR (2 Years)" button use pannunga.\n'
      '3. Penalty Deduction — Delay period-ku APH slab (₹15L / ₹35L / ₹100L) '
      'base pannitu penalty deduct aagum. Full release-la penalty waive '
      'aagum, partial release-la deduct aagum.\n'
      '4. Extreme non-compliance — FDR AICTE account-ku forfeit aagum '
      '(forfeited & encashed).\n\n'
      'Ippo live-a $onHold FDR hold-la irukku. Time exceed aana udane '
      'renewal upload pannunga, illa na penalty + forfeiture risk irukku.';
}

String _ekoshCorpusReply(PortalState state) {
  final regional = state.regionalCorpus.entries
      .map((entry) => '${entry.key} ${inrCompact(entry.value)}')
      .join(' • ');
  return 'Finance Bureau live snapshot:\n\n'
      '• National FDR corpus: ${inrCompact(state.nationalCorpus)} '
      '(${inr(state.nationalCorpus)}) across ${state.records.length} FDRs.\n'
      '• Penalties assessed: ${inr(state.totalPenaltyAssessed)}.\n'
      '• Penalties deducted: ${inr(state.totalPenaltiesDeducted)}.\n'
      '• Forfeited & encashed: ${inr(state.totalForfeited)}.\n'
      '• e-NOCs issued: ${state.issuedEnocs.length} • settled & closed: '
      '${state.disbursedRecords.length}.\n'
      '• Audit events recorded: ${state.auditEventCount}.\n\n'
      'Regional corpus: $regional.\n\n'
      'Open Finance HQ → Analytics & Audit for the donut, regional bars and '
      'the immutable audit trail.';
}

// -----------------------------------------------------------------------------
// Phase 3: Executive analytics & immutable audit trail (Finance HQ)
// -----------------------------------------------------------------------------

class FinanceInsightsPage extends StatelessWidget {
  const FinanceInsightsPage({super.key, required this.state});

  final PortalState state;

  @override
  Widget build(BuildContext context) {
    final slices = state.nationalStatusBreakdown;
    final total = slices.fold<int>(0, (sum, slice) => sum + slice.count);
    final regional = state.regionalCorpus;

    return WorkspacePage(
      header: WorkspaceHeader(
        eyebrow: 'AICTE finance bureau • executive intelligence',
        title: 'Executive Analytics & Immutable Audit Trail',
        subtitle:
            'National FDR status mix, regional corpus distribution and the tamper-evident security log that records every action performed on the portal.',
        actions: [
          AppButton(
            label: 'Export Audit Extract',
            icon: Icons.file_download_rounded,
            primary: false,
            onPressed: () => showAppToast(
              context,
              'Audit extract prepared: ${state.auditEventCount} immutable entries signed with the AICTE ledger hash (demo).',
              icon: Icons.file_download_done_rounded,
              color: AppColors.indigo,
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
              label: 'Records Analysed',
              value: '$total',
              helper: 'Across all regional offices and lifecycle states',
              icon: Icons.dataset_rounded,
              color: AppColors.navy,
            ),
            KpiCard(
              label: 'National Corpus',
              value: inrCompact(state.nationalCorpus),
              helper: inr(state.nationalCorpus),
              icon: Icons.account_balance_rounded,
              color: AppColors.teal,
            ),
            KpiCard(
              label: 'Released / Settled',
              value:
                  '${state.releasedRecords.length + state.disbursedRecords.length}',
              helper:
                  '${state.issuedEnocs.length} digital e-NOCs anchored on the ledger',
              icon: Icons.verified_rounded,
              color: AppColors.emeraldDark,
            ),
            KpiCard(
              label: 'Audit Events',
              value: '${state.auditEventCount}',
              helper: 'Immutable entries — newest first',
              icon: Icons.security_rounded,
              color: AppColors.indigo,
            ),
          ],
        ),
        LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 1080;
            final breakdown = SectionCard(
              title: 'National FDR Status Breakdown',
              subtitle:
                  'Proportion of every instrument by its current lifecycle state.',
              trailing: SoftChip(
                label: '$total instruments',
                icon: Icons.donut_large_rounded,
                color: AppColors.navy,
              ),
              contentPadding: const EdgeInsets.all(18),
              child: LayoutBuilder(
                builder: (context, inner) {
                  final stacked = inner.maxWidth < 520;
                  final chart = _NationalStatusDonut(
                    slices: slices,
                    total: total,
                  );
                  final legend = Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (var index = 0; index < slices.length; index++) ...[
                        if (index > 0) const SizedBox(height: 9),
                        _StatusLegendRow(slice: slices[index], total: total),
                      ],
                    ],
                  );
                  if (stacked) {
                    return Column(
                      children: [
                        Center(child: chart),
                        const SizedBox(height: 16),
                        legend,
                      ],
                    );
                  }
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      chart,
                      const SizedBox(width: 22),
                      Expanded(child: legend),
                    ],
                  );
                },
              ),
            );
            final regionalCard = SectionCard(
              title: 'Regional Corpus Distribution',
              subtitle:
                  'Deposit holdings compared across Southern, Northern, Western and Eastern ROs.',
              trailing: SoftChip(
                label: inrCompact(state.maxRegionalCorpus),
                icon: Icons.leaderboard_rounded,
                color: AppColors.teal,
              ),
              contentPadding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var index = 0; index < regional.length; index++) ...[
                    if (index > 0) const SizedBox(height: 15),
                    _RegionalCorpusRow(
                      region: regional.keys.elementAt(index),
                      amount: regional.values.elementAt(index),
                      maximum: state.maxRegionalCorpus,
                      color: _regionColor(index),
                    ),
                  ],
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(11),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceSoft,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(
                          Icons.info_outline_rounded,
                          size: 15,
                          color: AppColors.navy,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Regional totals aggregate every FDR held under that '
                            'Regional Office, including instruments awaiting '
                            'release or forfeiture. Total monitored corpus: '
                            '${inr(state.nationalCorpus)}.',
                            style: const TextStyle(
                              fontSize: 8.8,
                              height: 1.45,
                              color: AppColors.muted,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
            if (!wide) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [breakdown, const SizedBox(height: 18), regionalCard],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 6, child: breakdown),
                const SizedBox(width: 18),
                Expanded(flex: 5, child: regionalCard),
              ],
            );
          },
        ),
        _AuditLogCard(state: state),
      ],
    );
  }

  Color _regionColor(int index) {
    const palette = [
      AppColors.navy,
      AppColors.gold,
      AppColors.teal,
      AppColors.orange,
    ];
    return palette[index % palette.length];
  }
}

class _NationalStatusDonut extends StatelessWidget {
  const _NationalStatusDonut({required this.slices, required this.total});

  final List<StatusSlice> slices;
  final int total;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 208,
      height: 208,
      child: Stack(
        alignment: Alignment.center,
        children: [
          CustomPaint(
            size: const Size.square(208),
            painter: _DonutPainter(slices: slices, total: total),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '$total',
                style: const TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.8,
                  color: AppColors.navyInk,
                ),
              ),
              const SizedBox(height: 1),
              const Text(
                'FDR INSTRUMENTS',
                style: TextStyle(
                  fontSize: 7.4,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.8,
                  color: AppColors.muted,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DonutPainter extends CustomPainter {
  _DonutPainter({required this.slices, required this.total});

  final List<StatusSlice> slices;
  final int total;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTWH(14, 14, size.width - 28, size.height - 28);
    final base = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 22
      ..color = AppColors.slate;
    canvas.drawArc(rect, 0, 6.283185307, false, base);

    if (total <= 0) return;
    var start = -1.570796327;
    const gap = 0.045;
    for (final slice in slices) {
      if (slice.count <= 0) continue;
      final sweep = (slice.count / total) * 6.283185307;
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 22
        ..strokeCap = StrokeCap.butt
        ..color = slice.color;
      final drawSweep = sweep > gap ? sweep - gap : sweep;
      canvas.drawArc(rect, start + gap / 2, drawSweep, false, paint);
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(covariant _DonutPainter oldDelegate) =>
      oldDelegate.total != total ||
      oldDelegate.slices.length != slices.length ||
      List.generate(
        slices.length,
        (index) => oldDelegate.slices[index].count != slices[index].count,
      ).any((changed) => changed);
}

class _StatusLegendRow extends StatelessWidget {
  const _StatusLegendRow({required this.slice, required this.total});

  final StatusSlice slice;
  final int total;

  @override
  Widget build(BuildContext context) {
    final share = total == 0 ? 0.0 : (slice.count / total) * 100;
    return Row(
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: slice.color,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        const SizedBox(width: 9),
        Expanded(
          child: Text(
            slice.label,
            style: const TextStyle(
              fontSize: 9.4,
              fontWeight: FontWeight.w700,
              color: AppColors.ink,
            ),
          ),
        ),
        Text(
          '${slice.count}',
          style: const TextStyle(
            fontSize: 10.4,
            fontWeight: FontWeight.w900,
            color: AppColors.navyInk,
          ),
        ),
        const SizedBox(width: 7),
        SizedBox(
          width: 52,
          child: Text(
            '${share.toStringAsFixed(0)}%',
            textAlign: TextAlign.right,
            style: const TextStyle(
              fontSize: 8.6,
              fontWeight: FontWeight.w700,
              color: AppColors.muted,
            ),
          ),
        ),
      ],
    );
  }
}

class _RegionalCorpusRow extends StatelessWidget {
  const _RegionalCorpusRow({
    required this.region,
    required this.amount,
    required this.maximum,
    required this.color,
  });

  final String region;
  final double amount;
  final double maximum;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final fraction = maximum <= 0 ? 0.0 : (amount / maximum).clamp(0.0, 1.0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                '$region RO',
                style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  color: AppColors.navyInk,
                ),
              ),
            ),
            Text(
              inrCompact(amount),
              style: const TextStyle(
                fontSize: 10.4,
                fontWeight: FontWeight.w900,
                color: AppColors.navyInk,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: Container(
            height: 11,
            color: AppColors.slate,
            child: LayoutBuilder(
              builder: (context, constraints) {
                return Stack(
                  children: [
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 420),
                      curve: Curves.easeOutCubic,
                      width: constraints.maxWidth * fraction,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [color, color.withValues(alpha: 0.62)],
                        ),
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          '${(fraction * 100).toStringAsFixed(0)}% of the largest regional holding',
          style: const TextStyle(fontSize: 7.8, color: AppColors.muted),
        ),
      ],
    );
  }
}

class _AuditLogCard extends StatelessWidget {
  const _AuditLogCard({required this.state});

  final PortalState state;

  @override
  Widget build(BuildContext context) {
    final entries = state.auditLog;
    return SectionCard(
      title: 'Immutable Security Audit Log',
      subtitle:
          'Chronological, append-only trail of every portal action with actor role, FDR reference, simulated IP and ledger hash.',
      trailing: SoftChip(
        label: '${entries.length} events • append-only',
        icon: Icons.lock_clock_rounded,
        color: AppColors.emeraldDark,
      ),
      contentPadding: entries.isEmpty
          ? EdgeInsets.zero
          : const EdgeInsets.only(bottom: 10),
      child: entries.isEmpty
          ? const EmptyState(
              title: 'No audit events recorded',
              message:
                  'Perform any portal action and the immutable audit entry will appear here instantly.',
              icon: Icons.receipt_long_rounded,
              color: AppColors.muted,
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  padding: const EdgeInsets.fromLTRB(18, 12, 18, 12),
                  color: AppColors.surfaceSoft,
                  child: Row(
                    children: [
                      const Icon(
                        Icons.verified_user_rounded,
                        size: 15,
                        color: AppColors.emeraldDark,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Each row is hash-chained. Newest actions are '
                          'prepended automatically — entries cannot be edited '
                          'or deleted from the UI.',
                          style: const TextStyle(
                            fontSize: 8.6,
                            height: 1.4,
                            color: AppColors.muted,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                TableScroll(
                  minWidth: 1120,
                  child: DataTable(
                    horizontalMargin: 18,
                    columnSpacing: 22,
                    headingRowHeight: 42,
                    dataRowMinHeight: 46,
                    dataRowMaxHeight: 62,
                    headingRowColor: const WidgetStatePropertyAll(
                      AppColors.navy,
                    ),
                    headingTextStyle: const TextStyle(
                      fontSize: 8.4,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.8,
                      color: Colors.white,
                    ),
                    dividerThickness: 1,
                    border: const TableBorder(
                      horizontalInside: BorderSide(color: AppColors.softBorder),
                    ),
                    columns: const [
                      DataColumn(label: Text('TIMESTAMP')),
                      DataColumn(label: Text('ACTOR ROLE')),
                      DataColumn(label: Text('FDR ID')),
                      DataColumn(label: Text('ACTION TAKEN')),
                      DataColumn(label: Text('IP / HASH')),
                    ],
                    rows: [
                      for (final (rowIndex, entry) in entries.take(30).indexed)
                        DataRow(
                          color: portalRowColor(rowIndex),
                          cells: [
                            DataCell(
                              Text(
                                formatDateTime(entry.timestamp),
                                style: const TextStyle(
                                  fontSize: 8.8,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.ink,
                                ),
                              ),
                            ),
                            DataCell(
                              Text(
                                entry.actor,
                                style: const TextStyle(
                                  fontSize: 8.8,
                                  color: AppColors.muted,
                                ),
                              ),
                            ),
                            DataCell(
                              Text(
                                entry.fdrId,
                                style: const TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.w800,
                                  color: AppColors.navy,
                                ),
                              ),
                            ),
                            DataCell(
                              SizedBox(
                                width: 300,
                                child: Text(
                                  entry.action,
                                  style: const TextStyle(
                                    fontSize: 9,
                                    height: 1.35,
                                    color: AppColors.ink,
                                  ),
                                ),
                              ),
                            ),
                            DataCell(
                              Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    entry.ipReference,
                                    style: const TextStyle(
                                      fontSize: 8.4,
                                      fontFamily: 'monospace',
                                      color: AppColors.navyInk,
                                    ),
                                  ),
                                  Text(
                                    entry.hashReference,
                                    style: const TextStyle(
                                      fontSize: 8.2,
                                      fontFamily: 'monospace',
                                      color: AppColors.muted,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
                if (entries.length > 30)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(18, 8, 18, 4),
                    child: Text(
                      'Showing the latest 30 of ${entries.length} immutable '
                      'entries. Older records remain retrievable from the '
                      'AICTE cold-storage ledger.',
                      style: const TextStyle(
                        fontSize: 8.2,
                        color: AppColors.muted,
                      ),
                    ),
                  ),
              ],
            ),
    );
  }
}

// -----------------------------------------------------------------------------
// Phase 3: Finance e-NOC registry
// -----------------------------------------------------------------------------

class _EnocRegistryCard extends StatelessWidget {
  const _EnocRegistryCard({required this.state});

  final PortalState state;

  @override
  Widget build(BuildContext context) {
    final records = state.issuedEnocs;
    return SectionCard(
      title: 'Issued Digital e-NOC Registry',
      subtitle:
          'Every digitally signed release order generated by the Finance Bureau, with the net authorised amount and QR verification status.',
      trailing: SoftChip(
        label: '${records.length} e-NOCs issued',
        icon: Icons.qr_code_2_rounded,
        color: AppColors.emeraldDark,
      ),
      contentPadding: records.isEmpty
          ? EdgeInsets.zero
          : const EdgeInsets.only(bottom: 8),
      child: records.isEmpty
          ? const EmptyState(
              title: 'No e-NOCs issued yet',
              message:
                  'Approve a full or partial release and the digitally signed certificate will be registered here for bank verification.',
              icon: Icons.description_rounded,
              color: AppColors.muted,
            )
          : TableScroll(
              minWidth: 1080,
              child: DataTable(
                horizontalMargin: 20,
                columnSpacing: 22,
                headingRowHeight: 44,
                dataRowMinHeight: 58,
                dataRowMaxHeight: 66,
                headingRowColor: const WidgetStatePropertyAll(AppColors.navy),
                headingTextStyle: const TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.8,
                  color: Colors.white,
                ),
                dividerThickness: 1,
                border: const TableBorder(
                  horizontalInside: BorderSide(color: AppColors.softBorder),
                ),
                columns: const [
                  DataColumn(label: Text('e-NOC / FDR')),
                  DataColumn(label: Text('INSTITUTE')),
                  DataColumn(label: Text('BANK / IFSC')),
                  DataColumn(label: Text('NET AUTHORISED')),
                  DataColumn(label: Text('STATUS')),
                  DataColumn(label: Text('CERTIFICATE')),
                ],
                rows: records.asMap().entries.map((entry) {
                  final rowIndex = entry.key;
                  final record = entry.value;
                  return DataRow(
                    color: portalRowColor(rowIndex),
                    cells: [
                      DataCell(
                        Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              record.enocNumber ?? '—',
                              style: const TextStyle(
                                fontSize: 9.6,
                                fontWeight: FontWeight.w800,
                                color: AppColors.indigo,
                              ),
                            ),
                            Text(
                              record.id,
                              style: const TextStyle(
                                fontSize: 8.8,
                                color: AppColors.muted,
                              ),
                            ),
                          ],
                        ),
                      ),
                      DataCell(
                        SizedBox(
                          width: 210,
                          child: Text(
                            record.instituteName,
                            style: const TextStyle(
                              fontSize: 9.4,
                              color: AppColors.ink,
                              height: 1.35,
                            ),
                          ),
                        ),
                      ),
                      DataCell(
                        Text(
                          '${bankAbbreviation(record.bankName)} • ${record.ifsc}',
                          style: const TextStyle(
                            fontSize: 8.8,
                            color: AppColors.muted,
                          ),
                        ),
                      ),
                      DataCell(
                        Text(
                          inr(record.releasedAmount ?? record.netPayable),
                          style: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w900,
                            color: AppColors.emeraldDark,
                          ),
                        ),
                      ),
                      DataCell(StatusPill(status: record.status)),
                      DataCell(
                        SizedBox(
                          width: 210,
                          child: AppButton(
                            label: 'View / Download Digital e-NOC',
                            icon: Icons.qr_code_2_rounded,
                            dense: true,
                            color: AppColors.emeraldDark,
                            onPressed: () =>
                                showEnocDialog(context, state, record),
                          ),
                        ),
                      ),
                    ],
                  );
                }).toList(),
              ),
            ),
    );
  }
}
