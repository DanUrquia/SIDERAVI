import {readFileSync} from 'node:fs';

// Operator tool for the existing SIDERA VI field project. Pass a short-lived
// Google OAuth access token on stdin. Never use a Firebase client ID token.
const project = 'sidera-vi';
const database = 'https://sidera-vi-default-rtdb.firebaseio.com';
const auth = 'https://identitytoolkit.googleapis.com';
const session = 'field-test-01';
const slots = ['ARES-01', 'ARES-02'];
const bases = {
  endeavour: {baseLat: -2.295, baseLon: -5.17},
  gale: {baseLat: -5.415, baseLon: 137.725},
  'columbia-hills': {baseLat: -14.5478, baseLon: 175.6165},
  'valles-marineris': {baseLat: -13.83, baseLon: -59.155},
  jezero: {baseLat: 18.386, baseLon: 77.6564},
};
const missions = Object.keys(bases);
const sessionAt = mission => `/${mission}/sessions/${session}`;
const [command, slot, uid, replace, ...extra] = process.argv.slice(2);

function usage() {
  console.error('Usage: supply the Google OAuth access token on stdin to one command.');
  console.error('  node firebase/admin-crew.mjs verify');
  console.error('  node firebase/admin-crew.mjs create-sessions');
  console.error('  node firebase/admin-crew.mjs enroll ARES-01|ARES-02 DEVICE_UID [--replace]');
}

async function admin(token, origin, path, {method, headers, body} = {}) {
  const response = await fetch(origin + path, {
    method,
    headers: {
      authorization: `Bearer ${token}`,
      ...(body === undefined ? {} : {'content-type': 'application/json'}),
      ...headers,
    },
    body: body === undefined ? undefined : JSON.stringify(body),
    signal: AbortSignal.timeout(15000),
  });
  if (!response.ok) throw new Error(`${method ?? 'GET'} ${path} failed (HTTP ${response.status})`);
  return {data: await response.json(), etag: response.headers.get('etag')};
}

async function main() {
  const invalid =
    !['verify', 'create-sessions', 'enroll'].includes(command) ||
    (command !== 'enroll' && slot !== undefined) ||
    (command === 'enroll' &&
      (!slots.includes(slot) || !/^[A-Za-z0-9_-]{1,128}$/.test(uid ?? '') ||
        (replace !== undefined && replace !== '--replace') || extra.length !== 0));
  if (invalid || process.stdin.isTTY) {
    usage();
    process.exitCode = 2;
    return;
  }
  const token = readFileSync(0, 'utf8').trim();
  if (!token) throw new Error('A Google OAuth access token is required.');

  const rows = await Promise.all(missions.map(async (mission) => {
    const value = await admin(token, database, `/missions${sessionAt(mission)}.json`, {
      headers: {'X-Firebase-ETag': 'true'},
    });
    return [mission, value];
  }));
  const found = Object.fromEntries(rows);
  const existing = found.jezero.data?.members;
  if (!existing || !slots.every(id => typeof existing[id] === 'string' && existing[id]) ||
      existing[slots[0]] === existing[slots[1]]) {
    throw new Error('Jezero must contain two distinct existing legacy memberships.');
  }
  const requested = [...slots.map(id => existing[id]), ...(uid ? [uid] : [])];
  const fields = 'users(localId,disabled,email,phoneNumber,providerUserInfo(providerId))';
  const lookup = await admin(token, auth, `/v1/projects/${project}/accounts:lookup?fields=${fields}`, {
    method: 'POST',
    body: {localId: requested},
  });
  const users = new Map((lookup.data.users ?? []).map(user => [user.localId, user]));
  for (const id of slots) {
    const user = users.get(existing[id]);
    if (!user || user.disabled || !(user.providerUserInfo ?? []).some(entry => entry.providerId === 'password')) {
      throw new Error(`The legacy ${id} account is unavailable or no longer a password account.`);
    }
  }

  for (const [mission, {data}] of rows) {
    if (data === null) {
      if (command === 'create-sessions') continue;
      throw new Error(`Session missing in ${mission}.`);
    }
    const metadata = data.metadata;
    const expected = bases[mission];
    if (metadata?.state !== 'active' ||
        !['baseLat', 'baseLon'].every(key =>
          typeof metadata[key] === 'number' && Math.abs(metadata[key] - expected[key]) < 1e-7) ||
        !slots.every(id => data.members?.[id] === existing[id])) {
      throw new Error(`Unexpected metadata or legacy membership in ${mission}.`);
    }
  }

  if (command === 'create-sessions') {
    for (const [mission, {data, etag}] of rows) {
      if (data !== null) continue;
      if (!etag) throw new Error(`Missing ETag in ${mission}; conditional creation is unavailable.`);
      await admin(token, database, `/missions${sessionAt(mission)}.json`, {
        method: 'PUT',
        headers: {'if-match': etag},
        body: {metadata: {state: 'active', ...bases[mission]}, members: existing},
      });
      console.log(`Created ${mission}/${session} with both existing legacy slots.`);
    }
    return;
  }

  if (command === 'enroll') {
    const device = users.get(uid);
    if (!device || device.disabled || device.email || device.phoneNumber ||
        device.providerUserInfo?.length || requested.slice(0, 2).includes(uid)) {
      throw new Error('Device UID must belong to an enabled anonymous identity in this project.');
    }
    const otherSlot = slots.find(id => id !== slot);
    const updates = {};
    for (const [mission, {data}] of rows) {
      const members = data.deviceMembers ?? {};
      if (members[otherSlot] === uid) {
        throw new Error(`This anonymous identity already owns ${otherSlot} in ${mission}.`);
      }
      if (members[slot] && members[slot] !== uid && replace !== '--replace') {
        throw new Error(`${slot} already has a different device in ${mission}. Review the replacement before using --replace.`);
      }
      updates[`${sessionAt(mission).slice(1)}/deviceMembers/${slot}`] = uid;
    }
    // A multi-location update keeps all five assignments consistent and touches
    // only the requested slot. Presence and legacy memberships are left intact.
    await admin(token, database, '/missions.json', {method: 'PATCH', body: updates});
    console.log(`Enrolled ${slot} in ${missions.length} ${session} sessions.`);
    return;
  }

  for (const [mission, {data}] of rows) {
    const enrolled = slots.filter(id => typeof data.deviceMembers?.[id] === 'string');
    console.log(`${mission}/${session}: active; legacy slots verified; enrolled devices ${enrolled.join(', ') || 'none'}.`);
  }
}

try {
  await main();
} catch (error) {
  console.error(error.message);
  process.exitCode = 1;
}
