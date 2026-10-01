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
ADD COLUMN IF NOT EXISTS access_prompt_count INTEGER NOT NULL DEFAULT 0;

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
);

CREATE TABLE IF NOT EXISTS access_code_attempts (
  scope_key TEXT PRIMARY KEY,
  failed_count INTEGER NOT NULL DEFAULT 0,
  window_started_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  locked_until TIMESTAMPTZ,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS access_code_aggregate_attempts (
  code_fingerprint TEXT PRIMARY KEY,
  failed_count INTEGER NOT NULL DEFAULT 0,
  window_started_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  last_alerted_at TIMESTAMPTZ,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS policy_relationship_reviews (
  id BIGSERIAL PRIMARY KEY,
  user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  agent_id INTEGER REFERENCES agents(id) ON DELETE SET NULL,
  match_type TEXT NOT NULL,
  status TEXT NOT NULL DEFAULT 'pending',
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  reviewed_at TIMESTAMPTZ,
  reviewed_by TEXT
);

CREATE TABLE IF NOT EXISTS agent_message_events (
  id BIGSERIAL PRIMARY KEY,
  agent_id INTEGER NOT NULL REFERENCES agents(id) ON DELETE CASCADE,
  campaign TEXT NOT NULL,
  eligible_user_count INTEGER NOT NULL DEFAULT 0,
  devices_targeted INTEGER NOT NULL DEFAULT 0,
  success_count INTEGER NOT NULL DEFAULT 0,
  failure_count INTEGER NOT NULL DEFAULT 0,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS device_transfer_packages (
  id UUID PRIMARY KEY,
  user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  transfer_code TEXT UNIQUE NOT NULL,
  encrypted_payload TEXT,
  chunk_count INTEGER NOT NULL DEFAULT 0,
  status TEXT NOT NULL DEFAULT 'pending',
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  downloaded_at TIMESTAMPTZ,
  redeemed_device_id TEXT,
  expires_at TIMESTAMPTZ NOT NULL DEFAULT NOW() + INTERVAL '6 hours'
);

ALTER TABLE device_transfer_packages
ALTER COLUMN encrypted_payload DROP NOT NULL,
ADD COLUMN IF NOT EXISTS chunk_count INTEGER NOT NULL DEFAULT 0,
ADD COLUMN IF NOT EXISTS redeemed_device_id TEXT;

CREATE TABLE IF NOT EXISTS device_transfer_chunks (
  transfer_id UUID NOT NULL REFERENCES device_transfer_packages(id) ON DELETE CASCADE,
  chunk_index INTEGER NOT NULL,
  chunk_data TEXT NOT NULL,
  PRIMARY KEY (transfer_id, chunk_index)
);

CREATE INDEX IF NOT EXISTS idx_device_transfer_user_status
ON device_transfer_packages (user_id, status, expires_at);

CREATE TABLE IF NOT EXISTS profile_share_links (
  id UUID PRIMARY KEY,
  owner_user_id TEXT NOT NULL,
  recipient_user_id TEXT,
  invited_email TEXT,
  invited_phone TEXT,
  profile_id UUID,
  profile_name TEXT,
  allowed_sections JSONB NOT NULL DEFAULT '["emergency"]'::jsonb,
  status TEXT NOT NULL DEFAULT 'pending',
  invite_code TEXT UNIQUE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  accepted_at TIMESTAMPTZ,
  revoked_at TIMESTAMPTZ,
  recipient_removed_at TIMESTAMPTZ,
  expires_at TIMESTAMPTZ DEFAULT NOW() + INTERVAL '6 hours'
);

ALTER TABLE profile_share_links
ALTER COLUMN invite_code DROP NOT NULL,
ADD COLUMN IF NOT EXISTS recipient_removed_at TIMESTAMPTZ,
ADD COLUMN IF NOT EXISTS expires_at TIMESTAMPTZ;

CREATE INDEX IF NOT EXISTS idx_profile_share_links_expiry
ON profile_share_links (status, expires_at);

CREATE TABLE IF NOT EXISTS profile_update_packages (
  id UUID PRIMARY KEY,
  owner_user_id TEXT NOT NULL,
  profile_id UUID,
  profile_name TEXT,
  allowed_sections JSONB NOT NULL DEFAULT '[]'::jsonb,
  encrypted_payload TEXT NOT NULL,
  status TEXT NOT NULL DEFAULT 'pending',
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  expires_at TIMESTAMPTZ NOT NULL DEFAULT NOW() + INTERVAL '7 days'
);

CREATE TABLE IF NOT EXISTS profile_update_recipients (
  id UUID PRIMARY KEY,
  package_id UUID NOT NULL REFERENCES profile_update_packages(id) ON DELETE CASCADE,
  recipient_user_id TEXT NOT NULL,
  share_link_id UUID REFERENCES profile_share_links(id) ON DELETE SET NULL,
  status TEXT NOT NULL DEFAULT 'pending',
  notified_at TIMESTAMPTZ,
  downloaded_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS maintenance_job_runs (
  job_name TEXT PRIMARY KEY,
  last_started_at TIMESTAMPTZ,
  last_succeeded_at TIMESTAMPTZ,
  last_failed_at TIMESTAMPTZ,
  last_alerted_at TIMESTAMPTZ,
  last_error TEXT,
  last_counts JSONB NOT NULL DEFAULT '{}'::jsonb
);
