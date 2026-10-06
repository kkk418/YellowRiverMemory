import { CultureService } from '../../service/CultureService';
import { Site, Artifact } from '../../model/entity/Entities';
import { SiteCard } from '../components/SiteCard';
import { ArtifactCard } from '../components/ArtifactCard';
import { TagChip } from '../components/TagChip';
import { EraMeta, CityMeta, SiteTypeMeta, ArtifactTypeMeta } from '../../common/constants/AppMeta';
import { EraType, CityType, SiteType, ArtifactType } from '../../common/constants/Enums';
import { FilterCriteria } from '../../model/dto/DTOs';
import { EmptyState } from '../components/EmptyState';
import { colors } from '../../common/constants/Colors';
import { Logger } from '../../common/utils/Logger';

interface FilterOption {
  key: string;
  label: string;
  color?: ResourceColor;
}
interface SearchParam { keyword: string; }

/**
 * 探索页：三维筛选（年代+类型+城市）+ 搜索 + 遗址/文物切换
 */
@Component
export struct BrowsePage {
  @Consume('navPathStack') navPathStack: NavPathStack;
  @State keyword: string = '';
  @State activeTab: number = 0; // 0=遗址 1=文物
  @State showFilterPanel: boolean = false;
  @State sites: Site[] = [];
  @State artifacts: Artifact[] = [];
  @State loading: boolean = true;
  @State loadingMore: boolean = false;
  @State loadError: boolean = false;
  @State moreError: boolean = false;
  @State siteHasMore: boolean = false;
  @State artifactHasMore: boolean = false;
  private sitePage: number = 1;
  private artifactPage: number = 1;
  private loadGeneration: number = 0;
  // 筛选状态（多选用Set）
  @State selectedEras: Set<string> = new Set();
  @State selectedTypes: Set<string> = new Set();
  @State selectedArtifactTypes: Set<string> = new Set();
  @State selectedCities: Set<string> = new Set();
  @State contentWidth: number = 390;

  private makePath(name: string, param?: Object): NavPathInfo {
    const info: NavPathInfo = { name: name };
    if (param !== undefined) info.param = param;
    return info;
  }
  private makeSearchPath(keyword: string): NavPathInfo {
    const param: SearchParam = { keyword: keyword };
    return this.makePath('searchResult', param);
  }

  async aboutToAppear() {
    await this.loadData();
  }

  async loadData() {
    const generation = ++this.loadGeneration;
    this.loading = true;
    this.loadingMore = false;
    this.loadError = false;
    this.moreError = false;
    this.sitePage = 1;
    this.artifactPage = 1;
    const criteria = this.currentCriteria();
    try {
      const svc = CultureService.getInstance();
      const siteRes = await svc.querySites(criteria, 1, 50);
      const artRes = await svc.queryArtifacts(criteria, 1, 50);
      if (generation !== this.loadGeneration) return;
      this.sites = siteRes.list;
      this.siteHasMore = siteRes.hasMore;
      this.artifacts = artRes.list;
      this.artifactHasMore = artRes.hasMore;
    } catch (e) {
      if (generation !== this.loadGeneration) return;
      Logger.error('BrowsePage', `loadData failed: ${e}`);
      this.loadError = true;
      this.sites = [];
      this.artifacts = [];
    }
    if (generation === this.loadGeneration) this.loading = false;
  }

  private currentCriteria(): FilterCriteria {
    return {
      keyword: this.keyword.trim() || undefined,
      era: this.selectedEras.size > 0 ? Array.from(this.selectedEras) as EraType[] : undefined,
      siteType: this.selectedTypes.size > 0 ? Array.from(this.selectedTypes) as SiteType[] : undefined,
      artifactType: this.selectedArtifactTypes.size > 0 ? Array.from(this.selectedArtifactTypes) as ArtifactType[] : undefined,
      city: this.selectedCities.size > 0 ? Array.from(this.selectedCities) as CityType[] : undefined,
    };
  }

