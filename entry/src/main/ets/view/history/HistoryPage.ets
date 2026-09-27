import { Site, Artifact, HistoryRecord, Note } from '../../model/entity/Entities';
import { CultureService } from '../../service/CultureService';
import { UserDataService } from '../../service/UserDataService';
import { FavoriteTargetType } from '../../common/constants/Enums';
import { EraMeta, CityMeta } from '../../common/constants/AppMeta';
import { colors } from '../../common/constants/Colors';
import { DateUtil } from '../../common/utils/DateUtil';
import { EmptyState } from '../components/EmptyState';

interface HistoryItem {
  rec: HistoryRecord;
  site?: Site;
  art?: Artifact;
}

interface HistoryGroup {
  title: string;
  items: HistoryItem[];
}

/**
 * 浏览历史页（按日期分组）
 */
@Component
export struct HistoryPage {
  @Consume('navPathStack') navPathStack: NavPathStack;
  @State groups: HistoryGroup[] = [];
  @State loading: boolean = true;
  @State isEmpty: boolean = false;

  private itemEra(it: HistoryItem): EraMeta | undefined {
    return it.site ? EraMeta.getByCode(it.site.era) : it.art ? EraMeta.getByCode(it.art.era) : undefined;
  }
  private itemCity(it: HistoryItem): CityMeta | undefined {
    return it.site ? CityMeta.getByCode(it.site.city) : undefined;
  }
  private itemName(it: HistoryItem): string { return it.site ? it.site.name : it.art ? it.art.name : ''; }
  private itemSummary(it: HistoryItem): string { return it.site ? it.site.summary : it.art ? it.art.description : ''; }

  aboutToAppear(): void { this.load(); }

  private async load(): Promise<void> {
    this.loading = true;
    try {
      const records = await UserDataService.getInstance().listHistory(100);
      const cs = CultureService.getInstance();
      const all: HistoryItem[] = [];
      for (const r of records) {
        if (r.targetType === FavoriteTargetType.SITE) {
          const s = await cs.getSiteById(r.targetId);
          if (s) all.push({ rec: r, site: s });
        } else if (r.targetType === FavoriteTargetType.ARTIFACT) {
          const a = await cs.getArtifactById(r.targetId);
          if (a) all.push({ rec: r, art: a });
        }
      }
      this.isEmpty = all.length === 0;
      // 按日期分组：今天/昨天/近7天/近30天/更早
      const now = DateUtil.now();
      const todayStart = DateUtil.startOfDay(now);
      const yesterdayStart = todayStart - 86400000;
      const weekAgo = now - 7 * 86400000;
      const monthAgo = now - 30 * 86400000;
      const buckets: Record<string, HistoryItem[]> = {
        '今天': [], '昨天': [], '近七天': [], '近一月': [], '更早': []
      };
      for (const it of all) {
        const t = it.rec.lastViewedAt;
        if (t >= todayStart) buckets['今天'].push(it);
        else if (t >= yesterdayStart) buckets['昨天'].push(it);
        else if (t >= weekAgo) buckets['近七天'].push(it);
        else if (t >= monthAgo) buckets['近一月'].push(it);
        else buckets['更早'].push(it);
      }
      this.groups = [];
      ['今天', '昨天', '近七天', '近一月', '更早'].forEach(k => {
        if (buckets[k].length > 0) this.groups.push({ title: k, items: buckets[k] });
      });
    } finally { this.loading = false; }
  }

  private async clearAll(): Promise<void> {
    await UserDataService.getInstance().clearHistory();
    this.groups = [];
    this.isEmpty = true;
  }

  private tapItem(it: HistoryItem): void {
     if (it.site) this.navPathStack.pushPath({ name: 'siteDetail', param: it.site } as NavPathInfo);
     else if (it.art) this.navPathStack.pushPath({ name: 'artifactDetail', param: it.art } as NavPathInfo);
  }

