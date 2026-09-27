import { Site, Artifact, Poetry, Note } from '../../model/entity/Entities';
import { CultureService, DiscoveryItem, HistoricalEventItem } from '../../service/CultureService';
import { UserDataService } from '../../service/UserDataService';
import { RecommendationService, RecommendItem } from '../../service/RecommendationService';
import { EraMeta, CityMeta, SiteTypeMeta } from '../../common/constants/AppMeta';
import { SiteCard } from '../components/SiteCard';
import { ArtifactCard } from '../components/ArtifactCard';
import { LoadingIndicator } from '../components/LoadingIndicator';
import { FavoriteTagSheet } from '../components/FavoriteTagSheet';
import { FavoriteTargetType, NoteTargetType } from '../../common/constants/Enums';
import { colors } from '../../common/constants/Colors';
import { StringUtil } from '../../common/utils/StringUtil';
import { DateUtil } from '../../common/utils/DateUtil';
import { EventBus, AppEvents } from '../../common/utils/EventBus';

/**
 * 遗址详情页（数字敦煌洞窟详情风格）
 */
@Component
export struct SiteDetailPage {
  @Consume('navPathStack') navPathStack: NavPathStack;
  @Prop site: Site | null = null;
  @State artifacts: Artifact[] = [];
  @State poetries: Poetry[] = [];
  @State relatedSites: RecommendItem[] = [];
  @State notes: Note[] = [];
  @State isFav: boolean = false;
  @State loading: boolean = true;
  @State discoveries: DiscoveryItem[] = [];
  @State events: HistoricalEventItem[] = [];
  @State favSheetName: string = '';
  @State favSheetTags: string[] = [];
  private siteEra(): EraMeta | undefined { return this.site ? EraMeta.getByCode(this.site.era) : undefined; }
  private siteCity(): CityMeta | undefined { return this.site ? CityMeta.getByCode(this.site.city) : undefined; }
  private siteType(): SiteTypeMeta | undefined { return this.site ? SiteTypeMeta.getByCode(this.site.type) : undefined; }
  private onNoteChange = (): void => { this.loadNotes(); };
  private onFavoriteChange = (_data?: Object | null): void => {
    if (this.site) {
      this.isFav = UserDataService.getInstance().isFavoritedSync(FavoriteTargetType.SITE, this.site.id);
    }
  };
  favSheetCtrl: CustomDialogController = new CustomDialogController({
    builder: FavoriteTagSheet({
      targetName: this.favSheetName,
      selectedTags: this.favSheetTags,
      onConfirm: (tags: string[]) => this.confirmFav(tags),
    }),
    alignment: DialogAlignment.Bottom,
    customStyle: true,
    autoCancel: true,
  });

  aboutToAppear(): void {
    EventBus.getInstance().on(AppEvents.NOTE_CHANGED, this.onNoteChange);
    EventBus.getInstance().on(AppEvents.FAVORITE_CHANGED, this.onFavoriteChange);
    setTimeout(() => this.loadAll(), 30);
  }

  aboutToDisappear(): void {
    EventBus.getInstance().off(AppEvents.NOTE_CHANGED, this.onNoteChange);
    EventBus.getInstance().off(AppEvents.FAVORITE_CHANGED, this.onFavoriteChange);
  }

  private async loadAll(): Promise<void> {
    if (!this.site) return;
    this.loading = true;
    try {
      const s = this.site;
      const cs = CultureService.getInstance();
      const us = UserDataService.getInstance();
      const results = await Promise.all([
        cs.getArtifactsBySite(s.id),
        cs.getPoetriesBySite(s.id),
        RecommendationService.getInstance().getRelatedSites(s, 4),
      ]);
      this.artifacts = results[0];
      this.poetries = results[1];
      this.relatedSites = results[2];
      this.discoveries = cs.parseDiscoveries(s);
      this.events = cs.parseHistoricalEvents(s);
      this.isFav = us.isFavoritedSync(FavoriteTargetType.SITE, s.id);
      await us.addHistory(FavoriteTargetType.SITE, s.id);
      await cs.incrementView('site', s.id);
      await this.loadNotes();
    } finally {
      this.loading = false;
    }
  }

