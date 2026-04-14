# homeLibrary 开发说明（面向有 Python 基础、刚接触 iOS 的开发者）

这份文档的目标不是只告诉你“这个项目现在有什么文件”，而是让你看完之后，知道这种 iOS 应用为什么这么搭、以后你自己要怎么继续写、哪些地方是当前方案的边界、如果规模变大会先在哪里出问题。

我会默认你已经有 Python 基础，但没有 iOS 开发经验。所以文中会尽量把 Swift / SwiftUI / iOS 工程里容易卡住的新名词解释清楚，并用接近 Python 工程思维的方式来描述。

---

## 1. 先用一句话概括这个项目

`homeLibrary` 是一个用 **SwiftUI** 写的家庭藏书管理应用。它的核心设计是：

1. 用 `SwiftUI` 写界面。
2. 用 `LibraryStore` 统一管理界面状态和业务动作。
3. 用自定义的文件目录结构做本地持久化，而不是 Core Data / SwiftData。
4. 用“本地目录”和“云端目录”之间的双向合并，做一个轻量同步层。
5. 通过 `SeedBooks.json` 支持首次导入历史数据。

从工程分层上看，它更像一个：

- `SwiftUI 界面层`
- `轻量 ViewModel / Store 层`
- `文件存储层`
- `同步层`
- `少量外部服务层（ISBN 查询）`

的组合。

如果你熟悉 Python，可以先把它粗略类比成：

- `SwiftUI View` 类似“声明式模板 + 状态驱动渲染”
- `LibraryStore` 类似“一个被 UI 订阅的 service/view-model”
- `LibraryDiskStore` 类似“文件仓储层 repository”
- `LibrarySyncEngine` 类似“同步 worker / merge engine”

---

## 2. 这个工程在仓库里长什么样

仓库根目录的关键内容如下：

```text
homeLibrary/
├── homeLibrary.xcodeproj/         # Xcode 工程配置
├── homeLibrary/                   # App 主 target 的源码与资源
├── homeLibraryTests/              # 单元测试
├── homeLibraryUITests/            # UI 自动化测试
├── scripts/                       # 辅助脚本
├── docs/                          # 项目补充文档
├── README.md
├── plan.md
├── log.md
└── forDeveloper.md                # 这份文档
```

### 2.1 每个目录的职责

#### `homeLibrary.xcodeproj`

这是 **Xcode 工程文件**。  
你可以把它理解成 iOS 世界里的“IDE 工程描述文件”，它负责定义：

- 有哪些 target
- 用什么 build configuration
- 哪些源码和资源会被打包
- bundle id 是什么
- 是否启用 entitlement（能力声明）
- 测试 target 如何依赖 app target

这个项目当前有 3 个 target：

- `homeLibrary`
- `homeLibraryTests`
- `homeLibraryUITests`

以及 2 个 build configuration：

- `Debug`
- `Release`

#### `homeLibrary/`

这是主应用的源码目录，也是你未来大部分时间会改的地方。

关键文件：

- `homeLibraryApp.swift`：应用入口
- `ContentView.swift`：主页面，书籍列表、筛选、搜索、同步入口
- `BookEditorView.swift`：新增/编辑书籍的表单页
- `Book.swift`：数据模型定义
- `LibraryStore.swift`：核心状态管理与业务操作
- `LibraryPersistence.swift`：本地文件存储逻辑
- `LibrarySync.swift`：同步引擎
- `LibrarySyncSettings.swift`：同步目标配置、共享文件夹 bookmark 持久化
- `LibraryAppConfiguration.swift`：运行时配置装配
- `ISBNLookupService.swift`：外部 ISBN 查询
- `ISBNScannerView.swift`：扫码封装
- `SeedBooks.json`：首次启动可导入的种子数据
- `Info.plist`：权限文案等基础配置
- `homeLibrary.entitlements`：iCloud 等系统能力声明

#### `homeLibraryTests/`

单元测试。  
更像 Python 里的 `tests/unit`。

当前主要覆盖：

- 搜索/筛选逻辑
- 表单标准化
- ISBN 提取
- 同步设置持久化
- 文件存储
- 同步合并

#### `homeLibraryUITests/`

UI 自动化测试。  
更像“驱动真实 App 界面”的端到端测试。

它会启动应用，然后像用户一样点按钮、输入内容、保存、搜索、删除。

#### `scripts/`

目前最重要的是：

- `import_from_cloudflare.mjs`

它不是 App 运行时依赖，而是一个离线导入脚本，用来把旧系统里 Cloudflare D1/R2 的数据导出成 `SeedBooks.json`。

---

## 3. 一个很重要的点：这个 Xcode 工程不是手动逐个加文件的

这个项目用了 Xcode 较新的 **File System Synchronized Group** 机制。

这意味着：

1. `homeLibrary/`、`homeLibraryTests/`、`homeLibraryUITests/` 这几个目录直接和文件系统同步。
2. 你往目录里加新文件，Xcode 通常会自动把它看见，不需要像老工程那样每次手动拖进项目。
3. 这也是为什么 `SeedBooks.json` 这种资源可以直接放在 `homeLibrary/` 里，被主 target 使用。

这点非常值得你记住，因为很多旧教程会告诉你“加文件要手动进 Xcode 点很多次”。这个项目现在不完全是那种老方式了。

### 优点

- 目录结构更接近真实文件系统
- 减少 Xcode 工程文件里无意义的文件条目
- 新增文件时更省事

