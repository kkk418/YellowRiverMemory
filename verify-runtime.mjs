// Exercises the real non-UI .ets services with SQLite and controllable platform events.
// This is host verification; it does not emulate HarmonyOS transport or certify devices.
import assert from 'node:assert/strict';
import { readFileSync, mkdtempSync, readdirSync, unlinkSync, rmdirSync } from 'node:fs';
import { resolve, dirname, join } from 'node:path';
import { tmpdir } from 'node:os';
import { createRequire } from 'node:module';
import { runInNewContext } from 'node:vm';
import { DatabaseSync } from 'node:sqlite';

const require = createRequire(import.meta.url);
const ts = require(process.env.YRM_TYPESCRIPT_PATH ??
  'D:/hongmeng IDE/DevEco Studio/tools/ohpm/node_modules/typescript/lib/typescript.js');
const root = resolve('entry/src/main/ets');
const temporary = mkdtempSync(join(tmpdir(), 'yrm-service-check-'));
const worlds = [];
const diagnostics = [];

class Predicates {
  constructor(table) { this.table = table; this.parts = []; this.args = []; }
  equalTo(column, value) { this.parts.push(`${column}=?`); this.args.push(value); return this; }
  and() { return this; }
  get where() { return this.parts.join(' AND '); }
}

class SqlStore {
  constructor(path, transactional = false) {
    this.path = path;
    this.db = new DatabaseSync(path);
    this.db.exec('PRAGMA journal_mode=WAL');
    this.transactional = transactional;
    if (transactional) this.db.exec('BEGIN IMMEDIATE');
  }
  get version() { return this.db.prepare('PRAGMA user_version').get().user_version; }
  set version(value) { this.db.exec(`PRAGMA user_version=${Number(value)}`); }
  async executeSql(sql, args = []) { this.db.prepare(sql).run(...args); }
  async execute(sql, args) { return this.executeSql(sql, args); }
  async querySql(sql, args = []) {
    const statement = this.db.prepare(sql);
    const rows = statement.all(...args);
    const names = statement.columns().map(column => column.name);
    let index = -1;
    return {
      columnCount: names.length, getColumnName: n => names[n],
      goToNextRow: () => ++index < rows.length,
      getColumnType: n => {
        const value = rows[index][names[n]];
        return value === null ? 0 : typeof value === 'number' ? 2 : typeof value === 'string' ? 3 : 4;
      },
      getDouble: n => rows[index][names[n]], getString: n => rows[index][names[n]],
      getBlob: n => rows[index][names[n]], close() {},
    };
  }
  async insert(table, values) {
    const keys = Object.keys(values);
    const result = this.db.prepare(`INSERT INTO ${table}(${keys.join(',')}) VALUES(${keys.map(() => '?').join(',')})`)
      .run(...Object.values(values).map(value => typeof value === 'boolean' ? Number(value) : value));
    return Number(result.lastInsertRowid);
  }
  async update(...args) {
    const [values, predicates] = args;
    const result = this.db.prepare(`UPDATE ${predicates.table} SET ${Object.keys(values).map(key => `${key}=?`).join(',')} WHERE ${predicates.where}`)
      .run(...Object.values(values), ...predicates.args);
    return Number(result.changes);
  }
  async delete(predicates) {
    return Number(this.db.prepare(`DELETE FROM ${predicates.table} WHERE ${predicates.where}`).run(...predicates.args).changes);
  }
  async createTransaction() { return new SqlStore(this.path, true); }
  async commit() { this.db.exec('COMMIT'); this.db.close(); }
  async rollback() { this.db.exec('ROLLBACK'); this.db.close(); }
  close() { this.db.close(); }
}

class ControlledKv {
  values = new Map();
  callbacks = new Map();
  scans = 0;
  syncCalls = 0;
  failPut = false;
  async get(key) { if (!this.values.has(key)) throw new Error('missing'); return this.values.get(key); }
  async put(key, value) { if (this.failPut) throw new Error('offline'); this.values.set(key, value); }
  async getEntries(prefix) {
    this.scans++;
    return [...this.values].filter(([key]) => key.startsWith(prefix))
      .map(([key, value]) => ({ key, value: { value } }));
  }
  on(name, ...args) { this.callbacks.set(name, args.at(-1)); }
  sync() { this.syncCalls++; }
}

