# homeLibrary 当前测试说明

## 总览

目前仓库里有 **58 个 XCTest 用例/执行项**，外加 **1 个辅助脚本**：

- `homeLibraryTests/homeLibraryTests.swift`：35 个单元/状态管理测试
- `homeLibraryTests/LibraryPersistenceTests.swift`：9 个持久化与导入测试
- `homeLibraryTests/CloudKitLiveIntegrationTests.swift`：1 个真实 CloudKit 集成测试
- `homeLibraryTests/LibraryCoverCompressionTests.swift`：4 个封面压缩测试
- `homeLibraryTests/LibraryExportProgressTests.swift`：1 个导出进度测试
- `homeLibraryUITests/homeLibraryUITests.swift`：4 个 UI 测试
- `homeLibraryUITests/homeLibraryUITestsLaunchTests.swift`：1 个启动测试（按方向/明暗模式重复执行）
- `scripts/run_dual_sim_cloudkit_share_test.swift`：双模拟器 CloudKit 分享验证脚本，不属于 XCTest

整体上，当前测试重点在：

1. 数据模型和草稿归一化
2. 本地缓存持久化与导入/导出
3. `LibraryStore` 的仓库管理流程
4. CloudKit 配置切换
5. CloudKit 增量刷新与本地缓存合并
6. 最基础的 iOS UI 主流程

## 1. `homeLibraryTests/homeLibraryTests.swift`

这组测试主要覆盖业务规则、应用配置和 `LibraryStore` 核心流程。

### 过滤与数据归一化

- `testFiltersBooksByDynamicLocationAndKeyword`
  - 测试图书筛选是否同时按“动态位置 + 关键字”生效
- `testNormalizesDraftFieldsAndManagedBookInfoBeforeSave`
  - 测试 `BookDraft` 保存前是否会去掉首尾空格、清理空自定义字段
- `testBookPayloadDecodesLegacyLocationIntoDynamicLocationID`
  - 测试旧格式 `location` 字段是否能转换成新的 `locationID`
  - 同时验证旧 `isbn` 会被转进 `customFields["ISBN"]`

### 会话与配置

- `testRepositorySessionStorePersistsCurrentRepositoryPerNamespace`
  - 测试当前仓库选择是否按 namespace 隔离持久化
- `testLiveConfigurationDefaultsToPrimaryStorageNamespace`
  - 测试 XCTest 环境下默认配置是否使用默认 namespace、默认 cache 路径、默认 memory remote
- `testCloudKitOverrideWinsInsideXCTestHost`
  - 测试 XCTest 宿主下显式指定 `HOME_LIBRARY_REMOTE_DRIVER=cloudkit` 时是否真的启用 CloudKit
- `testCloudKitOverrideWinsInsideXCTestHostWithTestRunnerPrefixedEnvironment`
  - 测试 `TEST_RUNNER_` 前缀环境变量是否也能正确覆盖 remote driver 和 storage namespace
- `testLiveConfigurationUsesPreferredOwnedRepositoryNameOverride`
  - 测试自定义默认仓库名环境变量是否生效
- `testLiveConfigurationUsesTestRunnerPrefixedPreferredOwnedRepositoryNameOverride`
  - 测试 `TEST_RUNNER_` 前缀的默认仓库名环境变量是否生效
- `testUserFacingMessageForCloudKitNetworkFailureIsReadable`
  - 测试 CloudKit 网络错误是否会转换成可读的中文提示

### `LibraryStore` 主流程

- `testStoreCreatesRepositoryAndLoadsDefaultLocations`
  - 测试创建自有仓库后，是否会自动加载默认位置（成都、重庆）
- `testStoreAllowsRemovingOnlyNonCurrentRepositoryWhenMultipleRepositoriesExist`
  - 测试多仓库场景下，只有非当前仓库允许删除
- `testStoreRemovesNonCurrentRepositoryAndKeepsCurrentSelection`
  - 测试删除非当前仓库后，当前选中仓库是否保持正确
- `testStoreCanExportCurrentRepositoryAsZip`
  - 测试当前仓库是否能成功导出 zip 文件
- `testStoreImportsPackageAndUpdatesProgress`
  - 测试导入 JSON 包后，是否更新进度状态并正确装载图书数据
- `testStoreRefreshUsesCachedCloudKitChangeTokenAndMergesIncrementalChanges`
  - 测试刷新时会携带本地保存的 CloudKit zone change token
  - 测试增量变更只合并新增/删除内容，不会丢掉未变化的本地缓存

## 2. `homeLibraryTests/LibraryPersistenceTests.swift`

这组测试主要覆盖本地缓存结构、资源文件管理，以及旧数据导入兼容性。

### 缓存与资源持久化

