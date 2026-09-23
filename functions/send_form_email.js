const db = require("./services/db");
const generateClientReportPdf = require("./generate-client-report-pdf");
const { createMailer, fromAddress } = require("./services/mailer");
const {
  syncVitalinkPackageToCrm,
} = require("./services/crm-sync");
const {
  getAuthorizedUser,
  recordSigning,
} = require("./services/authorization-status");

exports.handler = async (event) => {
  try {
    const body = JSON.parse(event.body || "{}");

    if (!body.agent || !body.agent.email || !Array.isArray(body.attachments)) {
      return {
        statusCode: 400,
        body: JSON.stringify({ success: false, error: "Invalid payload" }),
      };
    }

    const transporter = createMailer();
    const hipaaAttachment = body.attachments.find((att) =>
      att.name === "Health_Information_Authorization.pdf"
    );
    const soaAttachment = body.attachments.find((att) =>
      att.name === "Medicare_Scope_of_Appointment.pdf"
    );
    const isSeparateConsent = Boolean(hipaaAttachment || soaAttachment || body.soa_product_types);
    if (isSeparateConsent && (!hipaaAttachment?.content || !soaAttachment?.content ||
        !Array.isArray(body.soa_product_types) || body.soa_product_types.length === 0)) {
      return {
        statusCode: 400,
        body: JSON.stringify({ success: false, error: "Both signed documents and selected SOA products are required" }),
      };
    }
    let signedUser = null;
    if (isSeparateConsent) {
      signedUser = await getAuthorizedUser(body.app_user_id, body.sessionToken);
      if (!signedUser ||
          signedUser.email.toLowerCase() !== String(body.user_email || '').toLowerCase() ||
          signedUser.agent_email?.toLowerCase() !== body.agent.email.toLowerCase()) {
        return {
          statusCode: 403,
          body: JSON.stringify({ success: false, error: 'Client session or registered agent does not match' }),
        };
      }
    }

    const mailOptions = {
      from: fromAddress("VitaLink"),
      to: body.agent.email,
      subject: `VitaLink - Signed authorization and SOA from ${body.user || "Client"}`,
      text: `Hello ${body.agent.name || "Agent"},

Your client ${body.user || "Client"} has signed their information authorization and Scope of Appointment.

Attached:
• Signed information authorization PDF
• Signed Scope of Appointment PDF
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
      pharmacies: body.pharmacies || [],
      providers: body.providers || [],
    });

    mailOptions.attachments.push({
      filename: "VitaLink_Client_Report.pdf",
      content: reportPdfBuffer,
      contentType: "application/pdf",
    });

    // Signed forms and the client CSV are sent as separate attachments.
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

    if (signedUser) {
      try {
        await recordSigning(signedUser.id, signedUser.agent_id, body.signed_at);
      } catch (error) {
        console.error('Authorization status record failed after email delivery:', error);
      }
    }

    // Update user record
    if (body.user_email) {
      await db.query(
        `UPDATE users
         SET status = 'complete',
             last_review_year = EXTRACT(YEAR FROM CURRENT_DATE)
         WHERE LOWER(email) = LOWER($1)`,
        [body.user_email]
      );
    }

    // ✅ Return confirmation details
    let crmSync = null;

    try {
      const legacyAttachment = (body.attachments || []).find((att) =>
        String(att.name || "").toLowerCase().includes("hipaa")
      );

      crmSync = await syncVitalinkPackageToCrm({
        agentEmail: body.agent.email,
        clientData: {
          name: body.user,
          email: body.user_email,
          phone: body.user_phone,
          dob: body.user_dob,
          address: body.user_address,
          city: body.user_city,
          state: body.user_state,
          zip: body.user_zip,
          meds: body.medications || [],
          doctors: body.providers || [],
        },
        packageData: {
          appUserId: body.app_user_id,
          appProfileId: body.app_profile_id,
          signedAt: body.signed_at,
          medsReviewedAt: body.meds_reviewed_at,
          doctorsReviewedAt: body.doctors_reviewed_at,
          emergencyContacts: body.emergency_contacts || [],
          pharmacies: body.pharmacies || [],
          hipaaPdfBase64: hipaaAttachment?.content || legacyAttachment?.content,
          soaPdfBase64: soaAttachment?.content || legacyAttachment?.content,
          soaProductTypes: body.soa_product_types || null,
          newAuthorizationSigned: Boolean(signedUser),
        },
      });
    } catch (syncErr) {
      console.error("CRM sync after send failed:", syncErr);
      crmSync = {
        success: false,
        error: syncErr.message || "CRM sync failed",
      };
    }

    return {
      statusCode: 200,
      body: JSON.stringify({
        success: true,
        message: "Email sent successfully",
        messageId: info.messageId,
        accepted: info.accepted,
        crm_sync: crmSync,
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
