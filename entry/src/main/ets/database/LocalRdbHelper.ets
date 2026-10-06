/**
 * 本地RDB辅助类
 * 负责：建表、CRUD封装、预置数据导入入口
 * RDB 保存本地实体、迁移、同步队列与冲突日志；跨设备传输由分布式 KV 服务负责。
 */
import { relationalStore } from '@kit.ArkData';
import { Context } from '@kit.AbilityKit';
import { Logger } from '../common/utils/Logger';
import { AppConstants } from '../common/constants/AppMeta';

const TAG = 'LocalRdbHelper';

interface CountRow {
  c: number;
}

interface ColumnInfo {
  name: string;
}

/**
 * 所有建表DDL（与04-数据库设计.md保持一致）
 */
const CREATE_TABLE_SQL: string[] = [
  `CREATE TABLE IF NOT EXISTS site (
    id TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    nameEn TEXT,
    era TEXT NOT NULL,
    type TEXT NOT NULL,
    city TEXT NOT NULL,
    yearStart INTEGER,
    yearEnd INTEGER,
    latitude REAL,
    longitude REAL,
    coverImage TEXT,
    summary TEXT,
    overview TEXT,
    archaeology TEXT,
    historicalEvents TEXT,
    travelInfo TEXT,
    highlight TEXT,
    artifactCount INTEGER DEFAULT 0,
    viewCount INTEGER DEFAULT 0,
    isFeatured INTEGER DEFAULT 0,
    createdAt INTEGER,
    updatedAt INTEGER
  );`,
  `CREATE TABLE IF NOT EXISTS artifact (
    id TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    nameEn TEXT,
    era TEXT NOT NULL,
    type TEXT NOT NULL,
    siteId TEXT,
    city TEXT,
    coverImage TEXT,
    description TEXT,
    material TEXT,
    size TEXT,
    location TEXT,
    level TEXT,
    viewCount INTEGER DEFAULT 0,
    isFeatured INTEGER DEFAULT 0,
    isNationalTreasure INTEGER DEFAULT 0,
    createdAt INTEGER,
    updatedAt INTEGER
  );`,
  `CREATE TABLE IF NOT EXISTS poetry (
    id TEXT PRIMARY KEY,
    title TEXT NOT NULL,
    author TEXT,
    dynasty TEXT,
    content TEXT NOT NULL,
    translation TEXT,
    relatedSiteId TEXT,
    relatedCity TEXT,
    createdAt INTEGER
  );`,
  `CREATE TABLE IF NOT EXISTS favorite (
    id TEXT PRIMARY KEY,
    targetType TEXT NOT NULL,
    targetId TEXT NOT NULL,
    tags TEXT,
    remark TEXT,
    createdAt INTEGER,
    updatedAt INTEGER,
    isDeleted INTEGER DEFAULT 0,
    deviceId TEXT
  );`,
  `CREATE TABLE IF NOT EXISTS note (
    id TEXT PRIMARY KEY,
    title TEXT,
    content TEXT,
    targetType TEXT NOT NULL,
    targetId TEXT,
    tags TEXT,
    images TEXT,
    createdAt INTEGER,
    updatedAt INTEGER,
    isDeleted INTEGER DEFAULT 0,
    deviceId TEXT
  );`,
  `CREATE TABLE IF NOT EXISTS note_draft (
    id TEXT PRIMARY KEY,
    noteId TEXT,
    title TEXT,
    content TEXT,
    targetType TEXT NOT NULL,
    targetId TEXT,
    tags TEXT,
    baseUpdatedAt INTEGER DEFAULT 0,
    baseDeviceId TEXT,
    savedAt INTEGER NOT NULL
  );`,
  `CREATE TABLE IF NOT EXISTS topic (
    id TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    description TEXT,
    coverColor TEXT,
    iconEmoji TEXT,
    createdAt INTEGER,
    updatedAt INTEGER,
    isDeleted INTEGER DEFAULT 0,
    deviceId TEXT
  );`,
  `CREATE TABLE IF NOT EXISTS topic_relation (
    id TEXT PRIMARY KEY,
    topicId TEXT NOT NULL,
    targetType TEXT NOT NULL,
    targetId TEXT NOT NULL,
    note TEXT,
    orderIndex INTEGER DEFAULT 0,
    createdAt INTEGER,
    updatedAt INTEGER,
    isDeleted INTEGER DEFAULT 0,
    deviceId TEXT
  );`,
  // Legacy history remains readable for v1-to-v2 migration; new visits use history_record.
  `CREATE TABLE IF NOT EXISTS browse_history (
    id TEXT PRIMARY KEY,
    targetType TEXT NOT NULL,
    targetId TEXT NOT NULL,
    viewedAt INTEGER,
    duration INTEGER DEFAULT 0
  );`,
  `CREATE TABLE IF NOT EXISTS history_record (
    id TEXT PRIMARY KEY,
    targetType TEXT NOT NULL,
    targetId TEXT NOT NULL,
    lastViewedAt INTEGER,
    viewCount INTEGER DEFAULT 0,
    createdAt INTEGER,
    updatedAt INTEGER,
    deviceId TEXT
  );`,
  `CREATE TABLE IF NOT EXISTS sync_outbox (
    id TEXT PRIMARY KEY,
    entityType TEXT NOT NULL,
    entityId TEXT NOT NULL,
    entryJson TEXT NOT NULL,
    updatedAt INTEGER NOT NULL
  );`,
  `CREATE TABLE IF NOT EXISTS sync_local_version (
    id TEXT PRIMARY KEY,
    entryJson TEXT NOT NULL
  );`,
  `CREATE TABLE IF NOT EXISTS sync_conflict (
    id TEXT PRIMARY KEY,
    entityType TEXT NOT NULL,
    entityId TEXT NOT NULL,
    localData TEXT,
    remoteData TEXT,
    localDeviceId TEXT,
    remoteDeviceId TEXT,
    localTimestamp INTEGER,
    remoteTimestamp INTEGER,
    resolvedAt INTEGER,
    resolution TEXT,
    createdAt INTEGER
  );`,
];

