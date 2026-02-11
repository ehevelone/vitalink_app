const nodemailer = require("nodemailer");
const db = require("./services/db");
const generateClientReportPdf = require("./generate-client-report-pdf");

exports.handler = async (event) => {
  try {
    const body = JSON.parse(event.body || "{}");

    if (!body.agent || !body.agent.email || !Array.isArray(body.attachments)) {
      return {
        statusCode: 400,
        body: JSON.stringify({ success: false, error: "Invalid payload" }),
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
• Client information report (PDF)
• Client medication/doctor CSV

– VitaLink`,
      attachments: [],
    };

    // 🔹 Generate Client Report PDF
    const reportPdfBuffer = await generateClientReportPdf({
      name: body.user || "Client",
      email: body.user_email || "",
      phone: body.user_phone || "",
      dob: body.user_dob || "",
      medications: body.medications || [],
      providers: body.providers || [],
    });

    mailOptions.attachments.push({
      filename: "VitaLink_Client_Report.pdf",
      content: reportPdfBuffer,
      contentType: "application/pdf",
    });

    // 🔹 Existing attachments (SOA + CSV)
    body.attachments.forEach((att) => {
      if (!att.name || !att.content) return;

      const lower = att.name.toLowerCase();
      const isPdf = lower.endsWith(".pdf");

      let buffer;

      try {
        buffer = Buffer.from(att.content, "base64");
        if (!buffer || buffer.length < 100) {
          throw new Error("Invalid base64");
        }
      } catch {
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

    // 🔥 Send email and capture confirmation
    const info = await transporter.sendMail(mailOptions);

    // Update user record
    if (body.user) {
      await db.query(
        `UPDATE users
         SET status = 'complete',
             last_review_year = EXTRACT(YEAR FROM CURRENT_DATE)
         WHERE LOWER(email) = LOWER($1)`,
        [body.user]
      );
    }

    // ✅ Return confirmation details
    return {
      statusCode: 200,
      body: JSON.stringify({
        success: true,
        message: "Email sent successfully",
        messageId: info.messageId,
        accepted: info.accepted,
      }),
    };

  } catch (err) {
    console.error("❌ send_form_email error", err);
    return {
      statusCode: 500,
      body: JSON.stringify({
        success: false,
        error: err.message,
      }),
    };
  }
};
