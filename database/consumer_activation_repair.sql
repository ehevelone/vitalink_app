BEGIN;

DO $$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM activation_codes
    WHERE stripe_session IS NOT NULL
    GROUP BY stripe_session
    HAVING COUNT(*) > 1
  ) THEN
    RAISE EXCEPTION 'Duplicate activation_codes.stripe_session values must be resolved before migration';
  END IF;
END
$$;

ALTER TABLE activation_codes
  ADD COLUMN IF NOT EXISTS payment_intent_id TEXT,
  ADD COLUMN IF NOT EXISTS payment_status TEXT,
  ADD COLUMN IF NOT EXISTS paid_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS redeemed_by_user_id INTEGER;

UPDATE activation_codes
SET redeemed = false
WHERE redeemed IS NULL;

ALTER TABLE activation_codes
  ALTER COLUMN redeemed SET DEFAULT false,
  ALTER COLUMN redeemed SET NOT NULL;

CREATE UNIQUE INDEX IF NOT EXISTS activation_codes_stripe_session_unique
  ON activation_codes (stripe_session)
  WHERE stripe_session IS NOT NULL;

CREATE UNIQUE INDEX IF NOT EXISTS activation_codes_payment_intent_unique
  ON activation_codes (payment_intent_id)
  WHERE payment_intent_id IS NOT NULL;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM information_schema.table_constraints
    WHERE table_schema = 'public'
      AND table_name = 'activation_codes'
      AND constraint_name = 'activation_codes_redeemed_by_user_fkey'
  ) THEN
    ALTER TABLE activation_codes
      ADD CONSTRAINT activation_codes_redeemed_by_user_fkey
      FOREIGN KEY (redeemed_by_user_id) REFERENCES users(id);
  END IF;
END
$$;

COMMIT;
