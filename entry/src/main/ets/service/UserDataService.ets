/**
 * 用户数据服务：收藏/笔记/主题/浏览历史的CRUD
 * 核心 CRUD 与持久化同步队列入口
 */
import { relationalStore, preferences } from '@kit.ArkData';
import { LocalRdbHelper, RdbSession } from '../database/LocalRdbHelper';
import { Favorite, Note, Topic, TopicRelation, HistoryRecord } from '../model/entity/Entities';
import { FavoriteTargetType, NoteTargetType } from '../common/constants/Enums';
import { TagMeta } from '../common/constants/AppMeta';
import { DateUtil } from '../common/utils/DateUtil';
import { StringUtil } from '../common/utils/StringUtil';
import { PreferencesHelper } from '../common/utils/PreferencesHelper';
import { EventBus, AppEvents } from '../common/utils/EventBus';
import { Logger } from '../common/utils/Logger';

const TAG = 'UserDataService';

interface TagCount {
  tag: string;
  count: number;
}

interface IdRow {
  id: string;
}

interface CountRow {
  c: number;
}

interface NoteVersionRow {
  updatedAt: number;
  deviceId: string;
  isDeleted: number;
}

export class UserDataService {
  private static instance: UserDataService;
  private localDeviceId: string = '';
  // 内存缓存：key = "type:id"，快速判断收藏状态
  private favCache: Set<string> = new Set();
  private cacheLoaded: boolean = false;
  private favoriteQueues: Map<string, Promise<void>> = new Map();
  private lastWriteTime: number = 0;

  private nextWriteTime(previous: number = 0): number {
    const timestamp = Math.max(DateUtil.now(), previous + 1, this.lastWriteTime + 1);
    this.lastWriteTime = timestamp;
    return timestamp;
  }

  static getInstance(): UserDataService {
    if (!UserDataService.instance) UserDataService.instance = new UserDataService();
    return UserDataService.instance;
  }

  async ensureReady(): Promise<string> {
    if (!this.localDeviceId) {
      this.localDeviceId = await PreferencesHelper.getLocalDeviceId();
      if (!this.localDeviceId) {
        this.localDeviceId = `dev_${DateUtil.uuid()}`;
        await PreferencesHelper.setLocalDeviceId(this.localDeviceId);
      }
    }
    if (!this.cacheLoaded) await this.reloadFavCache();
    return this.localDeviceId;
  }

  async reloadFavCache(): Promise<void> {
    try {
      const list = await LocalRdbHelper.query<Favorite>(
        `SELECT targetType, targetId FROM favorite WHERE isDeleted=0`, []
      );
      this.favCache.clear();
      for (const f of list) this.favCache.add(`${f.targetType}:${f.targetId}`);
      this.cacheLoaded = true;
    } catch (e) {
      Logger.warn(TAG, `reloadFavCache failed: ${e}`);
    }
  }

  /** 同步判断是否已收藏（基于内存缓存） */
  isFavoritedSync(targetType: FavoriteTargetType, targetId: string): boolean {
    return this.favCache.has(`${targetType}:${targetId}`);
  }

  /** 切换收藏状态 */
  async toggleFavorite(targetType: FavoriteTargetType, targetId: string, tags: string[] = []): Promise<boolean> {
    return this.serializeFavorite(`${targetType}:${targetId}`, async (): Promise<boolean> => {
      await this.ensureReady();
      if (this.isFavoritedSync(targetType, targetId)) {
        await this.removeFavoriteUnlocked(targetType, targetId);
        return false;
      }
      await this.addFavoriteUnlocked(targetType, targetId, tags);
      return true;
    });
  }

  private async serializeFavorite<T>(key: string, action: () => Promise<T>): Promise<T> {
    const previous = this.favoriteQueues.get(key) ?? Promise.resolve();
    let release: () => void = () => {};
    const gate = new Promise<void>((resolve) => { release = resolve; });
    const queued = previous.then(() => gate, () => gate);
    this.favoriteQueues.set(key, queued);
    await previous.catch(() => {});
    try { return await action(); }
    finally {
      release();
      if (this.favoriteQueues.get(key) === queued) this.favoriteQueues.delete(key);
    }
  }

  // ================== 收藏 ==================
  async addFavorite(targetType: FavoriteTargetType, targetId: string, tags: string[] = []): Promise<string> {
    return this.serializeFavorite(`${targetType}:${targetId}`,
      () => this.addFavoriteUnlocked(targetType, targetId, tags));
  }

