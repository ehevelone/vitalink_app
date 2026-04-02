const db = require("./services/db");
const admin = require("firebase-admin");

/* INIT FIREBASE */
if (!admin.apps.length) {
  try {

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

    console.log("✅ Firebase initialized");

  } catch (err) {
    console.error("🔥 Firebase init crash:", err);
    throw err;
  }
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

  console.log("🔥 RAW BODY:", event.body);

  try {

    if (!event.body) {
      return {
        statusCode: 400,
        headers: { "Access-Control-Allow-Origin": "https://myvitalink.app" },
        body: JSON.stringify({ success:false, error: "Missing request body" }),
      };
    }

    let body;
    try {
      body = JSON.parse(event.body);
    } catch {
      return {
        statusCode: 400,
        headers: { "Access-Control-Allow-Origin": "https://myvitalink.app" },
        body: JSON.stringify({ success:false, error: "Invalid JSON" }),
      };
    }

    const user_id = body.user_id;
    const items = body.items || body.cart;

    if (!user_id || !items || items.length === 0) {
      return {
        statusCode: 400,
        headers: { "Access-Control-Allow-Origin": "https://myvitalink.app" },
        body: JSON.stringify({ success:false, error: "Missing data" }),
      };
    }

    // 🧾 SAVE ORDER
    const result = await db.query(
      `
      INSERT INTO public.order_requests (user_id, items, status)
      VALUES ($1, $2, 'pending')
      RETURNING id
      `,
      [user_id, JSON.stringify(items)]
    );

    const request_id = result.rows[0].id;

    // 🔥 GET DEVICE TOKEN
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

      console.log("📱 SENDING TO TOKEN:", token);

      try {

        await admin.messaging().send({
          token,

          notification: {
            title: "VitaLink Order Approval",
            body: "Tap to review and approve your accessory order"
          },

          data: {
            type: "order_approval",
            request_id: request_id.toString()
          },

          android: {
            priority: "high",
            notification: {
              channelId: "default",
              priority: "high",
              sound: "default"
            }
          }
        });

        console.log("✅ PUSH SENT");

      } catch (pushErr) {
        console.error("❌ PUSH FAILED:", pushErr);
      }
    }

    return {
      statusCode: 200,
      headers: { "Access-Control-Allow-Origin": "https://myvitalink.app" },
      body: JSON.stringify({
        success: true,
        order_id: request_id
      }),
    };

  } catch (err) {
    console.error("❌ SERVER ERROR:", err);
    return {
      statusCode: 500,
      headers: { "Access-Control-Allow-Origin": "https://myvitalink.app" },
      body: JSON.stringify({ success:false, error: "Server error" }),
    };
  }
};