/** 索引 */
const CREATE_INDEX_SQL: string[] = [
  `CREATE INDEX IF NOT EXISTS idx_site_era ON site(era);`,
  `CREATE INDEX IF NOT EXISTS idx_site_city ON site(city);`,
  `CREATE INDEX IF NOT EXISTS idx_site_type ON site(type);`,
  `CREATE INDEX IF NOT EXISTS idx_site_featured ON site(isFeatured);`,
  `CREATE INDEX IF NOT EXISTS idx_artifact_site ON artifact(siteId);`,
  `CREATE INDEX IF NOT EXISTS idx_artifact_era ON artifact(era);`,
  `CREATE INDEX IF NOT EXISTS idx_favorite_target ON favorite(targetType, targetId, isDeleted);`,
  `CREATE INDEX IF NOT EXISTS idx_note_target ON note(targetType, targetId, isDeleted);`,
  `CREATE INDEX IF NOT EXISTS idx_topic_relation_topic ON topic_relation(topicId);`,
  `CREATE INDEX IF NOT EXISTS idx_browse_history_time ON browse_history(viewedAt DESC);`,
  `CREATE INDEX IF NOT EXISTS idx_history_record_time ON history_record(lastViewedAt DESC);`,
  `CREATE UNIQUE INDEX IF NOT EXISTS idx_favorite_target_unique ON favorite(targetType, targetId);`,
];

const TOPIC_RELATION_UNIQUE_INDEX =
  `CREATE UNIQUE INDEX IF NOT EXISTS idx_topic_relation_identity ON topic_relation(topicId, targetType, targetId);`;

/** Explicit executor: unrelated async work cannot join another caller's transaction. */
export class RdbSession {
  private store: relationalStore.RdbStore;
  private tx?: relationalStore.Transaction;

  constructor(store: relationalStore.RdbStore, tx?: relationalStore.Transaction) {
    this.store = store;
    this.tx = tx;
  }

