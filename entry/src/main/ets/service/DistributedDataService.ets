/**
 * 分布式数据服务（核心亮点）
 * - 基于 distributedKVStore 实现收藏/笔记/标签/主题的多设备双向同步
 * - LWW (Last-Writer-Wins) 时间戳冲突解决
 * - 设备发现 + 同步状态面板 + 冲突日志
 * - 离线编辑 + 联网自动合并
 */
import { Context, Permissions, abilityAccessCtrl } from '@kit.AbilityKit';
import { distributedKVStore } from '@kit.ArkData';
import { relationalStore } from '@kit.ArkData';
import { distributedDeviceManager } from '@kit.DistributedServiceKit';
import { connection } from '@kit.NetworkKit';
import { Logger } from '../common/utils/Logger';
import { PreferencesHelper } from '../common/utils/PreferencesHelper';
import { AppConstants } from '../common/constants/AppMeta';
import { deviceInfo } from '@kit.BasicServicesKit';
import { util } from '@kit.ArkTS';
import { EventBus, AppEvents } from '../common/utils/EventBus';
import { SyncStatus } from '../common/constants/Enums';
import { DateUtil } from '../common/utils/DateUtil';
import { LocalRdbHelper } from '../database/LocalRdbHelper';

const TAG = 'DistributedDataService';

/** 远端设备信息 */
export interface RemoteDevice {
  deviceId: string;
  deviceName: string;
  deviceType: string;
  isOnline: boolean;
  lastSeenTime: number;
}

/** 同步状态对象（UI可订阅） */
export class SyncState {
  status: SyncStatus = SyncStatus.IDLE;
  lastSyncTime: number = 0;
  localDeviceName: string = '';
  localDeviceId: string = '';
  localDeviceType: string = 'phone';
  pendingCount: number = 0;
  conflictCount: number = 0;
  progressPercent: number = 100;
  networkAvailable: boolean = false;
  permissionGranted: boolean = false;
  remoteDevices: RemoteDevice[] = [];
  /** 同步方向描述 */
  syncDirection: string = '';
  /** 本次同步变更数 */
  lastSyncChanged: number = 0;

  get remoteDeviceName(): string {
    const online = this.remoteDevices.find(d => d.isOnline);
    return online ? online.deviceName : '';
  }
  get isPhone(): boolean { return this.localDeviceType === 'phone'; }
  get hasRemote(): boolean { return this.remoteDevices.length > 0; }
}

/** 同步冲突记录 */
export interface SyncConflict {
  id: string;
  entityType: string;
  entityId: string;
  localData: string;
  remoteData: string;
  localDeviceId: string;
  remoteDeviceId: string;
  localTimestamp: number;
  remoteTimestamp: number;
  resolvedAt?: number;
  resolution?: 'version_a' | 'version_b' | 'merge';
  createdAt: number;
}

/** KV条目封装（LWW） */
interface KvEntry {
  v: string;     // value JSON
  t: number;     // timestamp
  d: string;     // deviceId
  s?: number;    // payload schema version; absent on older installs
  pT?: number;   // version observed before this edit
  pD?: string;
}

interface LocalEntity {
  updatedAt: number;
  dataStr: string;
  deviceId: string;
}

interface InFlightItem {
  id: string;
  entryJson: string;
}

interface IdRow {
  id: string;
}

interface EntryJsonRow {
  entryJson: string;
}

interface ConflictCountRow {
  cnt: number;
}

interface PendingRow {
  id: string;
  entityType: EntityType;
  entityId: string;
  entryJson: string;
}

interface PreparedChange {
  key: string;
  stableId: string;
  value: string;
  entry: KvEntry;
}

interface MergeOutcome {
  applied: boolean;
  republish: boolean;
  entityId: string;
  data?: Record<string, Object>;
}

type EntityType = 'favorite' | 'note' | 'topic' | 'topic_relation';
const ALL_ENTITY_TYPES: EntityType[] = ['favorite', 'note', 'topic', 'topic_relation'];
type RecordLocalChange = (entityType: EntityType, entityId: string,
  baseTime?: number, baseDeviceId?: string) => Promise<void>;

export class DistributedDataService {
  private static instance: DistributedDataService;
  private context?: Context;
  private state: SyncState = new SyncState();
  private initialized = false;
  private initRunning = false;
  private kvManager?: distributedKVStore.KVManager;
  private kvStore?: distributedKVStore.SingleKVStore;
  private deviceManager?: distributedDeviceManager.DeviceManager;
  private networkConnection?: connection.NetConnection;
  /** 防重入 */
  private syncing = false;
  /** A change queued during an active sync needs a follow-up pass. */
  private syncAgain = false;
  /** Only the exact outbox versions sent by this sync may be acknowledged. */
  private inFlightOutbox: InFlightItem[] = [];
  private inFlightDeviceIds: string[] = [];
  private remoteApplyFailed = false;
  /** syncComplete has no request ID; after a timeout its callbacks cannot safely acknowledge an outbox. */
  private completionAckUnsafe = false;
  private applyQueue: Promise<void> = Promise.resolve();
  private syncTimer?: number;
  private syncTimeout?: number;
  private retryDelayMs: number = 2000;

  static getInstance(): DistributedDataService {
    if (!DistributedDataService.instance) {
      DistributedDataService.instance = new DistributedDataService();
    }
    return DistributedDataService.instance;
  }

