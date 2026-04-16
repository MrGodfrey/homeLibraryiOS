# homeLibrary

`homeLibrary` 是一个面向 iPhone 的家庭书库应用。

它的核心目标不是“把书存进 CloudKit”这么简单，而是让一个家庭围绕同一套书库长期使用：主人维护仓库，家庭成员通过 iCloud 标准共享加入；首页专注浏览与查找；仓库设置页承接迁移、地点配置、清空、导出和共享管理。

## 0. 当前项目实际补充

下面的 `1` 到 `7` 节需求文档已经恢复保留。这一节只补当前代码已经落地的实现信息，方便把 README 和仓库现状对齐；如果和后文需求表述有细微出入，以当前代码实现为准。

### 0.1 当前已实现的功能

- 创建自有仓库，默认初始化 `成都`、`重庆` 两个地点
- 浏览当前仓库书籍，支持搜索、地点筛选、下拉刷新
- 在仓库设置里为当前仓库选择图书排序方式：按作者首字母、按标题首字母、按添加时间、按修改时间；默认按添加时间
- 新增、编辑、删除书籍
- 从相册选择或替换封面
- 在仓库设置里管理地点：新增、删除、拖拽排序、控制是否显示在首页筛选；修改后立即生效
- 查看并切换当前设备可访问的仓库
- owner 通过系统 `UICloudSharingController` 邀请家人加入
- member 通过系统回调或手动粘贴 iCloud 分享链接加入共享仓库
- 通过仓库设置页导入旧 JSON 包
- 导出当前仓库为 ZIP，包内只有一个 `LibraryImport.json`
- 清空当前仓库
- 本地缓存当前仓库快照和封面，并恢复上次选中的仓库

### 0.2 当前项目形态

- SwiftUI iOS 应用
- 目标设备：iPhone（`TARGETED_DEVICE_FAMILY = 1`）
- Deployment target：`iOS 26.4`
- Scheme：`homeLibrary`
- Bundle ID：`yu.homeLibrary`
- CloudKit container：`iCloud.yu.homeLibrary`

当前默认后端是 CloudKit；测试默认切到内存后端。

### 0.3 当前 UI 和数据模型补充

当前代码里，一个家庭书库对应一个 CloudKit 自定义 zone：

- owner 从 `privateCloudDatabase` 访问
- member 从 `sharedCloudDatabase` 访问
- zone 根记录类型：`LibraryRepository`
- 书籍记录类型：`LibraryBook`
- 地点记录类型：`LibraryLocation`

地点已经不是写死枚举。代码仍然保留 `成都` / `重庆` 作为默认地点，但每个仓库都可以独立修改地点列表和首页筛选可见性。

图书排序方式也是仓库级配置。当前支持：

- 按作者首字母排序
- 按标题首字母排序
- 按添加时间排序
- 按修改时间排序

其中作者和标题的排序会把中文转换为拼音后再与英文统一比较。

书籍当前 UI 可编辑的字段是：

- 书名
- 作者
- 出版社
- 出版年份
- 所在地点
- 封面

导入数据里的 `customFields` 仍会保留，搜索时也会参与匹配，但当前 UI 没有单独的自定义字段编辑入口。

### 0.4 本地运行

1. 用 Xcode 打开 [homeLibrary.xcodeproj](homeLibrary.xcodeproj)
2. 选择 `homeLibrary` scheme
3. 直接运行到 iPhone 模拟器或真机

如果只是想调 UI，不想依赖 iCloud / CloudKit，可以给运行 Scheme 加环境变量：

```text
HOME_LIBRARY_REMOTE_DRIVER=memory
```

这时仓库、图书和地点都走内存后端，分享相关能力不会启用。

### 0.5 常用环境变量

| 变量 | 作用 |
| --- | --- |
| `HOME_LIBRARY_REMOTE_DRIVER` | 后端实现，`cloudkit` 或 `memory` |
| `HOME_LIBRARY_STORAGE_ROOT` | 覆盖本地存储根目录 |
| `HOME_LIBRARY_STORAGE_NAMESPACE` | 隔离本地缓存命名空间 |
| `HOME_LIBRARY_SESSION_NAMESPACE` | 隔离当前仓库会话命名空间 |
| `HOME_LIBRARY_CLOUDKIT_CONTAINER` | 覆盖 CloudKit container |
| `HOME_LIBRARY_PREFERRED_REPOSITORY_NAME` | 创建 owner 仓库时的默认名称 |
| `HOME_LIBRARY_DEBUG_CLOUDKIT` | 输出更多 CloudKit 调试日志 |
| `HOME_LIBRARY_CLOUDKIT_LIVE_TESTS` | 显式开启真实 CloudKit 集成测试 |

