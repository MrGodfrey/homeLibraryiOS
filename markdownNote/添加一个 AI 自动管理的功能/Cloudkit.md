# CloudKit CLI + Codex Skill：最终实施计划

## 1. 结论

最终方案：

- 不做完整 Mac App。
- 不做 iPhone 本地接口。
- 不做网页后台。
- 做一个自研 macOS Swift 命令行工具。
- 再做一个 Codex Skill，让 Codex 通过这个 CLI 管理书库。

工具名称建议：

```text
home-library-cloudkit
```

只要 Mac 和 iPhone 登录的是同一个 iCloud 账号，并且 CLI 使用同一个 CloudKit container、同一个 CloudKit environment，那么 CLI 写入 CloudKit 后，iPhone app 会通过现有 CloudKit 同步看到这些修改。

这不是修改 iPhone 本地数据，也不是修改本地缓存。正确链路是：

```text
Codex Skill
  -> home-library-cloudkit CLI
  -> CloudKit private/shared database
  -> iPhone app 同步刷新
```

CLI 必须是一个带 CloudKit entitlement、被 Xcode/codesign 正确签名的 macOS executable。它不是裸 Swift 脚本。

## 2. 产品边界

CLI 是正式产品能力。Codex Skill 是正式产品能力。

CLI 负责：

- 访问 CloudKit。
- 导出 AI 工作包。
- 生成缺失项和重复项报告。
- 校验 AI patch。
- 展示本地确认页面。
- 在用户确认后应用 patch。
- 输出机器可读 apply result。

Codex Skill 负责：

- 调用 CLI。
- 阅读 AI 工作包。
- 查询 ISBN 和出版信息。
- 准备封面候选并记录来源；最终压缩和写入由 CLI 复用 App 现有逻辑完成。
- 生成 `.homelibpatch`。
- 启动确认流程。
- apply 后总结结果。

不做：

- 不让 Codex 直接拿 CloudKit 凭据。
- 不让 Codex 直接改 `cloudkit-cache`。
- 不让 Codex 操作 CloudKit Console。
- 不通过第三方后端中转个人书库。
- 不把 Apple ID、账号信息、真实快照或 patch 提交到开源仓库。

## 3. CLI 基础要求

### 3.1 签名与权限

CLI target 需要：

- 明确 bundle identifier，例如 `yu.homeLibrary.cloudkit-cli`。
- 同一个 Apple Developer Team。
- 同一个 CloudKit container entitlement。
- `com.apple.developer.icloud-services = CloudKit`。
- `com.apple.developer.icloud-container-identifiers` 包含当前 app 的 container：`iCloud.yu.homeLibrary`。
- CloudKit environment 必须和目标数据一致：App Store / TestFlight 数据使用 Production；Xcode Debug / 模拟器数据按当前签名 entitlement 对应环境验证。

必须提供检查命令：

```bash
home-library-cloudkit doctor
```

`doctor` 检查：

- 当前 executable 是否带 entitlement。
- 当前 CloudKit environment。
- 当前 iCloud account status。
- private database 是否可访问。
- shared database 是否可访问。
- `.derived/AIWorkflow/` 是否被忽略。
- `markdownNote/test` 是否被忽略，如果本机仍保留账号说明文件。

`doctor` 不输出 Apple ID、邮箱、密码或任何账号文件内容。

### 3.2 输出规则

CLI 默认面向 Codex 和脚本。

- stdout 只输出 JSON。
- stderr 输出进度、人类提示和本地确认 URL。
- 错误也输出 JSON，并使用非 0 exit code。
- 所有结果文件默认写到 `.derived/AIWorkflow/`。

### 3.3 与当前 App 实现对齐

CLI 必须复用或抽出当前 App 的 domain、CloudKit 和封面处理代码，不能重新臆造一套数据模型。

当前实现事实：

