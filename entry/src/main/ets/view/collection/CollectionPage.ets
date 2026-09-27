import { colors } from '../../common/constants/Colors';
import { AppEvents, EventBus } from '../../common/utils/EventBus';
import { Favorite, Site, Artifact } from '../../model/entity/Entities';
import { UserDataService } from '../../service/UserDataService';
import { CultureService } from '../../service/CultureService';
import { SiteCard } from '../components/SiteCard';
import { ArtifactCard } from '../components/ArtifactCard';
import { EmptyState } from '../components/EmptyState';
import { StringUtil } from '../../common/utils/StringUtil';
import { TagMeta } from '../../common/constants/AppMeta';

interface TagGroup {
  name: string;
  count: number;
  color: ResourceColor;
}

interface FirstTag {
  name: string;
  color: ResourceColor;
}

/**
 * 收藏页：按标签分组展示
 */
@Component
export struct CollectionPage {
  @Consume('navPathStack') navPathStack: NavPathStack;
  @State collections: Favorite[] = [];
  @State tagGroups: TagGroup[] = [];
  @State selectedTag: string = '全部';
  @State isLoading: boolean = true;
  @State showRemoveConfirm: boolean = false;
  @State pendingRemove: Favorite | null = null;
  private onFavoriteChange = (): void => { this.loadData(); };

  aboutToAppear(): void {
    this.loadData();
    EventBus.getInstance().on(AppEvents.FAVORITE_CHANGED, this.onFavoriteChange);
  }

  aboutToDisappear(): void {
    EventBus.getInstance().off(AppEvents.FAVORITE_CHANGED, this.onFavoriteChange);
  }

  private loadData(): void {
    this.isLoading = true;
    setTimeout(async () => {
      try {
        const svc = UserDataService.getInstance();
        this.collections = await svc.listFavorites();
        const tagMap = new Map<string, number>();
        tagMap.set('全部', this.collections.length);
        let untagged = 0;
        for (const f of this.collections) {
          const tags = StringUtil.parseTagsArray(f.tags);
          if (tags.length === 0) untagged++;
          for (const t of tags) tagMap.set(t, (tagMap.get(t) || 0) + 1);
        }
        if (untagged > 0) tagMap.set('未分类', untagged);
        const groups: TagGroup[] = [];
        for (const entry of tagMap) {
          const name = entry[0];
          const count = entry[1];
          let color: ResourceColor = colors.gold;
          for (const meta of TagMeta.ALL) {
            if (meta.code === name || meta.label === name) {
              color = meta.colorRes ?? colors.gold;
              break;
            }
          }
          groups.push({ name, count, color });
        }
        this.tagGroups = groups;
        if (!this.tagGroups.find(g => g.name === this.selectedTag)) {
          this.selectedTag = '全部';
        }
      } finally {
        this.isLoading = false;
      }
    }, 30);
  }

  private getFilteredList(): Favorite[] {
    if (this.selectedTag === '全部') return this.collections;
    if (this.selectedTag === '未分类') {
      return this.collections.filter(c => StringUtil.parseTagsArray(c.tags).length === 0);
    }
    return this.collections.filter(c => StringUtil.parseTagsArray(c.tags).includes(this.selectedTag));
  }

  private resolveSite(c: Favorite): Site | null {
    if (c.targetType !== 'site') return null;
    return CultureService.getInstance().getSiteByIdSync?.(c.targetId) ?? null;
  }

  private resolveArtifact(c: Favorite): Artifact | null {
    if (c.targetType !== 'artifact') return null;
    return CultureService.getInstance().getArtifactByIdSync?.(c.targetId) ?? null;
  }

  private openDetail(c: Favorite): void {
    if (c.targetType === 'site') {
      const s = this.resolveSite(c);
      if (s) this.navPathStack.pushPath({ name: 'siteDetail', param: s });
    } else {
      const a = this.resolveArtifact(c);
      if (a) this.navPathStack.pushPath({ name: 'artifactDetail', param: a });
    }
  }

  private confirmRemove(c: Favorite): void {
    this.pendingRemove = c;
    this.showRemoveConfirm = true;
  }

  private async doRemove(): Promise<void> {
    if (!this.pendingRemove) return;
    const svc = UserDataService.getInstance();
    await svc.removeFavorite(this.pendingRemove.targetType, this.pendingRemove.targetId);
    this.pendingRemove = null;
    this.showRemoveConfirm = false;
    this.loadData();
  }

  private firstTagName(c: Favorite): FirstTag | null {
    const tags = StringUtil.parseTagsArray(c.tags);
    if (tags.length === 0) return null;
    const t = tags[0];
    for (const m of TagMeta.ALL) {
      if (m.code === t || m.label === t) return { name: t, color: m.colorRes ?? colors.gold };
    }
    return { name: t, color: colors.gold };
  }

