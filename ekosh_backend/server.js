require('dotenv').config();
const express = require('express');
const mongoose = require('mongoose');
const cors = require('cors');
const multer = require('multer');
const Tesseract = require('tesseract.js');

const app = express();
app.use(cors());
app.use(express.json());

mongoose.connect(process.env.MONGO_URI || process.env.MONGODB_URI)
  .then(async () => {
    console.log('✅ Connected to MongoDB Atlas: ekosh_aicte_db');
    await seedDefaultUsers();
    await seedDemoNotificationData();
    await runMaturityNotificationScheduler('AUTO_CRON_SCHEDULER');
    // The production scheduler re-scans the portfolio every 24 hours. Each
    // milestone flag guarantees a single dispatch per FDR per alert window.
    setInterval(() => {
      runMaturityNotificationScheduler('AUTO_CRON_SCHEDULER').catch((err) =>
        console.error('❌ Maturity scheduler error:', err.message)
      );
    }, 24 * 60 * 60 * 1000);
    console.log('⏱️  Maturity notification scheduler armed for a 24-hour cycle');
  })
  .catch((err) => console.error('❌ MongoDB Connection Error:', err));

const fdrSchema = new mongoose.Schema({
  fdr_number: { type: String, required: true, unique: true },
  aicte_permanent_id: String,
  institute_name: String,
  program_type: String,
  bank_details: {
    bank_name: String,
    branch_name: String,
    ifsc_code: String,
    is_joint_holder_verified: { type: Boolean, default: false }
  },
  financials: {
    principal_amount: Number,
    interest_rate: Number,
    penalty_deducted: { type: Number, default: 0 },
    net_refundable_amount: Number
  },
  timeline: {
    issue_date: String,
    maturity_date: String,
    lock_in_years: { type: Number, default: 8 },
    is_time_exceeded: { type: Boolean, default: false },
    alerts_sent: {
      alert_90_sent: { type: Boolean, default: false },
      alert_60_sent: { type: Boolean, default: false },
      alert_30_sent: { type: Boolean, default: false },
      last_alert_timestamp: { type: String, default: null }
    }
  },
  ocr_extraction_metadata: {
    ocr_confidence_score: { type: Number, default: 98.5 },
    is_auto_filled: { type: Boolean, default: true }
  },
  settlement: {
    utr_number: { type: String, default: null },
    settled_amount: { type: Number, default: 0 },
    settled_at: { type: String, default: null },
    disbursed_at: { type: String, default: null }
  },
  lifecycle_status: {
    type: String,
    default: 'PENDING_BANK_VERIFICATION'
  }
}, { collection: 'fdr_records' });

const instituteSchema = new mongoose.Schema({
  aicte_permanent_id: String,
  institute_name: String,
  trust_name: String,
  region: String,
  state: String,
  contact_email: String,
  contact_mobile: String,
  compliance_scrutiny: {
    has_infrastructure_deficiency: Boolean,
    has_faculty_salary_dispute: Boolean,
    has_vigilance_or_court_case: Boolean,
    approval_timeline_exceeded: Boolean,
    active_penalty_amount: Number,
    scrutiny_remarks: String
  }
}, { collection: 'institutes' });

// Immutable gateway ledger for every Email + SMS advisory dispatched by the
// automated pre-maturity engine. Kept separate from audit_logs so the Finance
// HQ screen can render the delivery trail without parsing the audit stream.
const notificationLogSchema = new mongoose.Schema({
  fdr_number: { type: String, required: true },
  aicte_id: String,
  institute_name: String,
  recipient_email: String,
  recipient_mobile: String,
  milestone_window: {
    type: String,
    enum: ['90_DAYS', '60_DAYS', '30_DAYS'],
    required: true
  },
  channels: [{ type: String, enum: ['EMAIL', 'SMS'] }],
  message_preview: String,
  email_subject: String,
  email_body: String,
  sms_body: String,
  days_to_maturity: Number,
  delivery_status: { type: String, default: 'DELIVERED' },
  triggered_by: {
    type: String,
    enum: ['AUTO_CRON_SCHEDULER', 'FINANCE_HQ_MANUAL'],
    required: true
  },
  timestamp: { type: String, default: () => new Date().toISOString() }
}, { collection: 'notification_logs' });

