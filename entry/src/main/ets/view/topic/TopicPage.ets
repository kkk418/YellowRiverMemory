import { colors } from '../../common/constants/Colors';
import { TopicService, TopicCardData, KnowledgeGraph, GraphNode } from '../../service/TopicService';
import { EventBus, AppEvents } from '../../common/utils/EventBus';
import { Site, Artifact } from '../../model/entity/Entities';
import { SiteCard } from '../components/SiteCard';
import { ArtifactCard } from '../components/ArtifactCard';
import { EmptyState } from '../components/EmptyState';

/**
 * 文化主题聚合页：个人知识库（主题为节点，关联遗址/文物/笔记）
 */
@Component
export struct TopicPage {
  @Consume('navPathStack') navPathStack: NavPathStack;
  @State cards: TopicCardData[] = [];
  @State showCreate: boolean = false;
  @State newTopicName: string = '';
  @State newTopicDesc: string = '';
  @State newTopicIcon: string = '📜';
  @State graph: KnowledgeGraph | null = null;
  private onTopicChange = (): void => { this.load(); };

  aboutToAppear(): void {
    EventBus.getInstance().on(AppEvents.TOPIC_CHANGED, this.onTopicChange);
    setTimeout(() => this.load(), 50);
  }

  aboutToDisappear(): void {
    EventBus.getInstance().off(AppEvents.TOPIC_CHANGED, this.onTopicChange);
  }

  private async load(): Promise<void> {
    this.cards = await TopicService.getInstance().getTopicCards();
    if (this.cards.length > 0) {
      this.graph = await TopicService.getInstance().buildKnowledgeGraph();
    } else {
      this.graph = null;
    }
  }

  private async createTopic(): Promise<void> {
    const name = this.newTopicName.trim();
    if (!name) return;
    await TopicService.getInstance().createTopic(name, this.newTopicDesc, this.newTopicIcon);
    this.newTopicName = '';
    this.newTopicDesc = '';
    this.showCreate = false;
  }

  private topicNodes(): GraphNode[] {
    return this.graph ? this.graph.nodes.filter((node: GraphNode) => node.type === 'topic') : [];
  }

  private childNodes(topicId: string): GraphNode[] {
    const graph = this.graph;
    if (!graph) return [];
    const children: GraphNode[] = [];
    for (const edge of graph.edges) {
      if (edge.source !== topicId) continue;
      const child = graph.nodes.find((node: GraphNode) => node.id === edge.target);
      if (child) children.push(child);
      if (children.length >= 12) break;
    }
    return children;
  }

