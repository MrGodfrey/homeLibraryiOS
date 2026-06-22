# Mac Companion App + AI Workflow：实施计划

## 1. 结论

推荐把 Mac target 做成一个完整但克制的 `homeLibrary` macOS 伴随应用，而不是只做一个 `.homelibpatch` 导入器。

它的定位是：

- 正常用户可以在 Mac 上浏览、搜索、编辑和导出书库。
- Codex / AI 可以通过 Mac App 导出的结构化工作包理解书库状态。
- Codex 在本地生成 `.homelibpatch`。
- Mac App 导入、校验并应用 patch。
- 所有写入仍然走 CloudKit，而不是修改本地缓存或绕过 app 写数据库。

这样 Mac App 不是 iPhone app 的远程控制器，而是同一个 CloudKit 书库的 macOS 客户端。AI 工作流只是这个 Mac 客户端上的一个高级导入/整理能力。

## 2. 为什么要做完整一点

只做 patch 导入器虽然实现最小，但会让 Codex 缺少上下文：

- Codex 不知道当前书库有哪些书。
- Codex 不知道哪些字段缺失。
- Codex 不知道哪些书已经有封面。
- Codex 需要靠 Computer Use 在 UI 里翻找信息，效率低且不稳定。

完整 Mac App 可以提供原生的 AI 工作入口：

- 导出当前书库快照。
- 导出缺失项报告。
- 导出疑似重复报告。
- 导出压缩封面状态表。
- 导入 AI patch。
- 应用 patch 后输出机器可读结果。

Computer Use 只负责点击标准 UI；数据交换主要通过文件完成。

## 3. 审核与分发判断

### 3.1 iOS App Store 审核

如果 Mac App 是独立 macOS target，并且不作为 iOS app 的隐藏功能提交到 iOS App Store，那么它不会直接触发 iOS app 审核。

iOS app 审核关注的是：

- iOS binary 本身。
- iOS 元数据。
- iOS 可见功能。
- iOS 是否隐藏远程控制、下载代码或绕过审核。

Mac App 不应该写进 iOS app 的功能描述里，也不应该让 iOS app 依赖它才能完成核心使用。

### 3.2 Mac App 分发

Mac App 可以不上传 Mac App Store。更推荐：

- 本机开发阶段：Xcode 直接运行。
- 自用或小范围分发：Developer ID 签名，必要时 notarize。
- 不走 Mac App Store Review。

Apple 官方文档说明，同一开发团队的多个 app 可以共享 CloudKit container；Mac App Store 之外分发的 macOS app 可以用 Developer ID 签名，Developer ID 软件也可以使用 CloudKit 等能力。

参考：

- Apple Xcode Help: <https://help.apple.com/xcode/mac/current/en.lproj/devcae40ccb9.html>
- Apple Developer ID: <https://developer.apple.com/developer-id/>
- Apple macOS distribution: <https://developer.apple.com/macos/distribution/>

### 3.3 数据访问边界

这不是“操作同一个本地数据库文件”。

正确模型是：

- iOS app 和 Mac app 属于同一开发团队。
- 两个 app 都声明同一个 CloudKit container entitlement。
- 两个 app 都访问用户自己的 iCloud / CloudKit 数据。
- Mac App 写 CloudKit 后，iOS app 通过现有同步路径看到变化。

本地 `cloudkit-cache` 仍然只是缓存，不是跨 app 共享数据库，也不允许 Codex 直接改。

## 4. 产品形态

新增 macOS target，名称建议：

```text
HomeLibraryMac
```

主窗口采用三栏结构：

```text
Sidebar
  - 仓库
  - 地点
  - 智能筛选
  - AI 工作区

Content
  - 书籍表格 / 书墙
  - 搜索结果
  - 缺失项列表
  - 重复候选列表

Inspector
  - 书籍详情
  - 编辑表单
  - 封面
  - CloudKit / patch 状态
```

第一版优先做效率型 Mac UI，不做营销页或复杂视觉。

## 5. 核心功能

### 5.1 书库浏览器

能力：

