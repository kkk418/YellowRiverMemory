import { Site, Artifact, Poetry } from '../../model/entity/Entities';
import { CultureService } from '../../service/CultureService';
import { UserDataService } from '../../service/UserDataService';
import { SiteCard } from '../components/SiteCard';
import { ArtifactCard } from '../components/ArtifactCard';
import { EmptyState } from '../components/EmptyState';
import { colors } from '../../common/constants/Colors';
import { TagMeta } from '../../common/constants/AppMeta';

/**
 * 搜索结果页（无关键词时显示搜索历史+热门推荐）
 */
@Component
export struct SearchResultPage {
  @Prop initialKeyword: string = '';
  @Consume('navPathStack') navPathStack: NavPathStack;
  @State keyword: string = '';
  @State sites: Site[] = [];
  @State artifacts: Artifact[] = [];
  @State poetries: Poetry[] = [];
  @State activeTab: number = 0; // 0=全部 1=遗址 2=文物 3=诗词
  @State loading: boolean = false;
  @State searched: boolean = false;
  @State history: string[] = [];
  @State hotKeywords: string[] = ['仰韶文化', '殷墟', '龙门石窟', '二里头', '开封', '唐三彩', '汝窑', '甲骨文'];

  async aboutToAppear(): Promise<void> {
    this.keyword = this.initialKeyword;
    this.history = await UserDataService.getInstance().getSearchHistory();
    if (this.keyword) {
      await this.doSearch();
    }
  }

  async doSearch(kw?: string): Promise<void> {
    if (kw !== undefined) this.keyword = kw;
    const q = this.keyword.trim();
    if (!q) { this.searched = false; return; }
    this.loading = true;
    this.searched = true;
    try {
      const us = UserDataService.getInstance();
      await us.addSearchHistory(q);
      this.history = await us.getSearchHistory();
      const result = await CultureService.getInstance().searchAll(q, 30);
      this.sites = result.sites;
      this.artifacts = result.artifacts;
      this.poetries = result.poetries;
    } finally { this.loading = false; }
  }

  async clearHistory(): Promise<void> {
    await UserDataService.getInstance().clearSearchHistory();
    this.history = [];
  }

  private tapSite(s: Site): void {
    this.navPathStack.pushPath({ name: 'siteDetail', param: s });
  }

  private tapArtifact(a: Artifact): void {
    this.navPathStack.pushPath({ name: 'artifactDetail', param: a });
  }

