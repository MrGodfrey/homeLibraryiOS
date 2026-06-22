# Goal 模式目标：无人值守开发 CloudKit CLI + Codex Skill

## 1. 启动方式

Goal mode 的目标文本有长度限制，所以不要把完整计划直接塞进 `/goal`。启动时使用短目标，并指向本文件：

```text
/goal 按 markdownNote/添加一个 AI 自动管理的功能/goal.md 执行：无人值守开发 home-library-cloudkit CLI 与 home-library-curator Codex Skill，直到所有完成标准满足。
```

如果 `/goal` 不可用，先启用：

```bash
codex features enable goals
```

本文件就是目标的详细定义、约束和完成标准。Goal 启动后，Codex 不应停在计划阶段，也不应把需要确认的操作留给人手动点击；除非遇到真实外部阻塞，否则要持续推进到实现、测试、文档和验收全部完成。

## 2. OpenAI Codex Goal Mode 要点

本目标按 OpenAI Codex manual 中的建议组织：

- Goal mode 适合多步骤、长时间任务。
- goal 文本既是起始 prompt，也是 Codex 判断是否完成的标准。
- 好的 goal 必须包含具体结果、可度量目标和测试标准。
- 目标太长时，把细节放进文件，再在 `/goal` 里指向该文件。
- 长任务可以经历 context compaction；恢复后必须重新读取本文件和当前代码状态，不要从头臆测。
- 无人值守工作必须显式处理 sandbox / approval / network 权限，不要运行到一半才等待用户确认。
- 自动化中应使用明确的权限、命令、输出和测试结果；不能用“看起来可以”代替验证。

## 3. 最终目标

完成一个可真实使用的本地 CloudKit AI 工作流产品：

- macOS signed Swift CLI：`home-library-cloudkit`
- Codex Skill：`home-library-curator`
- 完整 patch schema、validator、applier、review decision、apply result
- AI workspace 导出能力
- CloudKit private/shared repository 读取和写入能力
- 封面管理能力，与当前 App 的 `coverAssetID` + `coverAsset` / `CKAsset` 实现完全对齐
- 无人值守测试套件，覆盖单元、memory remote、review server、CLI command、CloudKit live、Skill workflow
- 文档、README、日志和安全边界全部更新

完成标准不是“代码写完”，而是：

- 所有关键功能已实现。
- 所有关键测试已写好并通过。
- CloudKit live 测试已在当前真实 iCloud 账号下跑过。
- iPhone 或 `iPhone 17 Pro` 模拟器能看到 CLI 写入的测试仓库数据。
- 没有已知 P0/P1/P2 阻塞问题。
- 没有真实账号、真实 snapshot、patch、token、Apple ID 信息被提交。

## 4. 无人值守原则

Goal 运行期间默认无人值守。遇到需要人工确认的地方，Codex 必须优先改造成可自动完成的工程路径。

### 4.1 不等待人类确认

不允许因为下面事项停住等待用户手动操作：

- 点击 review page 的 Approve / Reject。
- 在 Xcode UI 里点签名、能力或 scheme 设置。
- 在 iOS App UI 里点按钮验证同步。
- 在浏览器里点确认。
- 手动复制测试账号。
- 手动编辑 patch。
- 手动清理测试仓库。
- 手动选择文件。

必须替代为：

- CLI 参数。
- 测试 fixture。
- 临时 `ReviewDecision.json`。
- loopback HTTP test client 直接 POST。
- `xcodebuild` / XcodeBuildMCP。
- Swift 单元测试。
- shell 命令。
- 自动生成的 test repository。
- 自动 cleanup。

### 4.2 产品确认页仍保留，但测试不能靠真人点击

真实产品里仍然需要 `review-patch` 确认页，防止误删主书库数据。

但无人值守开发和测试中：