- 查看当前 iCloud 账号状态。
- 查看可访问仓库列表。
- 区分 owner / shared 仓库。
- 切换仓库。
- 查看地点列表。
- 按地点筛选。
- 搜索标题、作者、译者、ISBN、出版社。
- 表格列展示：
  - 书名
  - 作者
  - 译者
  - 出版社
  - 年份
  - ISBN
  - 地点
  - 是否有封面
  - 更新时间
  - 共享/权限状态

智能筛选：

- 缺 ISBN。
- 缺出版社。
- 缺年份。
- 缺封面。
- 缺译者。
- 疑似重复 ISBN。
- 疑似重复标题。
- 低质量元数据。

### 5.2 书籍编辑器

能力：

- 新增书籍。
- 编辑书籍字段。
- 更换封面。
- 删除封面。
- 移动地点。
- 保存前展示 CloudKit 写入结果。

第一版仍不建议开放硬删除书籍；如果需要删除，沿用现有软删除或 iOS 已有删除语义。

编辑保存规则：

- 手工编辑走普通 `LibraryStore.saveBook`。
- 保存前持有当前书籍的 `updatedAt` / CloudKit change tag。
- 保存时使用 CloudKit 原生冲突检测。
- 如果服务端记录已更新，提示用户刷新或手动合并，不静默覆盖。

### 5.3 导出能力

Mac App 需要比 iOS app 更适合作为 AI 工作站。

导出格式：

- `LibrarySnapshot.json`
- `MissingMetadataReport.json`
- `DuplicateCandidates.json`
- `CoverStatus.json`
- `AIWorkspace.zip`

`AIWorkspace.zip` 建议包含：

```text
LibrarySnapshot.json
MissingMetadataReport.json
DuplicateCandidates.json
CoverStatus.json
PatchSchema.json
README.md
```

导出原则：

- 默认不导出封面二进制。
- 只导出 `hasCover`、封面尺寸、封面更新时间等状态。
- 用户明确选择时，才导出压缩封面缩略图。
- 导出文件写入本地，不上传第三方服务。

### 5.4 AI Patch 导入

支持文件：

```text
.homelibpatch
```

导入方式：

- SwiftUI `.fileImporter`。
- 拖拽文件到 AI 工作区。
- Finder 双击 `.homelibpatch` 打开。
- Codex 用 `open /path/to/file.homelibpatch` 交给 Mac App。

导入后流程：

1. 解码 JSON。
2. 校验 schema。
3. 校验目标仓库。
4. 拉取最新 CloudKit 变更。
5. 逐条 validate。
6. 显示摘要。
7. Apply。
8. 逐条写入 CloudKit。
9. 输出 apply result。

### 5.5 AI 工作区

AI 工作区不是聊天 UI，而是文件与结果中转站。

页面包含：

- 当前仓库。
- 生成 AI 工作包按钮。
- 最近导出的工作包路径。
- 导入 patch 区域。
- patch validate 摘要。
- apply 结果。
- 复制结果 JSON 按钮。
- 打开结果文件按钮。

Codex 最稳定的 workflow：

1. 用户打开 Mac App 的 AI 工作区。
2. Codex 点击“导出 AI 工作包”。
3. Codex 读取 `AIWorkspace.zip`。
4. Codex 查询资料并生成 `.homelibpatch`。
5. Codex 用 `open patch.homelibpatch` 交给 Mac App。
6. Mac App 显示 validate 摘要。
7. Codex 点击 Apply。
8. Codex 读取 `ApplyResult.json` 并汇报。

## 6. Patch 文件格式

文件扩展名：

```text
.homelibpatch
```

文件内容是 JSON。

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

规则：

- `schemaVersion` 必须匹配。
- `targetRepository.id` 必须匹配当前仓库。
- `databaseScope` / `zoneID` 必须匹配当前仓库引用。
- `baseSnapshot` 只用于冲突提示，不能代替 CloudKit 当前状态校验。
- `operations` 有数量上限，例如第一版最多 `200` 条。
- patch 总大小有上限，例如第一版最多 `20 MB`。

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

