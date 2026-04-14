# homeLibrary

一个用 SwiftUI 编写的家庭藏书管理应用，当前版本优先恢复原有书库能力，并把数据层收敛为本地 JSON 持久化。

## 项目现状

截至 2026-04-14，项目已经完成从旧版 Cloudflare 数据源到当前原生 App 的第一阶段迁移，主流程可用：

- 已实现藏书列表展示
- 已实现按 `成都` / `重庆` 筛选
- 已实现按书名、作者、ISBN 搜索
- 已实现新增、编辑、删除书籍
- 已实现封面选择、存储与展示
- 已实现 ISBN 自动补全
- 已实现 ISBN 扫码入口
- 已完成历史数据导入，当前仓库内置 `110` 本书和对应封面作为种子数据

当前已验证情况：

- `xcodebuild -project homeLibrary.xcodeproj -scheme homeLibrary -destination 'platform=macOS' test` 通过
- 单元测试 `3` 个通过
- UI 测试当前为显式 `skip`，不会阻塞构建，但还没有覆盖真实交互流程

## 技术方案

- UI：SwiftUI
- 持久化：本地 `JSON`
- 图片：书籍封面以二进制形式写入 JSON
- ISBN 数据来源：
  - Google Books
  - Open Library
- 扫码能力：VisionKit `DataScannerViewController`

当前版本不依赖 iCloud / CloudKit，同步能力暂时关闭。

## 目录结构

```text
homeLibrary/
├── homeLibrary.xcodeproj/           Xcode 工程
├── homeLibrary/                     主应用源码
│   ├── ContentView.swift            列表页
│   ├── BookEditorView.swift         新增 / 编辑页
│   ├── LibraryStore.swift           本地数据读写
│   ├── ISBNLookupService.swift      ISBN 自动补全
│   ├── ISBNScannerView.swift        ISBN 扫码
│   └── SeedBooks.json               首次启动导入的种子数据
├── homeLibraryTests/                单元测试
├── homeLibraryUITests/              UI 测试（当前为 skip）
├── docs/cloudflare-migration.md     历史数据迁移说明
└── scripts/import_from_cloudflare.mjs
                                   从旧仓库导出数据的脚本
```

## 如何运行

### 1. 环境要求

- macOS
- 已安装 Xcode
- 使用本仓库根目录下的 `homeLibrary.xcodeproj`

### 2. 在 Xcode 中启动

1. 打开 `homeLibrary.xcodeproj`
2. 选择 scheme：`homeLibrary`
3. 选择运行目标：
   - `My Mac`：适合日常开发和本地验证
   - iPhone / iPad 真机：如果要测试摄像头扫码，建议使用支持 VisionKit 扫码的真机
4. 按 `Run`

### 3. 首次启动后的数据行为

- 如果本地还没有书库文件，应用会自动把 `homeLibrary/SeedBooks.json` 复制到本地存储
- 后续的新增、编辑、删除都只写入本地文件，不会回写种子文件

## 如何使用

### 浏览与筛选

- 顶部支持 `全部 / 成都 / 重庆` 切换
- 支持按书名、作者、ISBN 搜索

### 添加或编辑书籍

- 右上角 `+` 可新增书籍
- 点击已有书籍卡片或右侧编辑按钮可修改信息
- 必填项只有书名

### ISBN 自动录入

在编辑页中输入或扫描 ISBN 后，点击“自动补全”：

- 会优先查询 Google Books
- 如果未命中，再查询 Open Library
- 自动回填书名、作者、出版社、年份

说明：

- 该功能依赖网络
- 外部接口返回为空时，需要手动补录

### 扫码

- 支持设备上可直接扫码识别 ISBN
- 不支持扫码的环境下，会提示改为手动输入

通常以下环境不能直接扫码：

- macOS
- Simulator
- 不支持 VisionKit `DataScannerViewController` 的设备

## 本地数据位置

应用默认把书库写到 `Application Support/homeLibrary/books.json`。

在 macOS 沙盒环境下，实际常见路径类似：

```text
~/Library/Containers/yu.homeLibrary/Data/Library/Application Support/homeLibrary/books.json
```

如果你想重置本地数据，可以删除这个文件后重新启动应用；应用会再次从 `SeedBooks.json` 导入初始数据。

## 测试

运行测试：

```bash
xcodebuild -project homeLibrary.xcodeproj -scheme homeLibrary -destination 'platform=macOS' test
```

当前测试覆盖：

- 图书筛选逻辑
- 表单字段标准化
- 扫码文本中的 ISBN 提取

## 历史数据迁移

如果需要重新从旧版 Cloudflare 数据源生成种子文件，可执行：

```bash
node scripts/import_from_cloudflare.mjs --source-repo /Users/wangyu/code/Home-library
```

默认输出：

```text
homeLibrary/SeedBooks.json
```

脚本依赖：

- Node.js
- 源仓库可用
- `wrangler` 可执行
- 当前机器具有有效的 Cloudflare 登录态

更多细节见：

- `docs/cloudflare-migration.md`

## 当前限制

- 只有本地存储，没有云同步
- UI 自动化测试仍是占位状态
- ISBN 自动补全依赖第三方公开接口，稳定性受外部服务影响
- 封面二进制直接写入 JSON，种子文件体积较大（当前约 20 MB）

## 后续建议

- 为新增 / 编辑 / 删除补充更完整的 UI 测试
- 评估是否恢复 iCloud 或引入新的同步方案
- 视数据规模决定是否把封面与书籍元数据拆分存储
