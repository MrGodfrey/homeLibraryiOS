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

## 运行与调试

### 先知道当前工程的调试策略

当前工程已经按“本地开发优先，云同步单独验证”拆开了：

- `Debug`：不带 `homeLibrary.entitlements`，可以直接做本地开发和真机调试
- `Release`：保留 iCloud entitlement，用于真实 iCloud 同步验证和后续 TestFlight 分发

所以如果你现在看到：

```text
Personal development teams do not support the iCloud capability
```

不要继续在 `Debug` 下验证 iCloud。当前正确做法是：

1. 日常开发先用 `Debug`
2. 本地功能在 simulator / 真机先跑通
3. 等 Apple Developer Program 订阅生效后，再切到 `Release` 验证真实云同步

### 日常开发：用 Simulator 跑 `Debug`

这是最快、最稳定的开发方式。

1. 打开 `homeLibrary.xcodeproj`
2. 选择 `homeLibrary` scheme
3. 确认 `Run` 用的是 `Debug`
4. 运行目标选一个 iPhone / iPad Simulator
5. 点击 `Run`

推荐先验证这些本地功能：

- 启动是否正常
- 搜索、筛选
- 新增书籍
- 编辑书籍
- 删除书籍
- 封面选择与展示
- ISBN 自动补全

在这条路径下，应用会使用本地书库；同步状态显示为“同步未开启”是预期行为，不是 bug。

### `Debug` 时建议怎么查问题

如果你在本地调试中遇到异常，建议按这个顺序处理：

1. 先看 Xcode 的 `Issue navigator`，确认是编译错误、签名错误，还是运行时错误
2. 再看 Xcode 底部调试区输出，确认是不是文件访问、网络请求或 SwiftUI 状态更新问题
3. 如果界面状态不对，先在 app 里点一次刷新按钮
4. 如果本地数据看起来脏了，删除 simulator 里的 app 后重新运行
5. 如果编译缓存异常，执行 `Product > Clean Build Folder`

### 调试时隔离数据（可选）

如果你不想让不同调试会话共用同一份数据，可以在：

`Product > Scheme > Edit Scheme > Run > Arguments > Environment Variables`

里设置这些环境变量：

- `HOME_LIBRARY_STORAGE_NAMESPACE=simulator-debug`
- `HOME_LIBRARY_DISABLE_BUNDLED_SEED=1`
- `HOME_LIBRARY_DISABLE_CLOUD_SYNC=1`

含义：

- `HOME_LIBRARY_STORAGE_NAMESPACE`：给当前调试会话单独开一份本地数据目录
- `HOME_LIBRARY_DISABLE_BUNDLED_SEED=1`：不要自动导入 `SeedBooks.json`
- `HOME_LIBRARY_DISABLE_CLOUD_SYNC=1`：强制只走本地模式

## 真机本地调试

### 在个人团队下把 app 跑到你自己的 iPhone / iPad

即使 Apple Developer Program 订阅还没通过，你也可以先把 `Debug` 装到自己的真机上测试本地功能。

步骤：

1. 在 Xcode 中打开 `Settings > Accounts`，确认已经登录你的 Apple ID
2. 用数据线连接 iPhone / iPad，解锁设备，并在设备上点“信任这台电脑”
3. 打开 target `homeLibrary` 的 `Signing & Capabilities`
4. 勾选 `Automatically manage signing`
5. `Team` 选择你当前的个人团队，例如 `Yu Wang`
6. 如果 `Bundle Identifier` 冲突，就改成你自己唯一的一份，例如 `yu.homeLibrary.dev`
7. 运行配置保持为 `Debug`
8. 在顶部运行目标里选择你的真机
9. 点击 `Run`

第一次真机调试时，你可能还需要在设备上开启开发者模式；系统会提示你重启设备并确认。

在这条路径下，真机上能测的是：

- 列表、搜索、筛选
- 新增 / 编辑 / 删除
- 封面选择
- ISBN 扫码
- 本地持久化

在这条路径下，真机上不能测的是：

- “个人 iCloud” 容器同步

