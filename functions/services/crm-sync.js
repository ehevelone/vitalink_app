const db = require("./db");

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
        input.medications,
        formatList(input.meds, ["name", "dosage", "frequency"])
      ),
    doctor_list:
      firstNonEmpty(
        input.doctor_list,
        input.doctors,
        formatList(input.doctors, ["name", "specialty", "clinic", "phone"])
      ),
  };
}

async function ensureCrmSyncSchema() {
  await db.query(`
    ALTER TABLE crm_clients
    ADD COLUMN IF NOT EXISTS linked_app_client_id TEXT,
    ADD COLUMN IF NOT EXISTS profile_linked TEXT,
    ADD COLUMN IF NOT EXISTS medication_list TEXT,
    ADD COLUMN IF NOT EXISTS doctor_list TEXT,
    ADD COLUMN IF NOT EXISTS last_sync TIMESTAMPTZ
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
    ADD COLUMN IF NOT EXISTS client_id UUID,
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
    SELECT id, crm_uuid
    FROM agents
    WHERE ${where.join(" OR ")}
    LIMIT 1
    `,
    values
  );

  if (!agentRes.rows.length || !agentRes.rows[0].crm_uuid) {
    return { error: "Agent is not linked to CRM" };
  }

  return {
    appAgentId: agentRes.rows[0].id,
    crmAgentId: agentRes.rows[0].crm_uuid,
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
  ].filter(([, value]) => clean(value));

  const assignments = [
    "profile_linked = 'Linked'",
    "last_sync = NOW()",
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
      last_sync
    )
    VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,'Client',$11,'Linked',$12,$13,NOW())
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
    ]
  );

  return result.rows[0];
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
};
