const crypto = require("crypto");
const db = require("./db");

const MAX_FAILURES = 5;
const WINDOW_MINUTES = 15;
const LOCK_MINUTES = 15;
const AGGREGATE_ALERT_THRESHOLD = 25;

async function ensureAccessCodeRateLimitSchema() {
  await db.query(`
    CREATE TABLE IF NOT EXISTS access_code_attempts (
      scope_key TEXT PRIMARY KEY,
      failed_count INTEGER NOT NULL DEFAULT 0,
      window_started_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
      locked_until TIMESTAMPTZ,
      updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
    )
  `);
  await db.query(`
    CREATE TABLE IF NOT EXISTS access_code_aggregate_attempts (
      code_fingerprint TEXT PRIMARY KEY,
      failed_count INTEGER NOT NULL DEFAULT 0,
      window_started_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
      last_alerted_at TIMESTAMPTZ,
      updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
    )
  `);
}

function codeFingerprint(code) {
  const secret = process.env.ACCESS_CODE_MONITOR_SECRET || process.env.ENCRYPTION_KEY;
  if (!secret || !code) return null;
  return crypto
    .createHmac("sha256", String(secret))
    .update(String(code).trim().toUpperCase())
    .digest("hex");
}

async function sendAggregateAlert({ fingerprint, failedCount }) {
  const { createMailer, fromAddress } = require("./mailer");
  const to = String(
    process.env.SECURITY_ALERT_EMAIL ||
      process.env.CLEANUP_ALERT_EMAIL ||
      process.env.SMTP_USER ||
      ""
  ).trim();
  if (!to) return false;
  await createMailer().sendMail({
    from: fromAddress("VitaLink Security"),
    to,
    subject: "Repeated VitaLink access-code failures detected",
    text: [
      "Repeated failed attempts against the same access-code value were detected.",
      `Failure count: ${failedCount}`,
      `Keyed code fingerprint: ${fingerprint}`,
      "The submitted code and user identifiers are not included in this alert.",
    ].join("\n"),
  });
  return true;
}

async function recordAggregateCodeFailure(code) {
  const fingerprint = codeFingerprint(code);
  if (!fingerprint) return;
  const result = await db.query(
    `INSERT INTO access_code_aggregate_attempts
       (code_fingerprint, failed_count, window_started_at, updated_at)
     VALUES ($1,1,NOW(),NOW())
     ON CONFLICT (code_fingerprint) DO UPDATE SET
       failed_count=CASE
         WHEN access_code_aggregate_attempts.window_started_at <= NOW() - INTERVAL '${WINDOW_MINUTES} minutes'
           THEN 1
         ELSE access_code_aggregate_attempts.failed_count + 1
       END,
       window_started_at=CASE
         WHEN access_code_aggregate_attempts.window_started_at <= NOW() - INTERVAL '${WINDOW_MINUTES} minutes'
           THEN NOW()
         ELSE access_code_aggregate_attempts.window_started_at
       END,
       last_alerted_at=CASE
         WHEN access_code_aggregate_attempts.window_started_at <= NOW() - INTERVAL '${WINDOW_MINUTES} minutes'
           THEN NULL
         ELSE access_code_aggregate_attempts.last_alerted_at
       END,
       updated_at=NOW()
     RETURNING failed_count, last_alerted_at`,
    [fingerprint]
  );
  const row = result.rows[0];
  if (Number(row?.failed_count || 0) < AGGREGATE_ALERT_THRESHOLD || row?.last_alerted_at) {
    return;
  }
  try {
    if (await sendAggregateAlert({
      fingerprint,
      failedCount: Number(row.failed_count),
    })) {
      await db.query(
        `UPDATE access_code_aggregate_attempts
         SET last_alerted_at=NOW()
         WHERE code_fingerprint=$1`,
        [fingerprint]
      );
    }
  } catch (_) {
    console.error("access_code_aggregate_alert_failed", new Date().toISOString());
  }
}

