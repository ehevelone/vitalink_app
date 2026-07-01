const crypto = require("crypto");
const db = require("./db");

const DOCUMENT_TYPES = Object.freeze({
  HIPAA: "hipaa",
  SOA: "soa",
  VITALINK_CSV: "vitalink_csv",
});

function digitsOnly(value) {
  return (value || "").toString().replace(/\D/g, "");
}

function clean(value) {
  const text = (value ?? "").toString().trim();
  return text || null;
}

function firstNonEmpty(...values) {
  for (const value of values) {
    const cleaned = clean(value);

    if (cleaned) {
      return cleaned;
    }
  }

  return null;
}

function splitName(name) {
  const parts = clean(name)?.split(/\s+/) || [];

  if (parts.length <= 1) {
    return {
      first_name: parts[0] || null,
      last_name: null,
    };
  }

  return {
    first_name: parts.slice(0, -1).join(" "),
    last_name: parts[parts.length - 1],
  };
}

function formatList(items, fields) {
  if (!Array.isArray(items)) {
    return null;
  }

  const lines = items
    .map(item =>
      fields
        .map(field => clean(item?.[field]))
        .filter(Boolean)
        .join(" - ")
    )
    .filter(Boolean);

  return lines.length ? lines.join("; ") : null;
}

function normalizeClientInput(input = {}) {
  const nameParts =
    splitName(input.fullName || input.name);
  const medicationList =
    Array.isArray(input.meds)
      ? formatList(input.meds, ["name", "dose", "dosage", "frequency", "pharmacy"])
      : Array.isArray(input.medications)
        ? formatList(input.medications, ["name", "dose", "dosage", "frequency", "pharmacy"])
      : null;
  const doctorList =
    Array.isArray(input.doctors)
      ? formatList(input.doctors, ["name", "specialty", "clinic", "phone"])
      : null;
  const emergencyContacts =
    Array.isArray(input.vitalink_emergency_contacts)
      ? formatList(input.vitalink_emergency_contacts, ["name", "relationship", "phone", "email"])
      : null;
  const pharmacies =
    Array.isArray(input.vitalink_pharmacy_list)
      ? formatList(input.vitalink_pharmacy_list, ["name", "phone", "details"])
      : null;

  return {
    first_name:
      firstNonEmpty(input.first_name, input.firstName, nameParts.first_name),
    last_name:
      firstNonEmpty(input.last_name, input.lastName, nameParts.last_name),
    email:
      firstNonEmpty(input.email),
    phone:
      firstNonEmpty(input.phone, input.mobile_phone, input.userPhone),
    dob:
      firstNonEmpty(input.dob, input.dateOfBirth),
    address:
      firstNonEmpty(input.address),
    city:
      firstNonEmpty(input.city),
    state:
      firstNonEmpty(input.state),
    zip:
      firstNonEmpty(input.zip),
    medication_list:
      firstNonEmpty(
        input.medication_list,
        Array.isArray(input.medications) ? null : input.medications,
        medicationList
      ),
    doctor_list:
      firstNonEmpty(
        input.doctor_list,
        Array.isArray(input.doctors) ? null : input.doctors,
        doctorList
      ),
    vitalink_emergency_contacts:
      firstNonEmpty(
        Array.isArray(input.vitalink_emergency_contacts) ? null : input.vitalink_emergency_contacts,
        emergencyContacts
      ),
    vitalink_pharmacy_list:
      firstNonEmpty(
        Array.isArray(input.vitalink_pharmacy_list) ? null : input.vitalink_pharmacy_list,
        pharmacies
      ),
  };
}

