import { image } from '@kit.ImageKit';
import { PreferencesHelper } from '../../common/utils/PreferencesHelper';
import { colors } from '../../common/constants/Colors';

/** Bundled cover with an explicit fallback for missing or undecodable files. */
@Component
export struct LicensedCover {
  @Prop @Watch('onPathChanged') path: string = '';
  @Prop tint: ResourceColor = colors.goldDim;
  @State picture: image.PixelMap | null = null;
  @State failed: boolean = false;
  private loadGeneration: number = 0;

  aboutToAppear(): void { this.load(); }
  private onPathChanged(): void { this.load(); }

  aboutToDisappear(): void {
    this.loadGeneration++;
    this.picture?.release();
    this.picture = null;
  }

  private async load(): Promise<void> {
    const generation = ++this.loadGeneration;
    this.picture?.release();
    this.picture = null;
    this.failed = false;
    if (!this.path) return;
    try {
      const bytes = await PreferencesHelper.getContext().resourceManager.getRawFileContent(this.path);
      const source = image.createImageSource(bytes.buffer);
      try {
        const info = await source.getImageInfo();
        const scale = Math.min(1, 1200 / Math.max(info.size.width, info.size.height));
        const picture = await source.createPixelMap({ desiredSize: {
          width: Math.max(1, Math.round(info.size.width * scale)),
          height: Math.max(1, Math.round(info.size.height * scale)),
        } });
        if (generation !== this.loadGeneration) picture.release();
        else this.picture = picture;
      } finally { source.release(); }
    } catch (_) {
      if (generation === this.loadGeneration) this.failed = true;
    }
  }

  build() {
    Stack({ alignContent: Alignment.TopEnd }) {
      Column().width('100%').height('100%').linearGradient({
        angle: 145, colors: [[this.tint, 0], [colors.bgElevated, 0.55], [colors.bg, 1]],
      })
      if (this.picture && !this.failed) {
        Image(this.picture).width('100%').height('100%').objectFit(ImageFit.Cover)
          .onError((): void => { this.failed = true; })
      } else {
        Text('暂无授权图片').fontSize(10).fontColor(colors.ricePaper).opacity(0.8)
          .padding(6).backgroundColor('#30282088').borderRadius(2)
          .margin({ top: 8, right: 8 })
      }
    }.width('100%').height('100%').clip(true)
  }
}