  private async loadNotes(): Promise<void> {
    if (!this.site) return;
    this.notes = await UserDataService.getInstance().getNotesForTarget(NoteTargetType.SITE, this.site.id);
  }

  private async toggleFav(): Promise<void> {
    if (!this.site) return;
    if (this.isFav) {
      // 取消收藏
      await UserDataService.getInstance().toggleFavorite(FavoriteTargetType.SITE, this.site.id);
      this.isFav = false;
      EventBus.getInstance().emit(AppEvents.FAVORITE_CHANGED, { targetType: 'site', targetId: this.site.id, favorited: false });
    } else {
      // 首次收藏：弹出标签选择Sheet
      this.favSheetName = this.site.name;
      this.favSheetTags = [];
      this.favSheetCtrl.open();
    }
  }

  private async confirmFav(tags: string[]): Promise<void> {
    if (!this.site) return;
    const us = UserDataService.getInstance();
    await us.addFavorite(FavoriteTargetType.SITE, this.site.id, tags);
    this.isFav = true;
    us.reloadFavCache();
    EventBus.getInstance().emit(AppEvents.FAVORITE_CHANGED, { targetType: 'site', targetId: this.site.id, favorited: true });
  }

  private goNote(n?: Note): void {
    const params: Record<string, Object> = {};
    if (n) {
      params['noteId'] = n.id;
    } else {
      params['targetType'] = NoteTargetType.SITE;
      params['targetId'] = this.site!.id;
      params['targetName'] = this.site!.name;
    }
    this.navPathStack.pushPath({ name: 'noteEditor', param: params });
  }

  private goArtifact(a: Artifact): void {
    this.navPathStack.pushPath({ name: 'artifactDetail', param: a });
  }

  private goSite(s: Site): void {
    this.navPathStack.pushPath({ name: 'siteDetail', param: s });
  }

  private back(): void {
    this.navPathStack.pop();
  }