### 缺点

- 需要较新的 Xcode
- 如果你看的教程比较老，会发现工程文件长得不一样

---

## 4. 应用运行时，数据到底存在哪里

你问“文件存在哪里”，要分成三种：

1. **源码文件** 存在仓库里
2. **App 运行时本地数据** 存在设备沙盒里
3. **同步数据** 存在 iCloud 容器或用户选择的共享文件夹里

### 4.1 源码文件在哪里

源码就是你现在看到的仓库：

- 主代码：`/Users/wangyu/code/homeLibraryApp/homeLibrary/homeLibrary/`
- 测试：`/Users/wangyu/code/homeLibraryApp/homeLibrary/homeLibraryTests/`
- UI 测试：`/Users/wangyu/code/homeLibraryApp/homeLibrary/homeLibraryUITests/`

### 4.2 本地运行数据在哪里

本地数据根目录是通过 `LibraryAppConfiguration.live()` 算出来的。

默认逻辑是：

1. 取系统 `Application Support` 目录
2. 在其下创建 `homeLibrary/`
3. 把它作为本地书库根目录

也就是说，逻辑上的根目录是：

```text
Application Support/homeLibrary/
```

这里说的是“逻辑位置”。  
真正到设备或模拟器上时，它还会包在各自的 sandbox 里。

常见情况：

- iOS Simulator：在某个 app sandbox 的 `Library/Application Support/homeLibrary/`
- 真机 iPhone：也在 app sandbox 的 `Library/Application Support/homeLibrary/`
- macOS 运行：通常在用户目录下的 `Application Support/homeLibrary/`

你在调试时真正看到的完整路径一般会更长，例如模拟器里常会像这样：

```text
~/Library/Developer/CoreSimulator/Devices/<device-id>/data/Containers/Data/Application/<app-id>/Library/Application Support/homeLibrary/
```

如果设置了环境变量 `HOME_LIBRARY_STORAGE_NAMESPACE`，会变成：

```text
Application Support/homeLibrary/<namespace>/
```

这主要用于：

- UI 测试隔离
- 调试不同会话的数据
- 避免测试互相污染

### 4.3 本地书库目录结构

这个项目现在不是一个大 JSON 文件，而是一个“目录 + 多文件”的结构：

```text
Application Support/homeLibrary/
├── manifest.json
├── books/
│   └── <book-id>.json
├── covers/
│   └── <cover-asset-id>.bin
├── deletions/
│   └── <book-id>.json
└── books.legacy.backup.json   # 只在迁移旧数据时出现
```

各目录含义：

- `manifest.json`：库级元信息，比如 schemaVersion、最后一次成功同步时间
- `books/`：每本书一个 JSON 文件，只存元数据
- `covers/`：封面二进制文件
- `deletions/`：删除墓碑（tombstone）
- `books.legacy.backup.json`：旧版单文件数据的备份

### 4.4 云端数据在哪里

当前项目支持两种同步目标：

#### 模式 A：个人 iCloud

数据会放在：

```text
iCloud 容器 / Documents / homeLibrarySync/
```

容器标识在代码里是：

```text
iCloud.yu.homeLibrary
```

#### 模式 B：共享书库文件夹

用户通过系统文件选择器选中一个文件夹后，这个文件夹本身就会成为同步根目录。

也就是说，**本地目录结构和云端目录结构是一模一样的**。  
同步本质上是在合并两个 `LibraryDiskStore`。

### 4.5 同步目标配置存在哪里

同步目标不是写在文件里，而是写在 `UserDefaults` 里。

会存这些信息：

- 当前模式：个人 iCloud / 共享文件夹
- 共享文件夹 bookmark 数据
- 共享文件夹显示名

这很像你在 Python 桌面应用里把用户偏好存在一个轻量配置存储里，而不是专门建一张业务表。

---

## 5. 从入口开始看：App 是怎么启动的

应用入口在 `homeLibraryApp.swift`。

核心逻辑非常少：

1. 创建一个 `LibraryStore(configuration: .live())`
2. 把这个 store 注入 `ContentView`

也就是说，App 启动阶段只做了两件事：

- 拼装运行时依赖
- 把状态中心交给界面

### 5.1 `@main`

`@main` 表示程序入口。  
你可以把它类比成 Python 里的：

```python
if __name__ == "__main__":
    main()
```

只是 SwiftUI 的入口不是一个裸函数，而是一个符合 `App` 协议的结构体。

### 5.2 `@StateObject`

`@StateObject` 的意思是：这个对象由当前 View 生命周期“拥有”。

这里为什么用它？

因为 `LibraryStore` 需要在整个 App 生命周期里稳定存在，不能因为页面刷新被反复创建。

如果用错成普通变量，你会遇到典型问题：

- 页面一刷新，store 重建
- 数据重新加载
- 搜索条件丢失
- 异步状态乱掉

这和 Python Web 或桌面开发里“不要在每次渲染时重新 new 一个全局状态容器”是同一个道理。

---

## 6. 当前项目的总体架构图

可以把它理解成下面这个流向：

```text
homeLibraryApp
    ↓
ContentView / BookEditorView / ISBNScannerView
    ↓
LibraryStore   ← 负责界面状态、业务动作、错误提示、同步触发
    ↓
LibraryDiskStore / LibrarySyncEngine / ISBNLookupService
    ↓
本地文件系统 / iCloud 容器 / 共享文件夹 / 外部 ISBN API
```

