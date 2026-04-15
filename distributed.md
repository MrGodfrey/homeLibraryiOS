# homeLibrary 分发说明（TestFlight / App Store）

本文基于我在 2026-04-15 查阅的 Apple 官方资料整理，并结合当前仓库配置给出一份可直接执行的分发说明。适用对象是这个仓库里的 iPhone 应用 `homeLibrary`。

## 当前项目的已知分发前提

- 平台：iPhone only（`TARGETED_DEVICE_FAMILY = 1`）
- Bundle ID：`yu.homeLibrary`
- iCloud container：`iCloud.yu.homeLibrary`
- 关键能力：CloudKit、`CKShare` 系统共享、相册选图
- 当前 Deployment Target：`iOS 26.4`

结合当前工程，这意味着：

- 只有系统版本不低于 `iOS 26.4` 的设备才能安装你的 TestFlight 包或正式版。
- 你的分发流程必须把 CloudKit、隐私声明、相册权限文案一起考虑进去。
- 由于这是 iPhone-only App，上架时主要准备 iPhone 相关截图即可，不需要 iPad 素材。

## 1. 如果想通过 TestFlight 分发给别人，应该怎么做

### 1.1 先满足 Apple 的前置条件

1. 加入 `Apple Developer Program`。Apple 官方的 Xcode 分发文档明确说明：如果你要通过 TestFlight 或 App Store 分发，就需要加入该计划。
2. 确认 `App Store Connect` 可用。Apple 官方说明，第一次开始时只有 `Account Holder` 能登录，且在创建 App 记录前，账号需要先接受最新协议。
3. 如果将来你要做收费 App 或 App 内购，还需要在 `Business` 里签 `Paid Apps Agreement`，并填写税务与收款信息；如果只是免费 App，这一步暂时不是硬前提。

### 1.2 先把这个项目准备到可上传状态

分发前，至少检查下面这些点：

- `Bundle ID`、Team、签名配置正确。
- 版本号和构建号要更新。
- App Icon、Launch Screen、权限文案齐全。
- `homeLibrary/Info.plist` 里的以下内容继续保留并确认准确：
  - `CKSharingSupported = true`
  - `NSPhotoLibraryUsageDescription`
- `homeLibrary/homeLibrary.entitlements` 中的 iCloud 容器要和项目、App ID、App Store Connect 里的记录一致。

对这个项目尤其重要的，是 CloudKit 生产环境：

- Apple 的 CloudKit 文档说明，`App Store` 上的 App 只能访问 `production` 环境；发布前必须把 development schema 部署到 production。
- 这个项目依赖 `iCloud.yu.homeLibrary`、自定义 zone、共享邀请、成员读取 `sharedCloudDatabase`。所以在任何面向他人的 TestFlight 包上线前，都应先去 CloudKit Console 把 schema 部署到 production。

如果不做这一步，最常见的结果就是：

- TestFlight 包能装，但 CloudKit 读写失败；
- 分享邀请能弹出，但接受后读取不到正确数据；
- 某些字段或索引只存在于 development 环境，生产环境直接报错。

### 1.3 在 App Store Connect 先创建 App 记录

Apple 官方要求：在第一次上传到 App Store Connect 之前，先创建一个 `app record`。

你需要在 `Apps -> + -> New App` 里至少填这些内容：

- Platform：`iOS`
- Name：你的 App 名称
- Primary Language
- Bundle ID：`yu.homeLibrary`
- SKU

创建完成后，App 状态会进入 `Prepare for Submission`。

### 1.4 用 Xcode 归档并上传 build

Apple 官方的 Xcode 分发流程是：

1. 在 Xcode 里选择真机目标或合适的 Archive 目标。
2. 执行 `Product > Archive`。
3. 打开 `Organizer`，先跑一次 `Validate App` 更稳妥。
4. 点击 `Distribute App`。
5. 如果你希望这个 build 既能走 TestFlight，也能将来直接用于 App Store 提交，选择 `TestFlight & App Store`。

这里有一个很关键的 Apple 官方细节：

- `TestFlight Internal Only` 只能给内部测试组，不能再拿去做外部测试，也不能直接交给 App Store 客户。

所以，如果你的目标是“分发给别人”而不是只给自己团队，上传时不要选 `TestFlight Internal Only`。

### 1.5 先做内部测试，再做外部测试

Apple 当前的 TestFlight 规则里：

- `Internal testers` 最多 `100` 人，必须是 App Store Connect 里有权限的用户。
- `External testers` 最多 `10,000` 人，可以是普通邮箱邀请，也可以用公开链接。
- TestFlight build 默认可测试 `90` 天。

推荐顺序：

1. 先创建一个 `Internal Testing` 组，自己和少量协作者先跑一遍真机流程。
2. 再创建 `External Testing` 组，对外发放。

Apple 官方还明确要求：

