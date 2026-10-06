import { readFileSync, existsSync } from 'node:fs';
import { join } from 'node:path';
import { DatabaseSync } from 'node:sqlite';

const raw = 'entry/src/main/resources/rawfile';
const preset = JSON.parse(readFileSync(join(raw, 'data/preset.json'), 'utf8'));
const manifest = JSON.parse(readFileSync(join(raw, 'data/cover_manifest.json'), 'utf8'));
const items = [...preset.sites, ...preset.artifacts];
if (preset.sites.length !== 10 || preset.artifacts.length !== 30 || manifest.entries.length !== 40) {
  throw new Error('Preset or cover audit count changed');
}
for (const item of items) {
  const audit = manifest.entries.find(entry => entry.id === item.id);
  if (!audit || audit.bundledPath !== item.coverImage) throw new Error(`Cover audit differs: ${item.id}`);
  if (!item.coverImage) continue;
  if (!existsSync(join(raw, item.coverImage))) throw new Error(`Missing image: ${item.coverImage}`);
  if (!manifest.licenses.some(license => license.id === item.id && license.path === item.coverImage)) {
    throw new Error(`No license: ${item.id}`);
  }
}

const source = readFileSync('entry/src/main/ets/database/LocalRdbHelper.ets', 'utf8');
const tableBlock = source.match(/const CREATE_TABLE_SQL: string\[\] = \[([\s\S]*?)\n\];/);
const indexBlock = source.match(/const CREATE_INDEX_SQL: string\[\] = \[([\s\S]*?)\n\];/);
if (!tableBlock || !indexBlock) throw new Error('Schema DDL not found');
const tables = [...tableBlock[1].matchAll(/`([^`]+)`/g)].map(match => match[1]);
const indices = [...indexBlock[1].matchAll(/`([^`]+)`/g)].map(match => match[1]);
const relationIndex = source.match(/const TOPIC_RELATION_UNIQUE_INDEX\s*=\s*`([^`]+)`/);
if (!relationIndex) throw new Error('Topic relation index not found');

function applySchema(db, includeDraft, withIndices = true) {
  for (const ddl of tables) {
    if (!includeDraft && ddl.includes('CREATE TABLE IF NOT EXISTS note_draft')) continue;
    db.exec(ddl);
  }
  if (withIndices) {
    for (const ddl of indices) db.exec(ddl);
    db.exec(relationIndex[1]);
  }
}

const fresh = new DatabaseSync(':memory:');
applySchema(fresh, true);
const insertSite = fresh.prepare('INSERT INTO site(id,name,era,type,city,coverImage) VALUES(?,?,?,?,?,?)');
const insertArtifact = fresh.prepare('INSERT INTO artifact(id,name,era,type,siteId,coverImage) VALUES(?,?,?,?,?,?)');
for (const site of preset.sites) {
  insertSite.run(site.id, site.name, site.era, site.type, site.city, site.coverImage);
}
for (const artifact of preset.artifacts) {
  insertArtifact.run(artifact.id, artifact.name, artifact.era, artifact.type, artifact.siteId, artifact.coverImage);
}
if (fresh.prepare('SELECT COUNT(*) AS count FROM site').get().count !== 10 ||
  fresh.prepare('SELECT COUNT(*) AS count FROM artifact').get().count !== 30) {
  throw new Error('Fresh preset shape failed');
}
fresh.close();

// Check DDL can be opened over representative v1/v2/v3 shaped stores.
for (const version of [1, 2, 3]) {
  const db = new DatabaseSync(':memory:');
  for (const ddl of tables) {
    if (ddl.includes('CREATE TABLE IF NOT EXISTS note_draft')) continue;
    if (version === 1 && /CREATE TABLE IF NOT EXISTS (history_record|sync_outbox|sync_local_version|sync_conflict)/.test(ddl)) continue;
    let oldDdl = ddl;
    if (version === 1) {
      if (ddl.includes('CREATE TABLE IF NOT EXISTS artifact')) {
        oldDdl = oldDdl.replace(/,\s*isNationalTreasure INTEGER DEFAULT 0/, '');
      }
      if (ddl.includes('CREATE TABLE IF NOT EXISTS poetry')) {
        oldDdl = oldDdl.replace(/,\s*createdAt INTEGER\s*\);/, '\n  );');
      }
      if (ddl.includes('CREATE TABLE IF NOT EXISTS topic_relation')) {
        oldDdl = oldDdl.replace(/,\s*isDeleted INTEGER DEFAULT 0/, '');
      }
    }
    db.exec(oldDdl);
  }
  db.exec("INSERT INTO favorite(id,targetType,targetId,createdAt,updatedAt,isDeleted) VALUES('fav','site','site_longmen',1,2,0)");
  db.exec("INSERT INTO note(id,title,content,targetType,createdAt,updatedAt,isDeleted) VALUES('note','研学','原文','standalone',1,2,0)");
  db.exec("INSERT INTO topic(id,name,createdAt,updatedAt,isDeleted) VALUES('topic','黄河',1,2,0)");
  db.exec("INSERT INTO topic_relation(id,topicId,targetType,targetId,createdAt,updatedAt) VALUES('rel','topic','site','site_longmen',1,2)");
  if (version === 1) {
    // These are the additive column repairs performed before CREATE TABLE IF NOT EXISTS.
    db.exec('ALTER TABLE artifact ADD COLUMN isNationalTreasure INTEGER DEFAULT 0');
    db.exec('ALTER TABLE poetry ADD COLUMN createdAt INTEGER');
    db.exec('ALTER TABLE topic_relation ADD COLUMN isDeleted INTEGER DEFAULT 0');
  }
  applySchema(db, true);
  db.exec("INSERT INTO note_draft(id,noteId,title,content,targetType,tags,baseUpdatedAt,baseDeviceId,savedAt) VALUES('draft','note','未完','本机输入','standalone','[]',2,'device',3)");
  for (const table of ['favorite', 'note', 'topic', 'topic_relation', 'note_draft']) {
    if (db.prepare(`SELECT COUNT(*) AS count FROM ${table}`).get().count !== 1) {
      throw new Error(`User row lost in v${version} schema rehearsal: ${table}`);
    }
  }
  db.close();
}
console.log(`Cover audit: ${items.filter(item => item.coverImage).length} licensed, ${items.filter(item => !item.coverImage).length} placeholders`);
console.log('SQLite DDL: first schema and v1/v2/v3 shaped store opening passed; representative user rows retained');
