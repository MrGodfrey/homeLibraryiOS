# homeLibrary 重构计划（含真实 CloudKit 测试环境）

## 摘要
- 把当前 `publicCloudDatabase + 仓库账号密码` 的协作模型，重构为标准 `CKShare` iCloud 共享模型。
- 把首页和仓库管理改成以“家庭书库使用体验”为中心：动态地点、双栏书墙、悬浮筛选、底部玻璃搜索、高级管理区。
- 把测试分成两层：默认测试继续走内存驱动；新增一套显式的真实 CloudKit 集成测试，固定在已登录测试 iCloud 账号的 `iPhone 17` 模拟器上运行，命中 `Development` 环境。
- 文档同步重写：`README.md` 采用需求优先结构，`log.md` 继续 append-only，并把 CloudKit 调试与环境约束写清楚。

## 关键实现变更
### 1. CloudKit 数据与共享模型
- 远端主线改成：owner 私有数据库中的自定义 zone 承载一个家庭书库；共享通过 `CKShare` 暴露给家庭成员；加入者从 `sharedCloudDatabase` 访问共享仓库。
- 废弃账号密码加入流程，删除 `RepositoryCredentials`、`joinRepository(account:password:)`、`rotateCredentials` 以及所有对应 UI、README 和测试叙述。
- `LibraryRepositoryReference` / `RepositoryDescriptor` 升级为 share-aware 模型，至少包含：仓库 id、显示名、角色、数据库作用域、zone 标识、share 状态。
- `LibraryRemoteSyncing` 重写为仓库级接口：创建自有仓库、列出可访问仓库、读取仓库元数据、创建/管理 share、接受 share、在指定仓库 zone 中执行书籍 CRUD、清空仓库、导出仓库。
- 应用接入系统共享链路：`CKSharingSupported = true`、分享控制器、接受分享回调、`CKAcceptSharesOperation`、shared/private 数据库切换。
- 旧公共库数据提供一次性升级迁移：把旧 `LibraryRepository` / `LibraryBook` 数据复制进新的私有共享仓库；旧成员关系不自动迁移，owner 需重新发送共享链接。

### 2. 本地模型、迁移与仓库设置
- 用仓库级 `LibraryLocation` 配置替换硬编码 `BookLocation` 枚举；书籍改存 `locationID`，首页“全部”保留为 UI 虚拟筛选项。
- 默认迁移把旧 `成都`、`重庆` 变成初始地点配置，并把旧书映射到新地点 id。
- 仓库设置页重组为“仓库信息 / 地点配置 / 高级管理区”。
- 高级管理区固定包含三项：旧数据迁移、清空当前仓库、导出当前仓库 zip。
- 迁移流程增加可视进度状态：先统计总数，再显示 `已导入 x / total`，完成后显示成功；迁移后按需清理旧本地历史数据。
- 导出格式统一为 zip，根目录放 `LibraryImport.json`，内嵌封面数据，保证可再次导入。

### 3. 首页与编辑体验
- 首页删除仓库信息面板，只保留内容浏览。
- 书籍列表改为双栏书墙；卡片稳定显示竖向封面、标题、作者、出版社、地点。
- 顶部改为固定透明地点切换条；滚动超过阈值后隐藏“家藏万卷”标题，只保留地点切换。
- 底部搜索改为自定义悬浮玻璃搜索控件，不再依赖 `.searchable` 顶部搜索栏。
- 卡片交互改成两段式：先选中并压暗封面显示“修改/删除”，再执行具体动作。
- 编辑页删除“当前版本只保留手动录入”说明；地点选择改成动态地点列表；新建书籍默认沿用当前筛选地点或仓库默认地点。

### 4. 真实 CloudKit 测试环境
- 默认测试策略不变：现有单测与 UI 测试继续默认走内存驱动，保持稳定、快速、可重复。
- 在 [LibraryAppConfiguration.swift](/Users/wangyu/code/homeLibraryApp/homeLibrary/homeLibrary/LibraryAppConfiguration.swift) 增加显式覆盖优先级：`HOME_LIBRARY_REMOTE_DRIVER=cloudkit` 时，即使在 `XCTestConfigurationFilePath` 存在的情况下也强制使用 `CloudKitLibraryService`；未显式指定时仍保留现有 memory 默认。
- 复用现有 host-backed 单测 target，不新建 target；当前 `homeLibraryTests` 已绑定 `TEST_HOST = homeLibrary.app`，适合承载真实 CloudKit 集成测试。
- 新增独立 live 测试入口，例如 `CloudKitLiveIntegrationTests`，默认不随常规 `test_sim` 运行，只有显式指定时才跑。
- 真实 CloudKit 测试固定使用：
  - CloudKit 环境：`Development`
  - 模拟器：booted `iPhone 17`
  - 测试账号：该模拟器当前已登录的专用 iCloud 账号
  - 数据隔离：专用测试仓库或测试 zone，不复用日常仓库
- live 测试执行时注入专用环境：
  - `HOME_LIBRARY_REMOTE_DRIVER=cloudkit`
  - `HOME_LIBRARY_STORAGE_NAMESPACE=cloudkit-live-tests`
  - `HOME_LIBRARY_CLOUDKIT_LIVE_TESTS=1`
  - 可选的测试仓库前缀或固定 zone 名，保证查找与清理可控
- live 测试默认自清理：每个测试用例在专用测试仓库/zone 下建数据并在结束时删除；保留失败现场时用显式环境开关控制，不作为默认行为。
- UI 测试先继续走 memory；真实 CloudKit UI 验证先做手动验收，不把真网 UI 测试并入首版自动化。

### 5. 文档、调试与运行说明
- `README.md` 改成需求优先结构，并新增“真实 CloudKit 测试”章节，明确 Development / Production 差异、模拟器前提、显式测试入口和数据清理规则。
- `log.md` 每次结构性修改、测试环境调整、CloudKit 经验结论都追加记录。
- 新增调试模式要求：对 CloudKit 失败保留脱敏上下文，包括操作名、数据库作用域、zone/仓库 id、CKError code、用户可见错误。
- 旧 README 中关于公共库 queryable 索引的内容降级为兼容旧架构的迁移/排障补充，不再作为主线说明。

## 测试计划
- 单元测试：动态地点配置、旧地点迁移、导入进度状态、导出包编码、仓库状态持久化。
- 内存集成测试：新仓库创建、筛选、搜索、编辑、删除、导入、清空。
- 真实 CloudKit 集成测试：Development 环境下创建专用测试仓库、写入书籍、读取回显、删除、清空、导出、仓库发现。
- 共享链路验证：owner 创建共享、接受邀请、shared 仓库读写、owner 移除参与者后的权限变化。
- 手动验收：在 booted `iPhone 17` 模拟器上确认测试账号可访问 CloudKit，执行 live 测试入口，并做一轮真实共享操作。

## 默认假设
- 真网 CloudKit 测试只在本地显式运行，不并入默认测试入口，不进 CI 默认路径。
- 真实测试先只覆盖集成层，不把现有 UI 测试切到真网。
- Development 和 Production 使用同一套数据格式与业务模型，差异只在 CloudKit 环境与部署节奏。
- live 测试以专用测试仓库/zone 为隔离单位，避免污染日常数据。