async function ensureCrmSyncSchema() {
  await db.query(`
    ALTER TABLE agents
    ADD COLUMN IF NOT EXISTS crm_subscription_status TEXT,
    ADD COLUMN IF NOT EXISTS crm_subscription_valid BOOLEAN DEFAULT false
  `);

  await db.query(`
    ALTER TABLE crm_clients
    ADD COLUMN IF NOT EXISTS linked_app_client_id TEXT,
    ADD COLUMN IF NOT EXISTS profile_linked TEXT,
    ADD COLUMN IF NOT EXISTS medication_list TEXT,
    ADD COLUMN IF NOT EXISTS doctor_list TEXT,
    ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ DEFAULT NOW(),
    ADD COLUMN IF NOT EXISTS last_sync TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS vitalink_connected BOOLEAN NOT NULL DEFAULT false,
    ADD COLUMN IF NOT EXISTS vitalink_app_user_id TEXT,
    ADD COLUMN IF NOT EXISTS vitalink_profile_id TEXT,
    ADD COLUMN IF NOT EXISTS last_vitalink_package_at TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS last_vitalink_import_at TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS hipaa_signed_at TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS soa_signed_at TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS vitalink_emergency_contacts TEXT,
    ADD COLUMN IF NOT EXISTS vitalink_pharmacy_list TEXT
  `);

  await db.query(`
    CREATE TABLE IF NOT EXISTS crm_vitalink_packages (
      id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
      crm_agent_id TEXT NOT NULL,
      crm_client_id TEXT,
      app_user_id TEXT,
      app_profile_id TEXT,
      package_type TEXT NOT NULL DEFAULT 'vitalink_package',
      status TEXT NOT NULL DEFAULT 'received',
      client_name TEXT,
      client_dob DATE,
      client_email TEXT,
      client_phone TEXT,
      received_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
      imported_at TIMESTAMPTZ,
      imported_by_agent_id TEXT,
      hipaa_signed_at TIMESTAMPTZ,
      soa_signed_at TIMESTAMPTZ,
      source TEXT NOT NULL DEFAULT 'vitalink_app',
      metadata JSONB NOT NULL DEFAULT '{}'::jsonb,
      created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
      updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
    )
  `);

  await db.query(`
    CREATE TABLE IF NOT EXISTS crm_client_documents (
      id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
      crm_agent_id TEXT NOT NULL,
      crm_client_id TEXT NOT NULL,
      package_id UUID REFERENCES crm_vitalink_packages(id) ON DELETE SET NULL,
      document_type TEXT NOT NULL,
      document_name TEXT,
      storage_path TEXT,
      document_url TEXT,
      document_data BYTEA,
      document_size_bytes INTEGER,
      mime_type TEXT NOT NULL DEFAULT 'application/pdf',
      sha256 TEXT,
      signed_at TIMESTAMPTZ,
      received_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
      created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
      metadata JSONB NOT NULL DEFAULT '{}'::jsonb
    )
  `);

  await db.query(`
    ALTER TABLE crm_client_documents
    ADD COLUMN IF NOT EXISTS document_data BYTEA,
    ADD COLUMN IF NOT EXISTS document_size_bytes INTEGER,
    ADD COLUMN IF NOT EXISTS metadata JSONB NOT NULL DEFAULT '{}'::jsonb
  `);

  await db.query(`
    CREATE TABLE IF NOT EXISTS crm_audit_log (
      id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
      crm_agent_id TEXT,
      crm_client_id TEXT,
      actor_type TEXT NOT NULL DEFAULT 'system',
      actor_id TEXT,
      event_type TEXT NOT NULL,
      package_id UUID REFERENCES crm_vitalink_packages(id) ON DELETE SET NULL,
      ip_address TEXT,
      user_agent TEXT,
      metadata JSONB NOT NULL DEFAULT '{}'::jsonb,
      created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
    )
  `);

  await db.query(`
    CREATE INDEX IF NOT EXISTS idx_crm_vitalink_packages_client
    ON crm_vitalink_packages (crm_client_id, received_at DESC)
  `);

  await db.query(`
    CREATE INDEX IF NOT EXISTS idx_crm_client_documents_client
    ON crm_client_documents (crm_client_id, document_type, received_at DESC)
  `);

  await db.query(`
    CREATE TABLE IF NOT EXISTS crm_client_notes (
      id BIGSERIAL PRIMARY KEY,
      agent_id TEXT NOT NULL,
      client_id TEXT NOT NULL,
      note TEXT NOT NULL,
      source TEXT,
      source_app_item_id BIGINT,
      created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
    )
  `);

  await db.query(`
    ALTER TABLE crm_client_notes
    ADD COLUMN IF NOT EXISTS source_app_item_id BIGINT
  `);

  await db.query(`
    ALTER TABLE crm_client_notes
    ALTER COLUMN client_id TYPE TEXT
    USING client_id::TEXT
  `);

  await db.query(`
    ALTER TABLE crm_tasks
    ADD COLUMN IF NOT EXISTS title TEXT,
    ADD COLUMN IF NOT EXISTS notes TEXT,
    ADD COLUMN IF NOT EXISTS due_date DATE,
    ADD COLUMN IF NOT EXISTS priority TEXT,
    ADD COLUMN IF NOT EXISTS status TEXT,
    ADD COLUMN IF NOT EXISTS completed_at TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS source_app_item_id BIGINT
  `);

  await db.query(`
    CREATE INDEX IF NOT EXISTS idx_crm_client_notes_client_created
    ON crm_client_notes (client_id, created_at DESC)
  `);

  await db.query(`
    CREATE INDEX IF NOT EXISTS idx_crm_client_notes_source_app_item
    ON crm_client_notes (source_app_item_id)
  `);

  await db.query(`
    CREATE INDEX IF NOT EXISTS idx_crm_tasks_source_app_item
    ON crm_tasks (source_app_item_id)
  `);
}