新增规则：

- `title` 和 `locationID` 必填。
- `isbn` 如果存在，必须通过 ISBN-10 / ISBN-13 校验。
- 第一版新增书籍必须带封面缩略图。
- `idempotencyKey` 用于避免同一个 patch 重复 apply。
- 写入前必须用当前 CloudKit 数据检查重复 ISBN 和重复标题。

### 7.2 更新书籍字段

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

第一版不允许：

- `deleteField`
- `deleteBook`
- 任意 CloudKit record 原始字段写入
- 无条件覆盖非空字段

### 7.3 补全既有书籍封面

```json
{
  "op": "updateBookCover",
  "clientOperationID": "op-003",
  "id": "existing-book-id",
  "expectedUpdatedAt": "2026-05-04T12:00:00.000Z",
  "expectedRecordChangeTag": "abc123",
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
  "evidence": [],
  "warnings": []
}
```

封面补全规则：

- 只给当前没有封面的书补封面。
- 当前已经有封面时，第一版跳过。
- 必须校验 `expectedUpdatedAt` 或 `expectedRecordChangeTag`。
- 封面只作为 iOS 小略缩图，不导入原始大图。

## 8. 封面压缩规则

封面只服务于 iOS 小略缩图。

- 只接受 `image/jpeg`。
- 推荐尺寸 `160 x 240 px`。
- 长边硬上限 `300 px`。
- JPEG 质量建议 `0.35 - 0.45`。
- 目标大小不超过 `30 KB`。
- 单张硬上限 `60 KB`。
- `sourceURL` 必填。
- 不允许传入原始大图、PNG 截图或网页整图。

Mac App 校验：

- base64 可解码。
- JPEG magic bytes 合法。
- 像素尺寸不超过限制。
- `byteSize` 与实际数据大小一致或接近。
- 单个 patch 的封面总大小不超过上限。

## 9. CloudKit 原生同步与冲突处理

### 9.1 推荐同步模型

Mac App 应尽量复用当前 iOS app 的 CloudKit service 和 cache 逻辑。

推荐路径：

1. 使用现有仓库发现逻辑。
2. 使用同一个 custom zone。
3. 使用 record zone change token 做增量刷新。
4. apply 前强制拉取当前 zone 最新变更。
5. apply 后保存新的 change token。
6. apply 后刷新本地 cache。

Apple 官方 CloudKit API 中：

- `CKFetchRecordZoneChangesOperation` / `recordZoneChanges` 用于获取指定 zone 内创建、更新和删除的 record 变化。
- `CKServerChangeToken` 用于记录增量同步位置。
- `CKModifyRecordsOperation.RecordSavePolicy.ifServerRecordUnchanged` 用于仅在服务端 record change tag 未变时保存。
- `CKError.Code.serverRecordChanged` 表示服务端版本比客户端要保存的版本新。
- `CKError` 的 `ancestorRecord`、`clientRecord`、`serverRecord` 可用于冲突分析。
- `CKSyncEngine` 可以降低自建同步引擎复杂度，但本仓库已有自定义 CloudKit 层，第一版不强制迁移。

参考：

- `CKFetchRecordZoneChangesOperation`: <https://developer.apple.com/documentation/cloudkit/ckfetchrecordzonechangesoperation>
- `CKServerChangeToken`: <https://developer.apple.com/documentation/cloudkit/ckserverchangetoken>
- `CKModifyRecordsOperation.RecordSavePolicy`: <https://developer.apple.com/documentation/cloudkit/ckmodifyrecordsoperation/recordsavepolicy>
- `CKError.Code.serverRecordChanged`: <https://developer.apple.com/documentation/cloudkit/ckerror/code/serverrecordchanged>
- `CKSyncEngine`: <https://developer.apple.com/documentation/cloudkit/cksyncengine-5sie5>

### 9.2 保存策略

对 AI patch 写入，默认使用保守策略：

