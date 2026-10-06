import { CultureService, CityStat } from '../../service/CultureService';
import { RecommendationService, RecommendItem } from '../../service/RecommendationService';
import { Site, Artifact, Poetry } from '../../model/entity/Entities';
import { SiteCard } from '../components/SiteCard';
import { ArtifactCard } from '../components/ArtifactCard';
import { EraTimeline } from '../components/EraTimeline';
import { LoadingIndicator } from '../components/LoadingIndicator';
import { EmptyState } from '../components/EmptyState';
import { LicensedCover } from '../components/LicensedCover';
import { EraMeta, CityMeta } from '../../common/constants/AppMeta';
import { colors } from '../../common/constants/Colors';
import { EventBus, AppEvents } from '../../common/utils/EventBus';

interface HeroPoetry {
  title: string;
  author: string;
  verse: string;
}
interface SearchParam { keyword: string; }

const POETRY_HERO_POOL: HeroPoetry[] = [
  { title: '登鹳雀楼', author: '王之涣', verse: '白日依山尽，黄河入海流。欲穷千里目，更上一层楼。' },
  { title: '将进酒', author: '李白', verse: '君不见，黄河之水天上来，奔流到海不复回。' },
  { title: '黄河二首', author: '杜甫', verse: '黄河北岸海西军，椎鼓鸣钟天下闻。' },
];

/**
 * 首页（数字敦煌风格沉浸式首屏）
 */
@Component
export struct HomePage {
  @Consume('navPathStack') navPathStack: NavPathStack;
  @State dailySite: Site | null = null;
  @State featuredArtifacts: Artifact[] = [];
  @State featuredSites: Site[] = [];
  @State cityStats: CityStat[] = [];
  @State recommendedItems: RecommendItem[] = [];
  @State heroPoetry: HeroPoetry = POETRY_HERO_POOL[0];
  @State loading: boolean = true;
  @State allSites: Site[] = [];
  @State viewportHeight: number = 700;
  @State viewportWidth: number = 400;
  private refreshTimer?: number;
  private loadGeneration: number = 0;
  private onUserDataChange = (): void => {
    if (this.refreshTimer) clearTimeout(this.refreshTimer);
    this.refreshTimer = setTimeout(() => { this.loadData(); }, 100);
  };

  private makePath(name: string, param?: Object): NavPathInfo {
    const info: NavPathInfo = { name: name };
    if (param !== undefined) info.param = param;
    return info;
  }

  private heroHeight(): number {
    return this.viewportHeight < 500 ? Math.max(320, this.viewportHeight * 0.95) :
      Math.max(420, Math.min(680, this.viewportHeight * 0.72));
  }
  private makeSearchPath(keyword: string): NavPathInfo {
    const param: SearchParam = { keyword: keyword };
    return this.makePath('searchResult', param);
  }

  async aboutToAppear() {
    EventBus.getInstance().on(AppEvents.FAVORITE_CHANGED, this.onUserDataChange);
    EventBus.getInstance().on(AppEvents.HISTORY_CHANGED, this.onUserDataChange);
    await this.loadData();
  }

  aboutToDisappear(): void {
    this.loadGeneration++;
    EventBus.getInstance().off(AppEvents.FAVORITE_CHANGED, this.onUserDataChange);
    EventBus.getInstance().off(AppEvents.HISTORY_CHANGED, this.onUserDataChange);
    if (this.refreshTimer) clearTimeout(this.refreshTimer);
  }

  async loadData() {
    const generation = ++this.loadGeneration;
    try {
      const svc = CultureService.getInstance();
      const idx = new Date().getDate() % POETRY_HERO_POOL.length;
      const dailySite = await svc.getDailySite();
      const featuredSites = await svc.getFeaturedSites(6);
      const featuredArtifacts = await svc.getFeaturedArtifacts(8);
      const cityStats = await svc.getCityStats();
      const allSites = await svc.getAllSites();
      const recommendedItems = await RecommendationService.getInstance().getRecommendations(6);
      if (generation !== this.loadGeneration) return;
      this.heroPoetry = POETRY_HERO_POOL[idx];
      this.dailySite = dailySite;
      this.featuredSites = featuredSites;
      this.featuredArtifacts = featuredArtifacts;
      this.cityStats = cityStats;
      this.allSites = allSites;
      this.recommendedItems = recommendedItems;
    } catch (e) {
      // ignore
    }
    if (generation === this.loadGeneration) this.loading = false;
  }

