# Change Log

## 2026-04-14

- 重写数据与同步主线：从 `本地 JSON + iCloud Documents / 共享文件夹` 切换到 `CloudKit 数据库 + 仓库模型`。
- 新增仓库会话层：引入 `我的仓库` / `加入的仓库` 概念，使用应用内生成的仓库账号密码进行协作接入。
- 新增 CloudKit 远端服务：实现 `LibraryRepository` 与 `LibraryBook` 两类记录的创建、查询、更新、软删除和封面 `CKAsset` 上传。
- 新增版本化 `BookPayload`：把书籍业务字段放进可扩展 JSON，给后续增删字段留出空间。
- 重做本地存储：本地只保留 `cloudkit-cache/<repository-id>/` 缓存，不再承担 iCloud Drive 镜像职责。
- 新增历史迁移：首次进入自己的 CloudKit 仓库时，自动导入旧 `books/ covers/ deletions/` 或 `books.json`，随后清理旧结构。
- 移除旧能力：删除 ISBN 自动补全、扫码录入、共享文件夹同步、个人 iCloud Documents 同步、多平台目标叙述。
- 将工程收敛为 iPhone only：调整 target 平台与设备族，移除 macOS / iPad / xr 方向。
- 更新权限声明：`homeLibrary.entitlements` 改为 CloudKit，`Info.plist` 删除相机权限说明，仅保留相册权限。
- 新增仓库管理界面：可查看当前仓库、分享自己的仓库账号密码、加入别人的仓库、切回自己的仓库、重新生成凭据。
- 更新单元测试：覆盖搜索、草稿规范化、仓库会话存储、本地缓存、旧结构迁移。
- 保留并验证 UI 测试主流程：新增 -> 搜索 -> 编辑 -> 删除，以及启动烟测。

### 验证记录

- `xcodebuild ... build` 通过
- `homeLibraryTests` 共 `6` 个测试通过
- `homeLibraryUITests.testAddSearchEditAndDeleteBookOnIOS` 通过
- `homeLibraryUITestsLaunchTests.testLaunch` 通过

## 2026-04-14（增补）

- 新增结构化旧库种子导入：支持从 `SeedBooks.json` 读取书籍与封面，不再只依赖旧 `books/`、`covers/`、`deletions/` 或 `books.json`。
- 新增本地模式自动灌库：当 `local-default` 仓库本地缓存为空时，应用会自动把 `SeedBooks.json` 导入本地缓存，便于 iPhone / Simulator 在不开 CloudKit 时直接查看旧数据。
- 新增 CloudKit 空仓库自动灌库：当拥有者首次进入自己的空 CloudKit 仓库时，应用会自动把同一份 seed 上传到远端，并继续走现有缓存刷新链路。
- 新增结构化 seed 兼容层：支持新的 `schemaVersion/source/exportedAt/books[]` 包格式，同时继续兼容旧数组格式。
- 保留旧库 `isbn`：迁移时把旧字段写入 `customFields["ISBN"]`，避免在新模型里丢失信息。
- 更新 Cloudflare 导出脚本：`scripts/import_from_cloudflare.mjs` 现在直接生成结构化 `homeLibrary/SeedBooks.json`，可作为本地模式和 CloudKit 模式共用的一次性导入源。
- 生成最新迁移种子：已从旧 Cloudflare 仓库导出 `110` 本书，生成本地 `homeLibrary/SeedBooks.json`，供后续打包和首次迁移使用。
- 更新应用图标资源：将 `IconKitchen` 导出的 iOS 图标集替换到 `AppIcon.appiconset`。

### 验证记录

- `node scripts/import_from_cloudflare.mjs --source-repo /Users/wangyu/code/Home-library --output homeLibrary/SeedBooks.json` 生成成功
- 生成的 `homeLibrary/SeedBooks.json` 大小约 `19.65 MB`
- `xcodebuild -project homeLibrary.xcodeproj -scheme homeLibrary -destination 'platform=iOS Simulator,name=iPhone 17' build` 通过
- 构建产物确认执行 `CpResource ... SeedBooks.json ... homeLibrary.app`

## 2026-04-15

- 去掉本地模式主路径：`LibraryAppConfiguration.live()` 不再根据 `Debug` 或环境变量回退到本地模式，应用运行默认始终按 CloudKit 仓库逻辑启动。
- 删除本地仓库语义：移除 `localOnly` 角色以及“本地模式 / 本地调试仓库”相关文案、状态和分支判断，仓库管理界面只保留 CloudKit 路径。
- 收敛 `LibraryStore`：加载、保存、删除统一走远端仓库同步与本地缓存刷新，不再保留本地模式专用 seed / cache 写入链路。
- 新增测试远端驱动：加入 `InMemoryLibraryRemoteService`，供单测和 UI 测试使用，避免测试宿主在启动期直接初始化 CloudKit。
- 调整测试配置：`XCTest` 宿主默认使用内存远端，UI 测试改为显式设置 `HOME_LIBRARY_REMOTE_DRIVER=memory`，不再通过关闭 Cloud sync 进入旧本地模式。
- 收紧 UI 交互与测试：移除书籍行整行点击进入编辑的手势，保留显式编辑按钮；UI 测试拆分为“新增并编辑”和“搜索过滤”两条稳定路径。

### 验证记录

- `Build iOS Apps / build_sim` 通过
- `Build iOS Apps / build_run_sim` 通过，应用可在 `iPhone 17` 模拟器启动
- `Build iOS Apps / test_sim -only-testing:homeLibraryTests` 通过，`10` 个单元测试全部通过
- `Build iOS Apps / test_sim -only-testing:homeLibraryUITests` 通过，`3` 个 UI 测试全部通过
- `Build iOS Apps / test_sim` 通过，整套 `13` 个测试全部通过

## 2026-04-15（CloudKit entitlement 修正）

- 修复真机 CloudKit entitlement 缺失：`homeLibrary` target 的 `Debug` 配置现在也绑定 `homeLibrary/homeLibrary.entitlements`。
- 在工程的 target attributes 中显式开启 iCloud capability，避免新设备上的调试包缺少 `com.apple.developer.icloud-services`。
- 重写 `README.md`：删除“`Debug` 走本地模式、`Release` 才启用 CloudKit”的过期说明，改为当前真实运行、测试驱动和签名要求。

### 验证记录

- `xcodebuild -project homeLibrary.xcodeproj -scheme homeLibrary -configuration Debug -showBuildSettings` 确认 `Debug` 带有 `CODE_SIGN_ENTITLEMENTS = homeLibrary/homeLibrary.entitlements`
- `xcodebuild -project homeLibrary.xcodeproj -scheme homeLibrary -configuration Release -showBuildSettings` 确认 `Release` 带有同一份 entitlement
- `Build iOS Apps / build_sim` 通过
- `xcodebuild -project homeLibrary.xcodeproj -scheme homeLibrary -configuration Debug -destination 'id=00008140-00186D4A2EEB001C' build -quiet` 通过

## 2026-04-15（CKShare 重构、动态地点与真网 CloudKit）

- 用标准 `CKShare` 重构仓库协作：远端主线切换到“owner 私有 zone + shared database 访问”，删除仓库账号密码加入模型及相关 UI、测试和文档叙述。
- 升级仓库模型：`LibraryRepositoryReference` 现在显式记录角色、数据库作用域、zone 标识和 share 状态；`LibraryRemoteSyncing` 改成仓库级接口。
- 引入动态地点：新增仓库级 `LibraryLocation`，书籍改存 `locationID`，旧 `成都 / 重庆` 自动映射为默认地点配置。
- 重做缓存与导出：仓库缓存新增 `locations.json`，导出统一为 zip，根目录写入 `LibraryImport.json` 并内嵌封面数据。
- 重做首页：移除仓库信息面板，改为双栏书墙、顶部透明地点切换、滚动隐藏 `家藏万卷`、底部悬浮毛玻璃搜索、两段式卡片操作。
- 重做仓库设置页：重组为“仓库信息 / 地点配置 / 高级管理区”，高级管理区固定提供旧数据迁移、清空当前仓库、导出当前仓库 zip。
- 增加迁移进度状态：导入前统计总数，导入中展示 `已导入 x / total`，完成后更新为成功状态。
- 接入系统共享链路：`Info.plist` 启用 `CKSharingSupported`，应用增加分享回调接收与 `CKAcceptSharesOperation` 处理。
- 调整测试环境优先级：`HOME_LIBRARY_REMOTE_DRIVER=cloudkit` 在 XCTest 宿主下也会强制启用 CloudKit；默认测试仍保持 memory。
- 新增 test-runner 环境变量兼容：为 host-backed 单测补充 `TEST_RUNNER_` 前缀环境变量兼容，解决 `xcodebuild`/测试运行器环境注入不一致的问题。
- 新增 live 集成测试：`CloudKitLiveIntegrationTests` 固定在 booted `iPhone 17` 模拟器上运行，命中真实 iCloud 测试账号和 CloudKit `Development` 环境。
- 收敛 CloudKit 主路径对 queryable index 的依赖：仓库发现改用 `databaseChanges(since:)` + 固定根记录，zone 内全量拉取改用 `recordZoneChanges(inZoneWith:since:)`，不再把旧公共库 query 索引作为主线前提。
- 修复 CloudKit 真网问题：处理了 shared DB 不支持 zone-wide query、清空仓库时同一记录被同时保存和删除等真实运行期错误。
- 重写 `README.md` 为需求优先结构；同步用更详细的实施版内容替换 `plan.md`。

### 验证记录

- `Build iOS Apps / build_sim` 通过
- `Build iOS Apps / test_sim -only-testing:homeLibraryTests` 通过，`18` 个测试里 `17` 个通过、`1` 个 live 测试在默认路径下按预期跳过
- `Build iOS Apps / test_sim -only-testing:homeLibraryUITests` 通过，`2` 个 UI 测试通过
- `Build iOS Apps / test_sim` 通过，整套 `20` 个测试中 `19` 个通过、`1` 个 live 测试按预期跳过
- `Build iOS Apps / test_sim -only-testing:homeLibraryTests/CloudKitLiveIntegrationTests` 在 `iPhone 17` 模拟器、真实 iCloud 账号、CloudKit `Development` 环境下通过

### CloudKit 经验结论

- 对 host-backed 单测，普通 shell 环境变量不一定会原样进入测试进程；需要通过 test-runner 环境注入，或在代码里兼容测试运行器前缀变量。
- `sharedCloudDatabase` 不适合沿用“整库 query”的仓库发现方式，更稳妥的做法是围绕共享 zone 和固定根记录组织模型。
- 如果 CloudKit 失败，需要尽早保留操作名、数据库作用域、zone 名和映射后的用户可见错误；否则很难分辨是网络、权限、schema 还是共享约束导致的问题。
- `Development` 和 `Production` 不需要两套数据格式；差异在 schema 发布与数据隔离，而不在业务模型。