  @Builder SectionTitle(title: string, en: string) {
    Column({ space: 6 }) {
      Row() {
        Text(en).fontSize(9).fontColor(colors.textTertiary).letterSpacing(2)
        Text('·').fontSize(9).fontColor(colors.textTertiary).margin({ left: 5, right: 5 })
        Text('SECTION').fontSize(9).fontColor(colors.textTertiary).letterSpacing(2)
      }
      Text(title).fontSize(18).fontWeight(FontWeight.Bold).fontColor(colors.textPrimary)
      Divider().color(colors.gold).width(28).height(1)
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
    .padding({ bottom: 8 })
  }

  @Builder InfoRow(label: string, value: string, labelColor: ResourceColor = colors.gold) {
    Row({ space: 12 }) {
      Text(label).fontSize(12).fontColor(labelColor).width(64).textAlign(TextAlign.End)
      Text(value).fontSize(13).fontColor(colors.textSecondary).layoutWeight(1)
    }
    .width('100%')
  }

  build() {
    Stack() {
      if (this.loading) {
        LoadingIndicator()
      } else if (!this.site) {
        Column() {
          Text('文卷未寻')
            .fontSize(18).fontColor(colors.textTertiary)
          Text('返回').fontSize(13).fontColor(colors.gold).margin({ top: 16 })
            .onClick((): void => this.back())
        }.width('100%').height('100%').justifyContent(FlexAlign.Center)
      } else {
        Scroll() {
          Column({ space: 0 }) {
            // ===== 1. 全宽封面图 =====
            Stack({ alignContent: Alignment.BottomStart }) {
              // 占位色块（无图时）
              Column().width('100%').height(300).linearGradient({
                angle: 180,
                colors: [[this.siteEra()?.colorRes ?? colors.goldDim, 0], [colors.bg, 1]]
              })
              // 金色渐入遮罩
              Column().width('100%').height(120)
                .linearGradient({ angle: 0, colors: [[Color.Transparent, 0], [colors.bg, 1]] })
            }
            .width('100%').height(300)

            // ===== 2. 标题区 =====
            Column({ space: 8 }) {
              Text(this.siteEra()?.enName ?? '').fontSize(10).fontColor(colors.gold).letterSpacing(4)
              Text(this.site!.name).fontSize(28).fontWeight(FontWeight.Bold).fontColor(colors.textPrimary)
              if (this.site!.nameEn) {
                Text(this.site!.nameEn).fontSize(11).fontColor(colors.textTertiary).letterSpacing(1)
              }
              Divider().color(colors.gold).width(32).height(1).margin({ top: 8, bottom: 4 })
              Text(this.site!.summary).fontSize(13).fontColor(colors.textSecondary).lineHeight(22)
            }
            .width('100%')
            .padding({ left: 24, right: 24, top: -40, bottom: 20 })
            .alignItems(HorizontalAlign.Start)

            // ===== 3. 信息牌 =====
            Column({ space: 8 }) {
              this.InfoRow('年代', this.siteEra()?.label ?? this.site!.era)
              this.InfoRow('所在城市', this.siteCity()?.label ?? this.site!.city)
              this.InfoRow('遗址类型', this.siteType()?.label ?? this.site!.type)
              if (this.site!.yearStart) {
                this.InfoRow('纪年', this.site!.yearEnd && this.site!.yearEnd !== this.site!.yearStart ?
                  `${DateUtil.formatYear(this.site!.yearStart)} — ${DateUtil.formatYear(this.site!.yearEnd)}` :
                  DateUtil.formatYear(this.site!.yearStart))
              }
            }
            .width('100%')
            .padding(16)
            .backgroundColor(colors.bgCard)
            .borderRadius(2)
            .border({ width: 0.5, color: colors.border })
            .margin({ left: 24, right: 24, bottom: 24 })

            // ===== 4. 概述 =====
            if (this.site!.overview) {
              Column({ space: 12 }) {
                this.SectionTitle('历史源流', 'OVERVIEW')
                Text(this.site!.overview).fontSize(14).fontColor(colors.textSecondary).lineHeight(24)
              }
              .width('100%')
              .padding({ left: 24, right: 24, bottom: 24 })
              .alignItems(HorizontalAlign.Start)
            }

            // ===== 5. 考古发现 =====
            if (this.discoveries.length > 0) {
              Column({ space: 12 }) {
                this.SectionTitle('考古发现', 'DISCOVERIES')
                Column({ space: 10 }) {
                  ForEach(this.discoveries, (d: DiscoveryItem) => {
                    Column({ space: 6 }) {
                      if (d.title) {
                        Text(d.title).fontSize(14).fontColor(colors.gold).fontWeight(FontWeight.Medium)
                      }
                      Text(d.desc).fontSize(12).fontColor(colors.textSecondary).lineHeight(22)
                    }
                    .width('100%')
                    .padding(12)
                    .backgroundColor(colors.bgElevated)
                    .borderRadius(2)
                  })
                }
              }
              .width('100%')
              .padding({ left: 24, right: 24, bottom: 24 })
              .alignItems(HorizontalAlign.Start)
            }

            // ===== 6. 历史事件时间线 =====
            if (this.events.length > 0) {
              Column({ space: 12 }) {
                this.SectionTitle('历史年轮', 'CHRONICLE')
                Column({ space: 0 }) {
                  ForEach(this.events, (ev: HistoricalEventItem, idx: number) => {
                    Row({ space: 12 }) {
                      Column({ space: 4 }) {
                        Text(ev.year).fontSize(11).fontColor(colors.gold).width(80).textAlign(TextAlign.End)
                        Stack() { Circle().width(8).height(8).fill(colors.gold) }.width(80)
                      }.alignItems(HorizontalAlign.End)
                      Column().width(1).height('100%').backgroundColor(colors.goldDim)
                        .visibility(idx === this.events.length - 1 ? Visibility.Hidden : Visibility.Visible)
                        .position({ x: 84, y: 16 })
                      Column({ space: 4 }) {
                        Text(ev.event).fontSize(13).fontColor(colors.textPrimary).lineHeight(20)
                      }
                      .layoutWeight(1).alignItems(HorizontalAlign.Start).padding({ bottom: 20 })
                    }.width('100%').alignItems(VerticalAlign.Top)
                  })
                }
              }
              .width('100%').padding({ left: 24, right: 24, bottom: 24 })
              .alignItems(HorizontalAlign.Start)
            }

            // ===== 7. 诗词 =====
            if (this.poetries.length > 0) {
              Column({ space: 16 }) {
                this.SectionTitle('题咏', 'POETRY')
                ForEach(this.poetries, (p: Poetry) => {
                  Column({ space: 10 }) {
                    Text(p.title).fontSize(16).fontColor(colors.gold).fontWeight(FontWeight.Medium)
                    if (p.author) {
                      Text(p.dynasty ? `〔${p.dynasty}〕${p.author}` : p.author)
                        .fontSize(11).fontColor(colors.textTertiary)
                    }
                    Divider().color(colors.goldDim).strokeWidth(0.5).width(30)
                    Text(p.content).fontSize(15).fontColor(colors.textPrimary).lineHeight(30)
                      .textAlign(TextAlign.Center).width('100%').padding({ top: 8, bottom: 8 })
                    if (p.translation) {
                      Text(p.translation).fontSize(11).fontColor(colors.textTertiary).lineHeight(20)
                    }
                  }
                  .width('100%').padding(16).backgroundColor(colors.bgCard)
                  .borderRadius(2).border({ width: 0.5, color: colors.border })
                  .alignItems(HorizontalAlign.Center)
                })
              }
              .width('100%').padding({ left: 24, right: 24, bottom: 24 })
              .alignItems(HorizontalAlign.Start)
            }

            // ===== 8. 笔记模块 =====
            Column({ space: 12 }) {
              Row() {
                Column({ space: 4 }) {
                  Text('MY NOTES').fontSize(9).fontColor(colors.textTertiary).letterSpacing(2)
                  Text('我的笔记').fontSize(18).fontWeight(FontWeight.Bold).fontColor(colors.textPrimary)
                }
                .alignItems(HorizontalAlign.Start).layoutWeight(1)
                Button('+ 写笔记')
                  .fontSize(12).fontColor(colors.bg).backgroundColor(colors.gold)
                  .height(32).borderRadius(2)
                  .onClick((): void => this.goNote())
              }
              .width('100%')
              Divider().color(colors.gold).width(28).height(1).margin({ bottom: 4 })

              if (this.notes.length === 0) {
                Column({ space: 8 }) {
                  Text('✍️').fontSize(28).opacity(0.4)
                  Text('尚未为此遗址记录笔记').fontSize(12).fontColor(colors.textTertiary)
                  Text('记录你的探访见闻、研究思考').fontSize(11).fontColor(colors.textTertiary)
                }
                .width('100%').padding({ top: 20, bottom: 20 })
                .alignItems(HorizontalAlign.Center)
              } else {
                ForEach(this.notes, (n: Note) => {
                  Column({ space: 6 }) {
                    Row() {
                      Text(n.title || '无题').fontSize(14).fontColor(colors.textPrimary)
                        .fontWeight(FontWeight.Medium).maxLines(1)
                        .textOverflow({ overflow: TextOverflow.Ellipsis }).layoutWeight(1)
                      Text(DateUtil.formatDateTime(n.updatedAt).substring(5, 16))
                        .fontSize(10).fontColor(colors.textTertiary)
                    }.width('100%')
                    Text(n.content).fontSize(12).fontColor(colors.textSecondary)
                      .maxLines(3).textOverflow({ overflow: TextOverflow.Ellipsis }).lineHeight(20)
                    if (StringUtil.parseTagsArray(n.tags).length > 0) {
                      Row({ space: 6 }) {
                        ForEach(StringUtil.parseTagsArray(n.tags).slice(0, 4), (t: string) => {
                          Text(`# ${t}`).fontSize(10).fontColor(colors.textTertiary)
                        })
                      }
                    }
                  }
                  .width('100%').padding(12)
                  .backgroundColor(colors.bgElevated).borderRadius(2)
                  .margin({ bottom: 8 })
                  .onClick((): void => this.goNote(n))
                }, (n: Note) => n.id)
              }
            }
            .width('100%').padding({ left: 24, right: 24, bottom: 24 })
            .alignItems(HorizontalAlign.Start)

            // ===== 9. 馆藏文物 =====
            if (this.artifacts.length > 0) {
              Column({ space: 12 }) {
                this.SectionTitle('馆藏文物', `ARTIFACTS · ${this.artifacts.length}`)
                Grid() {
                  ForEach(this.artifacts, (a: Artifact) => {
                    GridItem() {
                      ArtifactCard({ artifact: a, onTap: (): void => this.goArtifact(a) })
                    }
                  })
                }
                .columnsTemplate('1fr 1fr').columnsGap(10).rowsGap(10).width('100%')
              }
              .width('100%').padding({ left: 24, right: 24, bottom: 24 })
              .alignItems(HorizontalAlign.Start)
            }

            // ===== 10. 文旅信息 =====
            if (this.site!.travelInfo) {
              Column({ space: 12 }) {
                this.SectionTitle('今日往矣', 'VISIT TODAY')
                Text(this.site!.travelInfo).fontSize(12).fontColor(colors.textSecondary).lineHeight(22)
                  .width('100%').padding(16).backgroundColor(colors.gold10).borderRadius(2)
                  .border({ width: 0.5, color: colors.goldDim })
              }
              .width('100%').padding({ left: 24, right: 24, bottom: 24 })
              .alignItems(HorizontalAlign.Start)
            }

            // ===== 11. 相关推荐 =====
            if (this.relatedSites.length > 0) {
              Column({ space: 12 }) {
                this.SectionTitle('文脉相连', 'RELATED')
                ForEach(this.relatedSites, (ri: RecommendItem) => {
                  Column({ space: 6 }) {
                    SiteCard({ site: ri.item as Site, onTap: (): void => this.goSite(ri.item as Site) })
                    Text(ri.reason)
                      .fontSize(10).fontColor(colors.gold)
                      .padding({ left: 8, top: 2, bottom: 2 })
                  }
                  .width('100%')
                  .alignItems(HorizontalAlign.Start)
                })
              }
              .width('100%').padding({ left: 24, right: 24, bottom: 40 })
              .alignItems(HorizontalAlign.Start)
            }

            // ===== 页脚 =====
            Column({ space: 6 }) {
              Text('黄河记忆 · YELLOW RIVER MEMORY')
                .fontSize(9).fontColor(colors.textTertiary).letterSpacing(2)
              Text('探寻河南黄河沿线八千年文明脉络')
                .fontSize(10).fontColor(colors.textTertiary)
            }.width('100%').padding({ top: 20, bottom: 32 }).alignItems(HorizontalAlign.Center)
          }
        }
        .scrollBar(BarState.Off).edgeEffect(EdgeEffect.Spring).width('100%').height('100%')

        // ===== 悬浮顶部操作栏 =====
        Column() {
          Row() {
            Text('‹').fontSize(26).fontColor(colors.gold).padding(12)
              .onClick((): void => this.back())
            BlanKSpacer()
            Text(this.isFav ? '★' : '☆').fontSize(22).fontColor(this.isFav ? colors.gold : colors.textSecondary)
              .padding(12).onClick((): void => { this.toggleFav(); })
            Text('✍').fontSize(18).fontColor(colors.gold).padding(12)
              .onClick((): void => this.goNote())
          }
          .width('100%').height(56)
        }
        .width('100%').position({ x: 0, y: 0 })
      }
    }
    .width('100%').height('100%').backgroundColor(colors.bg)
  }
}

@Component
struct BlanKSpacer {
  build() { Blank().layoutWeight(1) }
}