notificationLogSchema.index({ timestamp: -1 });
notificationLogSchema.index({ fdr_number: 1, milestone_window: 1 });

const auditLogSchema = new mongoose.Schema({
  fdr_number: String,
  aicte_permanent_id: String,
  actor_role: String,
  actor_name: String,
  action_type: String,
  previous_status: String,
  new_status: String,
  remarks: String,
  timestamp: { type: String, default: () => new Date().toISOString() }
}, { collection: 'audit_logs' });

const userSchema = new mongoose.Schema({
  role: { type: String, required: true, unique: true },
  portal_module: { type: String, required: true },
  email: { type: String, required: true, unique: true, lowercase: true, trim: true },
  password: { type: String, required: true },
  organization_name: String,
  aicte_or_ifsc_code: String
}, { collection: 'users' });

const FDR = mongoose.model('FDR', fdrSchema);
const Institute = mongoose.model('Institute', instituteSchema);
const AuditLog = mongoose.model('AuditLog', auditLogSchema);
const User = mongoose.model('User', userSchema);
const NotificationLog = mongoose.model('NotificationLog', notificationLogSchema);

// The four stakeholder personas issued to evaluators. Upserting on boot keeps
// the demo credentials deterministic even on a fresh Atlas cluster.
const DEFAULT_USERS = [
  {
    role: 'Institute Login',
    portal_module: 'Portfolio & Tracker',
    email: 'principal@kpr.edu.in',
    password: 'Kpr@2026',
    organization_name: 'KPR Institute of Technology',
    aicte_or_ifsc_code: '1-492831'
  },
  {
    role: 'Bank Node',
    portal_module: 'Verification Desk',
    email: 'banknode@sbi.co.in',
    password: 'Sbi@2026',
    organization_name: 'State Bank of India',
    aicte_or_ifsc_code: 'SBIN0004321'
  },
  {
    role: 'AICTE RO',
    portal_module: 'Scrutiny Queue',
    email: 'ro.south@aicte.gov.in',
    password: 'RoSouth@2026',
    organization_name: 'AICTE Southern Regional Office',
    aicte_or_ifsc_code: 'RO-SOUTH'
  },
  {
    role: 'Finance HQ',
    portal_module: 'Final Settlement',
    email: 'finance.hq@aicte.gov.in',
    password: 'Finance@2026',
    organization_name: 'AICTE Finance Bureau HQ',
    aicte_or_ifsc_code: 'FIN-HQ'
  }
];

async function seedDefaultUsers() {
  await Promise.all(
    DEFAULT_USERS.map((account) =>
      User.updateOne(
        { role: account.role },
        { $set: account },
        { upsert: true }
      )
    )
  );
  console.log(`✅ Seeded ${DEFAULT_USERS.length} default SSO users`);
}

// -----------------------------------------------------------------------------
// Automated 90 / 60 / 30-day pre-maturity Email + SMS notification engine
// -----------------------------------------------------------------------------

const ACTIVE_LIFECYCLE_STATUSES = [
  'PENDING_BANK_VERIFICATION',
  'ACTIVE_LIEN_LOCKED',
  'MATURED_PENDING_RO',
  'RO_CLEARED_PENDING_FINANCE',
  'ON_HOLD_EXTENSION'
];

const ALERT_WINDOWS = {
  '90_DAYS': {
    flag: 'alert_90_sent',
    shortLabel: '90D',
    title: '90-Day Pre-Maturity Advisory',
    action:
      'Please initiate the release or two-year renewal paperwork with the partner bank at least 30 days before maturity.',
    audit: 'MATURITY_ALERT_DISPATCHED_90D'
  },
  '60_DAYS': {
    flag: 'alert_60_sent',
    shortLabel: '60D',
    title: '60-Day Follow-Up Reminder',
    action:
      'Verify that the joint lien is still marked in favour of AICTE and confirm the release/renewal decision to the Regional Office.',
    audit: 'MATURITY_ALERT_DISPATCHED_60D'
  },
  '30_DAYS': {
    flag: 'alert_30_sent',
    shortLabel: '30D',
    title: '30-Day Critical Final Notice',
    action:
      'URGENT: Submit the Release Application or the renewed 2-year FDR immediately to avoid encashment and penalty action.',
    audit: 'MATURITY_ALERT_DISPATCHED_30D'
  }
};

