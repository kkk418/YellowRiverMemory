/**
 * 标签 Chip（筛选/标签选择）
 */
@Component
export struct TagChip {
  label: string = '';
  selected: boolean = false;
  onTap?: () => void = undefined;

  build() {
    Text(this.label)
      .fontSize(12)
      .fontColor(this.selected ? $r('app.color.tag_text_selected') : $r('app.color.tag_text_default'))
      .padding({ left: 12, right: 12, top: 6, bottom: 6 })
      .backgroundColor(this.selected ? $r('app.color.tag_bg_selected') : $r('app.color.tag_bg_default'))
      .borderRadius(2)
      .border({
        width: this.selected ? 1 : 0.5,
        color: this.selected ? $r('app.color.tag_border_selected') : $r('app.color.ink_line'),
      })
      .margin({ right: 8, bottom: 8 })
      .onClick(() => {
        if (this.onTap) this.onTap();
      })
  }
}
