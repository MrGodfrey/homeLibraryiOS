# 添加一个 AI 自动管理的功能：实施计划

## 1. 背景

当前 `homeLibrary` 的真实数据源是 CloudKit：

- 每座家庭书库对应一个 CloudKit 自定义 zone。
- 图书写入统一走 `LibraryStore.saveBook` -> `LibraryRemoteSyncing.upsertBook` -> `CloudKitLibraryService.upsertBook`。
- 本地 `cloudkit-cache` 只是启动加速和封面缓存，不是可直接编辑的数据源。
- 导出会生成 zip，zip 内部包含 `LibraryImport.json`；导入主路径当前只接受 JSON。

因此，AI 不应该直接修改本地缓存，也不应该绕过 app 直接写 CloudKit。更简化的方向是：让 iPhone app 成为带权限的数据网关，Codex / AI 在 Mac 上做数据整理、联网查证和生成结构化 patch，然后直接调用 app 暴露的本地 `apply` 接口；app 负责校验 patch 并通过现有 CloudKit 写入链路落库。

## 2. 目标

第一版目标是新增一个“AI 整理模式”，让用户可以在同一局域网内把当前书库临时暴露给 Mac 上的 Codex 工具，由 AI 辅助完成：

1. 读取当前书库快照。
2. 根据 ISBN 或现有书籍信息在网上查资料。
3. 为新增或缺封面的书籍准备封面缩略图。
4. 生成结构化、面向机器的变更 patch。
5. Codex 直接提交 `apply` 请求。
6. app 校验后自动应用 patch 并同步到 CloudKit。

这个功能要解决的问题：

- 不把 ISBN 查询、AI 模型、联网爬取逻辑塞进 iOS app。
- 减少导出 zip、解压 JSON、手工导入的繁琐流程。
- 减少 iPhone 上的人工预览、勾选和确认步骤；用户开启会话后，主要操作在 Codex 里完成。
- 避免 AI 直接覆盖家庭成员已经修改过的数据。
- 避免把原始大图封面塞进局域网请求和 CloudKit；封面只作为 iOS 小略缩图使用，必须大幅压缩。
- 保持 App Store 合规边界清楚。

## 3. 非目标

第一版明确不做：

- 不在 iOS app 内集成 OpenAI、Google Books、Open Library 或其他 ISBN 查询服务。
- 不让 app 下载或执行任何外部代码、脚本、插件、JS、Swift 或动态功能模块。
- 不让 Mac 端 CLI 直接写 CloudKit。
- 不做后台常驻局域网服务。
- 不做 iPhone 端 patch 预览、逐条勾选或二次确认。
- 不要求局域网接口给人直接阅读；接口可以是 Codex 专用的简洁 JSON。
- 不把 AI patch 当作新的同步协议；CloudKit 仍然是唯一同步层。

## 4. 合规与安全原则

### 4.1 Apple 审核边界

这个方案可以做，但必须按下面原则实现：

- 局域网服务必须由用户手动开启，并且界面上清楚显示当前正在开放 AI 整理会话。
- 需要在 `Info.plist` 增加清楚的本地网络用途说明，例如 `NSLocalNetworkUsageDescription`。
- 如果使用 Bonjour 广播服务，还需要声明 `NSBonjourServices`。
- 不得从 Mac 端向 app 传入可执行代码；只能传入 JSON 数据 patch。
- 如果用户选择让 Codex / 第三方 AI 处理书库数据，app 需要在开启会话前明确提示数据可能会离开设备、由用户控制的电脑或第三方 AI 服务处理，并要求用户确认开启。
- 开启会话即表示允许持有 token 的 Codex 在会话期内提交并应用 patch；最终写入仍发生在 iPhone app 内，通过现有 `LibraryStore` 链路完成。

参考：

- Apple Local Network Privacy: <https://developer.apple.com/videos/play/wwdc2020/10110/>
- `NSLocalNetworkUsageDescription`: <https://developer.apple.com/documentation/bundleresources/information-property-list/nslocalnetworkusagedescription>
- `NSBonjourServices`: <https://developer.apple.com/documentation/bundleresources/information-property-list/nsbonjourservices>
- App Review Guidelines 5.1.2(i): <https://developer.apple.com/app-store/review/guidelines/>