测试运行器注入环境变量时，代码也兼容 `TEST_RUNNER_` 前缀。

### 0.6 导入与导出

仓库设置页当前通过文件选择器导入单个 `.json` 文件，兼容：

- 旧版 `books.json`
- `LibraryImport.json`
- `SeedBooks.json`
- 旧格式书籍数组 JSON

底层导入器还保留了对这些输入的兼容逻辑，主要用于测试和历史迁移：

- 结构化旧目录：`books/`、`covers/`、`deletions/`

导出入口在仓库设置页，输出为 ZIP 文件，压缩包里只有一个 `LibraryImport.json`。封面会内嵌在导出内容里。

### 0.7 测试入口

仓库当前包含三类测试：

- `homeLibraryTests/`：业务逻辑、配置切换、仓库流程、导入导出、持久化、排序和设置行为
- `homeLibraryUITests/`：最基本的建库、加书、搜索主流程，以及仓库设置页关键入口
- `homeLibraryTests/CloudKitLiveIntegrationTests.swift`：显式开启时运行的真实 CloudKit 集成测试

默认单测和 UI 测试都使用内存后端。直接在 Xcode 里跑 `Test` 即可。

命令行示例：

```bash
xcodebuild test \
  -project homeLibrary.xcodeproj \
  -scheme homeLibrary \
  -destination 'platform=iOS Simulator,name=iPhone 17'
```

如果要跑真实 CloudKit 集成测试，需要额外注入：

```text
HOME_LIBRARY_REMOTE_DRIVER=cloudkit
HOME_LIBRARY_CLOUDKIT_LIVE_TESTS=1
HOME_LIBRARY_STORAGE_NAMESPACE=cloudkit-live-tests
```

另外，仓库里还有一个双模拟器共享验证脚本：

- [scripts/run_dual_sim_cloudkit_share_test.swift](scripts/run_dual_sim_cloudkit_share_test.swift)

它用于验证 owner / member 两端的 CloudKit 共享、写入、同步和清理流程，不属于默认 XCTest 用例。

### 0.8 相关文件

- [homeLibrary/ContentView.swift](homeLibrary/ContentView.swift)：主界面
- [homeLibrary/RepositoryManagementView.swift](homeLibrary/RepositoryManagementView.swift)：仓库设置、地点管理、共享、导入导出
- [homeLibrary/LibraryStore.swift](homeLibrary/LibraryStore.swift)：状态管理和主要业务流程
- [homeLibrary/LibrarySync.swift](homeLibrary/LibrarySync.swift)：CloudKit / 内存后端
- [homeLibrary/LibraryPersistence.swift](homeLibrary/LibraryPersistence.swift)：缓存、导入器、ZIP 导出
- [TEST.md](TEST.md)：测试覆盖说明
- [scripts/import_from_cloudflare.mjs](scripts/import_from_cloudflare.mjs)：旧 Cloudflare 数据转换脚本

## 1. 设计方式

- 需求先于实现  
  先问这个应用要长期服务什么，再决定 CloudKit、缓存、页面结构和测试分层怎么写。

- 最简单可行架构  
  只保留满足需求所需的最小结构：一个仓库一个 CloudKit 自定义 zone，主人在 `privateCloudDatabase` 持有，成员在 `sharedCloudDatabase` 访问。

- 系统共享优先  
  家庭协作只走 `CKShare`，不再自造仓库账号密码，不再维护额外身份体系。

- 默认测试稳定，真网测试显式  
  常规单测和 UI 测试继续走内存驱动；真实 CloudKit 测试只在显式入口下运行，不污染默认测试路径。

- 变更可追踪  
  每次结构性修改、测试环境调整和 CloudKit 经验结论，都要追加写入 `log.md`。

## 2. 需求

### 2.1 这个应用要长期解决什么问题？

1. 一个家庭需要共享同一套书库，而不是每个人维护一份分裂的副本。
2. 书库中的“地点”不是写死枚举，而是仓库级配置。
3. 浏览体验要优先于后台信息展示：首页只看书，不看仓库承载细节。
4. 旧数据必须能迁进来，而且迁移过程要可见、可验证。
5. CloudKit 相关问题要能被定位，不能只给一个模糊的“网络失败”。

### 2.2 当前版本必须做到什么？

- 主人可创建自有仓库。
- 仓库通过 `CKShare` 共享给家庭成员。
- 成员从 `sharedCloudDatabase` 访问共享仓库。
- 书籍、地点、导出、清空都围绕“当前仓库”执行。
- 每个仓库都可以独立保存图书排序方式。
- 首页支持动态地点切换、双栏书墙、悬浮搜索和两段式卡片操作。
- 仓库设置页支持地点配置、高级管理区和系统共享入口。
- 旧结构数据可一次性迁移到新仓库。
- 默认测试稳定可重复；真实 CloudKit 集成测试可在已登录测试 iCloud 的 `iPhone 17` 模拟器上显式运行。

