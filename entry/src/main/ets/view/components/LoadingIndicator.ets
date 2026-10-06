/**
 * Loading 指示器（金色黄河水纹风）
 */
@Component
export struct LoadingIndicator {
  build() {
    Column({ space: 12 }) {
      LoadingProgress().width(36).height(36).color($r('app.color.gold_primary'))
      Text('金卷徐展…')
        .fontSize(11)
        .fontColor($r('app.color.text_tertiary'))
        .letterSpacing(2)
    }
    .width('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
  }
}
