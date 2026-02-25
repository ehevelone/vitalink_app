// functions/request_reset.js

const db = require("./services/db");
const nodemailer = require("nodemailer");

const CORS_HEADERS = {
  "Content-Type": "application/json",
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "Content-Type, Authorization",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function reply(statusCode, body) {
  return {
    statusCode,
    headers: CORS_HEADERS,
    body: JSON.stringify(body),
  };
}

exports.handler = async (event) => {
  try {
    if (event.httpMethod === "OPTIONS") {
      return { statusCode: 200, headers: CORS_HEADERS, body: "" };
    }

    if (event.httpMethod !== "POST") {
      return reply(405, {
        success: false,
        error: "Method Not Allowed",
      });
    }

    let body = {};
    try {
      body = event.isBase64Encoded
        ? JSON.parse(Buffer.from(event.body, "base64").toString("utf8"))
        : JSON.parse(event.body || "{}");
    } catch {
      return reply(400, {
        success: false,
        error: "Invalid request body",
      });
    }

    const { emailOrPhone, role } = body;

    if (!emailOrPhone || !role) {
      return reply(400, {
        success: false,
        error: "Missing required fields",
      });
    }

    if (role !== "users" && role !== "agents") {
      return reply(400, {
        success: false,
        error: "Invalid role",
      });
    }

    const email = emailOrPhone.trim().toLowerCase();

    const result = await db.query(
      `
      SELECT id, email
      FROM ${role}
      WHERE LOWER(email) = $1
      LIMIT 1
      `,
      [email]
    );

    if (!result.rows.length) {
      return reply(404, {
        success: false,
        error: "No account found",
      });
    }

    const user = result.rows[0];

    const resetCode = Math.floor(
      100000 + Math.random() * 900000
    ).toString();

    await db.query(
      `
      UPDATE ${role}
      SET reset_code = $2,
          reset_expires = NOW() + INTERVAL '20 minutes'
      WHERE id = $1
      `,
      [user.id, resetCode]
    );

    const transporter = nodemailer.createTransport({
      host: process.env.SMTP_HOST,
      port: Number(process.env.SMTP_PORT),
      secure: false,
      auth: {
        user: process.env.SMTP_USER,
        pass: process.env.SMTP_PASS,
      },
    });

    const subject =
      role === "agents"
        ? "VitaLink Agent Password Reset Code"
        : "VitaLink Password Reset Code";

    const message = `
Hi,

Your VitaLink password reset code is:

${resetCode}

This code expires in 20 minutes.

If you did not request this, you can ignore this email.

– VitaLink Support
`.trim();

    await transporter.sendMail({
      from: `"VitaLink Support" <${process.env.SMTP_USER}>`,
      to: user.email,
      subject,
      text: message,
    });

    console.log(`✅ Reset code sent to ${user.email} (${role})`);

    return reply(200, {
      success: true,
      expiresIn: 20,
      sentTo: user.email,
    });

  } catch (err) {
    console.error("❌ request_reset error:", err);
    return reply(500, {
      success: false,
      error: "Server error",
    });
  }
};