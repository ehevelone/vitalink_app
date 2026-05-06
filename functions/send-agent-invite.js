const crypto = require("crypto");
const nodemailer = require("nodemailer");
const db = require("./services/db");

exports.handler = async (event) => {

  // 🔥 CORS PREFLIGHT (REQUIRED)
  if (event.httpMethod === "OPTIONS") {
    return {
      statusCode: 200,
      headers: {
        "Access-Control-Allow-Origin": "*",
        "Access-Control-Allow-Headers": "Content-Type",
        "Access-Control-Allow-Methods": "POST, OPTIONS"
      },
      body: ""
    };
  }

  try {
    const body = JSON.parse(event.body || "{}");

    console.log("BODY:", body);

    if (!body.email || !body.agent_id || !body.agent_name) {
      return {
        statusCode: 400,
        headers: {
          "Access-Control-Allow-Origin": "*",
          "Content-Type": "application/json"
        },
        body: JSON.stringify({ success: false, error: "Missing required fields" }),
      };
    }

    // 🔐 Create token
    const token = crypto.randomBytes(32).toString("hex");
    const token_hash = crypto.createHash("sha256").update(token).digest("hex");

    // ⏳ Expiration (24 hours)
    const expiresAt = new Date(Date.now() + 24 * 60 * 60 * 1000);

    console.log("🔎 INSERTING INVITE:", body.email);
    console.log("AGENT ID:", body.agent_id, typeof body.agent_id);

    // 💾 Store invite
    const insert = await db.query(
      `INSERT INTO agent_invites (client_email, new_agent_id, token_hash, expires_at)
       VALUES ($1, $2::uuid, $3, $4)
       RETURNING id`,
      [
        body.email.trim().toLowerCase(),
        body.agent_id,
        token_hash,
        expiresAt
      ]
    );

    console.log("✅ INSERT RESULT:", insert.rows);

    // 🔗 Build link
    const link = `https://vitalink-app.netlify.app/.netlify/functions/accept-agent-invite?token=${token}`;

    // 📧 Email setup
    const transporter = nodemailer.createTransport({
      host: process.env.SMTP_HOST,
      port: parseInt(process.env.SMTP_PORT || "587", 10),
      secure: false,
      auth: {
        user: process.env.SMTP_USER,
        pass: process.env.SMTP_PASS,
      },
    });

    const mailOptions = {
      from: `"VitaLink" <${process.env.SMTP_USER}>`,
      to: body.email,
      subject: "Connect with your VitaLink Agent",
      text: `Hello,

You’ve been invited to connect with ${body.agent_name} through VitaLink.

Click the link below to accept:
${link}

This link will expire in 24 hours.

– VitaLink`,
    };

    const info = await transporter.sendMail(mailOptions);

    return {
      statusCode: 200,
      headers: {
        "Access-Control-Allow-Origin": "*",
        "Content-Type": "application/json"
      },
      body: JSON.stringify({
        success: true,
        message: "Invite sent",
        messageId: info.messageId,
      }),
    };

  } catch (err) {
    console.error("❌ send-agent-invite error:", err);

    return {
      statusCode: 500,
      headers: {
        "Access-Control-Allow-Origin": "*",
        "Content-Type": "application/json"
      },
      body: JSON.stringify({
        success: false,
        error: err.message,
      }),
    };
  }
};