async function getCrmAgent({ agentId, agentEmail }) {
  const values = [];
  const where = [];

  if (agentId) {
    values.push(agentId);
    where.push(`id = $${values.length}`);
  }

  if (agentEmail) {
    values.push(agentEmail);
    where.push(`LOWER(email) = LOWER($${values.length})`);
  }

  if (!where.length) {
    return { error: "Missing agent" };
  }

  const agentRes = await db.query(
    `
    SELECT
      id,
      crm_uuid,
      crm_subscription_status,
      crm_subscription_valid
    FROM agents
    WHERE ${where.join(" OR ")}
    LIMIT 1
    `,
    values
  );

  if (!agentRes.rows.length || !agentRes.rows[0].crm_uuid) {
    return { error: "Agent is not linked to CRM" };
  }

  const row = agentRes.rows[0];
  const crmActive =
    row.crm_subscription_valid === true ||
    row.crm_subscription_status === "active" ||
    row.crm_subscription_status === "trialing";

  if (!crmActive) {
    return { skipped: true, error: "Agent CRM is not active" };
  }

  return {
    appAgentId: row.id,
    crmAgentId: row.crm_uuid,
  };
}

async function getAppClient(agentId, clientId) {
  const appClientRes = await db.query(
    `
    SELECT id, first_name, last_name, email, phone
    FROM users
    WHERE id = $1 AND agent_id = $2
    LIMIT 1
    `,
    [clientId, agentId]
  );

  if (!appClientRes.rows.length) {
    return { error: "Unauthorized client" };
  }

  return {
    appClient: appClientRes.rows[0],
  };
}

async function findCrmClient({ crmAgentId, clientId, client }) {
  const phoneDigits =
    digitsOnly(client.phone);

  const crmClientRes = await db.query(
    `
    SELECT *
    FROM crm_clients
    WHERE agent_id = $1
      AND (
        ($2 <> '' AND linked_app_client_id = $2)
        OR ($3 <> '' AND LOWER(COALESCE(email, '')) = LOWER($3))
        OR ($4 <> '' AND regexp_replace(COALESCE(mobile_phone, ''), '\\D', '', 'g') = $4)
      )
    ORDER BY
      CASE WHEN linked_app_client_id = $2 THEN 0 ELSE 1 END,
      created_at DESC
    LIMIT 1
    `,
    [
      crmAgentId,
      clientId ? String(clientId) : "",
      client.email || "",
      phoneDigits,
    ]
  );

  return crmClientRes.rows[0] || null;
}

async function updateCrmClient({ crmClientId, clientId, client }) {
  const fields = [
    ["first_name", client.first_name],
    ["last_name", client.last_name],
    ["email", client.email],
    ["mobile_phone", client.phone],
    ["dob", client.dob],
    ["address", client.address],
    ["city", client.city],
    ["state", client.state],
    ["zip", client.zip],
    ["medication_list", client.medication_list],
    ["doctor_list", client.doctor_list],
    ["vitalink_emergency_contacts", client.vitalink_emergency_contacts],
    ["vitalink_pharmacy_list", client.vitalink_pharmacy_list],
  ].filter(([, value]) => clean(value));

  const assignments = [
    "profile_linked = 'Linked'",
    "last_sync = NOW()",
    "vitalink_connected = TRUE",
    "last_vitalink_package_at = NOW()",
    "last_vitalink_import_at = NOW()",
  ];

  const values = [];

  if (clientId) {
    values.push(String(clientId));
    assignments.push(`linked_app_client_id = $${values.length}`);
  }

  fields.forEach(([field, value]) => {
    values.push(value);
    assignments.push(`${field} = $${values.length}`);
  });

  values.push(crmClientId);

  const result = await db.query(
    `
    UPDATE crm_clients
    SET ${assignments.join(", ")}
    WHERE id = $${values.length}
    RETURNING *
    `,
    values
  );

  return result.rows[0];
}

