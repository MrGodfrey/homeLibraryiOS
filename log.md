# Change Log

## 2026-04-14

- 重做数据层：将原来的单文件 `books.json + coverData` 方案调整为结构化存储，拆分为 `manifest.json`、`books/`、`covers/`、`deletions/`。
- 新增旧数据迁移：首次启动时自动读取旧版 `books.json` 或 bundled `SeedBooks.json`，并把封面拆成独立资源文件。
- 新增封面资源仓库：封面改为按 `coverAssetID` 独立存储，元数据文件只保留引用，不再内嵌图片二进制。
- 新增删除墓碑机制：删除操作生成 tombstone，保证多设备同步时删除不会被旧数据误覆盖。
- 新增 iCloud Documents 云同步：实现本地库与云端镜像目录的双向合并，支持新增、更新、删除和封面资源补齐。
- 重新接入 iCloud entitlement：为 app target 添加 `homeLibrary.entitlements`，启用 Documents 容器同步路径。
- 更新应用配置层：增加 `LibraryAppConfiguration`，支持注入本地存储根目录、云端根目录和是否加载种子数据，便于测试与调试。
- 更新界面层：列表页增加同步状态展示；编辑与列表改为按 `coverAssetID` 读取封面。
- 补充 iOS 测试可观测性：为主要交互控件增加 `accessibilityIdentifier`，并支持 UI 测试专用启动环境。
- 新增单元测试 `LibraryPersistenceTests`：覆盖封面拆分存储、云端更新合并、云端删除传播。
- 替换 UI 测试占位实现：新增 iOS Simulator 启动烟测，以及新增 -> 搜索 -> 编辑 -> 删除的完整 UI 流程测试。
- 完成命令行验证：
  - `homeLibraryTests` 共 `6` 个测试通过
  - `homeLibraryUITests.testAddSearchEditAndDeleteBookOnIOS` 通过
  - `homeLibraryUITestsLaunchTests.testLaunch` 通过