## 2026-04-15（双模拟器 CKShare live test）

- 新增显式双模拟器 CloudKit 测试 harness：应用启动时如果注入 `HOME_LIBRARY_CLOUDKIT_AUTOMATION_COMMAND`，会进入只读于正常产品路径之外的 automation runner，按命令执行 owner/member 的共享与 CRUD 验证。
- 新增 host 侧编排脚本：`scripts/run_dual_sim_cloudkit_share_test.swift` 负责构建、安装、驱动 `iPhone 17` 和 `testPhone2`，并在每一步通过结果文件轮询确认状态，不再靠手工点 UI。
- 新增双端隔离策略：脚本为 owner/member 分别生成唯一 `HOME_LIBRARY_STORAGE_NAMESPACE` 和 `HOME_LIBRARY_SESSION_NAMESPACE`，避免污染你在 `testPhone2` 上的常用会话与缓存。
- 新增仓库命名覆盖：`LibraryAppConfiguration.live()` 现在支持 `HOME_LIBRARY_PREFERRED_REPOSITORY_NAME`，让 live harness 能为每次运行生成唯一测试仓库名并精确定位 cleanup 目标。
- 新增 CloudKit 调试辅助接口：`CloudKitLibraryService` 现在暴露 share URL / share metadata 辅助方法，供显式 live harness 使用。
- 新增测试期开关：`HOME_LIBRARY_CLOUDKIT_AUTOMATION_ALLOW_PUBLIC_SHARE=1` 时，只对一次性测试 share 把 `CKShare.publicPermission` 提升到 `.readWrite`，以便无 UI 的双模拟器脚本通过 share URL 自动接受共享；正式产品共享仍保持 `UICloudSharingController` 的 private 路径。
- 新增配置单测：覆盖 `HOME_LIBRARY_PREFERRED_REPOSITORY_NAME` 以及 `TEST_RUNNER_HOME_LIBRARY_PREFERRED_REPOSITORY_NAME` 的解析，确保 host-backed 测试可以稳定驱动唯一仓库名。

### 验证记录

- `Build iOS Apps / test_sim` 通过，`22` 个测试中 `21` 个通过、`1` 个 live 测试按预期跳过
- `swift scripts/run_dual_sim_cloudkit_share_test.swift` 于 `2026-04-15` 在 booted `iPhone 17` 与 `testPhone2` 上通过：
  - owner 创建仓库并共享
  - member 接受共享后完成书籍新增、读取、修改、删除
  - owner 验证更新和删除同步
  - owner 删除测试仓库
  - member 确认共享仓库已消失

### CloudKit 经验结论

- 仅凭 `CKShare.url` 还不足以让另一台设备自动接受一个 `publicPermission = .none` 且没有参与者的 share；要么先把参与者加进 share，要么像这次 harness 一样仅在显式测试环境里临时放宽成 link-based share。
- 对双账号 live test，最重要的不是“能不能接受共享”这一瞬间，而是“跑完之后能否把 member 常用账号恢复干净”；因此脚本必须把远端仓库删除验证和 member 侧共享消失确认放进主流程，而不是留给人手工善后。

## 2026-04-15（首页继续简化）

- 继续收紧首页头部：移除标题左侧装饰方块，删除刷新按钮，把同步状态并入 `我的仓库 / 已共享` 同一行，改成更小的内联状态字。
- 重构首页滚动头部：标题区和设置入口作为顶部引导内容，搜索框与地点筛选改为吸顶区域；向上滚动后自动切到紧凑态，只保留搜索和地点，向下回滚时恢复完整头部。
- 简化书墙信息密度：书籍卡片现在只保留封面、书名和作者，移除地点与出版社展示；封面占比和底部留白同步收紧。
- 调整悬浮添加入口：右下角大号加号改为更轻的 `添加` 按钮，和新的简洁头部风格保持一致。
- 同步更新 UI 自动化：搜索流程改为直接操作搜索输入框，主 UI 测试收敛为稳定的“建库 -> 添加 -> 搜索”路径，避免把不稳定的自定义卡片手势选中层混进默认烟测。

### 验证记录

- `Build iOS Apps / build_sim` 通过
- `Build iOS Apps / test_sim -only-testing:homeLibraryUITests` 通过，`2` 个 UI 测试通过
- `Build iOS Apps / test_sim -only-testing:homeLibraryTests` 通过，`20` 个测试中 `19` 个通过、`1` 个 live 测试按预期跳过

## 2026-04-15（暗黑模式与表单页统一主题）

- 抽出共享主题层：新增 `LibraryTheme.swift`，把背景、卡片、次级卡片、文字、描边、成功/失败状态等颜色统一改成支持亮色/暗色的动态配色。
- 修正首页暗黑模式：书墙卡片、空态、进度条、设置按钮、地点切换、同步状态文字等全部切到动态主题，不再只有搜索框能正确适配暗黑模式。
- 统一添加书籍页风格：保留原有表单交互，改用与首页一致的背景和卡片表面；分区标题、上传封面 / 移除封面操作行、封面占位底色统一到同一套视觉语言。
- 统一仓库设置页风格：表单背景、分区卡片、当前仓库标记、地点配置、共享与高级管理按钮改为和首页一致的主题和操作行样式，暗黑模式下不再保留系统默认的浅色分组感。
- 保持现有默认 UI 烟测路径不变，确保样式调整没有影响“建库 -> 添加 -> 搜索”的主流程。

### 验证记录

- `Build iOS Apps / build_sim` 通过
- `Build iOS Apps / test_sim -only-testing:homeLibraryUITests` 通过，`2` 个 UI 测试通过
- `Build iOS Apps / test_sim -only-testing:homeLibraryTests` 通过，`20` 个测试中 `19` 个通过、`1` 个 live 测试按预期跳过
- 暗黑模式下手动检查首页与仓库设置页，动态主题已生效

## 2026-04-15（首页添加按钮挪到右上角）

- 调整首页顶部操作区：移除右下角悬浮“添加”按钮，改为放到右上角并位于“设置”左侧。
- 收敛添加入口样式：顶部“添加”改为与设置按钮同尺寸的方形操作按钮，使用绿色底色和白色加号。
- 同步更新首页空态文案：引导文字改为提示用户点击右上角加号录入第一本书。
- 保持暗黑模式适配：添加按钮继续复用 `LibraryTheme.accent` 的动态绿色，暗色界面下与现有顶部控件保持同一套主题。

### 验证记录

- `Build iOS Apps / build_sim` 通过
- iPhone 17 模拟器启动后通过辅助树确认 `addBookButton` 位于 `repositoryManagementButton` 左侧，且两者尺寸一致
- 暗黑模式下手动截图确认首页顶部绿色添加按钮、白色加号和整体对比度正常

## 2026-04-16（修复切换仓库时地点列表崩溃）

- 修复仓库设置页地点列表的 SwiftUI 绑定方式：不再对 `draftLocations` 使用下标驱动的 `$array` 绑定，改为按地点 `id` 生成安全 binding，避免切换仓库时整组地点数组被替换后 `Toggle` 仍访问旧下标而触发越界崩溃。
- 补充仓库切换测试：新增 `LibraryStore` 单测，覆盖两个仓库之间来回切换后，地点列表会刷新为对应仓库的数据。
- 修正测试工程配置：`homeLibraryTests` 的 `TEST_HOST` 仍指向旧的 `homeLibrary.app/homeLibrary`，主 target 的 Swift module 名也被 `PRODUCT_NAME=家藏万卷` 带成中文，导致 `@testable import homeLibrary` 无法编译；现已固定为中文产物名 + `homeLibrary` 模块名，测试链路恢复可用。

### 验证记录

- `xcodebuild -project homeLibrary.xcodeproj -scheme homeLibrary -destination 'platform=iOS Simulator,id=8CC688D1-06E8-4A1D-BC56-8AE8A52BA492' -only-testing:homeLibraryTests test` 通过
- `28` 个测试执行完成，`27` 个通过，`1` 个 CloudKit live 测试按预期跳过

## 2026-04-16（仓库排序设置、地点即时生效与文档同步）

- 在仓库设置页新增“图书排序方式”，支持按作者首字母、按标题首字母、按添加时间、按修改时间排序，默认值为“按添加时间排序”。
- 新增仓库级排序偏好持久化：每个仓库单独记住自己的排序方式，切换仓库后会恢复对应设置。
- 新增中英文统一排序键：作者和标题排序会先把中文转为拼音，再和英文一起比较，避免中英混排时顺序异常。
- 调整当前仓库展示：仓库设置页不再显示当前仓库的灰字说明文字，当前仓库只保留名称与状态信息。
- 重做地点配置交互：地点列表改为拖拽排序，删除“保存地点配置”按钮；改名、显隐、增删、拖拽后都会直接应用。
- 增加地点配置收口逻辑：关闭设置页、切换仓库或创建仓库前，会先尝试落盘未保存的地点改动，避免最后一次编辑丢失。
- 扩充测试覆盖：新增排序算法、仓库级排序偏好、地点显隐、地点重排、清空仓库等单测；新增设置页 UI 测试，覆盖排序入口和主要管理操作。
- 同步更新文档：补充 `README.md` 中关于排序设置、地点即时生效和测试范围的说明；新增根目录 `AGENTS.md`，要求每次改动都追加记录到 `log.md`。

### 验证记录

- `Build iOS Apps / test_sim -only-testing:homeLibraryTests -only-testing:homeLibraryUITests` 通过
- 整套测试共 `39` 项，其中 `38` 项通过，`1` 个 CloudKit live 测试按预期跳过

## 2026-04-16（README 改写为 GitHub 展示版）

- 删除 `README.md` 中原来的“当前项目实际补充”整节，避免首页说明过度偏向开发过程。
- 重写“设计方式”章节，改成面向非技术读者的表达，明确“需求先于实现”“变更可追踪”“简单优先”“家庭协作优先”“AI First”。
- 重写需求说明，直接回答这个仓库对普通用户到底能解决什么问题，突出“统一看总量、记录基础信息、多人共用、功能保持克制”。
- 新增“当前版本功能”“明确不做的功能”“需求完成情况”三组面向外部展示的章节，弱化实现细节，强化产品边界。
- 将仓库设置、录入、编辑、删除、共享、导入导出等内容收拢到“用户接口”章节，按用户视角重新组织。
- 将数据模型、数据库模型、本地缓存、同步处理、测试覆盖整理到单独的“架构层”章节，并按当前代码实现详细说明 CloudKit 同步链路。
- 新增“预期实现的其他功能”章节，作为后续演进方向说明。

