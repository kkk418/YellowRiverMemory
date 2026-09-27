/**
 * Loading 指示器（金色黄河水纹风）
 */
@Component
export struct LoadingIndicator {
  @State angle: number = 0;
  private timer?: number;

  aboutToAppear() {
    this.timer = setInterval(() => {
      this.angle = (this.angle + 6) % 360;
    }, 30);
  }

  aboutToDisappear() {
    if (this.timer) clearInterval(this.timer);
  }

  build() {
    Column({ space: 12 }) {
      Stack({ alignContent: Alignment.Center }) {
        Circle()
          .width(36).height(36)
          .fill(Color.Transparent)
          .stroke($r('app.color.gold_dim'))
          .strokeWidth(2)
        Circle()
          .width(36).height(36)
          .fill(Color.Transparent)
          .stroke($r('app.color.gold_primary'))
          .strokeWidth(2)
          .rotate({ angle: this.angle })
          .strokeDashArray([10, 20])
      }
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
