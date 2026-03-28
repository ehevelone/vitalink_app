const db = require("./services/db");

exports.handler = async (event) => {
  try {
    const authHeader = event.headers.authorization;

    if (!authHeader) {
      return { statusCode: 401, body: "Missing token" };
    }

    const token = authHeader.split(" ")[1];

    // 🔐 validate user
    const userRes = await db.query(
      `SELECT id FROM users WHERE auth_token = $1`,
      [token]
    );

    if (!userRes.rows.length) {
      return { statusCode: 401, body: "Invalid token" };
    }

    const user_id = userRes.rows[0].id;

    const body = JSON.parse(event.body);
    const profiles = body.profiles;

    if (!profiles || !Array.isArray(profiles)) {
      return { statusCode: 400, body: "Invalid profiles" };
    }

    // 🧹 wipe old profiles for this user
    await db.query(`DELETE FROM profiles WHERE user_id = $1`, [user_id]);

    // ➕ insert fresh list
    for (const p of profiles) {
      await db.query(
        `
        INSERT INTO profiles (id, user_id, name)
        VALUES ($1, $2, $3)
        `,
        [p.id, user_id, p.name]
      );
    }

    return {
      statusCode: 200,
      body: JSON.stringify({ success: true }),
    };

  } catch (err) {
    console.error(err);
    return {
      statusCode: 500,
      body: "Server error",
    };
  }
};