  async query<T>(sql: string, bindArgs?: relationalStore.ValueType[]): Promise<T[]> {
    const resultSet = this.tx ? await this.tx.querySql(sql, bindArgs) : await this.store.querySql(sql, bindArgs);
    const list: T[] = [];
    try {
      const names: string[] = [];
      for (let i = 0; i < resultSet.columnCount; i++) names.push(resultSet.getColumnName(i));
      while (resultSet.goToNextRow()) {
        const row: Record<string, relationalStore.ValueType | Uint8Array | null> = {};
        for (let i = 0; i < names.length; i++) {
          switch (await resultSet.getColumnType(i)) {
            case 0: row[names[i]] = null; break;
            case 1:
            case 2: row[names[i]] = resultSet.getDouble(i); break;
            case 4: row[names[i]] = resultSet.getBlob(i); break;
            default: row[names[i]] = resultSet.getString(i);
          }
        }
        list.push(row as Object as T);
      }
    } finally { resultSet.close(); }
    return list;
  }

  async execute(sql: string, bindArgs?: relationalStore.ValueType[]): Promise<void> {
    if (this.tx) await this.tx.execute(sql, bindArgs);
    else await this.store.executeSql(sql, bindArgs);
  }

  async insert(table: string, values: relationalStore.ValuesBucket): Promise<number> {
    return this.tx ? this.tx.insert(table, values) : this.store.insert(table, values);
  }

  async update(table: string, values: relationalStore.ValuesBucket,
    predicates: relationalStore.RdbPredicates): Promise<number> {
    return this.tx ? this.tx.update(values, predicates) : this.store.update(values, predicates);
  }

  async delete(table: string, predicates: relationalStore.RdbPredicates): Promise<number> {
    return this.tx ? this.tx.delete(predicates) : this.store.delete(predicates);
  }
}

export class LocalRdbHelper {
  private static rdbStore: relationalStore.RdbStore | null = null;
  private static transactionQueue: Promise<void> = Promise.resolve();

  static async init(context: Context): Promise<void> {
    if (LocalRdbHelper.rdbStore) return;
    const config: relationalStore.StoreConfig = {
      name: AppConstants.DB_NAME,
      securityLevel: relationalStore.SecurityLevel.S1,
    };
    try {
      LocalRdbHelper.rdbStore = await relationalStore.getRdbStore(context, config);
      await LocalRdbHelper.createTables();
      Logger.info(TAG, 'RDB init success');
    } catch (e) {
      // A failed migration must not leave an apparently initialized store in memory.
      // The next initialization attempt should retry the unfinished schema work.
      LocalRdbHelper.rdbStore = null;
      Logger.error(TAG, `RDB init failed: ${e}`);
      throw new Error(String(e));
    }
  }

  static getStore(): relationalStore.RdbStore {
    if (!LocalRdbHelper.rdbStore) {
      throw new Error('RDB not initialized, call init(context) first');
    }
    return LocalRdbHelper.rdbStore;
  }

  private static async createTables(): Promise<void> {
    const store = LocalRdbHelper.getStore();
    // 版本管理：旧库走显式迁移，不能只依赖 CREATE TABLE IF NOT EXISTS。
    if (store.version === 0) {
      for (const sql of CREATE_TABLE_SQL) {
        await store.executeSql(sql);
      }
      for (const sql of CREATE_INDEX_SQL) {
        await store.executeSql(sql);
      }
      await store.executeSql(TOPIC_RELATION_UNIQUE_INDEX);
      store.version = AppConstants.DB_VERSION;
      Logger.info(TAG, `Tables created, version=${AppConstants.DB_VERSION}`);
    } else {
      if (store.version < 2) {
        await LocalRdbHelper.migrateV1ToV2();
        store.version = 2;
        Logger.info(TAG, 'Database migrated from v1 to v2');
      }
      // Repair partial development installs that already claimed schema v2.
      for (const sql of CREATE_TABLE_SQL) await store.executeSql(sql);
      await LocalRdbHelper.ensureColumn('artifact', 'isNationalTreasure', 'INTEGER DEFAULT 0');
      await LocalRdbHelper.ensureColumn('poetry', 'createdAt', 'INTEGER');
      await LocalRdbHelper.ensureColumn('topic_relation', 'isDeleted', 'INTEGER DEFAULT 0');
      if (store.version < 3) {
        await LocalRdbHelper.migrateV2ToV3();
        store.version = 3;
      }
      if (store.version < 4) {
        // The additive DDL above created the local-only draft table without touching user rows.
        store.version = 4;
      }
      for (const sql of CREATE_INDEX_SQL) await store.executeSql(sql);
      await store.executeSql(TOPIC_RELATION_UNIQUE_INDEX);
    }
  }

