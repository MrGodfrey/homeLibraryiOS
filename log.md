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