- 更新已有 record：优先使用 `ifServerRecordUnchanged`。
- 只改业务 payload 中允许的字段。
- 不写 patch 没有声明的字段。
- 如果 CloudKit 返回 `serverRecordChanged`，该操作标记为 conflict，不自动重试覆盖。

什么时候可以用 `changedKeys`：

- 手工编辑器保存当前 UI 改过的字段时，可以考虑只保存 changed keys。
- AI patch apply 不建议依赖 `changedKeys` 来绕过冲突，因为 AI patch 的安全边界应以 `expectedUpdatedAt`、`expectedRecordChangeTag` 和字段模式为主。

什么时候不能用 `allKeys`：

- AI patch 更新已有书籍时不应使用 `allKeys` 覆盖整个 record。
- 除非创建新 record，否则避免全字段保存导致覆盖别人刚改的值。

### 9.3 Apply 前强制刷新

导入 patch 后，点击 Apply 前必须执行：

1. 拉取目标仓库最新 record zone changes。
2. 合并远端新增、修改、删除。
3. 更新本地 cache 和 change token。
4. 基于刷新后的当前状态重新 validate patch。

如果刷新失败：

- 不允许继续 apply。
- 显示 CloudKit 错误。
- 让用户稍后重试。

原因：AI patch 可能基于几分钟前的 snapshot 生成，而家庭成员或 iPhone 可能已经改过同一本书。

### 9.4 冲突判定

以下情况必须标记 conflict 或 skipped：

| 场景 | 处理 |
| --- | --- |
| `expectedUpdatedAt` 不匹配 | conflict，不写入 |
| `expectedRecordChangeTag` 不匹配 | conflict，不写入 |
| CloudKit 返回 `serverRecordChanged` | conflict，不自动合并 |
| 书籍已被删除 | skipped，原因 `bookDeleted` |
| 地点已被删除 | skipped，原因 `locationMissing` |
| 当前字段非空且 mode 是 `fillIfEmpty` | skipped，原因 `fieldNotEmpty` |
| 当前字段与 `expectedValue` 不一致 | conflict，原因 `expectedValueMismatch` |
| 当前已有封面但操作是 `updateBookCover` | skipped，原因 `coverAlreadyExists` |
| ISBN 已存在于其他书 | skipped，原因 `duplicateISBN` |
| 标题高度相似且无 ISBN | needsReview，不自动新增 |
| shared 仓库无写权限 | failed，原因 `permissionFailure` |
| iCloud 账号变化 | failed，要求重新加载仓库 |
| CloudKit zone 被删除或 share 失效 | failed，要求重新发现仓库 |

### 9.5 自动合并原则

第一版只做低风险自动合并：

- 空字段补全。
- 当前值匹配时替换。
- 缺封面时补缩略图。
- 新增不存在的 ISBN。

第一版不做：

- 两边都改了同一个字段时自动取 AI 值。
- 删除书籍。
- 合并地点。
- 替换已有封面。
- 批量覆盖出版社/年份。

如果需要人工介入，Mac App 显示 `needsReview`，但不写入。

### 9.6 Idempotency

同一个 `.homelibpatch` 可能被重复打开或重复 Apply。

处理规则：

- 每个 operation 必须有 `clientOperationID`。
- `createBook` 建议带 `idempotencyKey`。
- Mac App 维护最近 apply 的 operation digest。
- 对 `idempotencyKey` 已命中的新增操作，返回 `skippedAlreadyApplied`。
- 对已完成的字段补全，如果当前字段已等于目标值，返回 `skippedAlreadySatisfied`。

不要为了 idempotency 在 CloudKit 写入任意隐藏字段。优先用本地 apply history 和业务字段匹配判断。

## 10. AI 工作包格式

Mac App 导出的 `AIWorkspace.zip` 包含：

```text
manifest.json
LibrarySnapshot.json
MissingMetadataReport.json
DuplicateCandidates.json
CoverStatus.json
Locations.json
PatchSchema.json
README.md
```

### 10.1 LibrarySnapshot.json

包含：

- repository id / name / databaseScope / zoneID。
- snapshot id。
- snapshot 创建时间。
- change token digest。
- locations。
- books。

