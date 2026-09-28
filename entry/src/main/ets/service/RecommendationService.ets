/**
 * 智能推荐服务
 * 基于用户收藏/浏览行为，按"同期文化→同区域脉络→同类型"的权重混合推荐
 * 完全本地计算，不依赖云端
 */
import { Logger } from '../common/utils/Logger';
import { CultureService } from './CultureService';
import { UserDataService } from './UserDataService';
import { Site, Artifact } from '../model/entity/Entities';
import { EraType, FavoriteTargetType, NoteTargetType } from '../common/constants/Enums';
import { EraMeta } from '../common/constants/AppMeta';

const TAG = 'RecommendationService';

export interface RecommendItem {
  type: 'site' | 'artifact';
  item: Site | Artifact;
  score: number;
  reason: string; // 推荐理由
  reasonTag: 'era' | 'region' | 'type' | 'hot' | 'related';
}

type RecommendReasonTag = 'era' | 'region' | 'type' | 'hot' | 'related';

export class RecommendationService {
  private static instance: RecommendationService;
  private cache: RecommendItem[] = [];
  private cacheVersion: number = 0;

  static getInstance(): RecommendationService {
    if (!RecommendationService.instance) {
      RecommendationService.instance = new RecommendationService();
    }
    return RecommendationService.instance;
  }

  /**
   * 获取综合推荐列表（首页/推荐卡片使用）
   * @param limit 返回数量
   */
  async getRecommendations(limit: number = 10): Promise<RecommendItem[]> {
    try {
      const culture = CultureService.getInstance();
      const user = UserDataService.getInstance();
      await culture.warmCache();

      const allSites = culture.listSitesSync();
      const allArtifacts = culture.listArtifactsSync();

      // 用户画像：从收藏和实际浏览历史提取偏好
      const favSites = (await user.listFavorites(FavoriteTargetType.SITE)).map(f => f.targetId);
      const favArtifacts = (await user.listFavorites(FavoriteTargetType.ARTIFACT)).map(f => f.targetId);
      const history = await user.listHistory(50);

      // 偏好维度统计
      const eraCount = new Map<string, number>();
      const cityCount = new Map<string, number>();
      const typeCount = new Map<string, number>();

      const addPref = (era: string, city?: string, type?: string, weight: number = 1): void => {
        if (era) eraCount.set(era, (eraCount.get(era) || 0) + weight);
        if (city) cityCount.set(city, (cityCount.get(city) || 0) + weight);
        if (type) typeCount.set(type, (typeCount.get(type) || 0) + weight);
      };

      for (const sid of favSites) {
        const s = culture.getSiteByIdSync(sid);
        if (s) addPref(s.era, s.city, s.type, 3);
      }
      for (const aid of favArtifacts) {
        const a = culture.getArtifactByIdSync(aid);
        if (a) addPref(a.era, a.city, a.type, 2);
      }
      for (const h of history) {
        if (h.targetType === 'site') {
          const s = culture.getSiteByIdSync(h.targetId);
          if (s) addPref(s.era, s.city, s.type, 1);
        } else {
          const a = culture.getArtifactByIdSync(h.targetId);
          if (a) addPref(a.era, a.city, a.type, 0.7);
        }
      }

      // 计算top偏好
      const topEra = this.topKey(eraCount);
      const topCity = this.topKey(cityCount);
      const topType = this.topKey(typeCount);

      const scored: Map<string, RecommendItem> = new Map();

      // 新用户（无偏好）：返回精选+每日
      const isNewUser = favSites.length + favArtifacts.length + history.length < 3;

      // 评分所有候选
      for (const s of allSites) {
        if (favSites.includes(s.id)) continue;
        let score = 0;
        let reasonTag: RecommendReasonTag = 'hot';
        let reason = '精选遗址';

        if (isNewUser) {
          score = (s.viewCount || 0) * 0.01 + 5;
          reason = '黄河文明必访';
          reasonTag = 'hot';
        } else {
          if (topEra && s.era === topEra) {
            score += 15;
            reason = `${EraMeta.getByCode(s.era)?.label || ''}文化脉络`;
            reasonTag = 'era';
          }
          if (topCity && s.city === topCity) {
            score += 8;
            if (score < 15) { reason = '同区域文化遗址'; reasonTag = 'region'; }
            else reason += '·同区域';
          }
          if (topType && s.type === topType) {
            score += 5;
            if (score < 8) { reason = '同类型遗址'; reasonTag = 'type'; }
          }
          score += (s.viewCount || 0) * 0.005;
        }
        // 年代衰减：越早的文化稍加分（作为源头推荐）
        score += this.eraBaseScore(s.era) * 0.3;
        scored.set(`site:${s.id}`, { type: 'site', item: s, score, reason, reasonTag });
      }

      for (const a of allArtifacts) {
        if (favArtifacts.includes(a.id)) continue;
        let score = 0;
        let reason = '精品文物';
        let reasonTag: RecommendReasonTag = 'hot';

        if (isNewUser) {
          score = (a.viewCount || 0) * 0.01 + (a.isNationalTreasure ? 25 : 0) + 5;
          if (a.isNationalTreasure) reason = '馆藏国宝';
        } else {
          if (topEra && a.era === topEra) {
            score += 18;
            reason = `${EraMeta.getByCode(a.era)?.label || ''}文物`;
            reasonTag = 'era';
          }
          if (topCity && a.city === topCity) {
            score += 8;
            if (score < 10) { reason = '同区域馆藏'; reasonTag = 'region'; }
            else reason += '·同区域';
          }
          if (topType && a.type === topType) {
            score += 4;
          }
          score += (a.viewCount || 0) * 0.005;
          if (a.isNationalTreasure) score += 10;
        }
        scored.set(`artifact:${a.id}`, { type: 'artifact', item: a, score, reason, reasonTag });
      }

      // 排序+去重+截取
      const items = Array.from(scored.values())
        .sort((a, b) => b.score - a.score);

      // 按reasonTag多样性：每个tag最多4条
      const result: RecommendItem[] = [];
      const tagCount = new Map<string, number>();
      for (const it of items) {
        const cnt = tagCount.get(it.reasonTag) || 0;
        if (cnt < 4) {
          result.push(it);
          tagCount.set(it.reasonTag, cnt + 1);
        }
        if (result.length >= limit) break;
      }

      this.cache = result;
      this.cacheVersion++;
      Logger.info(TAG, `recommend ${result.length} items, topEra=${topEra}, topCity=${topCity}, newUser=${isNewUser}`);
      return result;
    } catch (e) {
      Logger.error(TAG, `getRecommendations failed: ${e}`);
      return [];
    }
  }

