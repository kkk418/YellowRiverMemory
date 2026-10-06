import { EraMeta } from '../../common/constants/AppMeta';

/**
 * 年代时间轴（仰韶→宋金）
 * 圆点 + 连线 + 年代名称 + 年代色
 */
@Component
export struct EraTimeline {
  build() {
    Column() {
      // 横向时间轴：用Row滚动
      Scroll() {
        Row({ space: 0 }) {
          ForEach(EraMeta.ALL, (era: EraMeta, index: number) => {
            Row({ space: 0 }) {
              // 节点
              Column({ space: 6 }) {
                Text(era.pinyin.toUpperCase())
                  .fontSize(8)
                  .letterSpacing(1)
                  .fontColor(era.colorRes)
                Text(era.name)
                  .fontSize(12)
                  .fontColor($r('app.color.text_primary'))
                Column().width(8).height(8).borderRadius(4).backgroundColor(era.colorRes)
                Text(era.yearRange)
                  .fontSize(9)
                  .fontColor($r('app.color.text_tertiary'))
                  .margin({ top: 4 })
              }
              .alignItems(HorizontalAlign.Center)
              .width(96)
              // 连线
              if (index < EraMeta.ALL.length - 1) {
                Divider()
                  .color(era.colorRes)
                  .width(24)
                  .strokeWidth(1)
                  .vertical(false)
                  .alignSelf(ItemAlign.Center)
                  .margin({ bottom: 36 })
              }
            }
          })
        }
        .padding({ left: 8, right: 16 })
      }
      .scrollable(ScrollDirection.Horizontal)
      .scrollBar(BarState.Off)
    }
    .width('100%')
    .padding({ top: 12, bottom: 12 })
    .backgroundColor($r('app.color.ink_wall_card'))
    .borderRadius(2)
    .border({ width: { top: 2 }, color: $r('app.color.gold_dim') })
  }
}
