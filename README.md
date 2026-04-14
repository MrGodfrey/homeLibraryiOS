# homeLibrary

一个用 SwiftUI 编写的家庭藏书管理应用。当前版本已经完成 iOS 端落地、云同步接入，以及“图片与书籍数据分离存储”的重构。

## 当前状态

截至 2026-04-14，项目已经具备以下能力：

- iPhone / iPad / macOS 共用一套 SwiftUI 界面
- 查看全部藏书
- 按 `成都` / `重庆` 筛选
- 按书名、作者、ISBN 搜索
- 新增、编辑、删除书籍
- 选择并展示书籍封面
- ISBN 自动补全
- ISBN 扫码入口
- iCloud Documents 云同步
- 旧版 `books.json` / `SeedBooks.json` 自动迁移

## 这次改了什么

### 1. iOS 版本

工程本身就是多平台 target，这次把它收敛成真正可验证的 iOS 版本：

- 保留统一 SwiftUI 代码路径
- 在 iOS Simulator 上补了真实 UI 测试
- 为表单、列表、工具栏增加了自动化测试标识

### 2. 图片和数据分离

旧方案把封面二进制直接写进整库 JSON，随着书量增加会带来几个问题：

- 单文件越来越大
- 每次改一条记录都要重写整个文件
- 云同步粒度过粗

现在改成了结构化目录：

```text
Application Support/homeLibrary/
├── manifest.json
├── books/
│   └── <book-id>.json
├── covers/
│   └── <cover-asset-id>.bin
├── deletions/
│   └── <book-id>.json
└── books.legacy.backup.json   # 仅迁移旧数据时生成
```

说明：

- `books/` 只保存元数据
- `covers/` 只保存封面文件
- `deletions/` 保存删除墓碑，给云同步做冲突处理

### 3. 云同步

同步层使用 iCloud Documents 容器镜像本地目录结构。

同步规则：

- 书籍更新：按 `updatedAt` 最后写入胜出
- 书籍删除：按 tombstone 的 `deletedAt` 胜出
- 封面资源：按 `coverAssetID` 复制补齐

触发时机：

- 应用加载后自动尝试同步
- 手动刷新时同步
- 保存 / 删除后同步

界面会显示当前同步状态。

## 旧数据迁移

为了兼容现有数据，这次没有直接改 bundled `SeedBooks.json` 的格式，而是在首次启动时自动迁移：

- 如果本地有旧版 `books.json`，优先迁移本地数据
- 否则迁移 bundled `SeedBooks.json`
- 迁移时把旧的 `coverData` 拆成独立封面文件

这样可以保留现有种子文件，同时把运行时存储切到新结构。

## 目录结构

```text
homeLibrary/
├── homeLibrary.xcodeproj/
├── homeLibrary/
│   ├── Book.swift
│   ├── BookEditorView.swift
│   ├── ContentView.swift
│   ├── ISBNLookupService.swift
│   ├── ISBNScannerView.swift
│   ├── LibraryAppConfiguration.swift
│   ├── LibraryPersistence.swift
│   ├── LibraryStore.swift
│   ├── LibrarySync.swift
│   ├── homeLibrary.entitlements
│   ├── homeLibraryApp.swift
│   └── SeedBooks.json
├── homeLibraryTests/
├── homeLibraryUITests/
├── plan.md
├── log.md
└── README.md
```

## 运行方式

### Xcode

1. 打开 `homeLibrary.xcodeproj`
2. 选择 `homeLibrary` scheme
3. 选择运行目标：
   - `iPhone / iPad Simulator`
   - `iPhone / iPad` 真机
   - `My Mac`
4. 点击 `Run`

### 云同步前提

如果要验证真实 iCloud 同步，需要：

- 使用带 iCloud capability 的签名团队
- 保持 `homeLibrary/homeLibrary.entitlements`
- 在需要同步的设备上登录同一个 Apple ID

如果当前只想本地开发，不登录 iCloud 也能正常使用本地书库。

## 本地数据位置

默认目录：

```text
Application Support/homeLibrary
```

在 macOS 沙盒下通常会落到：

```text
~/Library/Containers/yu.homeLibrary/Data/Library/Application Support/homeLibrary
```

## 测试

### 单元测试

覆盖内容：

- 图书筛选
- 表单标准化
- 扫码文本中的 ISBN 提取
- 元数据 / 封面分离存储
- 云端更新合并
- 云端删除传播

本次实际验证命令：

```bash
xcodebuild -project homeLibrary.xcodeproj -scheme homeLibrary \
  -destination 'id=8CC688D1-06E8-4A1D-BC56-8AE8A52BA492' \
  -parallel-testing-enabled NO \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO \
  -only-testing:homeLibraryTests test
```

结果：`6` 个测试通过。

### UI 测试

覆盖内容：

- iOS 启动烟测
- 新增 -> 搜索 -> 编辑 -> 删除完整流程

本次实际验证命令：

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

结果：

- 主流程 UI 测试通过
- 启动烟测通过

## ISBN 数据来源

- Google Books
- Open Library

说明：

- 自动补全依赖网络
- 接口无结果时需要手动补录

## 当前限制

- 命令行跑 iOS 测试时，当前机器更稳定的方式是先预热 simulator，再使用明确设备 ID 运行
- 扫码能力仍然依赖支持 `VisionKit DataScannerViewController` 的设备
- iCloud 同步在未配置可用签名 / 账号时会自动退回本地模式

## 后续可以继续做的事

- 为封面资源补充后台清理和更细的缓存策略
- 为云同步增加更明确的冲突提示和诊断信息
- 增加批量导入 / 导出能力
