**黄河记忆：可靠性与参赛展示交付记录（2026-10-06）**

源码目录：E:\codexproject\YellowRiverMemory。本报告记录本轮代码处理及实际验收结果；提交与推送状态以 Git 历史为准。原有 .archify/ 保留在本机。

**代码处理**

| 问题 | 实现 |
| --- | --- |
| 同步超时及迟到回调 | syncComplete 仅检查应用层 ACK。接收端本地事务提交后才确认；发送端要求每个目标设备的原版本和胜出版本匹配，并在事务内再次比较当前 outbox JSON 后删除。15 秒超时保留 outbox，退避重试；轮次保护阻止旧超时结束新同步。迟到的有效 ACK 可以恢复状态。 |
| 重连、离线编辑与扫描 | 普通同步只处理 outbox。启动、对端变化、断网恢复和异常后校准全量数据；同一网络下返回前台不再无条件全扫。软删除通过版本记录传播。变化数只统计实际应用或确认的唯一实体版本。 |
| 冲突 | 更新时间优先；同时间按设备标识的字符串顺序决定胜出方。并发版本写入可查看的冲突表，输掉的远端版本不会覆盖本地胜出版本；必要时重新发布胜出方。 |
| 数据事务安全 | 使用 API 14 Transaction 对象，并显式传递 RdbSession。实体、outbox 与本地版本一起提交；独立草稿或查询不会误加入别人的事务。主题删除和关系软删除作为同一批事务提交。 |
| 笔记 | 数据库 v4 增加本地 note_draft；350ms 自动保存、离开提醒、重新打开恢复。冲突保留当前输入并支持另存为新笔记。笔记提交与草稿删除同事务；保存期间阻止输入和重复操作。初始文本回填不再误生成草稿。 |
| 收藏 | 服务按目标串行，重复新增保持幂等；详情页显示处理中、阻止重复点击、显示失败提示。成功后由服务统一发送刷新事件。 |
| 刷新 | 首页订阅收藏与浏览变化；主题页订阅笔记、收藏和主题关系变化，笔记查询移到主题循环外。笔记列表修正 Builder 计数、异步加载次序和读取失败提示。 |
| 布局与兼容 | 列数随实际内容宽度变化；首页按高度缩短横屏标题、间距，修正透明渐变；详情和编辑区限制阅读宽度。整页导航修复横屏自动分栏导致的空白。避开底部导航手势区域。替换 API 26 才支持的绘图调用，移除枚举作为对象的编译警告。正式配置为 auto_rotation。 |
| 封面 | 逐条记录 10 遗址、30 文物的封面引用。打包 1 张已核实 CC0 的龙门石窟图片，其余 39 条明确占位。统一加载组件处理缺失和解码失败，缩小解码并释放资源；预置版本 v5 更新旧封面引用，不重建用户表。 |