- 想创建外部测试组之前，必须先有一个内部测试组。
- 第一次把某个 App 的 build 加到外部测试组时，这个 build 通常需要经过 `TestFlight App Review`。
- 后续同一版本的 build 可能不需要完整复审，但不能假设一定免审。

### 1.6 外部 TestFlight 分发的最短路径

你可以按这个顺序做：

1. `App Store Connect` 里填好 TestFlight 的 `Beta App Description`、`What to Test`、反馈邮箱等测试信息。
2. 创建一个内部测试组，先把 build 加进去。
3. 创建外部测试组。
4. 把 build 加到外部组，提交 `TestFlight App Review`。
5. 审核通过后，用两种方式邀请测试者：
   - 直接发邮箱邀请
   - 生成 `Public Link`
6. 如果你用 Public Link，Apple 允许你按设备和系统版本设置筛选条件，这对当前项目很有用，因为它的最低系统版本比较高。

### 1.7 这个项目做 TestFlight 时，建议你额外写清楚的内容

因为 `homeLibrary` 不是一个纯离线 App，建议在 TestFlight 审核信息和测试说明里写清楚：

- 这个 App 依赖用户已登录 iCloud。
- 共享书库使用系统的 `CKShare` 邀请链路。
- 如果想测试“主人邀请成员加入”的完整流程，通常需要两台设备或两个 Apple Account。
- 测试重点是什么：创建仓库、添加书籍、封面选择、发起共享、接受共享、共享后是否能读取到同一仓库。

这不是 Apple 的固定表单要求，而是结合当前项目实现后最实用的写法。它能减少测试者和审核方因为“不知道怎么走主流程”而卡住。

## 2. 如果想上架 App Store，应该怎么做

### 2.1 先明确 App Store 和 TestFlight 的关系

Apple 的 `App Review Guidelines` 明确写了两件事：

- `Demos`、`betas`、`trial versions` 不属于 App Store，应该走 TestFlight。
- 提交到 App Review 的必须是最终要给用户的版本，元数据和功能都要完整。

因此，正确顺序通常是：

1. 先用 TestFlight 把最终版本测稳；
2. 再把同一个或更新后的最终 build 提交到 App Review。

### 2.2 先把 App Store 页面和必填信息补齐

Apple 官方要求，在提交审核前，你必须补齐该版本需要的元数据，并为该版本选择 build。

至少要准备这些内容：

- App 名称
- Subtitle
- Description
- Keywords
- Category
- Support URL
- Privacy Policy URL
- App Privacy 回答
- Age Rating
- App Store 截图
- Pricing and Availability
- Export Compliance（如需要）
- Review Notes

其中几个点要特别注意：

- `Privacy Policy URL`：Apple 官方说明这是所有 App 的必填项。
- `App Privacy`：如果你要在 App Store 分发，必须在 App Store Connect 说明数据处理方式。
- `Age Rating`：Apple 官方说明这是必填项；`Unrated` 的 App 不能发布到 App Store。
- `Screenshots`：Apple 官方要求至少 `1` 张、最多 `10` 张截图；App Preview 可选，每种设备尺寸和语言最多 `3` 个。
- `Pricing and Availability`：即使是免费 App，也要把价格和可售地区设好；如果收费或含 IAP，必须先处理 `Paid Apps Agreement`。

### 2.3 结合当前项目，App Privacy 这一块怎么想

Apple 官方关于 `App Privacy` 的说明里有两个和这个项目非常相关的点：

- 你需要申报的是“你或第三方伙伴通过 App 收集的数据”。
- 如果你使用 `CloudKit` 这类 Apple 服务，你要申报的是“你通过这些服务收集的数据”，但不需要替 Apple 自己申报它收集的数据。

结合当前代码，我建议你重点核对这些数据类型是否需要申报：

- 书籍标题、作者、出版社、地点等用户录入内容
- 封面图片
- 可能同步到 CloudKit 的其他用户内容
- 诊断数据（如果后续你接入了崩溃、分析或日志上报）

粗暴地说，只要这些数据会离开设备并在你的 CloudKit 容器里保存，就不应按“纯本地数据”处理。最终答案还是要以你实际上线版本的行为为准。

### 2.4 准备好 App Review 需要看到的东西

Apple 的 App Review Guidelines 当前强调：

- 提交时要给出最终版，而不是占位内容、空网站、半成品流程。
- 元数据、截图、预览要准确反映真实体验。
- 功能、变更和特殊流程要在 `Notes for Review` 中写清楚。
- 如果有登录，必须提供可审核的账号和可用后端。

当前项目虽然没有自己的账号体系，但它依赖 iCloud 和 CloudKit 共享，所以建议你在 `Review Notes` 里写清：

- 主流程依赖设备已登录 iCloud。
- 核心功能是家庭书库共享，而不是单机样例。
- 如何创建一个书库。
- 如何发出共享邀请。
- 如何接受共享邀请。
- 如果审核环境不方便完成双账号共享，审核方至少可以单机验证哪些功能。

如果你能提供一段简短的审核说明视频，实际体验通常会更顺。