书籍字段：

```json
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
  "recordChangeTag": "abc123",
  "hasCover": true
}
```

默认不包含封面二进制。

### 10.2 MissingMetadataReport.json

按类别列出：

- missingISBN
- missingPublisher
- missingYear
- missingTranslator
- missingCover
- suspiciousYear
- suspiciousISBN
- lowInformationBooks

Codex 优先处理这些列表，不需要 Computer Use 在 UI 里逐本翻。

### 10.3 DuplicateCandidates.json

候选来源：

- 相同 ISBN。
- 规范化标题相同。
- 标题相似且作者相似。
- 同一套书不同册不自动视为重复，但列出供参考。

第一版只报告，不自动合并。

### 10.4 CoverStatus.json

包含：

- bookID。
- hasCover。
- coverByteSize。
- coverPixelWidth。
- coverPixelHeight。
- coverUpdatedAt。

用于让 Codex 决定是否生成 `updateBookCover`。

## 11. Mac UI 设计

### 11.1 主导航

Sidebar：

- 所有书籍
- 缺失项
- 重复候选
- 地点
- AI 工作区
- 导入/导出历史

Toolbar：

- 刷新
- 新增书籍
- 导出
- 导入 Patch
- 搜索

### 11.2 书籍表格

Mac App 应优先使用表格，而不是 iPhone 书墙。

表格支持：

- 排序。
- 多选。
- 快速筛选。
- 列显示/隐藏。
- 双击打开编辑。
- 右侧 inspector 编辑。

### 11.3 编辑器

编辑器分区：

- 基本信息。
- 出版信息。
- 位置。
- 封面。
- 自定义字段。
- CloudKit 状态。

CloudKit 状态展示：

- 最后更新时间。
- 当前 record change tag。
- 最近同步状态。
- 当前仓库权限。

### 11.4 AI 工作区

AI 工作区展示：

- 导出 AI 工作包。
- 最近工作包路径。
- 拖入 patch。
- validate 摘要。
- apply 结果。
- 打开结果 JSON。

不要做 AI chat。真正的 AI 对话仍在 Codex 里完成。

## 12. 实现拆分

建议新增 macOS 文件：

- `HomeLibraryMacApp.swift`
- `MacLibraryWindow.swift`
- `MacSidebarView.swift`
- `MacBookTableView.swift`
- `MacBookInspectorView.swift`
- `MacMissingMetadataView.swift`
- `MacDuplicateCandidatesView.swift`
- `MacAIWorkspaceView.swift`
- `MacPatchImportViewModel.swift`
- `AIWorkspaceExporter.swift`
- `LibraryAIPatch.swift`
- `LibraryAIPatchValidator.swift`
- `LibraryAIPatchApplyResult.swift`
- `LibraryAIPatchApplier.swift`

建议共享：

- `Book`
- `BookDraft`
- `LibraryLocation`
- `LibraryRepositoryReference`
- `LibraryStore` 中非 UI 部分
- `CloudKitLibraryService`
- `LibraryRemoteSyncing`
- `LibraryCacheStore`
- JSON import/export model

可能需要拆分：

- 把 iOS-only SwiftUI view 从共享 target 排除。
- 把 `LibraryStore` 中和 UIKit / iPhone lifecycle 绑定的逻辑拆出来。
- 抽出 `LibraryDomain` / `LibraryCloudKit` 共享层。

## 13. 权限、签名与环境

Mac target 需要：

- 同一个 iCloud container。
- CloudKit service entitlement。
- 正确的 Team ID。
- Production 环境配置，用于读取 iOS App Store 版数据。

注意：

- Debug 默认可能连 Development 环境。
- 如果要操作真实 iOS App Store 数据，Mac App 必须使用 Production CloudKit environment。
- 分发给自己以外的人时，建议 Developer ID 签名和 notarization。
- 如果只是本机调试，也要明确当前连接的是 Development 还是 Production，避免把 patch 写错环境。

UI 必须明显显示：

- 当前 iCloud 账号状态。
- 当前 CloudKit environment。
- 当前仓库。
- 当前权限。

