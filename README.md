# e-Kosh AICTE — FDR Security Deposit Portal

Flutter Web prototype for the AICTE e-Kosh security-deposit lifecycle: joint FDR
submission, bank lien verification, regional scrutiny, penalty / forfeiture,
e-NOC QR settlement, executive analytics, an immutable audit trail and the
bilingual "Ask e-Kosh AI" assistant.

## Run locally

```bash
# 1. Start the Node + MongoDB API (port 5000)
cd ekosh_backend
npm install
node server.js

# 2. Serve the Flutter web app (port 8902)
cd ..
flutter pub get
flutter build web
cd build/web && python3 -m http.server 8902
```

The backend seeds the four SSO accounts into the `users` collection on boot and
exposes `POST /api/auth/login`, `PATCH /api/auth/reset-password` and
`GET /api/dashboard-data`. The app calls these endpoints first and falls back
to the bundled demo credentials only when the API is unreachable.

The boot sequence also seeds a demonstration portfolio (`FDR-AICTE-ALERT-090`,
`-060`, `-030` and `-120`) whose maturity dates always sit inside the 90, 60,
30 and 120-day horizons, so the pre-maturity engine can be demonstrated without
waiting for real deposit dates.

## Government (GIGW 3.0 / NIC) interface

The login gateway and all four dashboards share the same official chrome:

- 32 px `#0F172A` top strip with the tricolour, `भारत सरकार | GOVERNMENT OF INDIA`,
  **Skip to Main Content**, **Screen Reader Access** and `A- / A / A+` /
  `English / हिन्दी` controls.
- 76 px white AICTE masthead with a 3 px gold `#D97706` rule, the
  `G2G / G2B Integrated` and `APH 2024-27 Compliant` badges and, once signed in,
  the active officer badge (role, email / code, **NIC SSO VERIFIED**) plus
  **LOGOUT / SWITCH ACCOUNT**.
- 34 px `#FEF3C7` circular ticker with a red **LATEST CIRCULAR** pill covering
  digital lien verification, the 90/60/30-day alerts and QR-verified e-NOC.
- Breadcrumb bar `Home > e-Kosh AICTE > [Portal] > [Module]` with a live IST
  server clock.
- Navy `#1E3A8A` sidebar with a 4 px gold active bar, KPI cards with a 4 px top
  accent, navy table headers with zebra rows and a 40 px `#0F172A` footer.

## Automated 90 / 60 / 30-day Email & SMS engine

`ekosh_backend/server.js` runs `runMaturityNotificationScheduler()` on startup
and every 24 hours. For every active FDR inside a milestone window it sends the
official Email + SMS advisory once, then records the dispatch:

- `timeline.alerts_sent.alert_90_sent`, `alert_60_sent`, `alert_30_sent` and
  `last_alert_timestamp` guarantee a single dispatch per FDR per window.
- Each delivery is written to `notification_logs` with the FDR number, AICTE ID,
  institute, recipient email / mobile, milestone (`90_DAYS` / `60_DAYS` /
  `30_DAYS`), channels (`EMAIL`, `SMS`), message preview, delivery status,
  trigger (`AUTO_CRON_SCHEDULER` / `FINANCE_HQ_MANUAL`) and timestamp.
- Audit entries `MATURITY_ALERT_DISPATCHED_90D` / `60D` / `30D` are appended to
  `audit_logs`.

Endpoints:

| Method | Endpoint | Purpose |
| --- | --- | --- |
| `GET` | `/api/notifications/logs` | Gateway ledger plus the live 90 / 60 / 30-day FDR counts |
| `POST` | `/api/notifications/run-scheduler` | Force a Finance HQ dispatch scan (`{"force": true}`) |

The Finance HQ dashboard renders the **📡 Automated Pre-Maturity Email & SMS
Dispatch Engine (NIC-SMS / SMTP Gateway)** panel with the three milestone cards,
an automatic check on page load, the **⚡ Run 90/60/30-Day Auto-Dispatch Scan
Now** button and the delivery ledger with a **View Official Message** preview of
the exact Email/SMS template. The Institute dashboard raises a countdown banner
whenever one of its FDRs enters the 90-day horizon and confirms that the
advisory was already delivered to the registered email and mobile number.

## Demo sign-in credentials

The portal opens on a centred GIGW 3.0 / NIC-styled AICTE single sign-on card
inside the official accessibility strip, masthead, circular ticker and footer.
Each of the four stakeholder tabs unlocks one role-scoped dashboard. Either the
full official email or the local part before `@` is accepted.

| Dashboard | User ID | Password |
| --- | --- | --- |
| Institute / College Admin | `principal@kpr.edu.in` | `Kpr@2026` |
| Partner Bank Node | `banknode@sbi.co.in` | `Sbi@2026` |
| AICTE Regional Officer | `ro.south@aicte.gov.in` | `RoSouth@2026` |
| AICTE Finance Bureau HQ | `finance.hq@aicte.gov.in` | `Finance@2026` |

Pick the matching stakeholder tab, enter the user ID and password above, then
type the six-character captcha shown in the challenge box before pressing
**AUTHENTICATE & PROCEED TO PORTAL**. Captcha matching is case-insensitive;
press the refresh icon for a new code. The **Forgot Password?** link opens
the official 3-step OTP recovery modal — request the OTP, verify the demo OTP
`654321`, then set a new password. When the backend is running the new password
is persisted to MongoDB; otherwise it applies to the current session only. After
signing in, your dashboard is fixed by the role returned from the database. To
change accounts, use **LOGOUT / SWITCH ACCOUNT** — this clears the session and
returns you to the government SSO gateway. Sign-in, sign-out and password-reset
events are written to the audit ledger.

## Tests

```bash
flutter analyze
flutter test
```

The widget suite covers the government sign-in gateway, all four role
dashboards, dialogs, the e-NOC / QR workflows, the AI assistant and the
pre-maturity notification engine (62 tests).