## 2026-04-16（首页书墙改为手机三列）

- 调整首页书墙网格：在紧凑宽度下默认按三列展示，缩小单本书封面占比；常规宽度下继续保持现有自适应列数和最多四列的策略。
- 补充布局回归测试：新增 `LibraryBookGridLayout` 单测，覆盖手机三列和宽屏自适应列数两种情况。
- 同步更新 `README.md` 首页浏览说明，补充手机竖屏默认三列展示的当前行为。

### 验证记录

- `xcodebuild -project homeLibrary.xcodeproj -scheme homeLibrary -destination 'platform=iOS Simulator,name=iPhone 17' build` 通过
- `xcodebuild -project homeLibrary.xcodeproj -scheme homeLibrary -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:homeLibraryTests -only-testing:homeLibraryUITests test` 通过
- 共执行 `44` 个测试，其中 `1` 个 CloudKit live 测试按预期跳过，其余全部通过

## 2026-04-16（首页书墙改为无框极小标题）

- 收紧首页书籍卡片：移除外层白色卡片框、描边和阴影，默认只显示封面与下方极小标题，不再显示作者。
- 调整首页标题样式：书名字号明显缩小，并限制为两行，降低封面下方文字占用。
- 保留原有选择逻辑：点击后仍可在封面上显示编辑、删除操作遮罩，其他交互不变。
- 同步更新 `README.md` 首页浏览说明，改成当前“紧凑书墙 + 极小标题”的展示描述。

### 验证记录

- `xcodebuild -project homeLibrary.xcodeproj -scheme homeLibrary -destination 'platform=iOS Simulator,name=iPhone 17' build` 通过
- `xcodebuild -project homeLibrary.xcodeproj -scheme homeLibrary -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:homeLibraryTests -only-testing:homeLibraryUITests test` 通过
- 共执行 `44` 个测试，其中 `1` 个 CloudKit live 测试按预期跳过，其余全部通过

## 2026-04-16（点封面直接编辑，删除入口收进编辑页）

- 调整首页书墙交互：移除封面点击后的编辑/删除遮罩，改为点击书籍封面后直接进入编辑页。
- 调整编辑页操作：在编辑书籍页最底部新增“删除书籍”按钮，删除前需要再次确认，删除成功后直接关闭编辑页。
- 补充回归测试：新增 UI 测试，覆盖“点书籍卡片进入编辑页”和“删除前二次确认”；新增 `LibraryStore` 单测，覆盖删除后书籍列表刷新为空。
- 同步更新 `README.md` 的录入、编辑、删除说明，确保当前交互与文档一致。

### 验证记录

- `xcodebuild -project homeLibrary.xcodeproj -scheme homeLibrary -destination 'platform=iOS Simulator,id=8CC688D1-06E8-4A1D-BC56-8AE8A52BA492' -only-testing:homeLibraryTests -only-testing:homeLibraryUITests test` 通过
- 共执行 `46` 个测试，其中 `1` 个 CloudKit live 测试按预期跳过，其余全部通过

## 2026-04-16（封面自动压缩与仓库整理）

- 新增封面压缩器：上传、编辑和导入封面时，会先把过大的图片下采样并压缩到适合首页小图标展示的尺寸和体积。
- 调整编辑页交互：选择封面后会立即执行压缩，处理中禁用保存并显示“正在压缩封面…”状态。
- 扩展高级管理区：新增“整理当前仓库封面”按钮，扫描当前仓库已有封面并显示“已处理多少 / 已压缩多少张图片”的进度。
- 补充自动化测试：新增 `LibraryCoverCompressionTests.swift`，覆盖封面压缩器、保存时自动压缩，以及仓库整理已有大图与进度回写；扩展现有 UI 测试，校验高级管理区里的新整理按钮可见。
- 同步更新 `README.md`，补充封面自动压缩、仓库整理入口和最新测试覆盖说明。

### 验证记录

- `xcodebuild -project homeLibrary.xcodeproj -scheme homeLibrary -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:homeLibraryTests test` 通过
- `xcodebuild -project homeLibrary.xcodeproj -scheme homeLibrary -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:homeLibraryTests -only-testing:homeLibraryUITests test` 通过
- 共执行 `50` 个测试，其中 `1` 个 CloudKit live 测试按预期跳过，其余全部通过

## 2026-04-16（封面整理确认弹窗与纯文字进度）

- 调整封面整理入口：点击“整理当前仓库封面”后，先弹出确认 alert，明确提示“此操作会替换所有的封面”。
- 调整高级管理展示：去掉整理进度前的进度条，改成纯文字状态，避免窄屏下一行放不下。
- 更新 UI 测试：仓库设置页现在会校验封面整理的确认弹窗文案与取消操作。
- 同步更新 `README.md`，补充封面整理需要再次确认和纯文字进度的当前行为说明。

### 验证记录

- `xcodebuild -project homeLibrary.xcodeproj -scheme homeLibrary -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:homeLibraryTests -only-testing:homeLibraryUITests test` 通过
- 共执行 `50` 个测试，其中 `1` 个 CloudKit live 测试按预期跳过，其余全部通过

## 2026-04-16（仓库设置按钮按下反馈与导出等待进度）

- 给仓库设置页里的主要操作按钮补了统一的按下态：点按时会出现轻微变色反馈，避免看起来像没有响应。
- 调整导出当前仓库 ZIP 的交互：导出开始后，会先弹出一个类似 alert 的模态进度层，显示当前正在读取数据、整理内容和生成 ZIP。
- 导出完成后，模态进度层会自动关闭，并继续打开系统共享面板；用户不再需要猜当前是否仍在工作。
- 新增 `LibraryExportProgressTests.swift`，覆盖导出开始时进度状态发布，以及导出结束后状态清理。
- 同步更新 `README.md`，补充仓库设置页按钮反馈、导出等待进度和最新测试数量说明。

### 验证记录

- `xcodebuild -project homeLibrary.xcodeproj -scheme homeLibrary -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:homeLibraryTests test` 通过
- `xcodebuild -project homeLibrary.xcodeproj -scheme homeLibrary -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:homeLibraryTests -only-testing:homeLibraryUITests test` 通过
- 共执行 `51` 个测试，其中 `1` 个 CloudKit live 测试按预期跳过，其余全部通过

## 2026-04-16（修复编辑页地点 Picker 无效 selection）

- 修复书籍编辑页地点 `Picker`：当当前草稿的 `locationID` 已经不在当前仓库地点列表里时，不再把无效 selection 直接交给 SwiftUI，避免控制台持续报 `does not have an associated tag`。
- 新增失效地点兼容：编辑已有图书且原地点已被删除时，地点选择器会保留一个“原地点已删除”的占位选项，避免用户只是改书名或作者时就被静默改写地点。
- 收紧新建图书默认地点：如果新建时带入的默认地点已经失效，编辑页会自动回退到当前仓库仍可选的地点，避免保存出无效 `locationID`。
- 补充 `BookDraft` 单测：覆盖“新建时回退到可用地点”和“编辑已有图书时保留失效地点占位”两条分支。
- 同步更新 `README.md` 的录入说明，补充失效地点在编辑页中的当前处理方式。

### 验证记录

- `Build iOS Apps / build_sim` 通过
- `Build iOS Apps / test_sim -only-testing:homeLibraryTests` 通过，共 `46` 个测试，其中 `45` 个通过、`1` 个 CloudKit live 测试按预期跳过
- `xcodebuild -project homeLibrary.xcodeproj -scheme homeLibrary -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:homeLibraryUITests test` 通过，`6` 个 UI 测试全部通过

## 2026-04-16（地点失效时改为静默回退）

- 调整编辑页地点失效策略：不再显示“原地点已删除”占位项；只要当前 `locationID` 不在仓库地点配置里，就直接静默回退到地点配置中的第一个可用地点。
- 统一新建与编辑行为：新建图书默认地点失效、或编辑旧图书遇到已删除地点时，都会落到当前第一个可选地点，避免界面暴露失效地点状态。
- 更新 `BookDraft` 单测，改为验证新建和编辑两条路径都会回退到第一个可用地点。
- 同步更新 `README.md` 的录入说明，确保文档与当前真实行为一致。

### 验证记录

- `Build iOS Apps / build_sim` 通过
- `Build iOS Apps / test_sim -only-testing:homeLibraryTests` 通过，共 `46` 个测试，其中 `45` 个通过、`1` 个 CloudKit live 测试按预期跳过
- `xcodebuild -project homeLibrary.xcodeproj -scheme homeLibrary -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:homeLibraryUITests test` 通过，`7` 个 UI 测试全部通过

## 2026-04-17（替换应用图标资源）

- 将你在 `/Users/wangyu/code/homeLibraryApp/AppIcons` 准备的新图标稿映射到工程现有的 `homeLibrary/Assets.xcassets/AppIcon.appiconset`，覆盖 iPhone、iPad、CarPlay 和 App Store 营销图标所需尺寸。
- 保留工程原有 `Contents.json` 声明，只替换对应 PNG 文件，避免改动 target 的资源配置方式。
- 同步更新 `README.md`，补充当前应用图标资源在工程中的管理位置和状态说明。

### 验证记录

- `xcodebuild -project homeLibrary.xcodeproj -scheme homeLibrary -destination 'generic/platform=iOS Simulator' build` 通过

## 2026-04-17（新增页草稿缓存、译者与 ISBN）

- 调整新增书籍页状态管理：把新增模式的 `BookDraft` 提升到父视图缓存，误滑关闭 sheet 后再次点“添加新书”会恢复未保存输入；右上角“取消”仍按显式放弃处理，会清空这份新增草稿。
- 扩展图书信息录入项：新增正式的“译者”和“ISBN”输入框，其中译者放在作者下方；保存时两项会和现有 `customFields` 兼容映射，不影响旧数据读取。
- 调整首页搜索文案与 README：搜索提示、功能说明和数据模型说明已同步更新为“书名、作者、译者或 ISBN”，并补充新增页草稿缓存的当前行为。
- 补充自动化测试：新增 `BookDraft` 映射单测、扩展导出包单测校验译者与 ISBN，并新增 UI 测试覆盖“误滑关闭新增页后恢复草稿”；同时修正旧删除流程 UI 测试在编辑页变长后的滚动查找。

### 验证记录

- `xcodebuild -project homeLibrary.xcodeproj -scheme homeLibrary -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:homeLibraryTests -only-testing:homeLibraryUITests test` 通过
- `homeLibraryTests.xctest` 共执行 `47` 个测试，其中 `1` 个 CloudKit live 测试按预期跳过，其余全部通过
- `homeLibraryUITests.xctest` 共执行 `8` 个测试，全部通过

## 2026-04-21（新增英文界面支持）

