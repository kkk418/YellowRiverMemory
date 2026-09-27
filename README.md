# 黄河记忆 · Yellow River Memory

> 基于 **HarmonyOS 5.0.2（API 14）**（ArkTS + Stage模型）开发的黄河文化数字档案应用。
> 当前预置数据为演示规模，主要展示文化浏览、个人研学记录与可信设备间的分布式同步。

## ✨ 核心亮点

### 1. 沉浸式文化探索
- 参考「数字敦煌」视觉：墨黑底 + 黄河金 + 衬线大标题 + 大图直角卡片
- 覆盖**仰韶→龙山→夏商→周→汉唐→宋**6个历史时期、5座城市、10处核心遗址、30件精品文物
- 三维组织：年代·城市·类型；关键词检索+多维度筛选
- 详情页含：图文介绍 · 考古发现 · 历史年轮时间线 · 题咏诗词 · 现代文旅 · 馆藏文物

### 2. 个人收藏与笔记
- 遗址/文物一键收藏，收藏时弹出标签Sheet（系统标签+自定义标签）
- 任意条目添加笔记（文字+时间戳+标签+关联对象），形成个人学习记录
- 按标签管理（待探访/已去过/研究资料等）
- 浏览足迹自动记录，按今天/昨天/近7天分组展示

### 3. 智能推荐（现有原型，非本轮验收项）
- 基于收藏/浏览历史构建用户偏好画像（年代/区域/类型三维权重）
- 混合推荐：同期文化 · 同区域脉络 · 同类型 · 国宝精选
- 多样性策略：每个理由维度最多4条，避免同质
- 详情页"文脉相连/同期文明"基于时序+同城+同类多因子评分

### 4. 分布式数据同步（比赛核心）
- 基于 `@kit.ArkData.distributedKVStore` 与可信设备发现能力实现同步
- **LWW（Last-Writer-Wins）**：按更新时间、设备标识确定胜出版本
- 离线变更先写入本地数据库和持久化待同步队列；前台或手动同步时重试
- 全局顶部SyncStatusBar实时展示同步状态
- 同步面板：设备连线动效+金色粒子流动+设备列表+进度+冲突数+冲突Sheet

### 5. 文化主题与个人知识库（现有原型，非本轮验收项）
- 自定义主题（如"夏商文明溯源"），将收藏的遗址/文物聚合归类
- 主题卡片统计：遗址数/文物数/笔记数
- 简化放射状**知识图谱可视化**（主题为中心，辐射时代/遗址/文物节点）
- 主题数据同样通过分布式服务多端同步

### 6. 后续计划
- 知识图谱与推荐持续完善
- 文件备份、导入恢复与扩充文化内容尚未纳入本轮参赛闭环

## 🛠 技术架构

```
┌─────────────────────────────────────────────────┐
│  UI 层（ArkUI 声明式）                           │
│  pages / view (home/browse/note/collection/...)  │
│  components (Card/Chip/Timeline/Sheet/StatusBar) │
├─────────────────────────────────────────────────┤
│  Service 层                                       │
│  CultureService   预置文化数据+内存缓存            │
│  UserDataService  收藏/笔记/主题/历史/搜索         │
│  DistributedDataService  鸿蒙KV分布式同步+LWW     │
│  RecommendationService  智能推荐算法              │
│  TopicService     主题聚合+知识图谱                │
│  BackupService    备份/恢复（暂未开放入口）          │
├─────────────────────────────────────────────────┤
│  数据层                                           │
│  LocalRdbHelper   RDB关系型数据库（含迁移与待同步队列）│
│  AssetRepository  Rawfile预置JSON首次导入          │
│  PreferencesHelper KV偏好存储                     │
│  MemoryCache      启动预热零延迟访问               │
└─────────────────────────────────────────────────┘
```

## 📁 项目结构

```
YellowRiverMemory/
├── AppScope/
│   └── app.json5                  # 应用全局配置
├── entry/src/main/
│   ├── ets/
│   │   ├── common/
│   │   │   ├── constants/         # Colors / Enums / AppMeta(元数据)
│   │   │   └── utils/             # Logger / EventBus / DateUtil / StringUtil / PreferencesHelper
│   │   ├── database/              # LocalRdbHelper + AssetRepository
│   │   ├── model/
│   │   │   ├── entity/Entities.ets        # 12个实体接口
│   │   │   └── dto/DTOs.ets
│   │   ├── service/
│   │   │   ├── CultureService.ets         # 文化资源服务（含内存缓存）
│   │   │   ├── UserDataService.ets        # 用户数据CRUD
│   │   │   ├── DistributedDataService.ets # 分布式KV同步+LWW冲突
│   │   │   ├── RecommendationService.ets  # 智能推荐算法
│   │   │   ├── TopicService.ets           # 主题聚合+知识图谱
│   │   │   └── BackupService.ets          # 备份/恢复
│   │   ├── entryability/EntryAbility.ets  # 生命周期+初始化链
│   │   ├── pages/Index.ets                # 根页（Tabs+Navigation+Splash）
│   │   └── view/
│   │       ├── home/HomePage.ets          # 首页（Hero+时间轴+城市+每日+推荐+精选）
│   │       ├── browse/                    # 探源（筛选浏览+搜索结果）
│   │       ├── note/                      # 笔记列表+编辑器
│   │       ├── collection/CollectionPage.ets  # 收藏夹
│   │       ├── history/HistoryPage.ets    # 浏览足迹
│   │       ├── topic/TopicPage.ets        # 主题聚合+知识图谱
│   │       ├── sync/SyncPage.ets          # 同步面板
│   │       ├── profile/ProfilePage.ets    # 我的
│   │       ├── detail/                    # 遗址详情+文物详情
│   │       └── components/                # SiteCard/ArtifactCard/TagChip/EraTimeline/
│   │                                        LoadingIndicator/EmptyState/
│   │                                        FavoriteTagSheet/SyncStatusBar
│   ├── resources/
│   │   ├── base/element/                  # color/float/string 资源（52色值）
│   │   ├── base/profile/main_pages.json
│   │   └── rawfile/data/preset.json       # 预置数据：10遗址+30文物+7诗词
│   └── module.json5               # 模块、设备类型与权限声明
├── build-profile.json5
└── oh-package.json5
```

