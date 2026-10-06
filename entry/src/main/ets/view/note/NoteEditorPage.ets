import { colors } from '../../common/constants/Colors';
import { Note, Site, Artifact } from '../../model/entity/Entities';
import { NoteTargetType } from '../../common/constants/Enums';
import { UserDataService } from '../../service/UserDataService';
import { CultureService } from '../../service/CultureService';
import { DateUtil } from '../../common/utils/DateUtil';
import { StringUtil } from '../../common/utils/StringUtil';
import { EventBus, AppEvents } from '../../common/utils/EventBus';
import { TagMeta } from '../../common/constants/AppMeta';
import { NoteDraftService, NoteDraft } from '../../service/NoteDraftService';
import { NoteLeaveGuard } from '../../common/utils/NoteLeaveGuard';

/** 笔记编辑页参数 */
export interface NoteEditorParams {
  noteId?: string;         // 编辑已有笔记
  draftId?: string;        // 恢复本机草稿
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
  @State draftDirty: boolean = false;
  @State canSaveAsNew: boolean = false;
  @State targetId: string = '';
  private draftId: string = '';
  private draftBaseTime: number = 0;
  private draftBaseDevice: string = '';
  private draftTimer?: number;
  private draftWrite: Promise<void> = Promise.resolve();
  private backGuard = (): boolean => {
    if (this.saving || this.loadingNote) return true;
    if (!this.draftDirty) return false;
    this.confirmLeave();
    return true;
  };
  private isTagActive(t: TagMeta): boolean { return this.tags.includes(t.code) || this.tags.includes(t.label); }