  private static async migrateV2ToV3(): Promise<void> {
    await LocalRdbHelper.runInTransaction(async (db: RdbSession) => {
      for (const table of ['favorite', 'note', 'topic', 'topic_relation']) {
        await db.execute(
          `UPDATE ${table} SET updatedAt=COALESCE(updatedAt, createdAt, 0) WHERE updatedAt IS NULL`);
      }
      const relations = await db.query<Record<string, Object>>(
        'SELECT id, topicId, targetType, targetId FROM topic_relation ORDER BY COALESCE(updatedAt, createdAt, 0) DESC, createdAt DESC, id DESC');
      const seen = new Set<string>();
      for (const relation of relations) {
        const key = `${String(relation.topicId)}:${String(relation.targetType)}:${String(relation.targetId)}`;
        if (seen.has(key)) {
          const id = String(relation.id);
          await db.execute('DELETE FROM topic_relation WHERE id=?', [id]);
          await db.execute('DELETE FROM sync_outbox WHERE entityType=? AND entityId=?',
            ['topic_relation', id]);
          await db.execute('DELETE FROM sync_local_version WHERE id=?', [`topic_relation/${id}`]);
        } else {
          seen.add(key);
        }
      }
      await db.execute(TOPIC_RELATION_UNIQUE_INDEX);
    });
    Logger.info(TAG, 'Database migrated from v2 to v3');
  }

  private static async migrateV1ToV2(): Promise<void> {
    await LocalRdbHelper.runInTransaction(async (db: RdbSession) => {
      await LocalRdbHelper.ensureColumn('artifact', 'isNationalTreasure', 'INTEGER DEFAULT 0', db);
      await LocalRdbHelper.ensureColumn('poetry', 'createdAt', 'INTEGER', db);
      await LocalRdbHelper.ensureColumn('topic_relation', 'isDeleted', 'INTEGER DEFAULT 0', db);
      await db.execute(`CREATE TABLE IF NOT EXISTS history_record (
        id TEXT PRIMARY KEY, targetType TEXT NOT NULL, targetId TEXT NOT NULL,
        lastViewedAt INTEGER, viewCount INTEGER DEFAULT 0, createdAt INTEGER,
        updatedAt INTEGER, deviceId TEXT)`);
      await db.execute(`INSERT OR IGNORE INTO history_record
        (id, targetType, targetId, lastViewedAt, viewCount, createdAt, updatedAt, deviceId)
        SELECT 'history_' || targetType || '_' || targetId, targetType, targetId,
          MAX(viewedAt), COUNT(*), MIN(viewedAt), MAX(viewedAt), ''
        FROM browse_history GROUP BY targetType, targetId`);
      await db.execute(`CREATE TABLE IF NOT EXISTS sync_outbox (
        id TEXT PRIMARY KEY, entityType TEXT NOT NULL, entityId TEXT NOT NULL,
        entryJson TEXT NOT NULL, updatedAt INTEGER NOT NULL)`);
      await db.execute(`CREATE TABLE IF NOT EXISTS sync_local_version (
        id TEXT PRIMARY KEY, entryJson TEXT NOT NULL)`);
      await db.execute(`CREATE TABLE IF NOT EXISTS sync_conflict (
        id TEXT PRIMARY KEY, entityType TEXT NOT NULL, entityId TEXT NOT NULL,
        localData TEXT, remoteData TEXT, localDeviceId TEXT, remoteDeviceId TEXT,
        localTimestamp INTEGER, remoteTimestamp INTEGER, resolvedAt INTEGER,
        resolution TEXT, createdAt INTEGER)`);

      // Keep the newest record for each target. The unique constraint then
      // guarantees that local devices share the same one-favorite-per-target rule.
      const favorites = await db.query<Record<string, Object>>(
        'SELECT * FROM favorite ORDER BY COALESCE(updatedAt, createdAt, 0) DESC, createdAt DESC, id DESC', []);
      const seen = new Set<string>();
      const retained: Record<string, Object>[] = [];
      for (const favorite of favorites) {
        const key = `${String(favorite.targetType)}:${String(favorite.targetId)}`;
        if (seen.has(key)) {
          await db.execute('DELETE FROM favorite WHERE id=?', [favorite.id as string]);
        } else {
          seen.add(key);
          retained.push(favorite);
        }
      }
      for (const favorite of retained) {
        const canonicalId = LocalRdbHelper.favoriteId(String(favorite.targetType), String(favorite.targetId));
        if (favorite.id !== canonicalId) {
          await db.execute('UPDATE favorite SET id=? WHERE id=?', [canonicalId, favorite.id as string]);
        }
      }
      for (const sql of CREATE_INDEX_SQL) await db.execute(sql);
    });
  }

