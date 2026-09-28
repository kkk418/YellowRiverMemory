import { colors } from '../../common/constants/Colors';
import { Note, Site, Artifact } from '../../model/entity/Entities';
import { NoteTargetType } from '../../common/constants/Enums';
import { UserDataService } from '../../service/UserDataService';
import { CultureService } from '../../service/CultureService';
import { DateUtil } from '../../common/utils/DateUtil';
import { StringUtil } from '../../common/utils/StringUtil';
import { EventBus, AppEvents } from '../../common/utils/EventBus';
import { TagMeta } from '../../common/constants/AppMeta';

/** 笔记编辑页参数 */
export interface NoteEditorParams {
  noteId?: string;         // 编辑已有笔记
  targetType?: NoteTargetType;
  targetId?: string;       // 关联的遗址/文物ID（新建时）
  targetName?: string;     // 关联对象名称（用于顶部显示）
}

@Component
export struct NoteEditorPage {
  @Consume('navPathStack') navPathStack: NavPathStack;
  @State params: NoteEditorParams = {};

  @State title: string = '';
  @State content: string = '';
  @State tags: string[] = [];
  @State isEditMode: boolean = false;
  @State existingNote: Note | null = null;
  @State targetName: string = '';
  @State targetType: NoteTargetType = NoteTargetType.STANDALONE;
  @State showTagSheet: boolean = false;
  @State newTagInput: string = '';
  @State saving: boolean = false;
  @State loadingNote: boolean = true;
  @State errorMessage: string = '';
  private isTagActive(t: TagMeta): boolean { return this.tags.includes(t.code) || this.tags.includes(t.label); }

  aboutToAppear(): void {
    this.loadingNote = true;
    setTimeout(async () => {
      this.errorMessage = '';
      if (this.params.noteId) {
        this.isEditMode = true;
        try {
          const n = await UserDataService.getInstance().getNoteById(this.params.noteId);
          if (!n || n.isDeleted !== 0) {
            this.existingNote = null;
            this.errorMessage = '这条笔记已不存在或已在其他设备删除，请返回笔记列表。';
            this.loadingNote = false;
            return;
          }
          this.existingNote = n;
          this.title = n.title;
          this.content = n.content;
          this.tags = StringUtil.parseTagsArray(n.tags);
          this.targetType = n.targetType;
          if (n.targetId) this.targetName = this.resolveTargetName(n.targetType, n.targetId);
        } catch (_) {
          this.errorMessage = '笔记加载失败，请返回后重试。';
        }
      } else {
        this.isEditMode = false;
        this.title = '';
        this.content = '';
        this.tags = [];
        if (this.params.targetType) this.targetType = this.params.targetType;
        if (this.params.targetId && this.params.targetName) {
          this.targetName = this.params.targetName;
        } else if (this.params.targetId) {
          this.targetName = this.resolveTargetName(this.targetType, this.params.targetId);
        }
      }
      this.loadingNote = false;
    }, 30);
  }

  private resolveTargetName(type: NoteTargetType, id: string): string {
    if (type === NoteTargetType.SITE) {
      const s = CultureService.getInstance().getSiteByIdSync(id);
      return s ? s.name : '';
    }
    if (type === NoteTargetType.ARTIFACT) {
      const a = CultureService.getInstance().getArtifactByIdSync(id);
      return a ? a.name : '';
    }
    return '';
  }

  private async doSave(): Promise<void> {
    if (this.saving || this.loadingNote) return;
    this.errorMessage = '';
    if (this.isEditMode && !this.existingNote) {
      this.errorMessage = '无法保存：原笔记已不存在，请返回笔记列表。';
      return;
    }
    if (!this.title.trim() && !this.content.trim()) {
      if (this.isEditMode) {
        this.errorMessage = '标题和正文不能同时为空。';
      } else {
        this.navPathStack.pop();
      }
      return;
    }
    this.saving = true;
    try {
      const svc = UserDataService.getInstance();
      if (this.isEditMode && this.existingNote) {
        await svc.updateNote(this.existingNote.id, this.title.trim() || '无题',
          this.content, this.tags, this.existingNote.updatedAt, this.existingNote.deviceId);
      } else {
        await svc.addNote(this.title.trim() || '无题', this.content,
          this.targetType, this.params.targetId, this.tags);
      }
      EventBus.getInstance().emit(AppEvents.NOTE_CHANGED, {});
      this.saving = false;
      this.navPathStack.pop();
    } catch (e) {
      this.errorMessage = String(e).includes('笔记已在其他设备修改或删除') ?
        '笔记已在其他设备修改或删除，当前编辑内容未保存。请返回后重新打开笔记。' :
        '保存失败，请稍后重试。';
    } finally {
      this.saving = false;
    }
  }