## 14. 审核与产品文案

如果以后要上 Mac App Store：

- 这是完整 macOS 书库管理 app。
- AI patch 只是“导入结构化整理文件”的能力。
- 不下载或执行代码。
- 不开放本地网络服务。
- 不描述 Computer Use。

如果只 Developer ID 分发：

- 仍然建议保持同样的产品边界。
- 不把它写成远程控制工具。
- 不把 Codex 自动化写进用户可见功能。

## 15. 最小可交付范围

第一版完整 Mac companion app 做：

1. macOS target。
2. CloudKit 账号和环境显示。
3. 仓库列表和仓库切换。
4. 书籍表格浏览。
5. 搜索和地点筛选。
6. 缺失项筛选。
7. 书籍详情 inspector。
8. 手工新增/编辑书籍。
9. 导出 `AIWorkspace.zip`。
10. 导入 `.homelibpatch`。
11. validate 摘要。
12. apply patch。
13. CloudKit 原生冲突检测。
14. apply result 导出。

第一版不做：

- 不做 AI chat。
- 不做本地 HTTP server。
- 不做后台 agent。
- 不做删除书籍。
- 不做自动合并重复书。
- 不做无条件覆盖。
- 不做替换已有封面。

## 16. 测试计划

测试必须分层。默认 CI / 本地快速测试不碰真实 CloudKit；只有显式打开 live test 开关时，才使用测试 Apple ID 和真实 CloudKit 环境。

### 16.1 测试账号与密钥规则

本仓库是开源仓库，测试账号和任何可识别凭据都不能提交。

本地约定：

- `markdownNote/test` 可以保存测试 Apple ID 的本机说明或登录信息。
- `markdownNote/test` 必须保持在 `.gitignore` 中。
- 测试脚本不得把该文件内容打印到 stdout、日志、测试失败信息或截图 OCR 结果里。
- 不把 Apple ID、密码、验证码、恢复密钥、设备受信任信息写入 patch、workspace、README、log 或测试 fixture。
- 自动化测试默认不自动登录 Apple ID；登录由人手动在系统设置或模拟器里完成。

当前可用环境：

- Xcode 的 `iPhone 17 Pro` 模拟器已经手动登录了测试 Apple ID。
- 这个模拟器可用于验证 iOS 端 CloudKit live 能力、跨端冲突、共享和同步。
- Mac App live test 如果要直接访问 Production CloudKit，需要运行它的 macOS 用户会话也登录同一个测试 Apple ID，或者明确使用当前 Mac 登录账号对应的测试数据。

建议环境变量：

```text
HOME_LIBRARY_ENABLE_CLOUDKIT_LIVE_TESTS=1
HOME_LIBRARY_CLOUDKIT_ENVIRONMENT=Production
HOME_LIBRARY_TEST_REPOSITORY_PREFIX=AIWorkflowTest
HOME_LIBRARY_TEST_SIMULATOR_NAME=iPhone 17 Pro
```

不建议把测试账号和密码做成环境变量。环境变量容易被 shell history、测试报告或进程列表间接暴露。

### 16.2 测试数据隔离与清理

所有 CloudKit live test 必须创建独立测试仓库：

```text
AIWorkflowTest-<yyyyMMdd-HHmmss>-<short-random>
```

规则：

- 不在用户真实书库上跑破坏性测试。
- 每次 live test 记录创建的 repository id、zone id、book id。
- 测试结束清理测试仓库、测试地点、测试书籍和测试 share。
- 清理失败时把仓库 id 写入本地 `.derived/cloudkit-live-cleanup.json`，供下次测试启动时先清理。
- `.derived` 已被忽略，不能提交清理清单。
- 测试数据标题统一带 `AIWorkflowTest` 前缀，避免误伤真实数据。

生成的 AI 工作包和 patch 文件默认写入：

```text
.derived/AIWorkflow/
```

不要默认写入 `markdownNote/` 或仓库根目录，避免把书库快照、封面和测试账号上下文误提交。

### 16.3 不联网单元测试

