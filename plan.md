# homeLibrary iOS / Sync Plan

## Goal

在当前 SwiftUI 工程上完成以下工作，并保持已有书库能力可用：

- 落实可运行、可验证的 iOS 版本
- 增加云同步能力
- 将封面图片与书籍元数据分离存储，支撑后续书量增长
- 补齐计划、变更记录、README 和测试

## Implementation Decisions

### 1. iOS 版本

- 保留现有 SwiftUI 单工程，多平台 target 继续共用一套界面
- 以 iPhone / iPad 为主验证目标，macOS 继续保留桌面运行能力
- 为 UI 测试增加可注入的启动环境，保证 Simulator 中可重复执行

### 2. 存储拆分

- 本地存储从单个 `books.json` 改为结构化目录：
  - `manifest.json`
  - `books/<book-id>.json`
  - `covers/<asset-id>.bin`
  - `deletions/<book-id>.json`
- 封面文件使用独立二进制文件存储，书籍元数据仅保存 `coverAssetID`
- 删除使用 tombstone 记录，避免云端多设备删除冲突丢失

### 3. 云同步

- 使用 iCloud Documents 容器镜像同一套结构化目录
- 同步策略：
  - 书籍以 `updatedAt` 做最后写入胜出
  - 删除以 tombstone 的 `deletedAt` 胜出
  - 封面资源按 `coverAssetID` 复制补齐
- 本地写入后自动尝试同步；刷新时也会重新同步

### 4. 兼容旧数据

- 首次启动时自动导入旧版 `books.json` 或 bundled `SeedBooks.json`
- 导入过程中把旧的 `coverData` 拆成独立封面文件
- 如果检测到本地旧版 `books.json`，迁移后备份为 `books.legacy.backup.json`

## Execution Status

- [x] 确认现有工程已具备 iOS target，避免重复造一个 app
- [x] 设计“元数据 / 封面 / 删除墓碑 / 云端镜像”存储模型
- [x] 实现结构化本地存储与旧数据迁移
- [x] 实现 iCloud Documents 云同步
- [x] 调整 UI，接入同步状态与新的封面读取方式
- [x] 增加 iOS 测试环境注入与可自动化的交互标识
- [x] 补充单元测试
- [x] 补充 iOS UI 测试
- [x] 更新 `plan.md`、`log.md`、`README.md`

## Validation Notes

截至 2026-04-14，已完成以下验证：

- 单元测试通过：`6` 个
  - 书籍筛选
  - 表单标准化
  - ISBN 提取
  - 元数据 / 封面分离存储
  - 云端更新合并
  - 云端删除传播
- iOS UI 主流程测试通过：新增 -> 搜索 -> 编辑 -> 删除
- iOS 启动烟测通过

本次实际执行过的命令：

```bash
xcodebuild -project homeLibrary.xcodeproj -scheme homeLibrary \
  -destination 'id=8CC688D1-06E8-4A1D-BC56-8AE8A52BA492' \
  -parallel-testing-enabled NO \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO \
  -only-testing:homeLibraryTests test
```

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
