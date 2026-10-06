import { Site } from '../../model/entity/Entities';
import { EraMeta, CityMeta, SiteTypeMeta } from '../../common/constants/AppMeta';
import { colors } from '../../common/constants/Colors';
import { LicensedCover } from './LicensedCover';

/**
 * 遗址卡片（数字敦煌"洞窟卡片"风格）
 * 大图/渐变封面 + 底部渐变叠字 + 金色标签
 */
@Component
export struct SiteCard {
  @Prop site: Site;
  onTap?: () => void;
  @State isHover: boolean = false;
  private siteEra(): EraMeta | undefined { return EraMeta.getByCode(this.site.era); }
  private siteCity(): CityMeta | undefined { return CityMeta.getByCode(this.site.city); }

  build() {
    Column({ space: 0 }) {
      Stack({ alignContent: Alignment.BottomStart }) {
        // 年代色渐变封面（图片占位）
        Stack({ alignContent: Alignment.Center }) {
          LicensedCover({ path: this.site.coverImage ?? '', tint: this.siteEra()?.colorRes ?? colors.borderSub })
            .width('100%').height(200)
          // 装饰纹样
          Text('◇')
            .fontSize(60).fontColor(colors.goldDim).opacity(0.15)
            .position({ x: '70%', y: 20 })
          // 主标题
          Column({ space: 4 }) {
            Text(this.site.name)
              .fontSize(22).fontColor(colors.ricePaper).fontWeight(FontWeight.Medium)
              .textShadow({ radius: 8, color: '#000000CC', offsetX: 0, offsetY: 2 })
            if (this.site.nameEn) {
              Text(this.site.nameEn.toUpperCase())
                .fontSize(9).letterSpacing(3).fontColor(colors.goldDim)
            }
          }
          .padding(16).alignItems(HorizontalAlign.Start)
        }
        .width('100%').height(200)

        // 顶部渐变遮罩（让底部标签更清晰）
        Column().width('100%').height(80)
          .linearGradient({ angle: 0, colors: [[Color.Transparent, 0], [colors.bg, 1]] })

        // 左下角：年代+城市标签
        Row({ space: 6 }) {
          Text(this.siteEra()?.label ?? '')
            .fontSize(10).fontColor(colors.gold)
            .padding({ left: 8, right: 8, top: 3, bottom: 3 })
            .backgroundColor(colors.gold20)
            .borderRadius(2)
          if (this.siteCity()) {
            Text(this.siteCity()!.label)
              .fontSize(10).fontColor(colors.textSecondary)
              .padding({ left: 8, right: 8, top: 3, bottom: 3 })
              .backgroundColor(colors.bgElevated)
              .borderRadius(2)
          }
        }
        .padding(12)
      }
      .width('100%').height(200)
      .clip(true)

      // 底部信息条
      Column({ space: 6 }) {
        Text(this.site.summary)
          .fontSize(12).fontColor(colors.textSecondary)
          .maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
          .lineHeight(18)
        Row({ space: 8 }) {
          Text(`${this.site.artifactCount ?? 0} 件馆藏`).fontSize(10).fontColor(colors.textTertiary)
          Text('·').fontSize(10).fontColor(colors.textTertiary)
          Text(SiteTypeMeta.getByCode(this.site.type)?.label ?? this.site.type)
            .fontSize(10).fontColor(colors.textTertiary)
        }
      }
      .width('100%').padding(12)
      .backgroundColor(colors.bgCard)
    }
    .width('100%')
    .borderRadius(2)
    .border({ width: 1, color: colors.border })
    .clip(true)
    .onClick((): void => { if (this.onTap) this.onTap(); })
  }
}
