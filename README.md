# homeLibrary

`homeLibrary` 是一个面向 iPhone 的家庭藏书协作应用。

当前实现把 CloudKit 公共数据库作为唯一远端主存。设备端保留仓库会话和本地缓存，但普通运行路径已经不再提供独立的“本地模式”回退。应用启动后会直接准备 CloudKit 仓库，并围绕同一个仓库完成浏览、搜索、录入、编辑、删除和协作加入。

## 1. 当前版本结论

- 平台是 `iPhone only`
- 普通运行默认使用 `CloudKitLibraryService`
- 测试和显式指定 `HOME_LIBRARY_REMOTE_DRIVER=memory` 时，才会切到内存远端
- 本地目录只承担缓存、会话和一次性迁移入口，不再是同步源
- 拥有者首次进入空仓库时，会按需导入旧结构或 bundled `SeedBooks.json`

如果当前设备没有可用的 iCloud 账号、签名缺少 CloudKit entitlement，或者 App ID / provisioning profile 没有开启 iCloud capability，应用不会回退到本地仓库，而是直接报 CloudKit 相关错误。

## 2. 用户流程

### 2.1 首次启动

应用启动后，`LibraryStore` 会按下面的顺序决定当前仓库：

1. 优先使用当前会话里已经保存的仓库
2. 如果当前仓库为空但自己已有拥有者仓库，则切回自己的仓库
3. 如果两者都没有，则通过 CloudKit 自动创建一个拥有者仓库

拥有者仓库首次为空时，系统会尝试读取旧数据并导入：

- 旧结构目录：`books/`、`covers/`、`deletions/`
- 旧单文件：`books.json`
- 结构化种子：`SeedBooks.json`、`LibraryImport.json`

导入完成后会记录迁移标记，避免重复执行。

### 2.2 浏览、筛选和搜索

主页面当前支持：

- 按 `全部` / `成都` / `重庆` 切换列表
- 按书名、作者、出版社和自定义字段搜索
- 显示当前仓库标题、角色和同步状态
- 手动刷新远端数据

### 2.3 添加、编辑和删除

当前版本只保留手动录入：

- 书名
- 作者
- 出版社
- 出版年份
- 所在地
- 自定义字段
- 从相册选择或替换封面

保存会直接写入当前 CloudKit 仓库，并刷新本地缓存。删除使用远端软删除字段，缓存中的对应书籍会随刷新移除。

### 2.4 仓库协作

“仓库管理”页当前负责四件事：

1. 查看当前仓库和自己的角色
2. 拥有者查看并复制仓库账号和密码
3. 拥有者重新生成账号密码
4. 加入者通过账号密码加入别人的仓库，并可切回自己的仓库

当前协作模型是家庭级门槛控制，不是企业级权限系统。核心约束是：

- 远端状态存在 CloudKit 公共数据库
- 仓库边界由 `LibraryRepository` 记录决定
- 加入流程依赖应用内生成的仓库账号密码

## 3. 数据与同步模型

### 3.1 领域对象

| 对象 | 作用 | 当前实现 |
| --- | --- | --- |
| `LibraryRepository` | 协作边界；决定当前在操作哪个家庭书库 | CloudKit 记录 |
| `LibraryBook` | 书籍主记录 | CloudKit 记录 |
| `Book` | UI 和缓存使用的本地模型 | `homeLibrary/Book.swift` |
| `BookPayload` | 版本化业务字段容器 | 编码进 `LibraryBook.payload` |
| `RepositoryCredentials` | 仓库加入凭据 | 账号 + 密码 |

### 3.2 CloudKit 记录

当前 CloudKit 使用两类记录：

- `LibraryRepository`
- `LibraryBook`

其中：

- `LibraryBook.payload` 保存版本化 JSON
- 封面以 `CKAsset` 形式上传
- 删除通过 `deletedAt` 软删除，不做即时物理清除

### 3.3 本地状态

本地状态分成三部分：

| 组件 | 作用 | 当前实现 |
| --- | --- | --- |
| `LibraryCacheStore` | 仓库级缓存 | `Application Support/homeLibrary/<namespace>/cloudkit-cache/<repository-id>/` |
| `RepositorySessionStore` | 当前仓库、拥有者仓库、迁移标记、拥有者 profile id | `UserDefaults` |
| `LegacyLibraryImporter` | 读取旧结构和种子，执行一次性导入 | `homeLibrary/LibraryPersistence.swift` |

缓存目录结构：

```text
Application Support/homeLibrary/<namespace>/cloudkit-cache/<repository-id>/
├── manifest.json
├── books/
│   └── <book-id>.json
└── covers/
    └── <cover-asset-id>.bin
```