  @Builder SectionTitle(title: string, en: string) {
    Column({ space: 4 }) {
      Row() {
        Text(en).fontSize(10).fontColor(colors.textTertiary).letterSpacing(2)
        Text('·').fontSize(10).fontColor(colors.textTertiary).margin({ left: 6, right: 6 })
        Text('TOPIC').fontSize(10).fontColor(colors.textTertiary).letterSpacing(2)
      }
      Text(title).fontSize(20).fontWeight(FontWeight.Bold).fontColor(colors.textPrimary)
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
    .margin({ bottom: 16 })
  }

  @Builder TopicCardView(card: TopicCardData) {
    Column({ space: 12 }) {
      // 主题头
      Row({ space: 12 }) {
        Text(card.topic.iconEmoji || '📜')
          .fontSize(32)
          .width(56).height(56)
          .textAlign(TextAlign.Center)
          .backgroundColor(card.topic.coverColor + '22')
          .borderRadius(4)
        Column({ space: 4 }) {
          Text(card.topic.name)
            .fontSize(18).fontWeight(FontWeight.Bold).fontColor(colors.textPrimary)
          Text(card.topic.description || '自定义文化主题')
            .fontSize(12).fontColor(colors.textSecondary).maxLines(2)
          Row({ space: 10 }) {
            Text(`${card.siteCount} 遗址`).fontSize(11).fontColor(colors.gold)
            Text(`·`).fontSize(11).fontColor(colors.textTertiary)
            Text(`${card.artifactCount} 文物`).fontSize(11).fontColor(colors.gold)
            Text(`·`).fontSize(11).fontColor(colors.textTertiary)
            Text(`${card.noteCount} 笔记`).fontSize(11).fontColor(colors.gold)
          }
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      // 预览（遗址缩略 + 文物缩略）
      if (card.sites.length > 0 || card.artifacts.length > 0) {
        Scroll() {
          Row({ space: 8 }) {
            ForEach(card.sites.slice(0, 3), (s: Site) => {
              SiteCard({ site: s, onTap: (): void => {
                this.navPathStack.pushPath({ name: 'siteDetail', param: s });
              } })
              .width(200)
            })
            ForEach(card.artifacts.slice(0, 3), (a: Artifact) => {
              ArtifactCard({ artifact: a, onTap: (): void => {
                this.navPathStack.pushPath({ name: 'artifactDetail', param: a });
              } })
              .width(140)
            })
          }
        }
        .scrollable(ScrollDirection.Horizontal)
        .scrollBar(BarState.Off)
        .width('100%')
      }
    }
    .width('100%')
    .padding(16)
    .backgroundColor(colors.bgCard)
    .borderRadius(4)
    .border({ width: 1, color: colors.border })
  }

  @Builder KnowledgeGraphView() {
    if (this.graph && this.graph.nodes.length >= 2) {
      Column({ space: 12 }) {
        this.SectionTitle('知识图谱', 'KNOWLEDGE MAP')
        Stack() {
          // 简化的放射状图谱：中心为主题，周围是site/artifact/era节点
          Column({ space: 20 }) {
            ForEach(this.topicNodes(), (center: GraphNode) => {
              Column({ space: 16 }) {
                // 中心节点
                Text(center.label)
                  .fontSize(14).fontColor(Color.Black).fontWeight(FontWeight.Bold)
                  .padding({ left: 14, right: 14, top: 10, bottom: 10 })
                  .backgroundColor(colors.gold)
                  .borderRadius(20)
                // 子节点（与中心相连的）
                Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Center }) {
                  ForEach(this.childNodes(center.id), (child: GraphNode) => {
                    Column({ space: 4 }) {
                      Text(child.label.replace(/^(仰韶|龙山|夏商|周|汉唐|宋)$/, '$1文化'))
                        .fontSize(11).fontColor(colors.textPrimary)
                        .padding({ left: 10, right: 10, top: 6, bottom: 6 })
                        .backgroundColor(child.type === 'era' ? colors.bgElevated : colors.bgCard)
                        .borderRadius(12)
                        .border({
                          width: 1,
                          color: child.type === 'era' ? colors.gold20 : colors.border
                        })
                    }
                    .margin(4)
                  })
                }
              }
              .alignItems(HorizontalAlign.Center)
            })
          }
          .width('100%')
          .padding(20)
        }
        .width('100%')
        .backgroundColor(colors.bgCard)
        .borderRadius(4)
        .border({ width: 1, color: colors.border })
      }
      .width('100%')
    }
  }

  build() {
    Column({ space: 0 }) {
      // 顶部栏
      Column({ space: 4 }) {
        Row() {
          Text('THEME').fontSize(10).fontColor(colors.textTertiary).letterSpacing(3)
          Text('·').fontSize(10).fontColor(colors.textTertiary).margin({ left: 6, right: 6 })
          Text('文脉').fontSize(10).fontColor(colors.textTertiary).letterSpacing(3)
        }
        Row() {
          Text('文化主题')
            .fontSize(28).fontWeight(FontWeight.Bold).fontColor(colors.textPrimary)
            .layoutWeight(1)
          Button('+ 新主题')
            .fontSize(12).fontColor(colors.bg).backgroundColor(colors.gold)
            .height(32).borderRadius(2)
            .onClick((): void => { this.showCreate = true; })
        }
        .width('100%')
      }
      .alignItems(HorizontalAlign.Start)
      .padding({ left: 20, right: 20, top: 12, bottom: 20 })

      Scroll() {
        Column({ space: 16 }) {
          if (this.cards.length === 0) {
            EmptyState({
              icon: '📚',
              title: '尚未创建主题',
              subtitle: '将收藏的遗址与文物按主题聚合，构建个人文化知识库'
            })
            .width('100%')
            .padding({ top: 40 })
          } else {
            this.KnowledgeGraphView()
            ForEach(this.cards, (card: TopicCardData) => {
              this.TopicCardView(card)
            })
          }
        }
        .padding({ left: 20, right: 20, bottom: 32 })
      }
      .scrollBar(BarState.Off)
      .layoutWeight(1)
    }
    .width('100%').height('100%').backgroundColor(colors.bg)
    .bindSheet($$this.showCreate, this.CreateTopicSheet(), {
      height: 380, dragBar: true, backgroundColor: colors.bgElevated,
      onDisappear: (): void => { this.showCreate = false; }
    })
  }

  @Builder CreateTopicSheet() {
    Column({ space: 14 }) {
      Text('创建文化主题').fontSize(18).fontWeight(FontWeight.Bold).fontColor(colors.textPrimary)
      Text('将相关遗址、文物、笔记归入一个主题，形成个人知识节点')
        .fontSize(12).fontColor(colors.textSecondary)
      // 图标选择
      Row({ space: 10 }) {
        ForEach(['📜', '🏺', '⛩️', '🗿', '📚', '🏯', '🎭', '🗺️'], (emoji: string) => {
          Text(emoji).fontSize(24).padding(10)
            .borderRadius(4)
            .backgroundColor(this.newTopicIcon === emoji ? colors.gold20 : colors.bgCard)
            .border({ width: 1, color: this.newTopicIcon === emoji ? colors.gold : colors.border })
            .onClick((): void => { this.newTopicIcon = emoji; })
        })
      }
      TextInput({ placeholder: '主题名，如"夏商文明溯源"', text: this.newTopicName })
        .fontSize(14).fontColor(colors.textPrimary).placeholderColor(colors.textTertiary)
        .backgroundColor(colors.bgCard).borderRadius(2)
        .height(44).padding({ left: 12, right: 12 })
        .border({ width: 1, color: colors.border })
        .onChange((v: string): void => { this.newTopicName = v; })
      TextArea({ placeholder: '主题简介（选填）', text: this.newTopicDesc })
        .fontSize(13).fontColor(colors.textPrimary).placeholderColor(colors.textTertiary)
        .backgroundColor(colors.bgCard).borderRadius(2)
        .height(80).padding(12)
        .border({ width: 1, color: colors.border })
        .onChange((v: string): void => { this.newTopicDesc = v; })
      Button('创建主题')
        .width('100%').height(46).fontSize(14).fontColor(Color.White)
        .backgroundColor(colors.gold).borderRadius(2)
        .enabled(this.newTopicName.trim().length > 0)
        .onClick((): void => { this.createTopic(); })
    }
    .width('100%')
    .padding(20)
    .alignItems(HorizontalAlign.Start)
  }
}