  async init(context: Context): Promise<void> {
    if ((this.initialized && this.kvStore) || this.initRunning) return;
    this.initRunning = true;
    this.context = context;
    try {
      // 1. 本地设备信息
      this.state.localDeviceName = String(deviceInfo.deviceType || '本机');
      this.state.localDeviceType = (deviceInfo.deviceType || 'phone').toString();
      let did = await PreferencesHelper.getLocalDeviceId();
      if (!did) {
        did = `dev_${Date.now().toString(36)}_${Math.random().toString(36).slice(2, 8)}`;
        await PreferencesHelper.setLocalDeviceId(did);
      }
      this.state.localDeviceId = did;
      this.state.lastSyncTime = await PreferencesHelper.getLastSyncTime();

      const grant = await abilityAccessCtrl.createAtManager().requestPermissionsFromUser(
        context, ['ohos.permission.DISTRIBUTED_DATASYNC'] as Permissions[]);
      this.state.permissionGranted = grant.authResults[0] === 0;
      if (!this.state.permissionGranted) {
        this.initialized = true;
        this.state.status = SyncStatus.ERROR;
        await this.refreshPendingCount();
        this.notifyStatusChange();
        return;
      }

      try {
        if (!this.deviceManager) {
          this.deviceManager = distributedDeviceManager.createDeviceManager(context.applicationInfo.name);
          this.deviceManager.on('deviceStateChange', () => {
            this.refreshRemoteDevices();
            this.notifyStatusChange();
            if (this.initialized) this.setOnline();
          });
          this.refreshRemoteDevices();
        }
      } catch (e) {
        Logger.warn(TAG, `createDeviceManager failed: ${e}`);
      }
      if (!this.networkConnection) this.initNetworkMonitor();

      // 2. 创建KVManager
      const kvConfig: distributedKVStore.KVManagerConfig = {
        context: context,
        bundleName: 'com.yellowriver.memory',
      };
      try {
        if (!this.kvManager) this.kvManager = distributedKVStore.createKVManager(kvConfig);
      } catch (e) {
        Logger.warn(TAG, `createKVManager failed (may need permission): ${e}`);
      }

      // 3. 获取/创建KVStore
      if (this.kvManager && !this.kvStore) {
        try {
          const options: distributedKVStore.Options = {
            createIfMissing: true,
            encrypt: true,
            backup: false,
            autoSync: false,
            kvStoreType: distributedKVStore.KVStoreType.SINGLE_VERSION,
            securityLevel: distributedKVStore.SecurityLevel.S1,
          };
          this.kvStore = await this.kvManager.getKVStore<distributedKVStore.SingleKVStore>(AppConstants.KV_STORE_ID, options);
          Logger.info(TAG, 'KVStore acquired, subscribing to data changes');
          this.subscribeRemoteChanges();
          this.kvStore.on('syncComplete', (result: [string, number][]) => {
            this.handleSyncComplete(result);
          });
        } catch (e) {
          Logger.warn(TAG, `getKVStore failed: ${e}`);
        }
      }

      this.initialized = true;
      // 4. 查询现有冲突数
      await this.refreshConflictCount();
      Logger.info(TAG, `DDS init ok, device=${this.state.localDeviceName}(${this.state.localDeviceId})`);
      this.notifyStatusChange();

      await this.refreshPendingCount();
      // 5. 启动时尝试一次同步（如果有KVStore）
      if (this.kvStore) {
        setTimeout(() => this.requestSync(), 2000);
      }
    } catch (e) {
      Logger.warn(TAG, `DDS init partially failed (app still runs standalone): ${e}`);
      this.initialized = true; // 允许降级运行
      this.state.status = SyncStatus.ERROR;
      await this.refreshPendingCount();
      this.notifyStatusChange();
    } finally {
      this.initRunning = false;
    }
  }

  /** 订阅远端数据变更（其他设备推送） */
  private subscribeRemoteChanges(): void {
    if (!this.kvStore) return;
    try {
      this.kvStore.on('dataChange',
        distributedKVStore.SubscribeType.SUBSCRIBE_TYPE_REMOTE,
        async (data: distributedKVStore.ChangeNotification) => {
          Logger.info(TAG, `remote change: insert=${data.insertEntries?.length ?? 0} update=${data.updateEntries?.length ?? 0} delete=${data.deleteEntries?.length ?? 0}`);
          let changed = 0;
          let failed = false;
          // One malformed entry must not prevent unrelated remote updates from applying.
          const allChanges: distributedKVStore.Entry[] = [
            ...(data.insertEntries || []),
            ...(data.updateEntries || []),
          ];
          for (const entry of allChanges) {
            try {
              const applied = await this.applyRemoteEntry(entry.key.toString(), entry.value.value as Uint8Array | string);
              if (applied) changed++;
            } catch (err) {
              Logger.error(TAG, `remote entry rejected key=${entry.key.toString()}: ${err}`);
              failed = true;
              this.remoteApplyFailed = true;
            }
          }
          for (const del of (data.deleteEntries || [])) {
            try {
              await this.applyRemoteDelete(del.key.toString());
            } catch (err) {
              Logger.error(TAG, `remote deletion rejected key=${del.key.toString()}: ${err}`);
              failed = true;
              this.remoteApplyFailed = true;
            }
          }
          this.state.lastSyncChanged = changed;
          if (failed) {
            this.state.status = SyncStatus.ERROR;
            this.scheduleSync();
          } else {
            // Receiving data alone does not confirm that our outbox reached peers.
            this.state.progressPercent = this.syncing ? 90 : 100;
            await this.refreshConflictCount();
          }
          this.notifyStatusChange();
        }
      );
    } catch (e) {
      Logger.warn(TAG, `subscribe dataChange failed: ${e}`);
    }
  }

  /** LWW：远端条目应用到本地 */
  private async applyRemoteEntry(key: string, value: Uint8Array | string): Promise<boolean> {
    let applied = false;
    const work = this.applyQueue.then(async () => {
      applied = await this.applyRemoteEntryCore(key, value);
    });
    this.applyQueue = work.then(() => {}, () => {});
    await work;
    return applied;
  }

