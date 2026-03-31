const db = require("./services/db");
const admin = require("firebase-admin");

/* LOAD FIREBASE SERVICE ACCOUNT */
let serviceAccount;

try {
  serviceAccount = require("./firebase-service-account.json");

  // 🔥 REQUIRED FIX
  if (!process.env.FIREBASE_PRIVATE_KEY) {
    throw new Error("FIREBASE_PRIVATE_KEY MISSING");
  }

  // ✅ PRIVATE KEY (fixed formatting)
  serviceAccount.private_key = process.env.FIREBASE_PRIVATE_KEY
    .trim()
    .replace(/\\n/g, '\n');

  // ✅ ADD THIS (PRIVATE KEY ID FROM ENV)
  serviceAccount.private_key_id = process.env.FIREBASE_PRIVATE_KEY_ID;

  console.log("Firebase service account loaded");
} catch (err) {
  console.error("Failed to load firebase-service-account.json", err);
  throw err;
}

/* INIT FIREBASE */
if (!admin.apps.length) {
  admin.initializeApp({
    credential: admin.credential.cert(serviceAccount),
  });
  console.log("Firebase initialized");
}

exports.handler = async (event) => {

  // 🔥 CORS PREFLIGHT HANDLER
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

    // ✅ SAFE PARSE
    if (!event.body) {
      return {
        statusCode: 400,
        headers: {
          "Access-Control-Allow-Origin": "https://myvitalink.app"
        },
        body: JSON.stringify({ success:false, error: "Missing request body" }),
      };
    }

    let body;
    try {
      body = JSON.parse(event.body);
    } catch (err) {
      return {
        statusCode: 400,
        headers: {
          "Access-Control-Allow-Origin": "https://myvitalink.app"
        },
        body: JSON.stringify({ success:false, error: "Invalid JSON" }),
      };
    }

    // ✅ ACCEPT BOTH (cart OR items)
    const user_id = body.user_id;
    const items = body.items || body.cart;

    if (!user_id || !items || items.length === 0) {
      return {
        statusCode: 400,
        headers: {
          "Access-Control-Allow-Origin": "https://myvitalink.app"
        },
        body: JSON.stringify({ success:false, error: "Missing data" }),
      };
    }

    // 🧾 SAVE ORDER REQUEST
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

          // 🔥 CRITICAL ANDROID DELIVERY FIX
          android: {
            priority: "high"
          },

          notification: {
            title: "VitaLink Order Approval",
            body: "Tap to review and approve your accessory order"
          },

          data: {
            type: "order_approval",
            request_id: request_id.toString()
          }
        });

        console.log("✅ PUSH SENT");

      } catch (pushErr) {
        console.error("Push failed:", pushErr);
      }
    }

    return {
      statusCode: 200,
      headers: {
        "Access-Control-Allow-Origin": "https://myvitalink.app"
      },
      body: JSON.stringify({
        success: true,
        order_id: request_id
      }),
    };

  } catch (err) {
    console.error("❌ SERVER ERROR:", err);
    return {
      statusCode: 500,
      headers: {
        "Access-Control-Allow-Origin": "https://myvitalink.app"
      },
      body: JSON.stringify({ success:false, error: "Server error" }),
    };
  }
};