async function createCrmClient({ crmAgentId, clientId, client }) {
  const result = await db.query(
    `
    INSERT INTO crm_clients (
      agent_id,
      first_name,
      last_name,
      email,
      mobile_phone,
      dob,
      address,
      city,
      state,
      zip,
      status,
      linked_app_client_id,
      profile_linked,
      medication_list,
      doctor_list,
      last_sync,
      vitalink_connected,
      last_vitalink_package_at,
      last_vitalink_import_at,
      vitalink_emergency_contacts,
      vitalink_pharmacy_list
    )
    VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,'Client',$11,'Linked',$12,$13,NOW(),TRUE,NOW(),NOW(),$14,$15)
    RETURNING *
    `,
    [
      crmAgentId,
      client.first_name,
      client.last_name,
      client.email,
      client.phone,
      client.dob,
      client.address,
      client.city,
      client.state,
      client.zip,
      clientId ? String(clientId) : null,
      client.medication_list,
      client.doctor_list,
      client.vitalink_emergency_contacts,
      client.vitalink_pharmacy_list,
    ]
  );

  return result.rows[0];
}

async function logCrmAuditEvent({ crmAgentId, crmClientId, eventType, packageId, metadata = {} }) {
  await db.query(
    `
    INSERT INTO crm_audit_log (
      crm_agent_id,
      crm_client_id,
      actor_type,
      event_type,
      package_id,
      metadata
    )
    VALUES ($1,$2,'system',$3,$4,$5::jsonb)
    `,
    [
      clean(crmAgentId),
      clean(crmClientId),
      eventType,
      clean(packageId),
      JSON.stringify(metadata),
    ]
  );
}

async function recordVitalinkPackage({ crmAgentId, crmClientId, client, appUserId, appProfileId, signedAt }) {
  await db.query(
    `
    UPDATE crm_clients
    SET
      vitalink_connected = TRUE,
      last_vitalink_package_at = NOW(),
      last_vitalink_import_at = NOW(),
      hipaa_signed_at = COALESCE($1, hipaa_signed_at),
      soa_signed_at = COALESCE($1, soa_signed_at),
      updated_at = NOW()
    WHERE id = $2
      AND agent_id = $3
    `,
    [clean(signedAt), crmClientId, crmAgentId]
  );

  const result = await db.query(
    `
    INSERT INTO crm_vitalink_packages (
      crm_agent_id,
      crm_client_id,
      app_user_id,
      app_profile_id,
      client_name,
      client_dob,
      client_email,
      client_phone,
      imported_at,
      imported_by_agent_id,
      hipaa_signed_at,
      soa_signed_at,
      metadata
    )
    VALUES ($1,$2,$3,$4,$5,$6,$7,$8,NOW(),$1,$9,$9,$10::jsonb)
    RETURNING *
    `,
    [
      crmAgentId,
      crmClientId,
      clean(appUserId),
      clean(appProfileId),
      [client.first_name, client.last_name].filter(Boolean).join(" "),
      clean(client.dob),
      clean(client.email),
      clean(client.phone),
      clean(signedAt),
      JSON.stringify({ source: "vitalink_package" }),
    ]
  );

  const pkg = result.rows[0];

  await logCrmAuditEvent({
    crmAgentId,
    crmClientId,
    eventType: "vitalink_package_received",
    packageId: pkg.id,
  });

  await logCrmAuditEvent({
    crmAgentId,
    crmClientId,
    eventType: "hipaa_received",
    packageId: pkg.id,
  });

  await logCrmAuditEvent({
    crmAgentId,
    crmClientId,
    eventType: "soa_received",
    packageId: pkg.id,
  });

  return pkg;
}