  private async loadMore(): Promise<void> {
    if (this.loading || this.loadingMore) return;
    const generation = this.loadGeneration;
    const tab = this.activeTab;
    const criteria = this.currentCriteria();
    this.loadingMore = true;
    this.moreError = false;
    try {
      const svc = CultureService.getInstance();
      if (tab === 0 && this.siteHasMore) {
        const next = this.sitePage + 1;
        const result = await svc.querySites(criteria, next, 50);
        if (generation !== this.loadGeneration) return;
        this.sites = [...this.sites, ...result.list];
        this.sitePage = next;
        this.siteHasMore = result.hasMore;
      } else if (tab === 1 && this.artifactHasMore) {
        const next = this.artifactPage + 1;
        const result = await svc.queryArtifacts(criteria, next, 50);
        if (generation !== this.loadGeneration) return;
        this.artifacts = [...this.artifacts, ...result.list];
        this.artifactPage = next;
        this.artifactHasMore = result.hasMore;
      }
    } catch (e) {
      if (generation !== this.loadGeneration) return;
      Logger.error('BrowsePage', `loadMore failed: ${e}`);
      this.moreError = true;
    }
    if (generation === this.loadGeneration) this.loadingMore = false;
  }

  build() {
    Column() {
      // 1. 顶部标题 + 搜索
      Column({ space: 12 }) {
        Text('EXPLORE')
          .fontSize(10).letterSpacing(3).fontColor($r('app.color.gold_dim'))
        Text('探源')
          .fontSize(22).fontColor($r('app.color.text_gold')).fontWeight(FontWeight.Medium)
        // 搜索栏（点击/提交跳转搜索页）
        Row({ space: 8 }) {
          Text('🔍').fontSize(14).fontColor(colors.textTertiary)
          TextInput({ placeholder: '搜索遗址、文物、关键词…', text: this.keyword })
            .layoutWeight(1)
            .backgroundColor(Color.Transparent)
            .fontSize(13).fontColor(colors.textPrimary)
            .placeholderColor(colors.textTertiary)
            .onChange((v: string) => { this.keyword = v; })
            .onSubmit((): void => {
              const kw = this.keyword.trim();
              if (kw) this.navPathStack.pushPath(this.makeSearchPath(kw));
            })
            .height(36)
          if (this.keyword) {
            Text('✕').fontSize(14).fontColor(colors.textTertiary)
              .onClick((): void => { this.keyword = ''; this.loadData(); })
          }
          // 筛选按钮
          Button() {
            Text('☰').fontSize(16).fontColor(this.hasFilter() ? $r('app.color.text_gold') : $r('app.color.text_secondary'))
          }
          .type(ButtonType.Normal)
          .backgroundColor(this.hasFilter() ? $r('app.color.gold_20') : $r('app.color.input_bg'))
          .width(36).height(36)
          .borderRadius(2)
          .border({ width: 0.5, color: this.hasFilter() ? $r('app.color.gold_primary') : $r('app.color.input_border') })
          .onClick(() => { this.showFilterPanel = !this.showFilterPanel; })
        }
        .width('100%')
        .height(40)
        .padding({ left: 12, right: 6 })
        .backgroundColor($r('app.color.input_bg'))
        .borderRadius(2)
        .border({ width: 0.5, color: $r('app.color.input_border') })
      }
      .width('100%')
      .padding({ left: 20, right: 20, top: 20, bottom: 8 })
      .alignItems(HorizontalAlign.Start)

      // 2. Tab切换：遗址 / 文物
      Row() {
        this.TabItem('文化遗址', 0)
        this.TabItem('馆藏文物', 1)
      }
      .width('100%')
      .padding({ left: 20, right: 20 })

      Divider().color($r('app.color.ink_line')).strokeWidth(0.5).width('100%')

      // 3. 筛选面板
      if (this.showFilterPanel) {
        this.FilterPanel()
      }

      // 4. 结果列表
      if (this.loading) {
        Column() {
          Text('查阅中…').fontSize(12).fontColor($r('app.color.text_tertiary'))
        }
        .width('100%').layoutWeight(1).justifyContent(FlexAlign.Center)
      } else if (this.loadError) {
        Column({ space: 12 }) {
          Text('内容加载失败，请重试').fontSize(13).fontColor(colors.textSecondary)
          Button('重新加载').onClick(() => { this.loadData(); })
        }
        .width('100%').layoutWeight(1).justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
      } else {
        if (this.activeTab === 0) {
          this.SitesList()
        } else {
          this.ArtifactsGrid()
        }
      }
    }
    .width('100%').height('100%')
    .backgroundColor($r('app.color.ink_wall'))
    .onAreaChange((_oldArea: Area, newArea: Area): void => {
      this.contentWidth = Number(newArea.width);
    })
  }

