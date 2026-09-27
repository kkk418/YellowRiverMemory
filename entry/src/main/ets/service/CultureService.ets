/**
 * 文化资源服务：封装site/artifact/poetry表的查询逻辑
 */
import { LocalRdbHelper } from '../database/LocalRdbHelper';
import { Site, Artifact, Poetry } from '../model/entity/Entities';
import { Logger } from '../common/utils/Logger';
import { EraType, CityType } from '../common/constants/Enums';
import { FilterCriteria, PageResult } from '../model/dto/DTOs';
import { EraMeta, CityMeta } from '../common/constants/AppMeta';

const TAG = 'CultureService';

interface CountRow {
  c: number;
}

interface ScoredSite {
  site: Site;
  score: number;
}

export interface CityStat {
  city: CityType;
  name: string;
  count: number;
}

export interface EraStat {
  era: EraType;
  name: string;
  color: ResourceColor;
  siteCount: number;
  artifactCount: number;
}

export interface CultureSearchResult {
  sites: Site[];
  artifacts: Artifact[];
  poetries: Poetry[];
}

export interface DiscoveryItem {
  title: string;
  desc: string;
}

export interface HistoricalEventItem {
  year: string;
  event: string;
}

export class CultureService {
  private static instance: CultureService;
  private siteMap: Map<string, Site> = new Map();
  private artifactMap: Map<string, Artifact> = new Map();
  private cacheWarmed: boolean = false;

  static getInstance(): CultureService {
    if (!CultureService.instance) CultureService.instance = new CultureService();
    return CultureService.instance;
  }

  /** 启动时预热内存缓存 */
  async warmCache(): Promise<void> {
    try {
      const sites = await LocalRdbHelper.query<Site>(`SELECT * FROM site`, []);
      const artifacts = await LocalRdbHelper.query<Artifact>(`SELECT * FROM artifact`, []);
      this.siteMap.clear();
      this.artifactMap.clear();
      for (const s of sites) this.siteMap.set(s.id, s);
      for (const a of artifacts) this.artifactMap.set(a.id, a);
      this.cacheWarmed = true;
      Logger.info(TAG, `Culture cache warmed: sites=${sites.length}, artifacts=${artifacts.length}`);
    } catch (e) {
      Logger.error(TAG, `warmCache failed: ${e}`);
    }
  }

  /** 同步按ID获取（需先warmCache） */
  getSiteByIdSync(id: string): Site | null {
    return this.siteMap.get(id) ?? null;
  }

  /** 同步按ID获取文物 */
  getArtifactByIdSync(id: string): Artifact | null {
    return this.artifactMap.get(id) ?? null;
  }

  /** 列出所有遗址（同步，从缓存） */
  listSitesSync(): Site[] {
    return Array.from(this.siteMap.values());
  }

  /** 列出所有文物（同步，从缓存） */
  listArtifactsSync(): Artifact[] {
    return Array.from(this.artifactMap.values());
  }

  // ========== 精选 / 首页 ==========

  /** 获取精选遗址 */
  async getFeaturedSites(limit: number = 6): Promise<Site[]> {
    const sql = `SELECT * FROM site ORDER BY isFeatured DESC, viewCount DESC, createdAt LIMIT ?`;
    return LocalRdbHelper.query<Site>(sql, [limit]);
  }

  /** 获取精选文物 */
  async getFeaturedArtifacts(limit: number = 10): Promise<Artifact[]> {
    const sql = `SELECT * FROM artifact ORDER BY isFeatured DESC, isNationalTreasure DESC, createdAt LIMIT ?`;
    return LocalRdbHelper.query<Artifact>(sql, [limit]);
  }

  /** 获取每日一景（基于日期哈希选一个） */
  async getDailySite(): Promise<Site | null> {
    const sites = await LocalRdbHelper.query<Site>(`SELECT * FROM site ORDER BY createdAt`);
    if (sites.length === 0) return null;
    const today = new Date();
    const seed = today.getFullYear() * 10000 + (today.getMonth() + 1) * 100 + today.getDate();
    return sites[seed % sites.length];
  }

  /** 获取全部城市+对应遗址数量 */
  async getCityStats(): Promise<CityStat[]> {
    const result: CityStat[] = [];
    for (const c of CityMeta.ALL) {
      const rows = await LocalRdbHelper.query<CountRow>(
        `SELECT COUNT(*) as c FROM site WHERE city=?`, [c.code]);
      result.push({ city: c.code as CityType, name: c.name, count: rows[0]?.c ?? 0 });
    }
    return result;
  }

