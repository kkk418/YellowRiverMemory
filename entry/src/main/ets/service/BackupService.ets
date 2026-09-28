/**
 * 备份与恢复服务
 * - 一键导出所有个人数据（收藏/笔记/主题/偏好）为JSON
 * - 从备份JSON恢复
 * - 支持多设备迁移场景：手机备份→平板恢复
 */
import { Logger } from '../common/utils/Logger';
import { DateUtil } from '../common/utils/DateUtil';
import { PreferencesHelper } from '../common/utils/PreferencesHelper';
import { AppConstants } from '../common/constants/AppMeta';
import { LocalRdbHelper } from '../database/LocalRdbHelper';
import { DistributedDataService } from './DistributedDataService';
import { Favorite, Note, Topic, TopicRelation } from '../model/entity/Entities';

const TAG = 'BackupService';

export interface BackupData {
  version: number;
  appVersion: string;
  exportedAt: number;
  deviceId: string;
  favorites: Favorite[];
  notes: Note[];
  topics: Topic[];
  topicRelations: TopicRelation[];
  preferences: Record<string, string>;
}

export interface BackupStats {
  favorites: number;
  notes: number;
  topics: number;
}

export interface BackupResult {
  success: boolean;
  filePath?: string;
  message: string;
  stats?: BackupStats;
}

export class BackupService {
  private static instance: BackupService;
  static getInstance(): BackupService {
    if (!BackupService.instance) BackupService.instance = new BackupService();
    return BackupService.instance;
  }

  /**
   * 一键备份：导出全部个人数据到文件
   */
  async exportBackup(): Promise<BackupResult> {
    try {
      const favorites = await LocalRdbHelper.query<Favorite>('SELECT * FROM favorite WHERE isDeleted=0', []);
      const notes = await LocalRdbHelper.query<Note>('SELECT * FROM note WHERE isDeleted=0', []);
      const topics = await LocalRdbHelper.query<Topic>('SELECT * FROM topic WHERE isDeleted=0', []);
      const relations = await LocalRdbHelper.query<TopicRelation>('SELECT * FROM topic_relation WHERE isDeleted=0', []);

      // 偏好设置
      const prefs = await PreferencesHelper.getAll();
      const deviceId = await PreferencesHelper.getLocalDeviceId() || '';

      const data: BackupData = {
        version: AppConstants.DB_VERSION,
        appVersion: '1.0.0',
        exportedAt: DateUtil.now(),
        deviceId,
        favorites,
        notes,
        topics,
        topicRelations: relations,
        preferences: prefs,
      };

      const now = new Date();
      const y = now.getFullYear();
      const m = String(now.getMonth() + 1).padStart(2, '0');
      const d = String(now.getDate()).padStart(2, '0');
      const hh = String(now.getHours()).padStart(2, '0');
      const mm = String(now.getMinutes()).padStart(2, '0');
      const ss = String(now.getSeconds()).padStart(2, '0');
      const fileName = `yellow_river_backup_${y}${m}${d}_${hh}${mm}${ss}.json`;
      // 写入沙箱文件
      const ctx = PreferencesHelper.getContext();
      let writeError = '应用文件目录不可用';
      if (ctx) {
        try {
          const filesDir = ctx.filesDir;
          const filePath = `${filesDir}/${fileName}`;
          const fs = await import('@ohos.file.fs');
          const file = fs.openSync(filePath, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
          fs.writeSync(file.fd, JSON.stringify(data, null, 2));
          fs.closeSync(file);
          Logger.info(TAG, `backup written: ${filePath}`);
          return {
            success: true,
            filePath,
            message: `备份成功：${favorites.length} 收藏 · ${notes.length} 笔记 · ${topics.length} 主题`,
            stats: { favorites: favorites.length, notes: notes.length, topics: topics.length },
          };
        } catch (fsErr) {
          writeError = String(fsErr);
          Logger.warn(TAG, `fs write failed: ${fsErr}`);
        }
      }
      return {
        success: false,
        message: `备份文件未保存：${writeError}`,
      };
    } catch (e) {
      Logger.error(TAG, `exportBackup failed: ${e}`);
      return { success: false, message: `备份失败：${e}` };
    }
  }

  /**
   * 触发一次分布式全量同步（在新设备首次启动后用于拉取旧设备数据）
   */
  async restoreFromCloud(): Promise<BackupResult> {
    try {
      await DistributedDataService.getInstance().requestSync();
      return {
        success: true,
        message: '已请求可信设备同步；此操作不导入备份文件，请在同步页确认结果'
      };
    } catch (e) {
      return { success: false, message: `同步触发失败：${e}` };
    }
  }

  /**
   * 清空所有个人数据（慎重操作）
   */
  async clearAllPersonalData(): Promise<BackupResult> {
    throw new Error('清空个人数据功能尚未开放');
  }
}
