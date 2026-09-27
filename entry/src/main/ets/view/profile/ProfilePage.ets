import { colors } from '../../common/constants/Colors';
import { UserDataService } from '../../service/UserDataService';
import { PreferencesHelper } from '../../common/utils/PreferencesHelper';
import { EventBus, AppEvents } from '../../common/utils/EventBus';
import { DateUtil } from '../../common/utils/DateUtil';

interface SectionHeaderProps {
  title: string;
  en: string;
}

/**
 * 我的页：用户统计 + 设置项
 */
@Component
export struct ProfilePage {
  @Consume('navPathStack') navPathStack: NavPathStack;
  @State favCount: number = 0;
  @State noteCount: number = 0;
  @State historyCount: number = 0;
  @State topicCount: number = 0;
  @State initVersion: number = 0;
  private onUserDataChange = (): void => { this.loadStats(); };

  aboutToAppear(): void {
    this.loadStats();
    EventBus.getInstance().on(AppEvents.FAVORITE_CHANGED, this.onUserDataChange);
    EventBus.getInstance().on(AppEvents.NOTE_CHANGED, this.onUserDataChange);
    EventBus.getInstance().on(AppEvents.TOPIC_CHANGED, this.onUserDataChange);
  }

  aboutToDisappear(): void {
    EventBus.getInstance().off(AppEvents.FAVORITE_CHANGED, this.onUserDataChange);
    EventBus.getInstance().off(AppEvents.NOTE_CHANGED, this.onUserDataChange);
    EventBus.getInstance().off(AppEvents.TOPIC_CHANGED, this.onUserDataChange);
  }

  private loadStats(): void {
    setTimeout(async () => {
      try {
        const svc = UserDataService.getInstance();
        const favs = await svc.listFavorites();
        const notes = await svc.listNotes();
        const topics = await svc.listTopics();
        const history = await svc.listHistory(100);
        this.favCount = favs.length;
        this.noteCount = notes.length;
        this.topicCount = topics.length;
        this.historyCount = history.length;
        this.initVersion = await PreferencesHelper.getDataVersion();
      } catch (e) { /* ignore */ }
    }, 30);
  }

  @Builder SectionHeader(header: SectionHeaderProps) {
    Row() {
      Text(header.en).fontSize(10).fontColor(colors.textTertiary).letterSpacing(2)
      Text('·').fontSize(10).fontColor(colors.textTertiary).margin({ left: 6, right: 6 })
      Text('PROFILE').fontSize(10).fontColor(colors.textTertiary).letterSpacing(2)
    }
    .margin({ bottom: 4 })
    Text(header.title).fontSize(28).fontWeight(FontWeight.Bold).fontColor(colors.textPrimary)
  }

  @Builder StatCell(num: number | string, label: string, en: string) {
    Column({ space: 4 }) {
      Text(`${num}`).fontSize(26).fontWeight(FontWeight.Bold).fontColor(colors.gold)
      Text(label).fontSize(12).fontColor(colors.textSecondary)
      Text(en).fontSize(9).fontColor(colors.textTertiary).letterSpacing(1)
    }
    .layoutWeight(1)
    .alignItems(HorizontalAlign.Center)
    .padding({ top: 16, bottom: 16 })
  }

  @Builder Divider() {
    Line().width('100%').height(1).backgroundColor(colors.border).margin({ top: 12, bottom: 12 })
  }

  @Builder SettingsItem(icon: string, label: string, onTap: () => void) {
    Row() {
      Text(icon).fontSize(18).fontColor(colors.gold).width(28)
      Text(label).fontSize(14).fontColor(colors.textPrimary).layoutWeight(1).margin({ left: 8 })
      Text('›').fontSize(18).fontColor(colors.textTertiary)
    }
    .width('100%')
    .height(52)
    .padding({ left: 4, right: 4 })
    .onClick(onTap)
  }