更细一点：

```text
UI 层
  - ContentView
  - BookEditorView
  - ISBNScannerView

状态与业务层
  - LibraryStore

配置层
  - LibraryAppConfiguration
  - LibrarySyncSettingsStore

数据层
  - Book / BookDraft / Tombstone
  - LibraryDiskStore
  - LibraryJSONCodec

同步层
  - CloudSyncConfiguration
  - LibrarySyncEngine

外部服务
  - ISBNLookupService
```

---

## 7. 为什么说 `LibraryStore` 是这个项目的核心

`LibraryStore.swift` 是全项目最重要的文件。

它承担了几个职责：

1. 保存页面需要观察的状态
2. 提供页面触发的业务动作
3. 负责本地加载
4. 负责保存和删除
5. 负责触发同步
6. 负责把错误转成可读提示
7. 缓存封面，减少重复读盘

### 7.1 它管理了哪些状态

例如：

- `books`
- `searchText`
- `activeTab`
- `isLoading`
- `isSaving`
- `syncStatus`
- `syncTarget`
- `alertMessage`

这些字段带了 `@Published` 时，意味着：

- 值变化了
- SwiftUI 会收到变更通知
- 界面会自动重算并刷新

这就是 SwiftUI 的“状态驱动 UI”。

### 7.2 对 Python 开发者怎么理解

你可以把 `ObservableObject + @Published` 粗略类比为：

- 一个带事件通知的状态对象
- UI 订阅它的字段变化
- 字段更新后，界面自动重渲染

如果你写过前端，会更像：

- React state/store
- Vue 响应式状态

如果你只熟悉 Python，也可以把它理解成“带订阅机制的 service object”。

### 7.3 为什么这里没有把逻辑全塞进 View

因为一旦把保存、删除、同步、错误处理都写在 View 里，会马上出现几个问题：

- View 太长，难读
- 逻辑难测试
- 复用困难
- 异步流程很乱

所以当前项目用了一个很实用的做法：

- View 负责展示与触发
- Store 负责业务动作和状态

这不是严格意义上的复杂架构，但对当前项目规模很合适。

---

## 8. 数据模型是怎么设计的

主要模型在 `Book.swift`。

### 8.1 `Book`

`Book` 是主业务实体，也就是一本书。

字段大致是：

- `id`
- `title`
- `author`
- `publisher`
- `year`
- `isbn`
- `location`
- `coverAssetID`
- `createdAt`
- `updatedAt`

### 8.2 为什么 `Book` 用 `struct`，`LibraryStore` 用 `class`

这是 Swift 里很重要的工程习惯。

#### `Book` 用 `struct`

因为它是一个“数据值”。

优点：

- 值语义，更安全
- 传来传去时不容易被意外共享修改
- 更适合作为 Codable 模型

这和 Python 里把简单数据放进 dataclass，而不是把所有东西都做成大对象，有一点相似。

#### `LibraryStore` 用 `class`

因为它是一个“共享的、持续存在的、可变的状态中心”。

这类对象需要引用语义。

### 8.3 `BookDraft`

`BookDraft` 不是正式入库对象，而是表单编辑态。

它的作用是：

- 承载用户输入中的中间状态
- 允许封面还没落盘
- 保存前做标准化

这是非常好的习惯。  
不要让“界面正在编辑的脏数据”直接等于“最终持久化模型”。

### 8.4 `LegacyBook`

这是旧数据格式，用于迁移。

旧格式里封面是：

- 直接放在 `coverData`
- 和图书元数据塞在同一个 JSON 里

当前项目保留它，是为了兼容历史数据。

### 8.5 `BookDeletionTombstone`

这是删除墓碑。

很多初学者一开始会觉得：删除就删了，为什么还要存个删除记录？

原因在同步。

假设：

1. 设备 A 删除了一本书
2. 设备 B 还保留旧文件
3. 如果没有 tombstone，下一次同步时 B 的旧书可能又被“同步回来”

所以删除墓碑的本质是：

- “这本书不是丢了”
- “而是明确被删除过”

这和分布式系统里的 delete marker 是同一种思路。

---

## 9. 持久化层为什么这样设计

本地存储在 `LibraryPersistence.swift`。

这里最重要的类型是 `LibraryDiskStore`。

### 9.1 `LibraryDiskStore` 做了什么

它是一个面向文件系统的仓储层，负责：

- 初始化目录结构
- 读取所有书籍和 tombstone
- 写入/更新一本书
- 删除一本书
- 写封面文件
- 读取封面文件
- 垃圾回收无引用封面
- 迁移旧格式数据
- 维护 manifest

### 9.2 为什么不用一个大 JSON 文件

旧方案就是一个大 JSON 文件，并且封面也塞进去。

问题会很快出现：

1. 任意改一本书，都要重写整个文件
2. JSON 越来越大
3. 二进制封面混在 JSON 里，读写很重
4. 同步粒度太粗
5. 冲突处理很难做

所以当前设计把它拆成：

- 每本书一个 JSON
- 每张封面一个二进制文件
- 删除单独一个 tombstone 文件

这是一个典型的“把数据拆细，降低冲突面”的策略。

### 9.3 为什么封面单独存

现在 `Book` 里只保留 `coverAssetID`，不直接带 `coverData`。

好处：

1. 图书元数据文件小很多
2. 改书名不会重写封面
3. 同步更细粒度
4. 封面可以去重

### 9.4 `coverAssetID` 为什么用哈希而不是 UUID

