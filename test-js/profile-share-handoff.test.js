const test = require('node:test');
const assert = require('node:assert/strict');
const Module = require('node:module');
const path = require('node:path');

function loadWithMocks(relativePath, mocks) {
  const absolutePath = path.resolve(__dirname, '..', relativePath);
  const originalLoad = Module._load;
  Module._load = function (request, parent, isMain) {
    return Object.hasOwn(mocks, request)
      ? mocks[request]
      : originalLoad.call(this, request, parent, isMain);
  };
  try {
    delete require.cache[require.resolve(absolutePath)];
    return require(absolutePath);
  } finally {
    Module._load = originalLoad;
  }
}

function helpers(pushes) {
  return {
    clean: value => String(value ?? '').trim() || null,
    cleanupExpiredPackages: async () => {},
    ensureSchema: async () => {},
    encrypt: value => `encrypted:${value.length}`,
    normalizeSections: value => Array.isArray(value) ? value : ['emergency'],
    parseBody: event => JSON.parse(event.body),
    reply: (statusCode, body) => ({ statusCode, body: JSON.stringify(body) }),
    sendProfileUpdatePush: async args => { pushes.push(args); return { successCount: 1 }; },
    verifyUserSession: async () => true,
  };
}

function event(body) {
  return { httpMethod: 'POST', body: JSON.stringify({
    userId: 'owner-1', sessionToken: 'session', profileId: 'profile-1',
    profileName: 'Profile', allowedSections: ['medications'],
    payload: { profileId: 'profile-1', meds: [{ name: 'Example' }] },
    ...body,
  }) };
}

test('pending invite stages one encrypted snapshot without notifying anyone', async () => {
  const calls = [];
  const pushes = [];
  const client = {
    async query(sql, params = []) {
      calls.push({ sql, params });
      if (sql.includes('FROM profile_share_links')) return { rows: [{
        id: '00000000-0000-0000-0000-000000000001',
        status: 'pending', allowed_sections: ['medications'],
      }] };
      return { rows: [] };
    },
    release() {},
  };
  const { handler } = loadWithMocks('functions/create_profile_update_package.js', {
    './services/db': { connect: async () => client },
    './services/profile-share-sync': helpers(pushes),
  });
  const response = await handler(event({ pendingShareId: '00000000-0000-0000-0000-000000000001' }));
  const body = JSON.parse(response.body);
  assert.equal(response.statusCode, 200);
  assert.equal(body.staged, true);
  assert.equal(body.recipients, 0);
  assert.equal(pushes.length, 0);
  assert.ok(calls.some(call => call.sql.includes('DELETE FROM profile_update_packages')));
  const insert = calls.find(call => call.sql.includes('INSERT INTO profile_update_packages'));
  assert.equal(insert.params[6], '00000000-0000-0000-0000-000000000001');
  assert.ok(insert.params[5].startsWith('encrypted:'));
  assert.ok(calls.some(call => call.sql === 'COMMIT'));
});

test('snapshot cannot be staged for a share outside the authenticated owner and profile', async () => {
  const calls = [];
  const client = {
    async query(sql, params = []) {
      calls.push({ sql, params });
      return { rows: [] };
    },
    release() {},
  };
  const { handler } = loadWithMocks('functions/create_profile_update_package.js', {
    './services/db': { connect: async () => client },
    './services/profile-share-sync': helpers([]),
  });
  const response = await handler(event({ pendingShareId: '00000000-0000-0000-0000-000000000001' }));
  assert.equal(response.statusCode, 404);
  const lookup = calls.find(call => call.sql.includes('FROM profile_share_links'));
  assert.deepEqual(lookup.params, [
    '00000000-0000-0000-0000-000000000001', 'owner-1', 'profile-1',
  ]);
  assert.ok(lookup.sql.includes('owner_user_id = $2'));
  assert.ok(lookup.sql.includes('profile_id = $3'));
  assert.equal(calls.some(call => call.sql.includes('INSERT INTO profile_update_packages')), false);
});

test('acceptance winning the race delivers the snapshot directly', async () => {
  const calls = [];
  const pushes = [];
  const client = {
    async query(sql, params = []) {
      calls.push({ sql, params });
      if (sql.includes('FROM profile_share_links')) return { rows: [{
        id: '00000000-0000-0000-0000-000000000001',
        status: 'accepted', recipient_user_id: 'recipient-1',
        allowed_sections: ['medications'],
      }] };
      return { rows: [] };
    },
    release() {},
  };
  const { handler } = loadWithMocks('functions/create_profile_update_package.js', {
    './services/db': { connect: async () => client },
    './services/profile-share-sync': helpers(pushes),
  });
  const response = await handler(event({ pendingShareId: '00000000-0000-0000-0000-000000000001' }));
  const body = JSON.parse(response.body);
  assert.equal(body.staged, false);
  assert.equal(body.recipients, 1);
  assert.ok(calls.some(call => call.sql.includes('INSERT INTO profile_update_recipients')));
  assert.deepEqual(pushes[0].recipientUserIds, ['recipient-1']);
});

test('accepting a pending invite attaches its snapshot before responding', async () => {
  const calls = [];
  const pushes = [];
  const client = {
    async query(sql, params = []) {
      calls.push({ sql, params });
      if (sql.includes('UPDATE profile_share_links')) return { rows: [{
        id: 'share-1', status: 'accepted', recipient_user_id: 'recipient-1',
      }] };
      if (sql.includes('FROM profile_update_packages')) return { rows: [{
        id: 'package-1', profile_name: 'Profile',
      }] };
      return { rows: [] };
    },
    release() {},
  };
  const { handler } = loadWithMocks('functions/accept_profile_share_link.js', {
    crypto: { randomUUID: () => 'recipient-package-1' },
    './services/db': { connect: async () => client },
    './services/profile-share-sync': helpers(pushes),
  });
  const response = await handler(event({ userId: 'recipient-1', inviteCode: 'VL-TEST' }));
  assert.equal(response.statusCode, 200);
  assert.equal(JSON.parse(response.body).updatesReady, 1);
  assert.ok(calls.some(call => call.sql.includes('INSERT INTO profile_update_recipients')));
  assert.ok(calls.some(call => call.sql === 'COMMIT'));
  assert.deepEqual(pushes[0].recipientUserIds, ['recipient-1']);
});

test('accepted invite stages no duplicate recipient when retried', async () => {
  const calls = [];
  const client = {
    async query(sql, params = []) {
      calls.push(sql);
      if (sql.includes('UPDATE profile_share_links')) return { rows: [{ id: 'share-1' }] };
      return { rows: [] };
    },
    release() {},
  };
  const { handler } = loadWithMocks('functions/accept_profile_share_link.js', {
    './services/db': { connect: async () => client },
    './services/profile-share-sync': helpers([]),
  });
  const response = await handler(event({ userId: 'recipient-1', inviteCode: 'VL-TEST' }));
  assert.equal(JSON.parse(response.body).updatesReady, 0);
  assert.equal(calls.some(sql => sql.includes('INSERT INTO profile_update_recipients')), false);
});
