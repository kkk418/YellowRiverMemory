import UIAbility from '@ohos.app.ability.UIAbility';
import window from '@ohos.window';
import { AbilityConstant, Want } from '@kit.AbilityKit';
import { BusinessError } from '@ohos.base';
import { Logger } from '../common/utils/Logger';
import { PreferencesHelper } from '../common/utils/PreferencesHelper';
import { LocalRdbHelper } from '../database/LocalRdbHelper';
import { AssetRepository } from '../database/AssetRepository';
import { DistributedDataService } from '../service/DistributedDataService';
import { CultureService } from '../service/CultureService';
import { UserDataService } from '../service/UserDataService';
import { EventBus, AppEvents } from '../common/utils/EventBus';

const TAG = 'EntryAbility';

export default class EntryAbility extends UIAbility {
  private initPromise: Promise<void> = Promise.resolve();

  onCreate(_want: Want, _launchParam: AbilityConstant.LaunchParam): void {
    this.initPromise = this.initialize();
  }

  private async initialize(): Promise<void> {
    Logger.info(TAG, 'onCreate');
    try {
      // 1. 初始化Preferences
      await PreferencesHelper.init(this.context);
      Logger.info(TAG, 'PreferencesHelper inited');

      // 2. 初始化本地RDB数据库（建表）
      await LocalRdbHelper.init(this.context);
      Logger.info(TAG, 'LocalRdbHelper inited');

      // 3. 导入预置资源（rawfile/data/preset.json → RDB，仅首次启动执行）
      await AssetRepository.initIfNeeded(this.context.resourceManager);
      Logger.info(TAG, 'AssetRepository preset data inited');

      // 4. 预热内存缓存（遗址/文物）
      await CultureService.getInstance().warmCache();
      // 初始化UserDataService缓存
      await UserDataService.getInstance().ensureReady();
      Logger.info(TAG, 'Services cache warmed');

      // 5. 通知应用数据初始化完成；分布式授权需在窗口加载后申请。
      EventBus.getInstance().emit(AppEvents.DATA_INIT_COMPLETED, null);
    } catch (e) {
      Logger.error(TAG, `Init failed: ${e}`);
      throw new Error(String(e));
    }
  }

  onDestroy() {
    Logger.info(TAG, 'onDestroy');
    DistributedDataService.getInstance().dispose();
    EventBus.getInstance().clear();
  }

  onForeground(): void {
    Logger.info(TAG, 'onForeground');
    EventBus.getInstance().emit(AppEvents.APP_FOREGROUND, null);
    DistributedDataService.getInstance().setOnline();
  }

  onBackground(): void {
    Logger.info(TAG, 'onBackground');
    EventBus.getInstance().emit(AppEvents.APP_BACKGROUND, null);
  }

  async onWindowStageCreate(windowStage: window.WindowStage) {
    Logger.info(TAG, 'onWindowStageCreate');
    try {
      // Stage lifecycle callbacks do not wait for an async onCreate body.
      // Load the UI only after schema migration and preset import finish.
      await this.initPromise;
      // 设置主窗口
      const win = await windowStage.getMainWindow();
      // 设置全屏沉浸式
      await win.setWindowLayoutFullScreen(true);
      // 状态栏/导航栏颜色适配深色主题
      const sysBarColor = '#0A0806';
      await win.setWindowSystemBarProperties({
        statusBarColor: sysBarColor,
        statusBarContentColor: '#C9A96E',
        navigationBarColor: sysBarColor,
        navigationBarContentColor: '#C9A96E',
      });

      windowStage.loadContent('pages/Index', (err: BusinessError<void>, _data: void) => {
        if (err.code) {
          Logger.error(TAG, `loadContent failed: ${JSON.stringify(err)}`);
          return;
        }
        Logger.info(TAG, 'loadContent success');
        DistributedDataService.getInstance().init(this.context)
          .then(() => Logger.info(TAG, 'DistributedDataService inited'))
          .catch((e: Error) => Logger.warn(TAG, `DistributedDataService init failed (non-fatal): ${e}`));
      });
    } catch (e) {
      Logger.error(TAG, `onWindowStageCreate error: ${e}`);
      windowStage.loadContent('pages/StartupError', (err: BusinessError<void>, _data: void) => {
        if (err.code) Logger.error(TAG, `startup error page failed: ${JSON.stringify(err)}`);
      });
    }
  }

  onWindowStageDestroy() {
    Logger.info(TAG, 'onWindowStageDestroy');
  }

}
