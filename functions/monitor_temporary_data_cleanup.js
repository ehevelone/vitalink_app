const db = require("./services/db");
const { createMailer, fromAddress } = require("./services/mailer");
const {
  JOB_NAME,
  ensureMaintenanceSchema,
} = require("./services/temporary-data-cleanup");

async function sendStaleAlert() {
  const to = String(
    process.env.CLEANUP_ALERT_EMAIL || process.env.SMTP_USER || ""
  ).trim();
  if (!to) return false;
  await createMailer().sendMail({
    from: fromAddress("VitaLink System"),
    to,
    subject: "VitaLink temporary-data cleanup is overdue",
    text: "The hourly temporary-data cleanup has not reported a successful run in the expected window. Review the Netlify scheduled functions and logs.",
  });
  return true;
}

exports.handler = async () => {
  try {
    await ensureMaintenanceSchema();
    const result = await db.query(
      `SELECT last_succeeded_at, last_alerted_at
       FROM maintenance_job_runs
       WHERE job_name=$1
       LIMIT 1`,
      [JOB_NAME]
    );
    const row = result.rows[0];
    if (!row) {
      await db.query(
        `INSERT INTO maintenance_job_runs (job_name, last_started_at)
         VALUES ($1,NOW())
         ON CONFLICT (job_name) DO NOTHING`,
        [JOB_NAME]
      );
      return {
        statusCode: 200,
        body: JSON.stringify({ success: true, stale: false, initializing: true }),
      };
    }
    const lastSuccess = row?.last_succeeded_at
      ? new Date(row.last_succeeded_at).getTime()
      : 0;
    const stale = lastSuccess < Date.now() - 2 * 60 * 60 * 1000;
    if (!stale) {
      return { statusCode: 200, body: JSON.stringify({ success: true, stale: false }) };
    }

    const lastAlert = row?.last_alerted_at
      ? new Date(row.last_alerted_at).getTime()
      : 0;
    const alertDue = lastAlert < Date.now() - 6 * 60 * 60 * 1000;
    if (alertDue && await sendStaleAlert()) {
      await db.query(
        `INSERT INTO maintenance_job_runs (job_name, last_alerted_at)
         VALUES ($1,NOW())
         ON CONFLICT (job_name) DO UPDATE SET last_alerted_at=NOW()`,
        [JOB_NAME]
      );
    }
    console.warn("temporary_data_cleanup_overdue", new Date().toISOString());
    return { statusCode: 200, body: JSON.stringify({ success: true, stale: true }) };
  } catch (_) {
    console.error("temporary_data_cleanup_monitor_failed", new Date().toISOString());
    return { statusCode: 500, body: JSON.stringify({ success: false }) };
  }
};
