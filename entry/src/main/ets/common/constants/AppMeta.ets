import { EraType, SiteType, ArtifactType, CityType } from './Enums';

/**
 * 年代元数据
 */
export class EraMeta {
  key: EraType;
  name: string;
  pinyin: string;
  enName: string;
  yearRange: string;
  order: number;
  colorHex: string;
  colorRes: ResourceColor;
  constructor(key: EraType, name: string, pinyin: string, enName: string, yearRange: string,
    order: number, colorHex: string, colorRes: ResourceColor) {
    this.key = key;
    this.name = name;
    this.pinyin = pinyin;
    this.enName = enName;
    this.yearRange = yearRange;
    this.order = order;
    this.colorHex = colorHex;
    this.colorRes = colorRes;
  }
  get code(): string { return this.key as string; }
  get label(): string { return this.name; }

  static ALL: EraMeta[] = [
    new EraMeta(EraType.YANG_SHAO, '仰韶文化', 'Yǎngsháo', 'Yangshao Culture', '约前5000-前3000', 1, '#C46A3F', $r('app.color.era_yangshao')),
    new EraMeta(EraType.LONG_SHAN, '龙山文化', 'Lóngshān', 'Longshan Culture', '约前2500-前2000', 2, '#5A5A5A', $r('app.color.era_longshan')),
    new EraMeta(EraType.XIA_SHANG, '夏商时期', 'Xià Shāng', 'Xia & Shang', '约前2070-前1046', 3, '#C9A96E', $r('app.color.era_xiashang')),
    new EraMeta(EraType.ZHOU, '两周时期', 'Zhōu', 'Zhou Dynasty', '前1046-前256', 4, '#B83B2E', $r('app.color.era_zhou')),
    new EraMeta(EraType.HAN_TANG, '汉唐时期', 'Hàn Táng', 'Han to Tang', '前202-907', 5, '#4E7A6B', $r('app.color.era_hantang')),
    new EraMeta(EraType.SONG, '宋金时期', 'Sòng Jīn', 'Song & Jin', '960-1279', 6, '#6B9FB5', $r('app.color.era_song')),
  ];

  static of(key: EraType): EraMeta | undefined {
    return EraMeta.ALL.find(e => e.key === key);
  }

  static getByCode(code: string): EraMeta | undefined {
    return EraMeta.ALL.find(e => e.key === code);
  }
}

/**
 * 城市元数据
 */
export class CityMeta {
  key: CityType;
  name: string;
  pinyin: string;
  enName: string;
  description: string;
  order: number;
  colorRes: ResourceColor;
  colorHex: string;
  constructor(key: CityType, name: string, pinyin: string, enName: string, description: string,
    order: number, colorHex: string, colorRes: ResourceColor) {
    this.key = key;
    this.name = name;
    this.pinyin = pinyin;
    this.enName = enName;
    this.description = description;
    this.order = order;
    this.colorHex = colorHex;
    this.colorRes = colorRes;
  }
  get code(): string { return this.key as string; }
  get label(): string { return this.name; }
  get nameEn(): string { return this.enName; }

  static ALL: CityMeta[] = [
    new CityMeta(CityType.SANMENXIA, '三门峡', 'Sānménxiá', 'Sanmenxia', '仰韶文化核心发现地，虢国故地', 1, '#C46A3F', $r('app.color.era_yangshao')),
    new CityMeta(CityType.LUOYANG, '洛阳', 'Luòyáng', 'Luoyang', '十三朝古都，二里头、龙门、白马寺', 2, '#C9A96E', $r('app.color.gold_primary')),
    new CityMeta(CityType.ZHENGZHOU, '郑州', 'Zhèngzhōu', 'Zhengzhou', '商代早期都城，大河村遗址', 3, '#B83B2E', $r('app.color.vermillion')),
    new CityMeta(CityType.KAIFENG, '开封', 'Kāifēng', 'Kaifeng', '北宋东京，汴梁文化', 4, '#4E7A6B', $r('app.color.bronze_green')),
    new CityMeta(CityType.PUYANG, '濮阳', 'Púyáng', 'Puyang', '颛顼遗都，中华龙乡', 5, '#5A5A5A', $r('app.color.text_tertiary')),
    new CityMeta(CityType.ANYANG, '安阳', 'Ānyáng', 'Anyang', '殷墟所在地，甲骨文发现地', 6, '#8B7549', $r('app.color.jade_green')),
  ];

  static of(key: CityType): CityMeta | undefined {
    return CityMeta.ALL.find(c => c.key === key);
  }

  static getByCode(code: string): CityMeta | undefined {
    return CityMeta.ALL.find(c => c.key === code);
  }
}

/**
 * 遗址类型元数据
 */
