const { createMailer, fromAddress } = require('./services/mailer');
const {
  ensureAuthorizationSchema,
  getAuthorizedUser,
  getStatus,
  recordRevocation,
  markAgentNotified,
  markCrmRevoked,
} = require('./services/authorization-status');

function reply(statusCode, data) {
  return {
    statusCode,
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(data),
  };
}

exports.handler = async (event) => {
  if (event.httpMethod !== 'POST') {
    return reply(405, { success: false, error: 'Method not allowed' });
  }

  try {
    const body = JSON.parse(event.body || '{}');
    const user = await getAuthorizedUser(body.userId, body.sessionToken);
    if (!user) return reply(403, { success: false, error: 'Session expired. Please sign in again.' });

    await ensureAuthorizationSchema();
    if (body.action === 'status') {
      const status = await getStatus(user.id);
      return reply(200, {
        success: true,
        agentName: user.agent_name,
        signedAt: status?.signed_at || null,
        revokedAt: status?.revoked_at || null,
        agentNotifiedAt: status?.agent_notified_at || null,
      });
    }

    if (body.action !== 'revoke') {
      return reply(400, { success: false, error: 'Unknown action' });
    }

    if (!user.agent_email) {
      return reply(409, { success: false, error: 'No registered agent email is available.' });
    }

    const revocation = await recordRevocation(user.id, user.agent_id);
    try {
      await markCrmRevoked(user.id, user.crm_uuid, revocation.revoked_at);
    } catch (error) {
      console.error('CRM revocation status update failed:', error);
    }

    if (!revocation.agent_notified_at) {
      try {
        const delivery = await createMailer().sendMail({
          from: fromAddress('VitaLink'),
          to: user.agent_email,
          subject: 'VitaLink client withdrawal of authorization and SOA',
          text: `Hello ${user.agent_name || 'Agent'},\n\n${[user.first_name, user.last_name].filter(Boolean).join(' ') || user.email} (${user.email}) used VitaLink to withdraw their Health Information Authorization and Medicare Scope of Appointment on ${new Date(revocation.revoked_at).toISOString()}.\n\nDo not rely on these permissions for future information sharing or Medicare product discussions. This does not undo information already shared. Please retain this notice with your client records.\n\nVitaLink`,
        });
        if (!delivery.accepted?.some((address) =>
            address.toLowerCase() === user.agent_email.toLowerCase())) {
          throw new Error('Agent address was not accepted by SMTP');
        }
        await markAgentNotified(user.id);
      } catch (error) {
        console.error('Agent revocation notice failed:', error);
        return reply(503, {
          success: false,
          recorded: true,
          error: 'Withdrawal recorded, but agent notification failed. Please retry Send Revocation.',
        });
      }
    }

    return reply(200, {
      success: true,
      revokedAt: revocation.revoked_at,
      agentName: user.agent_name,
    });
  } catch (error) {
    console.error('manage_authorizations error:', error);
    return reply(500, { success: false, error: 'Unable to process authorization request.' });
  }
};
