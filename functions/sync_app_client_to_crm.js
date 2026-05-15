// @ts-nocheck

const {
  syncAppClientToCrm,
} = require("./services/crm-sync");

function reply(statusCode, obj) {
  return {
    statusCode,
    headers: {
      "Content-Type": "application/json",
      "Access-Control-Allow-Origin": "*",
      "Access-Control-Allow-Headers": "Content-Type, Authorization",
      "Access-Control-Allow-Methods": "POST, OPTIONS",
    },
    body: JSON.stringify(obj),
  };
}

exports.handler = async (event) => {
  if (event.httpMethod === "OPTIONS") {
    return reply(200, {});
  }

  if (event.httpMethod !== "POST") {
    return reply(405, {
      success: false,
      error: "Method Not Allowed",
    });
  }

  try {
    let body = {};

    try {
      body = JSON.parse(event.body || "{}");
    } catch (_) {
      return reply(400, {
        success: false,
        error: "Invalid JSON",
      });
    }

    const agentId =
      Number(body.agentId);

    const agentEmail =
      (body.agentEmail || body.agent?.email || "").toString().trim();

    const clientId =
      Number(body.clientId);

    if ((!agentId && !agentEmail) || !clientId) {
      return reply(400, {
        success: false,
        error: "Missing agent or client",
      });
    }

    const clientData =
      body.client || body.profile || {};

    const result = await syncAppClientToCrm({
      agentId,
      agentEmail,
      clientId,
      clientData,
    });

    return reply(result.success ? 200 : 400, result);

  } catch (err) {
    console.error("sync_app_client_to_crm error:", err);

    return reply(500, {
      success: false,
      error: "Server error",
    });
  }
};
