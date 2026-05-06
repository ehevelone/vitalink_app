const crypto = require("crypto");
const nodemailer = require("nodemailer");
const db = require("./services/db");

exports.handler = async (event) => {
  try {
    const body = JSON.parse(event.body || "{}");

    if (!body.email || !body.agent_id || !body.agent_name) {
      return {
        statusCode: 400,
        body: JSON.stringify({ success: false, error: "Missing required fields" }),
      };
    }

    // 🔐 Create token
    const token = crypto.randomBytes(32).toString("hex");
    const token_hash = crypto.createHash("sha256").update(token).digest("hex");

    // ⏳ Expiration (24 hours)
    const expiresAt = new Date(Date.now() + 24 * 60 * 60 * 1000);

    // 💾 Store invite
    await db.query(
      `INSERT INTO agent_invites (client_email, new_agent_id, token_hash, expires_at)
       VALUES ($1, $2, $3, $4)`,
      [body.email, body.agent_id, token_hash, expiresAt]
    );

    // 🔗 Build link (FIXED)
    const link = `https://myvitalink.app/.netlify/functions/accept-agent-invite?token=${token}`;

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
      body: JSON.stringify({
        success: true,
        message: "Invite sent",
        messageId: info.messageId,
      }),
    };

  } catch (err) {
    console.error("❌ send-agent-invite error", err);
    return {
      statusCode: 500,
      body: JSON.stringify({
        success: false,
        error: err.message,
      }),
    };
  }
};