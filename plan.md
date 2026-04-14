# homeLibrary CloudKit Rewrite Plan

## Goal

把当前项目从旧的 iCloud Drive / ISBN / 多平台形态，收敛成一个只服务 iPhone 的家庭藏书应用：

- CloudKit 数据库存储与同步
- 仓库账号密码协作加入
- 手动录入书籍信息
- iPhone 上传封面
- 自动迁移并清理旧历史数据

## Decisions

### 1. 平台

- 只保留 iPhone
- 不再维护 macOS 入口

### 2. 远端模型

- `LibraryRepository`：仓库元数据和凭据
- `LibraryBook`：书籍记录、封面资产、软删除字段
- `BookPayload`：版本化业务字段 JSON

### 3. 本地模型

- 本地只保留缓存目录
- 旧 `books.json` / `books/ covers/ deletions/` 仅作迁移来源

### 4. 书籍录入

- 删除 ISBN 自动补全
- 删除 ISBN 扫码
- 封面从 iPhone 相册上传
- 书籍信息全部手动维护

### 5. 协作方式

- 仓库拥有者在 app 内生成账号密码
- 另一位用户在“加入仓库”中输入后访问同一仓库

## Status

- [x] 重做 `Book` / `BookDraft` / `BookPayload`
- [x] 重做本地缓存与旧数据迁移
- [x] 接入 CloudKit 仓库与书籍记录
- [x] 接入仓库管理和加入仓库流程
- [x] 移除 ISBN / iCloud Drive / macOS 方向
- [x] 调整 iPhone UI
- [x] 更新 README / log
- [x] 跑通编译、单元测试和 UI 测试

## Validation

截至 2026-04-14，已经验证：

- iOS Simulator 构建通过
- 单元测试 `6` 个通过
- UI 主流程测试通过
- UI 启动烟测通过