  private async applyRemoteEntryCore(key: string, value: Uint8Array | string): Promise<boolean> {
    try {
      const text = value instanceof Uint8Array
        ? util.TextDecoder.create('utf-8', { ignoreBOM: true }).decodeToString(value)
        : String(value);
      const remote: KvEntry = JSON.parse(text);
      if (!remote || typeof remote.v !== 'string' || typeof remote.t !== 'number' ||
        !Number.isFinite(remote.t) || typeof remote.d !== 'string' || (remote.s && remote.s !== 1)) {
        throw new Error('Invalid distributed entry');
      }
      const parsedKey = this.parseKey(key);
      const entityType = parsedKey[0];
      const entityId = parsedKey[1];
      if (!entityType) return false;
      const payload = JSON.parse(remote.v) as Record<string, Object>;
      if (payload.updatedAt === null || payload.updatedAt === undefined) {
        payload.updatedAt = remote.t;
        remote.v = JSON.stringify(payload);
      } else if (Number(payload.updatedAt) !== remote.t) {
        throw new Error('Distributed timestamp mismatch');
      }
      if (entityType === 'favorite' &&
        `${String(payload.targetType ?? '')}:${String(payload.targetId ?? '')}` !== entityId) {
        throw new Error('Distributed favorite identity mismatch');
      }
      if ((entityType === 'note' || entityType === 'topic') && String(payload.id ?? '') !== entityId) {
        throw new Error('Distributed entity identity mismatch');
      }

      const outcome = await LocalRdbHelper.runInTransaction(async (): Promise<MergeOutcome> => {
        const local = await this.readLocalEntity(entityType, entityId, remote.v);
        const localId = local && entityType === 'topic_relation'
          ? String((JSON.parse(local.dataStr) as Record<string, Object>).id) : entityId;
        if (!local) {
          const data = await this.persistLocalEntity(entityType, entityId, remote.v, remote.d);
          return { applied: true, republish: false, entityId, data };
        }
        const localTime = local.updatedAt ?? 0;
        const localDevice = local.deviceId || this.state.localDeviceId;
        if (remote.t === localTime && remote.d === localDevice) {
          return { applied: false, republish: false, entityId: localId };
        }
        const remoteWins = remote.t > localTime ||
          (remote.t === localTime && remote.d.localeCompare(localDevice) > 0);
        if (local.dataStr !== remote.v && await this.isConcurrentVersion(entityType, localId, local, remote)) {
          await this.recordConflict(entityType, localId, local.dataStr, remote.v,
            localDevice, remote.d, localTime, remote.t);
        }
        if (remoteWins) {
          const data = await this.persistLocalEntity(entityType, localId, remote.v, remote.d);
          return { applied: true, republish: false, entityId: localId, data };
        }
        return { applied: false, republish: true, entityId: localId };
      });
      if (outcome.applied && outcome.data) {
        await this.notifyEntityChanged(entityType, outcome.entityId, outcome.data);
        Logger.info(TAG, `remote→local ${entityType}/${outcome.entityId}`);
      }
      if (outcome.republish) this.scheduleSync();
      return outcome.applied;
    } catch (e) {
      Logger.warn(TAG, `applyRemoteEntry failed key=${key}: ${e}`);
      throw new Error(String(e));
    }
  }

  /** Compare the parent versions so an acknowledged concurrent edit remains visible. */
  private async isConcurrentVersion(entityType: EntityType, entityId: string,
    local: LocalEntity, remote: KvEntry): Promise<boolean> {
    if (local.deviceId !== this.state.localDeviceId || remote.d === local.deviceId) return false;
    const key = `${entityType}/${entityId}`;
    const versions = await LocalRdbHelper.query<EntryJsonRow>(
      'SELECT entryJson FROM sync_local_version WHERE id=? LIMIT 1', [key]);
    if (versions.length > 0) {
      const localVersion = JSON.parse(versions[0].entryJson) as KvEntry;
      if (localVersion.t === local.updatedAt && localVersion.d === local.deviceId) {
        if (remote.pT === local.updatedAt && remote.pD === local.deviceId) return false;
        if (localVersion.pT === remote.t && localVersion.pD === remote.d) return false;
        if (localVersion.pT !== undefined && remote.t <= localVersion.pT) return false;
        return true;
      }
    }
    const rows = await LocalRdbHelper.query<EntryJsonRow>(
      'SELECT entryJson FROM sync_outbox WHERE id=? LIMIT 1', [key]);
    if (rows.length === 0) return false;
    const pending = JSON.parse(rows[0].entryJson) as KvEntry;
    return pending.t === local.updatedAt && pending.d === local.deviceId;
  }

  private async applyRemoteDelete(key: string): Promise<void> {
    const parsedKey = this.parseKey(key);
    const entityType = parsedKey[0];
    const entityId = parsedKey[1];
    if (!entityType) return;
    // 仅当本地存在且更新时间早于删除时间才删除（删除也是一种写入，LWW已在applyRemoteEntry通过tombstone处理；此处保留）
    try {
      Logger.warn(TAG, `Unexpected physical KV deletion for ${entityType}/${entityId}; entities must use soft-delete records`);
    } catch (e) {
      Logger.warn(TAG, `applyRemoteDelete failed: ${e}`);
    }
  }

  private parseKey(key: string): [EntityType | null, string] {
    const idx = key.indexOf('/');
    if (idx < 0) return [null, key];
    const t = key.slice(0, idx) as EntityType;
    if (ALL_ENTITY_TYPES.indexOf(t) < 0) return [null, key.slice(idx + 1)];
    return [t, key.slice(idx + 1)];
  }