function rateLimitScope(prefix, value) {
  const digest = crypto
    .createHash("sha256")
    .update(`${prefix}:${String(value || "unknown")}`)
    .digest("hex");
  return `${prefix}:${digest}`;
}

function requestIp(event) {
  const headers = event.headers || {};
  const forwarded = headers["x-forwarded-for"] || headers["X-Forwarded-For"];
  return String(
    headers["x-nf-client-connection-ip"] ||
      headers["X-Nf-Client-Connection-Ip"] ||
      headers["client-ip"] ||
      headers["Client-Ip"] ||
      forwarded ||
      "unknown"
  )
    .split(",")[0]
    .trim();
}

async function checkAccessCodeLimit(scopeKey) {
  await ensureAccessCodeRateLimitSchema();
  const result = await db.query(
    `SELECT locked_until FROM access_code_attempts WHERE scope_key=$1 LIMIT 1`,
    [scopeKey]
  );
  const lockedUntil = result.rows[0]?.locked_until
    ? new Date(result.rows[0].locked_until)
    : null;
  if (!lockedUntil || lockedUntil.getTime() <= Date.now()) {
    return { allowed: true, retryAfterSeconds: 0 };
  }
  return {
    allowed: false,
    retryAfterSeconds: Math.max(1, Math.ceil((lockedUntil.getTime() - Date.now()) / 1000)),
  };
}

async function recordAccessCodeFailure(scopeKey, submittedCode) {
  await ensureAccessCodeRateLimitSchema();
  const result = await db.query(
    `INSERT INTO access_code_attempts
       (scope_key, failed_count, window_started_at, locked_until, updated_at)
     VALUES ($1,1,NOW(),NULL,NOW())
     ON CONFLICT (scope_key) DO UPDATE SET
       failed_count=CASE
         WHEN access_code_attempts.window_started_at <= NOW() - INTERVAL '${WINDOW_MINUTES} minutes'
           THEN 1
         ELSE access_code_attempts.failed_count + 1
       END,
       window_started_at=CASE
         WHEN access_code_attempts.window_started_at <= NOW() - INTERVAL '${WINDOW_MINUTES} minutes'
           THEN NOW()
         ELSE access_code_attempts.window_started_at
       END,
       locked_until=CASE
         WHEN access_code_attempts.window_started_at > NOW() - INTERVAL '${WINDOW_MINUTES} minutes'
          AND access_code_attempts.failed_count + 1 >= ${MAX_FAILURES}
           THEN NOW() + INTERVAL '${LOCK_MINUTES} minutes'
         ELSE NULL
       END,
       updated_at=NOW()
     RETURNING failed_count, locked_until`,
    [scopeKey]
  );
  await recordAggregateCodeFailure(submittedCode);
  return {
    locked: Boolean(result.rows[0]?.locked_until),
    failures: Number(result.rows[0]?.failed_count || 1),
  };
}

async function clearAccessCodeFailures(scopeKey) {
  await ensureAccessCodeRateLimitSchema();
  await db.query("DELETE FROM access_code_attempts WHERE scope_key=$1", [scopeKey]);
}

async function cleanupExpiredAccessCodeAttempts() {
  await ensureAccessCodeRateLimitSchema();
  const result = await db.query(`
    DELETE FROM access_code_attempts
    WHERE (locked_until IS NOT NULL AND locked_until <= NOW())
       OR (locked_until IS NULL AND updated_at <= NOW() - INTERVAL '${WINDOW_MINUTES} minutes')
  `);
  const aggregate = await db.query(`
    DELETE FROM access_code_aggregate_attempts
    WHERE updated_at <= NOW() - INTERVAL '${WINDOW_MINUTES} minutes'
  `);
  return (result.rowCount || 0) + (aggregate.rowCount || 0);
}

module.exports = {
  checkAccessCodeLimit,
  cleanupExpiredAccessCodeAttempts,
  clearAccessCodeFailures,
  ensureAccessCodeRateLimitSchema,
  rateLimitScope,
  recordAccessCodeFailure,
  requestIp,
};