  private async addFavoriteUnlocked(targetType: FavoriteTargetType, targetId: string,
    tags: string[]): Promise<string> {
    await this.ensureReady();
    const previous = await LocalRdbHelper.query<Favorite>(
      'SELECT id, updatedAt, deviceId, isDeleted FROM favorite WHERE targetType=? AND targetId=? LIMIT 1',
      [targetType, targetId]);
    if (previous.length > 0 && previous[0].isDeleted === 0) return previous[0].id;
    let id = LocalRdbHelper.favoriteId(targetType, targetId);
    await this.commitChange('favorite', `${targetType}:${targetId}`, async (db: RdbSession) => {
      id = await this.getOrCreateFavoriteId(targetType, targetId, tags, db);
    }, previous[0]?.updatedAt, previous[0]?.deviceId);
    this.favCache.add(`${targetType}:${targetId}`);
    EventBus.getInstance().emit(AppEvents.FAVORITE_CHANGED, { targetType, targetId, favorited: true });
    return id;
  }

  private async getOrCreateFavoriteId(targetType: FavoriteTargetType, targetId: string,
    tags: string[], db: RdbSession): Promise<string> {
    const rows = await db.query<Favorite>(
      'SELECT * FROM favorite WHERE targetType=? AND targetId=? LIMIT 1', [targetType, targetId]);
    if (rows.length > 0) {
      const id = rows[0].id;
      const now = this.nextWriteTime(rows[0].updatedAt);
      const pred = new relationalStore.RdbPredicates('favorite');
      pred.equalTo('id', id);
      await db.update('favorite', {
        'tags': StringUtil.toTagsArray(tags), 'isDeleted': 0,
        'updatedAt': now, 'deviceId': this.localDeviceId,
      }, pred);
      return id;
    }
    const id = LocalRdbHelper.favoriteId(targetType, targetId);
    const now = this.nextWriteTime();
    const inserted = await db.insert('favorite', {
      'id': id, 'targetType': targetType, 'targetId': targetId,
      'tags': StringUtil.toTagsArray(tags), 'remark': null,
      'createdAt': now, 'updatedAt': now, 'isDeleted': 0, 'deviceId': this.localDeviceId,
    });
    Logger.info(TAG, `favorite insert rowId=${inserted} id=${id}`);
    return id;
  }

  async removeFavorite(targetType: FavoriteTargetType, targetId: string): Promise<void> {
    return this.serializeFavorite(`${targetType}:${targetId}`,
      () => this.removeFavoriteUnlocked(targetType, targetId));
  }

  private async removeFavoriteUnlocked(targetType: FavoriteTargetType, targetId: string): Promise<void> {
    await this.ensureReady();
    const rows = await LocalRdbHelper.query<Favorite>(
      'SELECT id, updatedAt, deviceId FROM favorite WHERE targetType=? AND targetId=? AND isDeleted=0 LIMIT 1',
      [targetType, targetId]);
    if (rows.length === 0) return;
    const now = this.nextWriteTime(rows[0]?.updatedAt ?? 0);
    const pred = new relationalStore.RdbPredicates('favorite');
    pred.equalTo('targetType', targetType).and().equalTo('targetId', targetId).and().equalTo('isDeleted', 0);
    await this.commitChange('favorite', `${targetType}:${targetId}`, async (db: RdbSession) => {
      await db.update('favorite', { 'isDeleted': 1, 'updatedAt': now, 'deviceId': this.localDeviceId }, pred);
    }, rows[0].updatedAt, rows[0].deviceId);
    this.favCache.delete(`${targetType}:${targetId}`);
    EventBus.getInstance().emit(AppEvents.FAVORITE_CHANGED, { targetType, targetId, favorited: false });
  }

  async isFavorited(targetType: FavoriteTargetType, targetId: string): Promise<boolean> {
    const list = await LocalRdbHelper.query<Favorite>(
      `SELECT id FROM favorite WHERE targetType=? AND targetId=? AND isDeleted=0 LIMIT 1`,
      [targetType, targetId]
    );
    return list.length > 0;
  }

  async listFavorites(targetType?: FavoriteTargetType, tag?: string): Promise<Favorite[]> {
    let sql = `SELECT * FROM favorite WHERE isDeleted=0`;
    const args: relationalStore.ValueType[] = [];
    if (targetType) { sql += ` AND targetType=?`; args.push(targetType); }
    sql += ` ORDER BY updatedAt DESC`;
    const favs = await LocalRdbHelper.query<Favorite>(sql, args);
    if (tag) {
      return favs.filter(f => StringUtil.parseTagsArray(f.tags).includes(tag));
    }
    return favs;
  }

