# homeLibrary Migration Plan

## Goal

在当前 SwiftUI 工程中实现 `/Users/wangyu/code/Home-library` 的等价功能，只保留原仓库已有能力，不额外扩展功能。

## Source Feature Scope

- 查看全部藏书
- 按 `成都` / `重庆` 筛选
- 按书名、作者、ISBN 搜索
- 新增书籍
- 编辑书籍
- 删除书籍
- 书籍封面选择与显示
- ISBN 扫码录入
- 基于公开接口自动补全书名、作者、出版社、年份

## Storage / Sync Decision

- 先取消 `iCloud / CloudKit` 能力，优先恢复本地可运行版本
- 数据层改为应用沙盒内的本地 `JSON` 持久化
- 不增加额外功能，仍保持原有书库功能边界
- 后续如果重新启用同步，再单独评估 iCloud 能力与签名约束

## Execution Status

- [x] 读取源仓库与当前仓库，确认功能边界
- [x] 定义书籍数据模型，替换模板 `Item`
- [x] 配置应用入口与本地持久化方式
- [x] 实现书籍列表页
- [x] 实现搜索与地点筛选
- [x] 实现新增 / 编辑表单
- [x] 实现删除流程
- [x] 实现封面选择、存储与展示
- [x] 实现 ISBN 扫码
- [x] 实现 ISBN 自动补全
- [ ] 补充必要测试与本地构建验证

## Current Focus

Cloudflare 历史数据已经迁移为当前 app 的本地种子文件，当前剩余的是在完整 Xcode 环境里做一次实际运行确认。

## Validation Notes

- 已通过命令行静态检查：
  `swiftc -typecheck -sdk /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk homeLibrary/Book.swift homeLibrary/LibraryStore.swift homeLibrary/ISBNLookupService.swift homeLibrary/ISBNScannerView.swift homeLibrary/BookEditorView.swift homeLibrary/ContentView.swift homeLibrary/homeLibraryApp.swift`
- 本地数据文件路径为应用沙盒 `Application Support/homeLibrary/books.json`
- 已完成 Cloudflare 数据迁移：导出 `110` 本书和 `110` 张封面，生成 `homeLibrary/SeedBooks.json`
- 已补充迁移说明：`docs/cloudflare-migration.md`
- 当前环境缺少完整 Xcode，`xcodebuild` 仍无法执行；现有开发目录为 `/Library/Developer/CommandLineTools`