  aboutToAppear(): void {
    NoteLeaveGuard.register(this.backGuard);
    this.loadingNote = true;
    this.draftId = this.params.draftId ??
      (this.params.noteId ? `note_${this.params.noteId}` : `new_${DateUtil.uuid()}`);
    this.targetId = this.params.targetId ?? '';
    setTimeout(async () => {
      this.errorMessage = '';
      if (this.params.noteId) {
        this.isEditMode = true;
        try {
          const n = await UserDataService.getInstance().getNoteById(this.params.noteId);
          if (!n || n.isDeleted !== 0) {
            this.existingNote = null;
            this.errorMessage = '原笔记已不存在；如有本机草稿，可另存为新笔记。';
          } else {
            this.existingNote = n;
            this.draftBaseTime = n.updatedAt;
            this.draftBaseDevice = n.deviceId;
            this.title = n.title;
            this.content = n.content;
            this.tags = StringUtil.parseTagsArray(n.tags);
            this.targetType = n.targetType;
            this.targetId = n.targetId ?? '';
            if (n.targetId) this.targetName = this.resolveTargetName(n.targetType, n.targetId);
          }
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
      try {
        const draft = await NoteDraftService.get(this.draftId);
        if (draft) {
          this.title = draft.title;
          this.content = draft.content;
          this.tags = StringUtil.parseTagsArray(draft.tags);
          this.targetType = draft.targetType;
          this.targetId = draft.targetId ?? '';
          this.draftBaseTime = draft.baseUpdatedAt;
          this.draftBaseDevice = draft.baseDeviceId;
          this.draftDirty = true;
          if (this.params.noteId && !this.existingNote) this.canSaveAsNew = true;
          if (this.params.noteId && this.existingNote &&
            (draft.baseUpdatedAt !== this.existingNote.updatedAt ||
              draft.baseDeviceId !== this.existingNote.deviceId)) {
            this.canSaveAsNew = true;
            this.errorMessage = '原笔记已在其他设备修改，草稿已保留。可另存为新笔记。';
          }
        }
      } catch (_) { this.errorMessage = '草稿读取失败，请稍后重试。'; }
      this.loadingNote = false;
    }, 30);
  }

  aboutToDisappear(): void {
    NoteLeaveGuard.unregister(this.backGuard);
    if (this.draftTimer) clearTimeout(this.draftTimer);
    if (this.draftDirty) this.saveDraft().catch(() => {});
  }

  private markDirty(): void {
    this.draftDirty = true;
    if (this.draftTimer) clearTimeout(this.draftTimer);
    this.draftTimer = setTimeout(() => {
      this.saveDraft().catch(() => { this.errorMessage = '草稿保存失败，请检查设备存储。'; });
    }, 350);
  }

  private async saveDraft(): Promise<void> {
    if (!this.draftDirty) return;
    const draft: NoteDraft = {
      id: this.draftId, noteId: this.params.noteId ?? null,
      title: this.title, content: this.content, targetType: this.targetType,
      targetId: this.targetId || null, tags: StringUtil.toTagsArray(this.tags),
      baseUpdatedAt: this.draftBaseTime,
      baseDeviceId: this.draftBaseDevice, savedAt: Date.now(),
    };
    this.draftWrite = this.draftWrite.catch(() => {}).then(() => NoteDraftService.save(draft));
    await this.draftWrite;
  }

  private async clearDraft(): Promise<void> {
    if (this.draftTimer) clearTimeout(this.draftTimer);
    await this.draftWrite.catch(() => {});
    await NoteDraftService.delete(this.draftId);
    this.draftDirty = false;
  }

  private confirmLeave(): void {
    AlertDialog.show({
      title: '保留未保存的笔记？',
      message: '当前输入会保存在本机草稿中，下次可继续编辑。',
      primaryButton: { value: '保留草稿并离开', action: () => {
        this.saveDraft().then(() => this.navPathStack.pop())
          .catch(() => { this.errorMessage = '草稿保存失败，已留在编辑页。'; });
      } },
      secondaryButton: { value: '继续编辑', action: () => {} },
    });
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
      this.canSaveAsNew = true;
      this.errorMessage = '原笔记已不存在，当前内容可另存为新笔记。';
      return;
    }
    if (this.canSaveAsNew) {
      this.errorMessage = '当前草稿与其他设备版本冲突，请使用“另存为新笔记”。';
      return;
    }
    if (!this.title.trim() && !this.content.trim()) {
      if (this.isEditMode) {
        this.errorMessage = '标题和正文不能同时为空。';
      } else {
        try { await this.clearDraft(); this.navPathStack.pop(); }
        catch (_) { this.errorMessage = '草稿清理失败，请重试。'; }
      }
      return;
    }
    this.saving = true;
    try {
      if (this.draftTimer) clearTimeout(this.draftTimer);
      await this.draftWrite.catch(() => {});
      const svc = UserDataService.getInstance();
      if (this.isEditMode && this.existingNote) {
        await svc.updateNote(this.existingNote.id, this.title.trim() || '无题',
          this.content, this.tags, this.existingNote.updatedAt, this.existingNote.deviceId, this.draftId);
      } else {
        await svc.addNote(this.title.trim() || '无题', this.content,
          this.targetType, this.targetId || undefined, this.tags, this.draftId);
      }
      this.draftDirty = false;
      this.saving = false;
      this.navPathStack.pop();
    } catch (e) {
      const conflict = String(e).includes('笔记已在其他设备修改或删除');
      if (conflict) {
        this.canSaveAsNew = true;
        this.draftDirty = true;
        await this.saveDraft().catch(() => {});
      }
      this.errorMessage = conflict ?
        '笔记已在其他设备修改，当前输入已保留，可另存为新笔记。' :
        '保存失败，请稍后重试。';
    } finally {
      this.saving = false;
    }
  }

  private async saveAsNew(): Promise<void> {
    if (this.saving || this.loadingNote) return;
    this.saving = true;
    try {
      if (this.draftTimer) clearTimeout(this.draftTimer);
      await this.draftWrite.catch(() => {});
      await UserDataService.getInstance().addNote(this.title.trim() || '无题', this.content,
        this.targetType, this.targetId || undefined, this.tags, this.draftId);
      this.draftDirty = false;
      this.navPathStack.pop();
    } catch (_) {
      this.errorMessage = '另存失败，草稿仍保存在本机。';
    } finally { this.saving = false; }
  }

  private async doDelete(): Promise<void> {
    if (this.saving || this.loadingNote || !this.isEditMode || !this.existingNote) return;
    this.saving = true;
    this.errorMessage = '';
    try {
      if (this.draftTimer) clearTimeout(this.draftTimer);
      await this.draftWrite.catch(() => {});
      await UserDataService.getInstance().deleteNote(this.existingNote.id,
        this.existingNote.updatedAt, this.existingNote.deviceId, this.draftId);
      this.draftDirty = false;
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
    .onClick((): void => {
      if (this.saving || this.loadingNote) return;
      if (this.draftDirty) this.confirmLeave();
      else this.navPathStack.pop();
    })
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
      if (removable) { this.tags = this.tags.filter(t => t !== tag); this.markDirty(); }
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
      if (this.canSaveAsNew) {
        Button('另存为新笔记').onClick((): void => { this.saveAsNew(); })
          .margin({ left: 20, right: 20, top: 8 }).backgroundColor(colors.gold)
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
            .enabled(!this.saving && !this.loadingNote)
            .fontSize(20).fontWeight(FontWeight.Medium)
            .fontColor(colors.textPrimary)
            .placeholderColor(colors.textTertiary)
            .backgroundColor(Color.Transparent)
            .padding(0)
            .maxLength(50)
            .onChange((v: string) => {
              if (v !== this.title && !this.loadingNote && !this.saving) {
                this.title = v; this.markDirty();
              }
            })

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
            .enabled(!this.saving && !this.loadingNote)
            .constraintSize({ minHeight: 180 })
            .fontSize(15).fontColor(colors.textPrimary)
            .placeholderColor(colors.textTertiary)
            .backgroundColor(Color.Transparent)
            .padding(0)
            .lineHeight(26)
            .onChange((v: string) => {
              if (v !== this.content && !this.loadingNote && !this.saving) {
                this.content = v; this.markDirty();
              }
            })

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
        .width('100%')
        .constraintSize({ maxWidth: 820 })
        .alignSelf(ItemAlign.Center)
      }
      .layoutWeight(1)
      .width('100%')
      .align(Alignment.Top)
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
              this.markDirty();
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
            this.markDirty();
          }
          this.showTagSheet = false;
        })
    }
    .width('100%').padding({ left: 20, right: 20, bottom: 24 })
  }
}
