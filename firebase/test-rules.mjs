import assert from 'node:assert/strict';
import {randomUUID} from 'node:crypto';

// Use only the isolated localhost demo project started by firebase emulators:exec.
const project = 'demo-sideravi';
const origin = 'http://127.0.0.1:9000';
const identity = 'http://127.0.0.1:9099/identitytoolkit.googleapis.com/v1/accounts:';
const session = 'test-' + randomUUID();
const root = '/missions/jezero/sessions/' + session;
const write = (value) => ({
  method: 'PUT', body: JSON.stringify(value), headers: {'content-type': 'application/json'}
});

async function account() {
  const credentials = {
    email: randomUUID() + '@example.test', password: randomUUID(), returnSecureToken: true,
  };
  async function auth(method) {
    const response = await fetch(identity + method + '?key=demo', {
      ...write(credentials), method: 'POST',
    });
    assert.equal(response.status, 200, await response.clone().text());
    return response.json();
  }
  const created = await auth('signUp');
  const signedIn = await auth('signInWithPassword');
  assert.equal(signedIn.localId, created.localId);
  return signedIn;
}

async function anonymousAccount() {
  const response = await fetch(identity + 'signUp?key=demo', {
    ...write({returnSecureToken: true}), method: 'POST',
  });
  assert.equal(response.status, 200, await response.clone().text());
  return response.json();
}

function uri(path, token) {
  const target = new URL(path + '.json', origin);
  target.searchParams.set('ns', project + '-default-rtdb');
  if (token) target.searchParams.set('auth', token);
  return target;
}

async function expectStatus(path, token, status, options) {
  const admin = token === 'owner';
  const result = await fetch(uri(path, admin ? null : token), {
    ...options,
    headers: {...options?.headers, ...(admin ? {authorization: 'Bearer owner'} : {})},
  });
  const body = await result.text();
  assert.equal(result.status, status, body);
  return JSON.parse(body);
}

const [dan, adrian, outsider] = await Promise.all([account(), account(), account()]);
const seed = {
  metadata: {state: 'active', baseLat: 18, baseLon: 77},
  members: {'ARES-01': dan.localId, 'ARES-02': adrian.localId},
};
await expectStatus(root, 'owner', 200, write(seed));
const pose = {
  marsLon: 77, marsLat: 18, mode: 'live', quality: 'uncertain',
  online: true, updated: {'.sv': 'timestamp'}, relativeHeading: 20,
};
const presence = root + '/presence';
await expectStatus(presence, null, 401);
await expectStatus(presence, outsider.idToken, 401);
await expectStatus(presence, adrian.idToken, 200);
await expectStatus(root + '/members', adrian.idToken, 401);
await expectStatus(root + '/members/ARES-01', null, 401);
await expectStatus(root + '/members/ARES-01', outsider.idToken, 401);
await expectStatus(root + '/members/ARES-01', dan.idToken, 200);
await expectStatus(root + '/members/ARES-02', adrian.idToken, 200);
await expectStatus(root + '/members/ARES-01', adrian.idToken, 401);
await expectStatus(root + '/members/ARES-02', dan.idToken, 401);
await expectStatus(root + '/members/ARES-01', dan.idToken, 401, write(outsider.localId));
await expectStatus(root.replace('jezero', 'gale') + '/presence', dan.idToken, 401);
await expectStatus(presence + '/ARES-02', dan.idToken, 401, write(pose));
await expectStatus(presence + '/ARES-01', dan.idToken, 401, write({...pose, earthLatitude: 0}));
await expectStatus(presence + '/ARES-01', dan.idToken, 401, write({...pose, marsLat: 91}));
await expectStatus(presence + '/ARES-01', dan.idToken, 401, write({...pose, updated: 1}));
await expectStatus(presence + '/ARES-01', dan.idToken, 200, write(pose));
await expectStatus(presence + '/ARES-02', adrian.idToken, 200, write(pose));

const abort = new AbortController();
const stopwatch = setTimeout(() => abort.abort(), 5000);
try {
  const response = await fetch(uri(presence, adrian.idToken), {
    headers: {accept: 'text/event-stream'}, signal: abort.signal,
  });
  assert.equal(response.status, 200);
  const reader = response.body.pipeThrough(new TextDecoderStream()).getReader();
  assert.match((await reader.read()).value, /"ARES-01"/);
  await expectStatus(presence + '/ARES-01', dan.idToken, 200, write({...pose, relativeHeading: 95}));
  let event = '';
  while (!event.includes('"relativeHeading":95')) {
    const {value, done} = await reader.read();
    assert.equal(done, false);
    event += value;
  }
} finally {
  clearTimeout(stopwatch);
  abort.abort();
}

