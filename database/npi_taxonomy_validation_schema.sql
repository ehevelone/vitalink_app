CREATE TABLE IF NOT EXISTS public.npi_taxonomy_validation_runs (
  id BIGSERIAL PRIMARY KEY,
  mapping_version TEXT NOT NULL,
  published_version TEXT,
  status TEXT NOT NULL CHECK (status IN ('passed', 'review')),
  trigger_type TEXT NOT NULL CHECK (trigger_type IN ('scheduled', 'manual')),
  checked_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  confirmed_count INTEGER NOT NULL DEFAULT 0,
  review_count INTEGER NOT NULL DEFAULT 0,
  report JSONB NOT NULL DEFAULT '{}'::jsonb,
  email_sent BOOLEAN NOT NULL DEFAULT false
);

CREATE INDEX IF NOT EXISTS idx_npi_taxonomy_validation_runs_checked_at
ON public.npi_taxonomy_validation_runs (checked_at DESC);
