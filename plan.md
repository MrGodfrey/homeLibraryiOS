# homeLibrary CKShare 重构实施计划

## 1. 目标

这次重构的目标不是局部修补，而是把应用从“公共库 + 仓库账号密码”的临时协作模式，收敛到标准 iCloud 共享模型，并同步重做首页浏览体验、仓库设置、迁移工具和测试分层。

最终应满足下面五件事：

1. 用 `CKShare` 完成家庭书库共享。
2. 用动态地点替换硬编码地点枚举。
3. 用双栏书墙、顶部透明地点条和底部悬浮搜索重做首页。
4. 用仓库级高级管理区承接迁移、清空、导出。
5. 在 booted `iPhone 17` 模拟器上跑通真实 CloudKit Development 集成测试。

## 2. 范围

### 2.1 CloudKit 与共享

- owner 仓库位于 `privateCloudDatabase`
- member 仓库位于 `sharedCloudDatabase`
- 每个仓库使用一个自定义 zone
- zone 根记录固定为 `LibraryRepository`
- 共享入口使用 `UICloudSharingController`
- 接受邀请使用系统回调 + `CKAcceptSharesOperation`
- 删除旧账号密码加入逻辑及其 README / UI / 测试叙述

### 2.2 本地模型与持久化

- 引入仓库级 `LibraryLocation`
- 书籍主模型改为 `locationID`
- 首页“全部”变成纯 UI 筛选项
- 迁移层兼容旧 `成都 / 重庆`
- 缓存层同时持久化 `locations.json` 和书籍快照
- 导出格式统一为 zip + `LibraryImport.json`

### 2.3 页面与交互

- 首页删除仓库信息展示
- 书籍改为双栏书墙
- 顶部改成固定透明地点切换条
- 滚动后隐藏 `家藏万卷`
- 底部搜索改成悬浮毛玻璃搜索
- 卡片改成“先选中，再修改/删除”
- 编辑页地点选择改为动态列表

### 2.4 仓库设置

仓库设置页必须拆成：

1. 仓库信息
2. 地点配置
3. 高级管理区

高级管理区固定包含：

- 旧数据迁移
- 清空当前仓库
- 导出当前仓库 zip

### 2.5 测试

- 默认单测：内存远端
- 默认 UI 测试：内存远端
- live 集成测试：真实 CloudKit Development
- 不为首版自动化引入真网 UI 测试

## 3. 实施拆解

### 3.1 领域模型

- `Book.swift`
  - 新增 `LibraryLocation`
  - 新增 `LibraryLocationFilter`
  - `BookPayload` 改为存 `locationID`
  - `Book` 改为存 `locationID`
  - 兼容旧 `location` / `isbn` 字段解码

- `LibrarySyncSettings.swift`
  - `LibraryRepositoryReference` 升级为 share-aware
  - 引入角色、数据库作用域、share 状态
  - 会话层只保留当前仓库及迁移标记

### 3.2 本地持久化

- `LibraryPersistence.swift`
  - 缓存快照包含地点与书籍
  - 迁移导入统一返回 `LegacyImportBundle`
  - 支持导出 `LibraryImportPackage`
  - 支持 zip 封装

### 3.3 远端同步

- `LibrarySync.swift`
  - `LibraryRemoteSyncing` 改成仓库级接口
  - `InMemoryLibraryRemoteService` 改成仓库 + 地点模型
  - `CloudKitLibraryService` 切到私有 / 共享数据库 + 自定义 zone
  - 仓库发现与 zone 内全量读取改用：
    - `databaseChanges(since:)`
    - `recordZoneChanges(inZoneWith:since:)`
    - 固定根记录 `repository`
  - 这样主路径不再依赖旧公共库 query 索引

### 3.4 应用装配

- `LibraryAppConfiguration.swift`
  - `HOME_LIBRARY_REMOTE_DRIVER=cloudkit` 时强制使用 CloudKit
  - XCTest 默认仍走 memory
  - 兼容 test-runner 前缀环境变量

### 3.5 Store 与页面

- `LibraryStore.swift`
  - 统一管理仓库列表、当前仓库、地点、导出、导入进度、共享

- `ContentView.swift`
  - 双栏书墙
  - 顶部透明地点条
  - 底部毛玻璃搜索
  - 两段式卡片操作

- `BookEditorView.swift`
  - 动态地点列表
  - 删除旧“当前版本只保留手动录入”文案

- `RepositoryManagementView.swift`
  - 仓库信息 / 地点配置 / 高级管理区
  - 分享入口
  - 导入进度状态

### 3.6 分享回调

- `homeLibraryApp.swift`
  - 接收 CloudKit share metadata
  - 回传给 `LibraryStore` 执行接受共享

- `Info.plist`
  - `CKSharingSupported = true`

## 4. 测试与验收

### 4.1 默认回归

- `homeLibraryTests`
  - 动态地点筛选
  - 旧地点兼容解码
  - 会话持久化
  - 配置覆盖优先级
  - 导出 zip
  - 导入进度
  - 缓存与迁移

- `homeLibraryUITests`
  - 创建仓库
  - 新增书籍
  - 搜索
  - 编辑
  - 删除
  - 启动烟测

### 4.2 真实 CloudKit live

live 测试固定如下：

- target：`homeLibraryTests`
- case：`CloudKitLiveIntegrationTests`
- simulator：`iPhone 17`
- 环境：`Development`
- 数据隔离：`cloudkit-live-tests` + `library.live-test.*`

运行时变量：

```text
HOME_LIBRARY_REMOTE_DRIVER=cloudkit
HOME_LIBRARY_STORAGE_NAMESPACE=cloudkit-live-tests
HOME_LIBRARY_CLOUDKIT_LIVE_TESTS=1
```

当前已验证能力：

- 创建测试仓库
- 仓库发现
- 写入书籍
- 读取回显
- 导出
- 清空
- 自动清理

## 5. 风险与约束

### 5.1 已处理风险

- `sharedCloudDatabase` 不支持 zone-wide query  
  已改为按 zone 扫描根记录。

- host-backed 测试进程拿不到普通 shell 环境变量  
  已兼容 test-runner 前缀环境变量。

- 清空仓库时默认地点在一次 modify 中被同时保存和删除  
  已修复为只删除不再保留的地点记录。

### 5.2 保留为手动验收

- 双账号共享邀请与接受
- owner 移除参与者后的权限变化
- 真网 UI 层共享操作

## 6. 完成标准

满足下面条件视为本计划完成：

- 默认测试通过
- UI 测试通过
- `iPhone 17` 真网 CloudKit live 测试通过
- README 改成需求优先结构
- `log.md` 追加本轮结构性修改与 CloudKit 经验