因为当前工程故意把 iCloud entitlement 只保留在 `Release`。

### 真机调试常见问题

- 如果仍然报 iCloud provisioning profile 错误：
  先确认你跑的是 `Debug`，不是 `Release`
- 如果 Xcode 找不到设备：
  重新插线、解锁手机，并确认设备已信任这台 Mac
- 如果签名失败：
  先检查 `Team`，再检查 `Bundle Identifier` 是否唯一
- 如果安装过旧包、界面行为异常：
  先删除设备上的旧 app，再重新运行

## 开发者订阅通过后，如何测试真实云同步

这里说的是：Apple Developer Program 订阅已经生效，并且 Xcode 可以为你的 bundle 正常生成带 iCloud capability 的描述文件。

### 一次性准备

1. 确认你的付费开发者订阅已经生效
2. 在 Xcode 的 `Signing & Capabilities` 中继续使用自动签名
3. `Team` 选择你的付费开发团队
4. 确认 app 使用的 `Bundle Identifier` 是你团队名下可用的一项
5. 确认 iCloud capability 没被删掉，`homeLibrary/homeLibrary.entitlements` 仍然存在

### 当前工程怎么切到云同步调试

因为当前工程只有 `Release` 保留 iCloud entitlement，所以要这样切：

1. `Product > Scheme > Edit Scheme`
2. 选中左侧 `Run`
3. 把 `Build Configuration` 从 `Debug` 改成 `Release`
4. 关闭窗口

建议只在“验证真实云同步”时这样切；日常开发完成后，再切回 `Debug`。

### 验证“个人 iCloud”同步

最稳妥的验证方式是两台真实设备，或者一台 Mac 加一台真实 iPhone / iPad。

前提：

- 两台设备登录同一个 Apple ID
- 两台设备都开启 iCloud Drive
- 两台设备都安装同一版带 iCloud entitlement 的构建

说明：

- 不要用 simulator 作为“个人 iCloud 是否可用”的最终判断，真实验证请以真机 / `My Mac` 为准

操作步骤：

1. 在设备 A 上运行 `Release` 版本
2. 在设备 B 上也运行同一版本
3. 设备 A 新增一本书，确认保存成功
4. 在设备 B 打开 app，或者点一次刷新按钮
5. 确认设备 B 收到新书
6. 再继续验证编辑、删除、封面更新是否同步过去

同步触发时机：

- 启动应用后
- 手动点刷新
- 保存书籍后
- 删除书籍后

同步规则：

- 书籍更新：按 `updatedAt` 更晚的版本胜出
- 书籍删除：按 `deletedAt` 更晚的墓碑胜出

### 验证“共享书库文件夹”同步

这是给不同 Apple ID 共用一套书库用的，不依赖“同一个人同一个 Apple ID”。

操作步骤：

1. 由其中一方在 iCloud Drive 中创建一个专用文件夹，例如 `家庭共享书库`
2. 在系统层把该文件夹共享给另一个 Apple ID
3. 双方都安装 app
4. 双方在 app 顶部工具栏打开“同步目标”菜单
5. 选择“共享书库文件夹”
6. 各自选中同一个共享文件夹
7. 等同步状态变成“已同步”后，再开始多人编辑

建议：

- 不要直接共享整个 iCloud Drive 根目录
- 用专门的共享文件夹
- 第一次切过去后，先做一轮新增 / 编辑 / 删除的冒烟验证

### 云同步调试时怎么判断问题出在哪

- 如果状态是“同步未开启”：
  大概率还在跑 `Debug`，或者签名没拿到 iCloud entitlement
- 如果状态是“同步失败”：
  先看弹窗错误，再检查 iCloud 登录状态、共享文件夹权限、以及设备网络
- 如果一台设备改了，另一台没看到：
  先在第二台设备点刷新，再确认两边是不是同一个 Apple ID / 同一个共享文件夹
- 如果只是想测本地功能：
  不要在云同步问题上卡住，切回 `Debug` 继续开发

## 如何分发给朋友测试

### 方式 1：把源码给对方，让她自己用 Xcode 跑