- `Book` 只保存 `coverAssetID`，书籍 payload 不包含封面二进制。
- CloudKit 书籍 record 使用 `coverAssetID` 字符串字段和 `coverAsset` 这个 `CKAsset` 保存封面数据。
- 本地 cache 将书籍 JSON 写到 `cloudkit-cache/<repo>/books/<bookID>.json`，将封面写到 `cloudkit-cache/<repo>/covers/<coverAssetID>.bin`。
- 导入/导出包为了迁移方便，会在 `LibraryImportBook.coverData` 中嵌入封面数据；这不代表常规书籍元数据里嵌入封面。
- `coverAssetID` 是最终写入封面数据的 SHA-256：`cover-<hex>`。
- 保存书籍时，现有链路是 `BookDraft.coverData` -> `LibraryCoverCompressor.compressIfNeeded` -> `CloudKitLibraryService.upsertBook(... coverData:)` -> `CKAsset`。
- 未传新封面且保留 `book.coverAssetID` 时，现有封面会保留；传入空封面且 `coverAssetID == nil` 时，CloudKit 的 `coverAssetID` 和 `coverAsset` 会被清掉。
- 现有删除语义是删除 CloudKit 里的 `book.<id>` record，不是软删除。
- 现有 `RemoteBookSnapshot` 只有 `Book` 和 `coverData`；CLI 若要在 workspace 中输出 `recordChangeTag`，需要在 CloudKit CLI 层额外保留 CKRecord metadata，或扩展共享 snapshot 类型。

对应源码：

- `homeLibrary/Book.swift`
- `homeLibrary/LibraryStore.swift`
- `homeLibrary/LibrarySync.swift`
- `homeLibrary/LibraryPersistence.swift`
- `homeLibrary/LibraryCoverCompression.swift`

## 4. 命令设计

### 4.1 `doctor`

```bash
home-library-cloudkit doctor
```

输出示例：

```json
{
  "ok": true,
  "bundleID": "yu.homeLibrary.cloudkit-cli",
  "containerID": "iCloud.yu.homeLibrary",
  "environment": "Production",
  "accountStatus": "available",
  "canAccessPrivateDatabase": true,
  "canAccessSharedDatabase": true,
  "warnings": []
}
```

### 4.2 `repos`

```bash
home-library-cloudkit repos
```

列出当前账号可访问仓库：

```json
{
  "repositories": [
    {
      "id": "library.xxx",
      "name": "家藏万卷",
      "role": "owner",
      "databaseScope": "private",
      "zoneID": "zone.xxx",
      "canWrite": true,
      "bookCount": 120,
      "locationCount": 2
    }
  ]
}
```

### 4.3 `export-ai-workspace`

```bash
home-library-cloudkit export-ai-workspace \
  --repo <repo-id> \
  --output .derived/AIWorkflow/workspace.zip
```

输出：

```text
AIWorkspace.zip
  manifest.json
  LibrarySnapshot.json
  MissingMetadataReport.json
  DuplicateCandidates.json
  CoverStatus.json
  Locations.json
  PatchSchema.json
  README.md
```

默认不导出封面二进制，只导出 `coverAssetID`、`hasCover`、本地可读时的封面字节数和图片尺寸等状态。需要人工确认封面差异时，`review-patch` 可以从 patch 候选封面和当前 `coverAssetID` 加载临时缩略图，但这些临时文件仍放在 `.derived/AIWorkflow/`。

### 4.4 `validate-patch`

```bash
home-library-cloudkit validate-patch \
  .derived/AIWorkflow/suggested.homelibpatch \
  --result .derived/AIWorkflow/PatchValidationResult.json
```

只校验，不写 CloudKit。

校验：

- schemaVersion。
- 目标仓库。
- databaseScope / zoneID。
- operation 数量和文件大小。
- ISBN。
- locationID。
- 封面数据必须能被 ImageIO 解码，推荐 JPEG；CLI 必须用 `LibraryCoverCompressor.compressIfNeeded` 得到最终写入数据。
- 封面最终结果的 `coverAssetID`、字节数和像素尺寸。
- `expectedUpdatedAt`。
- `expectedRecordChangeTag`。
- 字段 mode。
- 重复 ISBN。
- 相似标题。
- 删除操作是否允许。

### 4.5 `review-patch`

```bash
home-library-cloudkit review-patch \
  .derived/AIWorkflow/suggested.homelibpatch \
  --repo <repo-id> \
  --result .derived/AIWorkflow/ReviewDecision.json
```

用途：打开本地浏览器确认页，让用户看清楚本次要做什么。

实现方式：

- CLI 在 Mac 本机启动一个只绑定 `127.0.0.1` 的临时 HTTP server。
- 生成一次性 token。
- 打开类似下面的链接：

