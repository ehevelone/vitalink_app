// functions/services/db.js
const { Pool } = require("pg");

// Expecting SUPABASE_URL in your Netlify environment variables
const pool = new Pool({
  connectionString: process.env.SUPABASE_URL,
  ssl: { rejectUnauthorized: false }, // required for Supabase
  // Fail fast instead of hanging until Netlify kills the function. These are
  // client-side limits, so they also work through Supabase's pooler.
  connectionTimeoutMillis: 8000,
  query_timeout: 20000,
  idleTimeoutMillis: 10000,
  max: 5,
});

const db = {
  query: (text, params) => pool.query(text, params),
  connect: () => pool.connect(),
};

module.exports = db;
