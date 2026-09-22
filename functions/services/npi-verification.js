const db = require("./db");
const { verifyAgentSession } = require("./agent-auth");
const { verifyUserSession } = require("./user-auth");
const { normalizeText } = require("./npi-registry");

async function ensureNpiCacheTable() {
  await db.query(`
    CREATE TABLE IF NOT EXISTS npi_verified_entities (
      id BIGSERIAL PRIMARY KEY,
      entity_type TEXT NOT NULL CHECK (entity_type IN ('provider', 'pharmacy')),
      normalized_name TEXT NOT NULL,
      npi VARCHAR(10) NOT NULL CHECK (npi ~ '^[0-9]{10}$'),
      display_name TEXT NOT NULL,
      credential TEXT,
      taxonomy TEXT,
      address_1 TEXT,
      address_2 TEXT,
      city TEXT,
      state VARCHAR(2),
      postal_code TEXT,
      phone TEXT,
      enumeration_type TEXT,
      confirmed_by TEXT NOT NULL,
      confirmed_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
      UNIQUE (entity_type, normalized_name, npi)
    )
  `);
  await db.query(`
    CREATE INDEX IF NOT EXISTS idx_npi_verified_entities_lookup
    ON npi_verified_entities (entity_type, normalized_name, state)
  `);
}

async function authenticate(body) {
  const agentId = Number(body.agentId);
  if (agentId && body.agentSessionToken) {
    const agent = await verifyAgentSession({
      agentId,
      token: body.agentSessionToken,
    });
    if (agent) return { actor: String(agent.id), type: "agent" };
  }

  if (body.userId && body.sessionToken) {
    const valid = await verifyUserSession(body.userId, body.sessionToken);
    if (valid) return { actor: String(body.userId), type: "user" };
  }
  return null;
}

function rowToCandidate(row) {
  return {
    npi: row.npi,
    displayName: row.display_name,
    credential: row.credential || "",
    taxonomy: row.taxonomy || "",
    address1: row.address_1 || "",
    address2: row.address_2 || "",
    city: row.city || "",
    state: row.state || "",
    postalCode: row.postal_code || "",
    phone: row.phone || "",
    enumerationType: row.enumeration_type || "",
    suggested: true,
  };
}

async function findCachedCandidates({ entityType, name, city, state, phone }) {
  await ensureNpiCacheTable();
  const values = [entityType, normalizeText(name)];
  let stateFilter = "";
  if (state) {
    values.push(String(state).trim().toUpperCase());
    stateFilter = `AND (state = $${values.length} OR state IS NULL)`;
  }
  let cityFilter = "";
  if (city) {
    values.push(String(city).trim());
    cityFilter = `AND (LOWER(city) = LOWER($${values.length}) OR city IS NULL)`;
  }
  let phoneFilter = "";
  const phoneDigits = String(phone || "").replace(/\D/g, "").slice(-10);
  if (phoneDigits.length === 10) {
    values.push(phoneDigits);
    phoneFilter = `AND RIGHT(REGEXP_REPLACE(COALESCE(phone, ''), '[^0-9]', '', 'g'), 10) = $${values.length}`;
  }
  const result = await db.query(
    `
    SELECT *
    FROM npi_verified_entities
    WHERE entity_type = $1
      AND normalized_name = $2
      ${stateFilter}
      ${cityFilter}
      ${phoneFilter}
    ORDER BY confirmed_at DESC
    LIMIT 4
    `,
    values,
  );
  return result.rows.map(rowToCandidate);
}

async function cacheConfirmedCandidate({ entityType, searchedName, candidate, actor }) {
  await ensureNpiCacheTable();
  await db.query(
    `
    INSERT INTO npi_verified_entities (
      entity_type, normalized_name, npi, display_name, credential, taxonomy,
      address_1, address_2, city, state, postal_code, phone,
      enumeration_type, confirmed_by, confirmed_at
    )
    VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14,NOW())
    ON CONFLICT (entity_type, normalized_name, npi)
    DO UPDATE SET
      display_name = EXCLUDED.display_name,
      credential = EXCLUDED.credential,
      taxonomy = EXCLUDED.taxonomy,
      address_1 = EXCLUDED.address_1,
      address_2 = EXCLUDED.address_2,
      city = EXCLUDED.city,
      state = EXCLUDED.state,
      postal_code = EXCLUDED.postal_code,
      phone = EXCLUDED.phone,
      enumeration_type = EXCLUDED.enumeration_type,
      confirmed_by = EXCLUDED.confirmed_by,
      confirmed_at = NOW()
    `,
    [
      entityType,
      normalizeText(searchedName),
      candidate.npi,
      candidate.displayName,
      candidate.credential || null,
      candidate.taxonomy || null,
      candidate.address1 || null,
      candidate.address2 || null,
      candidate.city || null,
      candidate.state || null,
      candidate.postalCode || null,
      candidate.phone || null,
      candidate.enumerationType || null,
      actor,
    ],
  );
}

module.exports = {
  authenticate,
  cacheConfirmedCandidate,
  ensureNpiCacheTable,
  findCachedCandidates,
};
