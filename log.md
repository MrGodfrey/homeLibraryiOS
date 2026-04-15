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