const schedulerState = {
  last_run: null,
  runs: 0,
  last_dispatched: 0,
  last_triggered_by: null
};

let schedulerPromise = null;

function isoDateAfterDays(days) {
  const date = new Date();
  date.setUTCHours(0, 0, 0, 0);
  date.setUTCDate(date.getUTCDate() + days);
  return date.toISOString().slice(0, 10);
}

function daysUntilDate(value) {
  if (!value) return null;
  const maturity = new Date(`${String(value).slice(0, 10)}T00:00:00Z`);
  if (Number.isNaN(maturity.getTime())) return null;
  const today = new Date();
  today.setUTCHours(0, 0, 0, 0);
  return Math.round((maturity.getTime() - today.getTime()) / 86400000);
}

function milestoneForDays(days) {
  if (days === null || days < 1) return null;
  if (days <= 30) return '30_DAYS';
  if (days <= 60) return '60_DAYS';
  if (days <= 90) return '90_DAYS';
  return null;
}

// A demonstration portfolio is maintained alongside the operator-entered FDRs
// so the Finance HQ dispatch engine always has qualifying instruments to scan.
// Dates are refreshed on every boot to keep one FDR inside each alert window.
const DEMO_INSTITUTE = {
  aicte_permanent_id: '1-492831',
  institute_name: 'KPR Institute of Technology',
  trust_name: 'KPR Educational Trust',
  region: 'Southern',
  state: 'Tamil Nadu',
  contact_email: 'principal@kpr.edu.in',
  contact_mobile: '+91-9840012310',
  compliance_scrutiny: {
    has_infrastructure_deficiency: false,
    has_faculty_salary_dispute: false,
    has_vigilance_or_court_case: false,
    approval_timeline_exceeded: false,
    active_penalty_amount: 0,
    scrutiny_remarks: 'Zero deficiency. Joint FDRs verified for the 2024-27 cycle.'
  }
};

const DEMO_ALERT_FDRS = [
  {
    fdr_number: 'FDR-AICTE-ALERT-090',
    daysToMaturity: 75,
    amount: 1500000,
    bank: { bank_name: 'State Bank of India', branch_name: 'Coimbatore Main', ifsc_code: 'SBIN0004321' },
    program: 'B.Tech - Computer Science'
  },
  {
    fdr_number: 'FDR-AICTE-ALERT-060',
    daysToMaturity: 45,
    amount: 2500000,
    bank: { bank_name: 'Bank of Baroda', branch_name: 'Coimbatore', ifsc_code: 'BARB0COIMBA' },
    program: 'B.Tech - Electronics & Communication'
  },
  {
    fdr_number: 'FDR-AICTE-ALERT-030',
    daysToMaturity: 15,
    amount: 2000000,
    bank: { bank_name: 'Canara Bank', branch_name: 'Coimbatore', ifsc_code: 'CNRB0COIMBT' },
    program: 'MBA - General Management'
  },
  {
    fdr_number: 'FDR-AICTE-ALERT-120',
    daysToMaturity: 120,
    amount: 3000000,
    bank: { bank_name: 'HDFC Bank', branch_name: 'Coimbatore', ifsc_code: 'HDFC0COIMBA' },
    program: 'M.Tech - Structural Engineering'
  }
];