### 2.3 当前版本明确不做什么？

- 不再使用仓库账号密码加入。
- 不把默认 UI 测试切到真网 CloudKit。
- 不为 `Development` 和 `Production` 维护两套数据格式。
- 不在首页显示仓库作用域、角色或 CloudKit 承载信息。

## 3. 用户接口

### 3.1 首次进入

- 如果当前会话已有仓库，直接进入该仓库。
- 如果没有仓库但可发现已有仓库，恢复到该仓库。
- 如果还没有任何仓库，用户可创建自己的家庭书库。

### 3.2 浏览、筛选和搜索

- 顶部固定透明地点切换条，支持 `全部 + 动态地点列表`。
- 顶部标题 `家藏万卷` 在向上滚动超过阈值后隐藏。
- 书籍以双栏书墙展示，稳定显示：封面、标题、作者。
- 当前仓库的图书列表可按作者、标题、添加时间、修改时间四种方式排序；默认按添加时间。
- 底部搜索为悬浮毛玻璃控件，不再使用顶部 `.searchable`。

### 3.3 录入、编辑和删除

- 新建书籍默认沿用当前地点筛选；如果当前是 `全部`，则回退到仓库默认地点。
- 编辑页地点列表来自当前仓库配置，不再写死 `成都 / 重庆`。
- 卡片交互采用两段式：先选中卡片，再点击 `修改 / 删除`。

### 3.4 仓库设置

仓库设置页当前主要分成六块：

1. 当前仓库  
   当前仓库名称、角色、数据库和共享状态。
2. 可访问的仓库  
   查看当前设备可访问仓库，并切换到其他仓库。
3. 图书排序  
   为当前仓库选择作者 / 标题 / 添加时间 / 修改时间排序。
4. 地点配置  
   新增、删除、拖拽排序、控制是否显示在首页；修改后直接生效。
5. 共享  
   owner 通过系统共享邀请家人，member 可手动粘贴 iCloud 分享链接。
6. 高级管理区  
   旧数据迁移、清空当前仓库、导出当前仓库 zip。

### 3.5 共享

- 只有 owner 可以发起共享。
- 分享入口走系统 `UICloudSharingController`。
- 接受分享走系统回调和 `CKAcceptSharesOperation`。
- 成员加入后从 `sharedCloudDatabase` 读取和写入共享仓库。

## 4. 数据与同步架构

### 4.1 仓库模型

每个家庭书库对应一个 CloudKit 自定义 zone。

- owner 数据库：`privateCloudDatabase`
- member 数据库：`sharedCloudDatabase`
- zone 根记录：`LibraryRepository`
- 书籍记录：`LibraryBook`
- 地点记录：`LibraryLocation`

`LibraryRepositoryReference` 现在是 share-aware 的，至少包含：

- 仓库 id
- 显示名
- 角色
- 数据库作用域
- zone 标识
- share record 标识
- share 状态

### 4.2 书籍与地点

- 旧 `BookLocation` 枚举已经废弃。
- 书籍主模型现在保存 `locationID`。
- 仓库级 `LibraryLocation` 负责名称、排序和显示控制。
- 首页的“全部”只是 UI 虚拟筛选项，不进入持久化。

### 4.3 本地缓存

本地缓存只承担当前仓库快照与封面缓存，不承担独立同步源职责。

目录结构：

```text
Application Support/homeLibrary/<namespace>/cloudkit-cache/<repository-id>/
├── manifest.json
├── locations.json
├── books/
│   └── <book-id>.json
└── covers/
    └── <cover-asset-id>.bin
```

### 4.4 迁移与导出

- 旧 `books/`、`covers/`、`deletions/`、`books.json`、`SeedBooks.json`、`LibraryImport.json` 都可以作为一次性迁移输入。
- 默认迁移会把旧 `成都 / 重庆` 映射成新的仓库地点配置。
- 导出统一为 zip，根目录只有 `LibraryImport.json`。
- 导出包内嵌封面数据，可直接再导入。

## 5. CloudKit 环境

### 5.1 当前配置

- bundle id：`yu.homeLibrary`
- CloudKit container：`iCloud.yu.homeLibrary`
- entitlement：`homeLibrary/homeLibrary.entitlements`
- `Info.plist`：`CKSharingSupported = true`

### 5.2 Development 和 Production 有什么区别？

业务模型和数据格式没有区别。

区别只在：

- CloudKit schema 所在环境不同
- schema 发布节奏不同
- 真实数据隔离不同