覆盖纯 domain 和 patch 逻辑：

- snapshot 导出。
- `AIWorkspace.zip` manifest 生成。
- missing report 生成。
- duplicate candidates 生成。
- cover status 生成。
- patch 解码。
- schema 版本不兼容。
- 目标仓库不匹配。
- database scope / zone id 不匹配。
- operation 数量上限。
- patch 总大小上限。
- ISBN-10 / ISBN-13 校验和标准化。
- 地点不存在。
- 新增书籍字段校验。
- 重复 ISBN 跳过。
- 标题高度相似且无 ISBN 时进入 `needsReview`。
- 补空字段成功。
- 非空字段默认不覆盖。
- `replaceIfCurrentValue` 当前值匹配才覆盖。
- `expectedUpdatedAt` 冲突检测。
- `expectedRecordChangeTag` 冲突检测。
- 封面 base64、JPEG magic bytes、mime type、尺寸和大小校验。
- 已有封面时 `updateBookCover` 跳过。
- 同一个 patch 重复 apply 时幂等跳过。
- apply result JSON 稳定编码。

### 16.4 Memory Remote 集成测试

用 `InMemoryLibraryRemoteService` 或等价 fake remote 覆盖完整业务链路：

- 创建测试仓库。
- 新增地点。
- 新增书籍。
- 编辑书籍。
- 导出 `AIWorkspace.zip`。
- 导入 `.homelibpatch`。
- apply 后 remote 内容正确。
- 单条 operation 失败不影响其他可安全执行的 operation。
- 整包 schema 错误时不写入任何 operation。
- apply 后本地 cache 刷新。
- apply result 中 created / updated / skipped / conflicted / failed 数量正确。

这些测试必须是默认测试的一部分，因为它们不依赖账号和网络。

### 16.5 CloudKit Live Preflight

CloudKit live test 开始前必须做 preflight：

- 确认 `HOME_LIBRARY_ENABLE_CLOUDKIT_LIVE_TESTS=1`。
- 确认当前 CloudKit environment 是预期值，尤其是 Production。
- 确认当前 iCloud account status 可用。
- 确认目标 simulator `iPhone 17 Pro` booted，且已登录测试 Apple ID。
- 确认 `markdownNote/test` 被 git ignore。
- 确认测试仓库名前缀是 `AIWorkflowTest`。
- 确认当前 git 工作区不会把 `.derived/AIWorkflow/`、patch、workspace、账号信息加入提交。

preflight 失败时：

- live test 标记为 skipped 或 failed-preflight。
- 不打印账号内容。
- 不尝试自动登录 Apple ID。

### 16.6 CloudKit Live 测试

覆盖真实 CloudKit owner 仓库：

- Mac App 创建测试仓库。
- Mac App 刷新仓库列表能看到测试仓库。
- Mac App 新增地点。
- Mac App 新增书籍，含压缩封面。
- Mac App 编辑书籍字段。
- Mac App 导出 `AIWorkspace.zip`。
- Codex 生成 patch 后，Mac App apply 成功。
- iPhone 17 Pro 模拟器刷新后能看到 Mac App 写入的数据。
- iPhone 17 Pro 模拟器修改同一本书后，Mac App 刷新能看到变化。
- Mac App 删除测试仓库或清空测试数据。

覆盖增量同步：

- 首次刷新拿到完整数据。
- 后续刷新使用 record zone change token。
- 远端新增书籍后，Mac App 增量刷新拿到新增。
- 远端修改书籍后，Mac App 增量刷新覆盖本地 cache。
- 远端删除书籍后，Mac App 增量刷新移除本地记录。
- change token 失效时，Mac App 回退全量刷新。

覆盖 CloudKit 原生错误：

- `serverRecordChanged`：返回 conflict，不自动覆盖。
- `partialFailure`：逐条记录失败原因。
- `networkUnavailable` / `networkFailure`：显示可重试错误。
- `serviceUnavailable` / `requestRateLimited`：尊重 retry-after。
- `notAuthenticated`：要求用户登录 iCloud。
- `permissionFailure`：shared 只读仓库不允许写。
- `zoneNotFound` / share 失效：要求重新发现仓库。
- `quotaExceeded`：停止写入并展示可读错误。

