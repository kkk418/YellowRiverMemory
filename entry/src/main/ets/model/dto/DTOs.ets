import { Site, Artifact, Note, Favorite, Topic, SyncPanelState } from '../entity/Entities';
import { EraType, SiteType, CityType, ArtifactType } from '../../common/constants/Enums';

/**
 * 筛选条件
 */
export interface FilterCriteria {
  keyword?: string;
  era?: EraType[];
  siteType?: SiteType[];
  artifactType?: ArtifactType[];
  city?: CityType[];
  isFeaturedOnly?: boolean;
}

/**
 * 分页请求
 */
export interface PageRequest {
  page: number;       // 从1开始
  pageSize: number;
}

/**
 * 分页结果
 */
export interface PageResult<T> {
  list: T[];
  total: number;
  page: number;
  pageSize: number;
  hasMore: boolean;
}

/**
 * 首页聚合数据
 */
export interface HomeAggregate {
  featuredSites: Site[];
  featuredArtifacts: Artifact[];
  recentSites: Site[];          // 近期浏览
  recommendedSites: Site[];     // 智能推荐
  eraStats: EraStat[];          // 各年代数量
}

export interface EraStat {
  era: EraType;
  siteCount: number;
  artifactCount: number;
}

/**
 * 遗址详情VO（聚合多表数据）
 */
export interface SiteDetailVO {
  site: Site;
  artifacts: Artifact[];
  poetries: PoetryVO[];
  isFavorited: boolean;
  favoriteId?: string;
  noteCount: number;
  relatedSites: Site[];         // 关联推荐
}

export interface PoetryVO {
  id: string;
  title: string;
  author?: string;
  dynasty?: string;
  content: string;
}

/**
 * 收藏夹分组视图
 */
export interface CollectionGroup {
  tag: string;                  // 标签名
  count: number;
  sites: Site[];
  artifacts: Artifact[];
  topics: Topic[];
}

/**
 * 笔记列表项（含关联对象名称）
 */
export interface NoteListItem {
  note: Note;
  targetName?: string;
  targetCover?: string;
}

/**
 * 主题详情VO（知识图谱）
 */
export interface TopicDetailVO {
  topic: Topic;
  nodes: KnowledgeNode[];
  edges: KnowledgeEdge[];
}

export interface KnowledgeNode {
  id: string;
  label: string;
  type: 'topic' | 'site' | 'artifact';
  cover?: string;
  x?: number;
  y?: number;
}

export interface KnowledgeEdge {
  source: string;
  target: string;
  label?: string;
}

/**
 * 通用结果包装
 */
export class Result<T> {
  success: boolean = false;
  data?: T;
  message?: string;
  code?: number;

  static ok<T>(data: T): Result<T> {
    const result = new Result<T>();
    result.success = true;
    result.data = data;
    return result;
  }

  static fail<T>(message: string, code?: number): Result<T> {
    const result = new Result<T>();
    result.message = message;
    result.code = code;
    return result;
  }
}
