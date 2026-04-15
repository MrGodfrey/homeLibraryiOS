# homeLibrary 根计划文档重写方案

## 摘要
- 用下面这份内容完整替换根目录的 [plan.md](/Users/wangyu/code/homeLibraryApp/homeLibrary/plan.md)，不再保留当前那种“目标/决策/状态/验证”的简版收尾文档。
- 新版计划要把 `plan2.md` 里的需求整理成一份可执行实施计划，并明确说明当前基线、目标状态、迁移路线、验收标准和默认取舍。
- 计划必须承认当前工程的真实基线：现状仍是 `publicCloudDatabase + 仓库账号密码`、固定 `成都/重庆`、首页单栏列表、顶部标题 + 分段筛选 + `.searchable`、迁移无进度、无清空仓库、无压缩包导出。

## 关键改动
### 1. 文档与仓库规范
- 把 [README.md](/Users/wangyu/code/homeLibraryApp/homeLibrary/README.md) 的改写纳入正式计划，写法采用“需求优先、架构后置”的结构：先写这个 App 要长期服务什么需求、核心流程是什么、哪些边界不能破坏，再解释 CloudKit、数据模型和代码分层。
- 把 [log.md](/Users/wangyu/code/homeLibraryApp/homeLibrary/log.md) 的 append-only 规则写进计划：每一次结构性修改、功能增加、架构重排、调试结论，都必须追加记录，不允许覆盖历史。
- 在计划里新增一条长期约束：以后每加一个功能，都要先检查“这个需求是否必要”，再检查“当前实现是否已经是满足需求的最简单架构”。

### 2. CloudKit 协作模型重构
- 废弃当前“公共数据库 + 账号密码加入仓库”的方案，彻底移除 `RepositoryCredentials`、`joinRepository(account:password:)`、`rotateCredentials`、`accessAccount/password` 文案与对应 README 叙述。
- 新方案改成 `CKShare` 标准共享：每个家庭书库对应一个 owner 私有数据库里的自定义 zone，`LibraryRepository` 是 zone 内的仓库元数据记录，所有 `LibraryBook` 记录也都落在这个 zone 中。
- 协作边界从“按 `repositoryID` 字段过滤公共库”改成“一个仓库就是一个共享 zone”；书籍查询、写入、删除都不再扫描整个公共库。
- 拥有者侧通过系统 `UICloudSharingController` 生成/管理共享；加入者通过系统分享链接接受邀请，应用用 `CKAcceptSharesOperation` 接收共享，之后从 `sharedCloudDatabase` 读取与写入。
- 计划里要明确补充 `CKSharingSupported = true`、分享接受回调接线、当前仓库切换逻辑、共享状态刷新逻辑。
- `RepositoryDescriptor` / `LibraryRepositoryReference` 要升级为 share-aware 模型，至少携带：仓库 id、显示名、角色、数据库作用域（`private/shared`）、zone 标识、share 标识或 share 状态。
- `LibraryRemoteSyncing` 接口要从“凭据式加入”改成“共享式仓库服务”：创建自有仓库、列出当前账号可访问仓库、读取仓库元数据、创建/管理 share、接受 share、在仓库 zone 中做书籍 CRUD、清空仓库、导出仓库。
- 增加一次性升级路线：如果当前用户的旧公共库仓库仍存在，首次升级后要引导把旧公共库数据复制到新的私有共享仓库，再停止继续依赖旧模型；旧密码协作成员不能自动映射到 Apple ID，必须由 owner 重新发送 CKShare 邀请。

### 3. 仓库设置与高级管理区
- 首页不再显示仓库名、角色、承载位置等信息；这些信息统一移到仓库设置页。
- 仓库设置页拆成“仓库信息/地点配置/高级管理区”三块，其中高级管理区必须放入且仅放入这三个维护动作：旧数据迁移、清空当前仓库、导出当前仓库压缩包。
- 旧数据迁移要改成可见进度流程：先统计总条数，再显示 `已导入 x / total`，再在导入结束时给出明确成功提示。计划里要要求新增明确的进度状态对象，例如 `RepositoryImportProgress { phase, totalCount, importedCount }`。
- “清空当前仓库”必须是高风险动作，要求二次确认，并在执行后同步清空远端仓库内容与本地缓存，再刷新当前页面。
- “导出当前仓库”要生成 zip 备份包；v1 约定 zip 根目录只放一个 `LibraryImport.json`，内容沿用当前导入包语义并内嵌封面数据，保证导出结构稳定、后续可复用。
- 地点配置放在仓库设置页，不放首页；owner 或可写成员可以新增、重命名、排序、隐藏地点，首页筛选条实时反映这个顺序。

