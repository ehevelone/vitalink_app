// functions/request_delete.js
function ok(msg) {
  return {
    statusCode: 200,
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ success: true, message: msg }),
  };
}

function fail(msg, code = 400) {
  return {
    statusCode: code,
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ success: false, error: msg }),
  };
}

exports.handler = async (event) => {
  try {
    if (event.httpMethod === "OPTIONS") {
  return {
    statusCode: 200,
    headers: {
      "Access-Control-Allow-Origin": "*",
      "Access-Control-Allow-Headers": "Content-Type, Authorization",
      "Access-Control-Allow-Methods": "POST, OPTIONS",
    },
    body: "",
  };
}

    if (event.httpMethod !== "POST") return fail("Method not allowed", 405);
    return fail("This legacy account-deletion endpoint has been retired", 410);
  } catch (err) {
    console.error("❌ Error in request_delete:", err);
    return fail("Server error during account deletion ❌", 500);
  }
};