  build() {
    Column() {
    if (this.loading) {
      Column() { LoadingIndicator() }.width('100%').height('100%')
        .backgroundColor($r('app.color.ink_wall'))
        .justifyContent(FlexAlign.Center);
    } else {
    Stack() {
      Scroll() {
        Column({ space: 0 }) {
          // 1. Hero 全屏沉浸式首屏：黄河意象背景 + 叠印诗句 + 标题
          this.HeroSection()

          // 2. 年代时间轴（仰韶→宋）
          Column({ space: 8 }) {
            this.SectionTitle('文明时序', 'CHRONICLE OF CIVILIZATION')
            EraTimeline()
          }
          .width('100%')
          .padding({ left: 20, right: 20, top: 28, bottom: 4 })

          // 3. 每日一景（遗址详情入口）
          Column({ space: 12 }) {
            this.SectionTitle('今日一址', 'DAILY SITE')
            if (this.dailySite) {
              this.DailySiteCard(this.dailySite)
            }
          }
          .width('100%')
          .padding({ left: 20, right: 20, top: 28 })

          // 4. 沿线城市（数字敦煌"洞窟列表"式）
          Column({ space: 12 }) {
            this.SectionTitle('五城览胜', 'ALONG THE RIVER')
            Scroll() {
              Row({ space: 12 }) {
                ForEach(this.cityStats, (c: CityStat) => {
                  this.CityCard(c)
                })
              }
              .padding({ left: 20, right: 20 })
            }
            .scrollable(ScrollDirection.Horizontal)
            .scrollBar(BarState.Off)
          }
          .width('100%')
          .padding({ top: 28 })

          // 5. 精品文物（横向滚动）
          if (this.featuredArtifacts.length > 0) {
            Column({ space: 12 }) {
              this.SectionTitle('精品馆藏', 'COLLECTIONS')
              Scroll() {
                Row({ space: 12 }) {
                  ForEach(this.featuredArtifacts, (a: Artifact) => {
                    ArtifactCard({ artifact: a, onTap: (): void => {
                      this.navPathStack.pushPath(this.makePath('artifactDetail', a));
                    } })
                    .width(160)
                  })
                }
                .padding({ left: 20, right: 20 })
              }
              .scrollable(ScrollDirection.Horizontal)
              .scrollBar(BarState.Off)
            }
            .width('100%')
            .padding({ top: 28 })
          }

          // 6. 为你推荐（智能推荐）
          if (this.recommendedItems.length > 0) {
            Column({ space: 12 }) {
              Row() {
                this.SectionTitle('为你推荐', 'RECOMMENDED')
              }
              Text('基于你的收藏与浏览偏好')
                .fontSize(11).fontColor(colors.textTertiary).margin({ top: -10, bottom: 4 })
              Column({ space: 14 }) {
                ForEach(this.recommendedItems, (ri: RecommendItem) => {
                  Column({ space: 4 }) {
                    if (ri.type === 'site') {
                      SiteCard({ site: ri.item as Site, onTap: (): void => {
                        this.navPathStack.pushPath(this.makePath('siteDetail', ri.item));
                      } })
                    } else {
                      ArtifactCard({ artifact: ri.item as Artifact, onTap: (): void => {
                        this.navPathStack.pushPath(this.makePath('artifactDetail', ri.item));
                      } })
                    }
                    Text(ri.reason).fontSize(10).fontColor(colors.gold).padding({ left: 8 })
                  }
                  .width('100%')
                })
              }
              .width('100%')
            }
            .width('100%')
            .padding({ left: 20, right: 20, top: 28 })
            .alignItems(HorizontalAlign.Start)
          }

          // 7. 精选遗址列表
          if (this.featuredSites.length > 0) {
            Column({ space: 12 }) {
              this.SectionTitle('文脉遗址', 'HERITAGE SITES')
              Column({ space: 16 }) {
                ForEach(this.featuredSites, (s: Site) => {
                  SiteCard({ site: s, onTap: (): void => {
                    this.navPathStack.pushPath(this.makePath('siteDetail', s));
                  } })
                })
              }
              .width('100%')
            }
            .width('100%')
            .padding({ left: 20, right: 20, top: 28 })
          }

          // 7. 页脚
          Column({ space: 8 }) {
            // 装饰：金色细线
            Row().width(40).height(1).backgroundColor($r('app.color.gold_dim'))
            Text('黄河记忆 · YELLOW RIVER MEMORY')
              .fontSize(9).letterSpacing(3).fontColor($r('app.color.text_tertiary'))
            Text('一条河，五千年，文明不息。')
              .fontSize(11).fontColor($r('app.color.text_tertiary')).margin({ top: 2 })
            Text('Yellow River · 5000 Years · Endless Civilization')
              .fontSize(8).letterSpacing(2).fontColor($r('app.color.text_tertiary')).opacity(0.6)
          }
          .width('100%')
          .padding({ top: 60, bottom: 40 })
          .alignItems(HorizontalAlign.Center)
        }
        .width('100%')
      }
      .scrollBar(BarState.Off)
      .width('100%').height('100%')
      .edgeEffect(EdgeEffect.Spring)
    }
    .width('100%').height('100%')
    .backgroundColor($r('app.color.ink_wall'))
    }
    }
    .width('100%').height('100%')
    .onAreaChange((_oldArea: Area, newArea: Area): void => {
      this.viewportHeight = Number(newArea.height);
      this.viewportWidth = Number(newArea.width);
    })
  }

