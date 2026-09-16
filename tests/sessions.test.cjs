const { test } = require('node:test');
const assert = require('node:assert/strict');
const { mkdtempSync, readFileSync } = require('node:fs');
const { tmpdir } = require('node:os');
const { join } = require('node:path');
const { DatabaseSync } = require('node:sqlite');
const { SessionRepository } = require('../dist-electron/services/SessionRepository.js');
const { SessionService } = require('../dist-electron/services/SessionService.js');

function setup(t) {
  const filename = join(mkdtempSync(join(tmpdir(), 'morixterm-sqlite-test-')), 'sessions.sqlite');
  const repository = new SessionRepository(filename);
  const secrets = new Map();
  const vault = { getPassword: async id => secrets.get(id) ?? null,
    savePassword: async (id, password) => { secrets.set(id, password); },
    deletePassword: async id => { secrets.delete(id); } };
  t.after(() => repository.close());
  return { filename, repository, secrets, vault, service: new SessionService(repository, vault) };
}
const draft = overrides => ({ name: 'test session', host: '127.0.0.1', port: 22, user: 'test', kind: 'SSH', color: '#38d9c3', group: '', ...overrides });
const edit = (session, changes) => { const { hasPassword, ...value } = session; return { ...value, ...changes }; };

test('fresh database has no seed data and is a real SQLite file', t => {
  const { filename, repository } = setup(t);
  assert.equal(repository.list({}).total, 0);
  assert.equal(readFileSync(filename).subarray(0,16).toString(), 'SQLite format 3\0');
});

test('SSH, RDP and local sessions persist after reopening, including edits', async t => {
  const { filename, service } = setup(t);
  const ssh = await service.save(draft());
  assert.match(ssh.createdAt, /^\d{4}-\d{2}-\d{2}T/);
  assert.match(ssh.updatedAt, /^\d{4}-\d{2}-\d{2}T/);
  assert.ok(Date.parse(ssh.updatedAt) >= Date.parse(ssh.createdAt));
  const rdp = await service.save(draft({kind:'RDP',port:3389}));
  const local = await service.save(draft({kind:'LOCAL',port:undefined,host:'localhost'}));
  await service.save(edit(ssh,{name:'renamed',port:2200}));
  const reopened = new SessionRepository(filename);
  try {
    assert.equal(reopened.list({}).total,3);
    assert.equal(reopened.get(ssh.id).name,'renamed');
    assert.equal(reopened.get(ssh.id).port,2200);
    assert.equal(reopened.get(rdp.id).port,3389);
    assert.equal(reopened.get(local.id).port,undefined);
  } finally { reopened.close(); }
});

test('same-name sessions have separate IDs, edits and credentials', async t => {
  const { repository, service, secrets, filename } = setup(t);
  const first = await service.save(draft({password:'secret-one'}));
  const second = await service.save(draft({password:'secret-two'}));
  await service.save(edit(first,{name:'renamed',password:''}));
  assert.equal(repository.get(second.id).name,'test session');
  assert.equal(secrets.get(first.id),'secret-one');
  assert.equal(secrets.get(second.id),'secret-two');
  assert.equal('password' in repository.get(first.id),false);
  const db = new DatabaseSync(filename);
  try { assert.equal(db.prepare('PRAGMA table_info(sessions)').all().some(row=>row.name==='password'),false); }
  finally { db.close(); }
  await service.save(edit(first,{kind:'LOCAL',port:undefined,host:'localhost'}));
  assert.equal(repository.get(first.id).hasPassword,false);
  assert.equal(secrets.has(first.id),false);
});

test('invalid saves and missing updates cannot add rows', async t => {
  const { service, repository } = setup(t);
  for (const override of [{port:0},{port:65536},{port:2.5},{name:'  '},{host:''},{extra:'field'}, {id:'00000000-0000-4000-8000-000000000000'}]) {
    await assert.rejects(service.save(draft(override)));
  }
  assert.equal(repository.list({}).total,0);
});

test('credential-store failure does not save metadata', async t => {
  const { repository, vault } = setup(t);
  vault.savePassword = async () => { throw new Error('locked'); };
  const service = new SessionService(repository,vault);
  await assert.rejects(service.save(draft({password:'never-stored'})));
  assert.equal(repository.list({}).total,0);
});

test('failed database save restores the prior secret', async t => {
  const { repository, service, secrets } = setup(t);
  const session = await service.save(draft({password:'original'}));
  repository.save = () => { throw new Error('disk full'); };
  await assert.rejects(service.save(edit(session,{password:'replacement'})));
  assert.equal(secrets.get(session.id),'original');
});

test('filtering and pagination are bounded and parameters are literal', async t => {
  const { repository, service } = setup(t);
  for (let index=0;index<12;index++) await service.save(draft({name:`host ${index}`,favorite:index%2===0}));
  await service.save(draft({name:"%' OR 1=1 --"}));
  assert.equal(repository.list({pageSize:5}).items.length,5);
  assert.equal(repository.list({page:3,pageSize:5}).items.length,3);
  assert.equal(repository.list({query:"%' OR 1=1 --"}).total,1);
  assert.equal(repository.list({favoritesOnly:true}).total,6);
  assert.equal(repository.list({query:'no matches',page:30}).page,1);
  assert.throws(()=>repository.list({pageSize:10000}));
});

test('delete removes metadata and credential', async t => {
  const { repository, service, secrets } = setup(t);
  const session = await service.save(draft({password:'to-remove'}));
  assert.equal(secrets.get(session.id),'to-remove');
  assert.equal(await service.delete(session.id), true);
  assert.equal(repository.get(session.id), undefined);
  assert.equal(secrets.has(session.id), false);
  assert.equal(await service.delete(session.id), false);
});

test('duplicate creates independent metadata and copies the vault secret', async t => {
  const { repository, service, secrets } = setup(t);
  const source = await service.save(draft({ password: 'copy-me', favorite: true }));
  const copy = await service.duplicate(source.id);
  assert.notEqual(copy.id, source.id);
  assert.equal(copy.name, 'test session (copy)');
  assert.equal(copy.favorite, false);
  assert.equal(copy.hasPassword, true);
  assert.equal(secrets.get(copy.id), 'copy-me');
  assert.equal(repository.list({}).total, 2);
});

test('moving a session by changing its group keeps the saved credential', async t => {
  const { service, secrets } = setup(t);
  const source = await service.save(draft({ password: 'keep-me', group: 'Production' }));
  const { hasPassword, ...editable } = source;
  const moved = await service.save({ ...editable, group: 'Production/Web Servers' });
  assert.equal(moved.group, 'Production/Web Servers');
  assert.equal(moved.hasPassword, true);
  assert.equal(secrets.get(source.id), 'keep-me');
});

test('folder CRUD preserves nested paths and updates grouped sessions', async t => {
  const { service, repository } = setup(t);
  const source = await service.save(draft({ group: 'Production/Web Servers' }));
  const folder = repository.createFolder('Production/Web Servers');
  assert.equal(folder.path, 'Production/Web Servers');
  assert.deepEqual(repository.listFolders().map(item => item.path), ['Production', 'Production/Web Servers']);
  repository.renameFolder('Production', 'Live');
  assert.equal(repository.get(source.id).group, 'Live/Web Servers');
  repository.deleteFolder('Live');
  assert.equal(repository.get(source.id).group, '');
  assert.equal(repository.listFolders().length, 0);
});
