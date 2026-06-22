# AGENTS

适用于本仓库内的所有 Codex / agent 改动。

## 必须遵守

- 任何会修改仓库文件的改动，在交付前都必须追加写入 `log.md`。
- `log.md` 只能追加新的变更记录，不能删除或覆盖已有历史记录。
- 如果改动影响用户可见行为、设置项、测试入口或运行方式，还必须同步更新 `README.md`。
- 更新 `README.md` 时，默认保持现有章节结构不变；除非用户明确要求，否则不要重排章节。

## 家庭书库 AI 管理流程

- 管理真实书库时，默认通过 `home-library-cloudkit` CLI 读写 CloudKit，不直接编辑本地 cache，也不绕过 patch validator。
- 真实 CloudKit 访问必须使用 `scripts/build_home_library_cloudkit.sh` 输出的签名 executable 路径；不要直接运行裸 `.build/debug/home-library-cloudkit` 访问真实远端。
- 面向用户真实书库时必须使用 Production CloudKit，构建和运行签名 CLI 时显式保留或设置 `HOME_LIBRARY_CLOUDKIT_ENVIRONMENT=production`；只有测试隔离场景才允许显式设置 `HOME_LIBRARY_CLOUDKIT_ENVIRONMENT=development`。
- 不要并行运行多个带 `HOME_LIBRARY_CODESIGN_IDENTITY` 的构建 / CLI 命令；签名 wrapper 会被重建，并行执行容易让其中一个进程拿到被替换的 executable。
- 从豆瓣补书时，优先用 ISBN 在豆瓣图书搜索页定位条目，再进入 `book.douban.com/subject/.../` 页面核对作者、译者、出版社、出版年、ISBN、封面等字段。
- 豆瓣网页、解析后的 metadata、下载的封面、小型中间 patch 和 apply/review/result 文件都放在 `.derived/AIWorkflow/` 下的任务子目录中；这些文件只作为临时缓存，不能提交到 Git。
- 生成 `.homelibpatch` 后必须先执行 `validate-patch`；新增书籍可以在用户明确要求添加时使用受限的 review decision，但删除、替换封面、替换非空字段等高风险操作仍必须通过 `review-patch`。
- 完成真实 apply 后，优先用 `repos` / workspace export 或模拟器 app 自动化确认书籍已进入目标仓库；如果用户要现场查看，则启动 `iPhone 17 Pro` 模拟器中的 app 供用户核验。
- 全流程不得读取 `markdownNote/test`，不得把真实账号、token、CloudKit snapshot、豆瓣缓存、封面文件或 patch 产物提交进仓库。
