const { createClient } = require("@supabase/supabase-js");

const supabase = createClient(
  process.env.SUPABASE_URL,
  process.env.SUPABASE_SERVICE_ROLE_KEY
);

exports.handler = async function (event) {
  try {
    // RSM count
    const { count: totalRSMs } = await supabase
      .from("rsms")
      .select("*", { count: "exact", head: true });

    // Agents count
    const { count: totalAgents } = await supabase
      .from("agents")
      .select("*", { count: "exact", head: true });

    // Active agents count
    const { count: activeAgents } = await supabase
      .from("agents")
      .select("*", { count: "exact", head: true })
      .eq("active", true);

    // Users count
    const { count: totalUsers } = await supabase
      .from("users")
      .select("*", { count: "exact", head: true });

    // Profiles count
    const { count: totalProfiles } = await supabase
      .from("profiles")
      .select("*", { count: "exact", head: true });

    // QR scans count (change table name if different)
    const { count: totalScans } = await supabase
      .from("qr_scans")
      .select("*", { count: "exact", head: true });

    return {
      statusCode: 200,
      body: JSON.stringify({
        totalRSMs: totalRSMs || 0,
        totalAgents: totalAgents || 0,
        activeAgents: activeAgents || 0,
        totalUsers: totalUsers || 0,
        totalProfiles: totalProfiles || 0,
        totalScans: totalScans || 0
      })
    };

  } catch (err) {
    return {
      statusCode: 500,
      body: JSON.stringify({ error: "Server error", details: err.message })
    };
  }
};