### 4.2 数据安全原则

- 会话默认只在 app 前台有效。
- 会话由用户手动停止，离开页面、锁屏或 app 进入后台时自动停止。
- 每次会话生成一次性 token，短时有效。
- token 只显示给用户，不写入 CloudKit，不进入导出包。
- Mac 端请求必须携带 token。
- 请求体需要限制大小，避免局域网内恶意请求造成内存压力。
- patch 只能描述允许的图书字段变更，不能包含任意 CloudKit record 字段。
- app 对 patch 做完整校验，不能信任 Codex 生成的内容。
- 接口返回可以偏机器可读，不需要设计成人类阅读友好的 HTML 或管理后台。

### 4.3 写入安全原则

- 默认只补空字段，不覆盖已有字段。
- 第一版不做无条件覆盖；需要覆盖非空字段时，patch 必须携带当前期望值，app 校验当前值一致才允许写入。
- 每条更新必须携带 `expectedUpdatedAt`。
- 如果 CloudKit 当前书籍 `updatedAt` 与 patch 里的 `expectedUpdatedAt` 不一致，自动列为冲突，不应用该操作。
- 新增书籍必须做 ISBN 去重、标题去重和地点校验。
- 应用 patch 时继续走现有 `LibraryStore.saveBook`，不直接写 CloudKit record。

## 5. 推荐产品形态

入口放在 `仓库设置 -> 高级管理`：

```text
AI 整理模式
```

进入后显示：

- 当前仓库名称。
- 本次会话说明。
- “启动本地连接”按钮。
- 启动后的局域网地址，例如 `http://192.168.1.23:17865`。
- 一次性访问码或 token。
- 当前连接状态。
- 最近一次 Codex apply 的摘要，例如成功、跳过、冲突、失败数量。
- “停止会话”按钮。

关键 UX：

- 页面明确说明：启动后，持有 token 的 Codex 可以读取快照并提交可自动应用的 patch。
- app 页面只负责启动、停止和显示最近结果，不做人类可读的 patch 编辑器。
- 低置信度、冲突、重复、缺封面的条目由 app 校验后拒绝或跳过，并在 apply response 中返回给 Codex。
- 用户如果想人工复核，由 Codex 在会话外输出摘要；iPhone app 第一版不承担复核界面。

## 6. 总体架构

```text
Mac / Codex skill
  1. 连接 iPhone 局域网会话
  2. 拉取 snapshot
  3. 联网查 ISBN / 书籍资料
  4. 生成 AI patch
  5. 可选提交 validate
  6. 直接提交 apply
  7. 输出 apply 结果摘要

iPhone app
  1. 用户手动开启 AI 整理模式
  2. 提供短时本地 HTTP 接口
  3. 接收 snapshot / validate / apply 请求
  4. 自动校验 patch
  5. 通过现有 LibraryStore 写入 CloudKit

CloudKit
  仍然是唯一远端同步与共享层
```

## 7. AI Patch 数据格式

新增一个明确的 patch 格式，避免复用完整 `LibraryImportPackage` 导致误覆盖。

### 7.1 顶层结构

```json
{
  "schemaVersion": 1,
  "source": "codex-home-library-curator",
  "createdAt": "2026-06-22T10:00:00.000Z",
  "baseRepositoryID": "library.xxx",
  "baseSnapshotID": "snapshot.xxx",
  "operations": [],
  "notes": []
}
```

字段说明：

- `schemaVersion`：patch 格式版本。
- `source`：生成工具标识。
- `createdAt`：patch 生成时间。
- `baseRepositoryID`：生成 patch 时对应的仓库 ID。
- `baseSnapshotID`：app 生成 snapshot 时的稳定标识，方便确认 patch 是否基于当前快照。
- `operations`：新增、更新或删除建议。第一版不开放删除。
- `notes`：全局说明，例如数据源、查找失败原因、低置信度提示。

### 7.2 新增书籍操作

