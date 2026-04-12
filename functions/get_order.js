const headers = {
  "Access-Control-Allow-Origin": "https://myvitalink.app",
  "Access-Control-Allow-Headers": "Content-Type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

exports.handler = async (event) => {

  if (event.httpMethod === "OPTIONS") {
    return {
      statusCode: 200,
      headers,
      body: ""
    };
  }

  try {

    const body = JSON.parse(event.body || "{}");
    const { order_id } = body;

    if (!order_id) {
      return {
        statusCode: 400,
        headers,
        body: JSON.stringify({
          success: false,
          error: "Missing order_id"
        })
      };
    }

    console.log("GET ORDER REQUEST:", order_id);

    // 🔥 FUTURE: pull from DB here
    // const result = await db.query(...)

    return {
      statusCode: 200,
      headers,
      body: JSON.stringify({
        success: true,
        order: {
          order_id
        }
      })
    };

  } catch (err) {

    console.error("get_order error:", err);

    return {
      statusCode: 500,
      headers,
      body: JSON.stringify({
        success: false,
        error: "Server error"
      })
    };
  }
};