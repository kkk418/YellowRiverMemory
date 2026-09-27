/**
 * 空状态占位：纸墨已备 / 尚无内容
 */
@Component
export struct EmptyState {
  icon: string = '纸';
  title: string = '纸墨已备';
  subtitle: string = '内容尚待翻阅，去首页探索文化遗址吧';
  @BuilderParam action?: CustomBuilder;

  build() {
    Column({ space: 12 }) {
      // 印章式圆形占位
      Stack({ alignContent: Alignment.Center }) {
        Circle()
          .width(72).height(72)
          .fill($r('app.color.gold_10'))
          .stroke($r('app.color.gold_dim'))
          .strokeWidth(1)
        Text(this.icon)
          .fontSize(30)
          .fontColor($r('app.color.gold_primary'))
          .fontWeight(FontWeight.Bold)
      }
      Text(this.title)
        .fontSize(15)
        .fontColor($r('app.color.text_secondary'))
        .letterSpacing(1)
      Text(this.subtitle)
        .fontSize(11)
        .fontColor($r('app.color.text_tertiary'))
      if (this.action) {
        Column() {
          this.action()
        }
        .margin({ top: 8 })
      }
    }
    .width('100%')
    .padding({ top: 60, bottom: 60 })
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
  }
}