### 2.5 提交 App Store 审核的标准流程

Apple 官方流程可以概括成：

1. 在 App Store Connect 里选中该 App 的目标版本。
2. 在该版本的 `Build` 区域选择正确的 build。
3. 点击 `Add for Review`。
4. 检查草稿提交内容。
5. 点击 `Submit for Review`。

提交之后：

- App 状态会进入 `Waiting for Review / In Review` 等状态。
- 如果被打回，就在 `App Review` 区域看消息并回复。
- 如果审核通过，你可以选择：
  - 自动发布
  - 手动发布
  - 分阶段发布

Apple 官方说明，审核通过后，App 在所有选定 storefront 完全上线可能还需要最多约 `24` 小时。

## 3. 这个仓库在真正分发前，我建议你逐项确认的清单

### 必查项

- [ ] `homeLibrary/Info.plist` 中的共享和相册权限文案准确无误
- [ ] `homeLibrary/homeLibrary.entitlements` 中的 iCloud 容器与 App ID 一致
- [ ] CloudKit development schema 已部署到 production
- [ ] 真机跑通过：建库、加书、换封面、发邀请、收邀请、成员读取
- [ ] App Store Connect 中的 `app record` 已创建
- [ ] 版本号 / build 号已更新
- [ ] 截图、隐私政策 URL、Support URL、Age Rating、App Privacy 已填写
- [ ] Review Notes 已说明 iCloud / CloudKit 共享流程

### 项目特有风险

- 当前最低系统版本是 `iOS 26.4`。这会直接限制谁能安装你的 TestFlight 包和正式版。如果你想覆盖更多设备，应该先评估是否能下调 Deployment Target。
- 这个项目依赖 CloudKit 生产环境。如果 production schema 没准备好，分发出去的包通常会“能打开但不能正常同步”。
- `homeLibrary/homeLibrary.entitlements` 里当前写着 `aps-environment = development`。我这次没有去验证 Archive 后最终签名产物是否会改写它；正式上传前，建议至少做一次 `Validate App` 和真实归档检查，避免把开发环境的 APNs entitlement 带进发布包。

## 4. 我建议你的实际执行顺序

如果你现在的目标是先让别人试用，再决定是否上架，最稳妥的顺序是：

1. 先创建 App Store Connect 的 App 记录。
2. 检查签名、版本号、图标、权限文案。
3. 把 CloudKit schema 部署到 production。
4. 真机自测一次完整共享链路。
5. 用 Xcode `Archive -> Validate App -> Distribute App -> TestFlight & App Store` 上传。
6. 先发内部 TestFlight。
7. 再发外部 TestFlight。
8. 收集反馈后，补齐 App Store 元数据并提交正式审核。

如果你的目标是直接上架，仍然建议至少先跑一轮小范围 TestFlight，再把同一版或修正后的 build 交给 App Review。

## 5. Apple 官方资料

- Xcode 分发总览：<https://developer.apple.com/documentation/xcode/distributing-your-app-for-beta-testing-and-releases>
- 准备项目用于分发：<https://developer.apple.com/documentation/xcode/preparing-your-app-for-distribution>
- App Store Connect 工作流：<https://developer.apple.com/help/app-store-connect/get-started/app-store-connect-workflow>
- 创建 App 记录：<https://developer.apple.com/help/app-store-connect/create-an-app-record/add-a-new-app>
- 上传 build：<https://developer.apple.com/help/app-store-connect/manage-builds/upload-builds/>
- TestFlight 总览：<https://developer.apple.com/help/app-store-connect/test-a-beta-version/testflight-overview/>
- 添加内部测试者：<https://developer.apple.com/help/app-store-connect/test-a-beta-version/add-internal-testers/>
- 邀请外部测试者：<https://developer.apple.com/help/app-store-connect/test-a-beta-version/invite-external-testers/>
- 提交 App 审核：<https://developer.apple.com/help/app-store-connect/manage-submissions-to-app-review/submit-an-app>
- App Store 发布总览：<https://developer.apple.com/help/app-store-connect/manage-your-apps-availability/overview-of-publishing-your-app-on-the-app-store/>
- 管理 App Privacy：<https://developer.apple.com/help/app-store-connect/manage-app-information/manage-app-privacy>
- 设置年龄分级：<https://developer.apple.com/help/app-store-connect/manage-app-information/set-an-app-age-rating/>
- 上传截图和预览：<https://developer.apple.com/help/app-store-connect/manage-app-information/upload-app-previews-and-screenshots>
- 设置价格：<https://developer.apple.com/help/app-store-connect/manage-app-pricing/set-a-price>
- App Review Guidelines：<https://developer.apple.com/app-store/review/guidelines/>
- CloudKit schema 发布：<https://developer.apple.com/documentation/cloudkit/deploying-an-icloud-container-s-schema>
- 启用 CloudKit：<https://developer.apple.com/documentation/cloudkit/enabling-cloudkit-in-your-app>