  @Builder
  HeroSection() {
    Column() {
      Stack({ alignContent: Alignment.BottomStart }) {
      // 背景：深色渐变+金色点缀（没有真实图片时用渐变模拟黄河日暮）
      Column()
        .width('100%')
        .height('100%')
        .linearGradient({
          angle: 180,
          colors: [
            ['#1A1510', 0.0],
            ['#0A0806', 0.5],
            ['#1C1812', 1.0],
          ],
        });
      // 装饰：抽象"几"字弯流的黄河（用渐变和线条暗示）
      Column()
        .width('100%').height('100%')
        .linearGradient({
          angle: 200,
          colors: [
            ['#00C9A96E', 0.0],
            ['#08C9A96E', 0.4],
            ['#1AC9A96E', 0.7],
            ['#00C9A96E', 1.0],
          ],
        });
      // 顶部搜索入口
      Row() {
        Row({ space: 8 }) {
          Text('🔍').fontSize(14).fontColor($r('app.color.text_tertiary'))
          Text('搜索遗址、文物、诗词…')
            .fontSize(13).fontColor($r('app.color.text_tertiary'))
            .layoutWeight(1)
        }
        .layoutWeight(1)
        .height(38)
        .padding({ left: 14, right: 14 })
        .backgroundColor($r('app.color.ink_wall_card'))
        .borderRadius(2)
        .border({ width: 0.5, color: $r('app.color.ink_line') })
        .onClick(() => {
          this.navPathStack.pushPath(this.makeSearchPath(''));
        })
      }
      .width('100%')
      .padding({ left: 20, right: 20, top: 16 })
      .position({ x: 0, y: 0 })

      // 底部诗句+标题（数字敦煌首屏式）
      Column({ space: this.viewportHeight < 500 ? 8 : 14 }) {
        // 英文副标
        Text('YELLOW RIVER MEMORY')
          .fontSize(10)
          .letterSpacing(6)
          .fontColor($r('app.color.gold_dim'))
        // 主标题（宋体金色）
        Text('黄河记忆')
          .fontSize(this.viewportHeight < 500 ? 32 : 44)
          .fontColor($r('app.color.text_gold'))
          .fontWeight(FontWeight.Medium)
        // 金色装饰线
        Row()
          .width(48).height(1).backgroundColor($r('app.color.gold_primary'))
          .margin({ top: 2, bottom: 4 })
        // 副标题
        Text('河南段黄河文化数字档案')
          .fontSize(13)
          .fontColor($r('app.color.text_secondary'))
          .letterSpacing(2)
        // Hero诗句
        Column({ space: 6 }) {
          Text(`「${this.heroPoetry.verse}」`)
            .fontSize(12).fontColor($r('app.color.gold_dim'))
            .fontStyle(FontStyle.Italic)
            .opacity(0.75)
            .maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
          Text(`—— ${this.heroPoetry.author}《${this.heroPoetry.title}》`)
            .fontSize(10).fontColor($r('app.color.text_tertiary'))
        }
        .margin({ top: this.viewportHeight < 500 ? 8 : 20 })
        .alignItems(HorizontalAlign.Center)
        .width('100%')
        // 开始探索按钮
        Row({ space: 6 }) {
          Text('探索文化档案')
            .fontSize(12).fontColor($r('app.color.ink_black'))
            .fontWeight(FontWeight.Medium)
          Text('›').fontSize(14).fontColor($r('app.color.ink_black'))
        }
        .padding({ left: 20, right: 20, top: 10, bottom: 10 })
        .backgroundColor($r('app.color.gold_primary'))
        .borderRadius(2)
        .margin({ top: this.viewportHeight < 500 ? 8 : 16 })
        .onClick(() => {
          this.navPathStack.pushPath(this.makeSearchPath(''));
        })
      }
      .width('100%')
      .padding({ left: this.viewportWidth >= 840 ? 48 : 24,
        right: this.viewportWidth >= 840 ? 48 : 24, bottom: this.viewportHeight < 500 ? 16 : 48 })
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
      .height(this.heroHeight())

      // 分隔阴影（hero和下一段之间）
      Row()
        .width('100%').height(24)
        .linearGradient({
          angle: 180,
          colors: [['#0A0806', 0.0], ['#000A0806', 1.0]],
        })
        .position({ x: 0, y: this.heroHeight() - 24 })
    }
  }

  @Builder
  SectionTitle(cn: string, en: string) {
    Column({ space: 6 }) {
      Text(en.toUpperCase())
        .fontSize(9).letterSpacing(3).fontColor($r('app.color.gold_dim'))
      Text(cn)
        .fontSize(20).fontColor($r('app.color.text_gold')).fontWeight(FontWeight.Medium)
      Row()
        .width(28).height(1).backgroundColor($r('app.color.gold_primary')).margin({ top: 2 })
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  DailySiteCard(s: Site) {
    Column() {
      Stack({ alignContent: Alignment.BottomStart }) {
        LicensedCover({ path: s.coverImage ?? '', tint: EraMeta.of(s.era)?.colorRes ?? '#2A241C' })
          .width('100%').height(220)
        Column({ space: 4 }) {
          Text('每 日 一 址')
            .fontSize(9).letterSpacing(4).fontColor($r('app.color.gold_dim'))
          Text(s.name)
            .fontSize(26).fontColor($r('app.color.white_pure')).fontWeight(FontWeight.Medium)
          if (s.nameEn) {
            Text(s.nameEn.toUpperCase())
              .fontSize(9).letterSpacing(3).fontColor($r('app.color.gold_primary'))
          }
        }
        .padding(16)
      }
      .width('100%')
      Column({ space: 8 }) {
        Row({ space: 8 }) {
          if (EraMeta.of(s.era)) Text(EraMeta.of(s.era)!.name).fontSize(10).fontColor($r('app.color.text_gold'))
            .padding({ left: 8, right: 8, top: 3, bottom: 3 })
            .backgroundColor($r('app.color.gold_20'))
            .border({ width: 0.5, color: $r('app.color.gold_dim') }).borderRadius(2)
          if (CityMeta.of(s.city)) Text(CityMeta.of(s.city)!.name).fontSize(10).fontColor($r('app.color.text_secondary'))
            .padding({ left: 8, right: 8, top: 3, bottom: 3 })
            .backgroundColor($r('app.color.ink_wall_card'))
            .border({ width: 0.5, color: $r('app.color.ink_line') }).borderRadius(2)
          Blank()
          Text(`${s.artifactCount}件文物`).fontSize(10).fontColor($r('app.color.text_tertiary'))
        }
        Text(s.summary ?? '')
          .fontSize(12).fontColor($r('app.color.text_secondary'))
          .lineHeight(1.8).maxLines(3).textOverflow({ overflow: TextOverflow.Ellipsis })
        Row() {
          Blank()
          Row({ space: 4 }) {
            Text('翻开长卷').fontSize(12).fontColor($r('app.color.gold_primary'))
            Text('›').fontSize(14).fontColor($r('app.color.gold_primary'))
          }
        }
        .width('100%')
        .margin({ top: 4 })
      }
      .width('100%')
      .padding(16)
      .backgroundColor($r('app.color.ink_wall_card'))
    }
    .width('100%')
    .borderRadius(2)
    .clip(true)
    .border({ width: 0.5, color: $r('app.color.ink_line') })
    .onClick(() => {
      this.navPathStack.pushPath(this.makePath('siteDetail', s));
    })
  }

  @Builder
  CityCard(c: CityStat) {
    Column({ space: 8 }) {
      Stack({ alignContent: Alignment.Center }) {
        Column()
          .width(140).height(180)
          .linearGradient({
            angle: 160,
            colors: [['#2A241C', 0.0], [CityMeta.of(c.city)?.colorRes ?? '#1C1812', 0.6], ['#0A0806', 1.0]],
          });
        Column({ space: 4 }) {
          Text(c.name)
            .fontSize(22).fontColor($r('app.color.white_pure')).fontWeight(FontWeight.Medium)
          Text(CityMeta.of(c.city)?.nameEn?.toUpperCase() ?? '')
            .fontSize(8).letterSpacing(3).fontColor($r('app.color.gold_primary'))
        }
      }
      .width(140).height(180)
      Row({ space: 6 }) {
        Text(`${c.count}处遗址`)
          .fontSize(11).fontColor($r('app.color.text_secondary'))
        Text('›').fontSize(14).fontColor($r('app.color.text_tertiary'))
        Blank()
      }
      .width(140)
      .padding({ left: 4, right: 4, top: 4, bottom: 8 })
    }
    .borderRadius(2).clip(true)
    .border({ width: 0.5, color: $r('app.color.ink_line') })
    .backgroundColor($r('app.color.ink_wall_card'))
    .onClick(() => {
      // 跳探源页并筛选城市——为简化，直接跳转搜索结果页
      this.navPathStack.pushPath(this.makeSearchPath(c.name));
    })
  }
}