```json
{
  "op": "createBook",
  "clientOperationID": "op-001",
  "confidence": 0.92,
  "fields": {
    "title": "示例书名",
    "author": "示例作者",
    "translator": "",
    "publisher": "示例出版社",
    "year": "2024",
    "isbn": "9780000000000",
    "locationID": "location.chengdu"
  },
  "cover": {
    "kind": "compressedThumbnailBase64",
    "mimeType": "image/jpeg",
    "width": 160,
    "height": 240,
    "quality": 0.42,
    "byteSize": 18000,
    "sourceURL": "https://example.com/cover.jpg",
    "data": ""
  },
  "evidence": [
    {
      "sourceName": "Open Library",
      "url": "https://openlibrary.org/isbn/9780000000000",
      "matchedFields": ["title", "author", "isbn"]
    }
  ],
  "warnings": []
}
```

规则：

- `title` 和 `locationID` 必填。
- `isbn` 如果存在，必须通过基本 ISBN-10 / ISBN-13 格式校验。
- `cover` 第一版必填，但只能是压缩后的封面缩略图，不保存原始大图。
- app 应拒绝超出缩略图限制的封面，而不是在主线程尝试处理大图。
- 新增前 app 必须检查当前书库是否已有同 ISBN 图书。

封面缩略图规则：

- 第一版只接受 `image/jpeg`，统一由 Codex skill 在 Mac 端完成下载、裁剪和压缩。
- 目标尺寸按书封 2:3 处理，推荐 `160 x 240 px`；长边硬上限 `300 px`。
- JPEG 质量建议 `0.35 - 0.45`，目标大小不超过 `30 KB`；单张硬上限 `60 KB`。
- `data` 必须是压缩后 JPEG 的 base64，不允许传入原图、PNG 截图或网页整图。
- `sourceURL` 必填，用于 apply result 和 Codex 输出摘要中保留来源。
- 如果同一个 ISBN 找不到可信封面，Codex 不应提交 `createBook`，而是把该 ISBN 放进 apply 结果摘要的“缺封面，未新增”列表。

### 7.3 更新书籍操作

```json
{
  "op": "updateBook",
  "clientOperationID": "op-002",
  "id": "existing-book-id",
  "expectedUpdatedAt": "2026-05-04T12:00:00.000Z",
  "confidence": 0.88,
  "fields": {
    "publisher": {
      "mode": "fillIfEmpty",
      "value": "示例出版社"
    },
    "year": {
      "mode": "fillIfEmpty",
      "value": "2024"
    },
    "isbn": {
      "mode": "fillIfEmpty",
      "value": "9780000000000"
    }
  },
  "evidence": [
    {
      "sourceName": "Google Books",
      "url": "https://books.google.com/...",
      "matchedFields": ["publisher", "year"]
    }
  ],
  "warnings": []
}
```

`mode` 第一版只允许：

- `fillIfEmpty`：目标字段为空才写入。
- `replaceIfCurrentValue`：只有目标字段当前值与 patch 里的 `expectedValue` 完全一致时才替换；用于 Codex 已知旧值且需要纠错的场景。

第一版不允许：

- `deleteField`
- `deleteBook`
- 任意自定义 CloudKit 字段写入

### 7.4 既有书籍封面补全操作

对已经存在但缺封面的图书，第一版使用独立操作，避免把封面更新混进普通字段补全：

```json
{
  "op": "updateBookCover",
  "clientOperationID": "op-003",
  "id": "existing-book-id",
  "expectedUpdatedAt": "2026-05-04T12:00:00.000Z",
  "confidence": 0.9,
  "cover": {
    "kind": "compressedThumbnailBase64",
    "mimeType": "image/jpeg",
    "width": 160,
    "height": 240,
    "quality": 0.42,
    "byteSize": 18000,
    "sourceURL": "https://example.com/cover.jpg",
    "data": ""
  },
  "evidence": [
    {
      "sourceName": "Open Library",
      "url": "https://openlibrary.org/isbn/9780000000000",
      "matchedFields": ["isbn"]
    }
  ],
  "warnings": []
}
```

规则：

- 只允许在当前书籍 `hasCover == false` 时自动应用。
- 如果当前书籍已经有封面，第一版直接跳过或拒绝，不做自动替换。
- 仍然必须携带 `expectedUpdatedAt`，避免覆盖家庭成员刚手动添加的封面。
- `cover` 使用和 `createBook` 完全相同的压缩缩略图限制。

