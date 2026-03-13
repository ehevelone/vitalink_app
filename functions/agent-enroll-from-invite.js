// functions/agent-enroll-from-invite.js

const { Pool } = require("pg");

const pool = new Pool({
  connectionString: process.env.SUPABASE_URL,
  ssl: { rejectUnauthorized: false }
});

const SITE = "https://myvitalink.app";

function generateAgentCode(prefix = "AGT", length = 8) {

  const chars = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";
  let code = "";

  for (let i = 0; i < length; i++) {
    code += chars.charAt(Math.floor(Math.random() * chars.length));
  }

  return `${prefix}-${code}`;
}

exports.handler = async function (event) {

  /* INVITE LINK CLICK */
  if (event.httpMethod === "GET") {

    const rsmCode = event.queryStringParameters?.rsm;

    if (!rsmCode) {
      return {
        statusCode: 302,
        headers: { Location: `${SITE}` }
      };
    }

    const client = await pool.connect();

    try {

      /* VALIDATE RSM */

      const rsm = await client.query(
        `SELECT id
         FROM rsms
         WHERE invite_code = $1
         AND role = 'rsm'
         AND active = true
         LIMIT 1`,
        [rsmCode]
      );

      if (rsm.rows.length === 0) {
        return {
          statusCode: 302,
          headers: { Location: `${SITE}` }
        };
      }

      const rsmId = rsm.rows[0].id;

      /* GENERATE AGENT CODE */

      const agentCode = generateAgentCode();

      /* CREATE AGENT RECORD */

      await client.query(
        `INSERT INTO agents
          (agent_code, active, created_at, rsm_id)
         VALUES
          ($1, false, NOW(), $2)`,
        [
          agentCode,
          rsmId
        ]
      );

      /* REDIRECT TO LANDING PAGE */

      return {
        statusCode: 302,
        headers: {
          Location: `${SITE}/core-node/agent_enrolled.html?code=${agentCode}`
        }
      };

    } catch (err) {

      console.error("agent-enroll-from-invite error:", err);

      return {
        statusCode: 302,
        headers: { Location: `${SITE}` }
      };

    } finally {

      client.release();

    }

  }

  /* BLOCK OTHER METHODS */

  return {
    statusCode: 405,
    body: "Method Not Allowed"
  };

};