图片原始页：[Rogerwilley 的龙门石窟照片](https://commons.wikimedia.org/wiki/File:Luoyang_-_Boddhisatvas_at_Longmen_Grotto.jpg)；许可：[CC0 1.0](https://creativecommons.org/publicdomain/zero/1.0/)。图片原文件打包，详情页展示作者及许可；原始页面、作者、修改情况和路径在 cover_manifest.json 中记录。占位图不计为补齐。

**实际检查及结果**

| 检查 | 结果与边界 |
| --- | --- |
| 最终构建 | BUILD SUCCESSFUL。compatibleSdkVersion 与 targetSdkVersion 均为 5.0.2(14)，实际编译器来自已安装的 API 26 SDK。尚未完成纯 API 14 SDK 编译。HAP 未签名，API 14 模拟器接受安装；正式真机签名未验收。 |
| 首装与文化数据 | API 14 手机模拟器实际创建 v4 数据库并导入 10 遗址、30 文物、7 诗词，启动和浏览成功。 |
| 旧库迁移 | verify-runtime.mjs 转译并调用实际 LocalRdbHelper 的 v1/v2/v3 -> v4 迁移函数，以 SQLite 适配器执行；代表性收藏、笔记、主题和关系保留，v1 重复收藏保留较新版本。属于本机服务检查，旧 HAP 在 ArkData 上升级仍待设备验证。 |
| 服务检查 | 首装导入、事务隔离/回滚、12 次重复收藏仅一条记录/一次新增事件、笔记增删改、草稿冲突保留、主题关系软删除通过。 |
| 编辑器检查 | 执行实际编辑器状态和生命周期方法，自动草稿、返回拦截、恢复、冲突输入保留、另存为新笔记通过；此项不覆盖 ArkUI 渲染。 |
| 可控同步事件 | 超时保留、自动重试、迟到回调和旧计时器、过期 ACK 不清新版本、每个对端逐条确认、提交失败不发 ACK、KV 发布失败保留、恢复重试、软删除、等时间冲突收敛、唯一变化数和普通同步无全扫均通过。使用模拟 KV 与网络接口，不能证明真实分布式传输时延。 |
| 实际笔记 UI | API 14 模拟器输入 DraftCheck 与正文，返回出现保留提醒；停止并重启进程后草稿标题和正文恢复；保存后列表显示笔记并清理草稿；修改正文后列表更新；打开后直接返回不再生成多余草稿；删除后列表及分类计数为 0。覆盖安装仍保留此前笔记。 |
| 实际收藏 UI | API 14 模拟器新增和取消收藏成功，重启后状态保留。快速重复操作与失败路径另由服务检查覆盖。 |
| 实际封面 UI | 龙门石窟列表、详情图片解码显示成功，作者及 CC0 署名可见；无图片的文物显示“暂无授权图片”。 |
| 手机布局 | 竖屏实际检查浏览、详情、笔记编辑。临时 landscape 配置在同一 API 14 模拟器检查横屏首页、列表和笔记编辑，修复导航空白后保存截图；随后恢复 auto_rotation 并重新构建。尚未证明设备传感器自动旋转和所有键盘/窗口尺寸组合。 |
| 静态检查 | verify-local.mjs 的 40 条引用/授权/本地文件一致性和 SQLite DDL 检查通过。git diff --check 无空白错误；仅换行符提示。 |

可重跑命令（从项目根目录，Node 24）：

```powershell
& 'D:\hongmeng IDE\DevEco Studio\tools\node\node.exe' verify-runtime.mjs
& 'D:\hongmeng IDE\DevEco Studio\tools\node\node.exe' verify-local.mjs
```

verify-runtime.mjs 使用 DevEco 自带 TypeScript，可用 YRM_TYPESCRIPT_PATH 指向其他 TypeScript 安装。测试只在系统临时目录生成 SQLite 库并清理，不访问应用实际用户数据库。

**仍待完成或设备验证**

- API 14 SDK 原生编译及正式签名真机安装。当前安装目录只有 API 26 编译 SDK；配置目标 API 14 与 API 14 模拟器运行已经验证。
- 两台可信真机的 3 秒前台同步、断网重连、迟到确认、冲突收敛和延迟计时。当前没有已连接真机，不宣称通过。
- 将实际 v1/v2/v3 应用数据库在 ArkData 上升级，以及关闭设备网络、重启、恢复网络后的真实传输验证。本轮已做服务迁移、持久性与恢复逻辑检查，以及无同步对端时的模拟器草稿跨进程恢复。
- 平板横竖屏、键盘避让及自动旋转。MatePad Pro 13 配置指向 API 26 平板镜像，但该镜像目录缺失，启动未成功；没有把手机横屏视为平板验收。
- 39 个条目仍无已打包的许可图片（9 个遗址、30 件文物）。加载失败回退在代码中实现，尚未做全部损坏文件注入的设备测试。
- 实际首页推荐与主题统计的全部操作组合仍需设备回归；事件订阅与防止旧查询覆盖已改，笔记列表实际刷新通过。
- 构建保留异常处理提示、API 26 SDK 对 AlertDialog 的弃用提示，以及 app_name 资源重复声明提示；未将其描述为无警告构建。

**本轮修改/新增文件**

- [entry/src/main/ets/common/constants/AppMeta.ets](E:/codexproject/YellowRiverMemory/entry/src/main/ets/common/constants/AppMeta.ets)
- [entry/src/main/ets/common/utils/EventBus.ets](E:/codexproject/YellowRiverMemory/entry/src/main/ets/common/utils/EventBus.ets)
- [entry/src/main/ets/database/AssetRepository.ets](E:/codexproject/YellowRiverMemory/entry/src/main/ets/database/AssetRepository.ets)
- [entry/src/main/ets/database/LocalRdbHelper.ets](E:/codexproject/YellowRiverMemory/entry/src/main/ets/database/LocalRdbHelper.ets)
- [entry/src/main/ets/entryability/EntryAbility.ets](E:/codexproject/YellowRiverMemory/entry/src/main/ets/entryability/EntryAbility.ets)
- [entry/src/main/ets/pages/Index.ets](E:/codexproject/YellowRiverMemory/entry/src/main/ets/pages/Index.ets)
- [entry/src/main/ets/service/DistributedDataService.ets](E:/codexproject/YellowRiverMemory/entry/src/main/ets/service/DistributedDataService.ets)
- [entry/src/main/ets/service/RecommendationService.ets](E:/codexproject/YellowRiverMemory/entry/src/main/ets/service/RecommendationService.ets)
- [entry/src/main/ets/service/TopicService.ets](E:/codexproject/YellowRiverMemory/entry/src/main/ets/service/TopicService.ets)
- [entry/src/main/ets/service/UserDataService.ets](E:/codexproject/YellowRiverMemory/entry/src/main/ets/service/UserDataService.ets)
- [entry/src/main/ets/view/browse/BrowsePage.ets](E:/codexproject/YellowRiverMemory/entry/src/main/ets/view/browse/BrowsePage.ets)
- [entry/src/main/ets/view/components/ArtifactCard.ets](E:/codexproject/YellowRiverMemory/entry/src/main/ets/view/components/ArtifactCard.ets)
- [entry/src/main/ets/view/components/EmptyState.ets](E:/codexproject/YellowRiverMemory/entry/src/main/ets/view/components/EmptyState.ets)
- [entry/src/main/ets/view/components/EraTimeline.ets](E:/codexproject/YellowRiverMemory/entry/src/main/ets/view/components/EraTimeline.ets)
- [entry/src/main/ets/view/components/LoadingIndicator.ets](E:/codexproject/YellowRiverMemory/entry/src/main/ets/view/components/LoadingIndicator.ets)
- [entry/src/main/ets/view/components/SiteCard.ets](E:/codexproject/YellowRiverMemory/entry/src/main/ets/view/components/SiteCard.ets)
- [entry/src/main/ets/view/components/SyncStatusBar.ets](E:/codexproject/YellowRiverMemory/entry/src/main/ets/view/components/SyncStatusBar.ets)
- [entry/src/main/ets/view/detail/ArtifactDetailPage.ets](E:/codexproject/YellowRiverMemory/entry/src/main/ets/view/detail/ArtifactDetailPage.ets)
- [entry/src/main/ets/view/detail/SiteDetailPage.ets](E:/codexproject/YellowRiverMemory/entry/src/main/ets/view/detail/SiteDetailPage.ets)
- [entry/src/main/ets/view/home/HomePage.ets](E:/codexproject/YellowRiverMemory/entry/src/main/ets/view/home/HomePage.ets)
- [entry/src/main/ets/view/note/NoteEditorPage.ets](E:/codexproject/YellowRiverMemory/entry/src/main/ets/view/note/NoteEditorPage.ets)
- [entry/src/main/ets/view/note/NoteListPage.ets](E:/codexproject/YellowRiverMemory/entry/src/main/ets/view/note/NoteListPage.ets)
- [entry/src/main/ets/view/profile/ProfilePage.ets](E:/codexproject/YellowRiverMemory/entry/src/main/ets/view/profile/ProfilePage.ets)
- [entry/src/main/ets/view/sync/SyncPage.ets](E:/codexproject/YellowRiverMemory/entry/src/main/ets/view/sync/SyncPage.ets)
- [entry/src/main/ets/view/topic/TopicPage.ets](E:/codexproject/YellowRiverMemory/entry/src/main/ets/view/topic/TopicPage.ets)
- [entry/src/main/module.json5](E:/codexproject/YellowRiverMemory/entry/src/main/module.json5)
- [entry/src/main/resources/rawfile/data/preset.json](E:/codexproject/YellowRiverMemory/entry/src/main/resources/rawfile/data/preset.json)
- [entry/src/main/ets/common/utils/NoteLeaveGuard.ets](E:/codexproject/YellowRiverMemory/entry/src/main/ets/common/utils/NoteLeaveGuard.ets)
- [entry/src/main/ets/service/NoteDraftService.ets](E:/codexproject/YellowRiverMemory/entry/src/main/ets/service/NoteDraftService.ets)
- [entry/src/main/ets/view/components/LicensedCover.ets](E:/codexproject/YellowRiverMemory/entry/src/main/ets/view/components/LicensedCover.ets)
- [entry/src/main/resources/rawfile/data/cover_manifest.json](E:/codexproject/YellowRiverMemory/entry/src/main/resources/rawfile/data/cover_manifest.json)
- [entry/src/main/resources/rawfile/images/sites/longmen.jpg](E:/codexproject/YellowRiverMemory/entry/src/main/resources/rawfile/images/sites/longmen.jpg)
- [verify-local.mjs](E:/codexproject/YellowRiverMemory/verify-local.mjs)
- [verify-runtime.mjs](E:/codexproject/YellowRiverMemory/verify-runtime.mjs)

**交付产物**

- [最终构建日志](E:/codexproject/YellowRiverMemory/verification/final-build.log)
- [服务检查日志](E:/codexproject/YellowRiverMemory/verification/host-checks.log)
- [龙门石窟详情截图](E:/codexproject/YellowRiverMemory/verification/phone-longmen-final.png)
- [手机横屏首页截图](E:/codexproject/YellowRiverMemory/verification/phone-home-landscape.png)
- [手机横屏笔记截图](E:/codexproject/YellowRiverMemory/verification/phone-note-landscape.png)
- [最终未签名 HAP](E:/codexproject/YellowRiverMemory/entry/build/default/outputs/default/entry-default-unsigned.hap)

verification/ 中先前保存的旧截图和布局记录保留在本机；以上命名截图及两份日志作为本轮证据入库，未签名 HAP 留在本机构建目录。README 未新增“真机能力已完成”的标记。
