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
);

CREATE INDEX IF NOT EXISTS idx_npi_verified_entities_lookup
ON npi_verified_entities (entity_type, normalized_name, state);
