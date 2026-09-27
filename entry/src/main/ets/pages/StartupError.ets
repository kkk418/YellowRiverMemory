@Entry
@Component
struct StartupError {
  build() {
    Column({ space: 14 }) {
      Text('黄河记忆')
        .fontSize(28)
        .fontWeight(FontWeight.Bold)
        .fontColor('#C9A96E')
      Text('数据初始化失败')
        .fontSize(20)
        .fontColor(Color.White)
      Text('请关闭应用后重试。若问题持续，请保留设备日志以便排查。')
        .fontSize(14)
        .fontColor('#B8AEA0')
        .textAlign(TextAlign.Center)
    }
    .width('100%')
    .height('100%')
    .padding(24)
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .backgroundColor('#0A0806')
  }
}