```text
http://127.0.0.1:<random-port>/review?token=<one-time-token>
```

- 页面展示新增、修改、删除、跳过、冲突和低置信度项目。
- 用户点击 Approve 或 Reject。
- CLI 收到本机 POST 后写入 `ReviewDecision.json`。
- server 立即关闭。
- 如果超时，返回 rejected/timeout。

这是本机 loopback review UI，不是局域网服务：

- 不绑定 `0.0.0.0`。
- 不做 Bonjour。
- 不需要 iPhone 参与。
- 不长期运行。
- 不接收 patch 之外的任意代码。

### 4.6 `apply-patch`

```bash
home-library-cloudkit apply-patch \
  .derived/AIWorkflow/suggested.homelibpatch \
  --review-decision .derived/AIWorkflow/ReviewDecision.json \
  --result .derived/AIWorkflow/ApplyResult.json
```

默认规则：

- 没有 review decision 时，只允许非破坏性低风险操作。
- 新增大量书籍、删除书籍、替换非空字段、替换封面等必须有 approve。
- apply 前强制刷新 CloudKit。
- apply 后输出完整结果。

## 5. 本地确认页面设计

确认页要让人能看清楚，不要求复杂。

页面分区：

- Summary
- Creates
- Updates
- Deletes
- Cover changes
- Conflicts
- Skipped
- Evidence
- Raw JSON download

Summary 展示：

- 本次 patch 来源。
- 目标仓库。
- 生成时间。
- 新增数量。
- 更新数量。
- 删除数量。
- 冲突数量。
- 低置信度数量。

每条操作展示：

- 操作类型。
- 书名。
- 作者。
- ISBN。
- 当前值。
- 新值。
- 封面缩略图。
- 当前 `coverAssetID`、新 `coverAssetID`、封面来源 URL、压缩前后大小。
- evidence URL。
- confidence。
- 风险标签。

Approve 前要求：

- 删除操作数量大于 0 时，页面显式显示红色危险区。
- 替换非空字段时，必须显示 old -> new。
- 替换或移除已有封面时，必须显示当前封面和新封面/空封面。
- 低置信度操作默认不应用，除非用户勾选“包含低置信度项”。
- 页面显示 apply 后不可保证自动恢复，需要依赖 CloudKit 历史和备份。

输出 `ReviewDecision.json`：

```json
{
  "approved": true,
  "approvedAt": "2026-06-22T10:30:00.000Z",
  "patchDigest": "sha256.xxx",
  "approvedOperationIDs": ["op-001", "op-002"],
  "rejectedOperationIDs": ["op-009"],
  "includeLowConfidence": false
}
```

## 6. Patch 文件格式

扩展名：

```text
.homelibpatch
```

顶层结构：

```json
{
  "schemaVersion": 1,
  "source": "codex-home-library-curator",
  "createdAt": "2026-06-22T10:00:00.000Z",
  "targetRepository": {
    "id": "library.xxx",
    "name": "家藏万卷",
    "databaseScope": "private",
    "zoneID": "zone.xxx"
  },
  "baseSnapshot": {
    "id": "snapshot.xxx",
    "createdAt": "2026-06-22T09:50:00.000Z",
    "changeTokenDigest": "sha256.xxx"
  },
  "operations": [],
  "notes": []
}
```

## 7. Patch 操作

### 7.1 新增书籍

```json
{
  "op": "createBook",
  "clientOperationID": "op-001",
  "confidence": 0.92,
  "idempotencyKey": "isbn:9780000000000",
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
    "kind": "coverDataBase64",
    "preferredMimeType": "image/jpeg",
    "originalPixelSize": {
      "width": 1200,
      "height": 1800
    },
    "compressedPixelSize": {
      "width": 480,
      "height": 720
    },
    "compressedByteSize": 120000,
    "expectedCoverAssetID": "cover-<sha256-after-compression>",
    "sourceURL": "https://example.com/cover.jpg",
    "data": ""
  },
  "evidence": [],
  "warnings": []
}
```

规则：

- `title` 和 `locationID` 必填。
- ISBN 必须合法或为空。
- 新增书籍可以带封面候选数据；写入前由 CLI 复用 App 压缩规则得到最终 `coverAssetID`。
- 写入前检查重复 ISBN 和相似标题。
- 大批量新增必须经过 review page approve。

