const nodemailer = require("nodemailer");
const db = require("./services/db");

exports.handler = async (event) => {
  try {
    const body = JSON.parse(event.body || "{}");

    if (!body.agent || !body.agent.email || !Array.isArray(body.attachments)) {
      return {
        statusCode: 400,
        body: JSON.stringify({ error: "Invalid payload" }),
      };
    }

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
      to: body.agent.email,
      subject: `VitaLink - Signed HIPAA & SOA from ${body.user || "Client"}`,
      text: `Hello ${body.agent.name || "Agent"},

Your client ${body.user || "Client"} has signed their HIPAA & SOA authorization.

Attached:
• Signed HIPAA & SOA PDF
• Client medication/doctor CSV

– VitaLink`,
      attachments: [],
    };

    // ✅ FIXED ATTACHMENTS (PDF + CSV, Gmail-safe)
    body.attachments.forEach((att) => {
      if (!att.name || !att.content) return;

      const lower = att.name.toLowerCase();
      const isPdf = lower.endsWith(".pdf");

      let buffer;

      // Attempt base64 decode first
      try {
        buffer = Buffer.from(att.content, "base64");

        // Guard: bad/empty decode (PDFs fail silently otherwise)
        if (!buffer || buffer.length < 100) {
          throw new Error("Invalid base64");
        }
      } catch {
        // Fallback: raw binary or text
        buffer = Buffer.isBuffer(att.content)
          ? att.content
          : Buffer.from(att.content);
      }

      mailOptions.attachments.push({
        filename: att.name,
        content: buffer,
        contentType: isPdf ? "application/pdf" : "text/csv",
      });
    });

    await transporter.sendMail(mailOptions);

    // keep your AEP logic
    if (body.user) {
      await db.query(
        `UPDATE users
         SET status = 'complete',
             last_review_year = EXTRACT(YEAR FROM CURRENT_DATE)
         WHERE LOWER(email) = LOWER($1)`,
        [body.user]
      );
    }

    return {
      statusCode: 200,
      body: JSON.stringify({ success: true }),
    };
  } catch (err) {
    console.error("❌ send_form_email error", err);
    return {
      statusCode: 500,
      body: JSON.stringify({ error: err.message }),
    };
  }
};
