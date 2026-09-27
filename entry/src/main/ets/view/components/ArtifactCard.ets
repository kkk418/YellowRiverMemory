import { Artifact } from '../../model/entity/Entities';
import { EraMeta, ArtifactTypeMeta } from '../../common/constants/AppMeta';
import { colors } from '../../common/constants/Colors';

/**
 * 文物卡片：正方形色块+名称
 */
@Component
export struct ArtifactCard {
  @Prop artifact: Artifact;
  onTap?: () => void;
  private artifactEra(): EraMeta | undefined { return EraMeta.getByCode(this.artifact.era); }
  private artifactType(): ArtifactTypeMeta | undefined { return ArtifactTypeMeta.getByCode(this.artifact.type); }

  build() {
    Column({ space: 0 }) {
      // 封面（朝代色渐变+文物名水印）
      Stack({ alignContent: Alignment.Center }) {
        Column()
          .width('100%')
          .layoutWeight(1)
          .linearGradient({
            angle: 160,
            colors: [[this.artifactEra()?.colorRes ?? colors.goldDim, 0], [colors.bgElevated, 0.6], [colors.bgCard, 1]],
          });
        Column({ space: 4 }) {
          if (this.artifact.isNationalTreasure === 1) {
            Text('国宝').fontSize(9).fontColor(colors.bg)
              .padding({ left: 6, right: 6, top: 2, bottom: 2 })
              .backgroundColor(colors.cinnabar).borderRadius(2)
              .margin({ bottom: 2 })
          }
          Text(this.artifact.name)
            .fontSize(14).fontColor(colors.ricePaper).fontWeight(FontWeight.Medium)
            .textAlign(TextAlign.Center).maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .textShadow({ radius: 4, color: '#000000AA', offsetX: 0, offsetY: 1 })
        }
        .padding(8)
      }
      .width('100%').height(120)

      // 底部信息
      Column({ space: 3 }) {
        Row() {
          Text(this.artifact.name)
            .fontSize(12).fontColor(colors.textPrimary).maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis }).layoutWeight(1)
        }
        .width('100%')
        Text(`${this.artifactEra()?.label ?? ''} · ${this.artifactType()?.label ?? ''}`)
          .fontSize(10).fontColor(colors.textTertiary).maxLines(1)
        if (this.artifact.material) {
          Text(this.artifact.material).fontSize(10).fontColor(colors.textTertiary)
            .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
        }
      }
      .width('100%').padding(10)
      .backgroundColor(colors.bgCard)
    }
    .width('100%').borderRadius(2)
    .border({ width: 1, color: colors.border })
    .clip(true)
    .onClick((): void => { if (this.onTap) this.onTap(); })
  }
}
