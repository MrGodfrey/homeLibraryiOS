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
- 个人 iCloud 与共享文件夹同步
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

### 3. 同步

同步层复用了同一套目录镜像和冲突合并逻辑，但现在支持两种同步目标：

- `个人 iCloud`：继续使用 iCloud Documents 容器，适合同一 Apple ID 的多设备同步
- `共享书库文件夹`：由用户在 app 内选择一个共享文件夹，适合不同 Apple ID 共同维护同一套书库

同步规则：

- 书籍更新：按 `updatedAt` 最后写入胜出
- 书籍删除：按 tombstone 的 `deletedAt` 胜出
- 封面资源：按 `coverAssetID` 复制补齐

触发时机：

- 应用加载后自动尝试同步
- 手动刷新时同步
- 保存 / 删除后同步
- 切换同步目标后立即同步一次

界面会同时显示当前同步状态和同步目标。

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

### 个人团队先做本地测试

如果 Xcode 提示：

```text
Personal development teams do not support the iCloud capability
```

说明当前签名团队还不能给这个 bundle 开出带 iCloud entitlement 的开发描述文件。项目已经改成：

- `Debug`：不再附带 `homeLibrary.entitlements`，可先测试本地功能
- `Release`：继续保留 iCloud entitlement，用于后续真实云同步验证或正式分发

也就是说，你现在可以直接用下面两种方式先开发和验收：

1. 运行到 `iPhone Simulator`
2. 用个人团队把 `Debug` 装到自己的真机

这时应用会正常使用本地书库；因为没有 iCloud entitlement，同步状态会显示为未开启，这是预期行为。

等 Apple Developer Program 审核通过后，再用 `Release` 或重新开启 iCloud capability 去验证真实 iCloud 同步。

## 在你的电脑和手机上怎么用

### 你自己的电脑（macOS）

1. 用 Xcode 打开工程，运行目标选 `My Mac`
2. 首次启动后，应用会在本机创建本地书库
3. 日常使用入口：
   - 顶部搜索框：按书名、作者、ISBN 搜索
   - 顶部分段：切换 `全部 / 成都 / 重庆`
   - 右上角 `+`：新增书籍
   - 每本书右侧铅笔按钮：编辑
   - 每本书右侧垃圾桶按钮：删除
   - 顶部刷新按钮：重新加载并触发一次同步
4. 如果没有配置 iCloud，也可以只把它当单机版使用

### 你自己的手机或平板（iPhone / iPad）

1. 用 Xcode 打开工程，运行目标选你的真机
2. 第一次装到真机时，按系统要求完成开发者信任 / 开发者模式设置
3. 安装完成后，手机上的操作和 Mac 基本一致：
   - 搜索、筛选
   - 添加书籍
   - 扫码录入 ISBN
   - 编辑书籍
   - 删除书籍
4. 如果你希望手机和电脑看到同一套数据，需要两边都登录同一个 Apple ID，并且 iCloud 可用

### 同一个人跨设备同步怎么工作

- 这个应用当前没有应用内账号系统，没有“邮箱注册 / 密码登录 / 邀请成员”页面
- 当前的“登录”其实是系统层的 Apple ID 登录，不是 app 内登录
- 只要你的 Mac、iPhone、iPad 登录的是同一个 Apple ID，并且项目签名能拿到 `iCloud.yu.homeLibrary` 容器，书库就会自动同步
- 同步触发时机：
  - 启动应用后
  - 手动点刷新
  - 保存书籍后
  - 删除书籍后
- 修改冲突时，以 `updatedAt` 更新更晚的版本为准
- 删除冲突时，以 `deletedAt` 更晚的删除记录为准
- 所以你在一台设备上删除一本书后，其他同 Apple ID 的设备同步后也会看到这本书被删除

## 如何分发给伙伴测试

当前项目是原生 SwiftUI 工程，不是网页，也没有现成的公开下载链接。要给伙伴测试，现实里有三种方式：