- 为应用新增中英文双语支持：首页、编辑页、仓库设置、同步状态、导入导出进度、错误提示等内置文案现在会跟随系统或应用当前语言切换。
- 调整默认地点初始化：新建书库时的默认地点名称会按当前语言生成；同时保留对历史中文地点名的兼容，并补上对英文默认地点名的归一化识别。
- 稳定测试环境语言：单元测试默认固定中文，新增英文输出单测；UI 测试显式注入中文语言环境，并把“下拉关闭新增页”改成更稳定的拖拽手势。
- 同步更新 `README.md`，补充当前双语界面行为，并更新最新测试数量。

### 验证记录

- `xcodebuild -project homeLibrary.xcodeproj -scheme homeLibrary -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:homeLibraryUITests/homeLibraryUITests/testCreateBookDraftRestoresAfterSwipeDismiss test` 通过
- `xcodebuild -project homeLibrary.xcodeproj -scheme homeLibrary -destination 'platform=iOS Simulator,name=iPhone 17' test` 通过
- `homeLibraryTests.xctest` 共执行 `48` 个测试，其中 `1` 个 CloudKit live 测试按预期跳过，其余全部通过
- `homeLibraryUITests.xctest` 共执行 `8` 个测试，全部通过

## 2026-04-21（新增 MIT 开源许可证）

- 新增根目录 `LICENSE`，采用标准 `MIT License`，允许任何人自由使用、修改、分发和商用本项目。
- 在 `README.md` 末尾追加“开源许可”章节，明确当前仓库的许可方式，以及商用和再分发时需保留版权声明与许可证全文。
- 本次只涉及许可证与文档说明，不改动应用代码、配置或测试入口。

### 验证记录

- `git status --short` 已确认改动范围仅包含 `LICENSE`、`README.md` 和 `log.md`

## 2026-04-24（CloudKit 增量刷新与测试补强）

- 修复 CloudKit 仓库刷新每次都全量扫描当前 zone 的问题：本地 cache manifest 现在会保存 `CKServerChangeToken`，首次刷新或 token 失效时才全量拉取，后续刷新改为携带 token 拉取增量变更。
- 新增增量变更合并路径：远端新增/修改的图书和地点会覆盖写入本地缓存，远端删除会移除本地记录，未变化内容不再被重新下载或重写。
- 保留本地写入后的旧 token：新增、编辑、删除、地点保存等本机操作不会清空 change token，下一次远端刷新会从旧 token 继续取得 CloudKit 回放结果并幂等合并。
- 补充测试覆盖：新增缓存层增量合并与 token 持久化测试，以及 `LibraryStore` 使用缓存 token 做增量刷新、不丢未变化数据的回归测试。
- 同步更新 `README.md` 和 `TEST.md`，补充当前增量同步链路和测试数量。

### 验证记录

- `xcodebuild -project homeLibrary.xcodeproj -scheme homeLibrary -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:homeLibraryTests test` 通过
  - `homeLibraryTests.xctest` 共执行 `50` 个测试，其中 `1` 个 CloudKit live 测试按预期跳过，其余全部通过
- `xcodebuild -project homeLibrary.xcodeproj -scheme homeLibrary -destination 'platform=iOS Simulator,name=iPhone 17' test` 通过
  - 单元测试执行 `50` 个，其中 `1` 个 CloudKit live 测试按预期跳过
  - UI 测试执行 `8` 个，全部通过

## 2026-05-04（启动优先恢复本地缓存）

- 调整 `LibraryStore.loadBooks` 的启动顺序：如果上次选中的仓库已有 `cloudkit-cache`，先恢复本地图书和地点，再刷新远端仓库列表与 CloudKit 数据，避免首页在同步返回前空白。
- 为缓存层新增只读取已存在快照的入口，避免为了探测缓存而创建新的空缓存目录。
- 补充回归测试：远端仓库列表请求被挂起时，验证 `LibraryStore` 已先展示当前仓库的缓存图书。
- 同步更新 `README.md` 和 `TEST.md`，说明启动缓存优先策略及测试数量变化。

### 验证记录

- `xcodebuild -project homeLibrary.xcodeproj -scheme homeLibrary -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:homeLibraryTests/homeLibraryTests/testStoreRestoresCachedBooksBeforeRemoteRepositoryListCompletes test` 通过
- `xcodebuild -project homeLibrary.xcodeproj -scheme homeLibrary -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:homeLibraryTests test` 通过
  - `homeLibraryTests.xctest` 共执行 `51` 个测试，其中 `1` 个 CloudKit live 测试按预期跳过，其余全部通过

## 2026-05-04（记录版本号位置）

- 记录应用版本号维护位置：用户可见版本号在 `homeLibrary.xcodeproj/project.pbxproj` 的 `homeLibrary` target Debug / Release 配置中，字段为 `MARKETING_VERSION`；构建号在同一位置，字段为 `CURRENT_PROJECT_VERSION`。
- 本次一并纳入当前工作区已有的版本号调整：`MARKETING_VERSION = 1.2.2`。

## 2026-06-22（AI 自动管理方案计划）

- 新增 `markdownNote/添加一个 AI 自动管理的功能/plan.md`，完整记录 AI 整理模式方案：以 iPhone app 作为 CloudKit 数据网关，Mac/Codex 通过局域网读取快照、生成结构化 patch，并由 app 预览确认后应用。
- 计划中明确 App Store 合规边界：不下载或执行外部代码、不开放无确认写库、本地网络会话需用户手动开启并使用一次性 token。
- 方案拆分为 AI patch 数据协议、局域网 API、iPhone 预览确认 UI、Codex skill、ZIP 导入闭环和测试验收等阶段。

### 验证记录

- 本次仅更新方案文档与变更记录，未改动应用代码。

## 2026-06-22（Mac App 导入 AI Patch 方案补记）

- 确认 `markdownNote/添加一个 AI 自动管理的功能/mac.md` 已写入完整 Mac App 导入 `.homelibpatch` 方案，作为替代 iPhone 本地 HTTP 接口的推荐方向。
- 该方案强调产品能力是本地文件导入与 CloudKit 写入，不在用户可见功能或审核说明中描述 Computer Use、本地 server 或 token。

### 验证记录

- 本次仅更新方案文档与变更记录，未改动应用代码。

## 2026-06-22（新增 Mac App 导入 AI Patch 方案）

- 新增 `markdownNote/添加一个 AI 自动管理的功能/mac.md`，记录更推荐的 Mac App 导入 `.homelibpatch` 方案：Codex 在本地生成 patch 文件，Mac App 通过标准文件导入 UI 校验并写入 CloudKit。
- 方案明确不在产品能力中暴露 Computer Use、本地 HTTP server 或 token；Computer Use 只作为用户本机自动化操作 Mac App 标准 UI 的方式。
- 补充 patch 文件格式、封面缩略图压缩约束、macOS target 拆分、文件类型注册、Apply 行为、审核说明、最小可交付范围和测试计划。

### 验证记录

- 本次仅更新方案文档与变更记录，未改动应用代码。

## 2026-06-22（AI 自动管理方案补充封面压缩要求）

- 更新 `markdownNote/添加一个 AI 自动管理的功能/plan.md`：第一版 AI patch 新增书籍必须携带封面缩略图，封面由 Codex 在 Mac 端下载、裁剪并大幅压缩后提交。
- 明确封面只作为 iOS 小略缩图使用：推荐 `160 x 240 px`、长边硬上限 `300 px`、目标不超过 `30 KB`、单张硬上限 `60 KB`，不传原始大图。
- 补充 `updateBookCover` 操作，用于给已有但缺封面的书籍补压缩封面；已有封面替换必须进入确认流程。
- 同步补充 snapshot、Codex skill、Store 应用规则、测试计划、风险缓解和第一版 MVP 范围中的封面压缩约束。

### 验证记录

- 本次仅更新方案文档与变更记录，未改动应用代码。

## 2026-06-22（AI 自动管理方案简化为 Codex 直接 apply）

- 更新 `markdownNote/添加一个 AI 自动管理的功能/plan.md`：AI 整理模式改为 Codex 专用本地控制接口，不再要求接口人类可读，也不在 iPhone app 内做 patch 预览、逐条勾选或二次确认。
- 局域网 API 改为 `GET /library/snapshot`、可选 `POST /patch/validate` 和直接写入的 `POST /patch/apply`，由 app 校验后通过现有 `LibraryStore.saveBook` 链路写入 CloudKit。
- 写入安全规则同步调整：保留一次性 token、短时前台会话、schema 校验、请求体限制、`expectedUpdatedAt` 冲突检测、非空字段默认不覆盖；必要覆盖改用 `replaceIfCurrentValue` 当前值校验。
- 产品和测试计划同步收敛：iPhone UI 只负责启动/停止会话、展示地址 token 与最近一次 apply 摘要；Codex skill 负责生成 patch、可选 validate、直接 apply 并输出结果摘要。

### 验证记录

- 本次仅更新方案文档与变更记录，未改动应用代码。

## 2026-06-22（Mac App 导入方案末尾补记）

- `markdownNote/添加一个 AI 自动管理的功能/mac.md` 已补充 Mac App 导入 `.homelibpatch` 的完整计划，作为替代 iPhone 本地 HTTP 接口的推荐实施方向。
- 本补记用于确保本次文档修改在 `log.md` 末尾也有追加记录；未删除或覆盖既有日志历史。

### 验证记录

- 本次仅更新方案文档与变更记录，未改动应用代码。

## 2026-06-22（Mac App 升级为完整 AI 工作流客户端）

- 重写 `markdownNote/添加一个 AI 自动管理的功能/mac.md`：从极小 patch 导入器升级为完整 Mac companion app 方案，覆盖书库浏览器、书籍编辑器、缺失项筛选、重复候选、AI 工作区、工作包导出和 patch apply。
- 明确 Mac App 是同一 CloudKit 书库的 macOS 客户端，而不是 iPhone app 的远程控制器；Codex 主要通过 `AIWorkspace.zip` 和 `.homelibpatch` 文件完成 workflow，Computer Use 只操作标准 Mac UI。
- 补充 CloudKit 原生同步与冲突处理：record zone change token、apply 前强制刷新、`ifServerRecordUnchanged` 保存策略、`serverRecordChanged` 冲突、共享权限、删除、地点失效、重复 ISBN 和幂等处理。
- 补充 Mac target 权限、签名、Production CloudKit 环境、测试计划和实施顺序。

### 验证记录

- 本次仅更新方案文档与变更记录，未改动应用代码。

## 2026-06-22（补充 Mac App CloudKit 测试计划与测试账号规则）