  /** 按城市取遗址 */
  async getSitesByCity(city: CityType): Promise<Site[]> {
    return LocalRdbHelper.query<Site>(
      `SELECT * FROM site WHERE city=? ORDER BY isFeatured DESC, createdAt`, [city]);
  }

  // ========== 详情 ==========

  /** 根据ID获取遗址 */
  async getSiteById(id: string): Promise<Site | null> {
    if (this.cacheWarmed) return this.getSiteByIdSync(id);
    const sql = `SELECT * FROM site WHERE id=? LIMIT 1`;
    const list = await LocalRdbHelper.query<Site>(sql, [id]);
    return list.length > 0 ? list[0] : null;
  }

  /** 根据ID获取文物 */
  async getArtifactById(id: string): Promise<Artifact | null> {
    if (this.cacheWarmed) return this.getArtifactByIdSync(id);
    const sql = `SELECT * FROM artifact WHERE id=? LIMIT 1`;
    const list = await LocalRdbHelper.query<Artifact>(sql, [id]);
    return list.length > 0 ? list[0] : null;
  }

  /** 获取某遗址下文物 */
  async getArtifactsBySite(siteId: string): Promise<Artifact[]> {
    const sql = `SELECT * FROM artifact WHERE siteId=? ORDER BY isNationalTreasure DESC, isFeatured DESC, createdAt`;
    return LocalRdbHelper.query<Artifact>(sql, [siteId]);
  }

  /** 获取遗址相关诗词 */
  async getPoetriesBySite(siteId: string): Promise<Poetry[]> {
    return LocalRdbHelper.query<Poetry>(`SELECT * FROM poetry WHERE relatedSiteId=?`, [siteId]);
  }

  /** 获取城市相关诗词 */
  async getPoetriesByCity(city: CityType): Promise<Poetry[]> {
    return LocalRdbHelper.query<Poetry>(`SELECT * FROM poetry WHERE relatedCity=?`, [city]);
  }

  // ========== 关联推荐 ==========

  /** 获取关联遗址（同年代/同城市/同类型，加权排序） */
  async getRelatedSites(siteId: string, limit: number = 4): Promise<Site[]> {
    const site = await this.getSiteById(siteId);
    if (!site) return [];
    const candidates = await LocalRdbHelper.query<Site>(
      `SELECT * FROM site WHERE id!=? AND (era=? OR city=? OR type=?)`,
      [siteId, site.era, site.city, site.type]
    );
    // 加权评分：同年代+同城市=3，同年代+同类型=2，同年代=2，同城市=2，同类型=1
    const scored: ScoredSite[] = candidates.map((s: Site): ScoredSite => {
      let score = 0;
      if (s.era === site.era) score += 2;
      if (s.city === site.city) score += 2;
      if (s.type === site.type) score += 1;
      if (s.isFeatured) score += 0.5;
      return { site: s, score };
    });
    scored.sort((a, b) => b.score - a.score);
    return scored.slice(0, limit).map(x => x.site);
  }

  /**
   * 基于浏览/收藏行为的智能推荐
   * 权重：年代0.30 + 城市0.20 + 类型0.15 + 文物材质0.10 + 浏览热度0.15 + 精选0.10
   */
  async getRecommendations(favoriteIds: string[], historyIds: string[], limit: number = 10): Promise<Site[]> {
    if (favoriteIds.length === 0 && historyIds.length === 0) {
      // 无数据时返回精选
      return this.getFeaturedSites(limit);
    }
    // 收集偏好
    const eraWeight = new Map<string, number>();
    const cityWeight = new Map<string, number>();
    const typeWeight = new Map<string, number>();
    const allIds = new Set([...favoriteIds, ...historyIds]);
    for (const id of allIds) {
      const s = await this.getSiteById(id);
      if (!s) continue;
      const w = favoriteIds.includes(id) ? 2 : 1;
      eraWeight.set(s.era, (eraWeight.get(s.era) ?? 0) + w);
      cityWeight.set(s.city, (cityWeight.get(s.city) ?? 0) + w);
      typeWeight.set(s.type, (typeWeight.get(s.type) ?? 0) + w);
    }
    const allSites = await LocalRdbHelper.query<Site>(`SELECT * FROM site`);
    const scored: ScoredSite[] = allSites
      .filter(s => !allIds.has(s.id))
      .map((s: Site): ScoredSite => {
        let score = 0;
        score += (eraWeight.get(s.era) ?? 0) * 0.3;
        score += (cityWeight.get(s.city) ?? 0) * 0.2;
        score += (typeWeight.get(s.type) ?? 0) * 0.15;
        score += Math.min(s.viewCount / 10, 3) * 0.15;
        if (s.isFeatured) score += 0.1;
        return { site: s, score };
      });
    scored.sort((a, b) => b.score - a.score);
    return scored.slice(0, limit).map(x => x.site);
  }