  /** Persist a validated entity; caller controls the RDB transaction. */
  private async persistLocalEntity(entityType: EntityType, entityId: string, dataJson: string,
    fromDevice: string): Promise<Record<string, Object>> {
    const data = JSON.parse(dataJson) as Record<string, Object>;
    data.updatedAt = data.updatedAt ?? Date.now();
    data.deviceId = fromDevice || String(data.deviceId ?? '');
    switch (entityType) {
      case 'favorite':
        await this.upsertFavorite(entityId, data);
        break;
      case 'topic_relation':
        await this.upsertTopicRelation(entityId, data);
        break;
      case 'note':
      case 'topic':
        await this.upsertById(entityType, entityId, data);
        break;
      default:
        throw new Error(`Unsupported entityType: ${entityType}`);
    }
    return data;
  }

  private async notifyEntityChanged(entityType: EntityType, entityId: string,
    data: Record<string, Object>): Promise<void> {
    if (entityType === 'favorite') {
      const userDataModule = await import('./UserDataService');
      await userDataModule.UserDataService.getInstance().reloadFavCache();
      EventBus.getInstance().emit(AppEvents.FAVORITE_CHANGED, {
        targetType: String(data.targetType ?? ''), targetId: String(data.targetId ?? ''), remote: true,
      });
    } else if (entityType === 'note') {
      EventBus.getInstance().emit(AppEvents.NOTE_CHANGED, { id: entityId, remote: true });
    } else {
      EventBus.getInstance().emit(AppEvents.TOPIC_CHANGED, {
        id: entityType === 'topic_relation' ? String(data.topicId ?? '') : entityId, remote: true,
      });
    }
    EventBus.getInstance().emit(AppEvents.DATA_INIT_COMPLETED, { source: 'sync' });
  }

  private async upsertFavorite(entityId: string, data: Record<string, Object>): Promise<void> {
    const targetType = String(data.targetType ?? '');
    const targetId = String(data.targetId ?? '');
    if (!targetType || !targetId) throw new Error('Remote favorite is missing target identity');
    const existing = await LocalRdbHelper.query<IdRow>(
      'SELECT id FROM favorite WHERE targetType=? AND targetId=? LIMIT 1', [targetType, targetId]);
    if (existing.length > 0) data.id = existing[0].id;
    else data.id = String(data.id ?? DateUtil.uuid());
    await this.upsertById('favorite', String(data.id), data);
  }

  private async upsertTopicRelation(entityId: string, data: Record<string, Object>): Promise<void> {
    const topicId = String(data.topicId ?? '');
    const targetType = String(data.targetType ?? '');
    const targetId = String(data.targetId ?? '');
    if (!topicId || !targetType || !targetId) throw new Error('Remote topic relation is missing target identity');
    const existing = await LocalRdbHelper.query<IdRow>(
      'SELECT id FROM topic_relation WHERE topicId=? AND targetType=? AND targetId=? LIMIT 1',
      [topicId, targetType, targetId]);
    data.id = existing.length > 0 ? existing[0].id :
      LocalRdbHelper.topicRelationId(topicId, targetType, targetId);
    await this.upsertById('topic_relation', String(data.id), data);
  }

  private async upsertById(table: string, id: string, data: Record<string, Object>): Promise<void> {
    const exist = await LocalRdbHelper.query<IdRow>(`SELECT id FROM ${table} WHERE id=? LIMIT 1`, [id]);
    const cleanData: relationalStore.ValuesBucket = {};
    const allowed = this.allowedColumns(table);
    for (const k of Object.keys(data)) {
      if (!allowed.has(k)) continue;
      const value = data[k];
      if (value === null || typeof value === 'string' || typeof value === 'number' || typeof value === 'boolean') {
        cleanData[k] = value as relationalStore.ValueType | null;
      }
    }
    cleanData.id = id;
    if (exist.length > 0) {
      const predicates = new relationalStore.RdbPredicates(table);
      predicates.equalTo('id', id);
      await LocalRdbHelper.update(table, cleanData, predicates);
    } else {
      await LocalRdbHelper.insert(table, cleanData);
    }
  }

  private allowedColumns(table: string): Set<string> {
    switch (table) {
      case 'favorite':
        return new Set(['id', 'targetType', 'targetId', 'tags', 'remark', 'createdAt', 'updatedAt', 'isDeleted', 'deviceId']);
      case 'note':
        return new Set(['id', 'title', 'content', 'targetType', 'targetId', 'tags', 'images',
          'createdAt', 'updatedAt', 'isDeleted', 'deviceId']);
      case 'topic':
        return new Set(['id', 'name', 'description', 'coverColor', 'iconEmoji',
          'createdAt', 'updatedAt', 'isDeleted', 'deviceId']);
      case 'topic_relation':
        return new Set(['id', 'topicId', 'targetType', 'targetId', 'note', 'orderIndex',
          'createdAt', 'updatedAt', 'isDeleted', 'deviceId']);
      default:
        throw new Error(`Unsupported entity type: ${table}`);
    }
  }

