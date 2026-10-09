const db = require("./db");
const { schemaOnce } = require("./schema-once");

// Runs once per warm instance (see schema-once.js).
const ensureUserSessionColumns = schemaOnce("user-auth:session-columns", () =>
  db.query(`
    ALTER TABLE users
    ADD COLUMN IF NOT EXISTS session_token TEXT,
    ADD COLUMN IF NOT EXISTS session_expires TIMESTAMPTZ
  `)
);

async function verifyUserSession(userId, token) {
  if (!userId || !token) return false;

  await ensureUserSessionColumns();

  const result = await db.query(
    `
    SELECT id
    FROM users
    WHERE id = $1
      AND session_token = $2
      AND session_expires > NOW()
    LIMIT 1
    `,
    [userId, token]
  );

  return result.rows.length > 0;
}

module.exports = {
  ensureUserSessionColumns,
  verifyUserSession,
};