### 方式 1：把源码发给她，让她自己用 Xcode 跑

适合对方有 Mac 和 Xcode。

1. 把仓库发给她
2. 她在自己的 Mac 上打开 `homeLibrary.xcodeproj`
3. 如果她不在你的开发团队里，需要先处理签名：
   - 改成她自己的 `Bundle ID`、签名团队、iCloud 容器；或者
   - 临时关闭 iCloud capability，只测试本地功能
4. 运行到 `My Mac` 或自己的 iPhone

这种方式下，她测试的是一份独立安装的 app。

### 方式 2：你打 TestFlight 给她

适合对方只想安装测试版，不想碰源码。

1. 你需要 Apple Developer Program
2. 用你自己的发布签名、Bundle ID、iCloud 配置打包上传到 App Store Connect
3. 在 TestFlight 邀请她
4. 她用自己的 Apple ID 安装测试版

这是最适合“分发给伙伴测试”的方式。现在如果你们还要共享同一套书库，可以在 app 里把双方都切到同一个共享书库文件夹。

### 方式 3：只验证你自己的多设备同步

如果你的目标只是验证“同一份书库能不能在多台设备保持一致”，最直接的方法不是把 app 发给别人，而是你自己在：

- `My Mac`
- 你的 iPhone / iPad

上都安装同一个构建，并登录同一个 Apple ID 来测试。

## 她要怎么登录、共享、修改、删除你的数据

这里需要明确区分“安装 app 测试”和“多人共享同一套书库”。

### 现在已经支持的

- 你自己在多台设备之间共享同一套数据
- 你自己在任意一台设备上新增、修改、删除书籍
- 这些改动通过 iCloud 同步到你自己其他设备
- 不同 Apple ID 通过同一个共享文件夹共同维护同一套书库

### 现在还不支持的

- 你在 app 里邀请她加入你的家庭书库
- 给不同成员设置“只读 / 可编辑 / 可删除”权限

原因很简单：当前跨 Apple ID 的方案是“共享文件夹同步”，不是独立账号系统；项目里还没有成员权限、操作审计和邀请流。

### 这意味着什么

- 如果她用自己的 Apple ID 安装 app，但没有选中和你相同的共享文件夹，她看到的仍然只是她自己的本地书库 / 她自己的 iCloud 数据
- 只要你们双方都把同步目标切到同一个共享文件夹，新增、修改、删除都会合并到同一套书库
- 如果你们仍使用“个人 iCloud”模式，那么数据仍然只在同一 Apple ID 下互通

### 不同 Apple ID 怎么接到同一套书库

1. 由其中一方在 iCloud Drive 里创建一个专用文件夹，比如 `家庭共享书库`
2. 在系统层把这个文件夹共享给另一个 Apple ID
3. 双方在 app 顶部工具栏打开同步目标菜单，选择“共享书库文件夹”
4. 各自选中同一个共享文件夹
5. 之后双方的改动都会通过该文件夹合并

建议：

- 用专门的共享文件夹，不要直接拿整个 iCloud Drive 根目录
- 首次切换后等状态变成“已同步”再开始多人编辑
- 冲突规则仍然是 `updatedAt` / `deletedAt` 较新的版本胜出

### 如果你只是想让她拿你的现有数据做一次测试

当前没有应用内“导出 / 导入 / 分享书库”功能，所以只能用临时方案：

1. 在 Mac 上把本地数据目录打包给她
2. 让她在本地开发环境里替换自己的数据目录后再运行

这属于“一次性拷贝数据”，不是实时共享。现在更合适的方式是直接使用共享文件夹同步。

### 云同步前提

如果要验证真实 iCloud 同步，需要：

- 使用带 iCloud capability 的签名团队
- 保持 `homeLibrary/homeLibrary.entitlements`
- 如果使用“个人 iCloud”模式，在需要同步的设备上登录同一个 Apple ID
- 如果使用“共享书库文件夹”模式，把同一个共享文件夹授权给相关 Apple ID

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