  async getAllTags(): Promise<TagCount[]> {
    const favs = await this.listFavorites();
    const counter = new Map<string, number>();
    for (const t of TagMeta.ALL) counter.set(t.label, 0);
    for (const f of favs) {
      for (const t of StringUtil.parseTagsArray(f.tags)) {
        counter.set(t, (counter.get(t) || 0) + 1);
      }
    }
    return Array.from(counter.entries()).map((pair: [string, number]): TagCount => ({ tag: pair[0], count: pair[1] }))
      .sort((a, b) => b.count - a.count);
  }

  // ================== 笔记 ==================
  async addNote(title: string, content: string, targetType: NoteTargetType, targetId?: string,
    tags: string[] = [], draftId?: string): Promise<string> {
    await this.ensureReady();
    const id = DateUtil.uuid();
    const now = this.nextWriteTime();
    await this.commitChange('note', id, async (db: RdbSession) => {
      await db.insert('note', {
        'id': id, 'title': title, 'content': content,
        'targetType': targetType, 'targetId': targetId ?? null,
        'tags': StringUtil.toTagsArray(tags),
        'images': null,
        'createdAt': now, 'updatedAt': now,
        'isDeleted': 0, 'deviceId': this.localDeviceId,
      });
      if (draftId) await db.execute('DELETE FROM note_draft WHERE id=?', [draftId]);
    });
    EventBus.getInstance().emit(AppEvents.NOTE_CHANGED, { id });
    if (draftId) EventBus.getInstance().emit(AppEvents.NOTE_DRAFT_CHANGED, { id: draftId });
    return id;
  }

  async updateNote(id: string, title: string, content: string, tags: string[],
    expectedUpdatedAt?: number, expectedDeviceId?: string, draftId?: string): Promise<void> {
    await this.ensureReady();
    const existing = await LocalRdbHelper.query<NoteVersionRow>(
      'SELECT updatedAt, deviceId, isDeleted FROM note WHERE id=? LIMIT 1', [id]);
    if (existing.length === 0) throw new Error(`Note not found: ${id}`);
    const baseTime = expectedUpdatedAt ?? existing[0].updatedAt;
    const baseDevice = expectedDeviceId ?? existing[0].deviceId;
    const pred = new relationalStore.RdbPredicates('note');
    pred.equalTo('id', id);
    await this.commitChange('note', id, async (db: RdbSession) => {
      await this.assertCurrentNoteVersion(id, baseTime, baseDevice, db);
      await db.update('note', {
        'title': title, 'content': content,
        'tags': StringUtil.toTagsArray(tags),
        'updatedAt': this.nextWriteTime(baseTime),
        'deviceId': this.localDeviceId,
      }, pred);
      if (draftId) await db.execute('DELETE FROM note_draft WHERE id=?', [draftId]);
    }, baseTime, baseDevice);
    EventBus.getInstance().emit(AppEvents.NOTE_CHANGED, { id });
    if (draftId) EventBus.getInstance().emit(AppEvents.NOTE_DRAFT_CHANGED, { id: draftId });
  }

  async deleteNote(id: string, expectedUpdatedAt?: number, expectedDeviceId?: string, draftId?: string): Promise<void> {
    await this.ensureReady();
    const existing = await LocalRdbHelper.query<NoteVersionRow>(
      'SELECT updatedAt, deviceId, isDeleted FROM note WHERE id=? LIMIT 1', [id]);
    if (existing.length === 0 || existing[0].isDeleted === 1) return;
    const baseTime = expectedUpdatedAt ?? existing[0].updatedAt;
    const baseDevice = expectedDeviceId ?? existing[0].deviceId;
    const pred = new relationalStore.RdbPredicates('note');
    pred.equalTo('id', id);
    await this.commitChange('note', id, async (db: RdbSession) => {
      await this.assertCurrentNoteVersion(id, baseTime, baseDevice, db);
      await db.update('note', {
        'isDeleted': 1, 'updatedAt': this.nextWriteTime(baseTime), 'deviceId': this.localDeviceId,
      }, pred);
      if (draftId) await db.execute('DELETE FROM note_draft WHERE id=?', [draftId]);
    }, baseTime, baseDevice);
    EventBus.getInstance().emit(AppEvents.NOTE_CHANGED, { id, deleted: true });
    if (draftId) EventBus.getInstance().emit(AppEvents.NOTE_DRAFT_CHANGED, { id: draftId });
  }