## 8. Snapshot 数据格式

app 提供给 Codex 的 snapshot 应该比完整导出包更轻：

```json
{
  "schemaVersion": 1,
  "snapshotID": "snapshot.xxx",
  "repository": {
    "id": "library.xxx",
    "name": "家藏万卷",
    "role": "owner",
    "databaseScope": "private"
  },
  "locations": [],
  "books": [
    {
      "id": "book-id",
      "title": "书名",
      "author": "作者",
      "translator": "",
      "publisher": "",
      "year": "",
      "isbn": "",
      "locationID": "location.chengdu",
      "updatedAt": "2026-05-04T12:00:00.000Z",
      "hasCover": true
    }
  ]
}
```

第一版 snapshot 不包含封面二进制，避免局域网接口过重；只暴露 `hasCover` 这类布尔状态，帮助 Codex 判断是否需要补封面。封面只能通过 patch 中的压缩缩略图进入 app。

## 9. 局域网 API 设计

### 9.1 服务生命周期

- 用户进入 AI 整理模式页面。
- 点击“启动本地连接”。
- app 创建本地服务并生成 token。
- app 显示地址和 token。
- 页面关闭、app 后台、锁屏、超时或用户点击停止时，服务关闭。

### 9.2 端点

第一版端点保持最小：

```http
GET /health
GET /library/snapshot
POST /patch/validate
POST /patch/apply
POST /session/stop
```

说明：

- `GET /health`：检查连接和版本。
- `GET /library/snapshot`：返回当前仓库轻量快照。
- `POST /patch/validate`：可选端点，只校验 patch 并返回机器可读的逐条结果，不保存。
- `POST /patch/apply`：校验 patch，通过后直接应用可写操作，并返回机器可读的逐条应用结果。
- `POST /session/stop`：请求停止会话。

接口约定：

- 不提供 HTML 页面，不追求人类可读。
- 响应以简洁 JSON 为主，字段稳定，方便 Codex 解析。
- `apply` 可以部分成功：通过校验的操作写入，冲突、重复、低置信度或封面不合规的操作跳过并返回原因。
- 如果 patch 顶层 schema、仓库 ID、snapshot ID 或请求体大小不合规，整个请求直接失败，不进入逐条应用。

### 9.3 认证

每个请求需要带：

```http
Authorization: Bearer <session-token>
```

可选增强：

- `X-HomeLibrary-Request-ID`
- `X-HomeLibrary-Timestamp`
- `X-HomeLibrary-Signature`

如果第一版实现 HMAC 签名，签名密钥由会话 token 派生，减少同一局域网内重放风险。

### 9.4 HTTP / HTTPS 取舍

第一版可以先用本地 HTTP，并满足：

- 只在局域网可访问。
- 短时会话。
- token 认证。
- 不后台常驻。
- 不接收任意代码。

更稳的后续版本可以考虑：

- app 生成临时自签名证书。
- UI 显示证书指纹。
- Codex 使用证书指纹校验连接。

但 HTTPS 会显著增加实现复杂度，不建议作为第一版阻塞项。

## 10. App 端实现拆分

### 10.1 新增领域模型

建议新增文件：

- `LibraryAIPatch.swift`
- `LibraryAIPatchValidator.swift`
- `LibraryAIPatchApplyResult.swift`

职责：

- 定义 snapshot、patch、operation、evidence、warning。
- 校验 patch schema。
- 根据当前 `books` / `locations` 生成 validate / apply 结果。
- 应用 patch 时转换为 `BookDraft` 并调用现有保存逻辑。

### 10.2 新增局域网服务层

建议新增文件：

- `LibraryAIAssistantSession.swift`
- `LibraryAIAssistantHTTPServer.swift`

实现建议：

- 优先使用 `Network.framework` 的 `NWListener`。
- 只实现非常小的 HTTP/1.1 JSON 接口。
- 避免引入大型 server 框架。
- 接口专为 Codex 调用设计，不需要 HTML、表单或人类可读页面。
- 所有写入状态仍由 `@MainActor LibraryStore` 或独立 view model 管理。