- `review-patch` 的 UI 通过 HTTP server test 覆盖。
- Approve / Reject 用测试 client POST 到 `127.0.0.1` 完成。
- apply 使用测试生成的 `ReviewDecision.json`。
- 允许新增仅测试可用的 `--auto-approve-test-only` 或等价能力，但必须同时满足：
  - 只能在 `HOME_LIBRARY_CLOUDKIT_LIVE_TESTS=1` 或测试 target 中启用。
  - 只能作用于 `AIWorkflowTest-*` 测试仓库。
  - 不能作用于真实主书库。
  - 不能绕过 validator。
  - 仍要输出完整 apply result。

### 4.3 真实主书库保护

无人值守不等于无保护。

- live test 默认创建 `AIWorkflowTest-<timestamp>-<random>` 独立仓库。
- 不对真实主书库做破坏性测试。
- 对真实主书库只允许 read-only、export、validate、dry-run。
- 如果必须验证真实主书库 apply，必须先导出 backup/workspace 到 `.derived/AIWorkflow/backups/`，再只执行用户明确要求的操作。
- 删除书籍、替换非空字段、替换或移除已有封面永远不能静默作用于主书库。

### 4.4 外部阻塞处理

只有下面情况可以标记 blocked：

- 当前 Mac 未登录 iCloud，且 CloudKit account status 不可用。
- Apple Developer 签名或 provisioning 无法通过 CLI/XcodeBuild 自动完成。
- Apple CloudKit 服务不可用或持续返回服务级错误。
- 当前系统没有可用的 Xcode / SDK / simulator。
- 仓库已损坏，继续修改会破坏用户现有代码。

标记 blocked 前必须：

- 至少尝试可自动执行的修复路径。
- 保存已完成的代码和测试。
- 写明失败命令、错误摘要、已尝试方案、剩余最小人工动作。
- 不能把“需要点确认页”当作 blocked；确认页必须被自动测试替代。

## 5. 权限和运行环境

Goal 启动前应使用适合无人值守的 Codex 权限组合。

推荐：

- trusted repo。
- workspace 可写。
- network 可用。
- approval policy 为 `never`，或 `on-request` + `approvals_reviewer = "auto_review"`。
- 当前线程能运行 `xcodebuild`、Swift tests、shell 命令和本地 HTTP server。

如果当前会话权限不足，Codex 必须：

- 先尝试在现有权限内完成。
- 对不能执行的命令改用可自动执行的替代路径。
- 只在真实外部阻塞时停止。

## 6. 必须读取和遵守的本地文档

开始实现前必须读取：

- `AGENTS.md` 或系统注入的仓库规则。
- `markdownNote/添加一个 AI 自动管理的功能/Cloudkit.md`
- `markdownNote/添加一个 AI 自动管理的功能/plan.md`
- 当前源码里的 CloudKit、cache、cover、import/export、store、tests 实现。

必须遵守：

- 修改仓库文件后追加 `log.md`。
- 如果新增 CLI 命令、测试入口、运行方式或用户可见行为，更新 `README.md`。
- 不读取 `markdownNote/test`。
- 不提交 `.derived/AIWorkflow/`。
- 不提交真实账号、真实 snapshot、patch、token 或 Apple ID 信息。

## 7. 实现范围

### 7.1 CLI target

实现 `home-library-cloudkit`，建议作为 Xcode 工程中的 macOS command line target 或等价 Swift target。

必须支持：

- `doctor`
- `repos`
- `export-ai-workspace`
- `validate-patch`
- `review-patch`
- `apply-patch`

输出规则：

- stdout 默认只输出 JSON。
- stderr 输出进度和本地 URL。
- 错误使用非 0 exit code。
- 所有默认产物写入 `.derived/AIWorkflow/`。

### 7.2 CloudKit 对齐

必须复用或抽出当前 App 能力：

- `Book`
- `BookPayload`
- `BookDraft`
- `LibraryLocation`
- `LibraryRepositoryReference`
- `CloudKitLibraryService`
- `LibraryCacheStore`
- `LibraryCoverCompressor`

必须与当前实现一致：

- container：`iCloud.yu.homeLibrary`
- book record name：`book.<id>`
- 封面：`coverAssetID` + `coverAsset` / `CKAsset`
- 本地封面 cache：`covers/<coverAssetID>.bin`
- `coverAssetID`：最终写入数据 SHA-256，格式 `cover-<hex>`
- 压缩阈值：最长边 `720 px`、目标 `220 KB`
- 删除书籍：删除 CloudKit record，不写成不存在的软删除语义