  private static async ensureColumn(table: string, column: string, definition: string,
    db: RdbSession = LocalRdbHelper.session()): Promise<void> {
    const columns = await db.query<ColumnInfo>(`PRAGMA table_info(${table})`, []);
    if (!columns.some(item => item.name === column)) {
      await db.execute(`ALTER TABLE ${table} ADD COLUMN ${column} ${definition}`);
    }
  }

  static favoriteId(targetType: string, targetId: string): string {
    return `favorite_${targetType}_${targetId}`;
  }

  static topicRelationId(topicId: string, targetType: string, targetId: string): string {
    return `topic_relation_${topicId}_${targetType}_${targetId}`;
  }

  static session(): RdbSession {
    return new RdbSession(LocalRdbHelper.getStore());
  }

  static async query<T>(sql: string, bindArgs?: relationalStore.ValueType[]): Promise<T[]> {
    return LocalRdbHelper.session().query<T>(sql, bindArgs);
  }

  static async execute(sql: string, bindArgs?: relationalStore.ValueType[]): Promise<void> {
    return LocalRdbHelper.session().execute(sql, bindArgs);
  }

  static async insert(table: string, values: relationalStore.ValuesBucket): Promise<number> {
    return LocalRdbHelper.session().insert(table, values);
  }

  static async update(table: string, values: relationalStore.ValuesBucket,
    predicates: relationalStore.RdbPredicates): Promise<number> {
    return LocalRdbHelper.session().update(table, values, predicates);
  }

  static async delete(table: string, predicates: relationalStore.RdbPredicates): Promise<number> {
    return LocalRdbHelper.session().delete(table, predicates);
  }

  static async count(table: string, where?: string, bindArgs?: relationalStore.ValueType[]): Promise<number> {
    const sql = where ? `SELECT COUNT(*) as c FROM ${table} WHERE ${where}` : `SELECT COUNT(*) as c FROM ${table}`;
    const rows = await LocalRdbHelper.query<CountRow>(sql, bindArgs);
    return rows.length > 0 ? rows[0].c : 0;
  }

  /** 在事务中执行一批操作 */
  static async runInTransaction<T>(operation: (db: RdbSession) => Promise<T>): Promise<T> {
    const store = LocalRdbHelper.getStore();
    const previous = LocalRdbHelper.transactionQueue;
    let release: () => void = () => {};
    LocalRdbHelper.transactionQueue = new Promise<void>((resolve: () => void) => { release = resolve; });
    await previous;
    try {
      const tx = await store.createTransaction();
      try {
        const result = await operation(new RdbSession(store, tx));
        await tx.commit();
        return result;
      } catch (e) {
        await tx.rollback();
        throw new Error(String(e));
      }
    } finally {
      release();
    }
  }
}
