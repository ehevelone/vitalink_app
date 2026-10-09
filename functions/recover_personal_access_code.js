const db = require("./services/db");
const { createMailer, fromAddress } = require("./services/mailer");
const { requestLanguage } = require("./services/notification-language");

const headers = {
  "Content-Type": "application/json",
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "Content-Type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const reply = (statusCode, body) => ({ statusCode, headers, body: JSON.stringify(body) });

exports.handler = async (event) => {
  const neutral = { success: true, message: "If a matching account was found, an email has been sent." };
  try {
    if (event.httpMethod === "OPTIONS") return reply(200, {});
    if (event.httpMethod !== "POST") return reply(405, { success: false, error: "Method Not Allowed" });
    const parsedBody = JSON.parse(event.body || "{}");
    const email = String(parsedBody.email || "").trim().toLowerCase();
    const language = requestLanguage(event, parsedBody) || "en";
    if (!email) return reply(200, neutral);

    const result = await db.query(
      `SELECT email, code AS purchase_code
       FROM activation_codes
       WHERE LOWER(email)=LOWER($1)
       ORDER BY created_at DESC
       LIMIT 1`,
      [email]
    );
    if (result.rows.length) {
      const user = result.rows[0];
      await createMailer().sendMail({
        from: fromAddress("VitaLink Support"),
        to: user.email,
        subject: language === "es"
          ? "Su código de acceso personal de VitaLink"
          : "Your VitaLink Personal Access Code",
        text: language === "es"
          ? `Su código de acceso personal de VitaLink es:\n\n${user.purchase_code}\n\nIngrese este código en VitaLink para continuar. Si usted no solicitó este correo, puede ignorarlo.`
          : `Your VitaLink personal access code is:\n\n${user.purchase_code}\n\nEnter this code in VitaLink to continue. If you did not request this email, you can ignore it.`,
      });
    }
    return reply(200, neutral);
  } catch (err) {
    console.error("recover_personal_access_code error:", err);
    return reply(200, neutral);
  }
};
