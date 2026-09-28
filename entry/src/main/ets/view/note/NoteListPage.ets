import { colors } from '../../common/constants/Colors';
import { Note } from '../../model/entity/Entities';
import { NoteTargetType } from '../../common/constants/Enums';
import { UserDataService } from '../../service/UserDataService';
import { CultureService } from '../../service/CultureService';
import { DateUtil } from '../../common/utils/DateUtil';
import { StringUtil } from '../../common/utils/StringUtil';
import { EventBus, AppEvents } from '../../common/utils/EventBus';
import { EmptyState } from '../components/EmptyState';
import { NoteEditorParams } from './NoteEditorPage';

interface NoteGroup {
  dateLabel: string;
  notes: Note[];
}

@Component
export struct NoteListPage {
  @Consume('navPathStack') navPathStack: NavPathStack;
  @State notes: Note[] = [];
  @State countNotes: Note[] = [];
  @State groups: NoteGroup[] = [];
  @State keyword: string = '';
  @State filter: 'all' | NoteTargetType = 'all';
  @State isLoading: boolean = true;
  private onNoteChange = (): void => { this.loadNotes(); };

  aboutToAppear(): void {
    this.loadNotes();
    EventBus.getInstance().on(AppEvents.NOTE_CHANGED, this.onNoteChange);
  }

  aboutToDisappear(): void {
    EventBus.getInstance().off(AppEvents.NOTE_CHANGED, this.onNoteChange);
  }

  private loadNotes(): void {
    this.isLoading = true;
    setTimeout(async () => {
      const svc = UserDataService.getInstance();
      let list = await svc.listNotes();
      if (this.keyword.trim()) {
        const kw = this.keyword.trim().toLowerCase();
        list = list.filter(n =>
          n.title.toLowerCase().includes(kw) || n.content.toLowerCase().includes(kw) ||
          StringUtil.parseTagsArray(n.tags).some(t => t.toLowerCase().includes(kw))
        );
      }
      this.countNotes = list;
      if (this.filter !== 'all') {
        list = list.filter(n => n.targetType === this.filter);
      }
      this.notes = list;
      this.groupNotes();
      this.isLoading = false;
    }, 30);
  }

  private groupNotes(): void {
    const map = new Map<string, Note[]>();
    for (const n of this.notes) {
      const key = this.dateGroupKey(n.updatedAt);
      if (!map.has(key)) map.set(key, []);
      map.get(key)!.push(n);
    }
    const result: NoteGroup[] = [];
    for (const entry of map) {
      result.push({ dateLabel: entry[0], notes: entry[1] });
    }
    this.groups = result;
  }

  private dateGroupKey(ts: number): string {
    const d = new Date(ts);
    const now = new Date();
    const today = new Date(now.getFullYear(), now.getMonth(), now.getDate()).getTime();
    const yest = today - 86400000;
    const dayStart = new Date(d.getFullYear(), d.getMonth(), d.getDate()).getTime();
    if (dayStart === today) return '今天';
    if (dayStart === yest) return '昨天';
    if (ts > today - 7 * 86400000) return '近七天';
    if (ts > today - 30 * 86400000) return '近一月';
    return DateUtil.formatDate(ts).substring(0, 7);
  }

  private resolveTargetName(n: Note): string {
    if (n.targetType === NoteTargetType.SITE && n.targetId) {
      const s = CultureService.getInstance().getSiteByIdSync(n.targetId);
      return s ? `🏛 ${s.name}` : '';
    }
    if (n.targetType === NoteTargetType.ARTIFACT && n.targetId) {
      const a = CultureService.getInstance().getArtifactByIdSync(n.targetId);
      return a ? `🏺 ${a.name}` : '';
    }
    return '';
  }

  private goEdit(n?: Note): void {
    const params: NoteEditorParams = {};
    if (n) {
      params.noteId = n.id;
    }
    this.navPathStack.pushPath({ name: 'noteEditor', param: params });
  }

  private openTarget(n: Note): void {
    if (n.targetType === NoteTargetType.SITE && n.targetId) {
      const s = CultureService.getInstance().getSiteByIdSync(n.targetId);
      if (s) this.navPathStack.pushPath({ name: 'siteDetail', param: s });
    } else if (n.targetType === NoteTargetType.ARTIFACT && n.targetId) {
      const a = CultureService.getInstance().getArtifactByIdSync(n.targetId);
      if (a) this.navPathStack.pushPath({ name: 'artifactDetail', param: a });
    }
  }