  build() {
    Column({ space: 0 }) {
      // 搜索栏
      Row({ space: 8 }) {
        Text('‹').fontSize(22).fontColor(colors.gold).padding(8)
          .onClick((): void => { this.navPathStack.pop(); })
        Row({ space: 8 }) {
          Text('🔍').fontSize(14).fontColor(colors.textTertiary)
          TextInput({ text: this.keyword, placeholder: '搜索遗址、文物、诗词…' })
            .layoutWeight(1).backgroundColor(Color.Transparent).fontSize(14)
            .fontColor(colors.textPrimary).placeholderColor(colors.textTertiary)
            .onChange((v: string) => { this.keyword = v; })
            .onSubmit((): void => { this.doSearch(); })
            .height(36)
          if (this.keyword) {
            Text('✕').fontSize(14).fontColor(colors.textTertiary).padding(4)
              .onClick((): void => { this.keyword = ''; this.searched = false; this.sites = []; this.artifacts = []; this.poetries = []; })
          }
        }
        .layoutWeight(1).height(36).padding({ left: 12, right: 12 })
        .backgroundColor(colors.bgElevated).borderRadius(4)
        Text('搜索').fontSize(13).fontColor(colors.gold).padding(8)
          .onClick((): void => { this.doSearch(); })
      }
      .width('100%').padding({ left: 8, right: 16, top: 10, bottom: 10 })

      if (this.loading) {
        Column().layoutWeight(1).justifyContent(FlexAlign.Center) {
          LoadingProgress().width(30).height(30).color(colors.gold)
        }
      } else if (!this.searched) {
        // 未搜索：展示历史 + 热门 + 分类
        Scroll() {
          Column({ space: 24 }) {
            if (this.history.length > 0) {
              Column({ space: 12 }) {
                Row() {
                  Text('最近搜索').fontSize(14).fontColor(colors.textPrimary).fontWeight(FontWeight.Medium)
                  Blank()
                  Text('清空').fontSize(12).fontColor(colors.textTertiary)
                    .onClick((): void => { this.clearHistory(); })
                }
                .width('100%')
                Flex({ wrap: FlexWrap.Wrap }) {
                  ForEach(this.history, (kw: string) => {
                    Text(kw).fontSize(12).fontColor(colors.textSecondary)
                      .padding({ left: 12, right: 12, top: 6, bottom: 6 })
                      .backgroundColor(colors.bgCard).borderRadius(16)
                      .margin({ right: 8, bottom: 8 })
                      .border({ width: 0.5, color: colors.borderSub })
                      .onClick((): void => { this.doSearch(kw); })
                  })
                }
              }
              .alignItems(HorizontalAlign.Start).width('100%').padding({ left: 20, right: 20 })
            }

            // 热门关键词
            Column({ space: 12 }) {
              Text('热门搜索').fontSize(14).fontColor(colors.textPrimary).fontWeight(FontWeight.Medium)
              Flex({ wrap: FlexWrap.Wrap }) {
                ForEach(this.hotKeywords, (kw: string, idx: number) => {
                  Row({ space: 6 }) {
                    Text(`${idx + 1}`).fontSize(12).fontColor(idx < 3 ? colors.cinnabar : colors.gold).fontWeight(FontWeight.Bold)
                    Text(kw).fontSize(12).fontColor(colors.textSecondary)
                  }
                  .padding({ left: 12, right: 12, top: 7, bottom: 7 })
                  .backgroundColor(colors.bgCard).borderRadius(4)
                  .margin({ right: 8, bottom: 8 })
                  .onClick((): void => { this.doSearch(kw); })
                })
              }
            }
            .alignItems(HorizontalAlign.Start).width('100%').padding({ left: 20, right: 20 })

            // 按类别浏览
            Column({ space: 12 }) {
              Text('按年代浏览').fontSize(14).fontColor(colors.textPrimary).fontWeight(FontWeight.Medium)
              Flex({ wrap: FlexWrap.Wrap }) {
                ForEach(TagMeta.ERA_TAGS, (t: TagMeta) => {
                  Text(t.label).fontSize(12).fontColor(t.colorRes ?? colors.gold)
                    .padding({ left: 12, right: 12, top: 6, bottom: 6 })
                    .backgroundColor(colors.gold10).borderRadius(4)
                    .border({ width: 0.5, color: colors.goldDim })
                    .margin({ right: 8, bottom: 8 })
                    .onClick((): void => { this.doSearch(t.label); })
                })
              }
            }
            .alignItems(HorizontalAlign.Start).width('100%').padding({ left: 20, right: 20 })

            Column().height(40)
          }
          .width('100%').padding({ top: 8 })
        }
        .layoutWeight(1).scrollBar(BarState.Off)
      } else {
        // 有搜索结果
        Column({ space: 0 }) {
          Row({ space: 12 }) {
            Text(`"${this.keyword}"`).fontSize(13).fontColor(colors.gold)
            Text(`共 ${this.sites.length + this.artifacts.length + this.poetries.length} 条`)
              .fontSize(11).fontColor(colors.textTertiary)
          }
          .width('100%').padding({ left: 20, right: 20, bottom: 8, top: 4 })

          Row() {
            this.TabItem('全部', 0, this.sites.length + this.artifacts.length + this.poetries.length)
            this.TabItem('遗址', 1, this.sites.length)
            this.TabItem('文物', 2, this.artifacts.length)
            this.TabItem('诗词', 3, this.poetries.length)
          }
          .width('100%').padding({ left: 20, right: 20, bottom: 4 })
          Divider().color(colors.border).strokeWidth(0.5).width('100%')

          if (this.sites.length + this.artifacts.length + this.poetries.length === 0) {
            Column().layoutWeight(1).justifyContent(FlexAlign.Center) {
              EmptyState({ icon: '卷', title: '查无此卷', subtitle: `未找到与"${this.keyword}"相关的内容` })
            }
          } else {
            Scroll() {
              Column({ space: 12 }) {
                if (this.activeTab === 0 || this.activeTab === 1) {
                  if (this.sites.length > 0) this.SectionLabel(`文化遗址 · ${this.sites.length}`);
                  ForEach(this.filteredSites(), (s: Site) => {
                    SiteCard({ site: s, onTap: (): void => this.tapSite(s) })
                  })
                }
                if (this.activeTab === 0 || this.activeTab === 2) {
                  if (this.artifacts.length > 0) this.SectionLabel(`馆藏文物 · ${this.artifacts.length}`);
                  if (this.filteredArtifacts().length > 0) {
                    Grid() {
                      ForEach(this.filteredArtifacts(), (a: Artifact) => {
                        GridItem() { ArtifactCard({ artifact: a, onTap: (): void => this.tapArtifact(a) }) }
                      })
                    }
                    .columnsTemplate('1fr 1fr').columnsGap(10).rowsGap(10).width('100%')
                  }
                }
                if (this.activeTab === 0 || this.activeTab === 3) {
                  if (this.poetries.length > 0) this.SectionLabel(`题咏 · ${this.poetries.length}`);
                  ForEach(this.filteredPoetries(), (p: Poetry) => {
                    Column({ space: 6 }) {
                      Text(p.title).fontSize(14).fontColor(colors.gold)
                      if (p.author) Text(`〔${p.dynasty ?? ''}〕${p.author}`)
                        .fontSize(10).fontColor(colors.textTertiary)
                      Text(p.content).fontSize(12).fontColor(colors.textSecondary).lineHeight(1.8)
                        .maxLines(3).textOverflow({ overflow: TextOverflow.Ellipsis })
                    }
                    .width('100%').padding(14)
                    .backgroundColor(colors.bgCard).borderRadius(2)
                    .border({ width: 0.5, color: colors.border })
                  })
                }
                Column().height(40)
              }
              .width('100%').padding({ left: 16, right: 16, top: 12 })
            }
            .layoutWeight(1).scrollBar(BarState.Off)
          }
        }
        .layoutWeight(1)
      }
    }
    .width('100%').height('100%').backgroundColor(colors.bg)
  }

