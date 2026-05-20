const crypto = require("crypto");
const { Pool } = require("pg");

const pool = new Pool({
  connectionString: process.env.SUPABASE_URL,
  ssl: { rejectUnauthorized: false }
});

const corsHeaders = {
  "Access-Control-Allow-Origin": "https://myvitalink.app",
  "Access-Control-Allow-Headers": "Content-Type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Access-Control-Allow-Credentials": "true",
  "Content-Type": "application/json"
};

function reply(statusCode, body) {
  return {
    statusCode,
    headers: corsHeaders,
    body: JSON.stringify(body)
  };
}

function hash(value) {
  if (!value) return null;
  return crypto
    .createHash("sha256")
    .update(String(value))
    .digest("hex");
}

function cleanText(value, max = 500) {
  const text = String(value || "").trim();
  return text ? text.slice(0, max) : null;
}

async function ensureTrafficTable(client) {
  await client.query(`
    CREATE TABLE IF NOT EXISTS site_traffic_events (
      id BIGSERIAL PRIMARY KEY,
      created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
      page_path TEXT,
      page_title TEXT,
      referrer_host TEXT,
      visitor_hash TEXT,
      session_hash TEXT
    )
  `);

  await client.query(`
    CREATE INDEX IF NOT EXISTS idx_site_traffic_created
    ON site_traffic_events (created_at DESC)
  `);

  await client.query(`
    CREATE INDEX IF NOT EXISTS idx_site_traffic_page
    ON site_traffic_events (page_path)
  `);
}

exports.handler = async (event) => {
  if (event.httpMethod === "OPTIONS") {
    return { statusCode: 200, headers: corsHeaders, body: "" };
  }

  if (event.httpMethod !== "POST") {
    return reply(405, { success: false, error: "Method Not Allowed" });
  }

  let body = {};

  try {
    body = JSON.parse(event.body || "{}");
  } catch {
    return reply(400, { success: false, error: "Invalid request body" });
  }

  const client = await pool.connect();

  try {
    await ensureTrafficTable(client);

    await client.query(
      `
      INSERT INTO site_traffic_events (
        page_path,
        page_title,
        referrer_host,
        visitor_hash,
        session_hash
      )
      VALUES ($1, $2, $3, $4, $5)
      `,
      [
        cleanText(body.page_path, 300),
        cleanText(body.page_title, 200),
        cleanText(body.referrer_host, 200),
        hash(body.visitor_id),
        hash(body.session_id)
      ]
    );

    return reply(200, { success: true });
  } catch (err) {
    console.error("track-site-traffic error:", err);
    return reply(500, { success: false, error: "Server error" });
  } finally {
    client.release();
  }
};