await expectStatus(root + '/metadata/state', 'owner', 200, write('ended'));
await expectStatus(root + '/members/ARES-01', dan.idToken, 401);
await expectStatus(presence, adrian.idToken, 401);
await expectStatus(presence + '/ARES-01', dan.idToken, 401, write(pose));
console.log('Firebase emulator passed password sign-in, own-slot membership and writes, session isolation, rejection of extra fields, streamed updates, and termination.');

const [danPhone, adrianPhone, sparePhone] = await Promise.all(
  Array.from({length: 3}, anonymousAccount),
);
const missionIds = ['endeavour', 'gale', 'columbia-hills', 'valles-marineris', 'jezero'];
const sessionAt = mission => '/missions/' + mission + '/sessions/field-test-01';

// Reuse the legacy account membership for every mission. The first anonymous
// sign-in by itself is insufficient to grant either slot any permissions.
for (const mission of missionIds) {
  const session = sessionAt(mission);
  await expectStatus(session, 'owner', 200, write(seed));
  await expectStatus(session + '/presence', danPhone.idToken, 401);
  await expectStatus(session + '/presence/ARES-01', danPhone.idToken, 401, write(pose));
  await expectStatus(
    session + '/deviceMembers/ARES-01',
    danPhone.idToken,
    401,
    write(danPhone.localId),
  );
  await expectStatus(session + '/deviceMembers/ARES-01', 'owner', 200, write(danPhone.localId));
  await expectStatus(session + '/deviceMembers/ARES-02', 'owner', 200, write(adrianPhone.localId));
}

for (const [index, mission] of missionIds.entries()) {
  const session = sessionAt(mission);
  const path = session + '/presence';
  await expectStatus(path, null, 401);
  await expectStatus(path, sparePhone.idToken, 401);
  await expectStatus(session + '/deviceMembers', danPhone.idToken, 401);
  await expectStatus(session + '/deviceMembers/ARES-01', adrianPhone.idToken, 401);
  await expectStatus(session + '/deviceMembers/ARES-02', danPhone.idToken, 401);
  assert.equal(
    await expectStatus(session + '/deviceMembers/ARES-01', danPhone.idToken, 200),
    danPhone.localId,
  );
  assert.equal(
    await expectStatus(session + '/deviceMembers/ARES-02', adrianPhone.idToken, 200),
    adrianPhone.localId,
  );
  await expectStatus(session + '/members/ARES-01', dan.idToken, 200);
  assert.equal(await expectStatus(path, danPhone.idToken, 200), null);
  await expectStatus(path + '/ARES-02', danPhone.idToken, 401, write(pose));
  await expectStatus(path + '/ARES-01', adrianPhone.idToken, 401, write(pose));
  await expectStatus(
    path + '/ARES-01',
    danPhone.idToken,
    401,
    write({...pose, earthLatitude: 0}),
  );
  await expectStatus(path + '/ARES-02', adrianPhone.idToken, 200, write(pose));

  const opening = new AbortController();
  const timeout = setTimeout(() => opening.abort(), 5000);
  try {
    const response = await fetch(uri(path, adrianPhone.idToken), {
      headers: {accept: 'text/event-stream'}, signal: opening.signal,
    });
    assert.equal(response.status, 200);
    const reader = response.body.pipeThrough(new TextDecoderStream()).getReader();
    assert.match((await reader.read()).value, /"ARES-02"/);
    const longitude = 60 + index;
    await expectStatus(
      path + '/ARES-01',
      danPhone.idToken,
      200,
      write({...pose, marsLon: longitude}),
    );
    let event = '';
    while (!event.includes('"marsLon":' + longitude)) {
      const {value, done} = await reader.read();
      assert.equal(done, false);
      event += value;
    }
    assert.equal((await expectStatus(path, danPhone.idToken, 200))['ARES-01'].marsLon, longitude);
    const otherMission = missionIds[(index + 1) % missionIds.length];
    const neighbor = await expectStatus(sessionAt(otherMission) + '/presence', danPhone.idToken, 200);
    assert.notEqual(neighbor?.['ARES-01']?.marsLon, longitude);
  } finally {
    clearTimeout(timeout);
    opening.abort();
  }
}

