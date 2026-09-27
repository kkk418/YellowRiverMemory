import { EraType, SiteType, CityType, ArtifactType, FavoriteTargetType, NoteTargetType, SyncStatus } from '../../common/constants/Enums';

/**
 * 文化遗址实体（本地RDB存储）
 */
export interface Site {
  id: string;                 // 主键，如 'site_yangshao_cun'
  name: string;               // 名称（中文），如 "仰韶村遗址"
  nameEn?: string;            // 英文/拼音，用于副标题
  era: EraType;               // 所属主要年代
  type: SiteType;             // 遗址类型
  city: CityType;             // 所在城市
  yearStart?: number;         // 起始年份（公元前用负数）
  yearEnd?: number;           // 结束年份
  latitude?: number;          // 纬度
  longitude?: number;         // 经度
  coverImage: string;         // 封面图资源路径（rawfile相对路径）
  summary: string;            // 概述（200字内）
  overview: string;           // 详细介绍（Markdown富文）
  archaeology?: string;       // 考古发现
  historicalEvents?: string;  // 相关历史事件（Markdown）
  travelInfo?: string;        // 文旅信息（开放时间、门票等）
  highlight?: string;         // 亮点标签，用于首页推荐
  artifactCount: number;      // 关联文物数量
  viewCount: number;          // 本地浏览次数
  isFeatured: number;         // 是否为精选（0/1）
  createdAt: number;          // 预置数据时间戳
  updatedAt: number;
}

/**
 * 文物实体（本地RDB存储）
 */
export interface Artifact {
  id: string;                 // 主键，如 'artifact_yangshao_pottery_001'
  name: string;               // 文物名称
  nameEn?: string;
  era: EraType;
  type: ArtifactType;
  siteId?: string;            // 关联遗址ID（可选，部分文物无明确出土地）
  city?: CityType;
  coverImage: string;
  description: string;
  material?: string;          // 材质
  size?: string;              // 尺寸
  location?: string;          // 现藏地点
  level?: string;             // 文物级别（如"国家一级文物"）
  viewCount: number;
  isFeatured: number;
  isNationalTreasure?: number; // 国宝级/禁止出境文物标记 0/1
  createdAt: number;
  updatedAt: number;
}

/**
 * 诗词/文献
 */
export interface Poetry {
  id: string;
  title: string;
  author?: string;
  dynasty?: string;
  content: string;            // 诗词正文
  translation?: string;       // 白话译文
  relatedSiteId?: string;
  relatedCity?: CityType;
  createdAt?: number;
}

/**
 * 收藏记录（DDBS同步核心实体）
 */
export interface Favorite {
  id: string;                 // 本地+分布式唯一ID（UUID）
  targetType: FavoriteTargetType;
  targetId: string;           // 关联siteId/artifactId/topicId
  tags: string;               // 标签列表JSON数组，如 '["待实地探访","研究资料"]'
  remark?: string;            // 收藏备注
  createdAt: number;          // 创建时间戳
  updatedAt: number;
  isDeleted: number;          // 软删除标记 0/1
  deviceId: string;           // 产生该记录的设备ID
}

/**
 * 笔记（DDBS同步核心实体）
 */
export interface Note {
  id: string;
  title: string;
  content: string;            // Markdown/纯文本内容
  targetType: NoteTargetType;
  targetId?: string;          // 关联对象ID；自由笔记为null
  tags: string;               // JSON数组
  images?: string;            // 本地图片路径JSON数组
  createdAt: number;
  updatedAt: number;
  isDeleted: number;
  deviceId: string;
}

/**
 * 用户自定义主题/知识库节点
 */
export interface Topic {
  id: string;
  name: string;               // 主题名，如 "仰韶彩陶"
  description?: string;
  coverColor?: string;        // 主题色
  iconEmoji?: string;
  createdAt: number;
  updatedAt: number;
  isDeleted: number;
  deviceId: string;
}

/**
 * 主题-条目关联（知识图谱边）
 */
export interface TopicRelation {
  id: string;
  topicId: string;
  targetType: FavoriteTargetType;
  targetId: string;
  note?: string;              // 用户对该关联的注解
  orderIndex: number;         // 排序
  createdAt: number;
  updatedAt: number;
  isDeleted: number;
  deviceId: string;
}

/**
 * 浏览历史
 */
export interface BrowseHistory {
  id: string;
  targetType: FavoriteTargetType;
  targetId: string;
  viewedAt: number;           // 浏览时间
  duration?: number;          // 停留时长（秒）
}

/**
 * 历史记录（累计浏览次数）
 */
export interface HistoryRecord {
  id: string;
  targetType: FavoriteTargetType;
  targetId: string;
  lastViewedAt: number;
  viewCount: number;
  createdAt: number;
  updatedAt: number;
  deviceId?: string;
}

/**
 * 同步冲突记录
 */
export interface SyncConflict {
  id: string;
  entityType: string;         // favorite | note | topic | topic_relation
  entityId: string;
  localData: string;          // JSON
  remoteData: string;         // JSON
  localDeviceId: string;      // UI版本A来源标识
  remoteDeviceId: string;     // UI版本B来源标识
  localTimestamp: number;     // UI版本A更新时间
  remoteTimestamp: number;    // UI版本B更新时间
  resolvedAt?: number;
  resolution?: string;        // version_a | version_b | merge
  createdAt: number;
}

/**
 * 同步状态面板数据（ViewModel层使用）
 */
export interface SyncPanelState {
  status: SyncStatus;
  lastSyncTime: number;
  localDeviceName: string;
  remoteDevices: RemoteDevice[];
  pendingCount: number;       // 待同步条目
  conflictCount: number;
  progressPercent: number;    // 0-100
}

/**
 * 远端设备信息
 */
export interface RemoteDevice {
  deviceId: string;
  deviceName: string;
  deviceType: string;         // 'phone' | 'tablet' | '2in1'
  isOnline: boolean;
  lastSeenTime: number;
}
