const db = require("./db");
const { ensureSchema: ensureDeviceTransferSchema } = require("./device-transfer");
const {
  cleanupExpiredPackages,
  cleanupExpiredShareInvites,
  ensureSchema: ensureProfileShareSchema,
} = require("./profile-share-sync");
const {
  cleanupExpiredAccessCodeAttempts,
  ensureAccessCodeRateLimitSchema,
} = require("./access-code-rate-limit");

const JOB_NAME = "temporary_data_cleanup";

async function ensureMaintenanceSchema() {
  await db.query(`
    CREATE TABLE IF NOT EXISTS maintenance_job_runs (
      job_name TEXT PRIMARY KEY,
      last_started_at TIMESTAMPTZ,
      last_succeeded_at TIMESTAMPTZ,
      last_failed_at TIMESTAMPTZ,
      last_alerted_at TIMESTAMPTZ,
      last_error TEXT,
      last_counts JSONB NOT NULL DEFAULT '{}'::jsonb
    )
  `);
}

async function cleanupDeviceTransfers() {
  const summary = await db.query(`
    SELECT
      COUNT(*) FILTER (WHERE expires_at <= NOW())::INTEGER AS expired_count,
      COUNT(*) FILTER (
        WHERE expires_at <= NOW()
          AND chunk_count <> (
            SELECT COUNT(*)::INTEGER
            FROM device_transfer_chunks c
            WHERE c.transfer_id = p.id
          )
      )::INTEGER AS incomplete_count,
      COUNT(*) FILTER (
        WHERE status IN ('consumed', 'completed')
      )::INTEGER AS consumed_count
    FROM device_transfer_packages p
    WHERE expires_at <= NOW()
       OR status IN ('consumed', 'completed')
  `);
  const deleted = await db.query(`
    DELETE FROM device_transfer_packages
    WHERE expires_at <= NOW()
       OR status IN ('consumed', 'completed')
  `);
  return {
    deleted: deleted.rowCount || 0,
    expired: Number(summary.rows[0]?.expired_count || 0),
    incomplete: Number(summary.rows[0]?.incomplete_count || 0),
    consumed: Number(summary.rows[0]?.consumed_count || 0),
  };
}

async function cleanupAgentInvites() {
  const table = await db.query(`SELECT to_regclass('public.agent_invites') AS name`);
  if (!table.rows[0]?.name) return 0;
  const result = await db.query(`
    DELETE FROM agent_invites
    WHERE expires_at <= NOW() OR used = TRUE
  `);
  return result.rowCount || 0;
}

async function markStarted() {
  await db.query(
    `INSERT INTO maintenance_job_runs (job_name, last_started_at)
     VALUES ($1,NOW())
     ON CONFLICT (job_name) DO UPDATE SET last_started_at=NOW()`,
    [JOB_NAME]
  );
}

async function markSucceeded(counts) {
  await db.query(
    `UPDATE maintenance_job_runs
     SET last_succeeded_at=NOW(), last_error=NULL, last_counts=$2::jsonb
     WHERE job_name=$1`,
    [JOB_NAME, JSON.stringify(counts)]
  );
}

async function markFailed() {
  try {
    await ensureMaintenanceSchema();
    await db.query(
      `INSERT INTO maintenance_job_runs (job_name, last_started_at, last_failed_at, last_error)
       VALUES ($1,NOW(),NOW(),'Cleanup failed')
       ON CONFLICT (job_name) DO UPDATE
       SET last_failed_at=NOW(), last_error='Cleanup failed'`,
      [JOB_NAME]
    );
  } catch (_) {
    // The scheduler log and failure email remain available if the database is down.
  }
}

async function runTemporaryDataCleanup() {
  await ensureDeviceTransferSchema({ cleanup: false });
  await ensureProfileShareSchema();
  await ensureAccessCodeRateLimitSchema();
  await ensureMaintenanceSchema();
  await markStarted();

  const deviceTransfers = await cleanupDeviceTransfers();
  const caregiverPackages = await cleanupExpiredPackages();
  const caregiverInvites = await cleanupExpiredShareInvites();
  const accessCodeAttempts = await cleanupExpiredAccessCodeAttempts();
  const agentInvites = await cleanupAgentInvites();
  const counts = {
    deviceTransfers,
    caregiverPackages,
    caregiverInvites,
    accessCodeAttempts,
    agentInvites,
  };
  await markSucceeded(counts);
  return counts;
}

module.exports = {
  JOB_NAME,
  ensureMaintenanceSchema,
  markFailed,
  runTemporaryDataCleanup,
};
