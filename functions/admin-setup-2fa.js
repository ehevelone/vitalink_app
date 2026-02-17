const speakeasy = require("speakeasy");
const QRCode = require("qrcode");
const { Pool } = require("pg");

const pool = new Pool({
  connectionString: process.env.SUPABASE_URL,
  ssl: { rejectUnauthorized: false }
});

exports.handler = async function () {
  try {
    const secret = speakeasy.generateSecret({
      length: 20,
      name: "VitaLink Admin"
    });

    const client = await pool.connect();

    await client.query(
      "UPDATE rsms SET totp_secret = $1 WHERE role = 'admin'",
      [secret.base32]
    );

    client.release();

    const qr = await QRCode.toDataURL(secret.otpauth_url);

    return {
      statusCode: 200,
      body: JSON.stringify({
        message: "Scan this QR with Google Authenticator",
        qr
      })
    };

  } catch (err) {
    return {
      statusCode: 500,
      body: JSON.stringify({ error: err.message })
    };
  }
};