当前实现里，封面资源 ID 是通过图片二进制算 `SHA256` 得到的。

好处：

1. 同一张图得到同一个 asset id
2. 天然去重
3. 可以避免重复存同样的封面

如果用 UUID：

- 实现更简单
- 但相同图片会被重复保存很多份

### 9.5 `manifest.json` 的作用

它当前主要记录：

- schemaVersion
- initializedAt
- lastLocalMutationAt
- lastSuccessfulSyncAt

为什么要有它？

因为一个成熟一点的本地存储，最好有一个“库级元信息文件”，否则以后升级格式时很被动。

它相当于在为将来的迁移留接口。

### 9.6 自定义日期编解码为什么值得保留

`LibraryJSONCodec` 自定义了 ISO8601 日期编解码，并兼容：

- 带小数秒
- 不带小数秒

这不是小题大做，而是在解决一个真实问题：

- 老数据格式未必完全一致
- 不兼容的时间格式会直接导致解码失败

很多工程一开始嫌麻烦，后面一旦数据进化，就会在兼容性上交学费。

---

## 10. 旧数据是怎么迁移进来的

首次启动时，`LibraryDiskStore.prepareForUse()` 会做初始化判断。

大致流程：

1. 确保目录存在
2. 如果 `manifest.json` 已存在，说明库已经初始化过，直接返回
3. 如果已经有结构化数据，也只补 manifest
4. 如果有旧版 `books.json`，优先迁移它
5. 否则如果允许种子数据，并且 bundle 里有 `SeedBooks.json`，迁移它
6. 迁移完成后做一次封面垃圾回收

### 10.1 为什么旧版本地数据优先于 `SeedBooks.json`

因为本地数据更像“用户真实操作后的结果”，而种子文件只是导入源。

如果反过来优先种子文件，就可能把用户本地历史覆盖掉。

### 10.2 `SeedBooks.json` 是什么

它是一个“打包进 App 的初始数据文件”。

当前项目里，它不是手写的，而是通过：

- `scripts/import_from_cloudflare.mjs`

从旧系统导出来的。

也就是说，`SeedBooks.json` 更像是：

- 一个离线导出快照
- 一个 bootstrap 数据源

而不是你的主数据库。

---

## 11. 同步层是怎么工作的

同步相关逻辑主要在：

- `LibrarySync.swift`
- `LibrarySyncSettings.swift`

### 11.1 先理解一个关键事实

当前项目的同步不是 CloudKit 数据库，也不是后端 API。

它的本质是：

- 本地有一个 `LibraryDiskStore`
- 云端也映射成一个 `LibraryDiskStore`
- 然后在两者之间做合并

所以你可以把它理解成：

“同一套文件格式，在两个位置各有一份，然后做 merge”

### 11.2 合并规则

`LibrarySyncEngine` 的核心规则非常直接：

#### 书籍更新

同一个 `book.id` 两边都存在时：

- `updatedAt` 更新的胜出
- 如果 `updatedAt` 一样，再看 `createdAt`

这就是典型的 **Last Write Wins**（最后写入胜出）。

#### 删除

如果某一边有 tombstone：

- 取 `deletedAt` 更新的 tombstone
- 如果 tombstone 比书的新，就删除书并保留 tombstone

#### 封面

如果胜出的书有 `coverAssetID`：

- 本地缺这个封面，就从云端拷贝
- 云端缺这个封面，就从本地拷贝

### 11.3 为什么现在的同步方案对“两个人共享书库”是够用的

因为当前需求相对朴素：

1. 参与者很少
2. 每条记录字段不多
3. 并发编辑概率不高
4. 接受最终一致性
5. 不需要复杂权限模型

对于家庭场景，`最后写入胜出 + 删除墓碑 + 封面补齐`，通常已经能覆盖大部分使用情况。

### 11.4 这个方案的优点

1. 结构简单
2. 不需要后端服务
3. 本地优先，离线可用
4. 数据格式透明，容易排查
5. 调试时可以直接看文件

### 11.5 这个方案的缺点

1. 没有真正的字段级冲突合并
2. 没有操作历史
3. 没有用户身份体系
4. 没有精细权限控制
5. 没有服务端权威真相源
6. 文件数量多时，同步成本会上升

### 11.6 如果以后参与者从 2 个变成更多人，问题会先出在哪里

这是你特别关心的点，我单独展开。

#### 问题 1：冲突会明显增多

比如：

- A 改书名
- B 改作者
- 两边几乎同时保存

当前规则只能保留“时间更新的一整条记录”，不会做字段级 merge。  
所以一个人的修改可能把另一个人的修改整体盖掉。

#### 问题 2：删除语义会变得更敏感

比如：

- A 删除一本书
- B 离线编辑同一本书
- 两边再同步

最后结果取决于 `deletedAt` 和 `updatedAt` 谁更新。  
这在家庭两人里还能接受，但参与者一多，认知成本会上升。

#### 问题 3：同步复杂度会升高

当前同步基本是：

- 读本地快照
- 读云端快照
- 取所有 ID 的并集
- 逐个合并

这在几百本书时没问题。  
但如果变成几万条记录、很多封面文件，性能和同步时长都会受影响。

#### 问题 4：共享文件夹权限管理不够强

当前共享模式依赖：

- 用户手动选中共享文件夹
- 系统授权
- bookmark 持久化

