import { colors } from '../../common/constants/Colors';

import { DistributedDataService, RemoteDevice, SyncConflict, SyncState } from '../../service/DistributedDataService';
import { EventBus, AppEvents } from '../../common/utils/EventBus';
import { DateUtil } from '../../common/utils/DateUtil';
import { SyncStatus } from '../../common/constants/Enums';

/**
 * 同步页：展示多设备同步状态、进度与冲突状态
 */
@Component
export struct SyncPage {
  @State state: SyncState = DistributedDataService.getInstance().getState();
  @State nowTick: number = Date.now();
  @State showConflictSheet: boolean = false;
  @State conflicts: SyncConflict[] = [];
  private timer?: number;

  aboutToAppear(): void {
    EventBus.getInstance().on(AppEvents.SYNC_STATUS_CHANGED, this.onSyncChange);
    this.state = DistributedDataService.getInstance().getState();
    this.timer = setInterval(() => {
      this.nowTick = Date.now();
    }, 1000);
  }

  aboutToDisappear(): void {
    EventBus.getInstance().off(AppEvents.SYNC_STATUS_CHANGED, this.onSyncChange);
    if (this.timer) clearInterval(this.timer);
  }

  private onSyncChange = (data?: Object | null): void => {
    if (data) this.state = DistributedDataService.getInstance().getState();
  };

  private async manualSync(): Promise<void> {
    await DistributedDataService.getInstance().requestSync();
  }

  @Builder StatusDot(color: ResourceColor) {
    Circle({ width: 8, height: 8 })
      .fill(color)
      .margin({ right: 8 })
  }

