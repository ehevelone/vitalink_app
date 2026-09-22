const {
  markEmailSent,
  saveValidationRun,
  sendValidationEmail,
  validateTaxonomyMappings,
} = require("./services/npi-taxonomy-validation");

exports.handler = async () => {
  try {
    const report = await validateTaxonomyMappings();
    const runId = await saveValidationRun(report, "scheduled");
    await sendValidationEmail(report);
    await markEmailSent(runId);
    console.log("Scheduled NPI taxonomy validation complete", {
      runId,
      status: report.status,
      confirmedCount: report.confirmedCount,
      reviewCount: report.reviewCount,
    });
    return { statusCode: 200 };
  } catch (error) {
    console.error("scheduled-npi-taxonomy-validation error:", error);
    return { statusCode: 500 };
  }
};