### 7.2 更新字段

```json
{
  "op": "updateBook",
  "clientOperationID": "op-002",
  "id": "existing-book-id",
  "expectedUpdatedAt": "2026-05-04T12:00:00.000Z",
  "expectedRecordChangeTag": "abc123",
  "confidence": 0.88,
  "fields": {
    "publisher": {
      "mode": "fillIfEmpty",
      "value": "示例出版社"
    },
    "year": {
      "mode": "replaceIfCurrentValue",
      "expectedValue": "2023",
      "value": "2024"
    }
  },
  "evidence": [],
  "warnings": []
}
```

字段模式：

- `fillIfEmpty`：当前字段为空才写入。
- `replaceIfCurrentValue`：当前字段必须等于 `expectedValue` 才写入。

### 7.3 更新封面

```json
{
  "op": "updateBookCover",
  "clientOperationID": "op-003",
  "id": "existing-book-id",
  "expectedUpdatedAt": "2026-05-04T12:00:00.000Z",
  "expectedRecordChangeTag": "abc123",
  "confidence": 0.9,
  "expectedCurrentCoverAssetID": null,
  "cover": {
    "kind": "coverDataBase64",
    "preferredMimeType": "image/jpeg",
    "originalPixelSize": {
      "width": 1200,
      "height": 1800
    },
    "compressedPixelSize": {
      "width": 480,
      "height": 720
    },
    "compressedByteSize": 120000,
    "expectedCoverAssetID": "cover-<sha256-after-compression>",
    "sourceURL": "https://example.com/cover.jpg",
    "data": ""
  },
  "evidence": [],
  "warnings": []
}
```

默认只给缺封面的书补封面。替换已有封面必须提供 `expectedCurrentCoverAssetID`，并经过 review page approve。

### 7.4 移除封面

```json
{
  "op": "removeBookCover",
  "clientOperationID": "op-004",
  "id": "existing-book-id",
  "expectedUpdatedAt": "2026-05-04T12:00:00.000Z",
  "expectedRecordChangeTag": "abc123",
  "expectedCurrentCoverAssetID": "cover.current-sha256",
  "reason": "wrong-cover",
  "evidence": [],
  "warnings": ["Destructive cover operation"]
}
```

移除规则：

- 只能清除 `coverAssetID` 和 `coverAsset`，不能改其他字段。
- 必须经过 review page approve。
- 如果当前 `coverAssetID` 与 `expectedCurrentCoverAssetID` 不一致，返回 conflict。
- 页面必须显示当前封面缩略图和移除原因。

### 7.5 删除书籍

```json
{
  "op": "deleteBook",
  "clientOperationID": "op-005",
  "id": "existing-book-id",
  "expectedUpdatedAt": "2026-05-04T12:00:00.000Z",
  "expectedRecordChangeTag": "abc123",
  "reason": "duplicate",
  "evidence": [],
  "warnings": ["Destructive operation"]
}
```

删除规则：

- 第一版只允许走现有 App 的删除语义：删除 CloudKit 里的 `book.<id>` record。
- 删除必须经过 review page approve。
- 删除页面必须显示书名、作者、ISBN、地点和删除原因。
- 不允许 Codex 静默删除。
- 如果 CloudKit 当前记录已变化，删除失败并返回 conflict。

## 8. 封面规则

封面规则必须和当前 App 保持一致。

当前 App 规则：

- 存储层把封面当作 opaque `Data`，本地扩展名是 `.bin`，CloudKit 字段是 `coverAsset` / `CKAsset`。
- 书籍记录只保存 `coverAssetID`，不保存 `coverData`。
- `coverAssetID` 必须基于最终写入数据计算 SHA-256，格式是 `cover-<hex>`。
- 压缩逻辑使用 `LibraryCoverCompressor.compressIfNeeded`。
- 当前压缩阈值是最长边 `720 px`、目标大小 `220 KB`。
- 当前 JPEG 质量阶梯是 `0.82, 0.72, 0.62, 0.52, 0.42`。
- 如果原图最长边不超过 `720 px` 且数据不超过 `220 KB`，现有逻辑会保留原始数据，不强制重编码。
- 如果需要压缩，现有逻辑会用 ImageIO 生成最长边不超过 `720 px` 的缩略图，并输出带白色背景的 JPEG。