### 7.3 Patch schema

必须覆盖：

- `createBook`
- `updateBook`
- `updateBookCover`
- `removeBookCover`
- `deleteBook`

必须支持：

- `expectedUpdatedAt`
- `expectedRecordChangeTag` 或等价 CloudKit metadata
- `expectedCurrentCoverAssetID`
- `fillIfEmpty`
- `replaceIfCurrentValue`
- duplicate ISBN 检测
- similar title 检测
- per-operation result
- partial success
- conflict / skipped / failed / retryable failed 分类

当前 `RemoteBookSnapshot` 不包含 `recordChangeTag`。实现时必须扩展 CLI 层 snapshot metadata 或扩展共享类型，不能假装已有字段存在。

### 7.4 Review server

实现短时 loopback server：

- 只绑定 `127.0.0.1`。
- one-time token。
- GET 展示 summary、creates、updates、deletes、cover changes、conflicts、skipped、evidence、raw JSON。
- POST approve/reject 写入 `ReviewDecision.json`。
- 超时后自动 rejected/timeout。
- server 结束后关闭。

测试不得依赖真人浏览器点击。

### 7.5 Codex Skill

交付 `home-library-curator` skill。

建议路径：

```text
skills/home-library-curator/SKILL.md
```

Skill 必须能指导 Codex：

- 运行 `doctor`。
- 选择目标 repo。
- 导出 workspace。
- 读取 missing / duplicate / cover status。
- 生成 patch。
- validate。
- review。
- apply。
- 读取 result。
- 总结成功、跳过、冲突、失败。

Skill 必须写明：

- 不读取 `markdownNote/test`。
- 不直接改 CloudKit。
- 不直接改 `cloudkit-cache`。
- 不绕过 validator。
- 对主书库高风险操作必须 review。
- 测试仓库可用 test-only auto approval。

## 8. 测试要求

### 8.1 默认测试

不访问 CloudKit，必须能稳定通过：

- patch 解码。
- schema 版本。
- target repository。
- operation 数量和 patch 大小限制。
- ISBN 校验。
- locationID 校验。
- `fillIfEmpty`。
- `replaceIfCurrentValue`。
- `expectedUpdatedAt`。
- `expectedRecordChangeTag`。
- duplicate ISBN。
- similar title。
- cover payload decode。
- `LibraryCoverCompressor` 规则。
- `coverAssetID` SHA-256。
- `deleteBook` 需要 approve。
- `removeBookCover` 需要 approve。
- apply result JSON 编码。

### 8.2 Memory remote 集成测试

不访问 CloudKit，覆盖完整业务链路：

- create test repo。
- save locations。
- export workspace。
- validate patch。
- apply patch。
- create book with cover。
- update fields。
- update cover。
- remove cover。
- delete book record。
- conflict。
- skipped。
- repeated apply idempotency。
- cache metadata 与 cover `.bin` 分离。
- export package embeds `LibraryImportBook.coverData`。

### 8.3 Review server 测试

必须无人值守：

- 只绑定 `127.0.0.1`。
- token 错误拒绝。
- GET 页面包含关键摘要。
- POST approve 写 `ReviewDecision.json`。
- POST reject 写 rejected。
- timeout 返回 rejected/timeout。
- 删除显示危险区。
- 替换非空字段显示 old -> new。
- 替换或移除封面显示当前/候选结果。

### 8.4 CLI command 测试

覆盖：

- stdout JSON。
- stderr progress。
- 非 0 exit code。
- `--result` 写文件。
- `.derived/AIWorkflow/` 默认路径。
- invalid patch 不写 CloudKit。
- missing review decision 时拒绝高风险操作。

### 8.5 CloudKit live 测试

使用当前 Mac 已登录的真实 iCloud 账号。

显式开启：

