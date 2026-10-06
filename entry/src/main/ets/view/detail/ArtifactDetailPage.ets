import { Artifact, Site, Note } from '../../model/entity/Entities';
import { CultureService } from '../../service/CultureService';
import { UserDataService } from '../../service/UserDataService';
import { RecommendationService, RecommendItem } from '../../service/RecommendationService';
import { EraMeta, ArtifactTypeMeta, CityMeta } from '../../common/constants/AppMeta';
import { SiteCard } from '../components/SiteCard';
import { ArtifactCard } from '../components/ArtifactCard';
import { LoadingIndicator } from '../components/LoadingIndicator';
import { FavoriteTagSheet } from '../components/FavoriteTagSheet';
import { FavoriteTargetType, NoteTargetType } from '../../common/constants/Enums';
import { colors } from '../../common/constants/Colors';
import { LicensedCover } from '../components/LicensedCover';
import { StringUtil } from '../../common/utils/StringUtil';
import { DateUtil } from '../../common/utils/DateUtil';
import { EventBus, AppEvents } from '../../common/utils/EventBus';
import { Logger } from '../../common/utils/Logger';

/**
 * 文物详情页
 */
@Component
export struct ArtifactDetailPage {
  @Consume('navPathStack') navPathStack: NavPathStack;
  @Prop artifact: Artifact | null = null;
  @State site: Site | null = null;
  @State notes: Note[] = [];
  @State isFav: boolean = false;
  @State favBusy: boolean = false;
  @State favError: string = '';
  @State loading: boolean = true;
  @State loadError: boolean = false;
  @State relatedSites: RecommendItem[] = [];
  @State favSheetName: string = '';
  private artifactEra(): EraMeta | undefined { return this.artifact ? EraMeta.getByCode(this.artifact.era) : undefined; }
  private artifactType(): ArtifactTypeMeta | undefined { return this.artifact ? ArtifactTypeMeta.getByCode(this.artifact.type) : undefined; }
  private onNoteChange = (): void => { this.loadNotes(); };
  private onFavoriteChange = (_data?: Object | null): void => {
    if (this.artifact) {
      this.isFav = UserDataService.getInstance().isFavoritedSync(FavoriteTargetType.ARTIFACT, this.artifact.id);
    }
  };
  favSheetCtrl: CustomDialogController = new CustomDialogController({
    builder: FavoriteTagSheet({
      targetName: this.favSheetName,
      onConfirm: (tags: string[]) => this.confirmFav(tags),
    }),
    alignment: DialogAlignment.Bottom, customStyle: true, autoCancel: true,
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
    if (!this.artifact) {
      this.loading = false;
      return;
    }
    this.loading = true;
    this.loadError = false;
    try {
      const a = this.artifact;
      const cs = CultureService.getInstance();
      const us = UserDataService.getInstance();
      if (a.siteId) this.site = cs.getSiteByIdSync(a.siteId);
      this.relatedSites = await RecommendationService.getInstance().getRelatedArtifacts(a, 4);
      this.isFav = us.isFavoritedSync(FavoriteTargetType.ARTIFACT, a.id);
      await this.loadNotes();
      try {
        await us.addHistory(FavoriteTargetType.ARTIFACT, a.id);
        await cs.incrementView('artifact', a.id);
      } catch (e) {
        Logger.warn('ArtifactDetailPage', `browse count update failed: ${e}`);
      }
    } catch (e) {
      Logger.error('ArtifactDetailPage', `loadAll failed: ${e}`);
      this.loadError = true;
    } finally {
      this.loading = false;
    }
  }

  private async loadNotes(): Promise<void> {
    if (!this.artifact) return;
    this.notes = await UserDataService.getInstance().getNotesForTarget(NoteTargetType.ARTIFACT, this.artifact.id);
  }

  private async toggleFav(): Promise<void> {
    if (!this.artifact || this.favBusy) return;
    this.favError = '';
    if (!this.isFav) {
      this.favSheetName = this.artifact.name;
      this.favSheetCtrl.open();
      return;
    }
    this.favBusy = true;
    try {
      await UserDataService.getInstance().removeFavorite(FavoriteTargetType.ARTIFACT, this.artifact.id);
      this.isFav = false;
    } catch (e) {
      Logger.error('ArtifactDetailPage', `remove favorite failed: ${e}`);
      this.favError = '取消收藏失败，请重试。';
    } finally {
      this.favBusy = false;
    }
  }

  private async confirmFav(tags: string[]): Promise<void> {
    if (!this.artifact || this.favBusy) return;
    this.favBusy = true;
    this.favError = '';
    try {
      await UserDataService.getInstance().addFavorite(FavoriteTargetType.ARTIFACT, this.artifact.id, tags);
      this.isFav = true;
    } catch (e) {
      Logger.error('ArtifactDetailPage', `add favorite failed: ${e}`);
      this.favError = '收藏失败，请重试。';
    } finally {
      this.favBusy = false;
    }
  }

  private goNote(n?: Note): void {
    const params: Record<string, Object> = {};
    if (n) params['noteId'] = n.id;
    else {
      params['targetType'] = NoteTargetType.ARTIFACT;
      params['targetId'] = this.artifact!.id;
      params['targetName'] = this.artifact!.name;
    }
    this.navPathStack.pushPath({ name: 'noteEditor', param: params });
  }

  private goSite(s: Site): void {
    this.navPathStack.pushPath({ name: 'siteDetail', param: s });
  }

  private goArtifact(a: Artifact): void {
    this.navPathStack.pushPath({ name: 'artifactDetail', param: a });
  }

  private back(): void { this.navPathStack.pop(); }

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
    .alignItems(HorizontalAlign.Start).width('100%').padding({ bottom: 8 })
  }