async function seedDemoNotificationData() {
  await Institute.updateOne(
    { aicte_permanent_id: DEMO_INSTITUTE.aicte_permanent_id },
    { $set: DEMO_INSTITUTE },
    { upsert: true }
  );

  for (const demo of DEMO_ALERT_FDRS) {
    const maturity = isoDateAfterDays(demo.daysToMaturity);
    const issue = new Date(`${maturity}T00:00:00Z`);
    issue.setUTCFullYear(issue.getUTCFullYear() - 8);
    const issueDate = issue.toISOString().slice(0, 10);
    await FDR.updateOne(
      { fdr_number: demo.fdr_number },
      {
        $set: {
          aicte_permanent_id: DEMO_INSTITUTE.aicte_permanent_id,
          institute_name: DEMO_INSTITUTE.institute_name,
          program_type: demo.program,
          'bank_details.bank_name': demo.bank.bank_name,
          'bank_details.branch_name': demo.bank.branch_name,
          'bank_details.ifsc_code': demo.bank.ifsc_code,
          'bank_details.is_joint_holder_verified': true,
          'financials.principal_amount': demo.amount,
          'financials.interest_rate': 7.1,
          'financials.penalty_deducted': 0,
          'financials.net_refundable_amount': demo.amount,
          'timeline.issue_date': issueDate,
          'timeline.maturity_date': maturity,
          'timeline.lock_in_years': 8,
          'timeline.is_time_exceeded': false,
          lifecycle_status: 'ACTIVE_LIEN_LOCKED',
          'ocr_extraction_metadata.ocr_confidence_score': 99.1,
          'ocr_extraction_metadata.is_auto_filled': true
        },
        $setOnInsert: {
          'timeline.alerts_sent.alert_90_sent': false,
          'timeline.alerts_sent.alert_60_sent': false,
          'timeline.alerts_sent.alert_30_sent': false,
          'timeline.alerts_sent.last_alert_timestamp': null
        }
      },
      { upsert: true }
    );
  }
  console.log(`✅ Seeded ${DEMO_ALERT_FDRS.length} demo FDRs for the maturity alert engine`);
}

function formatInr(value) {
  return `INR ${Number(value || 0).toLocaleString('en-IN')}`;
}

function buildAlertMessages(fdr, institute, windowKey, days) {
  const windowInfo = ALERT_WINDOWS[windowKey];
  const instituteName = fdr.institute_name || institute?.institute_name || 'AICTE Institute';
  const shortName = instituteName.split(',')[0];
  const email = institute?.contact_email || 'institute.nodal@aicte.gov.in';
  const mobile = institute?.contact_mobile || '+91-98XXXXXX10';
  const maturity = fdr.timeline?.maturity_date || '';
  const subject = `AICTE e-Kosh | ${windowInfo.title} | FDR ${fdr.fdr_number}`;
  const emailBody =
    `Dear Principal / Nodal Officer,\n\n` +
    `This is an official ${windowInfo.title.toLowerCase()} issued by the AICTE Finance Bureau ` +
    `for the Joint Fixed Deposit referenced below.\n\n` +
    `Institute: ${instituteName}\n` +
    `AICTE Permanent ID: ${fdr.aicte_permanent_id || 'N/A'}\n` +
    `FDR Number: ${fdr.fdr_number}\n` +
    `Bank / IFSC: ${fdr.bank_details?.bank_name || 'Partner Bank'} / ${fdr.bank_details?.ifsc_code || 'N/A'}\n` +
    `Principal Amount: ${formatInr(fdr.financials?.principal_amount)}\n` +
    `Maturity Date: ${maturity} (${days} days remaining)\n\n` +
    `Required action: ${windowInfo.action}\n\n` +
    `The release or renewal must be processed 100% digitally through the e-Kosh portal. ` +
    `A copy of this advisory has been marked to finance.hq@aicte.gov.in.\n\n` +
    `This is a system-generated message. Please do not reply.\n` +
    `AICTE Finance Bureau, New Delhi | Helpdesk 1800-11-2026`;
  const smsBody =
    `AICTE e-Kosh: FDR ${fdr.fdr_number} of ${shortName} matures on ${maturity} ` +
    `(${days} days). ${windowInfo.action} Portal: https://ekosh.aicte.gov.in`;
  const messagePreview =
    `EMAIL GATEWAY (SMTP)\nTo: ${email}\nCC: finance.hq@aicte.gov.in\nSubject: ${subject}\n\n` +
    `${emailBody}\n\n` +
    `SMS GATEWAY (NIC-SMS)\nTo: ${mobile}\n\n${smsBody}`;

  return { subject, emailBody, smsBody, messagePreview, email, mobile };
}

async function getMaturityWindowCounts() {
  const fdrs = await FDR.find({ lifecycle_status: { $in: ACTIVE_LIFECYCLE_STATUSES } });
  const counts = { within_90_days: 0, within_60_days: 0, within_30_days: 0 };
  for (const fdr of fdrs) {
    const days = daysUntilDate(fdr.timeline?.maturity_date);
    if (days === null || days < 1) continue;
    if (days <= 30) counts.within_30_days += 1;
    if (days <= 60) counts.within_60_days += 1;
    if (days <= 90) counts.within_90_days += 1;
  }
  return counts;
}