  private async assertCurrentNoteVersion(id: string, updatedAt: number, deviceId: string, db: RdbSession): Promise<void> {
    const current = await db.query<NoteVersionRow>(
      'SELECT updatedAt, deviceId, isDeleted FROM note WHERE id=? LIMIT 1', [id]);
    if (current.length === 0 || current[0].isDeleted === 1 ||
      current[0].updatedAt !== updatedAt || (current[0].deviceId ?? '') !== (deviceId ?? '')) {
      throw new Error('笔记已在其他设备修改或删除，请重新打开后再保存');
    }
  }

  async listNotes(targetType?: NoteTargetType, targetId?: string): Promise<Note[]> {
    let sql = `SELECT * FROM note WHERE isDeleted=0`;
    const args: relationalStore.ValueType[] = [];
    if (targetType) { sql += ` AND targetType=?`; args.push(targetType); }
    if (targetId) { sql += ` AND targetId=?`; args.push(targetId); }
    sql += ` ORDER BY updatedAt DESC`;
    return LocalRdbHelper.query<Note>(sql, args);
  }

  async getNoteById(id: string): Promise<Note | null> {
    const list = await LocalRdbHelper.query<Note>(`SELECT * FROM note WHERE id=? LIMIT 1`, [id]);
    return list[0] ?? null;
  }

  // ================== 主题（知识库节点）==================
  async createTopic(name: string, description?: string, coverColor?: string, iconEmoji?: string): Promise<string> {
    await this.ensureReady();
    const id = DateUtil.uuid();
    const now = this.nextWriteTime();
    await this.commitChange('topic', id, async (db: RdbSession) => {
      await db.insert('topic', {
        'id': id, 'name': name, 'description': description ?? null,
        'coverColor': coverColor ?? null, 'iconEmoji': iconEmoji ?? null,
        'createdAt': now, 'updatedAt': now, 'isDeleted': 0, 'deviceId': this.localDeviceId,
      });
    });
    EventBus.getInstance().emit(AppEvents.TOPIC_CHANGED, { id });
    return id;
  }

  async deleteTopic(id: string): Promise<void> {
    await this.ensureReady();
    const distributedModule = await import('./DistributedDataService');
    let changed = false;
    await distributedModule.DistributedDataService.getInstance().commitLocalBatch(async (record, db: RdbSession) => {
      const topics = await db.query<Topic>(
        'SELECT id, updatedAt, deviceId, isDeleted FROM topic WHERE id=? LIMIT 1', [id]);
      if (topics.length === 0) return;
      const topic = topics[0];
      // Query before tombstoning the topic: listTopicRelations intentionally hides deleted topics.
      const relations = await db.query<TopicRelation>(
        'SELECT id, updatedAt, deviceId FROM topic_relation WHERE topicId=? AND isDeleted=0', [id]);
      if (topic.isDeleted === 0) {
        const topicPred = new relationalStore.RdbPredicates('topic');
        topicPred.equalTo('id', id);
        await db.update('topic', {
          'isDeleted': 1, 'updatedAt': this.nextWriteTime(topic.updatedAt), 'deviceId': this.localDeviceId,
        }, topicPred);
        await record('topic', id, topic.updatedAt, topic.deviceId);
        changed = true;
      }
      for (const relation of relations) {
        const relationPred = new relationalStore.RdbPredicates('topic_relation');
        relationPred.equalTo('id', relation.id);
        await db.update('topic_relation', {
          'isDeleted': 1, 'updatedAt': this.nextWriteTime(relation.updatedAt), 'deviceId': this.localDeviceId,
        }, relationPred);
        await record('topic_relation', relation.id, relation.updatedAt, relation.deviceId);
        changed = true;
      }
    });
    if (changed) EventBus.getInstance().emit(AppEvents.TOPIC_CHANGED, { id, deleted: true });
  }

  async listTopics(): Promise<Topic[]> {
    return LocalRdbHelper.query<Topic>(`SELECT * FROM topic WHERE isDeleted=0 ORDER BY updatedAt DESC`);
  }