## 🔄 初始化链（EntryAbility）

```
PreferencesHelper.init(ctx)
   ↓
LocalRdbHelper.init(ctx)              # RDB建表（12表，含迁移与同步队列）
   ↓
AssetRepository.initIfNeeded(resMgr)  # 首次启动导入rawfile预置数据
   ↓
CultureService.warmCache()            # 预热内存Map
   ↓
UserDataService.ensureReady()         # 收藏Set缓存与本机设备标识
   ↓
emit DATA_INIT_COMPLETED
   ↓
窗口加载首页
   ↓
请求分布式同步授权并启动 DistributedDataService
```

## 🚀 运行方法

1. 使用支持 HarmonyOS 5.0.2（API 14）的 DevEco Studio（建议 5.0.2 或更高兼容版本）打开本项目
2. 使用 HarmonyOS 5.0.2（API 14）SDK / Stage 模型
3. 选择一个HarmonyOS NEXT模拟器或真机（手机/平板）
4. 点击运行 ▶ 自动编译部署
5. 首次启动会看到墨黑金色启动屏，1.8秒后进入首页
6. 多设备同步：在两台可信设备上安装同一签名应用，首次启动时授予分布式数据同步权限，再到「我的 → 多端数据同步」查看状态；仓库尚无真机验收记录

## 🎨 视觉规范

| 元素 | 色值 | 用途 |
|------|------|------|
| ink_wall | `#0A0806` | 墨黑底 |
| gold_primary | `#C9A96E` | 黄河金主色 |
| gold_dim | `#8B7355` | 次级金色 |
| vermillion | `#B5493A` | 朱砂（国宝章/错误/警示）|
| pottery_orange | `#C4653D` | 仰韶橙陶 |
| era_longshan | `#4A5568` | 龙山灰陶 |
| bronze_green | `#5C7A6E` | 汉唐青铜绿 |
| blue_white | `#3E6B8A` | 宋青花蓝 |

字体：系统默认 + 衬线大标题（`fontFamily: 'serif'`），数字/英文加 `letterSpacing`。

## 🏛 预置内容

**10处演示遗址**：实际城市/地域口径仍需进一步核定；详情页图片当前使用占位视觉

**30件精品文物**：彩陶双连壶、蛋壳黑陶杯、绿松石龙形器、司母戊鼎、莲鹤方壶、武则天除罪金简等（国宝级打朱砂"国 宝"徽章）

**7首诗词**：王之涣《登鹳雀楼》、李白《将进酒》、杜甫《黄河二首》、王维《使至塞上》等

## 📊 完成度

| 阶段 | 状态 | 说明 |
|------|------|------|
| 阶段一·项目骨架 | 已实现 | ArkTS 工程、预置数据和本地关系型数据库 |
| 阶段二·核心页面 | 原型已实现 | 首页/探索/详情/搜索/收藏/同步/我的；需在目标 SDK 编译验收 |
| 阶段三·个人数据 | 原型已实现 | 收藏、笔记和历史；需完成设备端回归 |
| 阶段四·分布式同步 | 实现待真机验证 | 可信设备发现、加密 KV、持久化队列和冲突记录已接入；未宣称双机验收完成 |
| 阶段五·拓展功能 | 暂不作为本轮验收项 | 推荐、主题图谱和备份恢复仍需单独验证 |

编译、升级和双设备时延的实测结果记录在 `../docs/10-核心闭环验收记录.md`；完成前不将分布式同步标记为已验收。

## ⚠️ 注意事项

- 图片资源使用**朝代色渐变色块+名称水印**作为占位，无真实图片依赖；实际部署时将图片放入 `resources/base/media/` 并替换Image路径即可
- 分布式功能需在**两台已组网的真机**上验证；本仓库不包含真机验收结果
- 所有Service均为单例，CRUD后自动emit EventBus事件驱动UI刷新，内存缓存保证零延迟访问
- 预置数据在首次启动时一次性导入RDB，后续启动直接读库，完全支持离线浏览

---
**一条河，五千年，文明不息。**