// Check atomic PIN/pose updates, SSE delivery and independent SOS state.
const serverTime = {'.sv': 'timestamp'};
const location = {marsLon: -5.17, marsLat: -2.295};
const tracked = {...pose, ...location, quality: 'accepted'};
const beforeRescue = {...tracked, marsLat: location.marsLat + .001};
const sendPin = (slot, point) => ({
  method: 'PATCH',
  body: JSON.stringify({
    ['presence/' + slot]: {...tracked, ...point},
    ['signals/pins/' + slot]: {...point, updated: serverTime},
  }),
  headers: {'content-type': 'application/json'},
});
const sse = async (path, user, apply, text) => {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), 5000);
  try {
    const response = await fetch(uri(path, user), {
      headers: {accept: 'text/event-stream'}, signal: controller.signal,
    });
    assert.equal(response.status, 200);
    const reader = response.body.pipeThrough(new TextDecoderStream()).getReader();
    assert.equal((await reader.read()).done, false);
    await apply();
    let data = '';
    while (!data.includes(text)) {
      const chunk = await reader.read();
      assert.equal(chunk.done, false);
      data += chunk.value;
    }
  } finally {
    clearTimeout(timer);
    controller.abort();
  }
};
for (const mission of missionIds) {
  const sessionPath = sessionAt(mission);
  const signals = sessionPath + '/signals';
  const incident = signals + '/sos';
  const danToken = danPhone.idToken;
  const peerToken = adrianPhone.idToken;
  const pin = signals + '/pins/ARES-01';
  assert.equal(await expectStatus(signals, danToken, 200), null);
  await expectStatus(signals, null, 401);
  await expectStatus(signals, sparePhone.idToken, 401);
  await expectStatus(pin, peerToken, 401, write({...location, updated: serverTime}));
  await expectStatus(pin, danToken, 401, write({...location, updated: 2}));
  await expectStatus(pin, danToken, 401, write({...location, updated: serverTime, earthLatitude: 0}));
  await expectStatus(sessionPath, null, 401, sendPin('ARES-01', location));
  await expectStatus(sessionPath, peerToken, 401, sendPin('ARES-01', location));

  await sse(signals, peerToken,
    () => expectStatus(sessionPath, danToken, 200, sendPin('ARES-01', location)),
    '"marsLon":-5.17');
  assert.equal((await expectStatus(pin, peerToken, 200)).marsLat, location.marsLat);
  const peerPin = {...location, marsLat: location.marsLat + .0001};
  await expectStatus(sessionPath, peerToken, 200, sendPin('ARES-02', peerPin));
  assert.equal((await expectStatus(signals, danToken, 200)).pins['ARES-02'].marsLat, peerPin.marsLat);
  await expectStatus(sessionPath, danToken, 200, sendPin('ARES-01', {...location, marsLat: -2.294}));
  assert.equal((await expectStatus(signals, peerToken, 200)).pins['ARES-01'].marsLat, -2.294);
  await expectStatus(sessionPath + '/presence/ARES-01', danToken, 200, write(tracked));

  const id = randomUUID().replaceAll('-', '');
  const open = {id, sender: 'ARES-01', ...location, state: 'active', started: serverTime};
  const ownPresence = sessionPath + '/presence/ARES-01';
  const savedPresence = await expectStatus(ownPresence, danToken, 200);
  const destination = {marsLon: -5.167, marsLat: -2.292};
  const nearbyMission = missionIds[(missionIds.indexOf(mission) + 1) % missionIds.length];
  const otherMissionPin = sessionAt(nearbyMission) + '/signals/pins/ARES-01';
  const priorOtherPin = await expectStatus(otherMissionPin, danToken, 200);
  await sse(signals, peerToken,
    () => expectStatus(pin, danToken, 200, write({...destination, updated: serverTime})),
    '"marsLon":-5.167');
  const received = await expectStatus(pin, peerToken, 200);
  assert.deepEqual(received, {...destination, updated: received.updated});
  assert.ok(Number.isInteger(received.updated));
  assert.deepEqual(await expectStatus(ownPresence, danToken, 200), savedPresence);
  assert.equal((await expectStatus(signals, danToken, 200)).pins['ARES-02'].marsLat, peerPin.marsLat);
  assert.deepEqual(await expectStatus(otherMissionPin, danToken, 200), priorOtherPin);

  await expectStatus(incident, peerToken, 401, write(open));
  await expectStatus(incident, danToken, 401, write({...open, marsLat: 50}));
  await sse(signals, peerToken,
    () => expectStatus(incident, danToken, 200, write(open)), id);
  const current = await expectStatus(incident, peerToken, 200);
  assert.equal(current.state, 'active');
  assert.equal(current.marsLat, location.marsLat);
  const peerOpen = {...open, id: randomUUID().replaceAll('-', ''), ...peerPin, sender: 'ARES-02'};
  await expectStatus(incident, peerToken, 401, write(peerOpen));

  const end = (state, finishedBy) => write({
    ...current, state, finishedBy, finished: serverTime,
  });
  await expectStatus(incident, peerToken, 401, end('canceled', 'ARES-02'));
  await expectStatus(incident, danToken, 401, end('resolved', 'ARES-01'));
  await expectStatus(sessionPath + '/presence/ARES-02', peerToken, 200, write(beforeRescue));
  await expectStatus(incident, peerToken, 401, end('resolved', 'ARES-02'));
  await expectStatus(sessionPath + '/presence/ARES-02', peerToken, 200, write({
    ...tracked, quality: 'waiting',
  }));
  await expectStatus(incident, peerToken, 401, end('resolved', 'ARES-02'));
  const tagged = await fetch(uri(incident, peerToken), {'headers': {'X-Firebase-ETag': 'true'}});
  await tagged.json();
  const etag = tagged.headers.get('etag');
  assert.ok(etag);
  await expectStatus(sessionPath + '/presence/ARES-02', peerToken, 200, write(tracked));
  const resolution = end('resolved', 'ARES-02');
  await expectStatus(incident, peerToken, 200, {...resolution, headers: {
    ...resolution.headers, 'if-match': etag,
  }});
  await expectStatus(incident, peerToken, 401, end('resolved', 'ARES-02'));
  await expectStatus(incident, danToken, 401, end('canceled', 'ARES-01'));
  assert.equal((await expectStatus(incident, danToken, 200)).finishedBy, 'ARES-02');
  await expectStatus(sessionPath + '/presence/ARES-01', danToken, 200, write(tracked));
  await expectStatus(incident, danToken, 401, write(open));
  const newId = randomUUID().replaceAll('-', '');
  await expectStatus(incident, danToken, 200, write({...open, id: newId}));
  const next = await expectStatus(incident, peerToken, 200);
  const cancel = write({...next, state: 'canceled', finished: serverTime, finishedBy: 'ARES-01'});
  await expectStatus(incident, danToken, 200, cancel);
  assert.equal((await expectStatus(incident, peerToken, 200)).state, 'canceled');
  const adjacent = missionIds[(missionIds.indexOf(mission) + 1) % missionIds.length];
  const neighbor = await expectStatus(sessionAt(adjacent) + '/signals', danToken, 200);
  assert.notEqual(neighbor?.sos?.id, newId);
}
console.log('Firebase emulator passed authorized PIN and SOS delivery, concurrent state guards, radius evidence, cancellation, and signal isolation across five missions.');

