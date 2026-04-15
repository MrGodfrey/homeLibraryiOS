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

### 5.1 CloudKit Dashboard 索引配置指南

除了签名和 entitlement，当前项目还有一个很容易忽略的前提：**CloudKit Schema 里的索引必须配好**。

如果真机上看到下面这类报错：

- `Field __createdBy is not marked queryable`
- `Field recordName is not marked queryable`
- `Field accessAccount is not marked queryable`
- `Field repositoryID is not marked queryable`

这不是“网络断了”，而是 **CloudKit Schema 缺少 QUERYABLE 索引**。

当前代码已经尽量减少了对索引的依赖。按 `2026-04-15` 之后的实现，最关键的是：

- `LibraryRepository.recordName` 要有 `QUERYABLE`
- `LibraryBook.recordName` 要有 `QUERYABLE`

如果你后续又把查询逻辑改回“按字段直接查”，那还可能需要给下面字段补 `QUERYABLE`：

- `LibraryRepository.__createdBy`
- `LibraryRepository.accessAccount`
- `LibraryBook.repositoryID`

### 5.2 在 CloudKit Dashboard 里添加 QUERYABLE 的具体步骤

下面步骤默认你在配置当前工程使用的容器：

- 容器：`iCloud.yu.homeLibrary`
- 开发环境：`Development`

#### 第一步：打开容器

1. 打开 [CloudKit Console](https://icloud.developer.apple.com/dashboard/)
2. 登录和当前 Apple Developer Team 对应的开发者账号
3. 选择容器 `iCloud.yu.homeLibrary`
4. 先切到 `Development` 环境，不要一开始就在 `Production` 上改

#### 第二步：检查 `LibraryRepository`

1. 进入 `Schema`
2. 找到 record type `LibraryRepository`
3. 打开这个 record type 的字段或索引配置页
4. 找到系统字段 `recordName`
5. 把它标记为 `QUERYABLE`

有些界面会把系统字段显示成 `recordName`，有些资料会写成 `___recordId`。这两个说的是同一个系统字段映射，不用纠结名字差异，关键是把 `recordName` 对应的查询索引打开。

如果你当前看到的是字段列表页面，并且右上角有 `Edit Indexes` 按钮，那么可以直接走这条路径：

1. 点右上 `Edit Indexes`
2. 在 `recordName` 这一行，把 `Single Field Indexes` 从 `None` 改成 `Queryable`
3. 保存

如果你在当前页面里没有看到可直接切换的下拉或开关，也可以走另一条路径：

1. 回到 `Schema`
2. 进入 `Indexes`
3. 点击 `+`
4. `Record Type` 选择 `LibraryRepository`
5. `Index Type` 选择 `QUERYABLE`
6. `Field` 选择 `recordName`
7. 保存

如果后面报 `__createdBy is not marked queryable`，在 Dashboard 里对应的字段通常显示为 `createdUserRecordName`。这时也可以按同样方式补一个 `QUERYABLE` 索引。

#### 第三步：检查 `LibraryBook`

1. 继续留在 `Schema`
2. 找到 record type `LibraryBook`
3. 打开字段或索引配置页
4. 找到系统字段 `recordName`
5. 同样把它标记为 `QUERYABLE`

对 `LibraryBook` 也可以走同样的两条路径：

- 在 record type 页面点 `Edit Indexes`，把 `recordName` 改成 `Queryable`
- 或者回到 `Schema -> Indexes -> +`，新建：
  - `Record Type = LibraryBook`
  - `Index Type = QUERYABLE`
  - `Field = recordName`

#### 第四步：如果你仍然报其他字段 not marked queryable

继续在对应 record type 里把报错字段补成 `QUERYABLE`：

- 报 `__createdBy`：去 `LibraryRepository` 里给 `__createdBy` 加 `QUERYABLE`
- 报 `accessAccount`：去 `LibraryRepository` 里给 `accessAccount` 加 `QUERYABLE`
- 报 `repositoryID`：去 `LibraryBook` 里给 `repositoryID` 加 `QUERYABLE`

#### 第五步：保存并等待 CloudKit 生效

1. 保存 schema 修改
2. 等待一小段时间让 CloudKit 后台完成索引更新
3. 删除 iPhone 上已有的旧安装包
4. 从 Xcode 重新 build 并安装到真机
5. 重新打开 app 验证

CloudKit 的索引更新不是完全瞬时的。如果你刚改完就立即重试，仍然看到旧错误，不一定是你改错了，也可能只是索引还没完全生效。

### 5.3 什么时候还要把 Development 部署到 Production

Xcode 直连真机调试时，通常先吃到的是 `Development` 环境的 schema。

如果你后面准备：

- 给其他测试人员安装
- 用 TestFlight 分发
- 走正式发布包

那还需要把已经验证过的 schema 变更部署到 `Production`。否则会出现：

- 开发机正常
- 换一个包或换一个环境就再次报 schema / queryable 错误

### 5.4 建议的最小排障顺序

如果真机首次运行失败，建议按下面顺序排：

1. 确认 iPhone 已登录可用的 iCloud 账号
2. 确认 Xcode 安装到设备上的包带有 CloudKit entitlement
3. 确认容器 `iCloud.yu.homeLibrary` 选对了 team 和环境
4. 先检查 `LibraryRepository.recordName`
5. 再检查 `LibraryBook.recordName`
6. 如果仍失败，按错误原文继续给对应字段补 `QUERYABLE`
7. 删除设备旧包，重新安装，再试一次

### 5.5 当前项目和索引的关系

当前项目使用两个 CloudKit record type：

- `LibraryRepository`
- `LibraryBook`

其中：

- `LibraryRepository` 负责仓库边界、拥有者信息和加入凭据
- `LibraryBook` 负责书籍主记录、封面引用和软删除状态

应用启动时会查询仓库记录；进入书库后会查询书籍记录。所以只要 Schema 里缺少对应索引，真机就可能在启动阶段直接报错，甚至还没走到书籍列表。

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
