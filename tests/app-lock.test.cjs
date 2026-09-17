const { test } = require('node:test');
const assert = require('node:assert/strict');
const { AppLockService } = require('../dist-electron/services/AppLockService.js');

function setup() {
  let password = null;
  return {
    service: new AppLockService({
      getPassword: async () => password,
      savePassword: async value => { password = value; },
    }),
  };
}

test('application lock requires configuration and keeps explicit lock state', async () => {
  const { service } = setup();
  assert.deepEqual(await service.status(), { configured: false, locked: false });
  assert.equal(await service.lock(), false);
  await service.setPassword(undefined, 'strong-password');
  assert.deepEqual(await service.status(), { configured: true, locked: false });
  assert.equal(await service.lock(), true);
  assert.deepEqual(await service.status(), { configured: true, locked: true });
  assert.equal(await service.unlock('wrong-password'), false);
  assert.equal(await service.unlock('strong-password'), true);
  assert.deepEqual(await service.status(), { configured: true, locked: false });
});

test('changing application password requires the current password', async () => {
  const { service } = setup();
  await service.setPassword(undefined, 'first-password');
  await assert.rejects(service.setPassword('wrong-password', 'next-password'), /incorrect/);
  await service.setPassword('first-password', 'next-password');
  await service.lock();
  assert.equal(await service.unlock('first-password'), false);
  assert.equal(await service.unlock('next-password'), true);
});