  /**
   * 与某遗址相关的推荐（详情页"文脉相连"使用）
   */
  async getRelatedSites(site: Site, limit: number = 6): Promise<RecommendItem[]> {
    const culture = CultureService.getInstance();
    await culture.warmCache();
    const all = culture.listSitesSync();
    const user = UserDataService.getInstance();
    const favSet = new Set((await user.listFavorites(FavoriteTargetType.SITE)).map(f => f.targetId));

    const scored: RecommendItem[] = [];
    for (const s of all) {
      if (s.id === site.id || favSet.has(s.id)) continue;
      let score = 0;
      let reason = '相关遗址';
      let tag: RecommendReasonTag = 'related';
      if (s.era === site.era) { score += 20; reason = `同期·${EraMeta.getByCode(s.era)?.label || ''}`; tag = 'era'; }
      if (s.city === site.city) { score += 12; reason = score > 15 ? '同城·同代' : '同城脉络'; tag = score > 15 ? 'era' : 'region'; }
      if (s.type === site.type && s.era !== site.era) { score += 6; if (score < 10) reason = '同类型'; }
      // 时序邻近：同一区域相邻时代的遗址更相关（如洛阳的夏→商→汉唐传承）
      const eras = Object.values(EraType);
      const iFrom = eras.indexOf(site.era as EraType);
      const iTo = eras.indexOf(s.era as EraType);
      if (iFrom >= 0 && iTo >= 0 && s.city !== site.city) {
        const dist = Math.abs(iFrom - iTo);
        if (dist === 1) score += 5; // 紧接的下一朝代
      }
      if (score > 0) {
        scored.push({ type: 'site', item: s, score, reason, reasonTag: tag });
      }
    }
    scored.sort((a, b) => b.score - a.score);
    return scored.slice(0, limit);
  }

  /**
   * 与某文物同期的文物推荐（详情页"同期文明"使用）
   */
  async getRelatedArtifacts(artifact: Artifact, limit: number = 6): Promise<RecommendItem[]> {
    const culture = CultureService.getInstance();
    await culture.warmCache();
    const all = culture.listArtifactsSync();
    const user = UserDataService.getInstance();
    const favSet = new Set((await user.listFavorites(FavoriteTargetType.ARTIFACT)).map(f => f.targetId));

    const scored: RecommendItem[] = [];
    for (const a of all) {
      if (a.id === artifact.id || favSet.has(a.id)) continue;
      let score = 0;
      let reason = '相关文物';
      let tag: RecommendReasonTag = 'related';
      if (a.era === artifact.era) { score += 18; reason = `同期·${EraMeta.getByCode(a.era)?.label || ''}`; tag = 'era'; }
      if (a.city === artifact.city && a.era !== artifact.era) { score += 8; reason = '同区域'; tag = 'region'; }
      if (a.type === artifact.type) { score += 6; if (score < 8) reason = '同类器物'; }
      if (a.isNationalTreasure) score += 5;
      if (score > 0) {
        scored.push({ type: 'artifact', item: a, score, reason, reasonTag: tag });
      }
    }
    scored.sort((a, b) => b.score - a.score);
    return scored.slice(0, limit);
  }

  private topKey(map: Map<string, number>): string {
    let best = '';
    let bestV = 0;
    for (const entry of map.entries()) {
      const k = entry[0];
      const v = entry[1];
      if (v > bestV) { bestV = v; best = k; }
    }
    return best;
  }

  private eraBaseScore(era: string): number {
    // 越早越加分，但不要让单一era垄断
    const order: Record<string, number> = {};
    order[EraType.YANG_SHAO] = 6;
    order[EraType.LONG_SHAN] = 5;
    order[EraType.XIA_SHANG] = 5;
    order[EraType.ZHOU] = 4;
    order[EraType.HAN_TANG] = 3;
    order[EraType.SONG] = 2;
    return order[era] || 1;
  }

  getCacheVersion(): number { return this.cacheVersion; }
  getCached(): RecommendItem[] { return this.cache; }
}