- 扩展 `markdownNote/添加一个 AI 自动管理的功能/mac.md` 的测试计划：拆分为不联网单测、memory remote 集成测试、CloudKit live preflight、CloudKit live 测试、冲突场景、macOS UI 测试和 Codex 自动化验收。
- 明确测试账号安全规则：`markdownNote/test` 只作为本地忽略文件，不读取、不打印、不写入日志、fixture、workspace 或提交内容；自动化测试不尝试自动登录 Apple ID。
- 补充测试数据隔离与清理策略：live test 使用 `AIWorkflowTest-*` 测试仓库，生成物默认写入已忽略的 `.derived/AIWorkflow/`，结束后清理 CloudKit 测试数据。
- 补充完整 CloudKit 能力验证范围：owner 仓库、增量 change token、iPhone 17 Pro 模拟器跨端可见性、`serverRecordChanged` 冲突、partial failure、权限失败、网络重试和重复 apply 幂等。

### 验证记录

- `git check-ignore -v markdownNote/test` 确认测试账号文件已被 `.gitignore` 忽略。
- 本次仅更新方案文档与变更记录，未改动应用代码。

## 2026-06-22（CloudKit CLI AI 工作流方案）

- 重写 `markdownNote/添加一个 AI 自动管理的功能/Cloudkit.md`：将方案收敛为 signed macOS Swift CLI `home-library-cloudkit`，通过原生 CloudKit framework 访问同一 iCloud container，不再需要 Mac UI 或 iPhone 本地接口。
- 明确可行性边界：CLI 必须带正确 Team、bundle identifier、CloudKit entitlement、container identifier 和 Production environment；Web Services / CloudKit JS 不作为 private/shared 书库主写入路径，`cktool` 只作为诊断和测试辅助。
- 补充 CLI 命令设计：`doctor`、`repos`、`snapshot`、`missing`、`duplicates`、`export-ai-workspace`、`validate-patch`、`apply-patch`，并规定 stdout 输出 JSON、stderr 输出进度、错误使用非 0 exit code。
- 补充 patch 格式、封面压缩、CloudKit 原生冲突处理、AI 工作流、测试账号安全、默认单测、memory remote、CloudKit live 和 Codex 验收计划。

### 验证记录

- 本次仅更新方案文档与变更记录，未改动应用代码。

## 2026-06-22（CloudKit CLI 最终产品计划：本地确认页与 Codex Skill）

- 再次重写 `markdownNote/添加一个 AI 自动管理的功能/Cloudkit.md`：最终方案明确为自研 signed Swift CLI + Codex Skill，Mac 与 iPhone 使用同一 iCloud 账号和同一 CloudKit container 时，CLI 写入会同步到 iPhone。
- 移除 Web Services / cktool 作为方案组成部分的叙述，产品边界收敛到 `home-library-cloudkit` 白名单 CLI 命令和 `home-library-curator` Codex Skill。
- 新增本地确认页设计：`review-patch` 只绑定 `127.0.0.1`，生成一次性 token 链接，在浏览器展示新增、修改、删除、封面和冲突项；用户 Approve 后 CLI 才执行高风险操作。
- 扩展 patch 操作到新增、更新字段、更新封面和软删除书籍；删除、替换非空字段、替换已有封面、大批量新增必须经过本地确认页批准。
- 补充 Codex Skill 的职责、规则、工作流、测试计划、Skill 交付文件和本地确认页测试要求。

### 验证记录

- 本次仅更新方案文档与变更记录，未改动应用代码。

## 2026-06-22（CloudKit CLI 封面实现对齐）

- 更新 `markdownNote/添加一个 AI 自动管理的功能/Cloudkit.md`：补充与当前 App 实现对齐的封面数据模型，明确书籍只保存 `coverAssetID`，CloudKit 使用 `coverAsset` / `CKAsset` 保存封面二进制，本地 cache 使用 `covers/<coverAssetID>.bin`。
- 修正封面压缩规则：CLI 必须复用 `LibraryCoverCompressor.compressIfNeeded`，按当前最长边 `720 px`、目标 `220 KB`、JPEG 质量阶梯 `0.82` 到 `0.42` 的实现处理候选封面，不再使用 `160 x 240 px` / `30 KB` 的独立规则。
- 补充 `coverAssetID` 生成和校验要求：基于最终写入数据 SHA-256 生成 `cover-<hex>`，patch 中的候选封面只作为输入，实际写入结果以 CLI 压缩后的数据为准。
- 新增 `removeBookCover` patch 操作，并修正删除书籍语义为按现有 App 删除 CloudKit `book.<id>` record；替换或移除已有封面必须经过本地确认页。
- 对齐当前 container、测试入口和冲突 metadata：使用 `iCloud.yu.homeLibrary`，CloudKit live 测试入口为 `HOME_LIBRARY_CLOUDKIT_LIVE_TESTS=1`，并注明 CLI 需要额外保留 `recordChangeTag` 或扩展 snapshot 类型。

### 验证记录

- 已检查 `homeLibrary/Book.swift`、`homeLibrary/LibraryStore.swift`、`homeLibrary/LibrarySync.swift`、`homeLibrary/LibraryPersistence.swift`、`homeLibrary/LibraryCoverCompression.swift` 以及相关测试，确认封面存储、压缩、导入导出和删除语义。
- `rg` 确认 `Cloudkit.md` 中不再残留旧的 `160 x 240 px`、`30 KB`、`60 KB`、`compressedThumbnail` 等封面规则；“软删除”仅保留在说明现有删除不是软删除的语句中。
- 未读取 `markdownNote/test`；本次仅更新方案文档与变更记录，未改动应用代码。

## 2026-06-22（CloudKit CLI 改为真实 iCloud 账号测试）

- 更新 `markdownNote/添加一个 AI 自动管理的功能/Cloudkit.md`：CloudKit live 测试不再要求配置单独测试 Apple ID，改为使用当前 Mac 系统已登录的真实 iCloud 账号。
- 明确 iPhone 或 `iPhone 17 Pro` 模拟器需要登录同一个真实 iCloud 账号，才能验证 CLI 写入后的跨端同步。
- 调整开源安全规则：不提交 Apple ID、邮箱、密码、验证码、恢复密钥或账号说明；`markdownNote/test` 只作为遗留本机说明文件处理，如果存在仍必须 git ignored，且 Skill / CLI / 测试都不读取。
- 保留数据隔离和风险边界：live test 默认使用 `AIWorkflowTest-*` 独立测试仓库；对真实主书库执行修改前必须先导出 workspace / backup，并通过 `review-patch` 确认高风险操作。

### 验证记录

- 本次仅更新方案文档与变更记录，未改动应用代码。
- 未读取 `markdownNote/test`。

## 2026-06-22（补充无人值守 Goal 模式目标）

- 新增 `markdownNote/添加一个 AI 自动管理的功能/goal.md` 的完整目标说明，用于启动 Goal mode 后无人值守开发 `home-library-cloudkit` CLI 和 `home-library-curator` Codex Skill。
- 根据 OpenAI Codex manual 中 Goal mode、prompting、approval / sandbox、non-interactive mode、auto-review 等建议，明确 goal 文本需要可判定完成标准，长说明放入文件，并要求运行期间不等待人工确认。
- 将人工确认路径改为自动化工程路径：review page 通过 loopback HTTP test client 或测试用 `ReviewDecision.json` 覆盖，CloudKit live 测试使用 `AIWorkflowTest-*` 独立仓库，主书库高风险操作仍需导出和确认机制保护。
- 补充无人值守完成标准：CLI 构建、命令 JSON 输出、workspace export、patch validate/apply、封面管理、review server、memory tests、CloudKit live tests、iPhone / 模拟器同步验证、Skill 交付、README 和日志更新、安全检查全部完成后才能结束 goal。

### 验证记录

- 已通过 OpenAI Codex manual 本地缓存读取 Goal mode、approval / sandbox、non-interactive mode 和 auto-review 相关段落。
- 本次仅更新方案文档与变更记录，未改动应用代码。
- 未读取 `markdownNote/test`。

## 2026-06-22（实现 home-library-cloudkit CLI 与 home-library-curator Skill）

- 新增 SwiftPM CLI 产品 `home-library-cloudkit`：支持 `doctor`、`repos`、`export-ai-workspace`、`validate-patch`、`review-patch`、`apply-patch`，stdout 输出 JSON，默认工作产物写入 `.derived/AIWorkflow/`。
- 新增 CLI domain / remote / patch / review / workspace 层：实现与当前 App 对齐的 `Book`、`BookPayload`、`LibraryLocation`、`LibraryRepositoryReference`、CloudKit record type / field / record name、`coverAssetID = cover-<sha256>`、最长边 `720 px` / 目标 `220 KB` 封面压缩、`coverAsset` / `CKAsset` 写入、删除 `book.<id>` record 语义。
- 新增 `.homelibpatch` schema：覆盖 `createBook`、`updateBook`、`updateBookCover`、`removeBookCover`、`deleteBook`，支持 `fillIfEmpty`、`replaceIfCurrentValue`、`expectedUpdatedAt`、`expectedRecordChangeTag`、`expectedCurrentCoverAssetID`、重复 ISBN、相似标题、封面 payload 校验、partial result、conflict / skipped / failed 分类。
- 新增 memory remote 与 apply 流程：默认测试不访问 CloudKit，覆盖 create / update / update cover / remove cover / delete / conflict / repeated apply。
- 新增本地 review server：只绑定 `127.0.0.1`，使用一次性 token，支持 GET review page / raw JSON、POST approve / reject、timeout rejected，并写入 `ReviewDecision.json`。
- 新增 AI workspace export：生成 `manifest.json`、`LibrarySnapshot.json`、`MissingMetadataReport.json`、`DuplicateCandidates.json`、`CoverStatus.json`、`Locations.json`、`PatchSchema.json`、`README.md`、`LibraryImport.json`。
- 新增 `scripts/build_home_library_cloudkit.sh`：默认构建可本地测试的 ad-hoc CLI；设置 `HOME_LIBRARY_CODESIGN_IDENTITY` 时用 `home-library-cloudkit/home-library-cloudkit.entitlements` 签 CloudKit entitlement。
- 新增 Codex Skill `skills/home-library-curator/SKILL.md`：固定通过 CLI 执行 doctor / repos / export / validate / review / apply，明确不读取 `markdownNote/test`、不直接改 CloudKit 或 cache、不绕过 validator，高风险操作必须 review。
- 更新 `README.md`：补充 CLI 命令、AI workspace、patch 操作、Skill、默认 memory 测试入口、真实 CloudKit 签名和 live 验收限制。
- 更新 `.gitignore`：忽略 SwiftPM `.build` 产物，继续保持 `.derived` 与 `markdownNote/test` 忽略。

### 验证记录

