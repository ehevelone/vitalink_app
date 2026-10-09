const db = require("./db");
const { schemaOnce } = require("./schema-once");

const AGREEMENT_VERSION = "2026-10-01";
const MESSAGING_CONSENT_VERSION = "2026-09-30";
const PROSPECT_CONSENT_VERSION = "2026-10-01";

const PROSPECT_CATEGORIES = {
  medicare: {
    label: "Medicare",
    durationDays: Number(process.env.PROSPECT_MEDICARE_CONSENT_DAYS || 365),
  },
  life: {
    label: "Life Insurance",
    durationDays: Number(process.env.PROSPECT_LIFE_CONSENT_DAYS || 365),
  },
};

// The exact text the user sees is stored with the consent, so a Spanish
// user's record holds the Spanish wording they agreed to.
function prospectConsentText(category, agentName, language = "en") {
  const config = PROSPECT_CATEGORIES[category];
  if (!config) return null;
  if (language === "es") return prospectConsentTextEs(category, config, agentName);
  const name = String(agentName || "your connected agent").trim();
  const topic = category === "medicare"
    ? "Medicare coverage options, enrollment periods, and invitations to request an appointment"
    : "life insurance information and invitations to request a conversation";
  const compensation = category === "medicare"
    ? "enroll in a plan"
    : "purchase coverage";

  return `I agree to receive in-app and push marketing messages from ${name}, a licensed insurance agent, about ${topic}. ${name} may be compensated if I ${compensation}. This permission applies only to ${name} and only to ${config.label} messages delivered through VitaLink. It does not authorize phone calls, text messages, or email. This consent is optional, is not required to use VitaLink, expires ${config.durationDays} days after I provide it, and may be withdrawn at any time.`;
}

function prospectConsentTextEs(category, config, agentName) {
  const name = String(agentName || "su agente conectado").trim();
  const topic = category === "medicare"
    ? "opciones de cobertura de Medicare, períodos de inscripción e invitaciones para solicitar una cita"
    : "información sobre seguros de vida e invitaciones para solicitar una conversación";
  const compensation = category === "medicare"
    ? "me inscribo en un plan"
    : "compro una cobertura";
  const label = category === "medicare" ? "Medicare" : "seguro de vida";

  return `Acepto recibir mensajes de mercadeo dentro de la aplicación y notificaciones de ${name}, agente de seguros con licencia, sobre ${topic}. ${name} puede recibir una compensación si ${compensation}. Este permiso se aplica solo a ${name} y solo a mensajes de ${label} enviados por medio de VitaLink. No autoriza llamadas telefónicas, mensajes de texto ni correos electrónicos. Este consentimiento es opcional, no es necesario para usar VitaLink, vence ${config.durationDays} días después de otorgarlo y puede retirarse en cualquier momento.`;
}

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

  await db.query(`
    CREATE TABLE IF NOT EXISTS prospect_marketing_consents (
      user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      agent_id INTEGER NOT NULL REFERENCES agents(id) ON DELETE CASCADE,
      category TEXT NOT NULL,
      status TEXT NOT NULL DEFAULT 'pending',
      consent_version TEXT NOT NULL,
      consent_text TEXT NOT NULL,
      granted_at TIMESTAMPTZ,
      withdrawn_at TIMESTAMPTZ,
      expires_at TIMESTAMPTZ,
      updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
      PRIMARY KEY (user_id, agent_id, category)
    )
  `);

  await db.query(`
    CREATE TABLE IF NOT EXISTS prospect_marketing_consent_events (
      id BIGSERIAL PRIMARY KEY,
      user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      agent_id INTEGER NOT NULL REFERENCES agents(id) ON DELETE CASCADE,
      category TEXT NOT NULL,
      status TEXT NOT NULL,
      consent_version TEXT NOT NULL,
      consent_text TEXT NOT NULL,
      platform TEXT,
      device_id TEXT,
      created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
    )
  `);

  await db.query(`
    CREATE INDEX IF NOT EXISTS idx_prospect_consents_agent_category
    ON prospect_marketing_consents (agent_id, category, status, expires_at)
  `);
}

async function setProspectConsent({
  userId,
  agentId,
  agentName,
  category,
  granted,
  declinedStatus,
  platform,
  deviceId,
  language,
}) {
  const config = PROSPECT_CATEGORIES[category];
  const consentText = prospectConsentText(category, agentName, language);
  if (!config || !consentText) throw new Error("Unsupported prospect category");

  const status = granted ? "granted" : (declinedStatus || "deferred");
  const expiresAt = granted
    ? new Date(Date.now() + config.durationDays * 24 * 60 * 60 * 1000)
    : null;

  await db.query(
    `INSERT INTO prospect_marketing_consents
      (user_id, agent_id, category, status, consent_version, consent_text,
       granted_at, withdrawn_at, expires_at, updated_at)
     VALUES ($1,$2,$3,$4,$5,$6,
       CASE WHEN $4='granted' THEN NOW() ELSE NULL END,
       NULL,$7,NOW())
     ON CONFLICT (user_id, agent_id, category) DO UPDATE SET
       status=EXCLUDED.status,
       consent_version=EXCLUDED.consent_version,
       consent_text=EXCLUDED.consent_text,
       granted_at=CASE WHEN EXCLUDED.status='granted' THEN NOW()
                       ELSE prospect_marketing_consents.granted_at END,
       withdrawn_at=NULL,
       expires_at=EXCLUDED.expires_at,
       updated_at=NOW()`,
    [userId, agentId, category, status, PROSPECT_CONSENT_VERSION, consentText, expiresAt]
  );

  await db.query(
    `INSERT INTO prospect_marketing_consent_events
      (user_id, agent_id, category, status, consent_version, consent_text,
       platform, device_id)
     VALUES ($1,$2,$3,$4,$5,$6,$7,$8)`,
    [userId, agentId, category, status, PROSPECT_CONSENT_VERSION,
      consentText, platform || null, deviceId || null]
  );
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

// Schema setup runs once per warm instance (see schema-once.js).
ensureAccountAccessSchema = schemaOnce("account-access:ensureAccountAccessSchema", ensureAccountAccessSchema);

module.exports = {
  AGREEMENT_VERSION,
  MESSAGING_CONSENT_VERSION,
  PROSPECT_CATEGORIES,
  PROSPECT_CONSENT_VERSION,
  ensureAccountAccessSchema,
  prospectConsentText,
  recordConsentEvent,
  setProspectConsent,
};
