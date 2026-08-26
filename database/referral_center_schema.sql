CREATE TABLE IF NOT EXISTS agent_referrals (
  id UUID PRIMARY KEY,
  agent_id INTEGER NOT NULL REFERENCES agents(id) ON DELETE CASCADE,
  referring_user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  referral_name TEXT NOT NULL,
  referral_phone TEXT,
  referral_email TEXT,
  relationship TEXT,
  reason TEXT,
  notes TEXT,
  source TEXT NOT NULL DEFAULT 'recommend_my_agent',
  public_token TEXT UNIQUE,
  contact_preference TEXT,
  link_opened_at TIMESTAMPTZ,
  contact_preference_submitted_at TIMESTAMPTZ,
  status TEXT NOT NULL DEFAULT 'Introduction Sent',
  submitted_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  agent_first_opened_at TIMESTAMPTZ,
  agent_first_contacted_at TIMESTAMPTZ,
  appointment_scheduled_at TIMESTAMPTZ,
  client_added_at TIMESTAMPTZ,
  closed_at TIMESTAMPTZ,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_agent_referrals_agent_submitted
ON agent_referrals (agent_id, submitted_at DESC);

CREATE INDEX IF NOT EXISTS idx_agent_referrals_user_submitted
ON agent_referrals (referring_user_id, submitted_at DESC);

ALTER TABLE agent_referrals
ADD COLUMN IF NOT EXISTS public_token TEXT UNIQUE,
ADD COLUMN IF NOT EXISTS contact_preference TEXT,
ADD COLUMN IF NOT EXISTS link_opened_at TIMESTAMPTZ,
ADD COLUMN IF NOT EXISTS contact_preference_submitted_at TIMESTAMPTZ;

ALTER TABLE user_devices
ALTER COLUMN user_id DROP NOT NULL;

ALTER TABLE user_devices
ADD COLUMN IF NOT EXISTS push_status TEXT,
ADD COLUMN IF NOT EXISTS last_push_at TIMESTAMPTZ,
ADD COLUMN IF NOT EXISTS last_push_success_at TIMESTAMPTZ,
ADD COLUMN IF NOT EXISTS last_push_failure_at TIMESTAMPTZ,
ADD COLUMN IF NOT EXISTS last_push_error TEXT;