  @Builder
  TabItem(label: string, idx: number) {
    Column({ space: 4 }) {
      Row({ space: 6 }) {
        Text(label)
          .fontSize(14)
          .fontColor(this.activeTab === idx ? $r('app.color.text_gold') : $r('app.color.text_tertiary'))
          .fontWeight(this.activeTab === idx ? FontWeight.Medium : FontWeight.Regular)
        Text(`${idx === 0 ? this.sites.length : this.artifacts.length}`)
          .fontSize(11)
          .fontColor(this.activeTab === idx ? $r('app.color.gold_dim') : $r('app.color.text_tertiary'))
      }
      Row()
        .width(28).height(this.activeTab === idx ? 2 : 0)
        .backgroundColor($r('app.color.gold_primary'))
        .borderRadius(1)
    }
    .layoutWeight(1)
    .padding({ top: 12, bottom: 10 })
    .alignItems(HorizontalAlign.Center)
    .onClick(() => { this.activeTab = idx; })
  }

  @Builder
  FilterPanel() {
    Column({ space: 14 }) {
      // 年代
      this.FilterGroup('年代', 'ERA',
        EraMeta.ALL.map((e: EraMeta): FilterOption => ({ key: e.code, label: e.name, color: e.colorRes })),
        this.selectedEras,
        (k: string): void => { this.toggleSet(this.selectedEras, k); })
      // 城市
      this.FilterGroup('城市', 'CITY',
        CityMeta.ALL.map((c: CityMeta): FilterOption => ({ key: c.code, label: c.name, color: c.colorRes })),
        this.selectedCities,
        (k: string): void => { this.toggleSet(this.selectedCities, k); })
      // 类型（仅遗址tab时显示类型）
      if (this.activeTab === 0) {
        this.FilterGroup('遗址类型', 'TYPE',
          SiteTypeMeta.ALL.map((t: SiteTypeMeta): FilterOption => ({ key: t.code, label: t.name })),
          this.selectedTypes,
          (k: string): void => { this.toggleSet(this.selectedTypes, k); })
      } else {
        this.FilterGroup('文物类型', 'TYPE',
          ArtifactTypeMeta.ALL.map((t: ArtifactTypeMeta): FilterOption => ({ key: t.key, label: t.label })),
          this.selectedArtifactTypes,
          (k: string): void => { this.toggleSet(this.selectedArtifactTypes, k); })
      }
      // 底部操作
      Row({ space: 12 }) {
        Button('清空筛选')
          .fontSize(12)
          .fontColor($r('app.color.text_secondary'))
          .backgroundColor($r('app.color.ink_wall_card'))
          .borderRadius(2)
          .layoutWeight(1)
          .height(38)
          .onClick(() => {
            this.selectedEras.clear();
            this.selectedCities.clear();
            this.selectedTypes.clear();
            this.selectedArtifactTypes.clear();
            this.showFilterPanel = false;
            this.loadData();
          })
        Button('确认')
          .fontSize(12)
          .fontColor($r('app.color.button_primary_text'))
          .backgroundColor($r('app.color.button_primary_bg'))
          .borderRadius(2)
          .layoutWeight(1)
          .height(38)
          .onClick(() => {
            this.showFilterPanel = false;
            this.loadData();
          })
      }
      .width('100%')
      .padding({ top: 4, bottom: 0 })
    }
    .width('100%')
    .padding({ left: 20, right: 20, top: 12, bottom: 16 })
    .backgroundColor($r('app.color.ink_wall_card'))
    .border({ width: { bottom: 1 }, color: $r('app.color.ink_line') })
  }