  private async doDelete(): Promise<void> {
    if (this.saving || this.loadingNote || !this.isEditMode || !this.existingNote) return;
    this.saving = true;
    this.errorMessage = '';
    try {
      await UserDataService.getInstance().deleteNote(this.existingNote.id,
        this.existingNote.updatedAt, this.existingNote.deviceId);
      EventBus.getInstance().emit(AppEvents.NOTE_CHANGED, {});
      this.navPathStack.pop();
    } catch (e) {
      this.errorMessage = '删除失败，请稍后重试。';
    } finally {
      this.saving = false;
    }
  }

  @Builder BackButton() {
    Row({ space: 4 }) {
      Text('‹').fontSize(22).fontColor(colors.gold)
      Text('返回').fontSize(14).fontColor(colors.gold)
    }
    .padding({ left: 4, right: 12, top: 8, bottom: 8 })
    .onClick((): void => { this.navPathStack.pop(); })
  }

  @Builder TagPill(tag: string, removable: boolean = true) {
    Row({ space: 4 }) {
      Text(`# ${tag}`).fontSize(12).fontColor(colors.gold)
      if (removable) {
        Text('×').fontSize(12).fontColor(colors.textTertiary).margin({ left: 2 })
      }
    }
    .padding({ left: 10, right: removable ? 6 : 10, top: 5, bottom: 5 })
    .backgroundColor(colors.gold20)
    .borderRadius(2)
    .onClick((): void => {
      if (removable) this.tags = this.tags.filter(t => t !== tag);
    })
  }