### 10.3 新增 UI

建议新增：

- `LibraryAIAssistantView.swift`

放置位置：

- `RepositoryManagementView` 的高级管理区新增入口。

UI 状态：

- idle
- requestingLocalNetworkPermission
- running
- applying
- completed
- failed

UI 不提供 patch 预览、逐条选择或确认应用。它只显示会话地址、token、连接状态、最近一次 apply 摘要和停止入口。

### 10.4 和现有 Store 的关系

新增方法建议：

```swift
func makeAISnapshot() -> LibraryAISnapshot
func validateAIPatch(_ patch: LibraryAIPatch) -> LibraryAIPatchApplyResult
func applyAIPatch(_ patch: LibraryAIPatch) async -> LibraryAIPatchApplyResult
```

应用 patch 时：

- 新增书籍：构造 `BookDraft`，写入压缩封面缩略图，调用 `saveBook(draft:editing:nil)`。
- 更新书籍：找到现有 `Book`，构造 `BookDraft(book:)` 后合并字段，再调用 `saveBook(draft:editing:existingBook)`。
- 补全封面：只在 validate 确认可写后把压缩 JPEG 写入草稿封面数据，再走同一条 `saveBook` 链路。
- 地点不存在：validate 阶段报错，不自动创建地点。
- 冲突：validate 标记，apply 时跳过对应操作。

## 11. Codex Skill 设计

新增一个本地 Codex skill，名称建议：

```text
home-library-curator
```

职责：

1. 询问用户 iPhone 上显示的局域网地址和 token。
2. 调用 `GET /library/snapshot` 拉取当前书库。
3. 识别缺失 ISBN、缺失出版社、缺失年份、疑似重复。
4. 根据用户提供的新 ISBN 列表联网查询资料。
5. 下载可信封面并压缩为 iOS 缩略图级 JPEG。
6. 生成 `LibraryAIPatch`。
7. 可选调用 `POST /patch/validate` 做机器校验。
8. 根据 validate 结果修正 patch。
9. 调用 `POST /patch/apply` 直接应用。
10. 输出 apply 结果摘要，必要时生成 `apply-report.md`，列出：
   - 新增书籍
   - 补全字段
   - 按当前值校验后替换的字段
   - 冲突
   - 重复 ISBN
   - 查不到资料的 ISBN
   - 查不到可信封面的 ISBN
   - 已跳过或失败的操作及原因
   - 低置信度项

Skill 规则：

- 不保存 token。
- 不把完整书库快照写入长期文件，除非用户明确要求。
- 所有联网资料必须记录来源。
- 默认不覆盖人工已有字段。
- 中文书优先查中文出版信息，不能只拿英文 edition 填中文书。
- 对同 ISBN 多版本结果，优先选与当前标题、作者、出版社最接近的版本。
- 封面只保留小缩略图，不保留或提交原始图片；压缩失败、尺寸过大或来源不可信时不提交对应新增操作。
- 调用 `apply` 前，Codex 必须先在本地做 ISBN、封面大小、字段模式和 snapshot ID 自检，减少 app 端拒绝率。

## 12. ISBN 查询规则

### 12.1 标准化

Codex skill 先做：

- 去掉空格、连字符。
- 校验 ISBN-10 / ISBN-13。
- ISBN-10 可转换为 ISBN-13。
- 无效 ISBN 不进入 patch，只进入报告。

### 12.2 数据源优先级

建议顺序：

1. 用户已有书库字段。
2. Open Library / Google Books 等结构化 API。
3. 出版社或图书馆页面。
4. 普通网页搜索。

注意：

- 豆瓣等网站可能有访问和版权限制，不应作为唯一依赖。
- 封面图片来源要记录 URL；第一版新增图书必须带压缩封面缩略图，但只能作为小图展示，不追求高清收藏级质量。

### 12.3 置信度

建议评分：

- ISBN 精确匹配：基础分高。
- 标题一致：加分。
- 作者一致：加分。
- 出版社一致：加分。
- 只有标题无 ISBN：低置信度。
- 多个来源互相冲突：降分；低于阈值时不提交 apply，只进入 Codex 摘要。