  async addTopicRelation(topicId: string, targetType: FavoriteTargetType, targetId: string, note?: string): Promise<void> {
    await this.ensureReady();
    const existing = await LocalRdbHelper.query<TopicRelation>(
      'SELECT * FROM topic_relation WHERE topicId=? AND targetType=? AND targetId=? LIMIT 1',
      [topicId, targetType, targetId]);
    if (existing.length > 0) {
      const relation = existing[0];
      const pred = new relationalStore.RdbPredicates('topic_relation');
      pred.equalTo('id', relation.id);
      await this.commitChange('topic_relation', relation.id, async (db: RdbSession) => {
        await db.update('topic_relation', {
          'note': note ?? null, 'isDeleted': 0,
          'updatedAt': this.nextWriteTime(relation.updatedAt), 'deviceId': this.localDeviceId,
        }, pred);
      }, relation.updatedAt, relation.deviceId);
      EventBus.getInstance().emit(AppEvents.TOPIC_CHANGED, { id: topicId });
      return;
    }
    const id = LocalRdbHelper.topicRelationId(topicId, targetType, targetId);
    const now = this.nextWriteTime();
    await this.commitChange('topic_relation', id, async (db: RdbSession) => {
      await db.insert('topic_relation', {
        'id': id, 'topicId': topicId, 'targetType': targetType, 'targetId': targetId,
        'note': note ?? null, 'orderIndex': 0, 'createdAt': now, 'updatedAt': now,
        'isDeleted': 0,
        'deviceId': this.localDeviceId,
      });
    });
    EventBus.getInstance().emit(AppEvents.TOPIC_CHANGED, { id: topicId });
  }

  async removeTopicRelation(id: string): Promise<void> {
    await this.ensureReady();
    const rows = await LocalRdbHelper.query<TopicRelation>(
      'SELECT topicId, updatedAt, deviceId FROM topic_relation WHERE id=? LIMIT 1', [id]);
    if (rows.length === 0) return;
    const pred = new relationalStore.RdbPredicates('topic_relation');
    pred.equalTo('id', id);
    await this.commitChange('topic_relation', id, async (db: RdbSession) => {
      await db.update('topic_relation', {
        'isDeleted': 1, 'updatedAt': this.nextWriteTime(rows[0]?.updatedAt ?? 0), 'deviceId': this.localDeviceId,
      }, pred);
    }, rows[0].updatedAt, rows[0].deviceId);
    EventBus.getInstance().emit(AppEvents.TOPIC_CHANGED, { id: rows[0].topicId });
  }

  async listTopicRelations(topicId: string): Promise<TopicRelation[]> {
    return LocalRdbHelper.query<TopicRelation>(
      `SELECT r.* FROM topic_relation r INNER JOIN topic t ON t.id=r.topicId
        WHERE r.topicId=? AND r.isDeleted=0 AND t.isDeleted=0 ORDER BY r.orderIndex, r.createdAt`, [topicId]
    );
  }

  // ========== 浏览历史 ==========

  /**
   * 添加浏览历史（去重：同一targetId更新lastViewedAt；最多保留100条）
   */
  async addHistory(targetType: FavoriteTargetType, targetId: string): Promise<void> {
    try {
      const exist = await LocalRdbHelper.query<HistoryRecord>(
        `SELECT * FROM history_record WHERE targetType=? AND targetId=? LIMIT 1`,
        [targetType, targetId]
      );
      const now = DateUtil.now();
      if (exist.length > 0) {
        const pred = new relationalStore.RdbPredicates('history_record');
        pred.equalTo('id', exist[0].id);
        await LocalRdbHelper.update('history_record', {
          'lastViewedAt': now, 'viewCount': exist[0].viewCount + 1, 'updatedAt': now
        }, pred);
      } else {
        const id = DateUtil.uuid();
        await LocalRdbHelper.insert('history_record', {
          'id': id, 'targetType': targetType, 'targetId': targetId,
          'lastViewedAt': now, 'viewCount': 1,
          'createdAt': now, 'updatedAt': now, 'deviceId': this.localDeviceId,
        });
      }
      // 清理超100条的历史
      const older = await LocalRdbHelper.query<IdRow>(
        `SELECT id FROM history_record ORDER BY lastViewedAt DESC LIMIT -1 OFFSET 100`);
      for (const r of older) {
        await LocalRdbHelper.execute(`DELETE FROM history_record WHERE id=?`, [r.id]);
      }
      EventBus.getInstance().emit(AppEvents.HISTORY_CHANGED, { targetType, targetId });
    } catch (e) {
      Logger.warn(TAG, `addHistory failed: ${e}`);
    }
  }