  @Builder SectionTitle(title: string, en: string) {
    Column({ space: 4 }) {
      Row() {
        Text(en).fontSize(10).fontColor(colors.textTertiary).letterSpacing(2)
        Text('·').fontSize(10).fontColor(colors.textTertiary).margin({ left: 6, right: 6 })
        Text('SYNC').fontSize(10).fontColor(colors.textTertiary).letterSpacing(2)
      }
      Text(title).fontSize(20).fontWeight(FontWeight.Bold).fontColor(colors.textPrimary)
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
    .margin({ bottom: 16 })
  }

  @Builder DeviceCard(icon: string, name: string, type: string, isLocal: boolean, online: boolean) {
    Row({ space: 12 }) {
      Text(icon).fontSize(28).opacity(online ? 1 : 0.4)
      Column({ space: 4 }) {
        Row({ space: 6 }) {
          Text(name).fontSize(14).fontColor(colors.textPrimary).maxLines(1)
          if (isLocal) {
            Text('本机').fontSize(9).fontColor(colors.bg)
              .backgroundColor(colors.gold)
              .padding({ left: 6, right: 6, top: 2, bottom: 2 })
              .borderRadius(2)
          }
        }
        Text(online ? `${type}· 在线` : `${type}· 离线`)
          .fontSize(11)
          .fontColor(online ? colors.era_hantang : colors.textTertiary)
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
    }
    .width('100%')
    .padding(12)
    .backgroundColor(colors.bgCard)
    .borderRadius(2)
  }

  build() {
    Column({ space: 0 }) {
      // 标题
      Column({ space: 4 }) {
        Row() {
          Text('DATA').fontSize(10).fontColor(colors.textTertiary).letterSpacing(3)
          Text('·').fontSize(10).fontColor(colors.textTertiary).margin({ left: 6, right: 6 })
          Text('流转').fontSize(10).fontColor(colors.textTertiary).letterSpacing(3)
        }
        Text('多端同步')
          .fontSize(28).fontWeight(FontWeight.Bold).fontColor(colors.textPrimary)
      }
      .alignItems(HorizontalAlign.Start)
      .padding({ left: 20, right: 20, top: 12, bottom: 20 })

      Scroll() {
        Column({ space: 16 }) {
          // ===== 设备流转可视化卡片 =====
          Column({ space: 16 }) {
            this.SectionTitle('数据流转', 'DATA FLOW')

            // 设备连线动画
            Stack() {
              // 连接线
              Line({ width: 120, height: 2 })
                .startPoint([0, 28]).endPoint([120, 28])
                .stroke(this.state.networkAvailable ? colors.gold : colors.borderSub)
                .strokeWidth(1)
                .strokeDashArray(this.state.networkAvailable ? [] : [4, 4])
              // 本端设备
              Column({ space: 8 }) {
                Text(this.state.isPhone ? '📱' : '💻').fontSize(28)
                Text('本机').fontSize(12).fontColor(colors.textSecondary)
                Text(this.state.localDeviceName || '当前设备').fontSize(10).fontColor(colors.textTertiary).maxLines(1)
              }
              .position({ x: 0, y: 0 })
              .alignItems(HorizontalAlign.Center)

              // 金色粒子动效（同步时流动）
              if (this.state.status === SyncStatus.SYNCING) {
                Circle({ width: 6, height: 6 })
                  .fill(colors.gold)
                  .position({ x: (this.nowTick / 20) % 120, y: 26 })
                Circle({ width: 4, height: 4 })
                  .fill(colors.goldDim)
                  .position({ x: ((this.nowTick / 20) - 40 + 120) % 120, y: 26 })
              }

              // 远端设备
              Column({ space: 8 }) {
                Text(this.state.remoteDeviceName ? (this.state.remoteDeviceName.includes('Pad') || this.state.remoteDeviceName.includes('平板') ? '📟' : '📱') : '💻')
                  .fontSize(28).opacity(this.state.remoteDeviceName ? 1 : 0.3)
                Text(this.state.remoteDeviceName || '未发现设备').fontSize(12)
                  .fontColor(this.state.remoteDeviceName ? colors.textSecondary : colors.textTertiary)
                  .maxLines(1)
                Text(this.state.remoteDeviceName ? '已连接' : '等待组网')
                  .fontSize(10)
                  .fontColor(this.state.remoteDeviceName ? colors.era_hantang : colors.textTertiary)
              }
              .position({ x: '100%', y: 0 })
              .translate({ x: '-100%' })
              .alignItems(HorizontalAlign.Center)
            }
            .width('100%')
            .height(80)

            // 状态信息行
            Column({ space: 10 }) {
              Row() {
                this.StatusDot(
                  this.state.status === SyncStatus.SYNCING ? colors.gold :
                  this.state.status === SyncStatus.OFFLINE ? colors.textTertiary :
                  this.state.status === SyncStatus.ERROR ? colors.cinnabar :
                  colors.era_hantang
                )
                Text(this.statusText()).fontSize(13).fontColor(colors.textSecondary)
              }
              Row() {
                Text('最近同步').fontSize(12).fontColor(colors.textTertiary).width(80)
                Text(this.state.lastSyncTime > 0 ? DateUtil.formatRelative(this.state.lastSyncTime) : '尚未同步')
                  .fontSize(12).fontColor(colors.textSecondary).layoutWeight(1)
              }
              Row() {
                Text('可信设备').fontSize(12).fontColor(colors.textTertiary).width(80)
                Text(this.state.remoteDevices.length > 0 ? `已发现 ${this.state.remoteDevices.length} 台` : '暂无可同步设备')
                  .fontSize(12).fontColor(this.state.remoteDevices.length > 0 ? colors.era_hantang : colors.textSecondary)
                  .layoutWeight(1)
              }
              Row() {
                Text('待同步项').fontSize(12).fontColor(colors.textTertiary).width(80)
                Text(`${this.state.pendingCount} 条`)
                  .fontSize(12)
                  .fontColor(this.state.pendingCount > 0 ? colors.gold : colors.textSecondary)
                  .layoutWeight(1)
              }
              Row() {
                Text('冲突记录').fontSize(12).fontColor(colors.textTertiary).width(80)
                Text(`${this.state.conflictCount} 条`)
                  .fontSize(12)
                  .fontColor(this.state.conflictCount > 0 ? colors.cinnabar : colors.textSecondary)
                  .layoutWeight(1)
                if (this.state.conflictCount > 0) {
                  Text('查看')
                    .fontSize(11).fontColor(colors.gold)
                    .onClick((): void => { this.openConflictSheet(); })
                }
              }
            }
            .width('100%')
            .padding(16)
            .backgroundColor(colors.bgCard)
            .borderRadius(4)
            .border({ width: 1, color: colors.border })
          }
          .padding(20)
          .backgroundColor(colors.bgElevated)
          .borderRadius(4)

          // ===== 设备列表 =====
          Column({ space: 12 }) {
            this.SectionTitle('我的设备', 'DEVICES')
            this.DeviceCard(this.state.isPhone ? '📱' : '💻', this.state.localDeviceName || '当前设备', this.state.localDeviceType, true, true)
            if (this.state.remoteDevices && this.state.remoteDevices.length > 0) {
              ForEach(this.state.remoteDevices, (dev: RemoteDevice) => {
                this.DeviceCard(dev.deviceType.toLowerCase().includes('phone') ? '📱' : '📟',
                  dev.deviceName, dev.deviceType, false, dev.isOnline)
              })
            } else {
              Text('暂无同账号在线设备，请在同一华为账号的另一台设备上打开应用')
                .fontSize(12).fontColor(colors.textTertiary)
                .width('100%').textAlign(TextAlign.Center)
                .padding({ top: 8, bottom: 8 })
            }
          }
          .padding(20)
          .backgroundColor(colors.bgElevated)
          .borderRadius(4)

          // ===== 同步进度面板 =====
          Column({ space: 12 }) {
            this.SectionTitle('同步进度', 'SYNC PROGRESS')
            Column({ space: 8 }) {
              Row() {
                Text('数据同步').fontSize(12).fontColor(colors.textSecondary).layoutWeight(1)
                Text(`${this.state.progressPercent}%`).fontSize(12).fontColor(colors.gold)
              }
              Progress({ value: this.state.progressPercent, total: 100, type: ProgressType.Linear })
                .width('100%').height(4).color(colors.gold).backgroundColor(colors.borderSub)
              Text(this.state.status === SyncStatus.SYNCING ? '正在同步多端数据…' :
                this.state.lastSyncTime > 0 ? '最近一次同步已完成；设备上线后会继续同步' : '联网后将查找可信设备并同步')
                .fontSize(11).fontColor(colors.textTertiary)
            }
          }
          .padding(20)
          .backgroundColor(colors.bgElevated)
          .borderRadius(4)

          // ===== 操作按钮 =====
          Column({ space: 12 }) {
            Button('立即同步')
              .width('100%').height(46)
              .fontSize(14).fontColor(Color.White)
              .backgroundColor(colors.gold)
              .borderRadius(2)
              .enabled(this.state.status !== SyncStatus.SYNCING)
              .onClick((): void => { this.manualSync(); })

          }
          .padding(20)
          .backgroundColor(colors.bgElevated)
          .borderRadius(4)

          // ===== 同步说明 =====
          Column({ space: 12 }) {
            Text('同步说明')
              .fontSize(14).fontWeight(FontWeight.Medium).fontColor(colors.textPrimary)
            Text('· 登录同一华为账号的手机/平板可同步收藏、笔记、主题及主题关联')
              .fontSize(12).fontColor(colors.textSecondary)
            Text('· 冲突处理采用 LWW（Last-Writer-Wins）策略：以最新时间戳的版本为准，保证最终一致性')
              .fontSize(12).fontColor(colors.textSecondary)
            Text('· 离线编辑保存在本机；重新打开应用或手动同步时会重试')
              .fontSize(12).fontColor(colors.textSecondary)
            Text('· 基于鸿蒙分布式数据服务（DDBS），同步数据使用加密 KV 存储')
              .fontSize(12).fontColor(colors.textSecondary)
          }
          .alignItems(HorizontalAlign.Start)
          .padding(20)
          .backgroundColor(colors.bgElevated)
          .borderRadius(4)
          .margin({ bottom: 32 })
        }
        .padding({ left: 20, right: 20 })
      }
      .scrollBar(BarState.Off)
      .layoutWeight(1)
    }
    .width('100%').height('100%').backgroundColor(colors.bg)
    .bindSheet($$this.showConflictSheet, this.ConflictSheet(), {
      height: SheetSize.MEDIUM,
      dragBar: true,
      backgroundColor: colors.bgElevated,
      onDisappear: (): void => { this.showConflictSheet = false; }
    })
  }

  @Builder ConflictSheet() {
    Column({ space: 12 }) {
      Text('冲突记录').fontSize(18).fontWeight(FontWeight.Bold).fontColor(colors.textPrimary)
      Text(`共 ${this.state.conflictCount} 处冲突，已按「最新时间戳优先」自动保留最新版本`)
        .fontSize(12).fontColor(colors.textSecondary)
      Text('自动胜出版本已应用。你也可以查看两端内容并手动选择保留版本。')
        .fontSize(11).fontColor(colors.textTertiary)
        .padding(12)
        .backgroundColor(colors.gold10)
        .borderRadius(2)
      Scroll() {
        Column({ space: 10 }) {
          ForEach(this.conflicts, (conflict: SyncConflict) => {
            Column({ space: 8 }) {
              Text(`${conflict.entityType} · ${conflict.entityId}`)
                .fontSize(12).fontWeight(FontWeight.Medium).fontColor(colors.textPrimary)
              Text(`版本 A · ${conflict.localDeviceId} · ${DateUtil.formatRelative(conflict.localTimestamp)}${this.conflictWinner(conflict) === 'A' ? ' · 自动胜出' : ''}`)
                .fontSize(10).fontColor(colors.textSecondary)
              Text(this.conflictPreview(conflict.localData)).fontSize(11).fontColor(colors.textTertiary).maxLines(3)
              Text(`版本 B · ${conflict.remoteDeviceId} · ${DateUtil.formatRelative(conflict.remoteTimestamp)}${this.conflictWinner(conflict) === 'B' ? ' · 自动胜出' : ''}`)
                .fontSize(10).fontColor(colors.textSecondary)
              Text(this.conflictPreview(conflict.remoteData)).fontSize(11).fontColor(colors.textTertiary).maxLines(3)
              Row({ space: 8 }) {
                Button('保留版本 A').layoutWeight(1).height(34).fontSize(11)
                  .onClick((): void => { this.resolveConflict(conflict, true); })
                Button('采用版本 B').layoutWeight(1).height(34).fontSize(11)
                  .onClick((): void => { this.resolveConflict(conflict, false); })
              }
            }
            .width('100%').padding(12).backgroundColor(colors.bgCard).borderRadius(4)
          }, (conflict: SyncConflict) => conflict.id)
          if (this.conflicts.length === 0) {
            Text('当前没有未处理冲突记录').fontSize(12).fontColor(colors.textTertiary)
          }
        }
      }
      .layoutWeight(1)
      Button('知道了')
        .width('100%').height(44)
        .fontSize(14).fontColor(Color.White).backgroundColor(colors.gold).borderRadius(2)
        .onClick((): void => { this.showConflictSheet = false; })
    }
    .width('100%')
    .padding(20)
    .alignItems(HorizontalAlign.Start)
  }

  private openConflictSheet(): void {
    this.showConflictSheet = true;
    DistributedDataService.getInstance().listConflicts().then((items: SyncConflict[]) => {
      this.conflicts = items;
    });
  }

  private async resolveConflict(conflict: SyncConflict, useVersionA: boolean): Promise<void> {
    await DistributedDataService.getInstance().resolveConflict(conflict.id, useVersionA);
    this.conflicts = await DistributedDataService.getInstance().listConflicts();
    this.state = DistributedDataService.getInstance().getState();
  }

  private conflictWinner(conflict: SyncConflict): string {
    if (conflict.localTimestamp !== conflict.remoteTimestamp) {
      return conflict.localTimestamp > conflict.remoteTimestamp ? 'A' : 'B';
    }
    return conflict.localDeviceId.localeCompare(conflict.remoteDeviceId) > 0 ? 'A' : 'B';
  }

  private conflictPreview(json: string): string {
    try {
      const row = JSON.parse(json) as Record<string, Object>;
      const title = String(row.title ?? row.name ?? '');
      const content = String(row.content ?? row.note ?? '');
      const preview = title && content ? `${title}：${content}` :
        (title || content || JSON.stringify(row));
      return preview.length > 180 ? `${preview.slice(0, 180)}…` : preview;
    } catch (_) {
      return json.length > 180 ? `${json.slice(0, 180)}…` : json;
    }
  }

  private statusText(): string {
    if (!this.state.permissionGranted) return '请在系统设置中授权分布式数据同步，再点击立即同步';
    switch (this.state.status) {
      case SyncStatus.SYNCING: return '正在多端同步数据…';
      case SyncStatus.IDLE:
        return this.state.remoteDeviceName ? '已发现可信设备，可执行多端同步' : '单机运行中，发现可信设备后即可同步';
      case SyncStatus.CONFLICT: return `有 ${this.state.conflictCount} 条冲突记录，可查看两个版本`;
      case SyncStatus.OFFLINE: return '同步服务暂不可用，数据保留在本机待重试';
      case SyncStatus.ERROR: return '同步异常，请检查网络或账号状态';
      default: return '服务初始化中…';
    }
  }
}
