CREATE TABLE IF NOT EXISTS profile_share_links (
  id UUID PRIMARY KEY,
  owner_user_id UUID NOT NULL,
  recipient_user_id UUID,
  invited_email TEXT,
  invited_phone TEXT,
  profile_id UUID,
  profile_name TEXT,
  allowed_sections JSONB NOT NULL DEFAULT '["emergency"]'::jsonb,
  status TEXT NOT NULL DEFAULT 'pending',
  invite_code TEXT UNIQUE NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  accepted_at TIMESTAMPTZ,
  revoked_at TIMESTAMPTZ
);

CREATE TABLE IF NOT EXISTS profile_update_packages (
  id UUID PRIMARY KEY,
  owner_user_id UUID NOT NULL,
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
  recipient_user_id UUID NOT NULL,
  share_link_id UUID REFERENCES profile_share_links(id) ON DELETE SET NULL,
  status TEXT NOT NULL DEFAULT 'pending',
  notified_at TIMESTAMPTZ,
  downloaded_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_profile_share_links_owner
ON profile_share_links (owner_user_id, status);

CREATE INDEX IF NOT EXISTS idx_profile_share_links_recipient
ON profile_share_links (recipient_user_id, status);

CREATE INDEX IF NOT EXISTS idx_profile_update_recipients_user
ON profile_update_recipients (recipient_user_id, status);

CREATE INDEX IF NOT EXISTS idx_profile_update_packages_expires
ON profile_update_packages (expires_at);
