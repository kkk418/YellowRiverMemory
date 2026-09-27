import { TagMeta } from '../../common/constants/AppMeta';
import { colors } from '../../common/constants/Colors';

/**
 * 收藏标签选择Sheet（复用：遗址/文物详情页收藏时弹出）
 * 展示系统标签+已选标签+自定义标签输入
 */
@CustomDialog
export struct FavoriteTagSheet {
  controller: CustomDialogController;
  @State selectedTags: string[] = [];
  @State customInput: string = '';
  @State allExistingTags: string[] = [];
  private isSelected(t: TagMeta): boolean { return this.selectedTags.indexOf(t.code) >= 0; }
  onConfirm?: (tags: string[]) => void;
  targetName: string = '';

  aboutToAppear(): void {
    // 从TagMeta.ALL系统标签合并用户历史标签
    const sys = TagMeta.ALL.map(t => t.code);
    // 去重合并
    const set = new Set<string>(sys);
    this.allExistingTags.forEach(t => set.add(t));
    this.allExistingTags = Array.from(set);
  }

  private toggleTag(tag: string): void {
    const i = this.selectedTags.indexOf(tag);
    if (i >= 0) this.selectedTags.splice(i, 1);
    else this.selectedTags.push(tag);
  }

  private addCustom(): void {
    const t = this.customInput.trim();
    if (!t) return;
    if (this.selectedTags.indexOf(t) < 0) this.selectedTags.push(t);
    if (this.allExistingTags.indexOf(t) < 0) this.allExistingTags.push(t);
    this.customInput = '';
  }

  build() {
    Column({ space: 0 }) {
      // 顶部把手
      Column().width(40).height(4).borderRadius(2)
        .backgroundColor(colors.borderSub).margin({ top: 10, bottom: 16 })

      // 标题
      Column({ space: 4 }) {
        Text('为收藏添加标签')
          .fontSize(18).fontColor(colors.textPrimary).fontWeight(FontWeight.Medium)
        if (this.targetName) {
          Text(`《${this.targetName}》`)
            .fontSize(12).fontColor(colors.textTertiary).maxLines(1)
        }
      }
      .alignItems(HorizontalAlign.Start).width('100%')
      .padding({ left: 20, right: 20, bottom: 16 })

      Scroll() {
        Column({ space: 20 }) {
          // 系统推荐标签
          Column({ space: 10 }) {
            Text('系统标签').fontSize(12).fontColor(colors.textTertiary)
            Flex({ wrap: FlexWrap.Wrap, alignItems: ItemAlign.Start }) {
              ForEach(TagMeta.ALL, (t: TagMeta) => {
                Text(t.label)
                  .fontSize(13)
                  .fontColor(this.isSelected(t) ? colors.bg : colors.gold)
                  .padding({ left: 14, right: 14, top: 7, bottom: 7 })
                  .backgroundColor(this.isSelected(t) ? colors.gold : colors.gold10)
                  .borderRadius(20)
                  .border({ width: 1, color: this.isSelected(t) ? colors.gold : colors.goldDim })
                  .margin({ right: 8, bottom: 8 })
                  .onClick((): void => this.toggleTag(t.code))
              })
            }
          }
          .alignItems(HorizontalAlign.Start).width('100%')

          // 自定义标签输入
          Column({ space: 10 }) {
            Text('自定义标签').fontSize(12).fontColor(colors.textTertiary)
            Row({ space: 8 }) {
              TextInput({ placeholder: '输入标签后回车添加', text: this.customInput })
                .layoutWeight(1).height(36).fontSize(13)
                .backgroundColor(colors.bgElevated)
                .fontColor(colors.textPrimary)
                .placeholderColor(colors.textTertiary)
                .borderRadius(4)
                .padding({ left: 12, right: 12 })
                .onChange((v: string) => { this.customInput = v; })
              Button('添加')
                .height(36).fontSize(13)
                .backgroundColor(colors.gold).fontColor(colors.bg)
                .borderRadius(4)
                .onClick((): void => this.addCustom())
            }
          }
          .alignItems(HorizontalAlign.Start).width('100%')

          // 已选标签预览
          if (this.selectedTags.length > 0) {
            Column({ space: 10 }) {
              Text(`已选 ${this.selectedTags.length} 个`).fontSize(12).fontColor(colors.textTertiary)
              Flex({ wrap: FlexWrap.Wrap }) {
                ForEach(this.selectedTags, (t: string) => {
                  Row({ space: 4 }) {
                    Text(t).fontSize(12).fontColor(colors.bg)
                    Text('×').fontSize(14).fontColor(colors.bg).fontWeight(FontWeight.Bold)
                  }
                  .padding({ left: 10, right: 6, top: 5, bottom: 5 })
                  .backgroundColor(colors.goldDim)
                  .borderRadius(16)
                  .margin({ right: 6, bottom: 6 })
                  .onClick((): void => this.toggleTag(t))
                })
              }
            }
            .alignItems(HorizontalAlign.Start).width('100%')
          }
        }
        .padding({ left: 20, right: 20, bottom: 80 })
      }
      .layoutWeight(1)
      .scrollBar(BarState.Off)

      // 底部操作栏
      Row({ space: 12 }) {
        Button('跳过')
          .layoutWeight(1).height(44)
          .backgroundColor(colors.bgCard).fontColor(colors.textSecondary)
          .borderRadius(4)
          .border({ width: 1, color: colors.border })
          .onClick((): void => this.controller.close())
        Button('完成收藏')
          .layoutWeight(2).height(44)
          .backgroundColor(colors.gold).fontColor(colors.bg)
          .borderRadius(4)
          .fontWeight(FontWeight.Medium)
          .onClick((): void => {
            if (this.onConfirm) this.onConfirm([...this.selectedTags]);
            this.controller.close();
          })
      }
      .width('100%').padding(20)
      .backgroundColor(colors.bg)
    }
    .width('100%').height('65%')
    .backgroundColor(colors.bg)
    .borderRadius({ topLeft: 16, topRight: 16 })
  }
}