## 13. 分阶段实施

### 阶段 0：确认数据协议

产出：

- `LibraryAIPatch` JSON schema。
- `LibraryAISnapshot` JSON schema。
- 示例 snapshot。
- 示例 patch。
- 压缩封面缩略图字段约束。
- 示例 validate / apply response。

验收：

- 能用 fixture 表达新增一本书、补全 ISBN、补出版社、冲突、重复 ISBN。
- 能用 fixture 表达封面过大、封面格式错误、缺少 `sourceURL` 时被 validate / apply 拒绝。

### 阶段 1：纯本地 patch 校验与应用

先不做局域网服务，只实现 patch domain：

- 解析 patch。
- 校验字段。
- 生成机器可读 validate 结果。
- 应用到内存远端测试仓库。

测试：

- 新增书籍成功。
- 补空字段成功。
- 非空字段默认不覆盖。
- `replaceIfCurrentValue` 只在当前值匹配时写入。
- `expectedUpdatedAt` 不一致时冲突。
- 重复 ISBN 被拦截。
- 地点不存在时报错。
- 新增书籍缺封面时报错。
- 已有书籍缺封面时可以通过 `updateBookCover` 补全。
- 已有书籍已有封面时，`updateBookCover` 被拒绝或跳过。
- 封面超过尺寸或体积上限时报错。

### 阶段 2：iPhone 会话入口

实现：

- 高级管理入口。
- 启动本地连接。
- 展示地址、token 和连接状态。
- 展示最近一次 apply 摘要。
- 停止会话。

验收：

- iPhone 上不需要预览 patch 或点击应用按钮。
- 用户启动会话后，Codex 可以在同一局域网内完成读取和应用。

### 阶段 3：局域网会话

实现：

- 本地 server 生命周期。
- token 生成与校验。
- `GET /health`。
- `GET /library/snapshot`。
- `POST /patch/validate`。
- `POST /patch/apply`。
- 前台/后台自动停止。
- `Info.plist` 本地网络说明。

验收：

- Mac 上 `curl` 可以拉 snapshot。
- 无 token 请求失败。
- 错误 token 请求失败。
- 超大请求体被拒绝。
- app 进入后台服务停止。
- apply patch 后返回逐条结果，iPhone UI 只显示摘要。

### 阶段 4：Codex skill

实现：

- `home-library-curator` skill。
- 连接 iPhone 会话。
- 拉 snapshot。
- 读取用户提供的 ISBN 列表。
- 查询资料。
- 下载、裁剪并大幅压缩封面缩略图。
- 生成 patch。
- 可选 validate。
- apply。
- 输出 apply 结果摘要，必要时生成 `apply-report.md`。

验收：

- 输入 1-3 个 ISBN，能生成 patch 并通过 `POST /patch/apply` 写入。
- 对无效 ISBN 给出报告，不提交无效操作。
- 对重复 ISBN 给出报告，不新增重复书籍。
- 对找不到可信封面的 ISBN 给出报告，不新增缺封面书籍。

### 阶段 5：ZIP 导入闭环补齐

这是相邻但独立的能力：

- 让现有导入入口支持 `.zip`。
- 自动读取 zip 内的 `LibraryImport.json`。
- 导入前增加摘要预览。

原因：

- 即使 AI 整理模式上线，备份恢复也应该闭环。
- 这不替代 AI patch，只补齐现有导入/导出体验。

### 阶段 6：App Store 审核准备

准备：

- 更新隐私说明。
- 更新 App Review Notes，说明 AI 整理模式需要同一局域网和用户手动开启。
- 准备演示视频或截图。
- 明确说明 app 不内置第三方 AI SDK，局域网工具由用户主动连接；开启会话后 Codex 可以提交并应用数据 patch。
- 如果上架版本包含该功能，确保 App Store Connect 隐私标签与实际数据流一致。

## 14. 测试计划

### 14.1 单元测试

覆盖：

