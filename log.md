# Change Log

## 2026-04-14

- 初始化迁移记录文件：创建 `plan.md` 和 `log.md`，明确迁移范围、功能边界与执行顺序。
- 完成应用骨架替换：移除模板 `Item` / `SwiftData` 首页，接入 CloudKit 数据层与真实书籍模型。
- 完成核心界面与交互：实现列表、搜索、成都/重庆筛选、新增、编辑、删除、封面选择、ISBN 扫码与自动补全。
- 完成工程配置补齐：为 target 挂载 entitlements，配置 CloudKit 容器与相机权限声明。
- 完成静态验证收尾：主应用 Swift 文件已通过 `swiftc -typecheck`，并补充了筛选与 ISBN 处理相关单测文件；完整 `xcodebuild` 受限于当前机器未切到完整 Xcode。
- 修复 `LibraryStore` 编译问题：显式导入 `Combine`，保证 `ObservableObject` 与 `@Published` 在 Xcode 构建下正常合成。
- 开始撤销 iCloud 方案：根据个人开发团队不支持 iCloud capability 的限制，数据层切换为本地 JSON 持久化，优先保证应用可运行。
- 完成工程去能力化：移除 target 的 `CODE_SIGN_ENTITLEMENTS` 引用并删除 `homeLibrary.entitlements`，取消 iCloud capability 依赖。
- 完成本地持久化收口：书籍数据改为读写 `Application Support/homeLibrary/books.json`，保存和删除先落盘再更新内存状态。
- 完成 Cloudflare 数据迁移：从源仓库的 D1 / R2 导出 `110` 本书及全部封面，生成当前 app 的 `homeLibrary/SeedBooks.json`，并在首次启动时自动导入本地存储。
- 完成容器预落库：已将 `homeLibrary/SeedBooks.json` 直接复制到 macOS 容器 `~/Library/Containers/yu.homeLibrary/Data/Library/Application Support/homeLibrary/books.json`，当前本地库确认包含 `110` 本书。
- 修复迁移后读取失败：扩展日期解码逻辑，兼容带毫秒的 ISO8601 时间字符串，例如 `2026-04-14T01:59:07.000Z`。