  build() {
    Column({ space: 0 }) {
      Scroll() {
        Column({ space: 20 }) {
          // 标题 + 用户卡
          Column({ space: 16 }) {
            this.SectionHeader({ title: '我的', en: 'MINE' })

            // 用户信息卡
            Row({ space: 16 }) {
              Stack({ alignContent: Alignment.Center }) {
                Circle({ width: 64, height: 64 })
                  .fill(colors.bgElevated)
                  .stroke(colors.gold).strokeWidth(1)
                Text('河')
                  .fontSize(28).fontWeight(FontWeight.Bold).fontColor(colors.gold)
                  .fontFamily('HarmonyOS Sans')
              }
              Column({ space: 6 }) {
                Text('文化探索者')
                  .fontSize(18).fontWeight(FontWeight.Medium).fontColor(colors.textPrimary)
                Text(`YELLOW RIVER · EXPLORER`)
                  .fontSize(9).fontColor(colors.textTertiary).letterSpacing(2)
                Text(`登录 ${this.historyCount > 0 ? DateUtil.formatRelative(Date.now() - 86400000) : '今日'}开始探索`)
                  .fontSize(11).fontColor(colors.textSecondary).margin({ top: 4 })
              }
              .alignItems(HorizontalAlign.Start)
              .layoutWeight(1)
            }
            .width('100%')
            .padding(16)
            .backgroundColor(colors.bgCard)
            .borderRadius(4)
            .border({ width: 1, color: colors.border })
          }

          // 统计数据
          Column() {
            Row({ space: 0 }) {
              this.StatCell(this.favCount, '收藏', 'FAVORITES')
              Column().width(1).height(36).backgroundColor(colors.border)
              this.StatCell(this.noteCount, '笔记', 'NOTES')
              Column().width(1).height(36).backgroundColor(colors.border)
              this.StatCell(this.topicCount, '主题', 'TOPICS')
              Column().width(1).height(36).backgroundColor(colors.border)
              this.StatCell(this.historyCount, '足迹', 'BROWSED')
            }
            .width('100%')
            .backgroundColor(colors.bgCard)
            .borderRadius(4)
            .border({ width: 1, color: colors.border })
          }

          // 设置分组
          Column({ space: 4 }) {
            Text('数据与同步').fontSize(12).fontColor(colors.textTertiary).margin({ left: 4, top: 8 })
            Column() {
              this.SettingsItem('☁️', '多端数据同步', (): void => {
                this.navPathStack.pushPath({ name: 'sync' });
              })
              this.SettingsItem('📚', '我的文化主题', (): void => {
                this.navPathStack.pushPath({ name: 'topic' });
              })
              this.SettingsItem('👣', '浏览足迹', (): void => {
                this.navPathStack.pushPath({ name: 'history' });
              })
            }
            .padding({ left: 16, right: 16 })
            .backgroundColor(colors.bgCard)
            .borderRadius(4)
            .border({ width: 1, color: colors.border })
          }

          Column({ space: 4 }) {
            Text('应用信息').fontSize(12).fontColor(colors.textTertiary).margin({ left: 4, top: 8 })
            Column() {
              Text(`黄河记忆 v1.0.0 · 预置数据 v${this.initVersion}`)
                .fontSize(12).fontColor(colors.textSecondary)
              Text('文化档案与个人研学记录')
                .fontSize(11).fontColor(colors.textTertiary)
            }
            .alignItems(HorizontalAlign.Start)
            .padding({ left: 16, right: 16 })
            .backgroundColor(colors.bgCard)
            .borderRadius(4)
            .border({ width: 1, color: colors.border })
          }

          // 页脚
          Column({ space: 4 }) {
            Text('黄河记忆 · YELLOW RIVER MEMORY')
              .fontSize(10).fontColor(colors.textTertiary).letterSpacing(2)
            Text('探寻河南黄河沿线八千年文明脉络')
              .fontSize(11).fontColor(colors.textTertiary)
          }
          .width('100%')
          .alignItems(HorizontalAlign.Center)
          .padding({ top: 20, bottom: 40 })
        }
        .padding({ left: 20, right: 20, top: 12, bottom: 20 })
      }
      .scrollBar(BarState.Off)
      .layoutWeight(1)
    }
    .width('100%').height('100%').backgroundColor(colors.bg)
  }
}