这不是一个强身份系统。  
它更像“大家都能接触同一个目录”，而不是“系统知道谁是谁、谁能改什么”。

#### 问题 5：没有审计与回滚

如果多人共同维护一个库，通常很快就会需要：

- 谁改了什么
- 什么时候改的
- 能不能回滚
- 能不能查看历史版本

当前方案不提供这些能力。

### 11.7 如果未来真要做多人协作，更合适的方向是什么

如果是 3-5 人以上、且希望长期稳定协作，建议考虑：

#### 方案 A：CloudKit

适合：

- 继续留在 Apple 生态
- 原生 iOS/macOS 为主
- 不想自己维护服务器

优点：

- Apple 官方同步体系
- 记录级数据模型更自然
- 比“共享文件夹 + 合并文件”更像数据库

缺点：

- 学习成本更高
- 共享模型和调试都比当前复杂
- 跨平台能力有限

#### 方案 B：自建后端

例如：

- FastAPI / Django
- PostgreSQL
- 对象存储保存封面

优点：

- 真正的多人协作模型
- 容易做用户、权限、审计、搜索、统计
- 可以给 Web / Android / 小程序共用

缺点：

- 成本最高
- 你要维护服务端
- 离线同步设计会变复杂

如果未来想把它从“家庭应用”变成“多人共享产品”，最终大概率要走这条路。

---

## 12. 为什么当前项目没有用 SwiftData / Core Data

这是一个非常好的问题。

### 12.1 当前方案：自定义文件存储

#### 优点

- 数据结构透明
- 容易导入旧 JSON
- 容易做文件级同步
- 读写逻辑完全自己可控
- 对初学者更容易理解

#### 缺点

- 需要自己写迁移
- 需要自己管一致性
- 查询能力弱
- 记录一多后性能和复杂度上升

### 12.2 SwiftData

SwiftData 是 Apple 新一代的本地持久化框架，偏现代、偏 SwiftUI 生态。

#### 优点

- 和 SwiftUI 集成好
- 建模比 Core Data 更现代
- 对简单 CRUD 应用很省事

#### 缺点

- 对复杂同步和自定义迁移，你还是得理解底层
- 当前这个项目已经有历史 JSON 数据和自定义同步格式，切过去不一定省事

### 12.3 Core Data

Core Data 是 Apple 的经典持久化框架。

#### 优点

- 成熟
- 查询能力更强
- 大量资料和实战经验

#### 缺点

- 学习曲线比当前方案陡
- 对初学者不够直观
- 和现有基于文件的同步方案不天然对齐

### 12.4 SQLite / GRDB 一类方案

如果以后数据量明显上升，其实非常值得考虑。

#### 优点

- 查询、排序、筛选更强
- 单机性能更稳定
- 结构化数据管理更成熟

#### 缺点

- 你要自己设计更多数据库层
- 与当前“目录镜像同步”模型不直接兼容

### 12.5 为什么当前项目的选择是合理的

因为它现在处在一个非常明确的阶段：

- 数据模型不复杂
- 用户量极小
- 重点是可用、可迁移、可同步
- 不是一个海量数据 App

在这个阶段，自定义文件存储是一个务实选择。

---

## 13. 界面层是怎么组织的

### 13.1 `ContentView`

主页面负责：

- 展示列表
- 搜索
- 地点筛选
- 刷新
- 切换同步目标
- 弹出新增/编辑页
- 删除确认
- 错误提示

它本身不直接写磁盘，只通过 `store` 调业务方法。

### 13.2 `BookEditorView`

表单页负责：

- 输入 ISBN
- 自动补全
- 扫码
- 编辑书名/作者/出版社/年份/所在地
- 选择封面
- 保存

它内部持有一个 `BookDraft`，用户点保存时，把 draft 交给 `store.saveBook(...)`。

这是一个很关键的思想：

- 编辑态和持久化态分离

### 13.3 `ISBNScannerView`

这是对系统扫码能力的封装。

在 iOS 上用了：

- `VisionKit`
- `DataScannerViewController`

如果平台不支持，就回退成一个不会真正扫描的占位实现。

这就是 **条件编译**。

### 13.4 条件编译是什么

例如代码里的：

- `#if canImport(UIKit)`
- `#if canImport(AppKit)`
- `#if canImport(VisionKit)`

表示：

- 在某个平台能用这个框架时，编译这一段
- 不能用时，编译另一段

这就是同一套代码同时支持 iOS / macOS 的常见方式。

---

## 14. SwiftUI 和传统命令式 UI 的差别

如果你以前没写过 iOS，很容易先在思维上卡住。

### 14.1 SwiftUI 是声明式 UI

你不是去命令系统：

- “创建一个 label”
- “再修改 label 的 text”
- “再手动刷新列表”

而是描述：

- 当 `store.visibleBooks` 是什么时，界面就应该长什么样

也就是说：

**状态变了，界面自动跟着变。**

### 14.2 一个更像 Python 的类比

你可以把 SwiftUI `body` 理解成一个：

- 输入是当前状态
- 输出是目标界面树

的纯函数风格描述。

虽然实际内部比这复杂，但这个理解对入门很有帮助。

### 14.3 为什么这对工程结构有影响

因为一旦 UI 是“状态驱动”，你就会很自然地需要：

- 一个清晰的状态源
- 一个地方负责异步加载
- 一个地方负责业务动作

这也是为什么 `LibraryStore` 会变成这个项目的中心。

---

## 15. 并发、主线程、`@MainActor`、`Task.detached` 是什么

