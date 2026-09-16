const { test } = require('node:test');
const assert = require('node:assert/strict');
const { mkdtempSync, readFileSync, statSync, writeFileSync } = require('node:fs');
const { tmpdir } = require('node:os');
const { join } = require('node:path');
const { KnownHostsStore } = require('../dist-electron/services/ssh/KnownHostsStore.js');
const { FreeRdpAdapter } = require('../dist-electron/services/rdp/RdpService.js');
const { redact } = require('../dist-electron/utils/logger.js');
const { transferFileSchema } = require('../dist-electron/contracts/files.js');

test('known SSH fingerprints persist in an owner-only file', async () => {
  const directory = mkdtempSync(join(tmpdir(), 'morixterm-known-hosts-'));
  const filename = join(directory, 'known-hosts.json');
  const store = new KnownHostsStore(filename);
  assert.equal(await store.lookup('example.test:22'), undefined);
  await store.remember('example.test:22', 'SHA256:YWJj');
  assert.equal(await store.lookup('example.test:22'), 'SHA256:YWJj');
  const saved = JSON.parse(readFileSync(filename, 'utf8'));
  assert.equal(saved.hosts.length, 1);
  if (process.platform !== 'win32') assert.equal(statSync(filename).mode & 0o777, 0o600);
});

test('corrupt trusted-host data fails closed', async () => {
  const directory = mkdtempSync(join(tmpdir(), 'morixterm-known-hosts-'));
  const filename = join(directory, 'known-hosts.json');
  writeFileSync(filename, '{not-json');
  await assert.rejects(new KnownHostsStore(filename).lookup('example.test:22'), /invalid or unreadable/);
});

test('logs redact named secrets and legacy RDP password arguments', () => {
  assert.equal(redact('password=hunter2'), 'password=[REDACTED]');
  assert.equal(redact('xfreerdp /p:hunter2 /v:host'), 'xfreerdp /p:[REDACTED] /v:host');
});

test('FreeRDP receives passwords through stdin instead of process arguments', () => {
  const args = new FreeRdpAdapter().buildArgs('/usr/bin/xfreerdp', {
    id: 'test', host: 'server.test', port: 3389, username: 'user', password: 'never-in-argv',
  });
  assert.equal(args.includes('/from-stdin'), true);
  assert.equal(args.some(value => value.includes('never-in-argv')), false);
  assert.equal(args.some(value => value.startsWith('/p:')), false);
});

test('remote paths reject null bytes and extra IPC properties', () => {
  assert.equal(transferFileSchema.safeParse({ id: 'session', remotePath: '/tmp/file' }).success, true);
  assert.equal(transferFileSchema.safeParse({ id: 'session', remotePath: '/tmp/\0file' }).success, false);
  assert.equal(transferFileSchema.safeParse({ id: 'session', remotePath: '/tmp/file', localPath: '/etc/passwd' }).success, false);
});