- `swift build --product home-library-cloudkit` 通过。
- `swift test` 通过：`HomeLibraryCloudKitTests` 共 `9` 个测试全部通过。
- `scripts/build_home_library_cloudkit.sh` 通过，生成 `.build/debug/home-library-cloudkit`。
- `.build/debug/home-library-cloudkit doctor --remote memory` 通过，确认 `.derived` 和 `markdownNote/test` 均被 git ignored。
- `.build/debug/home-library-cloudkit repos --remote memory` 通过，输出 memory 测试仓库 JSON。
- `.build/debug/home-library-cloudkit export-ai-workspace --remote memory --repo memory --output .derived/AIWorkflow/CommandWorkspace` 通过。
- `.build/debug/home-library-cloudkit validate-patch .derived/AIWorkflow/command-smoke.homelibpatch --snapshot .derived/AIWorkflow/CommandWorkspace/LibrarySnapshot.json --result .derived/AIWorkflow/CommandValidation.json` 通过。
- `.build/debug/home-library-cloudkit review-patch .derived/AIWorkflow/command-smoke.homelibpatch --snapshot .derived/AIWorkflow/CommandWorkspace/LibrarySnapshot.json --result .derived/AIWorkflow/CommandReviewDecision.json --auto-approve-test-only --remote memory` 通过。
- `.build/debug/home-library-cloudkit apply-patch .derived/AIWorkflow/command-smoke.homelibpatch --remote memory --review-decision .derived/AIWorkflow/CommandReviewDecision.json --result .derived/AIWorkflow/CommandApplyResult.json` 通过。
- `security find-identity -v -p codesigning` 找到可用的 Apple Development signing identity，但用该 identity 签 CloudKit entitlement 后，在当前 Codex 桌面宿主里执行真实 `doctor` 被 AppleSystemPolicy kill（exit `137`）；`codesign --verify --deep --strict --verbose=4` 和 `spctl --assess --type execute --verbose=4` 均通过静态校验。真实 CloudKit live apply 与 iPhone / 模拟器同步验证因此未能在当前宿主环境完成。
- 未读取 `markdownNote/test`；真实 workspace、patch、review decision 和 apply result 均生成在已忽略的 `.derived/AIWorkflow/`。

## 2026-06-22（补强 CLI command 测试与 live workflow 入口）

- 收紧 `updateBookCover` 校验规则：已有封面时，patch 如果没有提供 `expectedCurrentCoverAssetID`，现在会跳过而不是进入替换流程；提供但不匹配时返回 conflict，提供且匹配时才允许经 review 替换。
- 新增黑盒 CLI command 测试：直接运行已构建的 `.build/debug/home-library-cloudkit`，覆盖 stdout JSON、stderr progress、非 0 exit code、`--result` 写文件、默认 `.derived/AIWorkflow/` 输出路径、invalid patch 拦截，以及缺少 review decision 时拒绝高风险删除。
- 新增受保护命令 `run-live-test`：真实 CloudKit 路径要求 `HOME_LIBRARY_CLOUDKIT_LIVE_TESTS=1`，memory 路径可无人值守覆盖完整 live workflow 等价流程。
- `run-live-test --remote memory` 现在自动创建测试仓库、保存新增地点、创建带封面的书、更新字段、替换封面、验证旧 patch conflict、移除封面、导出 workspace、删除书籍并清理测试仓库。
- 更新 `README.md`：补充 `run-live-test` 命令、CLI command 测试范围、SwiftPM 测试数量和当前真实 CloudKit 签名阻塞说明。

### 验证记录

- `swift test` 通过：SwiftPM 测试共 `10` 项全部通过。
- `scripts/build_home_library_cloudkit.sh` 通过，生成 ad-hoc signed 本地测试 CLI。
- `.build/debug/home-library-cloudkit run-live-test --remote memory --result .derived/AIWorkflow/MemoryLiveResult.json` 通过，所有 workflow step 均为 `ok: true`，并完成 memory 测试仓库 cleanup。
- `HOME_LIBRARY_CODESIGN_IDENTITY='<Apple Development signing identity>' scripts/build_home_library_cloudkit.sh && HOME_LIBRARY_CLOUDKIT_LIVE_TESTS=1 HOME_LIBRARY_CLOUDKIT_CONTAINER=iCloud.yu.homeLibrary HOME_LIBRARY_TEST_REPOSITORY_PREFIX=AIWorkflowTest .build/debug/home-library-cloudkit run-live-test --result .derived/AIWorkflow/CloudKitLiveResult.json` 仍在当前 Codex 桌面宿主里被系统 kill，exit `137`，未进入 CLI 逻辑。
- 随后重新运行 `scripts/build_home_library_cloudkit.sh` 将本地测试 CLI 签回普通 ad-hoc；`codesign --verify --deep --strict --verbose=2 .build/debug/home-library-cloudkit` 通过，`.build/debug/home-library-cloudkit doctor --remote memory` 通过。
- 未读取 `markdownNote/test`；`.derived/AIWorkflow/MemoryLiveResult.json` 以及真实 live 尝试的结果路径均在已忽略目录下。

## 2026-06-22（确认 CloudKit CLI 签名阻塞边界）

- 继续排查真实 CloudKit live 入口失败原因：本机 Xcode profile 目录存在 provisioning profile，但均为 iOS / visionOS 平台，且只匹配现有 App ID `8VG8636JLY.yu.homeLibrary`。
- 未发现 macOS 平台 profile，也未发现 `8VG8636JLY.yu.homeLibrary.cloudkit-cli` 对应的 profile；因此带 iCloud restricted entitlement 的 `home-library-cloudkit` 在当前宿主上无法通过 AMFI / AppleSystemPolicy 运行真实 CloudKit 路径。
- 更新 `README.md`：补充真实 CloudKit live 测试的明确解锁条件，需要安装匹配 CLI bundle identifier 与 `iCloud.yu.homeLibrary` container 的 macOS development provisioning profile，或在已具备该 profile 的宿主环境继续。
- 未读取 `markdownNote/test`；本次排查未提交任何真实账号、snapshot、patch、token 或 Apple ID 信息。

## 2026-06-22（脱敏 CLI 签名示例与日志）

- 将 `skills/home-library-curator/SKILL.md` 中的真实 signing identity 示例改为占位符，避免把本机账号相关字符串写入仓库。
- 将本次新增 `log.md` 验证记录中的 signing identity 文本同步改为通用占位符，只保留诊断结论和可复现命令结构。
- 重新运行 `scripts/build_home_library_cloudkit.sh`，确认生成 ad-hoc signed 本地测试 CLI。
- 重新运行 `.build/debug/home-library-cloudkit run-live-test --remote memory --result .derived/AIWorkflow/MemoryLiveResult.json`，完整 memory workflow 通过并完成 cleanup。
- `codesign --verify --deep --strict --verbose=2 .build/debug/home-library-cloudkit` 通过。
- 未读取 `markdownNote/test`；未提交真实账号、snapshot、patch、token 或 Apple ID 信息。

## 2026-06-22（补强 doctor 签名与 provisioning 诊断）

- 扩展 `home-library-cloudkit doctor` JSON 输出：新增结构化 `codesign` 与 `provisioningProfiles` 诊断，报告当前 executable 的 CloudKit entitlement、container entitlement、目标 application identifier、已搜索 profile 目录、profile 总数、container 匹配数、macOS 平台匹配数和 ready profile 匹配数。
- `doctor --remote memory` 仍保持可用于默认测试，不访问 CloudKit；真实 CloudKit 模式的 `ok` 现在要求账号可用、CloudKit entitlement、目标 container entitlement 与匹配 macOS provisioning profile 都满足。
- 更新 CLI command 测试：黑盒检查 `doctor` 输出包含 codesign / provisioning JSON 结构和 `iCloud.yu.homeLibrary` 目标 container。
- 更新 `README.md`：记录 `doctor` 的签名和 provisioning profile 诊断能力。
- 验证：`swift build --product home-library-cloudkit` 通过；`swift test` 通过，SwiftPM 测试共 `10` 项全部通过。
- 未读取 `markdownNote/test`；未提交真实账号、snapshot、patch、token 或 Apple ID 信息。

## 2026-06-22（补充 Skill workflow 自动化测试）

- 新增 `SkillWorkflowTests`：读取 `skills/home-library-curator/SKILL.md`，校验 Skill 文档包含 `doctor`、`repos`、`export-ai-workspace`、`validate-patch`、`review-patch`、`apply-patch` 标准 CLI workflow。
- 同一测试覆盖 Skill 安全规则：禁止读取 `markdownNote/test`、禁止直接改 `cloudkit-cache`、禁止直接调用 CloudKit、禁止绕过 validator、高风险操作必须 review、test-only auto approval 只允许 memory 或 `AIWorkflowTest-*`。
- 更新 `README.md`：SwiftPM 测试数量从 `10` 增至 `11`，仓库总 XCTest / SwiftPM XCTest 数量从 `69` 增至 `70`。
- 验证：`swift test` 通过，SwiftPM 测试共 `11` 项全部通过。
- 未读取 `markdownNote/test`；未提交真实账号、snapshot、patch、token 或 Apple ID 信息。

## 2026-06-22（补齐 retryableFailed 分类）

- 调整 `LibraryAIPatchApplier`：对 CloudKit 的 `networkUnavailable`、`networkFailure`、`serviceUnavailable`、`requestRateLimited`、`zoneBusy`、`limitExceeded`、`serverResponseLost`、`operationCancelled` 等临时错误返回 `retryableFailed`，并在 per-operation result 中设置 `retryable: true`。
- 新增 `testRetryableCloudKitFailureClassification`：用测试 remote 抛出 `CKError(.networkUnavailable)`，验证 apply result 的 `failedCount == 0`、`retryableFailedCount == 1`、operation status 为 `retryableFailed`。
- 更新 `README.md`：SwiftPM 测试数量从 `11` 增至 `12`，仓库总 XCTest / SwiftPM XCTest 数量从 `70` 增至 `71`，补充 retryable apply result 覆盖。
- 验证：`swift test` 通过，SwiftPM 测试共 `12` 项全部通过。
- 未读取 `markdownNote/test`；未提交真实账号、snapshot、patch、token 或 Apple ID 信息。

## 2026-06-22（补强 ReviewDecision 写入时机）

- 调整 `PatchReviewServer.complete`：approve / reject / timeout 完成路径会立即写入 `ReviewDecision.json`，`review-patch` 的 `run()` 路径仍保留最终写入，确保测试 server 与产品 server 都能证明 POST 后决策文件落盘。
- 扩展 review server 测试：POST approve 后读取 `ReviewDecision.json`，校验 `approved` 与 `patchDigest`。
- 更新 `README.md`：补充 review server approve / reject 会写入 `ReviewDecision.json` 的测试覆盖。
- 验证：`swift test` 通过，SwiftPM 测试共 `11` 项全部通过。
- 未读取 `markdownNote/test`；未提交真实账号、snapshot、patch、token 或 Apple ID 信息。

