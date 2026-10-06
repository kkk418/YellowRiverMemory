import { colors } from '../../common/constants/Colors';

import { DistributedDataService, SyncState } from '../../service/DistributedDataService';
import { EventBus, AppEvents } from '../../common/utils/EventBus';
import { SyncStatus } from '../../common/constants/Enums';

/**
 * 顶部同步状态小条：同步中/离线/有冲突时显示一条细条提示
 */
@Component
export struct SyncStatusBar {
  @State state: SyncState = DistributedDataService.getInstance().getState();
  @Consume('navPathStack') navPathStack: NavPathStack;
  @State visible: boolean = false;

  aboutToAppear(): void {
    EventBus.getInstance().on(AppEvents.SYNC_STATUS_CHANGED, this.onChange);
    this.state = DistributedDataService.getInstance().getState();
    this.refresh(this.state);
  }

  aboutToDisappear(): void {
    EventBus.getInstance().off(AppEvents.SYNC_STATUS_CHANGED, this.onChange);
  }

  private onChange = (data?: Object | null): void => {
    if (!data) return;
    const state = DistributedDataService.getInstance().getState();
    this.state = state;
    this.refresh(state);
  };

  private refresh(s: SyncState): void {
    this.visible = s.status === SyncStatus.SYNCING ||
      s.status === SyncStatus.OFFLINE ||
      s.status === SyncStatus.ERROR ||
      s.conflictCount > 0;
  }

  build() {
    if (this.visible) {
      Row({ space: 8 }) {
        // 状态指示点
        Column().width(6).height(6).borderRadius(3)
          .backgroundColor(
            this.state.status === SyncStatus.SYNCING ? colors.gold :
            this.state.status === SyncStatus.ERROR || this.state.conflictCount > 0 ? colors.cinnabar :
            colors.textTertiary
          )
        Text(this.barText())
          .fontSize(11).fontColor(colors.textSecondary)
          .layoutWeight(1)
        if (this.state.status === SyncStatus.SYNCING) {
          Text(`${this.state.progressPercent}%`)
            .fontSize(11).fontColor(colors.gold)
        }
        Text('查看 ›')
          .fontSize(11).fontColor(colors.gold)
          .onClick((): void => {
            this.navPathStack.pushPathByName('sync', null);
          })
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 6, bottom: 6 })
      .backgroundColor(colors.bgElevated)
      .border({ width: { bottom: 0.5 }, color: colors.borderSub })
    }
  }

  private barText(): string {
    if (this.state.status === SyncStatus.SYNCING) return '多端同步中…';
    if (this.state.status === SyncStatus.OFFLINE) return '离线模式：编辑将在联网后同步';
    if (this.state.status === SyncStatus.ERROR) return '同步异常，点击查看详情';
    if (this.state.conflictCount > 0) return `有 ${this.state.conflictCount} 处同步冲突，点击查看`;
    return '';
  }
}