```text
HOME_LIBRARY_CLOUDKIT_LIVE_TESTS=1
HOME_LIBRARY_CLOUDKIT_CONTAINER=iCloud.yu.homeLibrary
HOME_LIBRARY_TEST_REPOSITORY_PREFIX=AIWorkflowTest
HOME_LIBRARY_TEST_SIMULATOR_NAME=iPhone 17 Pro
```

必须覆盖：

- `doctor` account status available。
- 创建 `AIWorkflowTest-*` repo。
- 新增地点。
- 新增含封面的书。
- 刷新后读回 `coverAssetID` 和 `coverAsset`。
- 更新字段。
- 替换封面。
- 移除封面。
- 删除测试书籍 record。
- 导出 workspace。
- validate / review / apply。
- iPhone 或 `iPhone 17 Pro` 模拟器刷新后可见测试数据。
- iPhone 或模拟器修改同一本测试书后，CLI apply 旧 patch 返回 conflict。
- 增量刷新使用 change token。
- 测试结束清理测试 repo。

不得对真实主书库做破坏性 live test。

## 9. 自动验收流程

Codex 必须按下面顺序推进；可以并行读文件和跑互不冲突的测试，但不能跳过验收。

1. 读取计划和源码。
2. 设计最小实现拆分。
3. 实现共享 domain / CloudKit / patch 层。
4. 新增 CLI target。
5. 实现 `doctor` 和 `repos`。
6. 实现 workspace export。
7. 实现 patch schema / validator。
8. 实现 cover payload / compression / `coverAssetID`。
9. 实现 review server。
10. 实现 applier。
11. 实现 memory tests。
12. 接入 real CloudKit live path。
13. 实现 Codex Skill。
14. 更新 README。
15. 追加 log。
16. 跑完整测试。
17. 修复失败。
18. 再跑关键测试。
19. 做 diff review。
20. 只有所有完成标准满足后才结束 goal。

## 10. 完成标准

Goal 只有在全部满足时才算完成：

- `home-library-cloudkit` 可以构建。
- `home-library-cloudkit doctor` 输出正确 JSON。
- `home-library-cloudkit repos` 能列出当前账号可访问仓库。
- `export-ai-workspace` 生成完整 workspace。
- `validate-patch` 能拦截非法 patch。
- `review-patch` 能启动 loopback server，并可被自动测试 approve/reject。
- `apply-patch` 能在 memory remote 和 CloudKit test repo 中应用 patch。
- 封面创建、替换、移除都正确处理 `coverAssetID` 与 `CKAsset`。
- 删除书籍使用现有 CloudKit record 删除语义。
- Codex Skill 已交付并能描述完整 workflow。
- 默认测试全部通过。
- CloudKit live 测试全部通过，或仅因明确外部服务/账号/签名阻塞而 blocked。
- iPhone / 模拟器同步验证通过。
- README 已更新新增命令、测试入口和运行方式。
- `log.md` 已追加。
- `git status` 中没有真实账号、真实数据、`.derived` 产物、patch、token。
- 没有未解释的测试失败。
- 没有已知关键缺陷。

不要用“应该没问题”结束。必须用命令、测试结果、文件变更和剩余风险清单结束。

## 11. 恢复和上下文压缩

如果 Goal 运行中发生 context compaction、线程恢复或自动续跑：

1. 重新读取本文件。
2. 读取 `Cloudkit.md`。
3. 查看 `git status --short`。
4. 查看最近 `log.md`。
5. 查看已实现代码和测试。
6. 从未完成的最高优先级验收项继续。

不要从头重写已经完成的工作。不要回退用户或前序 agent 的无关改动。

## 12. 最终汇报格式

最终回复必须包含：

- 实现了哪些功能。
- 新增/修改了哪些关键文件。
- 跑了哪些测试命令。
- 哪些测试通过。
- 是否跑了 CloudKit live 测试。
- iPhone / 模拟器同步验证结果。
- 未解决问题或残余风险；如果没有，写“没有已知阻塞问题”。
- 明确说明未读取 `markdownNote/test`，未提交真实数据。

只有完成标准全部满足，才能把 Goal 标记为 complete。
