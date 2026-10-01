const { createMailer, fromAddress } = require("./services/mailer");
const {
  markFailed,
  runTemporaryDataCleanup,
} = require("./services/temporary-data-cleanup");

async function sendFailureAlert() {
  const to = String(
    process.env.CLEANUP_ALERT_EMAIL || process.env.SMTP_USER || ""
  ).trim();
  if (!to) return;
  await createMailer().sendMail({
    from: fromAddress("VitaLink System"),
    to,
    subject: "VitaLink temporary-data cleanup failed",
    text: "The scheduled temporary-data cleanup failed. Review the Netlify function log for purge_expired_temporary_data.",
  });
}

exports.handler = async () => {
  try {
    const counts = await runTemporaryDataCleanup();
    console.log(JSON.stringify({
      event: "temporary_data_cleanup_succeeded",
      completedAt: new Date().toISOString(),
      counts,
    }));
    return {
      statusCode: 200,
      body: JSON.stringify({ success: true, counts }),
    };
  } catch (_) {
    console.error("temporary_data_cleanup_failed", new Date().toISOString());
    await markFailed();
    try {
      await sendFailureAlert();
    } catch (_) {
      console.error("temporary_data_cleanup_alert_failed", new Date().toISOString());
    }
    return {
      statusCode: 500,
      body: JSON.stringify({ success: false, error: "Cleanup failed" }),
    };
  }
};
