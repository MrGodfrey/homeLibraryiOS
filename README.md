# homeLibrary

`homeLibrary` 是一个面向 iPhone 的家庭藏书协作应用。

它不再把书库理解成散落在设备、本地 JSON 和共享文件夹里的多份副本，而是围绕同一个“仓库”维护三类核心状态：仓库身份、书籍记录、封面资产。CloudKit 是主存，iPhone 是主要操作端，本地目录只承担缓存、会话和一次性迁移入口。

## 1. 设计方式

- 需求先于架构  
先定义这个 app 长期服务什么家庭场景，再决定页面、Store、CloudKit 记录和目录怎么拆。需求变了，后面的实现应该跟着重写。

- 仓库先于设备  
系统的核心对象不是某一台 iPhone 上的本地书单，而是一个可被多人加入的书库仓库。设备只是这个仓库的操作端。

- 云端主存，本地缓存  
CloudKit 公共数据库保存协作状态；本地目录负责列表加载、封面读取、离线缓存和迁移落点，不再承担同步源职责。

- 数据模型先于页面  
先固定 `LibraryRepository`、`LibraryBook` 和 `BookPayload` 的含义，再让 `ContentView`、`BookEditorView` 和 `RepositoryManagementView` 去操作这些对象。

- 手动录入优先  
当前版本明确放弃 ISBN 自动补全、扫码录入和外部书籍检索。所有字段由用户直接维护，避免把体验建立在不稳定外部依赖上。

- 迁移是一次性事件  
旧 `books/`、`covers/`、`deletions/`、`books.json` 和 `SeedBooks.json` 只作为导入来源。迁移完成后，运行时只认新结构。

- 调试与生产分轨  
`Debug` 默认本地模式，不挂 CloudKit entitlement；`Release` 才进入真实 CloudKit。测试也强制走本地模式，保持可复现。

## 2. 需求

这一节是继续改这个项目时的起点。先把问题答清楚，再动架构和代码。

### 2.1 可以先回答这五个问题

```text
1. 这个 app 长期服务的核心家庭场景是什么？
2. 哪些状态必须稳定保存，并能跨设备协作？
3. 用户之间如何进入同一个书库？
4. 脱离 CloudKit 时，最少要保留什么可用体验？
5. 哪些能力当前明确不做，避免架构继续发散？
```

### 2.2 当前版本的示例回答

#### 这个 app 长期服务的核心家庭场景是什么？

服务一个家庭共用书库的日常维护：在 iPhone 上查看、搜索、筛选、录入、修改和删除书籍，并让家庭成员围绕同一个仓库协作，而不是各自维护一份副本。

#### 哪些状态必须稳定保存，并能跨设备协作？

必须稳定保存仓库身份、书籍元数据、封面资产、当前加入的是哪个仓库、拥有者自己的仓库凭据，以及首次迁移是否已经完成。远端主状态在 CloudKit；本地还保留按仓库分隔的缓存目录和会话状态。

#### 用户之间如何进入同一个书库？

拥有者首次启动时自动创建自己的仓库，在“仓库管理”里拿到仓库账号和密码；加入者输入这组凭据后进入同一仓库，之后的新增、编辑、删除都直接写到这一个仓库里。

#### 脱离 CloudKit 时，最少要保留什么可用体验？

在 `Debug`、测试或没有可用 iCloud 账号时，app 仍要能在本地模式下完成查看、搜索、筛选、增删改和封面缓存；如果本地库是空的，还要能自动消费 `SeedBooks.json` 作为旧库种子。

#### 哪些能力当前明确不做，避免架构继续发散？

不再做 iCloud Drive 共享文件夹、不再做 ISBN 自动补全和扫码录入、不再做 iPad/macOS 多平台扩张、不把仓库凭据系统伪装成企业级 ACL，也不让种子文件覆盖已有数据。

## 3. 用户接口

这一节给产品使用和开发调试都看得懂的简版说明。

### 3.1 打开 app 后会发生什么

应用启动后，`LibraryStore` 会先确定当前运行模式：

- `Release + CloudKit 可用`：连接 CloudKit，准备拥有者仓库或已加入仓库
- `Debug / XCTest / 显式关闭云同步`：进入本地模式，使用 `local-default` 仓库

如果当前仓库还没有数据，系统会按需触发旧库迁移或 `SeedBooks.json` 导入。

### 3.2 浏览、筛选和搜索

主页面支持：

- 按 `全部` / `成都` / `重庆` 切换可见书籍
- 按书名、作者、出版社搜索
- 下拉刷新或工具栏刷新
- 查看当前仓库标题、角色和同步状态

### 3.3 添加、编辑和删除书籍

新增或编辑时，当前版本只支持手动维护：