- patch 解码。
- patch schema 版本不兼容。
- ISBN 标准化。
- 新增书籍 validate / apply。
- 更新书籍 validate / apply。
- 冲突检测。
- 重复 ISBN 检测。
- 非空字段保护。
- `replaceIfCurrentValue` 当前值校验。
- 应用 patch 后 CloudKit mock / memory remote 内容正确。
- 新增书籍时封面缩略图必填。
- 既有书籍封面补全和已有封面跳过逻辑。
- 封面 mime type、像素尺寸、base64 大小和 `sourceURL` 校验。
- 过大的封面 patch 被拒绝，不进入应用流程。

### 14.2 UI 测试

覆盖：

- 打开 AI 整理模式。
- 启动和停止会话。
- 显示地址、token 和连接状态。
- apply 后显示最近一次摘要。
- app 后台或停止会话后接口不可用。

### 14.3 集成测试

覆盖：

- `curl` 访问 `GET /health`。
- `curl` 访问 snapshot。
- token 错误。
- validate patch。
- apply patch。
- apply 带压缩封面的 patch。

### 14.4 手工验收

覆盖：

- 真机 iPhone 与 Mac 在同一 Wi-Fi。
- iOS 本地网络权限弹窗。
- app 后台服务停止。
- 局域网断开后 UI 状态恢复。
- CloudKit owner 仓库写入。
- shared 仓库有写权限时写入；无写权限时显示可读错误。

## 15. 风险与缓解

| 风险 | 缓解 |
| --- | --- |
| Apple 认为这是隐藏远程控制 | 用户手动开启、明显 UI、短时会话、只传数据 patch、开启前明确说明 Codex 可提交并应用修改 |
| 去掉 app 内二次确认导致审核解释成本上升 | App Review Notes 明确这是用户本机 Codex 辅助整理入口，接口短时前台有效，且只允许结构化图书数据 patch |
| 被认为下载执行代码 | 明确禁止脚本/代码输入，patch schema 只允许数据字段 |
| 局域网数据被其他设备看到 | 短时 token、请求认证、可选 HMAC、前台有效、后续再做 HTTPS |
| AI 覆盖家人刚改的数据 | `expectedUpdatedAt` 冲突检测，非空字段默认不覆盖，必要覆盖必须 `replaceIfCurrentValue` |
| AI 查错版本 | evidence + confidence + 低置信度直接跳过或由 Codex 报告，不在 app 内做人工确认 |
| patch 太大 | snapshot 不含封面；patch 只允许压缩缩略图封面；限制单张封面、单次请求和总操作数量 |
| 导入导出与 AI patch 混用导致误覆盖 | AI patch 不复用完整导入包，只表达增量操作 |

## 16. 第一版最小可交付范围

第一版只做这些：

1. `LibraryAISnapshot`。
2. `LibraryAIPatch`。
3. validate / apply 结果。
4. iPhone UI 启停本地 Codex 会话。
5. 局域网 snapshot / validate / apply。
6. Codex skill 生成 patch 并直接 apply。
7. 新增书籍必须带压缩封面缩略图；不处理原始大图或高清封面。
8. 不开放删除书籍。
9. 不开放绕过 app 直写 CloudKit。

这版已经能覆盖核心使用场景：

- 我给 Codex 一组 ISBN。
- Codex 查资料。
- Codex 调用 iPhone app 的本地 apply 接口。
- app 写入 CloudKit。

## 17. 后续增强

可选增强：

- 更高清封面重建、手动换封面、封面重新压缩策略配置。
- HTTPS / 证书指纹校验。
- patch 操作分组、批量选择和人工复核界面。
- Codex 自动识别现有书库缺失字段并建议补全。
- 按“只新增 / 只补 ISBN / 只补出版社年份 / 不碰已有字段”配置模式运行。
- ZIP 导入预览。
- Mac 端 CLI 作为离线辅助工具，但仍不直接写 CloudKit。

## 18. 推荐实施顺序

最推荐的顺序：

1. 先做 AI patch domain 和测试。
2. 再做 `validateAIPatch` / `applyAIPatch`。
3. 再开放局域网 session 的 snapshot / validate / apply。
4. 最后做 Codex skill。

原因：

- patch 规则是安全核心。
- apply 直接写库，必须先把字段保护、冲突检测、封面限制和逐条结果做扎实。
- 局域网只是传输层，不能先于数据安全模型。
