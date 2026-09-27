/**
 * 遗址/文物所属历史时期
 */
export enum EraType {
  YANG_SHAO = 'yangshao',   // 仰韶（约公元前5000-3000年）
  LONG_SHAN = 'longshan',   // 龙山（约公元前2500-2000年）
  XIA_SHANG = 'xiashang',   // 夏商（约公元前2070-1046年）
  ZHOU = 'zhou',            // 周（公元前1046-256年）
  HAN_TANG = 'hantang',     // 汉唐（公元前202-907年）
  SONG = 'song',            // 宋金（960-1279年）
}

/**
 * 遗址类型
 */
export enum SiteType {
  CAPITAL = 'capital',          // 都城遗址
  TOMB = 'tomb',                // 墓葬群
  KILN = 'kiln',                // 窑址
  TEMPLE = 'temple',            // 宗教/祠庙
  ANCIENT_BUILDING = 'ancient_building', // 古建筑
  SETTLEMENT = 'settlement',    // 聚落遗址
  OTHER = 'other',              // 其他
}

/**
 * 文物类型
 */
export enum ArtifactType {
  JADE = 'jade',                // 玉器
  BRONZE = 'bronze',            // 青铜器
  POTTERY = 'pottery',          // 陶器
  PORCELAIN = 'porcelain',      // 瓷器
  PAINTING = 'painting',        // 绘画/壁画
  CALLIGRAPHY = 'calligraphy',  // 书法/碑刻
  STONE = 'stone',              // 石刻/造像
  BONE = 'bone',                // 骨器/甲骨文
  OTHER = 'other',
}

/**
 * 沿线城市
 */
export enum CityType {
  SANMENXIA = 'sanmenxia',  // 三门峡
  LUOYANG = 'luoyang',      // 洛阳
  ZHENGZHOU = 'zhengzhou',  // 郑州
  KAIFENG = 'kaifeng',      // 开封
  PUYANG = 'puyang',        // 濮阳
  JIAOZUO = 'jiaozuo',      // 焦作（扩展）
  ANYANG = 'anyang',        // 安阳（殷墟）
  XINXIANG = 'xinxiang',    // 新乡
}

/**
 * 收藏类型
 */
export enum FavoriteTargetType {
  SITE = 'site',
  ARTIFACT = 'artifact',
  TOPIC = 'topic',
}

/**
 * 同步状态
 */
export enum SyncStatus {
  IDLE = 'idle',          // 已同步
  SYNCING = 'syncing',    // 同步中
  CONFLICT = 'conflict',  // 冲突
  OFFLINE = 'offline',    // 离线待同步
  ERROR = 'error',        // 同步失败
}

/**
 * 笔记关联对象类型
 */
export enum NoteTargetType {
  SITE = 'site',
  ARTIFACT = 'artifact',
  TOPIC = 'topic',
  STANDALONE = 'standalone', // 自由笔记
}

/**
 * 主题色（墨壁模式 / 宣纸模式）
 */
export enum ThemeMode {
  INK = 'ink',          // 墨壁（深色默认）
  RICE_PAPER = 'rice_paper', // 宣纸（浅色）
}