  private async readLocalEntity(entityType: EntityType, entityId: string,
    remoteData?: string): Promise<LocalEntity | null> {
    let rows: Record<string, Object>[];
    if (entityType === 'favorite') {
      const splitAt = entityId.indexOf(':');
      if (splitAt < 0) return null;
      rows = await LocalRdbHelper.query<Record<string, Object>>(
        'SELECT * FROM favorite WHERE targetType=? AND targetId=? LIMIT 1',
        [entityId.slice(0, splitAt), entityId.slice(splitAt + 1)]);
    } else if (entityType === 'topic_relation' && remoteData) {
      const relation = JSON.parse(remoteData) as Record<string, Object>;
      rows = await LocalRdbHelper.query<Record<string, Object>>(
        'SELECT * FROM topic_relation WHERE topicId=? AND targetType=? AND targetId=? LIMIT 1',
        [String(relation.topicId ?? ''), String(relation.targetType ?? ''), String(relation.targetId ?? '')]);
    } else {
      rows = await LocalRdbHelper.query<Record<string, Object>>(
        `SELECT * FROM ${entityType} WHERE id=? LIMIT 1`, [entityId]);
    }
    if (rows.length === 0) return null;
    const row = rows[0];
    return {
      updatedAt: (row.updatedAt as number) ?? (row.createdAt as number) ?? 0,
      dataStr: JSON.stringify(row),
      deviceId: String(row.deviceId ?? ''),
    };
  }