async function runMaturityNotificationScheduler(triggeredBy = 'AUTO_CRON_SCHEDULER', options = {}) {
  const force = options.force === true;
  if (schedulerPromise) return schedulerPromise;

  schedulerPromise = (async () => {
    const fdrs = await FDR.find({ lifecycle_status: { $in: ACTIVE_LIFECYCLE_STATUSES } });
    const institutes = await Institute.find();
    const institutesById = new Map(
      institutes.map((institute) => [institute.aicte_permanent_id, institute])
    );
    const dispatched = [];

    for (const fdr of fdrs) {
      const days = daysUntilDate(fdr.timeline?.maturity_date);
      const windowKey = milestoneForDays(days);
      if (!windowKey) continue;

      const windowInfo = ALERT_WINDOWS[windowKey];
      const alerts = fdr.timeline?.alerts_sent || {};
      if (alerts[windowInfo.flag] === true && !force) continue;

      const institute = institutesById.get(fdr.aicte_permanent_id);
      const messages = buildAlertMessages(fdr, institute, windowKey, days);
      const timestamp = new Date().toISOString();

      const log = await NotificationLog.create({
        fdr_number: fdr.fdr_number,
        aicte_id: fdr.aicte_permanent_id,
        institute_name: fdr.institute_name || institute?.institute_name,
        recipient_email: messages.email,
        recipient_mobile: messages.mobile,
        milestone_window: windowKey,
        channels: ['EMAIL', 'SMS'],
        message_preview: messages.messagePreview,
        email_subject: messages.subject,
        email_body: messages.emailBody,
        sms_body: messages.smsBody,
        days_to_maturity: days,
        delivery_status: 'DELIVERED',
        triggered_by: triggeredBy,
        timestamp
      });

      if (!fdr.timeline.alerts_sent) fdr.timeline.alerts_sent = {};
      fdr.timeline.alerts_sent[windowInfo.flag] = true;
      fdr.timeline.alerts_sent.last_alert_timestamp = timestamp;
      fdr.markModified('timeline.alerts_sent');
      await fdr.save();

      await AuditLog.create({
        fdr_number: fdr.fdr_number,
        aicte_permanent_id: fdr.aicte_permanent_id,
        actor_role: triggeredBy === 'FINANCE_HQ_MANUAL' ? 'Finance HQ' : 'SYSTEM_CRON',
        actor_name: triggeredBy === 'FINANCE_HQ_MANUAL' ? 'AICTE Finance Bureau HQ' : 'e-Kosh Automation Engine',
        action_type: windowInfo.audit,
        previous_status: fdr.lifecycle_status,
        new_status: fdr.lifecycle_status,
        remarks:
          `${windowInfo.title} dispatched via Email + SMS to ${messages.email} / ${messages.mobile} ` +
          `(${days} days to maturity). Trigger: ${triggeredBy}.`
      });

      dispatched.push(log.toObject());
    }

    const windowCounts = await getMaturityWindowCounts();
    schedulerState.last_run = new Date().toISOString();
    schedulerState.runs += 1;
    schedulerState.last_dispatched = dispatched.length;
    schedulerState.last_triggered_by = triggeredBy;

    if (dispatched.length > 0) {
      console.log(
        `📨 Maturity alert engine dispatched ${dispatched.length} Email+SMS advisory(s) via ${triggeredBy}`
      );
    }

    return { dispatched, windowCounts, scheduler: { ...schedulerState } };
  })();

  try {
    return await schedulerPromise;
  } finally {
    schedulerPromise = null;
  }
}

// Accepts the full official email or its local part, matching the gateway UX.
function emailMatches(user, email) {
  const entered = String(email || '').trim().toLowerCase();
  const official = String(user.email || '').toLowerCase();
  return entered === official || entered === official.split('@')[0];
}

function publicUser(user) {
  return {
    role: user.role,
    portal_module: user.portal_module,
    email: user.email,
    organization_name: user.organization_name,
    aicte_or_ifsc_code: user.aicte_or_ifsc_code
  };
}