  @Builder
  itemView(it: HistoryItem) {
    Row({ space: 12 }) {
      // 年代色方块
      Column() {
        Text(this.itemEra(it)?.label?.charAt(0) ?? '?').fontSize(16).fontColor(colors.bg)
          .fontWeight(FontWeight.Bold)
      }
      .width(48).height(48).justifyContent(FlexAlign.Center).alignItems(HorizontalAlign.Center)
      .backgroundColor(this.itemEra(it)?.colorRes ?? colors.goldDim).borderRadius(4)

      Column({ space: 4 }) {
        Row() {
          Text(this.itemName(it)).fontSize(15).fontColor(colors.textPrimary)
            .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).layoutWeight(1)
          if (it.art?.isNationalTreasure === 1) {
            Text('国宝').fontSize(9).fontColor(colors.bg)
              .padding({ left: 5, right: 5, top: 1, bottom: 1 })
              .backgroundColor(colors.cinnabar).borderRadius(2).margin({ left: 6 })
          }
        }
        Text(this.itemSummary(it)).fontSize(12).fontColor(colors.textSecondary)
          .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
        Row({ space: 6 }) {
          Text(this.itemEra(it)?.label ?? '').fontSize(10).fontColor(colors.gold)
          if (this.itemCity(it)) {
            Text('·').fontSize(10).fontColor(colors.textTertiary)
            Text(this.itemCity(it)!.label).fontSize(10).fontColor(colors.textTertiary)
          }
          Text('·').fontSize(10).fontColor(colors.textTertiary)
          Text(`浏览${it.rec.viewCount}次`).fontSize(10).fontColor(colors.textTertiary)
          Text('·').fontSize(10).fontColor(colors.textTertiary)
          Text(DateUtil.formatRelative(it.rec.lastViewedAt)).fontSize(10).fontColor(colors.textTertiary)
        }
      }
      .layoutWeight(1).alignItems(HorizontalAlign.Start)

      Text('›').fontSize(18).fontColor(colors.textTertiary)
    }
    .width('100%').padding({ left: 16, right: 16, top: 14, bottom: 14 })
    .onClick((): void => this.tapItem(it))
  }

  build() {
    Column({ space: 0 }) {
      // 顶栏
      Row() {
        Text('‹').fontSize(22).fontColor(colors.gold).padding(8)
          .onClick((): void => { this.navPathStack.pop(); })
        Text('浏览足迹').fontSize(18).fontColor(colors.textPrimary).fontWeight(FontWeight.Medium).layoutWeight(1)
        if (!this.isEmpty) {
          Text('清空').fontSize(13).fontColor(colors.textTertiary).padding(8)
             .onClick((): void => { this.clearAll(); })
        }
      }
      .width('100%').height(52).padding({ left: 8, right: 16 })
      .alignItems(VerticalAlign.Center)

      Divider().color(colors.border).strokeWidth(0.5)

      if (this.loading) {
        Column().layoutWeight(1).justifyContent(FlexAlign.Center) {
          LoadingProgress().width(30).height(30).color(colors.gold)
        }
      } else if (this.isEmpty) {
        Column().layoutWeight(1).justifyContent(FlexAlign.Center) {
          EmptyState({ icon: '🏛️', title: '暂无浏览记录', subtitle: '开始探源黄河文明，你的足迹将在这里留存' })
        }
      } else {
        Scroll() {
          Column({ space: 0 }) {
            ForEach(this.groups, (g: HistoryGroup) => {
              Column({ space: 0 }) {
                Text(g.title).fontSize(13).fontColor(colors.gold)
                  .padding({ left: 16, right: 16, top: 18, bottom: 8 })
                Column({ space: 0 }) {
                  ForEach(g.items, (it: HistoryItem) => {
                    this.itemView(it)
                    Divider().color(colors.border).strokeWidth(0.5).margin({ left: 76 })
                  })
                }
                .backgroundColor(colors.bgCard)
                .borderRadius(4)
                .margin({ left: 16, right: 16 })
              }
              .width('100%')
              .alignItems(HorizontalAlign.Start)
            })
            // 底部留白
            Column().height(24)
          }
        }
        .layoutWeight(1).scrollBar(BarState.Off)
      }
    }
    .width('100%').height('100%').backgroundColor(colors.bg)
  }
}
