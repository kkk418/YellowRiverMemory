/**
 * 预置资源仓库：负责从 rawfile 读取 JSON 数据，并在首次启动时导入 RDB
 */
import { resourceManager } from '@kit.LocalizationKit';
import { relationalStore } from '@kit.ArkData';
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

interface IdRow { id: string; }

export class AssetRepository {
  private static initialized = false;

  /**
   * 启动时调用：读取rawfile/data/preset.json并写入RDB
   * 仅在首次启动（或预置数据版本升级）时执行
   */
  static async initIfNeeded(resMgr: resourceManager.ResourceManager): Promise<void> {
    if (AssetRepository.initialized) return;
    const currentVersion = AppConstants.PRESET_VERSION;
    try {
      const savedVersion = await PreferencesHelper.getDataVersion();
      const text = await AssetRepository.readRawText(resMgr, 'data/preset.json');
      const data: PresetData = JSON.parse(text) as PresetData;
      // Import by ID on every process start so an interrupted or partial install
      // is repaired even when the preference version was already advanced.
      // Refresh bundled content only after a preset upgrade; user data lives in separate tables.
      await AssetRepository.importToRdb(data, savedVersion < currentVersion);
      if (savedVersion < currentVersion) await PreferencesHelper.setDataVersion(currentVersion);
      AssetRepository.initialized = true;
      Logger.info(TAG, `Preset data checked: sites=${data.sites.length}, artifacts=${data.artifacts.length}, poetries=${data.poetries.length}`);
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

  private static async updateContent(table: 'site' | 'artifact' | 'poetry', id: string,
    values: relationalStore.ValuesBucket): Promise<void> {
    const predicates = new relationalStore.RdbPredicates(table);
    predicates.equalTo('id', id);
    await LocalRdbHelper.update(table, values, predicates);
  }

  private static async importToRdb(data: PresetData, refreshExisting: boolean): Promise<void> {
    await LocalRdbHelper.runInTransaction(async () => {
      const siteIds = new Set((await LocalRdbHelper.query<IdRow>('SELECT id FROM site')).map(row => row.id));
      const artifactIds = new Set((await LocalRdbHelper.query<IdRow>('SELECT id FROM artifact')).map(row => row.id));
      const poetryIds = new Set((await LocalRdbHelper.query<IdRow>('SELECT id FROM poetry')).map(row => row.id));
      for (const site of data.sites) {
        const now = DateUtil.now();
        const content: relationalStore.ValuesBucket = {
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
          'isFeatured': site.isFeatured ?? 0,
          'updatedAt': site.updatedAt ?? now,
        };
        if (siteIds.has(site.id)) {
          if (refreshExisting) await AssetRepository.updateContent('site', site.id, content);
          continue;
        }
        content.id = site.id;
        content.viewCount = 0;
        content.createdAt = site.createdAt ?? now;
        await LocalRdbHelper.insert('site', content);
      }
      for (const a of data.artifacts) {
        const now = DateUtil.now();
        const content: relationalStore.ValuesBucket = {
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
          'isFeatured': a.isFeatured ?? 0,
          'isNationalTreasure': AssetRepository.nationalTreasureFlag(a),
          'updatedAt': a.updatedAt ?? now,
        };
        if (artifactIds.has(a.id)) {
          if (refreshExisting) await AssetRepository.updateContent('artifact', a.id, content);
          continue;
        }
        content.id = a.id;
        content.viewCount = 0;
        content.createdAt = a.createdAt ?? now;
        await LocalRdbHelper.insert('artifact', content);
      }
      for (const p of data.poetries) {
        const content: relationalStore.ValuesBucket = {
          'title': p.title,
          'author': p.author ?? null,
          'dynasty': p.dynasty ?? null,
          'content': p.content,
          'translation': p.translation ?? null,
          'relatedSiteId': p.relatedSiteId ?? null,
          'relatedCity': p.relatedCity ?? null,
        };
        if (poetryIds.has(p.id)) {
          if (refreshExisting) await AssetRepository.updateContent('poetry', p.id, content);
          await LocalRdbHelper.execute(
            'UPDATE poetry SET createdAt=? WHERE id=? AND (createdAt IS NULL OR createdAt=0)',
            [p.createdAt ?? DateUtil.now(), p.id]);
          continue;
        }
        content.id = p.id;
        content.createdAt = p.createdAt ?? DateUtil.now();
        await LocalRdbHelper.insert('poetry', content);
      }
    });
  }
}