app.get('/api/dashboard-data', async (req, res) => {
  try {
    const fdrs = await FDR.find().sort({ _id: -1 });
    const institutes = await Institute.find();
    const auditLogs = await AuditLog.find().sort({ timestamp: -1 });
    res.json({ success: true, fdrs, institutes, auditLogs });
  } catch (err) {
    res.status(500).json({ success: false, error: err.message });
  }
});

app.post('/api/fdr/create', async (req, res) => {
  try {
    const newFdr = await FDR.create(req.body);
    await AuditLog.create({
      fdr_number: newFdr.fdr_number,
      aicte_permanent_id: newFdr.aicte_permanent_id,
      actor_role: 'INSTITUTE_ADMIN',
      actor_name: newFdr.institute_name,
      action_type: 'OCR_UPLOAD_SUBMITTED',
      previous_status: 'NONE',
      new_status: 'PENDING_BANK_VERIFICATION',
      remarks: 'Submitted new Joint FDR via AI OCR Scanner.'
    });
    res.status(201).json({ success: true, data: newFdr });
  } catch (err) {
    res.status(400).json({ success: false, error: err.message });
  }
});

app.patch('/api/fdr/:fdr_number/status', async (req, res) => {
  try {
    const { fdr_number } = req.params;
    const { new_status, actor_role, actor_name, action_type, remarks, penalty_deducted, new_maturity_date, utr_number, settled_amount, settled_at } = req.body;

    const fdr = await FDR.findOne({ fdr_number });
    if (!fdr) return res.status(404).json({ error: 'FDR not found' });

    const prevStatus = fdr.lifecycle_status;
    fdr.lifecycle_status = new_status;

    if (new_status === 'ACTIVE_LIEN_LOCKED') fdr.bank_details.is_joint_holder_verified = true;
    if (typeof penalty_deducted === 'number') {
      fdr.financials.penalty_deducted = penalty_deducted;
      fdr.financials.net_refundable_amount = fdr.financials.principal_amount - penalty_deducted;
    }
    if (new_status === 'FORFEITED_ENCASHED_BY_AICTE') {
      fdr.financials.penalty_deducted = fdr.financials.principal_amount;
      fdr.financials.net_refundable_amount = 0;
    }
    if (new_maturity_date) {
      fdr.timeline.maturity_date = new_maturity_date;
      fdr.timeline.is_time_exceeded = false;
    }
    if (new_status === 'FUNDS_DISBURSED') {
      fdr.settlement = {
        utr_number: utr_number || fdr.settlement?.utr_number || null,
        settled_amount: settled_amount ?? fdr.settlement?.settled_amount ?? fdr.financials?.net_refundable_amount ?? 0,
        settled_at: settled_at || new Date().toISOString(),
        disbursed_at: new Date().toISOString()
      };
    }

    await fdr.save();

    await AuditLog.create({
      fdr_number,
      aicte_permanent_id: fdr.aicte_permanent_id,
      actor_role: actor_role || 'SYSTEM_USER',
      actor_name: actor_name || 'Portal Officer',
      action_type: action_type || 'STATUS_UPDATED',
      previous_status: prevStatus,
      new_status,
      remarks: remarks || `Status changed from ${prevStatus} to ${new_status}`
    });

    res.json({ success: true, data: fdr });
  } catch (err) {
    res.status(500).json({ success: false, error: err.message });
  }
});

app.post('/api/auth/login', async (req, res) => {
  try {
    const { role, email, password } = req.body || {};
    if (!role || !email || !password) {
      return res.status(400).json({
        success: false,
        error: 'Role, official email and password are required.'
      });
    }

    const user = await User.findOne({ role });
    if (!user || !emailMatches(user, email) || password !== user.password) {
      return res.status(401).json({
        success: false,
        error: 'Invalid SSO credentials for the selected stakeholder role.'
      });
    }

    await AuditLog.create({
      fdr_number: 'SSO-SESSION',
      aicte_permanent_id: user.aicte_or_ifsc_code,
      actor_role: user.role,
      actor_name: user.organization_name || user.email,
      action_type: 'SSO_LOGIN_SUCCESS',
      previous_status: 'ANONYMOUS',
      new_status: 'AUTHENTICATED',
      remarks: `${user.portal_module} session opened via database-backed SSO.`
    });

    res.json({ success: true, user: publicUser(user) });
  } catch (err) {
    res.status(500).json({ success: false, error: err.message });
  }
});

