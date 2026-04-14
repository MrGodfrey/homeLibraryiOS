# homeLibrary

一个专注 iPhone 的家庭藏书管理应用。

当前版本不再使用 iCloud Drive 共享文件夹，也不再依赖 ISBN 扫码或外部书籍检索；数据以 CloudKit 数据库为中心，书籍信息手动录入，封面由 iPhone 直接上传。

## 当前能力

- 仅面向 iPhone 运行
- 按 `成都` / `重庆` 筛选
- 按书名、作者、出版社搜索
- 手动新增、编辑、删除书籍
- 从 iPhone 相册上传或更换封面
- 使用 CloudKit 同步当前仓库
- 由仓库拥有者生成账号密码，其他用户输入后加入同一仓库并共同修改
- 首次启动自动把旧本地历史数据迁移到 CloudKit，并清理旧结构

## 这次重构的核心变化

### 1. 同步模型

旧方案：

- 本地 JSON
- iCloud Documents 容器
- 共享文件夹书库
- ISBN 自动补全 / 扫码
- iPhone / iPad / macOS 混合目标

新方案：

- CloudKit 公共数据库作为远端源
- 仓库概念：`我的仓库` / `加入的仓库`
- 应用内生成仓库账号密码，不走 iCloud Drive 共享文件夹
- 手动维护书籍信息和封面
- iPhone only

### 2. CloudKit 数据结构

远端使用两个记录类型：

- `LibraryRepository`
  - 仓库名
  - 拥有者本地 profile id
  - 仓库账号
  - 密码盐值与哈希
- `LibraryBook`
  - 所属仓库 id
  - 书籍标题 / 作者 / 所在地
  - `payload` JSON
  - 封面 `CKAsset`
  - 创建时间 / 更新时间 / 软删除时间

其中 `payload` 使用版本化 JSON，当前映射到 `BookPayload`：

```swift
struct BookPayload: Codable {
    var schemaVersion: Int
    var title: String
    var author: String
    var publisher: String
    var year: String
    var location: BookLocation
    var customFields: [String: String]
}
```

这样后面新增字段时，优先改 `payload`，不用先把 CloudKit 的静态字段结构全部推翻。

### 3. 本地缓存

本地仍保留轻量缓存，路径在：

```text
Application Support/homeLibrary/<namespace>/cloudkit-cache/<repository-id>/
├── manifest.json
├── books/
│   └── <book-id>.json
└── covers/
    └── <cover-asset-id>.bin
```

职责只有两个：

- 提升列表加载与封面读取速度
- 作为旧数据迁移后的运行时缓存

它不再是同步源，也不再承担 iCloud Drive 镜像职责。

## 仓库协作方式

### 拥有者

1. 首次启动自动创建自己的仓库
2. 在“仓库管理”中看到仓库账号和仓库密码
3. 把这组信息发给另一位用户
4. 如有需要可重新生成账号密码

### 加入者

1. 打开“仓库管理”
2. 选择“加入别人的仓库”
3. 输入仓库账号和仓库密码
4. 加入成功后，后续对书籍的新增、修改、删除都会写入同一仓库

说明：

- 这是应用级的共享门槛，面向家庭协作场景
- 当前实现基于 CloudKit 公共数据库 + 随机仓库 id + 应用内凭据校验
- 它不是企业级 ACL，也不是端到端加密权限系统

## 历史数据迁移

首次进入自己的 CloudKit 仓库时，应用会检查旧数据：

- 旧结构化目录 `books/`、`covers/`、`deletions/`
- 旧单文件 `books.json`

如果当前远端仓库还是空的，就会：

1. 读取旧数据
2. 转成新 `Book` / `BookPayload`
3. 上传到 CloudKit
4. 清理旧本地结构

迁移完成后，项目运行时表现为只有新数据结构。

## 开发说明

### 目标平台

工程已经改成 iPhone only：

- `SUPPORTED_PLATFORMS = iphoneos iphonesimulator`
- `TARGETED_DEVICE_FAMILY = 1`

### CloudKit 能力

需要：

- iCloud capability
- `com.apple.developer.icloud-services = CloudKit`
- 容器标识：`iCloud.yu.homeLibrary`

`homeLibrary/homeLibrary.entitlements` 只在 `Release` 下启用。

日常本地开发 / 真机联调默认走 `Debug`：

- 不挂 iCloud entitlement
- 运行时默认本地模式
- 本地缓存与会话落到 `Application Support/homeLibrary/local-debug/`

等 CloudKit capability 可用后，再把 Scheme 的 Run 配置切到 `Release`，就会恢复 CloudKit 容器与真实同步验证。

### CloudKit 索引

如果你要把 schema 推到生产环境，至少确认这些字段可查询：

- `LibraryRepository.accessAccount`
- `LibraryBook.repositoryID`

### XCTest 行为

测试运行时会自动切成本地模式，不直接连 CloudKit，这样：

- 不依赖真实 iCloud 账号
- 不依赖签名后的 entitlement
- UI / 单元测试都能稳定跑在 Simulator

## 主要文件

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
├── plan.md
├── log.md
└── README.md
```

## 已验证

### 编译

```bash
xcodebuild -project homeLibrary.xcodeproj -scheme homeLibrary \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO build
```

### 单元测试

```bash
xcodebuild -project homeLibrary.xcodeproj -scheme homeLibrary \
  -destination 'id=8CC688D1-06E8-4A1D-BC56-8AE8A52BA492' \
  -parallel-testing-enabled NO \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO \
  -only-testing:homeLibraryTests test
```

### UI 测试

```bash
xcodebuild -project homeLibrary.xcodeproj -scheme homeLibrary \
  -destination 'id=8CC688D1-06E8-4A1D-BC56-8AE8A52BA492' \
  -parallel-testing-enabled NO \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO \
  -only-testing:homeLibraryUITests/homeLibraryUITests/testAddSearchEditAndDeleteBookOnIOS test
```

```bash
xcodebuild -project homeLibrary.xcodeproj -scheme homeLibrary \
  -destination 'id=8CC688D1-06E8-4A1D-BC56-8AE8A52BA492' \
  -parallel-testing-enabled NO \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO \
  -only-testing:homeLibraryUITests/homeLibraryUITestsLaunchTests/testLaunch test
```