CLI 规则：

- patch 输入推荐 `image/jpeg`，也可以接受 ImageIO 可解码的 PNG/JPEG 等图片数据。
- CLI 必须再次调用 `LibraryCoverCompressor.compressIfNeeded`，不能信任 Codex 预先填写的尺寸或大小。
- `expectedCoverAssetID` 只是校验辅助；实际写入以 CLI 压缩后的数据和 SHA-256 为准。
- `sourceURL` 必填，除非封面来自用户本机文件且 review page 明确展示文件来源。
- `review-patch` 必须展示压缩后的候选封面，不展示原始大图。
- `export-ai-workspace` 默认不导出封面二进制，避免 workspace 过大；只在用户要求检查封面或 patch 自身要改封面时携带候选封面数据。

## 9. CloudKit 写入与冲突处理

### 9.1 同步前提

apply 前必须：

1. 拉取目标仓库最新 record zone changes。
2. 合并远端新增、修改、删除。
3. 更新本地 cache 和 change token。
4. 基于最新状态重新 validate。

### 9.2 保存策略

更新已有记录：

- 先 fetch 当前 CloudKit record，拿到最新字段和 `recordChangeTag`。
- 只改当前 App 已定义的业务字段：`title`、`author`、`locationID`、`payload`、`coverAssetID`、`coverAsset`、`schemaVersion`、`createdAt`、`updatedAt`。
- 现有 `CloudKitLibraryService` 使用 `modifyRecords(savePolicy: .changedKeys)` 写入；CLI 可以复用这条路径，但 AI patch apply 必须在写入前完成 `expectedUpdatedAt` / `expectedRecordChangeTag` / 字段值校验。
- 如果为 CLI 增加更严格写入路径，优先使用 CloudKit 原生 `ifServerRecordUnchanged` 语义。
- 不用全字段覆盖已有 record，不写 patch 没声明的字段。
- 封面写入必须通过 `coverAsset` / `CKAsset`，并同步更新 `coverAssetID`。

如果服务端记录更新：

- 返回 conflict。
- 不自动合并，不为了 AI patch 复制 server record 后重试覆盖。
- 在 review/apply result 中展示 server/client 差异摘要。

### 9.3 冲突矩阵

| 场景 | 处理 |
| --- | --- |
| `expectedUpdatedAt` 不匹配 | conflict |
| `expectedRecordChangeTag` 不匹配 | conflict |
| CloudKit 返回 server record changed | conflict |
| 当前字段非空且 mode 是 `fillIfEmpty` | skipped |
| 当前字段与 `expectedValue` 不一致 | conflict |
| 当前 `coverAssetID` 与 `expectedCurrentCoverAssetID` 不一致 | conflict |
| 当前已有封面但 patch 只允许补缺失封面 | skipped |
| 书籍已被删除 | skipped |
| 地点已被删除 | skipped |
| ISBN 已存在于其他书 | skipped |
| 标题高度相似且无 ISBN | needsReview |
| shared 仓库无写权限 | failed |
| iCloud 账号不可用 | failed |
| 网络临时失败 | retryable failed |

## 10. Codex Skill

Skill 名称建议：

```text
home-library-curator
```

这是交付物，不只是文档。

### 10.1 Skill 职责

Skill 负责：

- 运行 `home-library-cloudkit doctor`。
- 选择或确认目标仓库。
- 导出 `AIWorkspace.zip`。
- 读取 snapshot、缺失项、重复项、封面状态。
- 根据用户请求查询资料。
- 生成 `.homelibpatch`。
- 调用 `validate-patch`。
- 必要时调用 `review-patch` 打开本地确认页。
- 用户批准后调用 `apply-patch`。
- 读取 `ApplyResult.json`。
- 向用户汇报成功、跳过、冲突和失败项。

### 10.2 Skill 规则

Skill 必须遵守：

- 不读取 `markdownNote/test`。
- 不输出账号、邮箱、密码、token。
- 不直接改 CloudKit。
- 不直接改 `cloudkit-cache`。
- 不生成删除操作，除非用户明确要求删除或去重。
- 删除、替换非空字段、替换已有封面、大批量新增必须走 `review-patch`。
- 移除封面必须走 `review-patch`，并显示当前封面。
- Skill 可以预处理封面以减小 patch，但不得跳过 CLI 的最终压缩和 `coverAssetID` 校验。
- 每个联网查询结果必须记录 evidence URL。
- 中文书优先中文出版信息。
- ISBN 冲突时不猜，进入 needsReview。
- 低置信度操作默认不 apply。
- apply 前必须先 validate。
- apply 后必须读取 result，而不是只看 exit code。