## 2026-06-22（修复 ad-hoc doctor 诊断路径）

- 调整 `home-library-cloudkit doctor` 执行顺序：先读取 codesign entitlement 与本地 provisioning profile 诊断，再决定是否调用 CloudKit account status。
- 对缺少 CloudKit entitlement 的 ad-hoc executable，`doctor` 现在返回 JSON：`ok: false`、`accountStatus: notCheckedMissingEntitlements`，并输出缺 entitlement / 缺 profile 的 warnings；不再在真实模式下直接触发 CloudKit 运行期 abort。
- 扩展 CLI command 测试：覆盖不带 `--remote memory` 的 `doctor`，确认缺 entitlement 时仍以 exit `0` 输出结构化失败诊断。
- 更新 `README.md`：补充 ad-hoc executable 真实模式缺 entitlement 时仍返回 JSON 的测试覆盖。
- 验证：`swift build --product home-library-cloudkit` 通过；`.build/debug/home-library-cloudkit doctor` 输出结构化失败诊断；`swift test` 通过，SwiftPM 测试共 `11` 项全部通过。
- 未读取 `markdownNote/test`；未提交真实账号、snapshot、patch、token 或 Apple ID 信息。

## 2026-06-22（修正 AIWorkspace.zip 根目录结构）

- 调整 `AIWorkspaceExporter` 的 zip 生成方式：`.zip` 输出不再保留临时随机父目录，解包后 `manifest.json`、`LibrarySnapshot.json`、`PatchSchema.json` 等必需文件直接位于工作包根目录，符合 `AIWorkspace.zip` 作为工作包的使用预期。
- 同步更新 workspace export 测试：解包后直接检查 zip 根目录中的全部必需文件。
- 验证：`swift test` 通过，SwiftPM 测试共 `11` 项全部通过。
- 未读取 `markdownNote/test`；未提交真实账号、snapshot、patch、token 或 Apple ID 信息。

## 2026-06-22（补强 workspace zip 与 live gate 测试）

- 扩展 workspace export 测试：除目录输出外，新增 `.zip` 输出校验，使用 `ditto -x -k` 解包后确认 `manifest.json`、`LibrarySnapshot.json`、`MissingMetadataReport.json`、`DuplicateCandidates.json`、`CoverStatus.json`、`Locations.json`、`PatchSchema.json`、`README.md`、`LibraryImport.json` 均存在。
- 扩展 CLI command 测试：强制移除测试进程里的 `HOME_LIBRARY_CLOUDKIT_LIVE_TESTS`，确认不带 `--remote memory` 的 `run-live-test` 会以 exit `2` 拒绝执行并提示需要显式 live test 环境变量，避免默认路径误触真实 CloudKit。
- 更新 `README.md`：补充 workspace zip 内容验证与 CloudKit live test 环境门禁覆盖。
- 验证：`swift test` 通过，SwiftPM 测试共 `11` 项全部通过。
- 未读取 `markdownNote/test`；未提交真实账号、snapshot、patch、token 或 Apple ID 信息。

## 2026-06-22（补强 review server 页面测试）

- 扩展 `HomeLibraryCloudKitTests.testReviewServerApproveRejectWrongTokenAndTimeout`：新增 `/raw.json` GET 校验，确认 review server 可返回原始 patch JSON。
- 同一测试新增 destructive review 页面覆盖：构造替换非空字段、替换已有封面和删除书籍的 patch，校验 HTML 包含 danger zone、更新 / 封面 / 删除计数、old -> new 提示以及对应风险文案。
- 验证：`swift test` 通过，SwiftPM 测试共 `11` 项全部通过。
- 未读取 `markdownNote/test`；未提交真实账号、snapshot、patch、token 或 Apple ID 信息。

## 2026-06-22（补强 CLI CloudKit 增量刷新缓存）

- 调整 `CloudKitLibraryRemote.refreshRepository`：按 database scope、zone owner 和 zone name 缓存上一次 `RemoteRepositorySnapshot` 与 `CKServerChangeToken`，后续真实 CloudKit 刷新会携带 token 拉取增量。
- 新增增量合并路径：当 CloudKit 返回新增或修改的 location / book record 时覆盖缓存快照，返回删除记录时从缓存快照移除对应地点或图书；token 失效时仍回退完整刷新。
- 更新 `README.md`：补充 AI 工作流 CLI 真实远端刷新会缓存 zone change token 并合并增量。
- 验证：`swift test` 通过，SwiftPM 测试共 `12` 项全部通过。
- 未读取 `markdownNote/test`；未提交真实账号、snapshot、patch、token 或 Apple ID 信息。

## 2026-06-22（AI 工作流 CLI 本地验收）

- 重新运行 `scripts/build_home_library_cloudkit.sh`，确认 `home-library-cloudkit` 可构建；当前未设置 `HOME_LIBRARY_CODESIGN_IDENTITY`，因此仍是 ad-hoc 签名且不具备 CloudKit entitlement。
- 运行 `.build/debug/home-library-cloudkit doctor`，确认真实 CloudKit 模式会输出结构化签名 / provisioning 失败诊断，而不是直接触发 CloudKit 运行期失败。
- 运行 `.build/debug/home-library-cloudkit doctor --remote memory`，确认 memory 模式本地诊断通过。
- 运行 `.build/debug/home-library-cloudkit run-live-test --remote memory --result .derived/AIWorkflow/MemoryLiveResult.json`，完整 memory workflow 通过并完成 cleanup。
- 运行 `git diff --check`、敏感字符串扫描与 `git check-ignore`，确认 diff 无空白错误、未命中账号 / token / 私钥模式，且 `.derived`、`.build`、`markdownNote/test` 和 live result 文件均被忽略。
- 未读取 `markdownNote/test`；未提交真实账号、snapshot、patch、token 或 Apple ID 信息。

## 2026-06-22（补强真实 CloudKit 错误分类与命令级 review 测试）

- 为 `CLIError` 增加错误类别，保留真实 CloudKit remote 映射后的临时错误与服务端记录冲突语义，避免 apply 层只能识别原始 `CKError`。
- `LibraryAIPatchApplier` 现在会把映射后的 CloudKit 临时错误归类为 `retryableFailed`，把映射后的 `serverRecordChanged` 归类为 `conflict`；直接抛出的 `CKError.serverRecordChanged` 也会归类为 `conflict`。
- `CloudKitLibraryRemote.upsertBook` 的单条 book 保存改用 `ifServerRecordUnchanged` save policy，让真实 CloudKit 更新更接近 expected metadata 冲突保护语义。
- 扩展 CLI command 测试：覆盖 `review-patch --auto-approve-test-only --remote memory` 写入 `ReviewDecision.json`。
- 更新 `README.md`：补充真实 CloudKit 映射错误分类和 test-only auto review 的测试覆盖。
- 验证：`swift test` 通过，SwiftPM 测试共 `12` 项全部通过。
- 未读取 `markdownNote/test`；未提交真实账号、snapshot、patch、token 或 Apple ID 信息。

## 2026-06-22（清理 Skill 签名占位符并复验）

- 将 `skills/home-library-curator/SKILL.md` 中的 signing identity 示例进一步收敛为通用占位符，避免敏感信息扫描把示例格式误判为真实签名身份。
- 重新运行 `swift test`，SwiftPM 测试共 `12` 项全部通过。
- 重新运行真实模式 `doctor`、`doctor --remote memory`、`repos --remote memory` 和 `run-live-test --remote memory`；真实模式仍仅缺 CloudKit entitlement / macOS provisioning profile，memory workflow 通过并完成 cleanup。
- 未读取 `markdownNote/test`；未提交真实账号、snapshot、patch、token 或 Apple ID 信息。

## 2026-06-22（修正签名构建为 embedded profile app wrapper）

- 扩展 `doctor` 的 provisioning profile 识别：同时枚举 `.mobileprovision` 和 `.provisionprofile`，并兼容 `com.apple.application-identifier` 与 profile 中通配形式的 iCloud services entitlement。
- 调整 `scripts/build_home_library_cloudkit.sh`：设置 `HOME_LIBRARY_CODESIGN_IDENTITY` 时先查找同时匹配 `8VG8636JLY.yu.homeLibrary.cloudkit-cli` 与 `iCloud.yu.homeLibrary` 的 macOS profile；匹配成功后生成 `.build/<configuration>/home-library-cloudkit.app`，嵌入 profile，并使用 profile 原始 entitlements 签名 wrapper 内 CLI。
- 签名模式找不到匹配 profile 时会在构建阶段明确失败，不再生成会被 AMFI / AppleSystemPolicy kill 的裸 executable。
- 当前本机诊断结果：profile 总数 `5`，macOS profile 匹配数 `1`，但 matching application identifier 为 `0`、ready profile 为 `0`；因此用户新安装的 profile 仍不是目标 CLI + target container 组合，真实 CloudKit live test 和 iPhone / 模拟器同步验证未能继续。
- 更新 `README.md` 和 `skills/home-library-curator/SKILL.md`：记录真实 CloudKit 签名模式应使用构建脚本 stdout 返回的 wrapper 内 executable 路径。
- 验证：`bash -n scripts/build_home_library_cloudkit.sh` 通过；`swift test` 通过，SwiftPM 测试共 `12` 项全部通过；默认 ad-hoc 构建通过；签名构建在缺匹配 profile 时按预期失败并输出明确错误；`run-live-test --remote memory` 通过并完成 cleanup。
- 未读取 `markdownNote/test`；未提交真实账号、snapshot、patch、token 或 Apple ID 信息。

## 2026-06-22（Goal 续跑签名阻塞复核）

- 重新读取 `goal.md` 并复查当前工作树，确认剩余未完成验收项仍是真实 CloudKit live test 与 iPhone / 模拟器同步验证。
- 运行 `.build/debug/home-library-cloudkit doctor`，当前诊断仍为 `profileCount = 5`、`matchingMacOSPlatformCount = 1`、`matchingApplicationIdentifierCount = 0`、`matchingReadyProfileCount = 0`，即本机已有 macOS profile，但没有匹配目标 CLI application identifier 与 `iCloud.yu.homeLibrary` container 的 ready profile。
- 运行签名构建：`HOME_LIBRARY_CODESIGN_IDENTITY=<identity hash> scripts/build_home_library_cloudkit.sh` 按预期在构建阶段失败，错误明确指出缺少 `8VG8636JLY.yu.homeLibrary.cloudkit-cli` + `iCloud.yu.homeLibrary` 的 macOS provisioning profile。
- 运行 `swift test`，SwiftPM 测试共 `12` 项全部通过。
- 结论：代码、默认测试、memory workflow、签名诊断和安全边界已推进到可自动验证范围；真实 CloudKit live test 与 iPhone / 模拟器同步验证仍被 Apple Developer provisioning 外部条件阻塞，剩余最小人工动作是安装匹配目标 App ID 和 container 的 macOS development provisioning profile。
- 未读取 `markdownNote/test`；未提交真实账号、snapshot、patch、token 或 Apple ID 信息。