### 16.7 冲突场景测试

每个冲突都需要独立 fixture 和至少一个 live 或 memory 测试：

| 场景 | 期望 |
| --- | --- |
| patch 基于旧 snapshot，书已被 iPhone 修改 | conflict |
| `expectedUpdatedAt` 不匹配 | conflict |
| `expectedRecordChangeTag` 不匹配 | conflict |
| CloudKit `serverRecordChanged` | conflict，返回 server/client 差异摘要 |
| 字段当前非空但 mode 是 `fillIfEmpty` | skipped |
| `replaceIfCurrentValue` 的 `expectedValue` 不匹配 | conflict |
| 书已被删除 | skipped `bookDeleted` |
| 地点已被删除 | skipped `locationMissing` |
| ISBN 已被另一端新增 | skipped `duplicateISBN` |
| 当前已有封面但 patch 要补封面 | skipped `coverAlreadyExists` |
| shared 仓库只读 | failed `permissionFailure` |
| apply 中途网络中断 | 已成功操作保留，未完成操作返回 failed/retryable |
| 同一 patch apply 两次 | 第二次返回 skippedAlreadyApplied / skippedAlreadySatisfied |

### 16.8 macOS UI 测试

覆盖：

- 打开 Mac App。
- 显示 CloudKit environment 和 iCloud account 状态。
- 切换仓库。
- 搜索书籍。
- 按地点筛选。
- 打开缺失项筛选。
- 编辑一本书。
- 保存冲突时显示错误。
- 导出 AI 工作包。
- 导入 `.homelibpatch`。
- 显示 validate 摘要。
- Apply 成功。
- 无效 patch 显示错误。
- 冲突 patch 显示跳过项。
- 打开 `ApplyResult.json`。

UI 测试不应截图或输出测试账号内容。

### 16.9 Codex 自动化验收

覆盖：

- Codex 打开 Mac App。
- Codex 导出 AI 工作包。
- Codex 读取工作包并生成 patch。
- Codex 用 `open patch.homelibpatch` 导入。
- Codex 点击 Apply。
- Codex 读取 `ApplyResult.json` 并汇报。
- Codex 不需要在 Mac App 里逐本翻书。
- Codex 不读取或输出 `markdownNote/test` 内容。

### 16.10 测试完成标准

第一版合格标准：

- 默认单元测试和 memory remote 集成测试全部通过。
- CloudKit live preflight 能明确跳过或运行，不出现半登录状态死等。
- 至少一条完整 live workflow 通过：Mac 创建/编辑/导出/patch apply，iPhone 17 Pro 模拟器刷新可见。
- 至少一条真实冲突 live test 通过：iPhone 修改同一本书后，Mac patch apply 返回 conflict。
- 测试结束后 CloudKit 测试仓库被清理。
- git 状态中没有 `markdownNote/test`、`.derived/AIWorkflow/`、真实 snapshot、真实 patch 或账号信息。

## 17. 推荐实施顺序

1. 抽出共享 domain / CloudKit 层，保证 macOS target 能复用。
2. 实现 Mac 仓库列表、刷新和书籍表格。
3. 实现手工编辑器，先验证 Mac App 可以安全写 CloudKit。
4. 实现缺失项、重复候选和封面状态报告。
5. 实现 `AIWorkspace.zip` 导出。
6. 实现 patch schema、validator 和 apply result。
7. 实现 `.homelibpatch` 导入。
8. 实现 CloudKit 原生冲突检测和 apply。
9. 实现 Codex 自动化工作流约定。
10. 补 UI 测试和 CloudKit 集成测试。

优先级理由：

- 先证明 Mac App 是完整 CloudKit 客户端。
- 再做 AI 工作包，避免 Codex 依赖 UI 翻找信息。
- 最后做 patch apply，确保所有写入都有浏览、编辑、刷新和冲突处理作为基础。
