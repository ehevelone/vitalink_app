const db = require("./db");

const AGREEMENT_VERSION = "2026-09-30";
const MESSAGING_CONSENT_VERSION = "2026-09-30";

async function ensureAccountAccessSchema() {
  await db.query(`
    ALTER TABLE users
    ADD COLUMN IF NOT EXISTS access_sponsor TEXT,
    ADD COLUMN IF NOT EXISTS relationship_status TEXT,
    ADD COLUMN IF NOT EXISTS relationship_confirmed_at TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS relationship_review_requested_at TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS messaging_consent_status TEXT,
    ADD COLUMN IF NOT EXISTS messaging_consent_version TEXT,
    ADD COLUMN IF NOT EXISTS messaging_consented_at TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS messaging_withdrawn_at TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS user_agreement_version TEXT,
    ADD COLUMN IF NOT EXISTS user_agreement_accepted_at TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS access_prompted_at TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS access_prompt_count INTEGER NOT NULL DEFAULT 0
  `);

  await db.query(`
    UPDATE users
    SET access_sponsor = CASE
          WHEN agent_id IS NOT NULL THEN 'agent'
          WHEN purchase_code IS NOT NULL THEN 'personal'
          ELSE 'locked'
        END,
        relationship_status = CASE
          WHEN agent_id IS NOT NULL THEN 'pending_confirmation'
          ELSE 'not_applicable'
        END,
        messaging_consent_status = CASE
          WHEN agent_id IS NOT NULL THEN 'pending'
          ELSE 'not_applicable'
        END
    WHERE access_sponsor IS NULL
       OR relationship_status IS NULL
       OR messaging_consent_status IS NULL
  `);

  await db.query(`
    CREATE TABLE IF NOT EXISTS user_consent_events (
      id BIGSERIAL PRIMARY KEY,
      user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      agent_id INTEGER REFERENCES agents(id) ON DELETE SET NULL,
      event_type TEXT NOT NULL,
      event_value TEXT,
      agreement_version TEXT,
      consent_version TEXT,
      platform TEXT,
      device_id TEXT,
      created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
    )
  `);

  await db.query(`
    CREATE INDEX IF NOT EXISTS idx_user_consent_events_user
    ON user_consent_events (user_id, created_at DESC)
  `);

  await db.query(`
    CREATE TABLE IF NOT EXISTS policy_relationship_reviews (
      id BIGSERIAL PRIMARY KEY,
      user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      agent_id INTEGER REFERENCES agents(id) ON DELETE SET NULL,
      match_type TEXT NOT NULL,
      status TEXT NOT NULL DEFAULT 'pending',
      created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
      reviewed_at TIMESTAMPTZ,
      reviewed_by TEXT
    )
  `);
}

async function recordConsentEvent({
  userId,
  agentId,
  eventType,
  eventValue,
  platform,
  deviceId,
}) {
  await db.query(
    `INSERT INTO user_consent_events
      (user_id, agent_id, event_type, event_value, agreement_version,
       consent_version, platform, device_id)
     VALUES ($1,$2,$3,$4,$5,$6,$7,$8)`,
    [
      userId,
      agentId || null,
      eventType,
      eventValue || null,
      AGREEMENT_VERSION,
      MESSAGING_CONSENT_VERSION,
      platform || null,
      deviceId || null,
    ]
  );
}

module.exports = {
  AGREEMENT_VERSION,
  MESSAGING_CONSENT_VERSION,
  ensureAccountAccessSchema,
  recordConsentEvent,
};