  private filteredSites(): Site[] {
    if (this.activeTab === 1) return this.sites;
    if (this.activeTab === 0) return this.sites.slice(0, 3);
    return [];
  }
  private filteredArtifacts(): Artifact[] {
    if (this.activeTab === 2) return this.artifacts;
    if (this.activeTab === 0) return this.artifacts.slice(0, 4);
    return [];
  }
  private filteredPoetries(): Poetry[] {
    if (this.activeTab === 3) return this.poetries;
    if (this.activeTab === 0) return this.poetries.slice(0, 2);
    return [];
  }

  @Builder
  TabItem(label: string, idx: number, count: number) {
    Column({ space: 4 }) {
      Row({ space: 6 }) {
        Text(label).fontSize(13)
          .fontColor(this.activeTab === idx ? colors.gold : colors.textTertiary)
          .fontWeight(this.activeTab === idx ? FontWeight.Medium : FontWeight.Regular)
        Text(`${count}`).fontSize(11)
          .fontColor(this.activeTab === idx ? colors.goldDim : colors.textTertiary)
      }
      Row().width(20).height(this.activeTab === idx ? 2 : 0)
        .backgroundColor(colors.gold).borderRadius(1)
    }
    .layoutWeight(1).padding({ top: 8, bottom: 8 }).alignItems(HorizontalAlign.Center)
    .onClick((): void => { this.activeTab = idx; })
  }

  @Builder
  SectionLabel(text: string) {
    Text(text).fontSize(11).fontColor(colors.textTertiary)
      .width('100%').padding({ top: 4, bottom: 8 })
  }
}
