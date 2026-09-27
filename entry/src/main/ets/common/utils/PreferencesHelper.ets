/**
 * 用户偏好设置工具（封装@ohos.data.preferences）
 * 用于存储轻量KV配置：主题模式、首次启动、上次同步时间等。
 */
import { preferences } from '@kit.ArkData';
import { Context } from '@kit.AbilityKit';
import { Logger } from './Logger';
import { AppConstants } from '../constants/AppMeta';
import { ThemeMode } from '../constants/Enums';

const TAG = 'PreferencesHelper';

class PreferencesKey {
  static FIRST_LAUNCH = 'first_launch';
  static THEME_MODE = 'theme_mode';
  static LAST_SYNC_TIME = 'last_sync_time';
  static LOCAL_DEVICE_ID = 'local_device_id';
  static DISTRIBUTED_ENABLED = 'distributed_enabled';
  static SEARCH_HISTORY = 'search_history';
  static DATA_VERSION = 'data_version';
}

export class PreferencesHelper {
  private static pref: preferences.Preferences | null = null;
  private static ctx?: Context;

  static getContext(): Context {
    if (!PreferencesHelper.ctx) throw new Error('PreferencesHelper not initialized');
    return PreferencesHelper.ctx;
  }

  static async init(context: Context): Promise<void> {
    try {
      PreferencesHelper.ctx = context;
      PreferencesHelper.pref = await preferences.getPreferences(context, AppConstants.PREFS_NAME);
      Logger.info(TAG, 'Preferences init success');
    } catch (e) {
      Logger.error(TAG, `Preferences init failed: ${e}`);
      throw new Error(String(e));
    }
  }

  private static async getPref(): Promise<preferences.Preferences> {
    if (!PreferencesHelper.pref) {
      throw new Error('Preferences not initialized, call init(context) first');
    }
    return PreferencesHelper.pref;
  }

  static async isFirstLaunch(): Promise<boolean> {
    const pref = await PreferencesHelper.getPref();
    return (await pref.get(PreferencesKey.FIRST_LAUNCH, true)) as boolean;
  }

  static async setFirstLaunchDone(): Promise<void> {
    const pref = await PreferencesHelper.getPref();
    await pref.put(PreferencesKey.FIRST_LAUNCH, false);
    await pref.flush();
  }

  static async getThemeMode(): Promise<ThemeMode> {
    const pref = await PreferencesHelper.getPref();
    const v = (await pref.get(PreferencesKey.THEME_MODE, ThemeMode.INK)) as string;
    return v === ThemeMode.RICE_PAPER ? ThemeMode.RICE_PAPER : ThemeMode.INK;
  }

  static async setThemeMode(mode: ThemeMode): Promise<void> {
    const pref = await PreferencesHelper.getPref();
    await pref.put(PreferencesKey.THEME_MODE, mode);
    await pref.flush();
  }

  static async getLastSyncTime(): Promise<number> {
    const pref = await PreferencesHelper.getPref();
    return (await pref.get(PreferencesKey.LAST_SYNC_TIME, 0)) as number;
  }

  static async setLastSyncTime(ts: number): Promise<void> {
    const pref = await PreferencesHelper.getPref();
    await pref.put(PreferencesKey.LAST_SYNC_TIME, ts);
    await pref.flush();
  }

  static async getLocalDeviceId(): Promise<string> {
    const pref = await PreferencesHelper.getPref();
    return (await pref.get(PreferencesKey.LOCAL_DEVICE_ID, '')) as string;
  }

  static async setLocalDeviceId(id: string): Promise<void> {
    const pref = await PreferencesHelper.getPref();
    await pref.put(PreferencesKey.LOCAL_DEVICE_ID, id);
    await pref.flush();
  }

  static async isDistributedEnabled(): Promise<boolean> {
    const pref = await PreferencesHelper.getPref();
    return (await pref.get(PreferencesKey.DISTRIBUTED_ENABLED, false)) as boolean;
  }

  static async setDistributedEnabled(enabled: boolean): Promise<void> {
    const pref = await PreferencesHelper.getPref();
    await pref.put(PreferencesKey.DISTRIBUTED_ENABLED, enabled);
    await pref.flush();
  }

  static async getDataVersion(): Promise<number> {
    const pref = await PreferencesHelper.getPref();
    return (await pref.get(PreferencesKey.DATA_VERSION, 0)) as number;
  }

  static async setDataVersion(v: number): Promise<void> {
    const pref = await PreferencesHelper.getPref();
    await pref.put(PreferencesKey.DATA_VERSION, v);
    await pref.flush();
  }

  /** 获取所有KV（用于备份） */
  static async getAll(): Promise<Record<string, string>> {
    try {
      const pref = await PreferencesHelper.getPref();
      const result: Record<string, string> = {};
      const keys = await pref.getAll();
      if (keys && typeof keys === 'object') {
    const obj = keys as Record<string, preferences.ValueType>;
        for (const k of Object.keys(obj)) {
          result[k] = String(obj[k]);
        }
      }
      return result;
    } catch (e) {
      return {};
    }
  }

  static getContextSync(): Context {
    return PreferencesHelper.getContext();
  }
}