  @Builder InfoRow(label: string, value: string, labelColor: ResourceColor = colors.gold) {
    Row({ space: 12 }) {
      Text(label).fontSize(12).fontColor(labelColor).width(72).textAlign(TextAlign.End)
      Text(value).fontSize(13).fontColor(colors.textSecondary).layoutWeight(1)
    }.width('100%')
  }

  build() {
    Stack() {
      if (this.loading) {
        LoadingIndicator()
      } else if (!this.artifact) {
        Column() {
          Text('文卷未寻').fontSize(18).fontColor(colors.textTertiary)
          Text('返回').fontSize(13).fontColor(colors.gold).margin({ top: 16 }).onClick((): void => this.back())
        }.width('100%').height('100%').justifyContent(FlexAlign.Center)
      } else if (this.loadError) {
        Column({ space: 14 }) {
          Text('文物内容加载失败').fontSize(18).fontColor(colors.textPrimary)
          Text('请重试；若问题持续，请保留设备日志以便排查。')
            .fontSize(12).fontColor(colors.textSecondary).textAlign(TextAlign.Center)
          Button('重新加载').onClick((): void => { this.loadAll(); })
          Text('返回').fontSize(13).fontColor(colors.gold)
            .onClick((): void => this.back())
        }
        .width('100%').height('100%').padding(24)
        .justifyContent(FlexAlign.Center).alignItems(HorizontalAlign.Center)
      } else {
        Scroll() {
          Column({ space: 0 }) {
            // 封面
            Stack({ alignContent: Alignment.BottomStart }) {
              LicensedCover({ path: this.artifact!.coverImage ?? '',
                tint: this.artifact!.isNationalTreasure ? colors.cinnabar : this.artifactEra()?.colorRes ?? colors.goldDim })
                .width('100%').height(320)
              if (this.artifact!.isNationalTreasure) {
                Text('国  宝')
                  .fontSize(10).fontColor(Color.White).letterSpacing(4)
                  .padding({ left: 10, right: 10, top: 4, bottom: 4 })
                  .backgroundColor(colors.cinnabar).borderRadius(2)
                  .position({ x: 24, y: 24 })
              }
              Column().width('100%').height(120)
                .linearGradient({ angle: 0, colors: [[Color.Transparent, 0], [colors.bg, 1]] })
            }.width('100%').height(320)

            // 标题
            Column({ space: 8 }) {
              Text(this.artifactEra()?.enName ?? '').fontSize(10).fontColor(colors.gold).letterSpacing(4)
              Text(this.artifact!.name).fontSize(26).fontWeight(FontWeight.Bold).fontColor(colors.textPrimary)
              if (this.artifact!.nameEn) Text(this.artifact!.nameEn).fontSize(11).fontColor(colors.textTertiary).letterSpacing(1)
              Divider().color(colors.gold).width(32).height(1).margin({ top: 8, bottom: 4 })
              Text(this.artifact!.description).fontSize(13).fontColor(colors.textSecondary).lineHeight(22)
            }
            .width('100%').padding({ left: 24, right: 24, top: -40, bottom: 20 })
            .alignItems(HorizontalAlign.Start)

            // 信息牌
            Column({ space: 8 }) {
              this.InfoRow('年代', this.artifactEra()?.label ?? this.artifact!.era)
              this.InfoRow('类别', this.artifactType()?.label ?? this.artifact!.type)
              if (this.artifact!.material) this.InfoRow('材质', this.artifact!.material)
              if (this.artifact!.size) this.InfoRow('规格', this.artifact!.size)
              if (this.artifact!.level) this.InfoRow('等级', this.artifact!.level, colors.cinnabar)
              if (this.artifact!.location) this.InfoRow('馆藏', this.artifact!.location)
              if (this.site) {
                Row({ space: 12 }) {
                  Text('出土地').fontSize(12).fontColor(colors.gold).width(72).textAlign(TextAlign.End)
                  Text(this.site.name).fontSize(13).fontColor(colors.gold)
                    .onClick((): void => this.goSite(this.site!))
                  Text('›').fontSize(14).fontColor(colors.gold)
                }.width('100%')
              }
            }
            .width('100%').padding(16).backgroundColor(colors.bgCard).borderRadius(2)
            .border({ width: 0.5, color: colors.border })
            .margin({ left: 24, right: 24, bottom: 24 })

            // 笔记模块
            Column({ space: 12 }) {
              Row() {
                Column({ space: 4 }) {
                  Text('MY NOTES').fontSize(9).fontColor(colors.textTertiary).letterSpacing(2)
                  Text('我的笔记').fontSize(18).fontWeight(FontWeight.Bold).fontColor(colors.textPrimary)
                }.alignItems(HorizontalAlign.Start).layoutWeight(1)
                Button('+ 写笔记').fontSize(12).fontColor(colors.bg).backgroundColor(colors.gold)
                  .height(32).borderRadius(2).onClick((): void => this.goNote())
              }.width('100%')
              Divider().color(colors.gold).width(28).height(1).margin({ bottom: 4 })

              if (this.notes.length === 0) {
                Column({ space: 8 }) {
                  Text('✍️').fontSize(28).opacity(0.4)
                  Text('记录对这件文物的观察与思考').fontSize(12).fontColor(colors.textTertiary)
                }.width('100%').padding({ top: 20, bottom: 20 }).alignItems(HorizontalAlign.Center)
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
                  }.width('100%').padding(12).backgroundColor(colors.bgElevated).borderRadius(2)
                    .margin({ bottom: 8 }).onClick((): void => this.goNote(n))
                }, (n: Note) => n.id)
              }
            }
            .width('100%').padding({ left: 24, right: 24, bottom: 24 })
            .alignItems(HorizontalAlign.Start)

            // 同期文明
            if (this.relatedSites.length > 0) {
              Column({ space: 12 }) {
                this.SectionTitle('同期文明', 'CONTEMPORARY')
                ForEach(this.relatedSites, (ri: RecommendItem) => {
                  Column({ space: 4 }) {
                    if (ri.type === 'site') {
                      SiteCard({ site: ri.item as Site, onTap: (): void => this.goSite(ri.item as Site) })
                    } else {
                      ArtifactCard({ artifact: ri.item as Artifact, onTap: (): void => this.goArtifact(ri.item as Artifact) })
                    }
                    Text(ri.reason).fontSize(10).fontColor(colors.gold).padding({ left: 8 })
                  }
                  .width('100%').alignItems(HorizontalAlign.Start)
                })
              }
              .width('100%').padding({ left: 24, right: 24, bottom: 40 })
              .alignItems(HorizontalAlign.Start)
            }

            // 页脚
            Column({ space: 6 }) {
              Text('黄河记忆 · YELLOW RIVER MEMORY')
                .fontSize(9).fontColor(colors.textTertiary).letterSpacing(2)
              Text('探寻河南黄河沿线八千年文明脉络')
                .fontSize(10).fontColor(colors.textTertiary)
            }.width('100%').padding({ top: 20, bottom: 32 }).alignItems(HorizontalAlign.Center)
          }
          .constraintSize({ maxWidth: 960 })
          .alignSelf(ItemAlign.Center)
        }
        .scrollBar(BarState.Off).edgeEffect(EdgeEffect.Spring).width('100%').height('100%')

        // 悬浮顶栏
        Column() {
          Row() {
            Text('‹').fontSize(26).fontColor(colors.gold).padding(12).onClick((): void => this.back())
            Blank().layoutWeight(1)
            Text(this.favBusy ? '…' : (this.isFav ? '★' : '☆'))
              .fontSize(22).fontColor(this.isFav ? colors.gold : colors.textSecondary)
              .padding(12).onClick((): void => { this.toggleFav(); })
            Text('✍').fontSize(18).fontColor(colors.gold).padding(12)
              .onClick((): void => this.goNote())
          }.width('100%').height(56)
          if (this.favError) {
            Text(this.favError).fontSize(12).fontColor(colors.cinnabar)
              .backgroundColor(colors.bgCard).padding({ left: 16, right: 16, bottom: 8 })
          }
        }.width('100%').position({ x: 0, y: 0 })
      }
    }
    .width('100%').height('100%').backgroundColor(colors.bg)
  }
}
