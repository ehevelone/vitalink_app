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

    console.log("📥 BODY:", body);

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
      SELECT id, email, reset_code, reset_expires
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

    console.log("👤 USER:", user);

    // 🔥 CRITICAL FIX — DO NOT CREATE NEW CODE IF ONE IS ACTIVE
    if (user.reset_expires && new Date(user.reset_expires) > new Date()) {
      console.log("⚠️ Existing code still valid — NOT generating new one");

      return reply(200, {
        success: true,
        message: "Code already sent. Check your email.",
        sentTo: user.email,
      });
    }

    // 🔥 Generate NEW code ONLY if needed
    const resetCode = Math.floor(
      100000 + Math.random() * 900000
    ).toString();

    const expires = new Date(Date.now() + 20 * 60 * 1000);

    await db.query(
      `
      UPDATE ${role}
      SET reset_code = $2,
          reset_expires = $3
      WHERE id = $1
      `,
      [user.id, resetCode, expires]
    );

    console.log("🔐 New Code Generated:", resetCode);

    // 🔥 EMAIL
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

    console.log(`✅ Email sent to ${user.email}`);

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