这是 Swift 新手常卡的地方。

### 15.1 为什么 UI 操作要在主线程

和几乎所有 GUI 框架一样：

- UI 更新要在主线程进行

Swift 里现在更常见的表达是：

- `@MainActor`

意思是：

- 这段代码应该在主 actor 上运行
- 对 UI 状态更安全

### 15.2 为什么当前项目把 `LibraryStore` 标成 `@MainActor`

因为它直接管理：

- `@Published` 状态
- UI 会订阅的字段

所以让它待在主 actor 上是合理的。

### 15.3 为什么 `LibraryDiskStore` 相关操作又经常放进 `Task.detached`

因为文件 I/O 可能慢。

如果你直接在主 actor 上做：

- 读所有 JSON
- 写大图片
- 遍历目录

界面可能卡顿。

所以当前项目的做法是：

1. UI / store 仍在主 actor
2. 真正的磁盘工作扔给 `Task.detached(priority: .utility)`
3. 结果回来后再更新 UI 状态

这和 Python 里：

- 主线程负责界面
- 后台线程/worker 负责重 I/O

是同一个思想。

### 15.4 为什么代码里会出现很多 `nonisolated`

这是当前工程一个非常值得注意的细节。

工程的 build setting 里启用了：

- `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`

这会让很多声明默认更偏向主 actor 隔离。

但像：

- `Book`
- `LibraryDiskStore`
- 工具方法

这些东西并不应该只能在主线程用。  
否则你就没法优雅地放到后台任务里执行。

所以作者显式加了很多 `nonisolated`，意思是：

- 这些声明不属于主 actor
- 可以在后台安全调用

### 15.5 这种设置的优点和代价

#### 优点

- UI 相关代码默认更安全
- 不容易忘记主线程约束

#### 代价

- 你要更清楚哪些类型是 UI 的，哪些是纯数据/工具
- 新手一开始会觉得 `nonisolated` 比较绕

这是一个“偏严格但更安全”的工程风格。

---

## 16. 外部服务层：ISBN 自动补全是怎么接的

`ISBNLookupService.swift` 提供了外部书籍信息查询。

策略是：

1. 先把 ISBN 标准化
2. 先查 Google Books
3. 查不到再查 OpenLibrary
4. 还查不到就报“未找到”

### 为什么这样设计

因为：

- 单一外部接口不稳定
- 不同接口覆盖率不同

串联两个公开来源，是一个成本很低但实用的提高成功率的方法。

### 优点

- 简单
- 无需自建元数据服务
- 开发快

### 缺点

- 依赖外部网络
- 第三方接口格式可能变化
- 查询质量受第三方数据源影响

如果以后这个 App 真产品化，最好把图书元数据查询收敛成你自己的后端接口，或者至少做一层中间缓存。

---

## 17. 权限配置和 Entitlements 是什么

### 17.1 `Info.plist`

当前项目的 `Info.plist` 里主要有两条权限说明：

- 相机权限：用于扫码 ISBN
- 相册权限：用于选择封面

在 iOS 里，这种权限文案必须提供。  
否则即使代码能编译，运行到权限请求时也会出问题。

### 17.2 `entitlements`

`homeLibrary.entitlements` 不是普通配置文件，它是“系统能力声明”。

当前主要用于：

- iCloud 容器
- ubiquity / CloudDocuments

你可以把它理解成：

- “这个 App 申请了哪些系统级能力”

### 17.3 为什么当前工程把 iCloud entitlements 放在 Release，而不是 Debug

这是当前工程一个很务实的决定。

原因是：

- 日常开发大多数时候只需要本地功能
- 个人开发团队常常会遇到 iCloud capability 限制
- 把 Debug 保持得更轻，可以让本地开发和测试更顺

所以当前策略是：

- `Debug`：偏本地开发
- `Release`：带 iCloud 能力，做真实同步验证

### 这种做法的优点

- 本地开发成本低
- 模拟器和真机更容易先跑起来

### 这种做法的缺点

- Debug 和 Release 行为不是完全一致
- 测同步时要更有意识地切配置

对当前项目来说，这个取舍是合理的。

---

## 18. 测试层为什么这样设计

### 18.1 单元测试

单元测试主要验证：

- 纯逻辑
- 本地存储
- 同步规则

这部分对应 Python 里的 pytest 单测。

它的重要性在于：  
同步和持久化这两层，一旦出错，很容易不是“崩一下”，而是“数据悄悄错了”。  
而这类 bug 最适合单元测试。

### 18.2 UI 测试

UI 测试做了真实用户流程：

- 启动
- 新增
- 搜索
- 编辑
- 删除

这很重要，因为 SwiftUI 页面层面的问题，很多不是纯逻辑测试能发现的。

### 18.3 为什么测试要注入环境变量

UI 测试里会设置：

- `HOME_LIBRARY_STORAGE_NAMESPACE`
- `HOME_LIBRARY_DISABLE_BUNDLED_SEED`
- `HOME_LIBRARY_DISABLE_CLOUD_SYNC`

这么做是为了：

1. 每次测试用独立数据目录
2. 不受种子数据影响
3. 不依赖云同步

这是很标准的工程思路：  
**让测试环境可控、可重复、可隔离。**

如果你以后自己写 iOS 应用，这个技巧非常值得保留。

---

## 19. 这个项目从零开始，大致是按什么顺序搭出来的