  // ========== 筛选 / 搜索 ==========

  /** 多维筛选+分页查询遗址 */
  async querySites(criteria: FilterCriteria, page: number = 1, pageSize: number = 20): Promise<PageResult<Site>> {
    const conditions: string[] = [];
    const args: (string | number)[] = [];
    if (criteria.keyword && criteria.keyword.length > 0) {
      // 对中文做bigram拆分（每2个字组合），提升模糊搜索命中率
      const kw = criteria.keyword.trim();
      const tokens: string[] = [];
      tokens.push(`%${kw}%`);
      for (let i = 0; i < kw.length - 1; i++) {
        const bi = kw.substring(i, i + 2);
        if (bi.length === 2) tokens.push(`%${bi}%`);
      }
      const ors: string[] = [];
      // 名称
      tokens.forEach(t => ors.push('name LIKE ?'));
      tokens.forEach(t => ors.push('summary LIKE ?'));
      tokens.forEach(t => ors.push('nameEn LIKE ?'));
      // 去重占位参数
      const allArgs: (string | number)[] = [];
      const cols = ['name', 'summary', 'nameEn'];
      cols.forEach(() => tokens.forEach(t => allArgs.push(t)));
      conditions.push(`(${ors.join(' OR ')})`);
      args.push(...allArgs);
    }
    if (criteria.era && criteria.era.length > 0) {
      conditions.push(`era IN (${criteria.era.map(() => '?').join(',')})`);
      args.push(...criteria.era);
    }
    if (criteria.siteType && criteria.siteType.length > 0) {
      conditions.push(`type IN (${criteria.siteType.map(() => '?').join(',')})`);
      args.push(...criteria.siteType);
    }
    if (criteria.city && criteria.city.length > 0) {
      conditions.push(`city IN (${criteria.city.map(() => '?').join(',')})`);
      args.push(...criteria.city);
    }
    const where = conditions.length > 0 ? `WHERE ${conditions.join(' AND ')}` : '';
    const countSql = `SELECT COUNT(*) as c FROM site ${where}`;
    const cntRows = await LocalRdbHelper.query<CountRow>(countSql, args);
    const total = cntRows[0]?.c ?? 0;

    const offset = (page - 1) * pageSize;
    const dataSql = `SELECT * FROM site ${where} ORDER BY isFeatured DESC, viewCount DESC, createdAt LIMIT ? OFFSET ?`;
    const list = await LocalRdbHelper.query<Site>(dataSql, [...args, pageSize, offset]);
    return { list, total, page, pageSize, hasMore: offset + list.length < total };
  }

  /** 多维筛选文物 */
  async queryArtifacts(criteria: FilterCriteria, page: number = 1, pageSize: number = 20): Promise<PageResult<Artifact>> {
    const conditions: string[] = [];
    const args: (string | number)[] = [];
    if (criteria.keyword && criteria.keyword.length > 0) {
      const kw = criteria.keyword.trim();
      conditions.push(`((name LIKE ? OR description LIKE ? OR material LIKE ? OR location LIKE ?))`);
      args.push(`%${kw}%`, `%${kw}%`, `%${kw}%`, `%${kw}%`);
    }
    if (criteria.era && criteria.era.length > 0) {
      conditions.push(`era IN (${criteria.era.map(() => '?').join(',')})`);
      args.push(...criteria.era);
    }
    if (criteria.city && criteria.city.length > 0) {
      conditions.push(`city IN (${criteria.city.map(() => '?').join(',')})`);
      args.push(...criteria.city);
    }
    const where = conditions.length > 0 ? `WHERE ${conditions.join(' AND ')}` : '';
    const countSql = `SELECT COUNT(*) as c FROM artifact ${where}`;
    const cntRows = await LocalRdbHelper.query<CountRow>(countSql, args);
    const total = cntRows[0]?.c ?? 0;
    const offset = (page - 1) * pageSize;
    const dataSql = `SELECT * FROM artifact ${where} ORDER BY isNationalTreasure DESC, isFeatured DESC LIMIT ? OFFSET ?`;
    const list = await LocalRdbHelper.query<Artifact>(dataSql, [...args, pageSize, offset]);
    return { list, total, page, pageSize, hasMore: offset + list.length < total };
  }