  /** 浏览历史列表（最近优先） */
  async listHistory(limit: number = 50): Promise<HistoryRecord[]> {
    return LocalRdbHelper.query<HistoryRecord>(
      `SELECT * FROM history_record ORDER BY lastViewedAt DESC LIMIT ?`, [limit]);
  }

  /** 清空浏览历史 */
  async clearHistory(): Promise<void> {
    await LocalRdbHelper.execute(`DELETE FROM history_record`);
    EventBus.getInstance().emit(AppEvents.HISTORY_CHANGED);
  }

  // ========== 搜索历史 ==========
  private static SEARCH_HISTORY_KEY = 'search_history';
  private static MAX_SEARCH_HISTORY = 20;

  async addSearchHistory(keyword: string): Promise<void> {
    try {
      const kw = keyword.trim();
      if (!kw) return;
      let list = await this.getSearchHistory();
      list = list.filter(k => k !== kw);
      list.unshift(kw);
      if (list.length > UserDataService.MAX_SEARCH_HISTORY) {
        list = list.slice(0, UserDataService.MAX_SEARCH_HISTORY);
      }
      const pref = await preferences.getPreferences(PreferencesHelper.getContext(), UserDataService.SEARCH_HISTORY_KEY);
      await pref.put('list', JSON.stringify(list));
      await pref.flush();
    } catch (e) { Logger.warn(TAG, `addSearchHistory failed: ${e}`); }
  }

  async getSearchHistory(): Promise<string[]> {
    try {
      const pref = await preferences.getPreferences(PreferencesHelper.getContext(), UserDataService.SEARCH_HISTORY_KEY);
      const v = await pref.get('list', '[]') as string;
      return JSON.parse(v);
    } catch { return []; }
  }

  async clearSearchHistory(): Promise<void> {
    try {
      const pref = await preferences.getPreferences(PreferencesHelper.getContext(), UserDataService.SEARCH_HISTORY_KEY);
      await pref.put('list', '[]');
      await pref.flush();
    } catch { /* ignore */ }
  }

  // ========== 笔记快捷方法 ==========
  /** 获取关联到某对象的笔记 */
  async getNotesForTarget(targetType: NoteTargetType, targetId: string): Promise<Note[]> {
    return this.listNotes(targetType, targetId);
  }

  /** 获取笔记数量 */
  async getNoteCount(targetType?: NoteTargetType, targetId?: string): Promise<number> {
    let sql = `SELECT COUNT(*) as c FROM note WHERE isDeleted=0`;
    const args: relationalStore.ValueType[] = [];
    if (targetType) { sql += ` AND targetType=?`; args.push(targetType); }
    if (targetId) { sql += ` AND targetId=?`; args.push(targetId); }
    const rows = await LocalRdbHelper.query<CountRow>(sql, args);
    return rows.length > 0 ? rows[0].c : 0;
  }

  /** 给收藏打标签（替换tags） */
  async updateFavoriteTags(targetType: FavoriteTargetType, targetId: string, tags: string[]): Promise<void> {
    await this.ensureReady();
    const pred = new relationalStore.RdbPredicates('favorite');
    pred.equalTo('targetType', targetType).and().equalTo('targetId', targetId).and().equalTo('isDeleted', 0);
    const list = await LocalRdbHelper.query<Favorite>(`SELECT id, updatedAt, deviceId FROM favorite WHERE targetType=? AND targetId=? AND isDeleted=0 LIMIT 1`, [targetType, targetId]);
    if (list.length === 0) return;
    await this.commitChange('favorite', `${targetType}:${targetId}`, async (db: RdbSession) => {
      await db.update('favorite', {
        'tags': StringUtil.toTagsArray(tags),
        'updatedAt': this.nextWriteTime(list[0]?.updatedAt ?? 0),
        'deviceId': this.localDeviceId,
      }, pred);
    }, list[0].updatedAt, list[0].deviceId);
    // 更新缓存
    await this.reloadFavCache();
    EventBus.getInstance().emit(AppEvents.FAVORITE_CHANGED, { targetType, targetId, tagsUpdated: true });
  }

  private async commitChange(table: 'favorite' | 'note' | 'topic' | 'topic_relation', id: string,
    write: (db: RdbSession) => Promise<void>, baseTime: number = 0, baseDeviceId: string = ''): Promise<void> {
    const distributedModule = await import('./DistributedDataService');
    await distributedModule.DistributedDataService.getInstance().commitLocalChange(
      table, id, write, baseTime, baseDeviceId);
  }

  private getContext() {
    return PreferencesHelper.getContext();
  }
}