const refresh = await fetch(
  'http://127.0.0.1:9099/securetoken.googleapis.com/v1/token?key=demo',
  {
    method: 'POST',
    body: new URLSearchParams({
      grant_type: 'refresh_token', refresh_token: danPhone.refreshToken,
    }),
  },
);
assert.equal(refresh.status, 200, await refresh.clone().text());
const renewed = await refresh.json();
assert.equal(renewed.user_id, danPhone.localId);
await expectStatus(sessionAt('endeavour') + '/deviceMembers/ARES-01', renewed.id_token, 200);

// A password credential with a matching UID still cannot access the
// anonymous-device member record. It only retains its original legacy slot.
const gale = sessionAt('gale');
await expectStatus(gale + '/deviceMembers/ARES-02', 'owner', 200, write(dan.localId));
await expectStatus(gale + '/deviceMembers/ARES-02', dan.idToken, 401);
await expectStatus(gale + '/presence/ARES-02', dan.idToken, 401, write(pose));

// Revoking or replacing a device is mission-local. That UID can still read
// the other approved sessions while the replaced slot fails closed.
await expectStatus(gale + '/deviceMembers/ARES-01', 'owner', 200, write(sparePhone.localId));
await expectStatus(gale + '/presence', danPhone.idToken, 401);
await expectStatus(gale + '/presence/ARES-01', danPhone.idToken, 401, write(pose));
await expectStatus(gale + '/presence/ARES-01', sparePhone.idToken, 200, write(pose));
await expectStatus(sessionAt('endeavour') + '/presence', sparePhone.idToken, 401);
await expectStatus(sessionAt('endeavour') + '/presence', danPhone.idToken, 200);

const jezero = sessionAt('jezero');
await expectStatus(jezero + '/metadata/state', 'owner', 200, write('ended'));
await expectStatus(jezero + '/deviceMembers/ARES-01', danPhone.idToken, 401);
await expectStatus(jezero + '/presence', adrianPhone.idToken, 401);
await expectStatus(jezero + '/presence/ARES-01', danPhone.idToken, 401, write(pose));

console.log('Firebase emulator passed anonymous enrollment, both own-slot writes, streamed isolation across all five field-test-01 sessions, and device replacement.');