- 书名
- 作者
- 出版社
- 出版年份
- 所在地
- 从 iPhone 相册选择或更换封面

删除会直接写入当前仓库；在 CloudKit 模式下是远端软删除，在本地缓存里会同步移除。

### 3.4 仓库协作

在“仓库管理”里可以完成四件事：

1. 查看当前仓库及自己的角色
2. 拥有者查看并复制仓库账号和密码
3. 拥有者重新生成账号密码
4. 其他用户输入账号密码加入仓库；已加入别人仓库后，也可以切回自己的仓库

当前方案是家庭协作门槛，基于 `CloudKit 公共数据库 + 随机仓库 id + 应用内凭据校验`，不是企业级权限系统。

### 3.5 首次迁移和种子导入

当前版本支持三类旧数据来源：

- 旧结构化目录：`books/`、`covers/`、`deletions/`
- 旧单文件：`books.json`
- 结构化种子：`SeedBooks.json` 或 `LibraryImport.json`

导入规则是：

- 只有空本地仓库或空 CloudKit 拥有者仓库才会自动导入
- 导入成功后会记录迁移完成标记
- 旧 `isbn` 会被写入 `customFields["ISBN"]`
- 现有数据不会被种子覆盖

### 3.6 本地调试和真实 CloudKit

日常本地开发默认走本地模式：

- 不要求 iCloud entitlement
- 不依赖真实 iCloud 账号
- 本地缓存落在 `Application Support/homeLibrary/local-debug/`

当要验证真实同步时，再切到 `Release` 并启用 CloudKit。测试运行时也会自动关闭云同步，避免依赖外部环境。

## 4. 架构

这一节描述当前实现怎样服务第 2 节需求。它不是唯一正确答案，但它解释了现在的代码为什么这样组织。

### 4.1 领域对象层

| 对象 | 作用 | 当前实现 |
|---|---|---|
| `Repository` | 协作边界；决定“我现在在操作哪一个家庭书库” | 远端是 `LibraryRepository` 记录，本地是 `LibraryRepositoryReference` |
| `Book` | 书籍主记录 | `LibraryBook` 远端记录 + 本地 `Book` 模型 |
| `BookPayload` | 可扩展的业务字段容器 | 标题、作者、出版社、年份、地点、自定义字段，带 `schemaVersion` |
| `Cover` | 书籍封面二进制资产 | 远端为 `CKAsset`，本地为 `covers/<asset-id>.bin` |
| `Seed` | 一次性导入包 | `SeedBooks.json` / `LibraryImport.json`，只在空库时消费 |

如果后面需求变化，这一层要先改，再去动 UI 和同步细节。

### 4.2 页面与交互层

当前 UI 很薄，主要负责把用户动作交给 `LibraryStore`：

| 文件 | 作用 |
|---|---|
| `homeLibrary/homeLibraryApp.swift` | 应用入口，创建唯一的 `LibraryStore` |
| `homeLibrary/ContentView.swift` | 书籍列表、地点筛选、搜索、刷新、入口按钮 |
| `homeLibrary/BookEditorView.swift` | 手动录入和封面选择 |
| `homeLibrary/RepositoryManagementView.swift` | 仓库凭据查看、加入仓库、切回自己的仓库、重置凭据 |

页面层尽量不直接碰持久化和 CloudKit；这些动作都交给 Store。

### 4.3 状态与编排层

`homeLibrary/LibraryStore.swift` 是当前应用的中心编排层，也是 UI 订阅的单一状态源。

它主要负责：

- 持有 `books`、搜索词、地点筛选、同步状态、当前仓库、提示消息
- 启动时决定当前仓库，并按模式选择本地或 CloudKit 流程
- 在拥有者首次进入空仓库时触发旧库导入
- 在本地模式空库时触发本地 seed 导入
- 处理新增、编辑、删除、加入仓库、切换仓库、刷新、重置凭据
- 把远端快照写回本地缓存，再让 UI 只基于缓存渲染

当前设计里，页面不直接操作 CloudKit，CloudKit 也不直接驱动 UI。中间的稳定接口是 `LibraryStore`。

### 4.4 同步与远端层

远端接口由 `LibraryRemoteSyncing` 抽象，当前实现是 `homeLibrary/LibrarySync.swift` 里的 `CloudKitLibraryService`。

它负责：

- 创建拥有者仓库
- 根据账号密码加入仓库
- 轮换拥有者仓库凭据
- 拉取某个仓库下的全部书籍
- 上传或更新书籍及封面
- 软删除书籍

CloudKit 当前使用两个记录类型：

- `LibraryRepository`
- `LibraryBook`

其中 `LibraryBook.payload` 保存版本化 JSON，封面用 `CKAsset`，删除使用 `deletedAt` 软删除字段，不做物理立即移除。