async function world(device, seed) {
  const store = new SqlStore(join(temporary, `${worlds.length}.db`));
  if (seed) seed(store.db);
  const kv = new ControlledKv();
  const cache = new Map();
  const timers = new Map();
  let serial = 0;
  let time = 1_800_000_000_000;
  let lastSync = 0;
  let dataVersion = 0;
  const peerIds = [];
  const alerts = [];
  const prefs = {
    getLocalDeviceId: async () => device, setLocalDeviceId: async () => {},
    getLastSyncTime: async () => lastSync, setLastSyncTime: async value => { lastSync = value; },
    getDataVersion: async () => dataVersion, setDataVersion: async value => { dataVersion = value; },
    getContext: () => ({}),
  };
  const manager = {
    getLocalDeviceNetworkId: () => `net-${device}`,
    getAvailableDeviceListSync: () => peerIds.map(id => ({ networkId: `net-${id}`, deviceName: id })),
  };
  class ClockDate extends Date { static now() { return time; } }
  const kits = {
    '@kit.ArkData': { relationalStore: { SecurityLevel: { S1: 1 }, RdbPredicates: Predicates,
      getRdbStore: async () => store }, distributedKVStore: { SubscribeType: { SUBSCRIBE_TYPE_REMOTE: 1 },
      SyncMode: { PUSH_PULL: 2 } } },
    '@kit.ArkTS': { util: { TextDecoder: { create: () => ({ decodeToString: bytes => new TextDecoder().decode(bytes) }) } } },
    '@kit.AbilityKit': {}, '@kit.LocalizationKit': {}, '@kit.DistributedServiceKit': {},
    '@kit.NetworkKit': { connection: { hasDefaultNet: async () => true } },
    '@kit.BasicServicesKit': { deviceInfo: { deviceType: 'phone' } },
  };
  function load(path) {
    if (cache.has(path)) return cache.get(path).exports;
    if (path.endsWith('/PreferencesHelper.ets')) return { PreferencesHelper: prefs };
    if (path.endsWith('/Logger.ets')) return { Logger: Object.fromEntries(['info', 'warn', 'debug', 'error']
      .map(level => [level, (...args) => diagnostics.push({ level, args })])) };
    const module = { exports: {} };
    cache.set(path, module);
    let source = readFileSync(path, 'utf8');
    if (path.endsWith('/NoteEditorPage.ets')) {
      // Execute the editor's actual state/lifecycle methods; ArkUI rendering stays device-only.
      source = source.slice(0, source.indexOf('  @Builder BackButton')) + '\n}';
      source = source.replace('@Component', '').replace('export struct ', 'export class ')
        .replace(/@Consume\('[^']+'\)\s*/g, '').replace(/@State\s*/g, '');
    }
    const code = ts.transpileModule(source, {
      compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2022 }, fileName: path + '.ts',
    }).outputText;
    const localRequire = name => {
      if (name.startsWith('@kit.')) {
        assert.ok(kits[name], `No mock for ${name}`);
        return kits[name];
      }
      return load(resolve(dirname(path), name + '.ets').replaceAll('\\', '/'));
    };
    runInNewContext(code, { module, exports: module.exports, require: localRequire,
      Date: ClockDate, Uint8Array, TextDecoder, console, $r: name => name,
      AlertDialog: { show: options => alerts.push(options) },
      setTimeout: (callback, delay) => { const id = ++serial; timers.set(id, { callback, delay }); return id; },
      clearTimeout: id => timers.delete(id),
    }, { filename: path });
    return module.exports;
  }
  const get = name => load(resolve(root, name + '.ets').replaceAll('\\', '/'));
  const db = get('database/LocalRdbHelper').LocalRdbHelper;
  await db.init({});
  const dds = get('service/DistributedDataService').DistributedDataService.getInstance();
  dds.state.localDeviceId = device;
  dds.state.permissionGranted = true;
  dds.kvStore = kv;
  dds.deviceManager = manager;
  dds.initialized = true;
  dds.subscribeRemoteChanges();
  const user = get('service/UserDataService').UserDataService.getInstance();
  const drafts = get('service/NoteDraftService').NoteDraftService;
  const result = { store, kv, db, dds, user, drafts, get, peerIds, timers, alerts,
    advance: value => { time += value; },
    fire: async delay => {
      const match = [...timers].find(([, timer]) => timer.delay === delay);
      assert.ok(match, `Missing timer ${delay}`);
      timers.delete(match[0]);
      await match[1].callback();
      await drain();
    },
  };
  worlds.push(result);
  return result;
}