- `testCacheStoreSeparatesCoverAssetsFromBookMetadata`
  - 测试封面二进制数据是否与图书元数据分离存储
  - 测试 metadata 文件中不会直接内嵌 `coverData`
- `testReplaceAllContentGarbageCollectsStaleAssetsAndPersistsLocations`
  - 测试全量替换内容时，旧封面资源是否会被清理
  - 测试位置列表是否一并持久化
- `testApplyRemoteChangesMergesIncrementalUpdateAndPersistsChangeToken`
  - 测试远端增量新增、删除、地点更新会正确合并到本地缓存
  - 测试 CloudKit zone change token 会随增量刷新持久化
- `testCacheStoreExportsImportPackageWithEmbeddedCoverData`
  - 测试导出导入包时，是否会把封面数据嵌入到导出包中

### 旧数据导入兼容

- `testLegacyImporterLoadsStructuredBooksAndSkipsDeletedRecords`
  - 测试旧目录结构导入时，会忽略已经删除的记录
- `testLegacyImporterLoadsLegacyStructuredBooksWithISBNAndCoverAsset`
  - 测试更旧格式图书 JSON 的兼容读取，包括 ISBN、旧位置字段、封面资源
- `testLegacyImporterLoadsBooksFromExplicitImportFile`
  - 测试从显式指定的 `LibraryImport.json` 文件导入
- `testLegacyImporterLoadsStructuredSeedFileWithoutLocationsArray`
  - 测试缺失 `locations` 数组的旧种子文件仍可导入，并能推导位置
- `testLegacyImporterNormalizesSeedLocationsWhenLocationIDContainsName`
  - 测试 seed 中地点 ID 写成地点名时仍会被归一化成可用地点 ID

## 3. `homeLibraryTests/CloudKitLiveIntegrationTests.swift`

这是一组**真实 CloudKit 集成测试**，不是 mock。

- `testCreateWriteRefreshExportAndClearRepository`
  - 测试创建自有仓库
  - 测试写入一本书
  - 测试刷新仓库快照
  - 测试导出仓库
  - 测试清空仓库并重置默认位置

### 运行前提

- 只有在环境变量 `HOME_LIBRARY_CLOUDKIT_LIVE_TESTS=1` 时才会执行
- 测试结束后会尝试清理创建出来的 CloudKit 仓库

## 4. `homeLibraryUITests/homeLibraryUITests.swift`

这组 UI 测试目前只覆盖一个最基础的用户路径。

- `testAddAndSearchBookOnIOS`
  - 如果还没有仓库，先创建自有仓库
  - 新增一本书
  - 验证图书卡片出现
  - 在搜索框输入作者关键字
  - 验证搜索后仍能找到对应图书

### 当前 UI 测试特点

- 使用 `HOME_LIBRARY_REMOTE_DRIVER=memory`
- 使用唯一的 `HOME_LIBRARY_STORAGE_NAMESPACE`
- 主要验证“启动后能建库、能加书、能搜索”这条主路径

## 5. `homeLibraryUITests/homeLibraryUITestsLaunchTests.swift`

- `testLaunch`
  - 只测试应用是否能正常启动
  - 启动后页面上至少应出现以下两种状态之一：
    - 还未建库时显示“创建仓库”按钮
    - 已可进入主界面时显示“新增图书”按钮

## 6. 非 XCTest 的辅助脚本

### `scripts/run_dual_sim_cloudkit_share_test.swift`

这个文件是一个**双模拟器 CloudKit 分享验证脚本**，更偏手工/集成验证工具，不是 XCTest 自动用例的一部分。按文件名和用途看，它主要用于验证：

- 双端模拟器场景
- CloudKit 共享流程
- 分享后的数据同步/协作行为

它属于额外验证能力，但不计入当前 XCTest 覆盖面。

## 7. 当前测试覆盖面的结论

目前测试已经覆盖了下面这些核心内容：

- 图书筛选逻辑
- 草稿字段清洗与旧数据兼容
- 仓库会话持久化
- 应用配置在测试环境和 CloudKit 环境下的切换规则
- `LibraryStore` 的建库、删库限制、导入、导出
- 本地缓存与封面资源存储
- 旧版 JSON/目录格式导入
- 基础 UI 主流程
- 一条真实 CloudKit 集成链路

## 8. 目前还没有明显覆盖到的区域

从现有测试文件看，下面这些内容暂时没有看到明确自动化覆盖，或者覆盖还比较浅：

- CloudKit 分享接收方流程
- 多设备/多仓库冲突处理
- 导入失败、损坏文件、非法字段等异常路径
- 大数据量、性能、并发相关测试
- UI 布局和无障碍相关测试

如果后面要继续补测试，优先级建议是：

1. CloudKit 分享与同步冲突
2. 导入失败与回滚类异常测试
3. UI 的编辑、删除、导入导出主路径
4. 大数据量、性能与并发相关测试
