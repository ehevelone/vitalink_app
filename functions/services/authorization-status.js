const db = require('./db');

async function ensureAuthorizationSchema() {
  await db.query(`
    CREATE TABLE IF NOT EXISTS user_authorization_status (
      user_id INTEGER PRIMARY KEY REFERENCES users(id),
      agent_id INTEGER,
      signed_at TIMESTAMPTZ,
      revoked_at TIMESTAMPTZ,
      agent_notified_at TIMESTAMPTZ,
      updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
    )
  `);
  await db.query(`
    ALTER TABLE crm_clients
    ADD COLUMN IF NOT EXISTS authorization_revoked_at TIMESTAMPTZ
  `);
}

async function getAuthorizedUser(userId, sessionToken) {
  if (!/^\d+$/.test(String(userId || '')) || !sessionToken) return null;
  const result = await db.query(`
    SELECT u.id, u.first_name, u.last_name, u.email, u.agent_id,
           a.name AS agent_name, a.email AS agent_email, a.crm_uuid
    FROM users u
    JOIN agents a ON a.id = u.agent_id
    WHERE u.id = $1 AND u.session_token = $2
      AND u.session_expires > NOW()
    LIMIT 1
  `, [userId, sessionToken]);
  return result.rows[0] || null;
}

async function getStatus(userId) {
  const result = await db.query(`
    SELECT signed_at, revoked_at, agent_notified_at
    FROM user_authorization_status WHERE user_id = $1
  `, [userId]);
  return result.rows[0] || null;
}

async function recordSigning(userId, agentId, signedAt) {
  await ensureAuthorizationSchema();
  await db.query(`
    INSERT INTO user_authorization_status
      (user_id, agent_id, signed_at, revoked_at, agent_notified_at)
    VALUES ($1, $2, $3, NULL, NULL)
    ON CONFLICT (user_id) DO UPDATE SET
      agent_id = EXCLUDED.agent_id,
      signed_at = EXCLUDED.signed_at,
      revoked_at = NULL,
      agent_notified_at = NULL,
      updated_at = NOW()
  `, [userId, agentId, signedAt]);
}

async function recordRevocation(userId, agentId) {
  await ensureAuthorizationSchema();
  const result = await db.query(`
    INSERT INTO user_authorization_status
      (user_id, agent_id, revoked_at)
    VALUES ($1, $2, NOW())
    ON CONFLICT (user_id) DO UPDATE SET
      agent_id = EXCLUDED.agent_id,
      revoked_at = CASE
        WHEN user_authorization_status.agent_id IS DISTINCT FROM EXCLUDED.agent_id
          THEN NOW()
        ELSE COALESCE(user_authorization_status.revoked_at, NOW())
      END,
      agent_notified_at = CASE
        WHEN user_authorization_status.agent_id IS DISTINCT FROM EXCLUDED.agent_id
          THEN NULL
        ELSE user_authorization_status.agent_notified_at
      END,
      updated_at = NOW()
    RETURNING revoked_at, agent_notified_at
  `, [userId, agentId]);
  return result.rows[0];
}

async function markAgentNotified(userId) {
  await db.query(`
    UPDATE user_authorization_status
    SET agent_notified_at = NOW(), updated_at = NOW()
    WHERE user_id = $1 AND revoked_at IS NOT NULL
  `, [userId]);
}

async function markCrmRevoked(userId, crmAgentId, revokedAt) {
  if (!crmAgentId) return false;
  const result = await db.query(`
    UPDATE crm_clients
    SET authorization_revoked_at = $3, updated_at = NOW()
    WHERE agent_id = $2
      AND id IN (
        SELECT crm_client_id FROM crm_vitalink_packages
        WHERE app_user_id = $1 AND crm_agent_id = $2
      )
  `, [String(userId), String(crmAgentId), revokedAt]);
  return result.rowCount > 0;
}

module.exports = {
  ensureAuthorizationSchema,
  getAuthorizedUser,
  getStatus,
  recordSigning,
  recordRevocation,
  markAgentNotified,
  markCrmRevoked,
};