适合对方有 Mac 和 Xcode，也愿意自己处理签名。

步骤：

1. 把仓库发给她
2. 她打开 `homeLibrary.xcodeproj`
3. 她在自己的 Xcode 里登录自己的 Apple ID
4. 在 `Signing & Capabilities` 里选择她自己的 Team
5. 如果签名冲突，就把 `Bundle Identifier` 改成她自己的唯一值
6. 如果她只是测本地功能，直接跑 `Debug`
7. 如果她要测自己的 iCloud，同步配置也要改成她自己的 bundle / iCloud 容器

这种方式下，她测试的是她自己签名的一份独立 app。

### 方式 2：用 TestFlight 分发给朋友

这是最推荐的方式，适合“朋友不看源码，只想安装测试版”。

#### 第一步：准备 App Store Connect 记录

1. 确认 Apple Developer Program 订阅已生效
2. 登录 App Store Connect
3. 创建一个 app 记录，并使用和 Xcode 工程一致的 `Bundle Identifier`

#### 第二步：从 Xcode 归档并上传构建

1. 在 Xcode 中选择一个真实设备，或者 `Any iOS Device`
2. 确认当前签名、bundle id、版本号都正确
3. 选择 `Product > Archive`
4. Archive 完成后会打开 `Organizer`
5. 在 `Organizer` 中选择刚生成的 archive
6. 点击 `Distribute App`
7. 选择 `App Store Connect`
8. 继续上传，等待 Apple 处理构建

注意：

- 如果你要给“朋友”这种外部测试者装，请走正常的 TestFlight / App Store Connect 上传流程
- 不要只做 `TestFlight Internal Only` 上传，否则这个构建只能给内部测试者使用

#### 第三步：在 TestFlight 邀请测试者

上传完成后，进入 App Store Connect 的 `TestFlight` 页面。

有两种测试者：

- 内部测试者：你 App Store Connect 团队里的成员
- 外部测试者：你的朋友、家人、非团队成员

如果你要邀请朋友，按下面做：

1. 先确认构建已经处理完成
2. 在 `TestFlight` 里先创建内部测试组
3. 再创建外部测试组
4. 把构建添加到外部测试组
5. 通过邮箱邀请，或者生成公开邀请链接

说明：

- 第一次给外部测试者分发某个构建时，通常还要经过一次 Beta App Review
- 审核通过后，朋友会收到 TestFlight 邀请
- 朋友在自己的 iPhone 上安装 `TestFlight` app 后，就可以接受邀请并安装

### 方式 3：你自己先做多设备同步验证

如果你的目标只是验证“同一套书库能不能跨设备同步”，最快的办法不是先发给别人，而是先在你自己的设备上完成闭环：

- `My Mac`
- 你的 iPhone / iPad

两边安装同一个带 iCloud entitlement 的构建，并使用同一个 Apple ID。

## 如果朋友要和你共享同一套数据

这里要把“安装 app”与“共享同一套书库”分开理解。

### 当前已经支持

- 同一个 Apple ID 通过“个人 iCloud”跨设备同步
- 不同 Apple ID 通过“共享书库文件夹”维护同一套书库

### 当前还不支持

- 在 app 内邀请成员加入家庭书库
- 给成员设置只读 / 可编辑 / 可删除权限

也就是说：

- 如果朋友只是装了你的 app，但没有选中同一个共享文件夹，她看到的只是她自己的数据
- 如果你们双方都切到同一个共享文件夹，新增、修改、删除会合并到同一套书库
- 如果你们仍使用“个人 iCloud”模式，那么数据只会在同一个 Apple ID 下互通

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
2. 第一次装到真机时，按系统要求完成设备信任和开发者模式设置
3. 安装完成后，手机上的操作和 Mac 基本一致：
   - 搜索、筛选
   - 添加书籍
   - 扫码录入 ISBN
   - 编辑书籍
   - 删除书籍
4. 如果你希望手机和电脑看到同一套数据，需要两边都登录同一个 Apple ID，并且 iCloud 可用

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