## 2026-06-22（真实 CloudKit 与模拟器同步验收通过）

- 在本机安装匹配 `8VG8636JLY.yu.homeLibrary.cloudkit-cli` 与 `iCloud.yu.homeLibrary` 的 macOS provisioning profile 后，签名构建的 `home-library-cloudkit` 通过 `doctor`：CloudKit entitlement、container entitlement、ready profile 与 iCloud account status 均可用。
- 调整签名构建脚本：签名模式会生成 embedded profile app wrapper，并把 profile 中不适合 macOS CLI 运行时的 iCloud entitlement 规范化为 CloudKit 服务与目标 container，避免运行时被 entitlement 形态拒绝。
- 修正真实 CloudKit record name 前缀解析：只移除一次 `location.` / `book.` 前缀，避免 `location.location.aiworkflow` 被错误还原为 `aiworkflow`；新增对应 SwiftPM 单测。
- 为 iOS app 增加自动化命令 `verify-repository-book`，可在指定仓库中刷新 CloudKit 并确认 app 侧读取到指定测试书籍。
- 扩展真实 `run-live-test`：设置 `HOME_LIBRARY_TEST_SIMULATOR_NAME` 时，会构建并安装 iOS app 到 booted 模拟器，在 CLI 写入测试书后执行 app 侧同步可见性验证，然后继续封面替换、冲突、移除封面、workspace export、删除书籍和清理测试仓库。
- 更新 `README.md` 与 `skills/home-library-curator/SKILL.md`：记录真实 CloudKit live test 的签名 CLI、模拟器验证环境变量与当前测试覆盖状态。
- 验证：`swift test` 通过，SwiftPM 测试共 `13` 项全部通过；`bash -n scripts/build_home_library_cloudkit.sh` 通过；XcodeBuildMCP `build_run_sim` 在 `iPhone 17 Pro` 模拟器上通过；签名 `doctor` 通过；真实 `run-live-test` 通过并包含 `verifySimulatorVisibility`，测试仓库已 cleanup。
- 未读取 `markdownNote/test`；真实 workspace、CloudKit live result 与模拟器自动化结果均留在已忽略的 `.derived/AIWorkflow/` 或模拟器 data container 中；未提交真实账号、snapshot、patch、token 或 Apple ID 信息。

## 2026-06-22（补充豆瓣补书 Agent 流程并实际新增《安德的游戏》）

- 更新 `AGENTS.md`：新增家庭书库 AI 管理流程，明确通过 ISBN 在豆瓣定位图书条目、将网页 / metadata / 封面 / patch / apply result 放入 `.derived/AIWorkflow/` 临时缓存、通过 `home-library-cloudkit` CLI validate / apply，并禁止提交真实账号、token、snapshot、patch 或封面缓存。
- 使用豆瓣 ISBN 搜索与条目页 `https://book.douban.com/subject/26767247/` 整理《安德的游戏》信息：作者 `[美] 奥森·斯科特·卡德`、译者 `李毅`、出版社 `浙江文艺出版社`、出版年 `2016-6`、ISBN `9787533944940`，并下载条目封面到已忽略缓存目录。
- 生成并验证 `createBook` patch：目标仓库为 `homeLibrary`，地点为 `location.chengdu`，验证结果 `acceptedCount = 1`、`needsReviewCount = 0`、`conflictCount = 0`、`failedCount = 0`。
- 应用 patch 到真实 CloudKit 仓库成功：新增书籍 ID `039c82ba-06b4-4146-825c-2c04dbe42758`，封面 asset ID `cover-2f0a647d21b8a2ee8de32167f4f576ae62779f6786569232fe37317243ed2ed0`。
- 复查 `repos` 显示 `homeLibrary` 书籍数为 `110`；重新导出的 workspace 中可检索到 ISBN `9787533944940` 与书名《安德的游戏》。
- 用户已在 `iPhone 17 Pro` 模拟器中刷新并确认新书可见；后续自动化轮询因此停止。
- 未读取 `markdownNote/test`；豆瓣缓存、workspace、patch、validation 和 apply result 均保留在已忽略的 `.derived/AIWorkflow/` 下，未提交真实账号、snapshot、patch、token 或 Apple ID 信息。

## 2026-06-22（修正 CLI CloudKit Production / Development 环境混用）

- 复核实体 iPhone 与 CLI 数据不一致问题：原签名 CLI entitlement 中包含 `com.apple.developer.icloud-container-development-container-identifiers = iCloud.yu.homeLibrary`，因此读写的是 CloudKit Development 环境；实体发布版 iPhone 使用的是 Production 环境。
- 调整 `scripts/build_home_library_cloudkit.sh`：签名构建默认使用 `HOME_LIBRARY_CLOUDKIT_ENVIRONMENT=production`，写入 `com.apple.developer.icloud-container-environment = Production`，并移除 development container entitlement；只有显式设置 `HOME_LIBRARY_CLOUDKIT_ENVIRONMENT=development` 时才保留 development container entitlement。
- 扩展 `home-library-cloudkit doctor`：输出 `iCloudContainerEnvironments`、`iCloudDevelopmentContainerIdentifiers`、`expectedICloudContainerEnvironment` 和 `hasExpectedCloudKitEnvironment`，并将真实模式 ok 条件收紧为必须匹配预期 CloudKit environment。
- 更新 `AGENTS.md`、`README.md` 与 `skills/home-library-curator/SKILL.md`：明确用户真实书库必须走 Production，Development 只用于显式隔离测试；签名 CLI wrapper 会原地重建，不要并行运行多个带签名身份的 CLI 构建 / 命令。
- 验证 Production 只读结果：`doctor` 显示 `environment = Production`、`iCloudContainerEnvironments = ["Production"]`、`iCloudDevelopmentContainerIdentifiers = []`；`repos` 显示实体 iPhone 对应仓库 `家藏万卷`，`bookCount = 117`、`locationCount = 2`，地点包含 `成都` 和 `重庆`。
- 将《安德的游戏》重新应用到 Production 仓库：Production validate 通过，`acceptedCount = 1`、`conflictCount = 0`、`failedCount = 0`；Production apply 成功，新增书籍 ID `d6d094ea-738a-4c71-abd3-20aba9d7b0b9`，封面 asset ID `cover-2f0a647d21b8a2ee8de32167f4f576ae62779f6786569232fe37317243ed2ed0`。
- 复查 Production `repos` 显示 `bookCount = 118`；重新导出的 Production workspace 可检索到 ISBN `9787533944940`、书名《安德的游戏》和书籍 ID `d6d094ea-738a-4c71-abd3-20aba9d7b0b9`。
- Development 环境中此前误加的一份《安德的游戏》未删除，避免未经明确确认执行删除操作；该记录不影响实体发布版 iPhone 的 Production 数据。
- 验证：`bash -n scripts/build_home_library_cloudkit.sh` 通过；`swift test` 通过，SwiftPM 测试共 `13` 项全部通过；Production signed `doctor` 与 `repos` 通过。
- 未读取 `markdownNote/test`；Production / Development workspace、patch、validation、apply result 和豆瓣缓存均保留在已忽略的 `.derived/AIWorkflow/` 下，未提交真实账号、snapshot、patch、token 或 Apple ID 信息。

## 2026-06-22（批量从豆瓣 ISBN 新增 9 本书到 Production 成都）

- 按用户提供的 9 个 ISBN，从豆瓣 ISBN 搜索与豆瓣条目页缓存 metadata 和封面到 `.derived/AIWorkflow/douban-batch-*` 临时目录。
- 目标仓库为 Production `家藏万卷`，地点统一为 `成都`（`locationID = chengdu`）；执行前 `repos` 显示 `bookCount = 118`、`locationCount = 2`。
- 当前 Production 快照查重确认 9 个 ISBN 均不存在。
- 生成批量 `createBook` patch 并验证通过：`acceptedCount = 9`、`needsReviewCount = 0`、`conflictCount = 0`、`failedCount = 0`。
- 应用 patch 到 Production 成功：`appliedCount = 9`、`conflictCount = 0`、`failedCount = 0`、`retryableFailedCount = 0`。
- 新增书籍：
  - `9787100013239`：《哥德尔、艾舍尔、巴赫》
  - `9787573922274`：《哈萨比斯：谷歌AI之脑》
  - `9787522333977`：《奇点更近》
  - `9787115644053`：《理解图灵》
  - `9787521770162`：《英伟达之道》
  - `9787521777680`：《AI文明史·前史》
  - `9787513361606`：《人比AI凶》
  - `9787500181699`：《智能简史》
  - `9787521765502`：《教育新语》
- 复查 Production `repos` 显示 `bookCount = 127`；重新导出的 Production workspace 可检索到上述 9 个 ISBN 和对应书籍 ID。
- `9787521765502` 的豆瓣搜索页因限频未返回条目列表，改用公开搜索结果定位豆瓣 subject `36873315` 后缓存条目页。
- 未读取 `markdownNote/test`；豆瓣页面、封面、workspace、patch、validation 和 apply result 均保留在已忽略的 `.derived/AIWorkflow/` 下，未提交真实账号、snapshot、patch、token 或 Apple ID 信息。

## 2026-06-22（README 补充 AI 辅助补书能力）

- 更新 `README.md` 的产品说明：当前版本已包含 AI 辅助补书能力，用户给出书名或 ISBN 后，AI 可以读取 Production 书库快照、从豆瓣搜索和条目页整理作者 / 译者 / 出版社 / 出版年 / ISBN / 封面，并通过结构化 patch 加入当前书库。
- 在用户接口章节新增 `AI 辅助补书` 小节，说明 `.derived/AIWorkflow/` 临时缓存、`.homelibpatch`、`validate-patch`、签名 `home-library-cloudkit` CLI、Production CloudKit 写入和写入后复查的边界。
- 调整“明确不做”的表述：仍不做扫码录入或无边界抓取电商资料，但允许在用户明确给出书名或 ISBN 后执行可校验的 AI 补全流程。
- 本次仅更新 README 和日志，未读取 `markdownNote/test`，未提交真实账号、snapshot、patch、token 或 Apple ID 信息。
- 同步修正 README 开头的当前版本聚焦数量，使 AI 辅助补书进入概述后文案保持一致。