  /** 按年代统计遗址/文物数量 */
  async countByEra(): Promise<EraStat[]> {
    const result: EraStat[] = [];
    for (const era of EraMeta.ALL) {
      const s = await LocalRdbHelper.query<CountRow>(`SELECT COUNT(*) as c FROM site WHERE era=?`, [era.code]);
      const a = await LocalRdbHelper.query<CountRow>(`SELECT COUNT(*) as c FROM artifact WHERE era=?`, [era.code]);
      result.push({
        era: era.code as EraType,
        name: era.name,
        color: era.colorRes,
        siteCount: s[0]?.c ?? 0,
        artifactCount: a[0]?.c ?? 0
      });
    }
    return result;
  }

  /** 获取所有遗址 */
  async getAllSites(): Promise<Site[]> {
    return LocalRdbHelper.query<Site>(`SELECT * FROM site ORDER BY createdAt`);
  }

  /** 获取所有文物 */
  async getAllArtifacts(): Promise<Artifact[]> {
    return LocalRdbHelper.query<Artifact>(`SELECT * FROM artifact ORDER BY createdAt`);
  }

  /** 获取所有诗词 */
  async getAllPoetries(): Promise<Poetry[]> {
    return LocalRdbHelper.query<Poetry>(`SELECT * FROM poetry ORDER BY createdAt`);
  }

  /** 增加浏览次数 */
  async incrementView(target: 'site' | 'artifact', id: string): Promise<void> {
    try {
      await LocalRdbHelper.execute(`UPDATE ${target} SET viewCount = viewCount + 1 WHERE id=?`, [id]);
    } catch (e) {
      Logger.warn(TAG, `incrementView failed: ${e}`);
    }
  }

  /** 综合搜索（遗址+文物） */
  async searchAll(keyword: string, limit: number = 20): Promise<CultureSearchResult> {
    const kw = `%${keyword}%`;
    const sites = await LocalRdbHelper.query<Site>(
      `SELECT * FROM site WHERE name LIKE ? OR summary LIKE ? OR nameEn LIKE ? LIMIT ?`,
      [kw, kw, kw, limit]
    );
    const artifacts = await LocalRdbHelper.query<Artifact>(
      `SELECT * FROM artifact WHERE name LIKE ? OR description LIKE ? OR nameEn LIKE ? OR material LIKE ? LIMIT ?`,
      [kw, kw, kw, kw, limit]
    );
    const poetries = await LocalRdbHelper.query<Poetry>(
      `SELECT * FROM poetry WHERE title LIKE ? OR author LIKE ? OR content LIKE ? LIMIT ?`,
      [kw, kw, kw, limit]
    );
    return { sites, artifacts, poetries };
  }

  /** 将 archaeology 字段（换行分隔）解析为条目数组 */
  parseDiscoveries(site: Site): DiscoveryItem[] {
    if (!site.archaeology) return [];
    const lines = site.archaeology.split(/\n|；|;/).map(s => s.trim()).filter(Boolean);
    return lines.map((line: string): DiscoveryItem => {
      // 形如"1921年首次发掘：发现大量彩陶"
      const idx = line.indexOf('：');
      if (idx > 0) {
        return { title: line.substring(0, idx), desc: line.substring(idx + 1) };
      }
      const idx2 = line.indexOf(':');
      if (idx2 > 0) {
        return { title: line.substring(0, idx2), desc: line.substring(idx2 + 1) };
      }
      return { title: '', desc: line };
    });
  }

  /** 将 historicalEvents 字段（换行分隔）解析为 {year,event} 数组 */
  parseHistoricalEvents(site: Site): HistoricalEventItem[] {
    if (!site.historicalEvents) return [];
    const lines = site.historicalEvents.split(/\n/).map(s => s.trim()).filter(Boolean);
    return lines.map((line: string): HistoricalEventItem => {
      const m = line.match(/^([^：:]+)[：:](.+)$/);
      if (m) return { year: m[1].trim(), event: m[2].trim() };
      return { year: '', event: line };
    });
  }
}