app.patch('/api/auth/reset-password', async (req, res) => {
  try {
    const { role, email, new_password } = req.body || {};
    if (!role || !email || !new_password) {
      return res.status(400).json({
        success: false,
        error: 'Role, official email and new_password are required.'
      });
    }
    if (String(new_password).trim().length < 6) {
      return res.status(400).json({
        success: false,
        error: 'New password must be at least 6 characters long.'
      });
    }

    const user = await User.findOne({ role });
    if (!user || !emailMatches(user, email)) {
      return res.status(404).json({
        success: false,
        error: 'No matching AICTE SSO account was found for this role.'
      });
    }

    user.password = new_password;
    await user.save();

    await AuditLog.create({
      fdr_number: 'SSO-SESSION',
      aicte_permanent_id: user.aicte_or_ifsc_code,
      actor_role: user.role,
      actor_name: user.organization_name || user.email,
      action_type: 'SSO_PASSWORD_RESET',
      previous_status: 'OTP_VERIFIED',
      new_status: 'PASSWORD_UPDATED',
      remarks: 'Password updated through the Forgot Password OTP recovery flow.'
    });

    res.json({ success: true, user: publicUser(user) });
  } catch (err) {
    res.status(500).json({ success: false, error: err.message });
  }
});

const signupOtps = new Map();

app.post('/api/auth/send-signup-otp', async (req, res) => {
  try {
    const { email, role } = req.body || {};
    if (!email || !role) {
      return res.status(400).json({
        success: false,
        error: 'Official email and role are required to issue a verification OTP.'
      });
    }
    const normalizedEmail = String(email).trim().toLowerCase();
    const otp = String(Math.floor(100000 + Math.random() * 900000));
    signupOtps.set(normalizedEmail, { otp, expires_at: Date.now() + 10 * 60 * 1000 });
    console.log(`📨 Signup OTP dispatched for ${normalizedEmail} (${role})`);
    res.json({
      success: true,
      otp,
      expires_in_minutes: 10,
      dev_mode: true,
      channel: 'NIC-SMS / SMTP Gateway (demo OTP channel)',
      role
    });
  } catch (err) {
    res.status(500).json({ success: false, error: err.message });
  }
});

app.post('/api/auth/register', async (req, res) => {
  try {
    const { role, organization_name, email, password, aicte_or_ifsc_code, otp_verified } = req.body || {};
    if (!role || !email || !password || !aicte_or_ifsc_code) {
      return res.status(400).json({
        success: false,
        error: 'Role, organization name, email, password, and AICTE ID / IFSC code are required.'
      });
    }
    if (String(password).trim().length < 6) {
      return res.status(400).json({
        success: false,
        error: 'Password must be at least 6 characters long.'
      });
    }
    const existingEmail = await User.findOne({ email: email.trim().toLowerCase() });
    if (existingEmail) {
      return res.status(409).json({
        success: false,
        error: 'An account with this official email already exists.'
      });
    }
    const existingAicte = await User.findOne({ aicte_or_ifsc_code: aicte_or_ifsc_code.trim().toUpperCase() });
    if (existingAicte) {
      return res.status(409).json({
        success: false,
        error: 'An account with this AICTE Permanent ID / Bank IFSC code already exists.'
      });
    }
    let portal_module;
    let is_internal = false;
    if (role === 'AICTE RO' || role === 'Finance HQ') {
      is_internal = true;
      portal_module = role === 'AICTE RO' ? 'Scrutiny Queue' : 'Final Settlement';
    } else if (role === 'Institute Login') {
      portal_module = 'Portfolio & Tracker';
    } else if (role === 'Bank Node') {
      portal_module = 'Verification Desk';
    } else {
      return res.status(400).json({
        success: false,
        error: 'Invalid role specified for registration.'
      });
    }
    const newUser = new User({
      role,
      portal_module,
      email: email.trim().toLowerCase(),
      password,
      organization_name: organization_name || null,
      aicte_or_ifsc_code: aicte_or_ifsc_code.trim().toUpperCase()
    });
    await newUser.save();
    if (role === 'Institute Login' && !is_internal) {
      await Institute.updateOne(
        { aicte_permanent_id: aicte_or_ifsc_code.trim().toUpperCase() },
        {
          $setOnInsert: {
            aicte_permanent_id: aicte_or_ifsc_code.trim().toUpperCase(),
            institute_name: organization_name || 'New Institute',
            trust_name: organization_name ? organization_name + ' Trust' : 'New Trust',
            region: 'Southern',
            state: 'Tamil Nadu',
            contact_email: email.trim(),
            contact_mobile: '+91-98XXXXXX10',
            compliance_scrutiny: {
              has_infrastructure_deficiency: false,
              has_faculty_salary_dispute: false,
              has_vigilance_or_court_case: false,
              approval_timeline_exceeded: false,
              active_penalty_amount: 0,
              scrutiny_remarks: 'Institute onboarded via self-registration flow.'
            }
          }
        },
        { upsert: true }
      );
    }
    await AuditLog.create({
      fdr_number: 'SSO-SESSION',
      aicte_permanent_id: aicte_or_ifsc_code.trim().toUpperCase(),
      actor_role: role,
      actor_name: organization_name || email,
      action_type: 'ACCOUNT_REGISTERED',
      previous_status: 'ANONYMOUS',
      new_status: 'REGISTERED',
      remarks: `New ${role} account registered via self-service portal.`
    });
    res.json({ success: true, user: publicUser(newUser) });
  } catch (err) {
    console.error('Registration error:', err.message);
    res.status(500).json({ success: false, error: err.message });
  }
});

