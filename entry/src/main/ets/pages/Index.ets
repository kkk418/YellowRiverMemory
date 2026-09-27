import { HomePage } from '../view/home/HomePage';
import { BrowsePage } from '../view/browse/BrowsePage';
import { CollectionPage } from '../view/collection/CollectionPage';
import { SyncPage } from '../view/sync/SyncPage';
import { ProfilePage } from '../view/profile/ProfilePage';
import { SiteDetailPage } from '../view/detail/SiteDetailPage';
import { ArtifactDetailPage } from '../view/detail/ArtifactDetailPage';
import { SearchResultPage } from '../view/browse/SearchResultPage';
import { NoteListPage } from '../view/note/NoteListPage';
import { NoteEditorPage, NoteEditorParams } from '../view/note/NoteEditorPage';
import { HistoryPage } from '../view/history/HistoryPage';
import { TopicPage } from '../view/topic/TopicPage';
import { SyncStatusBar } from '../view/components/SyncStatusBar';
import { PreferencesHelper } from '../common/utils/PreferencesHelper';
import { ThemeMode } from '../common/constants/Enums';
import { Logger } from '../common/utils/Logger';
import { colors } from '../common/constants/Colors';
import { Site, Artifact } from '../model/entity/Entities';

const TAG = 'Index';

interface TabItem {
  label: string;
  icon: string;
}

interface SearchParams {
  keyword: string;
}

/**
 * 黄河记忆·根页面
 * Tab：首页 / 探源 / 笔记 / 收藏 / 我的
 * 路由：siteDetail/artifactDetail/searchResult/noteEditor/noteList/history
 */
@Entry
@Component
struct Index {
  @State currentTab: number = 0;
  @Provide('navPathStack') navPathStack: NavPathStack = new NavPathStack();
  @State themeMode: ThemeMode = ThemeMode.INK;
  @State splashDone: boolean = false;

  private tabs: TabItem[] = [
    { label: '首页', icon: '⌂' },
    { label: '探源', icon: '◎' },
    { label: '笔记', icon: '✎' },
    { label: '收藏', icon: '★' },
    { label: '我的', icon: '◉' },
  ];

  async aboutToAppear(): Promise<void> {
    this.themeMode = await PreferencesHelper.getThemeMode();
    Logger.info(TAG, `Index ready, theme=${this.themeMode}`);
    setTimeout(() => { this.splashDone = true; }, 1800);
  }

  build() {
    if (!this.splashDone) {
      // ===== 启动屏 =====
      Column({ space: 20 }) {
        Column({ space: 8 }) {
          Text('河').fontSize(72).fontWeight(FontWeight.Bold)
            .fontColor(colors.gold)
            .fontFamily('serif')
          Text('YELLOW RIVER MEMORY').fontSize(10).fontColor(colors.textTertiary).letterSpacing(4)
          Text('· 黄河记忆 ·').fontSize(14).fontColor(colors.goldDim).letterSpacing(6)
        }
        .alignItems(HorizontalAlign.Center)
        Column({ space: 6 }) {
          Text('探寻河南黄河沿线八千年文明脉络')
            .fontSize(11).fontColor(colors.textTertiary)
          Text('仰韶 · 龙山 · 夏商 · 周 · 汉唐 · 宋')
            .fontSize(10).fontColor(colors.textTertiary).letterSpacing(2)
        }
        .alignItems(HorizontalAlign.Center)
        .margin({ top: 24 })
        LoadingProgress()
          .width(28).height(28).color(colors.gold)
          .margin({ top: 32 })
      }
      .width('100%').height('100%')
      .justifyContent(FlexAlign.Center)
      .backgroundColor(colors.bg)
    } else {
      Column({ space: 0 }) {
        SyncStatusBar()
        Navigation(this.navPathStack) {
          Tabs({ barPosition: BarPosition.End }) {
            TabContent() { HomePage() }.tabBar(this.TabBar(0))
            TabContent() { BrowsePage() }.tabBar(this.TabBar(1))
            TabContent() { NoteListPage() }.tabBar(this.TabBar(2))
            TabContent() { CollectionPage() }.tabBar(this.TabBar(3))
            TabContent() { ProfilePage() }.tabBar(this.TabBar(4))
          }
          .barHeight(58)
          .barBackgroundColor(colors.bgCard)
          .scrollable(false)
          .width('100%').layoutWeight(1)
          .onChange((index: number) => { this.currentTab = index; })
          .divider({ strokeWidth: '0.5px', color: colors.border })
        }
        .hideTitleBar(true).hideToolBar(true)
        .navDestination(this.destinationBuilder)
        .mode(NavigationMode.Stack)
        .layoutWeight(1)
        .backgroundColor(colors.bg)
      }
      .width('100%').height('100%')
      .backgroundColor(colors.bg)
    }
  }

  @Builder
  TabBar(idx: number) {
    Column({ space: 3 }) {
      Text(this.tabs[idx].icon)
        .fontSize(idx === 2 ? 22 : 20)
        .fontColor(this.currentTab === idx ? colors.gold : colors.textTertiary)
      Text(this.tabs[idx].label)
        .fontSize(10)
        .fontColor(this.currentTab === idx ? colors.gold : colors.textTertiary)
    }
    .width('100%').height('100%').justifyContent(FlexAlign.Center)
  }

  @Builder
  destinationBuilder(name: string, param?: Object) {
    if (name === 'siteDetail') {
      NavDestination() {
        SiteDetailPage({ site: param as Site })
      }
      .hideTitleBar(true).backgroundColor(colors.bg)
    } else if (name === 'artifactDetail') {
      NavDestination() {
        ArtifactDetailPage({ artifact: param as Artifact })
      }
      .hideTitleBar(true).backgroundColor(colors.bg)
    } else if (name === 'searchResult') {
      NavDestination() {
        SearchResultPage({ initialKeyword: param ? (param as SearchParams).keyword : '' })
      }
      .hideTitleBar(true).backgroundColor(colors.bg)
    } else if (name === 'noteEditor') {
      NavDestination() {
        NoteEditorPage({ params: param ? (param as NoteEditorParams) : {} })
      }
      .hideTitleBar(true).backgroundColor(colors.bg)
    } else if (name === 'noteList') {
      NavDestination() { NoteListPage() }
      .hideTitleBar(true).backgroundColor(colors.bg)
    } else if (name === 'history') {
      NavDestination() { HistoryPage() }
      .hideTitleBar(true).backgroundColor(colors.bg)
    } else if (name === 'sync') {
      NavDestination() { SyncPage() }
      .hideTitleBar(true).backgroundColor(colors.bg)
    } else if (name === 'topic') {
      NavDestination() { TopicPage() }
      .hideTitleBar(true).backgroundColor(colors.bg)
    } else {
      NavDestination() {
        Column() {
          Text('页面未找到').fontSize(14).fontColor(colors.textSecondary)
        }
        .width('100%').height('100%').justifyContent(FlexAlign.Center)
        .backgroundColor(colors.bg)
      }
      .hideTitleBar(true).backgroundColor(colors.bg)
    }
  }
}
