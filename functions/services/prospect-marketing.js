const db = require("./db");
const { schemaOnce } = require("./schema-once");

const CONTACT_REQUEST_VERSION = "2026-10-01";
const MAX_SENDS_PER_30_DAYS = Number(process.env.PROSPECT_MESSAGE_30_DAY_LIMIT || 3);

const TEMPLATES = {
  medicare_aep: {
    category: "medicare",
    topic: "Medicare",
    label: "AEP reminder",
    text: (name) => `AEP begins October 15. Would you like to schedule a Medicare coverage review? Contact ${name}.`,
    textEs: (name) => `El AEP comienza el 15 de octubre. ¿Desea programar una revisión de su cobertura de Medicare? Comuníquese con ${name}.`,
  },
  medicare_window: {
    category: "medicare",
    topic: "Medicare",
    label: "Enrollment window",
    text: (name) => `Your Medicare enrollment window is approaching. Tap here if you'd like ${name} to reach out.`,
    textEs: (name) => `Se acerca su período de inscripción en Medicare. Toque aquí si desea que ${name} se comunique con usted.`,
  },
  medicare_options: {
    category: "medicare",
    topic: "Medicare",
    label: "Medicare conversation",
    text: (name) => `Would you like to talk about your Medicare options? Contact ${name}.`,
    textEs: (name) => `¿Desea hablar sobre sus opciones de Medicare? Comuníquese con ${name}.`,
  },
  life_awareness: {
    category: "life",
    topic: "Life Insurance",
    label: "Life Insurance Awareness Month",
    text: (name) => `It's Life Insurance Awareness Month. Would you like to talk with ${name}?`,
    textEs: (name) => `Es el mes de concientización sobre el seguro de vida. ¿Desea hablar con ${name}?`,
  },
  life_family: {
    category: "life",
    topic: "Life Insurance",
    label: "Family coverage",
    text: (name) => `Would you like to discuss life insurance options for you or your family? Contact ${name}.`,
    textEs: (name) => `¿Desea hablar sobre opciones de seguro de vida para usted o su familia? Comuníquese con ${name}.`,
  },
};

function marketingEnabled(category) {
  if (process.env.PROSPECT_MARKETING_ENABLED === "false") return false;
  const key = `PROSPECT_${String(category).toUpperCase()}_SENDING_ENABLED`;
  return process.env[key] !== "false";
}

async function ensureProspectMarketingSchema() {
  await db.query(`
    CREATE TABLE IF NOT EXISTS prospect_marketing_deliveries (
      id UUID PRIMARY KEY,
      user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      agent_id INTEGER NOT NULL REFERENCES agents(id) ON DELETE CASCADE,
      category TEXT NOT NULL,
      template_id TEXT NOT NULL,
      status TEXT NOT NULL DEFAULT 'queued',
      sent_at TIMESTAMPTZ,
      opened_at TIMESTAMPTZ,
      request_submitted_at TIMESTAMPTZ,
      created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
    )
  `);
  await db.query(`
    CREATE INDEX IF NOT EXISTS idx_prospect_deliveries_frequency
    ON prospect_marketing_deliveries (user_id, agent_id, category, sent_at DESC)
  `);
  await db.query(`
    CREATE TABLE IF NOT EXISTS prospect_contact_requests (
      id UUID PRIMARY KEY,
      delivery_id UUID NOT NULL UNIQUE REFERENCES prospect_marketing_deliveries(id) ON DELETE CASCADE,
      user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      agent_id INTEGER NOT NULL REFERENCES agents(id) ON DELETE CASCADE,
      category TEXT NOT NULL,
      template_id TEXT NOT NULL,
      channels JSONB NOT NULL,
      request_text TEXT NOT NULL,
      request_version TEXT NOT NULL,
      platform TEXT,
      created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
    )
  `);
}

// Schema setup runs once per warm instance (see schema-once.js).
ensureProspectMarketingSchema = schemaOnce("prospect-marketing:ensureProspectMarketingSchema", ensureProspectMarketingSchema);

module.exports = {
  CONTACT_REQUEST_VERSION,
  MAX_SENDS_PER_30_DAYS,
  TEMPLATES,
  ensureProspectMarketingSchema,
  marketingEnabled,
};