### 4. 地点模型重构
- 用仓库可配置地点替换当前硬编码的 `BookLocation` 与 `LibraryFilterTab`。
- 新增 `LibraryLocation` 持久化模型，最少包含：稳定 `id`、显示名 `name`、排序字段；`Book` / `BookPayload` 改存 `locationID`，不再直接存枚举值。
- 初始迁移时先把现有 `成都`、`重庆` 变成默认地点配置，并把旧书籍映射到新地点 id。
- `全部` 继续作为 UI 层的虚拟筛选项，不写入远端数据；真实可选地点全部来自仓库配置。
- 计划里要明确：地点名称属于仓库设置，重命名地点时不回写所有书籍正文，只更新地点配置即可。

### 5. 首页改版
- 把当前单栏 `LazyVStack` 列表改成双栏书墙，适配竖屏 iPhone；每个卡片必须稳定展示：竖向封面、标题、作者、出版社行、地点。
- 顶部筛选改成固定、透明、可悬浮的地点条，顺序为 `全部 + 配置地点列表`；内容滚动时背景从其下方滑过。
- 页面上滑一个阈值后隐藏“家藏万卷”标题，只保留顶部地点切换条，腾出更多书籍展示空间。
- 首页彻底删除仓库信息面板。
- 书籍卡片交互改成两段式：第一次点击只选中卡片，并把封面区域压暗、显示“修改/删除”；点击“修改”进入编辑，点击“删除”进入确认删除；点空白区域取消选中。
- 底部搜索改成自定义悬浮玻璃搜索控件，不再依赖 `.searchable` 顶部搜索；默认占宽较小，点击后聚焦输入，始终悬浮在底部安全区上方，不遮挡主要内容。

### 6. 编辑页与表单
- 删除编辑页中“当前版本只保留手动录入...”这句解释性文案。
- 编辑表单的地点选择必须改成动态地点列表，而不是固定枚举。
- 新建书籍时，若当前首页筛选落在某个具体地点，则默认带入该地点；若当前是“全部”，则带入仓库默认地点或首个可见地点。

### 7. 调试、CloudKit 经验和环境说明
- 在计划里加入调试模式要求：Debug 构建或显式调试开关下，记录脱敏后的 CloudKit 操作上下文，包括 CKError code、数据库作用域、zone/仓库 id、失败操作名、最终展示给用户的报错。
- README 的 CloudKit 章节要从“公共库 queryable 索引排障”改写为“私有库 + shared 数据库 + CKShare 接入 + 分享接收流程”；旧的索引说明降级为故障排查补充，不再作为主线架构说明。
- 单独增加 Development / Production 说明：两者使用同一套业务结构，不搞两套数据格式；差异仅在 CloudKit 环境、数据和 schema 部署流程，开发先在 Development 验证，再推广到 Production。
- 把 `plan2.md` 中的 CloudKit 实践经验写进计划：早期版本必须尽量拿全报错信息；CloudKit Console/Dashboard 里的字段可读性、权限与共享配置是首要排查点。

## 测试与验收
- 单元测试：仓库会话持久化（含 share/zone 元数据）、地点配置增删改排、旧地点枚举迁移、导入进度状态、导出包生成、清空仓库状态流转、动态地点筛选与搜索。
- 内存远端集成测试：创建 owner 仓库、共享接受后的仓库发现、owned/shared 仓库切换、共享仓库里的书籍增删改、旧公共库升级路径、owner-only 清空保护。
- UI 测试：双栏布局渲染、顶部地点条、标题折叠、卡片选中遮罩、修改/删除入口、底部悬浮搜索、迁移进度展示、高级管理区按钮位置、导出按钮可见性。
- 真机双账号验证：A 账号创建共享并发送链接，B 账号接受后进入 shared 仓库，双方互相看到更新；owner 移除成员后 member 失去访问；Development 验证通过后再做 Production 发布检查。

## 默认假设
- 地点配置是“仓库级”，不是“设备级”。
- 家庭协作默认采用 `readWrite` 共享权限；更细的权限调整交给系统共享 UI 管理。
- “清空当前仓库”仅 owner 可用；“导出当前仓库”任何有读取权限的参与者都可用。
- 旧密码加入仓库不会自动迁移到 Apple ID 参与者；owner 迁移完成后必须重新发 CKShare 链接。
- CKShare 接入按 Apple 官方文档约束落地：`CKSharingSupported`、`UICloudSharingController`、`sharedCloudDatabase`、`CKAcceptSharesOperation`。参考：[Shared Records](https://developer.apple.com/documentation/cloudkit/shared-records)、[CKShare](https://developer.apple.com/documentation/CloudKit/CKShare)、[Sharing CloudKit Data with Other iCloud Users](https://developer.apple.com/documentation/CloudKit/sharing-cloudkit-data-with-other-icloud-users)、[application(_:userDidAcceptCloudKitShareWith:)](https://developer.apple.com/documentation/uikit/uiapplicationdelegate/application%28_%3Auserdidacceptcloudkitsharewith%3A%29)。