async function drain() { for (let i = 0; i < 20; i++) await new Promise(resolve => setImmediate(resolve)); }
function draft(id, noteId = null, content = '本机未保存输入') {
  return { id, noteId, title: '研学草稿', content, targetType: 'standalone', targetId: null,
    tags: '[]', baseUpdatedAt: 0, baseDeviceId: '', savedAt: Date.now() };
}
function ack(version) { return JSON.stringify({ t: version.t, d: version.d, winnerT: version.t, winnerD: version.d }); }

try {
  const a = await world('A');
  const asset = a.get('database/AssetRepository').AssetRepository;
  await asset.initIfNeeded({ getRawFileContent: async () => Uint8Array.from(readFileSync('entry/src/main/resources/rawfile/data/preset.json')) });
  assert.equal(await a.db.count('site'), 10);
  assert.equal(await a.db.count('artifact'), 30);
  assert.equal(a.store.version, 4);

  // An unrelated query sees committed data while a transaction is suspended.
  let release;
  let entered;
  const inside = new Promise(resolve => { entered = resolve; });
  const pause = new Promise(resolve => { release = resolve; });
  const transaction = a.db.runInTransaction(async db => {
    await db.execute("INSERT INTO note_draft(id,targetType,savedAt) VALUES('isolation','standalone',1)");
    entered(); await pause; throw new Error('rollback');
  });
  await inside;
  assert.equal(await a.db.count('note_draft'), 0);
  release(); await assert.rejects(transaction, /rollback/);
  assert.equal(await a.db.count('note_draft'), 0);
  console.log('PASS fresh preset, transaction isolation and rollback');

  let favoritesChanged = 0;
  const { EventBus, AppEvents } = a.get('common/utils/EventBus');
  EventBus.getInstance().on(AppEvents.FAVORITE_CHANGED, () => favoritesChanged++);
  const ids = await Promise.all(Array.from({ length: 12 }, () => a.user.addFavorite('site', 'site_longmen')));
  assert.equal(new Set(ids).size, 1);
  assert.equal(favoritesChanged, 1);
  assert.equal(await a.db.count('favorite'), 1);
  await a.user.removeFavorite('site', 'site_longmen');
  assert.equal(favoritesChanged, 2);
  assert.equal((await a.db.query('SELECT isDeleted FROM favorite'))[0].isDeleted, 1);
  await a.drafts.save(draft('local'));
  const noteId = await a.user.addNote('研学', '正文', 'standalone', undefined, [], 'local');
  assert.equal(await a.drafts.get('local'), null);
  const original = await a.user.getNoteById(noteId);
  await a.drafts.save(draft('edit', noteId));
  await a.db.execute('UPDATE note SET updatedAt=?,deviceId=? WHERE id=?', [original.updatedAt + 1, 'B', noteId]);
  await assert.rejects(a.user.updateNote(noteId, '本机输入', '保留正文', [], original.updatedAt, original.deviceId, 'edit'), /其他设备/);
  assert.equal((await a.drafts.get('edit')).content, '本机未保存输入');
  const copyId = await a.user.addNote('另存', '本机未保存输入', 'standalone', undefined, [], 'edit');
  const copy = await a.user.getNoteById(copyId);
  await a.user.updateNote(copyId, '更新', '更新正文', [], copy.updatedAt, copy.deviceId);
  const updated = await a.user.getNoteById(copyId);
  await a.user.deleteNote(copyId, updated.updatedAt, updated.deviceId);
  assert.equal((await a.user.getNoteById(copyId)).isDeleted, 1);
  const topicId = await a.user.createTopic('测试主题');
  await a.user.addTopicRelation(topicId, 'site', 'site_longmen');
  await a.user.deleteTopic(topicId);
  assert.equal((await a.db.query('SELECT isDeleted FROM topic WHERE id=?', [topicId]))[0].isDeleted, 1);
  assert.equal((await a.db.query('SELECT isDeleted FROM topic_relation WHERE topicId=?', [topicId]))[0].isDeleted, 1);
  await drain();
  console.log('PASS duplicate favorite, single refresh, note CRUD, draft conflict preservation, topic tombstones');

  const editorWorld = await world('editor');
  const Editor = editorWorld.get('view/note/NoteEditorPage').NoteEditorPage;
  const LeaveGuard = editorWorld.get('common/utils/NoteLeaveGuard').NoteLeaveGuard;
  let popped = 0;
  const editor = new Editor();
  editor.navPathStack = { pop: () => popped++ };
  editor.aboutToAppear(); await editorWorld.fire(30);
  editor.title = '未完笔记'; editor.content = '重启后保留'; editor.markDirty();
  await editorWorld.fire(350);
  assert.equal(LeaveGuard.onBackPressed(), true);
  assert.equal(editorWorld.alerts.length, 1);
  editorWorld.alerts[0].primaryButton.action(); await drain();
  assert.equal(popped, 1);
  editor.aboutToDisappear(); await drain();
  const recovered = new Editor();
  recovered.params = { draftId: editor.draftId };
  recovered.navPathStack = { pop: () => popped++ };
  recovered.aboutToAppear(); await editorWorld.fire(30);
  assert.equal(recovered.content, '重启后保留');
  await recovered.doSave();
  assert.equal(await editorWorld.drafts.get(editor.draftId), null);
  recovered.aboutToDisappear();
  const saved = (await editorWorld.user.listNotes())[0];
  const edit = new Editor();
  edit.params = { noteId: saved.id }; edit.navPathStack = { pop: () => popped++ };
  edit.aboutToAppear(); await editorWorld.fire(30);
  edit.content = '用户当前输入'; edit.markDirty(); await editorWorld.fire(350);
  await editorWorld.db.execute('UPDATE note SET updatedAt=?,deviceId=? WHERE id=?', [saved.updatedAt + 1, 'remote', saved.id]);
  await edit.doSave();
  assert.equal(edit.canSaveAsNew, true);
  assert.equal(edit.content, '用户当前输入');
  edit.aboutToDisappear(); await drain();
  const conflictRestored = new Editor();
  conflictRestored.params = { noteId: saved.id, draftId: edit.draftId };
  conflictRestored.navPathStack = { pop: () => popped++ };
  conflictRestored.aboutToAppear(); await editorWorld.fire(30);
  assert.equal(conflictRestored.canSaveAsNew, true);
  assert.equal(conflictRestored.content, '用户当前输入');
  await conflictRestored.saveAsNew();
  assert.equal((await editorWorld.user.listNotes()).length, 2);
  assert.equal(await editorWorld.drafts.get(edit.draftId), null);
  console.log('PASS editor lifecycle autosave, leave guard, restoration, atomic save and conflict save-as-new (host methods)');

  const schema = readFileSync(join(root, 'database/LocalRdbHelper.ets'), 'utf8');
  const ddls = [...schema.match(/const CREATE_TABLE_SQL: string\[\] = \[([\s\S]*?)\n\];/)[1].matchAll(/`([^`]+)`/g)].map(match => match[1]);
  for (const version of [1, 2, 3]) {
    const migrated = await world(`upgrade-${version}`, sql => {
      for (let ddl of ddls) {
        if (ddl.includes('note_draft') || (version === 1 && /CREATE TABLE IF NOT EXISTS (history_record|sync_)/.test(ddl))) continue;
        if (version === 1) ddl = ddl.replace(/,\s*isNationalTreasure INTEGER DEFAULT 0/, '')
          .replace(/,\s*createdAt INTEGER\s*\);/, '\n);')
          .replace(/,\s*isDeleted INTEGER DEFAULT 0/, ddl.includes('topic_relation') ? '' : ', isDeleted INTEGER DEFAULT 0');
        sql.exec(ddl);
      }
      sql.exec(`PRAGMA user_version=${version}`);
      sql.exec("INSERT INTO favorite(id,targetType,targetId,createdAt,updatedAt,isDeleted) VALUES('older','site','site_longmen',1,2,0),('newer','site','site_longmen',1,3,1)");
      // v2/v3 already have the unique target constraint from their migration.
      if (version > 1) sql.exec("DELETE FROM favorite WHERE id='older'");
      sql.exec("INSERT INTO note(id,title,content,targetType,createdAt,updatedAt,isDeleted) VALUES('kept','研学','用户正文','standalone',1,2,0)");
      sql.exec("INSERT INTO topic(id,name,createdAt,updatedAt,isDeleted) VALUES('kept-topic','黄河',1,2,0)");
      sql.exec("INSERT INTO topic_relation(id,topicId,targetType,targetId,createdAt,updatedAt) VALUES('kept-relation','kept-topic','site','site_longmen',1,2)");
    });
    assert.equal(migrated.store.version, 4);
    assert.equal((await migrated.user.getNoteById('kept')).content, '用户正文');
    assert.equal(await migrated.db.count('topic'), 1);
    assert.equal(await migrated.db.count('topic_relation'), 1);
    const favorites = await migrated.db.query('SELECT * FROM favorite');
    assert.equal(favorites.length, 1);
    assert.equal(favorites[0].updatedAt, 3);
    assert.equal(favorites[0].isDeleted, 1);
    if (version === 1) assert.equal(favorites[0].id, 'favorite_site_site_longmen');
    await migrated.drafts.save(draft('after-upgrade'));
  }
  console.log('PASS real migration functions v1/v2/v3 -> v4 preserve representative user rows');

  const sender = await world('sender');
  const receiver = await world('receiver');
  sender.peerIds.push('receiver'); receiver.peerIds.push('sender');
  const id = await sender.user.addNote('同步', '离线创建', 'standalone');
  await drain();
  const key = `note/${id}`;
  const first = JSON.parse(await sender.kv.get(key));
  await sender.dds.requestSync();
  assert.equal(sender.dds.awaitingAck, true);
  const oldTimeout = sender.timers.get(sender.dds.syncTimeout).callback;
  await sender.fire(15000);
  assert.equal(await sender.db.count('sync_outbox'), 1);
  await sender.dds.handleSyncComplete([['net-receiver', 0]]);
  assert.equal(await sender.db.count('sync_outbox'), 1);
  await sender.fire(2000); // The retained row retries automatically after timeout.
  oldTimeout();
  assert.equal(sender.dds.awaitingAck, true, 'Old timer must not stop the new round');
  const old = await sender.user.getNoteById(id);
  await sender.user.updateNote(id, '同步', '更新版本', [], old.updatedAt, old.deviceId);
  await drain();
  sender.kv.values.set(`ack/sender/net-receiver/${key}`, ack(first));
  await sender.dds.handleSyncComplete([['net-receiver', 0]]);
  assert.equal(await sender.db.count('sync_outbox'), 1, 'Old ACK must retain a newer edit');
  const latest = JSON.parse(await sender.kv.get(key));
  await receiver.dds.applyRemoteEntry(key, JSON.stringify(latest));
  assert.equal((await receiver.user.getNoteById(id)).content, '更新版本');
  const ackKey = `ack/sender/net-receiver/${key}`;
  sender.kv.values.set(ackKey, await receiver.kv.get(ackKey));
  await sender.dds.handleSyncComplete([['net-receiver', 0]]);
  assert.equal(await sender.db.count('sync_outbox'), 0);
  assert.equal(sender.dds.getState().lastSyncChanged, 1);
  const scans = sender.kv.scans;
  await sender.dds.requestSync();
  assert.equal(sender.kv.scans, scans, 'Ordinary round must not scan all entities');
  assert.equal(sender.dds.getState().lastSyncChanged, 0);
  await sender.dds.setOnline();
  assert.equal(sender.kv.scans, scans, 'Foreground on an unchanged network must keep outbox-only mode');
  await receiver.dds.applyRemoteEntry(key, JSON.stringify(latest));
  assert.equal(receiver.dds.actualChanges.size, 0, 'Unchanged apply must not count as a change');
  console.log('PASS timeout retention, late callback/timer, exact ACK, unique change count and outbox-only round');

  const beforeDelete = await sender.user.getNoteById(id);
  await sender.user.deleteNote(id, beforeDelete.updatedAt, beforeDelete.deviceId);
  await drain();
  await receiver.dds.applyRemoteEntry(key, await sender.kv.get(key));
  assert.equal((await receiver.user.getNoteById(id)).isDeleted, 1);
  const base = await receiver.user.addNote('冲突', 'base', 'standalone');
  await drain();
  const baseKey = `note/${base}`;
  await sender.dds.applyRemoteEntry(baseKey, await receiver.kv.get(baseKey));
  const common = await sender.user.getNoteById(base);
  await sender.user.updateNote(base, '冲突', 'sender edit', [], common.updatedAt, common.deviceId);
  await receiver.user.updateNote(base, '冲突', 'receiver edit', [], common.updatedAt, common.deviceId);
  await drain();
  const left = await sender.kv.get(baseKey), right = await receiver.kv.get(baseKey);
  await sender.dds.applyRemoteEntry(baseKey, right);
  await receiver.dds.applyRemoteEntry(baseKey, left);
  assert.equal((await sender.user.getNoteById(base)).content, (await receiver.user.getNoteById(base)).content);
  assert.equal((await sender.user.getNoteById(base)).content, 'sender edit');
  assert.ok((await sender.dds.listConflicts()).length > 0);
  assert.ok((await receiver.dds.listConflicts()).length > 0);
  console.log('PASS soft-delete propagation, equal-time deterministic conflict convergence and retained conflict rows');

  const recovery = await world('recovery');
  recovery.peerIds.push('peer-one', 'peer-two');
  recovery.kv.failPut = true;
  const retryId = await recovery.user.addNote('断网', '待发送', 'standalone');
  await drain();
  assert.equal(await recovery.db.count('sync_outbox'), 1);
  recovery.kv.failPut = false;
  await recovery.dds.setOnline();
  const retryKey = `note/${retryId}`;
  const retryVersion = JSON.parse(await recovery.kv.get(retryKey));
  await recovery.fire(15000);
  recovery.kv.values.set(`ack/recovery/net-peer-one/${retryKey}`, ack(retryVersion));
  await recovery.dds.handleSyncComplete([['net-peer-one', 0]]);
  assert.equal(await recovery.db.count('sync_outbox'), 1, 'Every targeted peer must confirm');
  recovery.kv.values.set(`ack/recovery/net-peer-two/${retryKey}`, ack(retryVersion));
  await recovery.dds.handleSyncComplete([['net-peer-two', 0]]);
  assert.equal(await recovery.db.count('sync_outbox'), 0);
  assert.equal(recovery.dds.getState().status, recovery.get('common/constants/Enums').SyncStatus.IDLE);
  const invalid = { id: 'invalid', updatedAt: retryVersion.t + 1, deviceId: 'recovery', isDeleted: 0 };
  await assert.rejects(receiver.dds.applyRemoteEntry('note/invalid', JSON.stringify({ v: JSON.stringify(invalid),
    t: invalid.updatedAt, d: 'recovery', s: 1 })), /NOT NULL/);
  assert.equal(receiver.kv.values.has('ack/recovery/net-receiver/note/invalid'), false);
  assert.equal(await receiver.user.getNoteById('invalid'), null);
  console.log('PASS failed KV publish retention, network recovery, every-peer ACK, late ACK status recovery and commit-before-ACK');

  await sender.drafts.save(draft('restart'));
  const pendingBeforeRestart = await sender.db.count('sync_outbox');
  const reopened = new SqlStore(sender.store.path);
  assert.equal(reopened.db.prepare("SELECT content FROM note_draft WHERE id='restart'").get().content, '本机未保存输入');
  assert.equal(reopened.db.prepare('SELECT COUNT(*) AS c FROM sync_outbox').get().c, pendingBeforeRestart);
  reopened.close();
  console.log('PASS reopened SQLite retains draft and outbox; device process restart remains a separate check');
} catch (error) {
  console.error('Recent service diagnostics:', diagnostics.slice(-8));
  throw error;
} finally {
  for (const current of worlds) current.store.close();
  for (const file of readdirSync(temporary)) unlinkSync(join(temporary, file));
  rmdirSync(temporary);
}