### 10.3 Skill 工作流

用户说“帮我导入这些书”时：

1. `doctor`
2. `repos`
3. `export-ai-workspace`
4. 查询 ISBN / 出版信息 / 封面
5. 生成 patch
6. `validate-patch`
7. `review-patch`
8. 用户在浏览器确认
9. `apply-patch`
10. 总结结果

用户说“帮我整理缺失项”时：

1. `export-ai-workspace`
2. 读取 `MissingMetadataReport.json`
3. 查询资料
4. 生成只补空字段的 patch
5. validate
6. review
7. apply

用户说“帮我删除重复书”时：

1. 读取 `DuplicateCandidates.json`
2. 生成候选删除建议
3. 必须打开 review page
4. 用户确认后才生成或 apply `deleteBook`

## 11. 真实账号测试与开源安全

不再要求配置单独测试 Apple ID。CloudKit live 测试使用当前 Mac 系统已登录的真实 iCloud 账号；iPhone 或 `iPhone 17 Pro` 模拟器需要登录同一个账号才能验证跨端同步。

- 不提交 Apple ID、邮箱、密码、验证码、恢复密钥或任何账号说明。
- CLI 不自动登录 Apple ID，不读取账号配置文件，只检查当前系统 CloudKit account status。
- `markdownNote/test` 只作为遗留本机说明文件处理；如果存在，必须保持 git ignored，且 Skill / CLI / 测试都不读取、不打印、不复制该文件内容。
- live test 默认使用 `AIWorkflowTest-*` 独立测试仓库，不直接拿主书库做破坏性测试。
- 对真实主书库执行修改前，必须先导出当前 workspace / backup 到 `.derived/AIWorkflow/`，再通过 `review-patch` 确认高风险操作。
- 真实 snapshot、patch、workspace、apply result 默认写到 `.derived/AIWorkflow/`。
- `.derived` 必须保持 git ignored。

当前测试环境：

- Mac 和 iPhone 登录当前真实 iCloud 账号时，CLI 写入的 CloudKit 数据会同步到 iPhone。
- Xcode 的 `iPhone 17 Pro` 模拟器登录同一个真实 iCloud 账号后，可用于验证 iOS 端同步可见性。
- 导出能力用于降低风险，但不等同于自动回滚；删除书籍、替换非空字段、替换或移除已有封面仍必须走确认页。

## 12. 测试计划

### 12.1 默认单元测试

不访问 CloudKit：

- patch 解码。
- schema 版本。
- target repository。
- operation 数量上限。
- patch 大小上限。
- ISBN 校验。
- missing report。
- duplicate report。
- cover status。
- cover patch 输入解码。
- `LibraryCoverCompressor` 最长边 `720 px`、目标 `220 KB` 规则。
- `coverAssetID` 基于最终写入数据 SHA-256 生成。
- workspace 导出能携带 CloudKit `recordChangeTag` 或等价冲突校验 metadata。
- `fillIfEmpty`。
- `replaceIfCurrentValue`。
- `deleteBook` 必须要求 review approval。
- `removeBookCover` 必须要求 review approval。
- `expectedUpdatedAt`。
- `expectedRecordChangeTag`。
- apply result 编码。

### 12.2 Memory Remote 集成测试

不访问 CloudKit：

- 导出 workspace。
- validate patch。
- review decision 过滤 operation。
- apply patch。
- 新增、修改、补封面、替换封面、移除封面、按 CloudKit record 删除书籍。
- cache 中书籍 metadata 与 `covers/<coverAssetID>.bin` 分离。
- 导出包 `LibraryImportBook.coverData` 嵌入封面数据。
- 单条失败不阻塞其他安全操作。
- 整包错误不写入。
- 重复 apply 幂等。

### 12.3 本地确认页测试

覆盖：