  build() {
    Column({ space: 0 }) {
      // 顶部栏
      Row() {
        this.BackButton()
        Text(this.isEditMode ? '编辑笔记' : '新建笔记')
          .fontSize(16).fontWeight(FontWeight.Medium).fontColor(colors.textPrimary)
          .layoutWeight(1).textAlign(TextAlign.Center)
        Row({ space: 16 }) {
          if (this.isEditMode && this.existingNote) {
            Text('删除').fontSize(13).fontColor(colors.cinnabar).onClick((): void => { this.doDelete(); })
          }
          Text(this.loadingNote ? '加载中…' : this.saving ? '处理中…' : '保存').fontSize(14)
            .fontColor(this.saving || this.loadingNote ? colors.textTertiary : colors.gold)
            .fontWeight(FontWeight.Medium)
            .onClick((): void => { this.doSave(); })
        }
      }
      .width('100%').height(56).padding({ left: 8, right: 16 })
      .backgroundColor(colors.bgCard)

      if (this.errorMessage) {
        Text(this.errorMessage).fontSize(12).fontColor(colors.cinnabar)
          .width('100%').padding({ left: 20, right: 20, top: 8, bottom: 8 })
      }

      Scroll() {
        Column({ space: 16 }) {
          // 关联对象提示
          if (this.targetName) {
            Row({ space: 8 }) {
              Text('📎').fontSize(14)
              Text(`关联：${this.targetName}`)
                .fontSize(13).fontColor(colors.textSecondary)
            }
            .width('100%')
            .padding(12)
            .backgroundColor(colors.gold10)
            .borderRadius(2)
            .border({ width: 1, color: colors.goldDim })
          }

          // 标题
          TextArea({ placeholder: '为这条笔记起一个标题…', text: this.title })
            .fontSize(20).fontWeight(FontWeight.Medium)
            .fontColor(colors.textPrimary)
            .placeholderColor(colors.textTertiary)
            .backgroundColor(Color.Transparent)
            .padding(0)
            .maxLength(50)
            .onChange((v: string) => { this.title = v; })

          // 金色分割线
          Divider().color(colors.goldDim).strokeWidth(1).width(40)

          // 时间戳
          Text(this.isEditMode && this.existingNote ?
            `最后修改于 ${DateUtil.formatDateTime(this.existingNote.updatedAt)}` :
            `${DateUtil.formatDateTime(Date.now())}`)
            .fontSize(11).fontColor(colors.textTertiary)
            .width('100%')

          // 正文
          TextArea({ placeholder: '在此记录你的阅读感受、研究思考、探访规划……', text: this.content })
            .fontSize(15).fontColor(colors.textPrimary)
            .placeholderColor(colors.textTertiary)
            .backgroundColor(Color.Transparent)
            .padding(0)
            .lineHeight(26)
            .onChange((v: string) => { this.content = v; })

          // 标签区
          Column({ space: 10 }) {
            Text('标签')
              .fontSize(13).fontWeight(FontWeight.Medium).fontColor(colors.textSecondary)
              .width('100%')
            if (this.tags.length > 0) {
              Flex({ wrap: FlexWrap.Wrap }) {
                ForEach(this.tags, (t: string) => { this.TagPill(t); })
              }
              .width('100%')
            }
            Button($r('app.string.note_add_tag'))
              .fontSize(12).fontColor(colors.gold).height(32)
              .backgroundColor(Color.Transparent).borderRadius(2)
              .border({ width: 1, color: colors.goldDim })
              .onClick((): void => {
                this.newTagInput = '';
                this.showTagSheet = true;
              })
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
          .padding({ top: 16 })
        }
        .padding(20)
      }
      .layoutWeight(1)
      .scrollBar(BarState.Off)
    }
    .width('100%').height('100%').backgroundColor(colors.bg)
    .bindSheet(this.showTagSheet, this.TagSheet(), {
      height: 400, dragBar: true, backgroundColor: colors.bgCard,
      onDisappear: (): void => { this.showTagSheet = false; }
    })
  }

  @Builder TagSheet() {
    Column({ space: 12 }) {
      Text('添加标签').fontSize(16).fontWeight(FontWeight.Medium).fontColor(colors.textPrimary)
        .margin({ top: 20 })
      // 输入框
      TextInput({ placeholder: '输入自定义标签…', text: this.newTagInput })
        .width('100%').height(40)
        .backgroundColor(colors.bgElevated)
        .fontColor(colors.textPrimary)
        .placeholderColor(colors.textTertiary)
        .borderRadius(2)
        .padding({ left: 12, right: 12 })
        .onChange((v: string) => { this.newTagInput = v; })
      // 预设标签
      Text('常用标签').fontSize(12).fontColor(colors.textTertiary).width('100%').margin({ top: 8 })
      Flex({ wrap: FlexWrap.Wrap }) {
        ForEach(TagMeta.ALL, (t: TagMeta) => {
          Text(t.label).fontSize(12).fontColor(this.isTagActive(t) ? colors.bg : t.colorRes)
            .padding({ left: 12, right: 12, top: 6, bottom: 6 })
            .backgroundColor(this.isTagActive(t) ? t.colorRes : colors.bgElevated)
            .borderRadius(2)
            .onClick((): void => {
              if (this.isTagActive(t)) this.tags = this.tags.filter(x => x !== t.code && x !== t.label);
              else this.tags = [...this.tags, t.label];
            })
        })
      }
      .width('100%')
      // 确认按钮
      Button(this.newTagInput ? '添加此标签' : '完成')
        .width('100%').height(44).fontSize(14)
        .backgroundColor(colors.gold).fontColor(colors.bg)
        .borderRadius(2)
        .margin({ top: 16 })
        .onClick((): void => {
          if (this.newTagInput.trim()) {
            const v = this.newTagInput.trim();
            if (!this.tags.includes(v)) this.tags = [...this.tags, v];
          }
          this.showTagSheet = false;
        })
    }
    .width('100%').padding({ left: 20, right: 20, bottom: 24 })
  }
}