  private async recordConflict(entityType: string, entityId: string, localData: string, remoteData: string,
    localDev: string, remoteDev: string, localT: number, remoteT: number): Promise<void> {
    try {
      const localFirst = localDev.localeCompare(remoteDev) <= 0;
      const firstTime = localFirst ? localT : remoteT;
      const secondTime = localFirst ? remoteT : localT;
      const id = `conflict_${entityType}_${entityId}_${firstTime}_${secondTime}`;
      const localJson = localFirst ? localData : remoteData;
      const remoteJson = localFirst ? remoteData : localData;
      const firstDevice = localFirst ? localDev : remoteDev;
      const secondDevice = localFirst ? remoteDev : localDev;
      await LocalRdbHelper.execute(
        `INSERT OR IGNORE INTO sync_conflict(id, entityType, entityId, localData, remoteData,
          localDeviceId, remoteDeviceId, localTimestamp, remoteTimestamp, createdAt)
         VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
        [id, entityType, entityId, localJson, remoteJson, firstDevice, secondDevice,
          firstTime, secondTime, Date.now()]);
    } catch (e) {
      Logger.warn(TAG, `recordConflict failed: ${e}`);
    }
  }

  async refreshConflictCount(): Promise<void> {
    try {
      const rows = await LocalRdbHelper.query<ConflictCountRow>(
        `SELECT COUNT(*) as cnt FROM sync_conflict WHERE resolvedAt IS NULL OR resolvedAt=0`, []);
      this.state.conflictCount = rows[0]?.cnt ?? 0;
      if (this.state.conflictCount > 0) {
        this.state.status = SyncStatus.CONFLICT;
      } else if (this.state.status === SyncStatus.CONFLICT) {
        this.state.status = SyncStatus.IDLE;
      }
    } catch { /* ignore */ }
  }

  private async refreshPendingCount(): Promise<void> {
    try {
      this.state.pendingCount = await LocalRdbHelper.count('sync_outbox');
    } catch { this.state.pendingCount = 0; }
  }

  private refreshRemoteDevices(): void {
    try {
      if (!this.deviceManager) return;
      const localNetworkId = this.deviceManager.getLocalDeviceNetworkId();
      const devices = this.deviceManager.getAvailableDeviceListSync();
      this.state.remoteDevices = devices
        .filter(device => device.networkId !== localNetworkId)
        .map((device): RemoteDevice => ({
          deviceId: String(device.networkId ?? ''),
          deviceName: String(device.deviceName ?? '可信设备'),
          deviceType: String(device.deviceType ?? 'device'),
          isOnline: true,
          lastSeenTime: Date.now(),
        }))
        .filter(device => device.deviceId.length > 0);
    } catch (e) {
      Logger.warn(TAG, `refresh devices failed: ${e}`);
      this.state.remoteDevices = [];
    }
  }

  private initNetworkMonitor(): void {
    try {
      const net = connection.createNetConnection();
      this.networkConnection = net;
      net.on('netAvailable', () => { this.setOnline(); });
      net.on('netLost', () => { this.setOffline(); });
      net.on('netUnavailable', () => { this.setOffline(); });
      net.register((err) => {
        if (err) {
          Logger.warn(TAG, `network monitor registration failed: ${err}`);
          return;
        }
        connection.hasDefaultNet().then((available: boolean) => {
          if (available) this.setOnline();
          else this.setOffline();
        }).catch(() => this.setOffline());
      });
    } catch (e) {
      Logger.warn(TAG, `network monitor unavailable: ${e}`);
    }
  }

  private async handleSyncComplete(result: [string, number][]): Promise<void> {
    if (!this.syncing) return;
    // A timed-out sync may report completion while a retry is active. The API does not
    // identify which call completed, so no callback in this process can safely ack it.
    if (this.completionAckUnsafe) {
      Logger.warn(TAG, 'syncComplete ignored: a prior timeout made outbox acknowledgement ambiguous');
      return;
    }
    if (this.syncTimeout) clearTimeout(this.syncTimeout);
    const successfulDeviceIds = result.filter(item => item[1] === 0).map(item => item[0]);
    const succeeded = !this.remoteApplyFailed && this.inFlightDeviceIds.length > 0 &&
      result.every(item => item[1] === 0) &&
      this.inFlightDeviceIds.every(id => successfulDeviceIds.indexOf(id) >= 0);
    if (succeeded) {
      try {
        await LocalRdbHelper.runInTransaction(async () => {
          for (const item of this.inFlightOutbox) {
            await LocalRdbHelper.execute('DELETE FROM sync_outbox WHERE id=? AND entryJson=?',
              [item.id, item.entryJson]);
          }
        });
      } catch (e) {
        Logger.warn(TAG, `acknowledge outbox failed: ${e}`);
      }
      this.state.lastSyncTime = Date.now();
      await PreferencesHelper.setLastSyncTime(this.state.lastSyncTime);
    }
    await this.refreshPendingCount();
    await this.refreshConflictCount();
    this.state.progressPercent = 100;
    this.state.status = !succeeded ? SyncStatus.ERROR :
      (this.state.conflictCount > 0 ? SyncStatus.CONFLICT : SyncStatus.IDLE);
    this.syncing = false;
    this.inFlightOutbox = [];
    this.inFlightDeviceIds = [];
    this.notifyStatusChange();
    if (succeeded) this.retryDelayMs = 2000;
    if (!succeeded) this.scheduleRetry();
    if (succeeded && this.syncAgain) {
      this.syncAgain = false;
      this.scheduleSync();
    }
  }

  /** Commit the entity and its pending sync version together. */
  async commitLocalChange(entityType: EntityType, entityId: string, write: () => Promise<void>,
    baseTime: number = 0, baseDeviceId: string = ''): Promise<void> {
    await this.commitLocalBatch(async (record: RecordLocalChange): Promise<void> => {
      await write();
      await record(entityType, entityId, baseTime, baseDeviceId);
    });
  }

  /** All writes and their outbox versions commit atomically; publish only after commit. */
  async commitLocalBatch(write: (record: RecordLocalChange) => Promise<void>): Promise<void> {
    const changes = await LocalRdbHelper.runInTransaction(async (): Promise<PreparedChange[]> => {
      const prepared: PreparedChange[] = [];
      const record: RecordLocalChange = async (entityType: EntityType, entityId: string,
        baseTime: number = 0, baseDeviceId: string = ''): Promise<void> => {
        const local = await this.readLocalEntity(entityType, entityId);
        if (!local) throw new Error(`Local change did not create ${entityType}/${entityId}`);
        const change = this.prepareChange(entityType, entityId, local.dataStr, baseTime, baseDeviceId);
        await this.persistChange(entityType, change);
        prepared.push(change);
      };
      await write(record);
      return prepared;
    });
    // Local callers can refresh immediately; the durable outbox survives a failed KV write.
    for (const change of changes) {
      this.publishChange(change).catch((e: Error) => Logger.warn(TAG, `publish queued change failed: ${e}`));
    }
  }

  /** Queue an already committed version, used by manual conflict resolution. */
  async pushChange(entityType: EntityType, entityId: string, data: string | Record<string, Object>,
    baseTime: number = 0, baseDeviceId: string = ''): Promise<void> {
    const dataString = typeof data === 'string' ? data : JSON.stringify(data);
    const change = this.prepareChange(entityType, entityId, dataString, baseTime, baseDeviceId);
    await LocalRdbHelper.runInTransaction(async () => {
      await this.persistChange(entityType, change);
    });
    await this.publishChange(change);
  }

  private prepareChange(entityType: EntityType, entityId: string, dataString: string,
    baseTime: number, baseDeviceId: string): PreparedChange {
    const parsed = JSON.parse(dataString) as Record<string, Object>;
    const stableId = entityType === 'favorite'
      ? `${String(parsed.targetType ?? '')}:${String(parsed.targetId ?? '')}` : entityId;
    const key = `${entityType}/${stableId}`;
    const entry: KvEntry = {
      v: dataString,
      t: Number(parsed.updatedAt ?? Date.now()),
      d: String(parsed.deviceId || this.state.localDeviceId),
      s: 1,
    };
    if (baseTime > 0 && baseDeviceId) {
      entry.pT = baseTime;
      entry.pD = baseDeviceId;
    }
    return { key, stableId, value: JSON.stringify(entry), entry };
  }

  private async persistChange(entityType: EntityType, change: PreparedChange): Promise<void> {
    await LocalRdbHelper.execute(
      'INSERT OR REPLACE INTO sync_outbox(id, entityType, entityId, entryJson, updatedAt) VALUES(?, ?, ?, ?, ?)',
      [change.key, entityType, change.stableId, change.value, change.entry.t]);
    await LocalRdbHelper.execute(
      'INSERT OR REPLACE INTO sync_local_version(id, entryJson) VALUES(?, ?)', [change.key, change.value]);
  }

  private async publishChange(change: PreparedChange): Promise<void> {
    await this.refreshPendingCount();
    if (!this.kvStore) {
      this.state.status = this.state.permissionGranted ? SyncStatus.OFFLINE : SyncStatus.ERROR;
      this.notifyStatusChange();
      return;
    }
    try {
      await this.putIfNewer(change.key, change.value, change.entry);
      Logger.debug(TAG, `queued ${change.key}`);
      this.scheduleSync();
    } catch (e) {
      Logger.warn(TAG, `kvStore.put failed; persistent outbox retained: ${e}`);
      this.state.status = SyncStatus.OFFLINE;
      this.notifyStatusChange();
    }
  }

  /** Keep a newer version already present in the distributed KV from being overwritten by a stale snapshot. */
  private async putIfNewer(key: string, value: string, candidate: KvEntry): Promise<void> {
    if (!this.kvStore) return;
    let existingValue: boolean | string | number | Uint8Array;
    try {
      existingValue = await this.kvStore.get(key);
    } catch (_) {
      // A missing key is expected; the candidate becomes the first version.
      await this.kvStore.put(key, value);
      return;
    }
    const existingText = existingValue instanceof Uint8Array
      ? util.TextDecoder.create('utf-8', { ignoreBOM: true }).decodeToString(existingValue)
      : String(existingValue);
    let existing: KvEntry;
    try {
      existing = JSON.parse(existingText) as KvEntry;
      if (!existing || typeof existing.v !== 'string' || typeof existing.t !== 'number' ||
        !Number.isFinite(existing.t) || typeof existing.d !== 'string') {
        throw new Error('Invalid existing distributed entry');
      }
    } catch (e) {
      // We cannot order an invalid version against a local edit. Preserve both
      // the stored value and the outbox item while allowing other keys to sync.
      Logger.error(TAG, `cannot compare distributed entry key=${key}: ${e}`);
      this.remoteApplyFailed = true;
      return;
    }
    const existingWins = existing.t > candidate.t ||
      (existing.t === candidate.t && existing.d.localeCompare(candidate.d) > 0);
    if (existingWins) {
      await this.applyRemoteEntry(key, existingText);
      return;
    }
    if (existing.t === candidate.t && existing.d === candidate.d) return;
    await this.kvStore.put(key, value);
  }

  private scheduleSync(): void {
    if (this.syncTimer) clearTimeout(this.syncTimer);
    this.syncTimer = setTimeout(() => {
      this.requestSync().catch((e: Error) => Logger.warn(TAG, `scheduled sync failed: ${e}`));
    }, 500);
  }

  private scheduleRetry(): void {
    if (!this.kvStore) return;
    if (this.syncTimer) clearTimeout(this.syncTimer);
    const delay = this.retryDelayMs;
    this.retryDelayMs = Math.min(this.retryDelayMs * 2, 30000);
    this.syncTimer = setTimeout(() => {
      this.requestSync().catch((e: Error) => Logger.warn(TAG, `retry sync failed: ${e}`));
    }, delay);
  }

  /** 触发一次全量同步（push收藏/笔记/主题/主题关系，再接收远端变更） */
  async requestSync(): Promise<void> {
    if (this.syncing) {
      this.syncAgain = true;
      return;
    }
    if (!this.kvStore && this.context) await this.init(this.context);
    if (!this.kvStore) {
      Logger.info(TAG, 'requestSync: KV not available (offline/permission)');
      return;
    }
    this.refreshRemoteDevices();
    let hasDefaultNetwork = false;
    try { hasDefaultNetwork = await connection.hasDefaultNet(); }
    catch (e) { Logger.warn(TAG, `requestSync network check failed: ${e}`); }
    // Distributed peers may be reachable directly without a default internet route.
    this.state.networkAvailable = hasDefaultNetwork || this.state.remoteDevices.some(d => d.isOnline);
    this.syncing = true;
    this.remoteApplyFailed = false;
    this.state.status = SyncStatus.SYNCING;
    this.state.progressPercent = 10;
    this.notifyStatusChange();
    try {
      this.refreshRemoteDevices();
      // Re-write the durable outbox before syncing. Records include soft deletes.
      // Recover any KV entry whose earlier dataChange callback failed to write RDB.
      for (const entityType of ALL_ENTITY_TYPES) {
        const entries = await this.kvStore.getEntries(`${entityType}/`);
        for (const item of entries) {
          try {
            await this.applyRemoteEntry(item.key.toString(), item.value.value as Uint8Array | string);
          } catch (e) {
            // Keep the bad entry in the KV store for inspection, but allow other keys
            // and the local outbox to make progress.
            Logger.error(TAG, `stored distributed entry rejected key=${item.key.toString()}: ${e}`);
            this.remoteApplyFailed = true;
          }
        }
      }
      const pending = await LocalRdbHelper.query<PendingRow>(
        'SELECT id, entityType, entityId, entryJson FROM sync_outbox ORDER BY updatedAt', []);
      this.inFlightOutbox = pending.map((item): InFlightItem => ({ id: item.id, entryJson: item.entryJson }));
      for (const item of pending) {
        const candidate = JSON.parse(item.entryJson) as KvEntry;
        await this.putIfNewer(`${item.entityType}/${item.entityId}`, item.entryJson, candidate);
      }
      this.state.progressPercent = 40;

      // Push all records, including soft-deleted rows, for first-time devices.
      let pushedCount = 0;
      for (const t of ALL_ENTITY_TYPES) {
        try {
          const rows = await LocalRdbHelper.query<Record<string, Object>>(`SELECT * FROM ${t}`, []);
          for (const r of rows) {
            const id = String(r.id ?? '');
            if (!id) continue;
            const syncId = t === 'favorite'
              ? `${String(r.targetType ?? '')}:${String(r.targetId ?? '')}` : id;
            const e: KvEntry = {
              v: JSON.stringify(r),
              t: (r.updatedAt as number) ?? Date.now(),
              d: String(r.deviceId || this.state.localDeviceId),
              s: 1,
            };
            await this.putIfNewer(`${t}/${syncId}`, JSON.stringify(e), e);
            pushedCount++;
          }
        } catch (e) {
          Logger.warn(TAG, `push all ${t} failed: ${e}`);
          throw new Error(String(e));
        }
      }
      this.state.progressPercent = 70;

      const deviceIds = this.state.remoteDevices.filter(d => d.isOnline).map(d => d.deviceId);
      if (deviceIds.length === 0) {
        this.syncing = false;
        this.inFlightOutbox = [];
        this.inFlightDeviceIds = [];
        if (this.syncTimeout) clearTimeout(this.syncTimeout);
        this.state.progressPercent = 100;
        await this.refreshPendingCount();
        this.state.status = this.remoteApplyFailed || this.completionAckUnsafe ? SyncStatus.ERROR :
          (this.state.pendingCount > 0 ? SyncStatus.OFFLINE : SyncStatus.IDLE);
        this.notifyStatusChange();
        if (this.syncAgain) {
          this.syncAgain = false;
          this.scheduleSync();
        }
        return;
      }
      this.state.lastSyncChanged = pushedCount;
      this.state.progressPercent = 70;
      // API 14 sync() is event-completed and returns void.
      this.inFlightDeviceIds = deviceIds;
      this.kvStore.sync(deviceIds, distributedKVStore.SyncMode.PUSH_PULL);
      if (this.syncTimeout) clearTimeout(this.syncTimeout);
      this.syncTimeout = setTimeout(() => {
        this.completionAckUnsafe = true;
        this.syncing = false;
        this.inFlightOutbox = [];
        this.inFlightDeviceIds = [];
        this.state.status = SyncStatus.ERROR;
        this.refreshPendingCount().then(() => this.notifyStatusChange());
        this.scheduleRetry();
      }, 15000);
      Logger.info(TAG, `sync started, peers=${deviceIds.length}, pushed=${pushedCount}`);
      this.notifyStatusChange();
    } catch (e) {
      Logger.error(TAG, `requestSync failed: ${e}`);
      if (this.syncTimeout) clearTimeout(this.syncTimeout);
      this.syncing = false;
      this.inFlightOutbox = [];
      this.inFlightDeviceIds = [];
      this.state.status = SyncStatus.ERROR;
      this.notifyStatusChange();
      this.scheduleRetry();
    }
  }

  /** 解决冲突 */
  async resolveConflict(conflictId: string, useVersionA: boolean): Promise<void> {
    try {
      const rows = await LocalRdbHelper.query<SyncConflict>(`SELECT * FROM sync_conflict WHERE id=?`, [conflictId]);
      if (rows.length === 0) return;
      const c = rows[0];
      const chosen = JSON.parse(useVersionA ? c.localData : c.remoteData) as Record<string, Object>;
      const current = await this.readLocalEntity(c.entityType as EntityType, c.entityId);
      // A manual choice is a new edit. Give it a later version than either
      // recorded candidate so the normal LWW rule propagates that choice.
      chosen.updatedAt = Math.max(DateUtil.now(), c.localTimestamp + 1,
        c.remoteTimestamp + 1, (current?.updatedAt ?? 0) + 1);
      chosen.deviceId = this.state.localDeviceId;
      const chosenJson = JSON.stringify(chosen);
      await this.commitLocalChange(c.entityType as EntityType, c.entityId, async () => {
        await this.persistLocalEntity(c.entityType as EntityType, c.entityId, chosenJson, this.state.localDeviceId);
      }, current?.updatedAt ?? 0, current?.deviceId ?? '');
      await this.notifyEntityChanged(c.entityType as EntityType, c.entityId, chosen);
      const predicates = new relationalStore.RdbPredicates('sync_conflict');
      predicates.equalTo('id', conflictId);
      await LocalRdbHelper.update('sync_conflict', {
        'resolvedAt': Date.now(), 'resolution': useVersionA ? 'version_a' : 'version_b',
      }, predicates);
      await this.refreshConflictCount();
      this.notifyStatusChange();
      EventBus.getInstance().emit(AppEvents.FAVORITE_CHANGED, { conflictResolved: true });
      EventBus.getInstance().emit(AppEvents.NOTE_CHANGED, { conflictResolved: true });
    } catch (e) {
      Logger.warn(TAG, `resolveConflict failed: ${e}`);
    }
  }

  async listConflicts(): Promise<SyncConflict[]> {
    try {
      return await LocalRdbHelper.query<SyncConflict>(
        `SELECT * FROM sync_conflict WHERE resolvedAt IS NULL OR resolvedAt=0 ORDER BY createdAt DESC`, []);
    } catch { return []; }
  }

  getState(): SyncState {
    const state = new SyncState();
    state.status = this.state.status;
    state.lastSyncTime = this.state.lastSyncTime;
    state.localDeviceName = this.state.localDeviceName;
    state.localDeviceId = this.state.localDeviceId;
    state.localDeviceType = this.state.localDeviceType;
    state.pendingCount = this.state.pendingCount;
    state.conflictCount = this.state.conflictCount;
    state.progressPercent = this.state.progressPercent;
    state.networkAvailable = this.state.networkAvailable;
    state.permissionGranted = this.state.permissionGranted;
    state.remoteDevices = this.state.remoteDevices.map((device: RemoteDevice): RemoteDevice => ({
      deviceId: device.deviceId, deviceName: device.deviceName, deviceType: device.deviceType,
      isOnline: device.isOnline, lastSeenTime: device.lastSeenTime,
    }));
    state.syncDirection = this.state.syncDirection;
    state.lastSyncChanged = this.state.lastSyncChanged;
    return state;
  }
  isInitialized(): boolean { return this.initialized; }

  async setOnline(): Promise<void> {
    try {
      if (!this.kvStore && this.context) await this.init(this.context);
      const available = await connection.hasDefaultNet();
      this.refreshRemoteDevices();
      this.state.networkAvailable = available || this.state.remoteDevices.some(d => d.isOnline);
      if (this.initialized && this.kvStore) {
        await this.requestSync();
      }
    } catch (e) {
      Logger.warn(TAG, `network availability check failed: ${e}`);
      this.setOffline();
    }
    this.notifyStatusChange();
  }

  setOffline(): void {
    this.refreshRemoteDevices();
    this.state.networkAvailable = this.state.remoteDevices.some(d => d.isOnline);
    if (this.state.networkAvailable) this.scheduleSync();
    else if (this.state.pendingCount > 0) this.state.status = SyncStatus.OFFLINE;
    this.notifyStatusChange();
  }

  dispose(): void {
    if (this.syncTimer) clearTimeout(this.syncTimer);
    if (this.syncTimeout) clearTimeout(this.syncTimeout);
    try { this.networkConnection?.unregister(() => {}); } catch (e) {
      Logger.warn(TAG, `network monitor unregister failed: ${e}`);
    }
  }

  private notifyStatusChange(): void {
    EventBus.getInstance().emit(AppEvents.SYNC_STATUS_CHANGED, { status: this.state.status });
  }
}