- 只绑定 `127.0.0.1`。
- token 错误时拒绝。
- Approve 写入 `ReviewDecision.json`。
- Reject 写入 rejected。
- 超时返回 timeout。
- 删除操作显示危险区。
- 替换非空字段显示 old -> new。
- 替换或移除封面显示当前封面和候选结果。
- 低置信度默认不勾选。

### 12.4 CloudKit Live Preflight

显式开启：

```text
HOME_LIBRARY_CLOUDKIT_LIVE_TESTS=1
HOME_LIBRARY_CLOUDKIT_CONTAINER=iCloud.yu.homeLibrary
HOME_LIBRARY_TEST_REPOSITORY_PREFIX=AIWorkflowTest
HOME_LIBRARY_TEST_SIMULATOR_NAME=iPhone 17 Pro
```

检查：

- CLI 已 codesign 且带 CloudKit entitlement。
- container id 正确。
- CloudKit environment 与目标 App 数据一致。
- iCloud account status 可用。
- 如果 `markdownNote/test` 存在，它必须被 git ignore。
- `.derived/AIWorkflow/` 被 git ignore。
- `iPhone 17 Pro` 模拟器 booted。

### 12.5 CloudKit Live 测试

使用独立测试仓库：

```text
AIWorkflowTest-<yyyyMMdd-HHmmss>-<short-random>
```

覆盖：

- CLI 创建或发现测试仓库。
- CLI 新增地点。
- CLI 新增书籍含封面。
- CLI 刷新后能读回 `coverAssetID` 和 `coverAsset` 数据。
- CLI 编辑字段。
- CLI 移除封面。
- CLI 按现有 App 语义删除书籍 record。
- CLI 导出 AI workspace。
- CLI validate / review / apply patch。
- iPhone 模拟器刷新后可见 CLI 写入内容。
- iPhone 修改同一本书后，CLI apply 旧 patch 返回 conflict。
- 增量刷新使用 change token。
- 测试结束清理测试仓库。

### 12.6 Codex Skill 验收

覆盖：

- Skill 能调用 CLI 完成 doctor。
- Skill 能导出 workspace。
- Skill 能生成 patch。
- Skill 能打开 review page。
- Skill 能等待用户批准。
- Skill 能 apply。
- Skill 能读取 result 并汇报。
- Skill 不读取 `markdownNote/test`。
- Skill 不绕过 review 删除书。

## 13. 实现拆分

建议新增：

- `HomeLibraryCloudKitCLI` target。
- `Sources/HomeLibraryCloudKitCLI/main.swift`。
- `LibraryCLICommand.swift`。
- `LibraryCLIOutput.swift`。
- `AIWorkspaceExporter.swift`。
- `LibraryAIPatch.swift`。
- `LibraryAIPatchValidator.swift`。
- `LibraryAIPatchApplier.swift`。
- `LibraryAIPatchApplyResult.swift`。
- `LibraryAICoverPayload.swift`。
- `PatchReviewServer.swift`。
- `PatchReviewHTMLRenderer.swift`。

必须复用或抽出的现有能力：

- `Book` / `BookPayload` / `BookDraft`
- `LibraryLocation`
- `LibraryRepositoryReference`
- `CloudKitLibraryService`
- `LibraryCacheStore`
- `LibraryCoverCompressor`

建议新增 Codex Skill：

```text
skills/home-library-curator/SKILL.md
```

Skill 可配套脚本：

```text
skills/home-library-curator/scripts/generate_patch.py
skills/home-library-curator/scripts/prepare_cover.py
skills/home-library-curator/scripts/read_apply_result.py
```

## 14. 实施顺序

1. 抽出 domain / CloudKit / patch 共享层。
2. 新建 signed macOS CLI target。
3. 实现 `doctor`。
4. 实现 `repos`。
5. 实现 `export-ai-workspace`。
6. 抽出并接入封面 payload、`LibraryCoverCompressor`、`coverAssetID` 生成。
7. 实现 patch schema 和 validator。
8. 实现本地 review page。
9. 实现 memory remote apply。
10. 接入真实 CloudKit apply。
11. 补 CloudKit live tests。
12. 新增 Codex Skill。
13. 用 Skill 跑完整导入书籍验收。

这个方案复杂度可控。本地 review page 是一个短时 loopback server 和静态 HTML 渲染，不需要完整 Web app；它换来的是用户能清楚确认 Codex 即将新增、修改或删除什么。
