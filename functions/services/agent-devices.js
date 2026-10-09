const db = require("./db");
const { schemaOnce } = require("./schema-once");

async function ensureAgentDevicesSchema(executor = db) {
  await executor.query(`
    ALTER TABLE user_devices
    ADD COLUMN IF NOT EXISTS agent_device_registered BOOLEAN DEFAULT FALSE
  `);
  await executor.query(`
    CREATE TABLE IF NOT EXISTS agent_devices (
      id BIGSERIAL PRIMARY KEY,
      agent_id INTEGER NOT NULL REFERENCES agents(id) ON DELETE CASCADE,
      device_token TEXT NOT NULL,
      platform TEXT,
      push_status TEXT NOT NULL DEFAULT 'registered',
      last_push_at TIMESTAMPTZ,
      last_push_success_at TIMESTAMPTZ,
      last_push_failure_at TIMESTAMPTZ,
      last_push_error TEXT,
      created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
      updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
    )
  `);
  await executor.query(`
    ALTER TABLE agent_devices ADD COLUMN IF NOT EXISTS app_language TEXT
  `);
  await executor.query(`
    CREATE UNIQUE INDEX IF NOT EXISTS idx_agent_devices_device_token
    ON agent_devices(device_token)
  `);
  await executor.query(`
    CREATE INDEX IF NOT EXISTS idx_agent_devices_agent_id
    ON agent_devices(agent_id)
  `);
  await executor.query(`
    INSERT INTO agent_devices
      (agent_id, device_token, platform, push_status, created_at, updated_at)
    SELECT DISTINCT ON (ud.device_token)
      ud.agent_id, ud.device_token, ud.platform,
      COALESCE(ud.push_status, 'registered'),
      COALESCE(ud.created_at, NOW()), COALESCE(ud.updated_at, NOW())
    FROM user_devices ud
    WHERE ud.agent_id IS NOT NULL
      AND ud.agent_device_registered IS TRUE
      AND ud.device_token IS NOT NULL
      AND TRIM(ud.device_token) <> ''
      AND TRIM(ud.device_token) <> 'NO_TOKEN'
    ORDER BY ud.device_token, ud.updated_at DESC NULLS LAST
    ON CONFLICT (device_token) DO NOTHING
  `);
  await executor.query(`
    UPDATE user_devices ud
    SET device_token=NULL, updated_at=NOW()
    FROM agent_devices ad, agents a, users u
    WHERE a.id=ad.agent_id
      AND u.id=ud.user_id
      AND ud.device_token=ad.device_token
      AND LOWER(TRIM(u.email)) <> LOWER(TRIM(a.email))
  `);
}

// Schema setup runs once per warm instance (see schema-once.js).
ensureAgentDevicesSchema = schemaOnce("agent-devices:ensureAgentDevicesSchema", ensureAgentDevicesSchema);

module.exports = { ensureAgentDevicesSchema };