  @Builder NoteCard(n: Note) {
    Column({ space: 8 }) {
      Row() {
        Text(n.title || '无题').fontSize(15).fontWeight(FontWeight.Medium)
          .fontColor(colors.textPrimary).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)
        Text(DateUtil.formatDateTime(n.updatedAt).substring(11, 16))
          .fontSize(11).fontColor(colors.textTertiary)
      }
      Text(n.content || '（无正文）')
        .fontSize(13).fontColor(colors.textSecondary)
        .maxLines(3).textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')
        .lineHeight(20)
      if (this.resolveTargetName(n)) {
        Text(this.resolveTargetName(n)).fontSize(11).fontColor(colors.gold)
          .padding({ left: 6, right: 6, top: 2, bottom: 2 })
          .backgroundColor(colors.gold10).borderRadius(2)
      }
      if (StringUtil.parseTagsArray(n.tags).length > 0) {
        Row({ space: 6 }) {
          ForEach(StringUtil.parseTagsArray(n.tags).slice(0, 4), (t: string) => {
            Text(`# ${t}`).fontSize(10).fontColor(colors.textTertiary)
          })
        }
      }
    }
    .width('100%')
    .padding(14)
    .backgroundColor(colors.bgCard)
    .borderRadius(4)
    .border({ width: 1, color: colors.border })
    .margin({ bottom: 10 })
    .onClick((): void => { this.goEdit(n); })
  }

  @Builder FilterTab(label: string, value: 'all' | NoteTargetType, count: number) {
    Column({ space: 4 }) {
      Text(label).fontSize(13)
        .fontColor(this.filter === value ? colors.gold : colors.textSecondary)
        .fontWeight(this.filter === value ? FontWeight.Medium : FontWeight.Regular)
      Text(`${count}`).fontSize(10)
        .fontColor(this.filter === value ? colors.gold : colors.textTertiary)
    }
    .padding({ left: 14, right: 14, top: 8, bottom: 8 })
    .border({ width: { bottom: this.filter === value ? 2 : 0 }, color: colors.gold })
    .onClick((): void => {
      this.filter = value;
      this.loadNotes();
    })
  }

  build() {
    Column({ space: 0 }) {
      // 顶部栏
      Row() {
        Text('我的笔记')
          .fontSize(22).fontWeight(FontWeight.Bold).fontColor(colors.textPrimary)
          .layoutWeight(1)
        Text('+ 新笔记').fontSize(13).fontColor(colors.gold)
          .padding({ left: 10, right: 10, top: 6, bottom: 6 })
          .onClick((): void => { this.goEdit(); })
      }
      .width('100%')
      .padding({ left: 20, right: 20, top: 12, bottom: 12 })

      // 搜索框
      Row() {
        Text('🔍').fontSize(14).fontColor(colors.textTertiary).margin({ right: 8 })
        TextInput({ placeholder: '搜索笔记标题、正文、标签…', text: this.keyword })
          .layoutWeight(1).height(36).backgroundColor(Color.Transparent)
          .fontSize(13).fontColor(colors.textPrimary)
          .placeholderColor(colors.textTertiary)
          .padding(0).onChange((v: string) => {
            this.keyword = v;
            this.loadNotes();
          })
        if (this.keyword) {
          Text('×').fontSize(16).fontColor(colors.textTertiary)
            .onClick((): void => { this.keyword = ''; this.loadNotes(); })
        }
      }
      .width('100%').height(40)
      .padding({ left: 14, right: 14 })
      .backgroundColor(colors.bgCard)
      .borderRadius(20)
      .margin({ left: 20, right: 20, bottom: 12 })

      // 筛选Tab
      Scroll() {
        Row({ space: 4 }) {
          this.FilterTab('全部', 'all', this.countNotes.length)
          this.FilterTab('自由笔记', NoteTargetType.STANDALONE,
            this.countNotes.filter(n => n.targetType === NoteTargetType.STANDALONE).length)
          this.FilterTab('遗址相关', NoteTargetType.SITE,
            this.countNotes.filter(n => n.targetType === NoteTargetType.SITE).length)
          this.FilterTab('文物相关', NoteTargetType.ARTIFACT,
            this.countNotes.filter(n => n.targetType === NoteTargetType.ARTIFACT).length)
        }
      }
      .scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off)
      .width('100%')
      .padding({ left: 12, right: 12 })

      // 内容
      if (this.isLoading) {
        Column() {
          LoadingProgress().width(28).height(28).color(colors.gold)
        }.width('100%').height(300).justifyContent(FlexAlign.Center)
      } else if (this.groups.length === 0) {
        EmptyState({ icon: '✍️', title: '纸墨已备', subtitle: '记录探访感悟、研究心得\n让文化记忆沉淀于此' })
          .padding({ top: 80 })
        Button('+ 写第一条笔记').fontSize(14).fontColor(colors.bg)
          .backgroundColor(colors.gold).height(40).borderRadius(2)
          .margin({ top: 16 })
          .onClick((): void => { this.goEdit(); })
      } else {
        Scroll() {
          Column({ space: 16 }) {
            ForEach(this.groups, (g: NoteGroup) => {
              Column({ space: 8 }) {
                Text(g.dateLabel)
                  .fontSize(12).fontColor(colors.textTertiary).letterSpacing(1)
                  .width('100%')
                  .padding({ bottom: 4 })
                  .border({ width: { bottom: 1 }, color: colors.border })
                ForEach(g.notes, (n: Note) => {
                  this.NoteCard(n)
                }, (n: Note) => n.id)
              }
            }, (g: NoteGroup) => g.dateLabel)
          }
          .padding({ left: 20, right: 20, top: 12, bottom: 32 })
        }
        .scrollBar(BarState.Off).edgeEffect(EdgeEffect.Spring).layoutWeight(1)
      }
    }
    .width('100%').height('100%').backgroundColor(colors.bg)
  }
}
