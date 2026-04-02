const db = require("./services/db");
const admin = require("firebase-admin");

/* INIT FIREBASE */
if (!admin.apps.length) {
  let privateKey = process.env.FIREBASE_PRIVATE_KEY;

  if (privateKey && privateKey.includes("\\n")) {
    privateKey = privateKey.replace(/\\n/g, "\n");
  }

  admin.initializeApp({
    credential: admin.credential.cert({
      projectId: process.env.FIREBASE_PROJECT_ID,
      clientEmail: process.env.FIREBASE_CLIENT_EMAIL,
      privateKey: privateKey
    })
  });
}

exports.handler = async (event) => {

  if (event.httpMethod === "OPTIONS") {
    return {
      statusCode: 200,
      headers: {
        "Access-Control-Allow-Origin": "https://myvitalink.app",
        "Access-Control-Allow-Headers": "Content-Type",
        "Access-Control-Allow-Methods": "POST, OPTIONS"
      },
      body: ""
    };
  }

  try {

    const body = JSON.parse(event.body || "{}");

    const order_id = body.order_id || body.request_id;

    if (!order_id) {
      return {
        statusCode: 400,
        headers: { "Access-Control-Allow-Origin": "https://myvitalink.app" },
        body: JSON.stringify({ success:false, error:"Missing order_id" })
      };
    }

    // ✅ GET ORDER + USER
    const result = await db.query(
      `
      SELECT user_id, qr_code
      FROM public.order_requests
      WHERE id = $1
      LIMIT 1
      `,
      [order_id]
    );

    if (result.rows.length === 0) {
      return {
        statusCode: 404,
        headers: { "Access-Control-Allow-Origin": "https://myvitalink.app" },
        body: JSON.stringify({ success:false, error:"Order not found" })
      };
    }

    const { user_id, qr_code } = result.rows[0];

    // ✅ APPROVE
    await db.query(
      `
      UPDATE public.order_requests
      SET status = 'approved', approved_at = NOW()
      WHERE id = $1
      `,
      [order_id]
    );

    // 🔔 SEND PUSH AGAIN (GUARANTEED)
    const deviceRes = await db.query(
      `
      SELECT device_token
      FROM public.user_devices
      WHERE user_id = $1
      LIMIT 1
      `,
      [user_id]
    );

    if (deviceRes.rows.length > 0) {

      const token = deviceRes.rows[0].device_token;

      try {
        await admin.messaging().send({
          token,
          android: { priority: "high" },
          notification: {
            title: "VitaLink Order Approved",
            body: "Your order has been approved"
          },
          data: {
            type: "order_approved",
            order_id: order_id.toString()
          }
        });

        console.log("✅ APPROVAL PUSH SENT");

      } catch (err) {
        console.error("Push failed:", err);
      }
    }

    return {
      statusCode: 200,
      headers: { "Access-Control-Allow-Origin": "https://myvitalink.app" },
      body: JSON.stringify({
        success: true,
        qr_code: qr_code
      })
    };

  } catch (err) {
    console.error("approve_order error:", err);

    return {
      statusCode: 500,
      headers: { "Access-Control-Allow-Origin": "https://myvitalink.app" },
      body: JSON.stringify({
        success:false,
        error:"Server error"
      })
    };
  }
};