这里的缓存不是独立仓库，不承担本地优先同步职责。它只是远端快照和封面资产缓存。

## 4. 运行装配

`homeLibrary/LibraryAppConfiguration.swift` 当前的装配逻辑很简单：

- 普通运行：`CloudKitLibraryService`
- `XCTest` 宿主：`InMemoryLibraryRemoteService`
- 显式设置 `HOME_LIBRARY_REMOTE_DRIVER=memory`：`InMemoryLibraryRemoteService`

### 4.1 支持的环境变量

| 变量 | 作用 |
| --- | --- |
| `HOME_LIBRARY_REMOTE_DRIVER=memory` | 强制使用内存远端，主要供测试和受控调试使用 |
| `HOME_LIBRARY_STORAGE_ROOT` | 重定向本地缓存根目录 |
| `HOME_LIBRARY_STORAGE_NAMESPACE` | 为缓存和会话隔离命名空间 |
| `HOME_LIBRARY_SESSION_NAMESPACE` | 单独覆盖会话命名空间 |
| `HOME_LIBRARY_CLOUDKIT_CONTAINER` | 覆盖默认 CloudKit 容器 id |
| `HOME_LIBRARY_DISABLE_BUNDLED_SEED=1` | 禁用 bundle 内的种子导入来源 |

当前已经移除基于 `Debug` / `Release` 自动切换本地模式的逻辑，也不再支持通过环境变量关闭 CloudKit 进入旧本地路径。

## 5. 签名与 CloudKit

真实设备运行需要三层都一致：

1. target 带有 iCloud capability
2. entitlements 包含 `com.apple.developer.icloud-services = CloudKit`
3. App ID / provisioning profile 已启用对应 iCloud 容器

当前工程固定使用：

- bundle id: `yu.homeLibrary`
- CloudKit 容器：`iCloud.yu.homeLibrary`
- entitlement 文件：`homeLibrary/homeLibrary.entitlements`

`homeLibrary.xcodeproj` 当前已在 `Debug` 和 `Release` 都绑定 `homeLibrary/homeLibrary.entitlements`。也就是说，普通真机调试包和发布包都要求签名链路具备 CloudKit 能力。

如果你修改了 signing / capability，或者之前设备上安装过不带 CloudKit entitlement 的旧包，需要重新 build 并重新安装 app。

## 6. 代码结构

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

页面层尽量不直接操作持久化和 CloudKit。主要职责分布如下：

| 文件 | 作用 |
| --- | --- |
| `homeLibrary/homeLibraryApp.swift` | 应用入口，创建唯一的 `LibraryStore` |
| `homeLibrary/ContentView.swift` | 列表、筛选、搜索、刷新、弹窗入口 |
| `homeLibrary/BookEditorView.swift` | 书籍编辑与封面选择 |
| `homeLibrary/RepositoryManagementView.swift` | 仓库信息、凭据、加入和切换 |
| `homeLibrary/LibraryStore.swift` | 状态编排、同步触发、缓存刷新 |
| `homeLibrary/LibrarySync.swift` | CloudKit / 内存远端实现 |
| `homeLibrary/LibraryPersistence.swift` | 缓存、旧数据导入、JSON 编解码 |

## 7. 开发与验证

### 7.1 构建

```bash
xcodebuild -project homeLibrary.xcodeproj -scheme homeLibrary \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO build
```

### 7.2 单元测试

```bash
xcodebuild -project homeLibrary.xcodeproj -scheme homeLibrary \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -parallel-testing-enabled NO \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO \
  -only-testing:homeLibraryTests test
```

### 7.3 UI 测试

```bash
xcodebuild -project homeLibrary.xcodeproj -scheme homeLibrary \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -parallel-testing-enabled NO \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO \
  -only-testing:homeLibraryUITests test
```

### 7.4 当前已验证范围

截至 `2026-04-15`，当前仓库已经验证：

- iOS Simulator 构建通过
- `homeLibraryTests` 共 `10` 个单元测试通过
- `homeLibraryUITests` 共 `3` 个 UI 测试通过
- 面向已连接真机的 `Debug` build 通过
- `Debug` / `Release` 的 build settings 都能解析出同一个 `CODE_SIGN_ENTITLEMENTS`

## 8. 迁移种子

旧 Cloudflare 数据可以通过 `scripts/import_from_cloudflare.mjs` 导出为 `homeLibrary/SeedBooks.json`。迁移脚本说明见 `docs/cloudflare-migration.md`。

示例：

```bash
node scripts/import_from_cloudflare.mjs \
  --source-repo /Users/wangyu/code/Home-library \
  --output homeLibrary/SeedBooks.json
```