如果你以后想自己写一类相似应用，我建议按照当前项目反映出来的正确顺序来理解，而不是一上来就研究某个局部控件。

### 第 1 步：先建一个最小可运行 SwiftUI App

只需要：

- 一个 `App`
- 一个根 `View`

目标不是“功能完整”，而是先把工程跑起来。

### 第 2 步：先定义业务模型

比如这里先有：

- `Book`
- `BookLocation`
- `BookDraft`

原因是：  
如果数据模型没想清楚，你后面页面、存储、同步都会反复返工。

### 第 3 步：先做本地可用，再做同步

这是当前项目最值得学习的顺序。

为什么？

因为同步永远是放大器：

- 本地结构没想清楚，同步只会让问题翻倍
- 本地 CRUD 都没稳，同步只会让调试极其痛苦

所以正确顺序通常是：

1. 本地数据结构
2. 本地增删改查
3. 再叠加同步

### 第 4 步：在页面和业务之间放一个 store

这样可以避免：

- 所有 View 都自己直接读写文件
- 异步逻辑散一地

### 第 5 步：为历史数据和未来扩展预留迁移点

比如这里的：

- `LegacyBook`
- `manifest.json`
- `schemaVersion`

这些设计在项目小的时候看起来“多此一举”，但一旦项目开始迭代，你会感谢早期的自己。

### 第 6 步：最后补测试和环境注入

不是说测试要最后才写，而是说：

- 在你已经知道系统关键风险点之后，测试会更有针对性

当前项目就很清晰：

- 文件存储
- 同步合并
- UI 主流程

这些都被补上了。

---

## 20. 以后你自己要怎么继续写这种应用

这里给你一个适合 Python 开发者的实操路线。

### 20.1 先建立几个核心习惯

#### 习惯 1：区分“界面状态”和“持久化对象”

不要把用户正在编辑的一坨输入，直接当数据库对象。

这里的 `BookDraft` 是正确示范。

#### 习惯 2：不要让 View 直接做重 I/O

View 应该：

- 触发动作
- 展示状态

不要：

- 直接遍历目录
- 直接写文件
- 直接写复杂同步逻辑

#### 习惯 3：同步一定建立在稳定的本地模型之上

同步不是第一层，是上层能力。

#### 习惯 4：把可变全局状态收口

当前项目用 `LibraryStore` 收口。  
以后即便你改成别的模式，也要尽量避免状态源分散。

### 20.2 如果你要加一个新功能，建议按这个顺序

比如你想加“图书分类”字段：

1. 先改 `Book` / `BookDraft`
2. 再改 `BookEditorView`
3. 再改 `ContentView` 展示
4. 再确认本地 JSON 编解码没问题
5. 再想同步冲突下如何合并
6. 最后补测试

这个顺序几乎适用于大部分业务字段扩展。

### 20.3 如果你要加一个“复杂功能”，建议先判断它属于哪一层

例如：

- 搜索排序增强：通常是 store / filter 层
- 封面缩略图缓存：通常是数据层 / 缓存层
- 多人权限：通常已经不是本地文件层能优雅解决的事了
- 书单分享链接：可能需要后端

学会先分层，再动手，会少走很多弯路。

---

## 21. 如果让我带一个 Python 开发者从这个项目继续迭代，我会建议这样学

### 第 1 阶段：只学会读工程，不急着改

目标：

- 看懂入口
- 看懂状态流
- 看懂数据落盘位置

你至少要能回答：

- `LibraryStore` 为什么是核心
- 本地文件在哪里
- 同步是怎么触发的

### 第 2 阶段：做纯本地功能

先加一些不碰同步的新字段、新筛选、新展示。

这样你会先适应：

- Swift 语法
- SwiftUI 状态机制
- Codable

### 第 3 阶段：开始理解异步和主 actor

到这里再深入理解：

- `async/await`
- `Task`
- `@MainActor`
- `nonisolated`

### 第 4 阶段：再碰同步

同步是进阶内容。  
不要一上来就改同步，否则很容易把本地和云端一起搞乱。

---

## 22. 当前项目的一些隐性技术决策

这些东西代码里不一定一眼能看出来，但很重要。

### 22.1 没有引第三方库

当前工程基本全是 Apple 自带框架：

- `SwiftUI`
- `Foundation`
- `Combine`
- `PhotosUI`
- `UniformTypeIdentifiers`
- `VisionKit`
- `CryptoKit`

这意味着：

- 依赖简单
- 构建轻
- 可维护性高

但也意味着：

- 某些能力要自己写

### 22.2 搜索是内存中过滤，不是数据库查询

`visibleBooks` 是在内存里对 `[Book]` 做过滤和排序。

优点：

- 简单直接
- 当前数据量足够用

缺点：

- 数据量大时性能会下降

### 22.3 列表加载是全量加载

`loadSnapshot()` 会把所有书都读进来。

对于家庭藏书，这是合理的。  
但如果未来数据量大很多，就需要考虑：

- 分页
- 增量加载
- 索引
- 数据库化

### 22.4 同步触发点是显式的

当前会在这些时机尝试同步：

- 首次加载后
- 手动刷新
- 保存后
- 删除后
- 切换同步目标后

这意味着它不是一个持续后台同步系统，而是一个“关键动作触发同步”的系统。

这对当前项目是简洁和可控的，但也意味着：

- 实时性有限

---

## 23. 和 Python 技术栈做一个对应表