也就是说：

- 你不需要为 `Development` 和 `Production` 维护两套导出格式或两套模型
- 你需要把 schema 变更先在 `Development` 验证，再决定是否部署到 `Production`

### 5.3 真实共享链路

正确链路是：

1. owner 在私有 zone 上创建或获取 `CKShare`
2. 系统分享面板发出邀请链接
3. 被邀请者接受链接
4. App 收到分享 metadata
5. `CKAcceptSharesOperation` 接受共享
6. 共享仓库出现在 `sharedCloudDatabase`

### 5.4 调试模式

如果要追 CloudKit 失败细节，可打开：

```text
HOME_LIBRARY_DEBUG_CLOUDKIT=1
```

调试日志会尽量保留脱敏上下文：

- 操作名
- 数据库作用域
- zone 名
- CloudKit 原始错误
- 用户可见错误映射

### 5.5 关于 QUERYABLE 索引

当前主路径已经尽量避免依赖旧公共库架构下的“全库 query + queryable index”。

仓库发现和 zone 内全量读取现在优先走：

- `databaseChanges(since:)`
- `recordZoneChanges(inZoneWith:since:)`
- 固定根记录 `repository`

因此，旧 README 中把 `recordName` queryable 当成主线前提的说明已经降级为兼容旧实现时的排障补充，而不是当前架构的核心依赖。

## 6. 测试策略

### 6.1 默认测试

默认单测和 UI 测试继续走内存远端：

- 快
- 稳定
- 可重复
- 不依赖 iCloud 账号状态

`LibraryAppConfiguration.live()` 的规则是：

- `HOME_LIBRARY_REMOTE_DRIVER=cloudkit` 时，即使在 XCTest 宿主下也强制用 CloudKit
- 未显式指定时，XCTest 默认还是 memory

### 6.2 真实 CloudKit 集成测试

当前 live 测试入口：

- target：`homeLibraryTests`
- case：`CloudKitLiveIntegrationTests`

固定约束：

- CloudKit 环境：`Development`
- 模拟器：booted `iPhone 17`
- iCloud 账号：当前模拟器已登录的专用测试账号
- 数据隔离：`library.live-test.*` zone 前缀

运行时环境：

```text
HOME_LIBRARY_REMOTE_DRIVER=cloudkit
HOME_LIBRARY_STORAGE_NAMESPACE=cloudkit-live-tests
HOME_LIBRARY_CLOUDKIT_LIVE_TESTS=1
```

如果你用的是支持 test-runner env 的工具，需要把这些变量注入到测试运行器；当前代码也兼容 `TEST_RUNNER_` 前缀环境变量。

### 6.3 双模拟器共享 live

- 跨账号双模拟器共享：
  - 脚本：`scripts/run_dual_sim_cloudkit_share_test.swift`
  - owner：booted `iPhone 17`
  - member：booted `testPhone2`
  - 本地隔离：owner / member 各自独立 `storage namespace` 与 `session namespace`
  - 远端隔离：每次运行都创建唯一仓库名和 `library.live-test.*` zone
  - 收尾：owner 删除测试仓库，member 轮询确认共享仓库从 `sharedCloudDatabase` 消失

- 双模拟器脚本当前验证：
  - owner 创建测试仓库并生成 `CKShare`
  - member 接受共享
  - member 在共享仓库完成书籍新增、读取、修改、删除
  - owner 验证 member 的修改与删除已同步
  - 最终自动清理 owner / member 本地测试命名空间

- 自动化约束说明：
  - 为了让无 UI 的双模拟器脚本能稳定接受 share URL，脚本只在显式测试环境里把临时 `CKShare.publicPermission` 提升到 `.readWrite`
  - 这条放宽只作用于一次性测试仓库，脚本结束后会删除远端仓库并确认 member 侧共享消失
  - 正式产品共享路径仍然是 `UICloudSharingController` + private participant，不会因为这套测试 harness 变成公开共享

### 6.4 当前已覆盖的真网能力

- 创建专用测试仓库
- 仓库发现
- 写入书籍
- 读取回显
- 导出仓库
- 清空仓库
- 自动清理测试仓库
- 双账号共享加入
- member 侧共享仓库 CRUD
- owner 侧跨账号同步验证

### 6.5 当前仍然保留为手动验收的内容

- owner 移除参与者后的权限变化
- 真网 UI 层共享验收
- 指定 Apple ID 私有邀请的完整系统分享面板流程

## 7. 仓库约定

- `README.md` 采用需求优先结构
- `log.md` 只追加，不回写历史
- `plan.md` 保留当前主线实施计划
- 每次结构性修改后，都要补充测试与 CloudKit 环境记录