  @Builder ItemView(c: Favorite) {
    Stack({ alignContent: Alignment.TopEnd }) {
      if (c.targetType === 'site') {
        if (this.resolveSite(c)) {
          SiteCard({ site: this.resolveSite(c)!, onTap: (): void => this.openDetail(c) })
        }
      } else {
        if (this.resolveArtifact(c)) {
          ArtifactCard({ artifact: this.resolveArtifact(c)!, onTap: (): void => this.openDetail(c) })
        }
      }
      if (this.firstTagName(c)) {
        Text(this.firstTagName(c)!.name)
          .fontSize(10)
          .fontColor(colors.bgCard)
          .backgroundColor(this.firstTagName(c)!.color)
          .padding({ left: 8, right: 8, top: 3, bottom: 3 })
          .margin({ top: 12, right: 12 })
          .borderRadius(2)
      }
    }
    .width('100%')
    .margin({ bottom: 16 })
    .gesture(LongPressGesture().onAction((): void => {
      this.confirmRemove(c);
    }))
  }

  build() {
    Column({ space: 0 }) {
      Column({ space: 4 }) {
        Row() {
          Text('COLLECTION')
            .fontSize(10)
            .fontColor(colors.textTertiary)
            .fontFamily('HarmonyOS Sans')
            .letterSpacing(3)
          Text('·').fontSize(10).fontColor(colors.textTertiary).margin({ left: 6, right: 6 })
          Text('典藏').fontSize(10).fontColor(colors.textTertiary).letterSpacing(3)
        }
        Text('我的收藏')
          .fontSize(28)
          .fontWeight(FontWeight.Bold)
          .fontColor(colors.textPrimary)
      }
      .alignItems(HorizontalAlign.Start)
      .padding({ left: 20, right: 20, top: 12, bottom: 16 })

      // Tag bar
      Scroll() {
        Row({ space: 4 }) {
          ForEach(this.tagGroups, (g: TagGroup) => {
            Column({ space: 4 }) {
              Text(g.name)
                .fontSize(14)
                .fontWeight(this.selectedTag === g.name ? FontWeight.Medium : FontWeight.Regular)
                .fontColor(this.selectedTag === g.name ? colors.gold : colors.textSecondary)
              Text(`${g.count}`)
                .fontSize(10)
                .fontColor(this.selectedTag === g.name ? colors.gold : colors.textTertiary)
            }
            .padding({ left: 14, right: 14, top: 8, bottom: 8 })
            .border({ width: { bottom: this.selectedTag === g.name ? 2 : 0 }, color: colors.gold })
            .onClick((): void => { this.selectedTag = g.name; })
          })
        }
      }
      .scrollable(ScrollDirection.Horizontal)
      .scrollBar(BarState.Off)
      .width('100%')
      .padding({ left: 12, right: 12 })

      if (this.isLoading) {
        Column() {
          LoadingProgress().width(32).height(32).color(colors.gold)
        }.width('100%').height(300).justifyContent(FlexAlign.Center)
      } else if (this.getFilteredList().length === 0) {
        EmptyState({ icon: '🏛️', title: '暂无收藏', subtitle: '在遗址或文物详情页\n点击星标即可加入典藏' })
          .padding({ top: 80 })
      } else {
        Scroll() {
          Column({ space: 0 }) {
            Text(`共 ${this.getFilteredList().length} 件藏品`)
              .fontSize(12)
              .fontColor(colors.textTertiary)
              .width('100%')
              .margin({ bottom: 16 })
            ForEach(this.getFilteredList(), (c: Favorite) => {
              this.ItemView(c)
            }, (c: Favorite) => c.id)
          }
          .padding({ left: 20, right: 20, bottom: 32 })
        }
        .scrollBar(BarState.Off)
        .edgeEffect(EdgeEffect.Spring)
        .layoutWeight(1)
      }
    }
    .width('100%').height('100%').backgroundColor(colors.bg)
    .bindSheet(this.showRemoveConfirm, this.RemoveSheet(), {
      height: 220, dragBar: true, backgroundColor: colors.bgCard,
      onDisappear: (): void => { this.showRemoveConfirm = false; }
    })
  }

  @Builder RemoveSheet() {
    Column({ space: 16 }) {
      Text('取消收藏？')
        .fontSize(18).fontWeight(FontWeight.Medium).fontColor(colors.textPrimary).margin({ top: 24 })
      Text(this.pendingRemove ?
        `将 "${this.pendingRemove.targetType === 'site' ?
          (this.resolveSite(this.pendingRemove)?.name ?? '') :
          (this.resolveArtifact(this.pendingRemove)?.name ?? '')}" 从收藏中移除` : '')
        .fontSize(14).fontColor(colors.textSecondary).textAlign(TextAlign.Center).padding({ left: 24, right: 24 })
      Row({ space: 12 }) {
        Button('取消').layoutWeight(1).height(44).backgroundColor(colors.bgElevated)
          .fontColor(colors.textPrimary).borderRadius(2).onClick((): void => { this.showRemoveConfirm = false; })
        Button('确认移除').layoutWeight(1).height(44).backgroundColor(colors.cinnabar)
          .fontColor(Color.White).borderRadius(2).onClick((): void => { this.doRemove(); })
      }.padding({ left: 24, right: 24, top: 8 })
    }.width('100%')
  }
}