async function recordCrmClientDocument({
  crmAgentId,
  crmClientId,
  packageId,
  documentType,
  documentName,
  documentBase64,
  signedAt,
}) {
  if (!documentBase64) {
    return null;
  }

  const cleanedBase64 = String(documentBase64)
    .replace(/^data:application\/pdf;base64,/i, "")
    .trim();

  const documentBuffer = Buffer.from(cleanedBase64, "base64");

  if (documentBuffer.length > 10 * 1024 * 1024) {
    throw new Error("Document PDF is larger than 10MB");
  }

  const sha256 = crypto
    .createHash("sha256")
    .update(documentBuffer)
    .digest("hex");

  const result = await db.query(
    `
    INSERT INTO crm_client_documents (
      crm_agent_id,
      crm_client_id,
      package_id,
      document_type,
      document_name,
      document_data,
      document_size_bytes,
      mime_type,
      sha256,
      signed_at,
      metadata
    )
    VALUES ($1,$2,$3,$4,$5,$6,$7,'application/pdf',$8,$9,$10::jsonb)
    RETURNING id
    `,
    [
      crmAgentId,
      crmClientId,
      packageId,
      documentType,
      clean(documentName),
      documentBuffer,
      documentBuffer.length,
      sha256,
      clean(signedAt),
      JSON.stringify({ source: "vitalink_package" }),
    ]
  );

  return result.rows[0];
}

async function syncVitalinkPackageToCrm({
  agentEmail,
  clientData = {},
  packageData = {},
}) {
  const signedAt =
    packageData.signedAt || new Date().toISOString();

  const sync = await syncAppClientToCrm({
    agentEmail,
    clientData: {
      ...clientData,
      vitalink_emergency_contacts: packageData.emergencyContacts,
      vitalink_pharmacy_list: packageData.pharmacies,
    },
  });

  if (!sync.success) {
    return sync;
  }

  const pkg = await recordVitalinkPackage({
    crmAgentId: sync.crmAgentId,
    crmClientId: sync.crmClientId,
    client: normalizeClientInput(clientData),
    appUserId: packageData.appUserId,
    appProfileId: packageData.appProfileId,
    signedAt,
  });

  const pdfBase64 = packageData.hipaaSoaPdfBase64;

  const hipaa = await recordCrmClientDocument({
    crmAgentId: sync.crmAgentId,
    crmClientId: sync.crmClientId,
    packageId: pkg.id,
    documentType: DOCUMENT_TYPES.HIPAA,
    documentName: "VitaLink HIPAA Authorization",
    documentBase64: pdfBase64,
    signedAt,
  });

  const soa = await recordCrmClientDocument({
    crmAgentId: sync.crmAgentId,
    crmClientId: sync.crmClientId,
    packageId: pkg.id,
    documentType: DOCUMENT_TYPES.SOA,
    documentName: "VitaLink Scope of Appointment",
    documentBase64: pdfBase64,
    signedAt,
  });

  await logCrmAuditEvent({
    crmAgentId: sync.crmAgentId,
    crmClientId: sync.crmClientId,
    eventType: "vitalink_import_completed",
    packageId: pkg.id,
    metadata: {
      hipaaDocumentId: hipaa?.id,
      soaDocumentId: soa?.id,
    },
  });

  return {
    ...sync,
    packageId: pkg.id,
    documents: {
      hipaa: hipaa?.id || null,
      soa: soa?.id || null,
    },
  };
}

async function syncAppClientToCrm({
  agentId,
  agentEmail,
  clientId,
  clientData = {},
}) {
  await ensureCrmSyncSchema();

  const agent = await getCrmAgent({ agentId, agentEmail });

  if (agent.error) {
    return {
      success: false,
      error: agent.error,
    };
  }

  let appClient = {};

  if (clientId) {
    const app = await getAppClient(agent.appAgentId, clientId);

    if (app.error) {
      return {
        success: false,
        error: app.error,
      };
    }

    appClient = app.appClient;
  }

  const client = normalizeClientInput({
    ...appClient,
    ...clientData,
  });

  const matchedClient = await findCrmClient({
    crmAgentId: agent.crmAgentId,
    clientId,
    client,
  });

  if (matchedClient) {
    const updatedClient = await updateCrmClient({
      crmClientId: matchedClient.id,
      clientId,
      client,
    });

    return {
      success: true,
      action: "updated",
      crmAgentId: agent.crmAgentId,
      crmClientId: updatedClient.id,
      client: updatedClient,
    };
  }

  const createdClient = await createCrmClient({
    crmAgentId: agent.crmAgentId,
    clientId,
    client,
  });

  return {
    success: true,
    action: "created",
    crmAgentId: agent.crmAgentId,
    crmClientId: createdClient.id,
    client: createdClient,
  };
}

module.exports = {
  ensureCrmSyncSchema,
  syncAppClientToCrm,
  syncVitalinkPackageToCrm,
};
