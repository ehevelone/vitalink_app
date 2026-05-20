const { requireAdmin } = require("./_adminAuth");
const { Pool } = require("pg");

const pool = new Pool({
  connectionString: process.env.SUPABASE_URL,
  ssl: { rejectUnauthorized: false }
});

const corsHeaders = {
  "Access-Control-Allow-Origin": "https://myvitalink.app",
  "Access-Control-Allow-Headers": "Content-Type, x-admin-session",
  "Access-Control-Allow-Methods": "GET, OPTIONS",
  "Content-Type": "application/json"
};

function reply(statusCode, body) {
  return {
    statusCode,
    headers: corsHeaders,
    body: JSON.stringify(body)
  };
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
}

exports.handler = async (event) => {
  if (event.httpMethod === "OPTIONS") {
    return { statusCode: 200, headers: corsHeaders, body: "" };
  }

  if (event.httpMethod !== "GET") {
    return reply(405, { success: false, error: "Method Not Allowed" });
  }

  const auth = await requireAdmin(event);
  if (auth.error) {
    return reply(401, { success: false, error: auth.error });
  }

  const client = await pool.connect();

  try {
    await ensureTrafficTable(client);

    const summary = await client.query(`
      SELECT
        COUNT(*)::INT AS total_views,
        COUNT(*) FILTER (WHERE created_at >= CURRENT_DATE)::INT AS views_today,
        COUNT(DISTINCT visitor_hash)::INT AS unique_visitors,
        COUNT(DISTINCT session_hash)::INT AS sessions
      FROM site_traffic_events
      WHERE created_at >= NOW() - INTERVAL '30 days'
    `);

    const topPages = await client.query(`
      SELECT
        COALESCE(page_path, '/') AS page_path,
        COUNT(*)::INT AS views,
        COUNT(DISTINCT visitor_hash)::INT AS visitors
      FROM site_traffic_events
      WHERE created_at >= NOW() - INTERVAL '30 days'
      GROUP BY page_path
      ORDER BY views DESC
      LIMIT 10
    `);

    const keyPages = await client.query(`
      WITH key_pages(page_name, paths) AS (
        VALUES
          ('Index', ARRAY['/', '/index.html']),
          ('Activate', ARRAY['/activate', '/activate.html']),
          ('Agents', ARRAY['/agents', '/agents.html']),
          ('Agent Quick Start', ARRAY['/quick_start', '/quick_start.html'])
      )
      SELECT
        key_pages.page_name,
        COUNT(site_traffic_events.id)::INT AS views,
        COUNT(DISTINCT site_traffic_events.visitor_hash)::INT AS unique_hits,
        COUNT(DISTINCT site_traffic_events.session_hash)::INT AS sessions
      FROM key_pages
      LEFT JOIN site_traffic_events
        ON COALESCE(site_traffic_events.page_path, '') = ANY(key_pages.paths)
       AND site_traffic_events.created_at >= NOW() - INTERVAL '30 days'
      GROUP BY key_pages.page_name
      ORDER BY
        CASE key_pages.page_name
          WHEN 'Index' THEN 1
          WHEN 'Activate' THEN 2
          WHEN 'Agents' THEN 3
          WHEN 'Agent Quick Start' THEN 4
          ELSE 5
        END
    `);

    const daily = await client.query(`
      SELECT
        TO_CHAR(created_at::DATE, 'YYYY-MM-DD') AS day,
        COUNT(*)::INT AS views,
        COUNT(DISTINCT visitor_hash)::INT AS visitors
      FROM site_traffic_events
      WHERE created_at >= NOW() - INTERVAL '14 days'
      GROUP BY created_at::DATE
      ORDER BY created_at::DATE DESC
    `);

    const referrers = await client.query(`
      SELECT
        COALESCE(referrer_host, 'Direct') AS referrer,
        COUNT(*)::INT AS views
      FROM site_traffic_events
      WHERE created_at >= NOW() - INTERVAL '30 days'
      GROUP BY referrer_host
      ORDER BY views DESC
      LIMIT 8
    `);

    return reply(200, {
      success: true,
      summary: summary.rows[0],
      key_pages: keyPages.rows,
      top_pages: topPages.rows,
      daily: daily.rows,
      referrers: referrers.rows
    });
  } catch (err) {
    console.error("get-site-traffic-report error:", err);
    return reply(500, { success: false, error: "Server error" });
  } finally {
    client.release();
  }
};