export class SiteTypeMeta {
  key: SiteType;
  name: string;
  constructor(key: SiteType, name: string) {
    this.key = key;
    this.name = name;
  }
  get code(): string { return this.key as string; }
  get label(): string { return this.name; }

  static ALL: SiteTypeMeta[] = [
    new SiteTypeMeta(SiteType.CAPITAL, '都城遗址'),
    new SiteTypeMeta(SiteType.SETTLEMENT, '聚落遗址'),
    new SiteTypeMeta(SiteType.TOMB, '墓葬群'),
    new SiteTypeMeta(SiteType.KILN, '窑址'),
    new SiteTypeMeta(SiteType.TEMPLE, '宗教祠庙'),
    new SiteTypeMeta(SiteType.ANCIENT_BUILDING, '古建筑'),
    new SiteTypeMeta(SiteType.OTHER, '其他'),
  ];

  static of(key: SiteType): SiteTypeMeta | undefined {
    return SiteTypeMeta.ALL.find(s => s.key === key);
  }
  static getByCode(code: string): SiteTypeMeta | undefined {
    return SiteTypeMeta.ALL.find(s => s.key === code);
  }
}

/**
 * 文物类型元数据
 */
export class ArtifactTypeMeta {
  key: ArtifactType;
  name: string;
  constructor(key: ArtifactType, name: string) {
    this.key = key;
    this.name = name;
  }
  get code(): string { return this.key as string; }
  get label(): string { return this.name; }

  static ALL: ArtifactTypeMeta[] = [
    new ArtifactTypeMeta(ArtifactType.POTTERY, '陶器'),
    new ArtifactTypeMeta(ArtifactType.JADE, '玉器'),
    new ArtifactTypeMeta(ArtifactType.BRONZE, '青铜器'),
    new ArtifactTypeMeta(ArtifactType.PORCELAIN, '瓷器'),
    new ArtifactTypeMeta(ArtifactType.PAINTING, '绘画/壁画'),
    new ArtifactTypeMeta(ArtifactType.CALLIGRAPHY, '书法/碑刻'),
    new ArtifactTypeMeta(ArtifactType.STONE, '石刻造像'),
    new ArtifactTypeMeta(ArtifactType.BONE, '甲骨/骨器'),
    new ArtifactTypeMeta(ArtifactType.OTHER, '其他'),
  ];

  static of(key: ArtifactType): ArtifactTypeMeta | undefined {
    return ArtifactTypeMeta.ALL.find(a => a.key === key);
  }
  static getByCode(code: string): ArtifactTypeMeta | undefined {
    return ArtifactTypeMeta.ALL.find(a => a.key === code);
  }
}

/**
 * 标签元数据（用于笔记/收藏标签选择）
 */
export class TagMeta {
  code: string;
  label: string;
  colorRes?: ResourceColor;
  constructor(code: string, label: string, colorRes?: ResourceColor) {
    this.code = code; this.label = label; this.colorRes = colorRes;
  }
  static ALL: TagMeta[] = [
    new TagMeta('to_visit', '待实地探访', $r('app.color.gold_dim')),
    new TagMeta('visited', '已去过', $r('app.color.success_green')),
    new TagMeta('research', '研究资料', $r('app.color.bronze_green')),
    new TagMeta('favorite', '喜爱', $r('app.color.vermillion')),
    new TagMeta('introduced_by_book', '书中所见', $r('app.color.blue_white')),
    new TagMeta('museum', '馆藏所见', $r('app.color.jade_green')),
  ];
  static ERA_TAGS: TagMeta[] = EraMeta.ALL.map(e => new TagMeta(e.key as string, e.name, e.colorRes));
}

/**
 * 系统标签常量
 */
export class SystemTags {
  static TO_VISIT = '待实地探访';
  static VISITED = '已去过';
  static RESEARCH = '研究资料';
  static FAVORITE = '喜爱';
  static ALL_DEFAULT: string[] = [SystemTags.TO_VISIT, SystemTags.VISITED, SystemTags.RESEARCH, SystemTags.FAVORITE];
}

/**
 * 应用级常量
 */
export class AppConstants {
  static DB_NAME: string = 'yellow_river_memory.db';
  static DB_VERSION: number = 4;
  static PRESET_VERSION: number = 5;
  static DISTRIBUTED_GROUP_ID: string = 'com.yellowriver.memory.group';
  // Encryption is part of the store creation options. Use a new ID so an existing
  // unencrypted store is not reopened with incompatible options.
  static KV_STORE_ID: string = 'yellow_river_kv_secure_v2';
  static RDB_STORE_ID: string = 'yellow_river_rdb_store';
  static PREFS_NAME: string = 'yellow_river_prefs';
  static SYNC_BATCH_SIZE: number = 50;
  static RECOMMEND_COUNT: number = 6;
  static PAGE_SIZE: number = 20;
}