### 4.5 本地持久化与迁移层

本地状态由三个部件组成：

| 组件 | 作用 | 当前实现 |
|---|---|---|
| `LibraryCacheStore` | 仓库级缓存 | `Application Support/homeLibrary/<namespace>/cloudkit-cache/<repository-id>/` |
| `RepositorySessionStore` | 当前仓库、拥有者仓库、迁移标记 | `UserDefaults` |
| `LegacyLibraryImporter` | 读取旧结构和 seed，执行一次性导入 | 支持旧目录、`books.json`、`SeedBooks.json`、`LibraryImport.json` |

缓存目录结构如下：

```text
Application Support/homeLibrary/<namespace>/cloudkit-cache/<repository-id>/
├── manifest.json
├── books/
│   └── <book-id>.json
└── covers/
    └── <cover-asset-id>.bin
```

这里的本地目录不是同步源，而是远端数据的缓存副本，以及无云环境下的运行时存储。

### 4.6 运行适配层

`homeLibrary/LibraryAppConfiguration.swift` 负责把运行环境装配成当前模式。

当前规则是：

- `XCTest` 一律关闭 CloudKit
- `Debug` 默认关闭 CloudKit
- `Release` 默认开启 CloudKit
- `HOME_LIBRARY_ENABLE_CLOUD_SYNC=1` 可以强制开启
- `HOME_LIBRARY_DISABLE_CLOUD_SYNC=1` 可以强制关闭
- `HOME_LIBRARY_STORAGE_ROOT` / `HOME_LIBRARY_STORAGE_NAMESPACE` / `HOME_LIBRARY_SESSION_NAMESPACE` 可以重定向本地数据和会话空间

这让同一套业务代码能在真机调试、Simulator、UI 测试和真实 CloudKit 环境下共用，而不是为每种环境分别维护一套实现。

## 5. 开发与验证

### 5.1 目标平台

当前工程明确是 iPhone only：

- `SUPPORTED_PLATFORMS = iphoneos iphonesimulator`
- `TARGETED_DEVICE_FAMILY = 1`

### 5.2 CloudKit 能力

真实云同步需要：

- iCloud capability
- `com.apple.developer.icloud-services = CloudKit`
- 容器 `iCloud.yu.homeLibrary`

`homeLibrary/homeLibrary.entitlements` 当前只在 `Release` 下启用。

### 5.3 CloudKit 查询字段

如果要把 schema 推到生产环境，至少确认这些字段可查询：

- `LibraryRepository.accessAccount`
- `LibraryBook.repositoryID`

### 5.4 旧库导出脚本

旧 Cloudflare 数据可以通过 [docs/cloudflare-migration.md](docs/cloudflare-migration.md) 里的流程导出为 `homeLibrary/SeedBooks.json`。

示例命令：

```bash
node scripts/import_from_cloudflare.mjs \
  --source-repo /Users/wangyu/code/Home-library \
  --output homeLibrary/SeedBooks.json
```

### 5.5 仓库结构

```text
homeLibrary/
├── homeLibrary/
│   ├── Book.swift
│   ├── BookEditorView.swift
│   ├── ContentView.swift
│   ├── LibraryAppConfiguration.swift
│   ├── LibraryPersistence.swift
│   ├── LibraryStore.swift
│   ├── LibrarySync.swift
│   ├── LibrarySyncSettings.swift
│   ├── RepositoryManagementView.swift
│   ├── homeLibrary.entitlements
│   └── homeLibraryApp.swift
├── homeLibraryTests/
├── homeLibraryUITests/
├── docs/
├── scripts/
├── plan.md
├── log.md
└── README.md
```

### 5.6 已验证

截至 `2026-04-14`，当前版本已经验证：

- iOS Simulator 构建通过
- 单元测试 `6` 个通过
- UI 主流程测试通过
- UI 启动烟测通过

示例命令：

```bash
xcodebuild -project homeLibrary.xcodeproj -scheme homeLibrary \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO build
```

```bash
xcodebuild -project homeLibrary.xcodeproj -scheme homeLibrary \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -parallel-testing-enabled NO \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO \
  -only-testing:homeLibraryTests test
```

```bash
xcodebuild -project homeLibrary.xcodeproj -scheme homeLibrary \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -parallel-testing-enabled NO \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO \
  -only-testing:homeLibraryUITests/homeLibraryUITests/testAddSearchEditAndDeleteBookOnIOS test
```

```bash
xcodebuild -project homeLibrary.xcodeproj -scheme homeLibrary \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -parallel-testing-enabled NO \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO \
  -only-testing:homeLibraryUITests/homeLibraryUITestsLaunchTests/testLaunch test
```