// -----------------------------------------------------------------------------
// Maturity notification gateway endpoints
// -----------------------------------------------------------------------------

app.get('/api/notifications/logs', async (req, res) => {
  try {
    const limit = Math.min(Math.max(Number(req.query.limit) || 100, 1), 500);
    const logs = await NotificationLog.find().sort({ timestamp: -1 }).limit(limit);
    const windowCounts = await getMaturityWindowCounts();
    res.json({
      success: true,
      logs,
      window_counts: windowCounts,
      scheduler: { ...schedulerState }
    });
  } catch (err) {
    res.status(500).json({ success: false, error: err.message });
  }
});

app.post('/api/notifications/run-scheduler', async (req, res) => {
  try {
    const force = req.body?.force !== false;
    const triggeredBy = req.body?.triggered_by || 'FINANCE_HQ_MANUAL';
    const result = await runMaturityNotificationScheduler(triggeredBy, { force });
    res.json({
      success: true,
      triggered_by: triggeredBy,
      dispatched_count: result.dispatched.length,
      logs: result.dispatched,
      window_counts: result.windowCounts,
      scheduler: result.scheduler
    });
  } catch (err) {
    res.status(500).json({ success: false, error: err.message });
  }
});

const PORT = process.env.PORT || 5000;
const upload = multer({ storage: multer.memoryStorage(), limits: { fileSize: 8 * 1024 * 1024 } });

function extractFields(text) {
  const clean = text.replace(/[ \t]+/g, ' ');
  const ifsc = (clean.match(/\b[A-Z]{4}0[A-Z0-9]{6}\b/i) || [])[0];
  const dateMatch = clean.match(/\b\d{1,2}[\/\-.]\d{1,2}[\/\-.]\d{2,4}\b/g) || [];
  const fdr = (clean.match(/(?:FDR|F\.D\.R|Receipt|Deposit)\s*(?:No\.?|Number|#)?\s*[:\-]?\s*([A-Z0-9\-\/]{6,25})/i) || [])[1];
  const amountMatch = clean.match(/(?:Rs\.?|INR|₹)\s*([\d,]+(?:\.\d{1,2})?)/i);

  return {
    fdrNumber: fdr || null,
    ifsc: ifsc ? ifsc.toUpperCase() : null,
    dates: dateMatch,
    amount: amountMatch ? amountMatch[1].replace(/,/g, '') : null,
  };
}

app.post('/api/ocr/extract', upload.single('file'), async (req, res) => {
  try {
    if (!req.file) return res.status(400).json({ error: 'No file uploaded' });
    const result = await Tesseract.recognize(req.file.buffer, 'eng');
    const text = result.data.text;
    res.json({ rawText: text, fields: extractFields(text) });
  } catch (e) {
    res.status(500).json({ error: 'OCR failed', detail: e.message });
  }
});
app.listen(PORT, () => console.log(`🚀 e-Kosh Backend running on http://localhost:${PORT}`));
