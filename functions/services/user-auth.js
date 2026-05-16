const db = require("./db");

async function verifyUserSession(userId, token) {
  if (!userId || !token) return false;

  await db.query(`
    ALTER TABLE users
    ADD COLUMN IF NOT EXISTS session_token TEXT,
    ADD COLUMN IF NOT EXISTS session_expires TIMESTAMPTZ
  `);

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
  verifyUserSession,
};
