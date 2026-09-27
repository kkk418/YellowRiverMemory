/**
 * 预置资源仓库：负责从 rawfile 读取 JSON 数据，并在首次启动时导入 RDB
 */
import { resourceManager } from '@kit.LocalizationKit';
import { util } from '@kit.ArkTS';
import { Context } from '@kit.AbilityKit';
import { Logger } from '../common/utils/Logger';
import { LocalRdbHelper } from './LocalRdbHelper';
import { Site, Artifact, Poetry } from '../model/entity/Entities';
import { DateUtil } from '../common/utils/DateUtil';
import { PreferencesHelper } from '../common/utils/PreferencesHelper';
import { AppConstants } from '../common/constants/AppMeta';

const TAG = 'AssetRepository';

interface PresetData {
  sites: Site[];
  artifacts: Artifact[];
  poetries: Poetry[];
}

export class AssetRepository {
  private static initialized = false;

  /**
   * 启动时调用：读取rawfile/data/preset.json并写入RDB
   * 仅在首次启动（或预置数据版本升级）时执行
   */
  static async initIfNeeded(resMgr: resourceManager.ResourceManager): Promise<void> {
    if (AssetRepository.initialized) return;
    const currentVersion = AppConstants.PRESET_VERSION;
    const installedVersion = await PreferencesHelper.getDataVersion();
    if (installedVersion >= currentVersion) {
      Logger.info(TAG, `Preset data already loaded (v${installedVersion}), skip.`);
      AssetRepository.initialized = true;
      return;
    }
    try {
      const text = await AssetRepository.readRawText(resMgr, 'data/preset.json');
      const data: PresetData = JSON.parse(text) as PresetData;
      const existing = await LocalRdbHelper.count('site');
      if (existing > 0) {
        // Keep user data and existing primary keys while filling fields added in schema v2.
        await AssetRepository.backfillExistingRows(data);
        await PreferencesHelper.setDataVersion(currentVersion);
        AssetRepository.initialized = true;
        Logger.info(TAG, `Existing cultural data found (${existing} sites); preset fields backfilled.`);
        return;
      }
      await AssetRepository.importToRdb(data);
      await PreferencesHelper.setDataVersion(currentVersion);
      AssetRepository.initialized = true;
      Logger.info(TAG, `Preset data imported: sites=${data.sites.length}, artifacts=${data.artifacts.length}, poetries=${data.poetries.length}`);
    } catch (e) {
      Logger.error(TAG, `Preset import failed: ${e}`);
      throw new Error(String(e));
    }
  }

  /**
   * 读取 rawfile 文本内容
   */
  static async readRawText(resMgr: resourceManager.ResourceManager, rawPath: string): Promise<string> {
    const file = await resMgr.getRawFileContent(rawPath);
    const buffer = file.buffer;
    const textDecoder = util.TextDecoder.create('utf-8', { ignoreBOM: true });
    return textDecoder.decodeToString(new Uint8Array(buffer));
  }

  /**
   * 通过Context读取rawfile文本
   */
  static async readRawFile(context: Context, rawPath: string): Promise<string> {
    const resMgr = context.resourceManager;
    return AssetRepository.readRawText(resMgr, rawPath);
  }

  private static nationalTreasureFlag(artifact: Artifact): number {
    return artifact.isNationalTreasure ?? (artifact.level?.startsWith('国宝级') ? 1 : 0);
  }

  private static async backfillExistingRows(data: PresetData): Promise<void> {
    await LocalRdbHelper.runInTransaction(async () => {
      for (const artifact of data.artifacts) {
        await LocalRdbHelper.execute(
          'UPDATE artifact SET isNationalTreasure=? WHERE id=?',
          [AssetRepository.nationalTreasureFlag(artifact), artifact.id]);
      }
      const importedAt = DateUtil.now();
      for (const poetry of data.poetries) {
        await LocalRdbHelper.execute(
          'UPDATE poetry SET createdAt=? WHERE id=? AND (createdAt IS NULL OR createdAt=0)',
          [poetry.createdAt ?? importedAt, poetry.id]);
      }
    });
  }

  private static async importToRdb(data: PresetData): Promise<void> {
    await LocalRdbHelper.runInTransaction(async () => {
      for (const site of data.sites) {
        if (!site.createdAt) site.createdAt = DateUtil.now();
        if (!site.updatedAt) site.updatedAt = site.createdAt;
        await LocalRdbHelper.insert('site', {
          'id': site.id,
          'name': site.name,
          'nameEn': site.nameEn ?? null,
          'era': site.era,
          'type': site.type,
          'city': site.city,
          'yearStart': site.yearStart ?? null,
          'yearEnd': site.yearEnd ?? null,
          'latitude': site.latitude ?? null,
          'longitude': site.longitude ?? null,
          'coverImage': site.coverImage,
          'summary': site.summary,
          'overview': site.overview,
          'archaeology': site.archaeology ?? null,
          'historicalEvents': site.historicalEvents ?? null,
          'travelInfo': site.travelInfo ?? null,
          'highlight': site.highlight ?? null,
          'artifactCount': site.artifactCount ?? 0,
          'viewCount': 0,
          'isFeatured': site.isFeatured ?? 0,
          'createdAt': site.createdAt,
          'updatedAt': site.updatedAt,
        });
      }
      for (const a of data.artifacts) {
        if (!a.createdAt) a.createdAt = DateUtil.now();
        if (!a.updatedAt) a.updatedAt = a.createdAt;
        await LocalRdbHelper.insert('artifact', {
          'id': a.id,
          'name': a.name,
          'nameEn': a.nameEn ?? null,
          'era': a.era,
          'type': a.type,
          'siteId': a.siteId ?? null,
          'city': a.city ?? null,
          'coverImage': a.coverImage,
          'description': a.description,
          'material': a.material ?? null,
          'size': a.size ?? null,
          'location': a.location ?? null,
          'level': a.level ?? null,
          'viewCount': 0,
          'isFeatured': a.isFeatured ?? 0,
          'isNationalTreasure': AssetRepository.nationalTreasureFlag(a),
          'createdAt': a.createdAt,
          'updatedAt': a.updatedAt,
        });
      }
      for (const p of data.poetries) {
        await LocalRdbHelper.insert('poetry', {
          'id': p.id,
          'title': p.title,
          'author': p.author ?? null,
          'dynasty': p.dynasty ?? null,
          'content': p.content,
          'translation': p.translation ?? null,
          'relatedSiteId': p.relatedSiteId ?? null,
          'relatedCity': p.relatedCity ?? null,
          'createdAt': DateUtil.now(),
        });
      }
    });
  }
}
