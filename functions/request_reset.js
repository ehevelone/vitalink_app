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

function getResetTable(role) {
  if (role === "users") return "users";
  if (role === "agents") return "agents";
  if (role === "rsms") return "rsms";
  return null;
}

function getEmailSubject(role) {
  if (role === "agents") return "VitaLink Agent Password Reset Code";
  if (role === "rsms") return "VitaLink RSM Password Reset Code";
  return "VitaLink Password Reset Code";
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

    const resetTable = getResetTable(role);

    if (!resetTable) {
      return reply(400, {
        success: false,
        error: "Invalid role",
      });
    }

    const email = String(emailOrPhone).trim().toLowerCase();

    const result = await db.query(
      `
      SELECT id, email, reset_code, reset_expires
      FROM ${resetTable}
      WHERE LOWER(TRIM(email)) = $1
      LIMIT 1
      `,
      [email]
    );

    if (!result.rows.length) {
      return reply(404, {
        success: false,
        error: "No account found",
        code: "email_not_found",
      });
    }

    const user = result.rows[0];
    const existingCode = String(user.reset_code || "").trim();
    const existingCodeValid =
      existingCode &&
      user.reset_expires &&
      new Date(user.reset_expires) > new Date();

    const resetCode = existingCodeValid
      ? existingCode
      : Math.floor(100000 + Math.random() * 900000).toString();

    const expires = existingCodeValid
      ? user.reset_expires
      : new Date(Date.now() + 20 * 60 * 1000);

    if (!existingCodeValid) {
      await db.query(
        `
        UPDATE ${resetTable}
        SET reset_code = $2,
            reset_expires = $3
        WHERE id = $1
        `,
        [user.id, resetCode, expires]
      );
    }

    const transporter = nodemailer.createTransport({
      host: process.env.SMTP_HOST,
      port: Number(process.env.SMTP_PORT),
      secure: false,
      auth: {
        user: process.env.SMTP_USER,
        pass: process.env.SMTP_PASS,
      },
    });

    const message = `
Hi,

Your VitaLink password reset code is:

${resetCode}

This code expires in 20 minutes.

If you did not request this, you can ignore this email.

- VitaLink Support
`.trim();

    await transporter.sendMail({
      from: `"VitaLink Support" <${process.env.SMTP_USER}>`,
      to: user.email,
      subject: getEmailSubject(role),
      text: message,
    });

    console.log("Password reset email sent", {
      table: resetTable,
      userId: user.id,
      email: user.email,
      reusedExistingCode: Boolean(existingCodeValid),
    });

    return reply(200, {
      success: true,
      expiresIn: 20,
      sentTo: user.email,
      reusedExistingCode: Boolean(existingCodeValid),
    });
  } catch (err) {
    console.error("request_reset error:", err);
    return reply(500, {
      success: false,
      error: "Server error",
    });
  }
};