| iOS / Swift 概念 | 你可以先这样理解 |
| --- | --- |
| `struct` | 类似更强约束的 dataclass，偏值对象 |
| `class` | 共享引用对象 |
| `Codable` | 类似“可 JSON 序列化/反序列化模型” |
| `SwiftUI View` | 声明式 UI 描述 |
| `ObservableObject` | 可被界面订阅的状态对象 |
| `@Published` | 字段变更会通知订阅者 |
| `@StateObject` | 当前界面拥有的长期状态对象 |
| `@ObservedObject` | 界面观察、但不拥有的对象 |
| `@MainActor` | 必须回到 UI 主线程/主 actor |
| `Task` | 异步任务 |
| `Task.detached` | 后台独立任务 |
| `UserDefaults` | 轻量本地偏好存储 |
| `Info.plist` | App 基础声明配置 |
| `entitlements` | 系统能力申请文件 |
| `Bundle` | 打包进 App 的资源容器 |
| `PhotosPicker` | 系统图片选择器 |
| `fileImporter` | 系统文件/文件夹选择器 |

这个对应表不是精确定义，但非常适合入门时建立直觉。

---

## 24. 以后如果你自己从零写同类应用，我推荐的技术路线

如果目标还是“个人或家庭使用的 iOS 本地优先应用”，我会建议：

### 路线 A：沿用当前路线

适合：

- 数据量不大
- 需要离线
- 需要简单同步
- 你希望所有数据格式都看得见、能直接检查

做法：

1. SwiftUI
2. 一个中心 store
3. 自定义本地文件存储
4. 必要时再加同步

### 路线 B：SwiftData 本地优先

适合：

- 主要是本地 CRUD
- 不想自己管太多序列化
- 项目没有复杂历史包袱

### 路线 C：后端优先

适合：

- 一开始就多人协作
- 要账号体系
- 要跨平台
- 要运营和审计

对你现在这个项目，我认为当前路线仍然是正确的。

---

## 25. 未来演进建议：如果继续做，我会优先改什么

这不是“必须马上改”，而是下一阶段最值得考虑的方向。

### 优先级 1：把同步冲突说明做得更清楚

当前是最后写入胜出。  
建议未来在界面或日志里更明确地暴露：

- 最近同步时间
- 当前冲突策略
- 最近一次失败原因

### 优先级 2：给封面加缩略图策略

如果封面越来越多，原图直接展示会增加：

- 读盘压力
- 内存压力

### 优先级 3：如果人数增加，尽早决定是否上后端

不要拖到多人协作已经频繁出问题时才重构。  
这类迁移越晚越痛。

### 优先级 4：补更明确的数据版本迁移机制

虽然现在已经有 `schemaVersion`，但如果未来字段继续增长，建议逐步把升级步骤显式化。

---

## 26. 最后给你的结论：你应该怎样理解这个项目

如果只用一句工程判断来概括：

**这是一个以 SwiftUI 为界面、以 `LibraryStore` 为状态中心、以自定义文件仓储为本地真相源、再叠加轻量双向同步的 iOS 应用。**

它当前最值得你学习的，不是某个单独 API，而是这几个工程判断：

1. 先把本地模型搭稳，再谈同步
2. 编辑态和持久化态分开
3. 二进制资源和元数据分开
4. 删除必须有 tombstone，不能只做硬删除
5. UI 状态和重 I/O 分层
6. 测试要能隔离环境

如果你把这 6 件事真正学会，以后不只是能继续写这个 app，很多“本地优先 + 轻同步”的 iOS 应用你都能自己搭出来。

---

## 27. 阅读源码的推荐顺序

如果你接下来准备直接读代码，我建议按这个顺序：

1. `homeLibrary/homeLibraryApp.swift`
2. `homeLibrary/ContentView.swift`
3. `homeLibrary/LibraryStore.swift`
4. `homeLibrary/Book.swift`
5. `homeLibrary/LibraryPersistence.swift`
6. `homeLibrary/LibrarySync.swift`
7. `homeLibrary/LibrarySyncSettings.swift`
8. `homeLibrary/BookEditorView.swift`
9. `homeLibrary/ISBNLookupService.swift`
10. `homeLibraryTests/`

按这个顺序，你会先看懂主干，再理解细节，而不会一开始就陷在某个 API 里。

---

## 28. 一个简短的名词表

### SwiftUI

Apple 的声明式 UI 框架。  
你描述“界面在某种状态下应该长什么样”，系统负责渲染。

### Store

这不是 Swift 官方关键字，而是工程术语。  
这里指集中管理状态和业务动作的对象。

### ViewModel

很多项目会用这个词。  
这个项目虽然文件名叫 `LibraryStore`，但它在职责上已经接近 ViewModel / Store 的混合体。

### Actor

Swift 并发模型里的隔离单元，用来减少数据竞争。

### MainActor

代表主线程相关的执行上下文，通常用于 UI。

### Entitlement

App 对系统能力的声明，比如 iCloud、Push、Keychain sharing。

### Bundle

打包进 App 的资源集合。  
例如 `SeedBooks.json` 这种文件会作为资源存在 bundle 里。

### Tombstone

删除墓碑。  
不是实体数据，而是“某条记录已经被删除”的同步证据。

### Bookmark

这里指系统保存的文件夹访问凭证。  
选择共享文件夹后，App 通过 bookmark 记住访问权限。

---

如果你后续继续维护这个项目，可以把这份文档当成“工程地图”。  
先沿着地图走，再去改业务，会稳很多。