  @Builder
  FilterGroup(label: string, _en: string, options: FilterOption[],
    selected: Set<string>, onToggle: (k: string) => void) {
    Column({ space: 8 }) {
      Row({ space: 8 }) {
        Text(label).fontSize(12).fontColor($r('app.color.text_secondary')).width(56)
        Flex({ wrap: FlexWrap.Wrap }) {
          ForEach(options, (o: FilterOption) => {
            TagChip({
              label: o.label,
              selected: selected.has(o.key),
              onTap: () => { onToggle(o.key); }
            })
          })
        }
        .layoutWeight(1)
      }
      .width('100%')
      .alignItems(VerticalAlign.Top)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  SitesList() {
    if (this.sites.length === 0) {
      Column() {
        EmptyState({ icon: '索', title: '未得此卷', subtitle: '当前筛选下暂无遗址，放宽条件试试' })
      }
      .layoutWeight(1)
    } else {
      Scroll() {
        Column({ space: 16 }) {
          Grid() {
          ForEach(this.sites, (s: Site) => {
            GridItem() {
              SiteCard({ site: s, onTap: (): void => {
                this.navPathStack.pushPath({ name: 'siteDetail', param: s });
              } })
            }
          })
          }.columnsTemplate(this.contentWidth >= 600 ? '1fr 1fr' : '1fr')
            .columnsGap(16).rowsGap(16).width('100%')
          if (this.siteHasMore) {
            Button(this.loadingMore ? '加载中…' : (this.moreError ? '加载失败，重试' : '加载更多遗址'))
              .onClick(() => { this.loadMore(); })
          }
        }
        .width('100%')
        .padding({ left: 20, right: 20, top: 16, bottom: 40 })
      }
      .width('100%')
      .layoutWeight(1)
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring)
    }
  }

  @Builder
  ArtifactsGrid() {
    if (this.artifacts.length === 0) {
      Column() {
        EmptyState({ icon: '索', title: '未得此卷', subtitle: '当前筛选下暂无文物，放宽条件试试' })
      }
      .layoutWeight(1)
    } else {
      Scroll() {
        Column() {
          Grid() {
            ForEach(this.artifacts, (a: Artifact) => {
              GridItem() {
                ArtifactCard({ artifact: a, onTap: (): void => {
                  this.navPathStack.pushPath({ name: 'artifactDetail', param: a });
                } })
              }
            })
          }
          .columnsTemplate(this.contentWidth >= 1000 ? '1fr 1fr 1fr 1fr' :
            this.contentWidth >= 700 ? '1fr 1fr 1fr' : '1fr 1fr')
          .columnsGap(10)
          .rowsGap(12)
          if (this.artifactHasMore) {
            Button(this.loadingMore ? '加载中…' : (this.moreError ? '加载失败，重试' : '加载更多文物'))
              .margin({ top: 16 })
              .onClick(() => { this.loadMore(); })
          }
        }
        .width('100%')
        .padding({ left: 20, right: 20, top: 16, bottom: 40 })
      }
      .width('100%')
      .layoutWeight(1)
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring)
    }
  }

  private toggleSet(set: Set<string>, key: string) {
    if (set.has(key)) set.delete(key); else set.add(key);
    // 触发UI刷新：赋值新集合
    if (set === this.selectedEras) this.selectedEras = new Set(set);
    else if (set === this.selectedTypes) this.selectedTypes = new Set(set);
    else if (set === this.selectedArtifactTypes) this.selectedArtifactTypes = new Set(set);
    else if (set === this.selectedCities) this.selectedCities = new Set(set);
  }

  private hasFilter(): boolean {
    return this.selectedEras.size > 0 || this.selectedCities.size > 0 ||
      (this.activeTab === 0 ? this.selectedTypes.size > 0 : this.selectedArtifactTypes.size > 0);
  }
}
