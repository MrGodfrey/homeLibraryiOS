# homeLibrary 分发操作手册（非常详细版）

本文基于我在 **2026-04-15** 查阅的 Apple 官方文档整理，目标是让你可以一边打开 Xcode、一边打开网页，照着一步一步完成 `homeLibrary` 的 **TestFlight 分发** 和 **App Store 上架**。

这份文档按你要的方式拆成两大部分：

1. **在 Xcode 中怎么操作**
2. **在网页中怎么操作**

适用对象：当前仓库里的 iPhone App `homeLibrary`。

---

## 先看当前项目的实际配置

我先把这个项目里和分发直接相关的配置列出来，后面每一步都会用到：

- Xcode 工程：`homeLibrary.xcodeproj`
- App Target：`homeLibrary`
- Bundle ID：`yu.homeLibrary`
- Version：`1.0`
- Build：`1`
- Deployment Target：`iOS 26.4`
- 设备：`iPhone only`
- iCloud Container：`iCloud.yu.homeLibrary`
- 关键能力：
  - CloudKit
  - Cloud Documents
  - `CKShare` 系统共享
  - 相册选图
- `Info.plist` 里当前已有：
  - `CKSharingSupported = true`
  - `NSPhotoLibraryUsageDescription = 选择书籍封面需要访问相册。`

这几个结论你先记住：

1. 这不是一个纯离线 App，它依赖 **iCloud / CloudKit**。
2. 这不是一个 iPad App，目前只需要重点准备 **iPhone** 相关内容。
3. 由于它依赖 CloudKit，**上架前一定要把 development schema 部署到 production**，否则别人装上 TestFlight 或正式版后，云同步很可能直接失败。
4. 当前 `Build = 1`，第一次上传可以用，但只要你再上传第二次，就必须把 Build 改成更大的数字，比如 `2`、`3`、`4`。

---

## 你真正要走的整体顺序

如果你是第一次做，建议按这个顺序：

1. 先在 **Xcode** 里把项目检查到可归档状态。
2. 再到 **网页**里创建 App Store Connect 的 App 记录。
3. 再到 **网页**里的 CloudKit Console 部署 schema 到 production。
4. 回到 **Xcode** 做 `Archive` 和上传。
5. 再到 **网页**里做 TestFlight 内测 / 外测。
6. 最后在 **网页**里补齐 App Store 元数据并提交审核。

不要一上来就直接 `Archive -> Upload`。  
第一次分发最容易卡住的地方，通常不是 Xcode，而是网页里缺资料、CloudKit 没部署、隐私信息没填。

---

## 一、在 Xcode 中怎么操作

这一部分只讲 **Xcode 里需要你点哪里、改哪里、怎么看是否正确**。

---

### 1. 打开项目

1. 打开 Xcode。
2. 选择 `Open a project or file`。
3. 选中这个工程文件：
   - `homeLibrary.xcodeproj`
4. 等 Xcode 把索引、签名、包依赖都处理完。
5. 左侧 Project Navigator 里，点最上面的蓝色项目图标 `homeLibrary`。

这时中间区域会出现：

- `PROJECT`
- `TARGETS`

后面绝大多数分发相关操作，都是在 **TARGETS > homeLibrary** 下面完成。

---

### 2. 检查 Target 选对了没有

1. 在中间区域左侧，找到 `TARGETS`。
2. 点击 `homeLibrary`。
3. 确认你现在看到的是这个 App 的设置，而不是 `homeLibraryTests` 或 `homeLibraryUITests`。

这一点非常重要。  
分发设置必须看 **App target**，不要在测试 target 里改。

---

### 3. 在 General 里检查 Identity

1. 点击上方标签页 `General`。
2. 找到 `Identity` 区域。
3. 重点检查以下几项：

- **Display Name / Name**
  - 确认是你想展示给用户的名字。
- **Bundle Identifier**
  - 应该是：`yu.homeLibrary`
- **Version**
  - 当前是：`1.0`
- **Build**
  - 当前是：`1`

#### 这里怎么填最稳妥

- 如果这是你第一次上传：
  - `Version` 可以继续用 `1.0`
  - `Build` 可以继续用 `1`
- 如果你已经上传过一次，准备重新上传：
  - `Version` 可先不变，比如还是 `1.0`
  - **Build 必须加 1**
  - 比如从 `1` 改成 `2`

#### Version 和 Build 的区别

- `Version` 是用户看得到的版本号，比如 `1.0`、`1.1`
- `Build` 是同一个版本下的第几次上传，比如 `1`、`2`、`3`

简单记法：

- 小修复重新传包：通常只加 `Build`
- 真正发新版本：`Version` 和 `Build` 一起调整

---

### 4. 在 General 里检查 Deployment Info

1. 还在 `General` 页。
2. 往下找到 `Deployment Info`。
3. 检查：

- **Target**
  - 当前项目是：`iOS 26.4`
- **Devices**
  - 当前项目是：`iPhone`

#### 这意味着什么

- 只有系统版本不低于 `iOS 26.4` 的设备，才能安装你的 TestFlight 包或正式版。
- 你上传后，低于这个系统版本的设备根本装不了。

如果你后面准备邀请测试员，记得提前告诉他们最低系统版本要求，不然他们会以为是 TestFlight 坏了。

---

### 5. 在 Signing & Capabilities 里检查签名

1. 点击上方标签页 `Signing & Capabilities`。
2. 看 `Signing` 区域。
3. 逐项检查：

- `Automatically manage signing` 是否勾选
- `Team` 是否已经选到你的开发者团队
- `Bundle Identifier` 是否仍然是 `yu.homeLibrary`

#### 正常状态应该是什么

- 一般建议 **勾选 Automatically manage signing**
- `Team` 一定要是你加入了 Apple Developer Program 的团队

如果这里没有 Team，或者 Team 选不上，后面的 Archive 和 Upload 通常都会失败。

---

### 6. 在 Signing & Capabilities 里检查能力开关

还在 `Signing & Capabilities` 页面，往下看 capability 列表。

你需要确认至少这些能力存在，而且状态正常：

#### 6.1 iCloud

1. 在 capabilities 列表里找到 `iCloud`。
2. 确认它已经开启。
3. 确认下面的勾选项里有：
   - `CloudKit`
   - `Cloud Documents`
4. 确认容器列表里有：
   - `iCloud.yu.homeLibrary`

#### 6.2 其他与共享相关能力

这个项目用到了 `CKShare`，`Info.plist` 里已经有 `CKSharingSupported = true`。  
这一项不在 `Signing & Capabilities` 里点，而是在配置文件里声明。你现在要做的是确认它没有被删。

---

### 7. 检查 Info.plist 里的分发关键字段

1. 左侧 Project Navigator 中找到：
   - `homeLibrary`
   - `Info.plist`
2. 点开后确认以下字段仍然存在：

- `CKSharingSupported`
  - 值应为 `YES`
- `NSPhotoLibraryUsageDescription`
  - 文案应准确、通顺、真实

#### 关于权限文案

Apple 审核很看重“权限申请理由是否真实对应功能”。

你这个项目的相册权限文案现在是：

- `选择书籍封面需要访问相册。`

这句是可用的，因为它明确说明了访问相册的用途。

如果你后面又新增了相机、通知、定位等功能，就必须同步补充对应权限说明，否则上传后会出问题。

---

### 8. 检查 entitlements 文件

1. 左侧找到：
   - `homeLibrary/homeLibrary.entitlements`
2. 打开后确认：

- iCloud container 里有：
  - `iCloud.yu.homeLibrary`
- iCloud services 里有：
  - `CloudKit`
  - `CloudDocuments`

#### 当前项目的一个注意点

这个文件里当前有：

- `aps-environment = development`

我这里没有直接替你改它，因为是否需要改、最终 Archive 产物如何签名，要以你实际团队证书和 Xcode 归档结果为准。  
你在真正上传前，至少做一次：

1. `Archive`
2. `Validate App`

如果签名或 entitlement 有问题，通常会在这里暴露。

---

### 9. 检查 App Icon

1. 左侧打开 `Assets.xcassets`。
2. 点击 `AppIcon`。
3. 检查是否所有必填图标槽都已经填满。

对于 App Store 分发，图标不是“差不多就行”，而是必须完整。  
如果缺尺寸，归档、验证或审核时都可能出错。

---

### 10. 先做一次真机自测

在进入 Archive 之前，建议先真机跑一遍关键流程。

最少测试这些：

1. 能正常启动 App。
2. 能创建书库。
3. 能添加书籍。
4. 能从相册选封面。
5. 能发起共享邀请。
6. 能在另一台设备或另一个 Apple Account 上接受共享。
7. 接受共享后能读到同一份数据。

#### 为什么这一步不能省

因为这个 App 的核心不是“能打开界面”，而是：

- CloudKit 是否正常
- 共享链路是否正常
- 生产环境 schema 是否完整

你只在模拟器里点几下，并不能替代真机验证。

---

### 11. 选择正确的归档目标

归档前，你要把运行目标从模拟器切换成可归档目标。

1. 看 Xcode 顶部工具栏左上角。
2. 找到 Scheme 选择器。
3. Scheme 应该是：
   - `homeLibrary`
4. 运行目标不要选某台模拟器。
5. 改成类似下面这种归档目标：
   - `Any iOS Device (arm64)`
   - 或者 Xcode 提供的通用 iOS 归档目标

如果你还选着某个 iPhone 模拟器，`Archive` 往往会是灰的，或者归档行为不对。

---

### 12. 执行 Archive

1. 菜单栏点击 `Product`
2. 点击 `Archive`
3. 等待构建完成

成功后，Xcode 会自动打开 `Organizer` 窗口，并切到 `Archives` 列表。

如果没有自动弹出：

1. 菜单栏点 `Window`
2. 点 `Organizer`
3. 左侧选 `Archives`

---

### 13. 在 Organizer 里确认这次归档没问题

在 `Organizer > Archives` 里：

1. 选中最新的 Archive
2. 看右侧信息
3. 确认：

- App 名称正确
- 版本号正确
- Build 号正确
- 时间是刚刚这次生成的

如果版本号或 Build 不对，不要硬着头皮传，先回 Xcode 改再重新 Archive。

---

### 14. 先点 Validate App

Apple 官方虽然不是每次都强制你先点，但第一次分发非常建议先做。

1. 在 Organizer 里选中刚刚的 archive
2. 右侧点击 `Validate App`
3. 按向导继续

如果中间弹出签名、隐私、导出合规之类的问题，按实际情况回答。

#### 为什么建议先 Validate

它能更早暴露这些问题：

- 签名不对
- entitlement 不匹配
- 缺少分发必填项
- archive 包结构异常

如果 `Validate App` 已经报错，你不要继续上传，先修。

---

### 15. 点击 Distribute App

1. 在同一个 archive 上，点击右侧 `Distribute App`
2. Xcode 会让你选分发方式

这里你最常见会看到这些选项：

- `TestFlight & App Store`
- `TestFlight Internal Only`
- `Release Testing`
- `Custom`

#### 这里怎么选

如果你的目标是：

- **想发 TestFlight 给别人**
- **并且将来还可能直接拿这个 build 去上架**

请选择：

- `TestFlight & App Store`

#### 不要误选 `TestFlight Internal Only`

Apple 官方说明得很清楚：

- `TestFlight Internal Only` 只能给内部测试组使用
- 这种 build **不能用于外部测试**
- 也**不能提交给 App Store 用户**

所以只要你有“给外部测试员”或“后面正式上架”的打算，就不要选这个。

---

### 16. 按 Xcode 上传向导继续

选择 `TestFlight & App Store` 之后：

1. 点击 `Distribute`
2. Xcode 会开始处理包
3. 期间可能出现若干确认页

一般按默认推荐设置走就行。  
Apple 官方对这个预设的说明是：

- 它会用默认推荐设置上传到 App Store Connect
- 可以管理版本 / 构建号
- 自动处理签名
- 上传符号文件

#### 你在这一步要重点看什么

如果页面出现类似选项，优先保持合理默认值：

- 上传 symbols：通常建议保留开启
- 自动管理版本和 build number：一般可开启
- 不要勾成 internal-only

---

### 17. 等待上传完成

上传完成后，Xcode 通常会提示成功，并给出跳转到 App Store Connect builds 页的入口。

这时你在 Xcode 里的工作基本结束，但事情还没完。  
**真正的后续动作都在网页里做**：

- build 处理
- TestFlight 组管理
- 外部测试审核
- App Store 提交审核

---

### 18. 如果 Xcode 上传后你在网页里还看不到 build

这是正常情况之一。  
上传完成不等于网页里立刻可用。

你需要知道两件事：

1. App Store Connect 会先处理 build
2. 处理完成后，build 才会出现在 TestFlight / 版本选择区域

所以如果你刚传完就去网页里找不到，不要立刻判断为失败，先等一会儿再刷新。

---

### 19. Xcode 部分的最简检查清单

在你关闭 Xcode 之前，确认这几项：

- [ ] Target 确实是 `homeLibrary`
- [ ] Bundle ID 是 `yu.homeLibrary`
- [ ] Team 已选对
- [ ] `Automatically manage signing` 已开启
- [ ] iCloud / CloudKit / `iCloud.yu.homeLibrary` 正确
- [ ] `CKSharingSupported` 还在
- [ ] 相册权限文案还在
- [ ] Version / Build 已更新
- [ ] AppIcon 已完整
- [ ] 已成功 `Archive`
- [ ] 已跑过 `Validate App`
- [ ] 已通过 `Distribute App -> TestFlight & App Store` 上传

---

## 二、在网页中怎么操作

这一部分讲两个网页系统：

1. **App Store Connect**
   - 地址：`https://appstoreconnect.apple.com/`
2. **CloudKit Console**
   - 地址：`https://icloud.developer.apple.com/`

其中：

- App Store Connect 用来创建 App、填资料、做 TestFlight、提审
- CloudKit Console 用来把 schema 从 development 部署到 production

---

### 0. 第一次登录前先知道你可能会遇到什么

Apple 官方说明：

- 最初只有 `Account Holder` 能登录 App Store Connect
- 如果最新协议还没签，账号会先被要求签协议
- 如果你要收费、IAP、订阅，还要在 `Business` 里完成 Paid Apps Agreement、税务和收款

如果你的 App 是免费 App，税务和收款通常不是当前第一步阻塞项，但协议本身仍可能卡住你。

---

### 1. 在 App Store Connect 里创建 App 记录

这是第一次分发时必须做的步骤。  
Apple 官方要求：**第一次上传前先创建 app record**。

#### 具体操作

1. 打开浏览器，进入：
   - `https://appstoreconnect.apple.com/`
2. 登录你的开发者账号。
3. 进入首页后，点击顶部或主区域的 `Apps`。
4. 到 Apps 页面后，点击左上角的加号 `+`。
5. 选择 `New App`。

这时会弹出 `New App` 对话框。

#### 这个对话框里怎么填

你至少会看到这些字段：

- `Platforms`
- `Name`
- `Primary Language`
- `Bundle ID`
- `SKU`
- `User Access`

#### 建议你这样填

- `Platforms`
  - 选 `iOS`
- `Name`
  - 填你准备在 App Store / TestFlight 展示的 App 名称
- `Primary Language`
  - 选你的主语言
- `Bundle ID`
  - 选 `yu.homeLibrary`
- `SKU`
  - 自己定义一个内部识别码，例如：
    - `homeLibrary-ios`
    - 或 `homeLibrary-2026`
- `User Access`
  - 如果只有你自己操作，选默认即可
  - 如果团队里只想让部分人看到，才选 `Limited Access`

6. 填完后点击 `Create`

创建成功后，这个 App 的状态通常会变成：

- `Prepare for Submission`

这表示 App 记录已经建好了，但资料还没填完。

---

### 2. 在网页里先补最基础的 App 信息

创建完 App 后，先别急着做 TestFlight。  
你先把 App 基础资料补起来。

#### 具体操作

1. 在 `Apps` 页面点击你刚创建的 `homeLibrary`
2. 进入后，先看左侧边栏
3. 常用区域一般包括：
   - App Information
   - Pricing and Availability
   - TestFlight
   - App Privacy
   - 版本页（例如 iOS App 版本）

---

### 3. 填 App Information

#### 具体操作

1. 左侧点击 `App Information`
2. 在右侧逐项填写或确认

这里通常会涉及：

- Name
- Subtitle
- Category
- Content Rights
- Age Rating
- 其他平台级基础信息

#### 你在这里重点处理什么

##### 3.1 类别 Category

1. 找到 `Category`
2. 选择最适合这个 App 的主类别
3. 如有次类别，也按实际情况选

Apple 官方建议 App Store Connect 里的主类别要和 Xcode 中设置保持一致。  
如果你在 Xcode 里没专门设置类别，网页里仍然要认真选。

##### 3.2 隐私政策入口

虽然很多人会在别处填，但你要从一开始就准备好：

- `Privacy Policy URL`

Apple 官方说明：

- **Privacy Policy URL 是所有 App 的必填项**

所以你最好现在就准备一个公开可访问的网址。  
如果没有，你后面提审时一定会被卡住。

##### 3.3 Support URL

也建议提前准备：

- 支持页面 URL
- 联系邮箱 / 联系方式

这不是“最好有”，而是正式上架时经常会成为必填或强烈需要填写的项。

---

### 4. 设置 Age Rating（年龄分级）

Apple 当前年龄分级系统已经是新版问卷式流程。  
这一项是必填，而且 **Unrated 不能发布到 App Store**。

#### 具体操作

1. 在 `App Information` 页面里找到 `Age Rating`
2. 点击进入问卷
3. 按实际功能回答每一项

你会看到一些关于以下内容的问题：

- 敏感内容出现频率
- 赌博
- Loot Boxes
- 用户生成内容
- Web 访问能力
- 社交能力

#### 填写原则

- 不要为了“看起来更健康”而故意填低
- 也不要因为紧张而乱填太高
- 按 App 实际能力回答

对于 `homeLibrary` 这类家庭书库 App，一般重点要看的是：

- 是否有用户生成内容
- 是否有外部网页访问
- 是否有社交 / 共享功能

共享功能不等于社交平台，但你仍然要按问卷的定义认真勾选。

4. 问卷做完后点击 `Save`

---

### 5. 填 App Privacy

这一块是很多人第一次上架最容易漏的。

Apple 官方要求：

- 如果要在 App Store 分发，必须在 App Store Connect 里说明数据处理方式
- 要包含你自己的做法，也要包含第三方代码的做法
- `Privacy Policy URL` 为所有 App 必填

#### 具体操作

1. 左侧点击 `App Privacy`
2. 右侧点击 `Get Started`

这时 Apple 会先问你一个大问题：

- 你的 App 是否收集数据

#### 你要怎么理解“收集数据”

Apple 的口径不是“你自己有没有另建服务器”，而是：

- 只要你的 App 或第三方伙伴通过 App 收集并处理数据，就需要申报

对于这个项目，建议你至少严肃评估这些是否属于需要申报的数据：

- 用户录入的书籍内容
  - 标题
  - 作者
  - 出版社
  - 位置
  - 备注
- 封面图片
- 与共享相关的用户内容
- 通过 CloudKit 同步到云端的其他数据

#### 具体填写步骤

1. 如果你确认不收集任何数据，选：
   - `No, we do not collect data from this app`
2. 如果有数据进入 CloudKit 或其他云端处理，通常就应按实际选：
   - `Yes, we collect data from this app`
3. 点击 `Next`
4. 在数据类型列表里，把实际收集的数据类型勾出来
5. 对每一种数据类型继续回答后续问题
   - 是否用于追踪
   - 是否与用户身份关联
   - 用途是什么
6. 全部答完后点击 `Save`
7. 看页面下方的 `Product Page Preview`
8. 确认无误后，点击右上角 `Publish`
9. 在确认框里再次点击 `Publish`

#### 再补 Privacy Policy URL

如果页面上 `Privacy Policy` 还是空的：

1. 在 `App Privacy` 页找到 `Privacy Policy`
2. 点击 `Edit`
3. 填入：
   - `Privacy Policy URL`
4. 如有需要，再填：
   - `User Privacy Choices URL`
5. 点击 `Save`

---

### 6. 设置 Pricing and Availability

即使你是免费 App，这一页也得填。

#### 具体操作

1. 左侧点击 `Pricing and Availability`
2. 按实际情况设置：
   - 价格
   - 销售地区 / 国家地区
   - 是否全部地区可售

Apple 官方说明：

- 在提交 App Store 审核前，必须设置 availability
- App 可以选择在 175 个国家或地区发布

#### 如果你是免费 App

1. 价格选免费
2. 国家 / 地区建议先全开，或者只开你准备提供服务的地区

#### 如果你还没准备好所有地区

可以先只选目标地区。  
但要注意，如果后面 App 已经在某地区发布，就不能再把那个地区当成“预购地区”。

---

### 7. 上传 App Store 截图

Apple 官方要求：

- 每种设备尺寸 / 语言，截图最少 `1` 张，最多 `10` 张
- App Preview 可选，每种设备尺寸 / 语言最多 `3` 个

你这个项目是 iPhone only，所以你主要准备 iPhone 截图。

#### 具体操作

1. 左侧点击你的 iOS 版本页
   - 如果还没有版本页，就先创建版本
2. 找到 `App Previews and Screenshots`
3. 直接把截图拖进去

#### 如果有多语言

1. 在页面右上切换语言
2. 分语言上传截图和文案

#### 如果有不同尺寸要单独传

1. 点击 `View All Sizes in Media Manager`
2. 在里面按设备尺寸分别上传

#### 对你这个项目的建议

至少准备这些 iPhone 截图：

1. 书库首页
2. 新增书籍页面
3. 书籍详情页
4. 封面选择 / 展示效果
5. 共享相关页面

第一张截图尤其重要，因为它很可能直接成为用户最先看到的核心展示图。

---

### 8. 在 CloudKit Console 里部署 schema 到 production

这一步不是 App Store Connect，而是 **CloudKit Console**。  
对于这个项目，这是正式分发前的硬前提。

Apple 官方明确说明：

- 开发阶段你在 development 环境里建立 schema
- App Store 上的 App **只能访问 production 环境**
- 发布前必须把 development schema 部署到 production

#### 具体操作

1. 打开：
   - `https://icloud.developer.apple.com/`
2. 登录同一个开发者账号
3. 进入 `CloudKit Database`
4. 在顶部容器下拉菜单里选择：
   - `iCloud.yu.homeLibrary`
5. 左侧找到：
   - `Deploy Schema Changes`
6. 点击进入
7. 查看待部署的 schema 变更
8. 确认无误后点击：
   - `Deploy`

#### 这一步会部署什么

- Record Types
- Fields
- Indexes

#### 这一步不会部署什么

- development 环境里的测试数据不会被一起复制过去

也就是说：

- schema 会过去
- 记录本身不会过去

#### 为什么这一步一定要做

如果你不部署 production schema，最常见的现象就是：

1. App 可以安装
2. 页面能打开
3. 但一到 CloudKit 读写、共享、拉数据时就失败

对于 `homeLibrary` 这种以 CloudKit 为核心的 App，这一步不能省。

---

### 9. 等待 Xcode 上传的 build 处理完成

回到 App Store Connect。

#### 具体操作

1. 左侧或顶部进入你的 App
2. 点击 `TestFlight`
3. 看 `Builds` 或平台 build 列表

如果刚上传完，build 可能暂时显示处理中。  
等它处理完成后，才能继续后面的组分发和审核。

---

### 10. 先填 TestFlight 的测试信息

Apple 官方要求：

- 外部测试前，要先提供 TestFlight 测试信息

#### 具体操作

1. 进入 App 后点击 `TestFlight`
2. 左侧边栏里，在 `Additional` 下面点击 `Test Information`
3. 在右侧选择语言
4. 填写必填信息

你通常会看到这些字段：

- `Beta App Description`
- `Feedback Email`
- 可能还有邀请展示相关设置

#### 建议你这样写

##### Beta App Description

写清这是个什么 App，以及 beta 想让测试者测什么。  
例如要涵盖：

- 家庭书库管理
- 书籍录入
- 封面选择
- iCloud 同步
- 共享邀请与接受

##### Feedback Email

填一个你确实会看的邮箱。  
测试员在 TestFlight 里反馈时，会走这个地址。

4. 填好后保存

---

### 11. 先建一个 Internal Testing 组

Apple 官方说明：

- Internal testers 最多 `100` 人
- 外部测试前，**必须先有内部测试组**

#### 具体操作

1. 进入 `TestFlight`
2. 左侧在 `Internal Testing` 旁边点击加号 `+`
3. 弹出框里输入组名
   - 例如：`Core Team`
4. 如有需要，勾选：
   - `Enable automatic distribution`
5. 点击 `Create`

#### 是否勾自动分发

- 如果希望以后新 build 自动发给这个内部组，就勾上
- 如果你想每次手动控制发哪个 build，就不勾

---

### 12. 把内部测试员加进组里

#### 具体操作

1. 在 `Internal Testing` 下点击你刚创建的组
2. 右侧点击 `Invite Testers`
3. 在 App Store Connect 用户列表里勾选要加入的人
4. 点击 `Add`

#### 如果你想加的人不在列表里

说明这个人还不是你 App Store Connect 账户里的合格内部用户。  
内部测试员必须是有权限的 App Store Connect 用户，不是随便一个邮箱。

---

### 13. 把 build 加到内部测试组

#### 具体操作

1. 还在刚才那个内部测试组页面
2. 点击 `Add Builds`
3. 选择平台和版本
4. 在表格里选中刚处理好的 build
5. 点击 `Next`
6. 在 `What to Test` 里填写这次让测试者重点测什么
7. 点击 `Add`

#### What to Test 建议这样写

对于这个项目，建议至少包含：

1. 创建书库
2. 添加 / 编辑书籍
3. 从相册选择封面
4. 发起共享邀请
5. 接受共享邀请
6. 被共享成员是否能读取同一份数据

内部测试员收到邀请后，就可以通过 TestFlight 安装测试。

---

### 14. 如果你只想小范围试用，到这里就可以先停

如果你当前只是：

- 自己测
- 和少量团队成员测

那么做到内部测试就够了。

但如果你的目标是“发给普通用户试用”，你还要继续做 **External Testing**。

---

### 15. 创建 External Testing 组

Apple 官方说明：

- External testers 最多 `10,000` 人
- 第一次把 build 发给外部测试组，通常要经过 TestFlight App Review

#### 具体操作

1. 在 `TestFlight` 页面左侧
2. 找到 `External Testing`
3. 点击旁边的加号 `+`
4. 输入组名
   - 例如：`Public Beta`
5. 点击创建

---

### 16. 把 build 加到外部测试组

#### 具体操作

1. 点击刚创建的外部测试组
2. 右侧点击 `Add Builds`
3. 选择平台和版本
4. 选中要发出去的 build
5. 点击 `Add`

这一步通常还会要求你填写：

- `What to Test`

建议写得比内部测试更清楚，因为外部测试员通常对项目背景不熟。

---

### 17. 提交 TestFlight App Review

Apple 官方说明：

- 当你把 build 加进外部组时，系统会进入 TestFlight 外测审核流程
- 第一个 build 通常需要完整审核
- 同一版本后续 build 可能不需要完整复审，但不要假设一定免审

#### 具体操作

1. 在外部测试组里加完 build 后
2. 如果页面显示 `Submit Review`
3. 就点击 `Submit Review`

有时如果 build 状态已经满足，也可能显示：

- `Start Testing`

如果是这种情况，就按页面可点击的按钮继续。

#### 还要注意一条 Apple 的限制

Apple 目前说明：

- 24 小时内最多可提交 `6` 个 build 给 TestFlight App Review

所以不要在短时间里疯狂传包并反复送审。

---

### 18. 邀请外部测试员

外测审核通过后，你可以正式邀请测试员。

Apple 支持两种常见方式：

1. 邮箱邀请
2. Public Link

---

### 19. 用邮箱邀请外部测试员

#### 具体操作

1. 进入外部测试组
2. 点击 `Invite Testers`
3. 选择邮箱邀请方式
4. 输入测试员邮箱
5. 发送邀请

对方会收到邮件，然后通过 TestFlight 接受邀请并安装。

---

### 20. 用 Public Link 邀请外部测试员

如果你不想一个个录邮箱，Public Link 更方便。

#### 具体操作

1. 进入外部测试组
2. 切到 `Testers` 页签
3. 点击 `Create Public Link`

Apple 官方这里会让你选两种模式：

- `Open to Anyone`
- `Filter by Criteria`

#### 这两个怎么选

##### Open to Anyone

- 任何拿到链接的人都可以加入

##### Filter by Criteria

- 可以按设备或平台筛选

#### 对这个项目的建议

因为 `homeLibrary` 的最低系统版本较高，所以如果页面支持筛选条件，建议认真设置。  
这样能减少不符合系统要求的人加入后装不了、再回来问你为什么失败。

#### 还可以设置人数上限

Public Link 还支持设置：

- `Tester Limit`

如果你想只放出小规模名额，可以这里限制人数。

---

### 21. 查看 TestFlight 反馈

#### 具体操作

1. 进入 `TestFlight`
2. 左侧查看 `Testers` 或反馈相关区域
3. 查看：
   - 安装情况
   - 测试状态
   - 截图反馈
   - 崩溃相关反馈

Apple 官方说明，公开链接加入的测试者在列表里可能会显示为匿名，除非他们通过特定方式留下邮箱信息。

---

### 22. 如果你只想发 TestFlight，到这里已经完成了

如果你的目标只是“给别人试用”，你做到下面这几个点就算完成：

1. App 记录已创建
2. CloudKit schema 已部署到 production
3. build 已从 Xcode 上传
4. Test information 已填写
5. 内部测试组已建立
6. 外部测试组已建立并审核通过
7. 测试者已通过邮箱或 Public Link 收到邀请

---

### 22.1 以后每次更新一个 TestFlight 新版本，你应该做什么

这一节专门回答你现在这个问题：

- 我修了 bug，重新传一个新版本到 TestFlight，应该做什么？
- 为什么我明明上传了新包，测试者却看不到？
- 已经在测试组里的那些人，要不要重新邀请？

先记住最重要的结论：

1. **已有测试者通常不需要重新邀请。**
2. **你每次重新上传，都必须让 Xcode 里的 `Build` 变大。**
3. **只把包传上去还不够，你还要把新 build 分发到对应的测试组。**
4. **外部测试的新 build，通常还要经过 TestFlight App Review，批准后测试者才能看到。**

#### 情况 A：只是修 bug，想让现有测试者更新到新的 beta build

这是最常见的情况。  
比如你已经发出去 `Version 1.0 (Build 3)`，现在修了一个问题，想发 `Build 4` 给同一批测试者。

你应该这样做：

##### 第 1 步：先改 Xcode 里的版本号

1. 打开 Xcode。
2. 进入 `TARGETS > homeLibrary > General > Identity`。
3. 看 `Version` 和 `Build`。

如果只是同一个 beta 周期里的修复，最稳妥的做法通常是：

- `Version` 先不变
- **只把 `Build` 加 1**

例如：

- 原来是 `Version 1.0 / Build 3`
- 现在改成 `Version 1.0 / Build 4`

Apple 官方说明里，`bundle ID` 和 `version number` 用来把 build 归到对应 App 和版本记录下，而 `build string` 用来唯一标识这一次 build。  
所以如果你重复上传，**`Build` 不能和之前一样**。

##### 第 2 步：重新 Archive 并上传

1. 选择 `homeLibrary` scheme。
2. 选择归档目标，例如 `Any iOS Device (arm64)`。
3. 点击 `Product -> Archive`。
4. 在 `Organizer` 里选最新 archive。
5. 先点 `Validate App`。
6. 再点 `Distribute App`。
7. 选择 `TestFlight & App Store`。
8. 继续上传。

##### 第 3 步：等待 App Store Connect 处理 build

1. 打开 `App Store Connect`。
2. 进入你的 App。
3. 点击 `TestFlight`。
4. 等待新 build 从处理状态变成可用状态。

如果 build 还在处理中，测试者此时还看不到。

##### 第 4 步：把这个新 build 分发到测试组

这一步非常关键。  
**上传成功 != 测试者已经能更新。**

你要看你发的是内部测试还是外部测试。

---

#### 情况 A-1：发给 Internal Testing（内部测试）

Apple 官方说明：

- 内部组可以开启 `Enable automatic distribution`
- 如果开启了，Xcode 上传的新 build 可以自动分发给组成员
- 如果没开启，你就必须手动把新 build 加进组里

##### 你先这样判断

1. 进入 `App Store Connect -> 你的 App -> TestFlight`
2. 左侧点击对应的内部测试组
3. 看这个组当初创建时是否启用了：
   - `Enable automatic distribution`

##### 如果这个组选了自动分发

通常你做完下面这些后，内部测试者就能看到新 build：

1. Xcode 里把 `Build` 加 1
2. 重新上传
3. 等待处理完成

这时内部测试组会自动拿到新 build。

##### 如果这个组没有开自动分发

你还要手动做一次：

1. 进入 `TestFlight`
2. 左侧点击你的内部测试组
3. 右侧点击 `Add Builds`
4. 选中刚上传的新 build
5. 点击 `Next`
6. 填写或更新 `What to Test`
7. 点击 `Add`

做完之后，组里的内部测试者才能在 TestFlight 里看到新 build。

---

#### 情况 A-2：发给 External Testing（外部测试）

外部测试和内部测试最大的区别是：

1. 新 build 通常要过 `TestFlight App Review`
2. 你必须把新 build 加到外部测试组
3. 是否自动通知测试者，要看你有没有勾选 `Automatically notify testers`

##### 标准步骤

1. 进入 `App Store Connect -> 你的 App -> TestFlight`
2. 左侧点击对应的外部测试组
3. 点击 `Add Builds`
4. 选中刚处理好的新 build
5. 点击 `Next`
6. 更新 `What to Test`
7. 如果页面有：
   - `Automatically notify testers`
   建议勾上
8. 根据状态点击：
   - `Submit Review`
   或 `Start Testing`

##### 这里有两个重要规则

Apple 官方目前明确写了：

1. **同一个 Version，一次只能有一个 build 处于 review 中。**
2. **等前一个同版本 build 审核通过后，才能继续提这个版本的后续 build。**

例如：

- `1.0 (Build 4)` 正在 TestFlight Review
- 那你不能同时再把 `1.0 (Build 5)` 也送进 review

这种时候你可以先上传 `Build 5`，但要等 `Build 4` 的 review 结束后，才能继续提。

##### 如果你没有勾选 `Automatically notify testers`

那就算 build 已经审核通过，外部测试者也不一定立刻收到更新。

你还要手动点一次：

1. 进入 `App Store Connect -> TestFlight`
2. 左侧在 `Builds` 下点击平台
3. 选中对应 `Version`
4. 在 build 那一行的状态区域点击：
   - `Notify Testers`

Apple 官方说明，只有你点了 `Notify Testers` 后，外部测试者才会收到通知并在 TestFlight 里开始测试这个 build。

---

#### 情况 B：我想发“新版本”，而不是同一版本下的新 build

例如你现在已经测完 `1.0`，准备开始测 `1.1`。

这时建议你这样做：

1. 在 Xcode 里把 `Version` 从 `1.0` 改成 `1.1`
2. 把 `Build` 设成新的值
   - 常见做法是设成 `1`
   - 或继续沿用你自己的递增规则
3. 再按上面的归档、上传、加测试组流程走一遍

你可以把它理解成：

- `Version` 是一条新的测试主线
- `Build` 是这条主线里的第几次包

---

#### 已经在测试组里的测试者，要不要重新邀请？

通常 **不用**。

只要下面这些条件成立：

1. 这个测试者还在原来的测试组里
2. 你把新 build 加进了同一个组
3. 外部测试需要的话，这个 build 已经过审
4. 你开启了自动通知，或者手动点了 `Notify Testers`

那这个测试者就能继续测试新 build，不需要重新走一遍邮箱邀请或 Public Link 加入流程。

---

#### 测试者那边通常会怎么更新

从开发者视角，你需要做的是：

1. 上传新 build
2. 把 build 分发到正确的组
3. 对外部测试 build 完成审核 / 通知

做到这三步后，测试者就会在 TestFlight 里看到新的可用 build。  
测试者常见的操作是：

- 打开 TestFlight
- 找到你的 App
- 点击 `Update`

如果测试者设备上的 TestFlight 开了自动更新，更新可能会更快出现；如果没有，通常就需要他们自己进 TestFlight 点更新。  
这一条是根据 TestFlight 的实际使用行为做的操作性说明。

---

#### 为什么你上传了新 build，但测试者还是看不到

这是最常见的排查清单。你可以按这个顺序查：

##### 1. 你忘了改 `Build`

这是第一常见原因。  
重新上传时，`Build` 必须是新值。

##### 2. build 还在 Processing

你刚传完的时候，App Store Connect 还在处理。  
处理没完成之前，测试组拿不到。

##### 3. 你只上传了 build，但没把它加到测试组

上传成功后，build 只是“存在于 App Store Connect”。  
它不一定已经“发给测试者”。

##### 4. 内部测试组没有开自动分发，而你忘了手动 `Add Builds`

这种情况下，内部测试者不会自动看到新版本。

##### 5. 外部测试 build 还没通过 TestFlight App Review

外部测试一定要等 review 状态走完。

##### 6. 外部测试时你没勾 `Automatically notify testers`，也没手动点 `Notify Testers`

这会导致 build 虽然批准了，但测试者仍然没有被推送到这个新 build。

##### 7. build 过期了

Apple 官方说明，TestFlight build 的可测试期是 `90` 天。  
过期后要重新上传新 build。

##### 8. 你把 build 加到了错误的组

比如你以为加到了 `Public Beta`，实际加到了另一个组。  
这在有多个测试组时很常见。

---

#### 最实用的更新流程模板

以后你每次给现有测试者发一个新版 TestFlight，直接照这个最短流程做：

1. 在 Xcode 中点击项目图标，targets，general 中把 `Build` 加 1。
2. `Product -> Archive -> Validate App -> Distribute App -> TestFlight & App Store`。
3. 去 App Store Connect 等 build 处理完成。
4. 内部测试：
   - 如果没开自动分发，手动 `Add Builds`。
5. 外部测试：
   - 把 build 加到外部组
   - 更新 `What to Test`
   - 勾 `Automatically notify testers`
   - 提交 `Submit Review`
6. 等外测通过后，确认测试者已收到新 build。

如果你每次都按这 6 步走，测试者基本就都能正常更新到新版。

---

### 23. 如果你还要正式上架 App Store，继续往下做

TestFlight 只是测试分发。  
正式上架还需要补齐 App Store 元数据，并把某个 build 提交给 App Review。

---

### 24. 创建或进入目标 iOS 版本页

在 App Store Connect 里，正式审核是按“版本”提交的。

#### 具体操作

1. 进入你的 App
2. 左侧找到 iOS 平台下的版本区域
3. 如果已经有版本，例如 `1.0`
   - 点进去
4. 如果还没有
   - 创建一个新版本

#### 版本号怎么定

这里的版本号应和你 Xcode 里 `Version` 对应。  
例如：

- Xcode `Version = 1.0`
- App Store Connect 版本页也应是 `1.0`

---

### 25. 在版本页补完整的 App Store 文案

这一页通常要填很多内容，至少包括：

- Subtitle
- Description
- Keywords
- Support URL
- Marketing URL（如需要）
- Promotional Text（如需要）
- 截图
- App Review 信息

#### 建议填写顺序

1. 先填标题区文案
2. 再填描述
3. 再填关键词
4. 再确认 Support URL
5. 再检查截图

这样最不容易漏。

---

### 26. 选择 App Review 用的 build

Apple 官方说明，提交审核前必须：

- 先补齐需要的元数据
- 再为该版本选择 build

#### 具体操作

1. 进入目标版本页
2. 向下滚到 `Build` 区域
3. 点击选择 build
4. 从已上传并处理完成的 build 里选中正确版本
5. 保存

如果这里找不到 build，通常是以下原因之一：

1. Xcode 还没上传成功
2. App Store Connect 还在处理 build
3. Xcode 里的版本号和当前版本页不匹配

---

### 27. 处理 Export Compliance（加密合规）

很多 App 第一次上传后都会在这里被拦一下。

Apple 官方说明：

- 只要 App 使用、访问、包含、实现或集成加密功能，就要先判断 export compliance
- 可以在 `App Information` 里处理，也可以在 build 旁边点 `Manage`

#### 具体操作

方法一：

1. 左侧点击 `App Information`
2. 找到 `App Encryption Documentation`
3. 点击加号 `+`
4. 按实际情况回答问题

方法二：

1. 如果某个 build 旁边显示缺少加密信息
2. 点击 `Manage`
3. 直接在弹窗里回答

#### 填写原则

一定按 App 实际使用的加密方式回答。  
不要想当然地随便点“没有”，也不要因为看到 HTTPS / CloudKit 就慌着乱传材料。

如果 Apple 认为你需要上传文档，页面会继续要求你上传。

---

### 28. 补 App Review Information

Apple 官方明确建议：

- 如果 App 需要特定设置、账户、特殊操作路径，就在 App Review Information 里写清楚

对于 `homeLibrary`，这一步很重要，因为它依赖 iCloud 和共享流程。

#### 具体操作

1. 在目标版本页向下找到 `App Review Information`
2. 填：
   - Contact first name / last name
   - Contact phone number
   - Contact email
   - Notes
3. 如果 App 需要登录，再填 demo account

#### 你这个项目的 Notes 建议至少写清楚

1. App 依赖设备已登录 iCloud
2. 核心功能包含 CloudKit 同步
3. 共享功能使用系统共享链路
4. 主流程如何进入：
   - 创建书库
   - 添加书籍
   - 选择封面
   - 发起共享
   - 接受共享
5. 如果审核方无法准备两台设备或两个账号，哪些功能可以先单机验证

#### 为什么这一段要写细

因为审核员不会自己猜你的主流程。  
如果你不写，他们很可能只点开首页看看，然后认为“功能不完整”或“无法复现核心体验”。

---

### 29. 选择 App Store 的发布时间方式

Apple 官方提供三种常见发布方式：

1. 手动发布
2. 审核通过后自动发布
3. 审核通过后不早于某个日期自动发布

#### 具体操作

1. 进入目标版本页
2. 找到 `App Store Version Release`
3. 按需要选择：

##### 方案 A：`Manually release this version`

适合你想先等审核通过，再自己决定哪天上线。

##### 方案 B：`Automatically release this version`

适合你希望审核一通过就自动上架。

##### 方案 C：`Automatically release this version after App Review, no earlier than ...`

适合你卡一个上线日期。

#### 我对第一次上架的建议

第一次上架，建议选：

- `Manually release this version`

这样审核通过后，你还有最后一次确认机会。

---

### 30. 如有需要，设置 phased release

这是给“更新版本”用得更多的功能。  
Apple 支持把自动更新在 7 天内逐步放量。

如果你是第一次发布新 App，通常用不到。  
如果以后做版本更新，可以考虑。

---

### 31. 正式提交审核

Apple 官方的正式步骤是：

1. 版本页里确认 build 正确
2. 点击 `Add for Review`
3. 把版本加入草稿 submission
4. 再点击 `Submit for Review`

#### 具体操作

1. 进入目标版本页
2. 再次确认以下都已填好：
   - 文案
   - 截图
   - App Privacy
   - Age Rating
   - Pricing and Availability
   - Build
   - App Review Information
   - Export Compliance（如需要）
3. 页面右上点击 `Add for Review`
4. 如果系统让你选择：
   - 加入现有 draft submission
   - 创建新 submission
   按当前情况选择即可
5. 状态变成 `Ready for Review`
6. 再点击 `Submit for Review`

提交后，状态通常会进入：

- `Waiting for Review`
- `In Review`

---

### 32. 审核通过后怎么发布

如果你前面选的是手动发布：

1. 等状态变成：
   - `Pending Developer Release`
2. 进入该版本页
3. 右上点击：
   - `Release This Version`
4. 在确认框里点击：
   - `Confirm`

Apple 官方说明：

- 手动发布后，App 可能还需要最多约 24 小时才会在 App Store 完全显示出来

所以别在你点完发布后的 30 秒内就判断“怎么还搜不到”。

---

### 33. 网页部分的最简检查清单

#### TestFlight 必查

- [ ] 已能登录 App Store Connect
- [ ] 已创建 App 记录
- [ ] `Bundle ID` 选的是 `yu.homeLibrary`
- [ ] `Pricing and Availability` 已设置
- [ ] `App Privacy` 已填写并发布
- [ ] `Age Rating` 已填写
- [ ] iPhone 截图已上传
- [ ] `Test Information` 已填写
- [ ] 已建内部测试组
- [ ] 已把 build 加进内部测试组
- [ ] 已建外部测试组
- [ ] 已把 build 提交给 TestFlight App Review
- [ ] 已通过邮箱或 Public Link 发出邀请

#### 正式上架必查

- [ ] CloudKit schema 已部署到 production
- [ ] 版本页文案已填写完整
- [ ] `Privacy Policy URL` 已填写
- [ ] `Support URL` 已填写
- [ ] build 已正确选中
- [ ] Export Compliance 已处理
- [ ] `App Review Information` 已写清 iCloud / 共享流程
- [ ] 发布方式已选好
- [ ] 已点 `Add for Review`
- [ ] 已点 `Submit for Review`

---

## 三、针对这个项目，我建议你这样执行

如果你现在是第一次把 `homeLibrary` 发给别人，我建议按下面这个实际顺序做：

1. 在 Xcode 里检查 `Team`、`Bundle ID`、Version、Build、iCloud capability。
2. 在 App Store Connect 创建 `yu.homeLibrary` 的 App 记录。
3. 在 CloudKit Console 把 `iCloud.yu.homeLibrary` 的 schema 部署到 production。
4. 回 Xcode 做真机自测。
5. 在 Xcode 里执行 `Archive -> Validate App -> Distribute App -> TestFlight & App Store`。
6. 在 App Store Connect 里等 build 处理完成。
7. 填 `Test Information`。
8. 先建内部测试组并发内部测试。
9. 再建外部测试组并提交 TestFlight App Review。
10. 如果外测没问题，再补齐 App Store 页面资料并正式提审。

---

## 四、这个项目最容易踩的坑

### 1. 只上传 build，但没创建 App 记录

第一次分发时，很多人以为“Xcode 能传就行”。  
实际更稳妥的方式是：**先在 App Store Connect 创建 App**。

### 2. CloudKit schema 只在 development，没部署到 production

这对你的项目是最大风险。  
会出现“安装正常，但同步 / 共享全坏掉”的情况。

### 3. Build 号没加

同一版本重新上传时，如果 `Build` 还是旧值，App Store Connect 会拒绝。

### 4. 误选 `TestFlight Internal Only`

一旦这样上传，这个 build 只能做内部测试，不能走外部测试，也不能直接给 App Store 用户。

### 5. App Privacy 乱填

你的数据虽然是走 CloudKit，但只要 App 通过这些服务处理用户数据，就要按实际情况申报，不能简单理解成“不是我自己服务器，所以等于不收集”。

### 6. Review Notes 写太少

这个项目的核心是共享流程。  
如果你不写审核路径，审核员可能根本走不到正确流程。

---

## 五、Apple 官方资料

下面这些是我这次整理时实际参考的官方资料，后续你自己核对也建议优先看这些：

- Xcode 分发总览  
  <https://developer.apple.com/documentation/xcode/distributing-your-app-for-beta-testing-and-releases>

- 准备项目用于分发  
  <https://developer.apple.com/documentation/xcode/preparing-your-app-for-distribution>

- App Store Connect 工作流  
  <https://developer.apple.com/help/app-store-connect/get-started/app-store-connect-workflow>

- 创建 App 记录  
  <https://developer.apple.com/help/app-store-connect/create-an-app-record/add-a-new-app>

- TestFlight 总览  
  <https://developer.apple.com/help/app-store-connect/test-a-beta-version/testflight-overview/>

- 提供 TestFlight 测试信息  
  <https://developer.apple.com/help/app-store-connect/test-a-beta-version/provide-test-information>

- 添加内部测试员  
  <https://developer.apple.com/help/app-store-connect/test-a-beta-version/add-internal-testers/>

- 邀请外部测试员  
  <https://developer.apple.com/help/app-store-connect/test-a-beta-version/invite-external-testers/>

- 上传 build  
  <https://developer.apple.com/help/app-store-connect/manage-builds/upload-builds/>

- 把测试者或测试组加到 build  
  <https://developer.apple.com/help/app-store-connect/test-a-beta-version/add-testers-to-builds>

- 查看 build 状态  
  <https://developer.apple.com/help/app-store-connect/reference/app-uploads/app-build-statuses>

- 上传截图和 App Preview  
  <https://developer.apple.com/help/app-store-connect/manage-app-information/upload-app-previews-and-screenshots>

- 管理 App 隐私  
  <https://developer.apple.com/help/app-store-connect/manage-app-information/manage-app-privacy>

- 设置年龄分级  
  <https://developer.apple.com/help/app-store-connect/manage-app-information/set-an-app-age-rating/>

- 管理可售地区  
  <https://developer.apple.com/help/app-store-connect/manage-your-apps-availability/manage-availability-for-your-app-on-the-app-store/>

- 选择发布方式  
  <https://developer.apple.com/help/app-store-connect/manage-your-apps-availability/select-an-app-store-version-release-option>

- 提交 App 审核  
  <https://developer.apple.com/help/app-store-connect/manage-submissions-to-app-review/submit-an-app>

- CloudKit schema 部署到 production  
  <https://developer.apple.com/documentation/cloudkit/deploying-an-icloud-container-s-schema>

---

## 六、最后给你一句最实用的提醒

对 `homeLibrary` 来说，真正的分发完成标准不是“Xcode 上传成功”，而是下面四件事同时成立：

1. App Store Connect 里有正确的 App 记录
2. CloudKit production schema 已部署
3. TestFlight / App Review 所需网页资料已补齐
4. 真机上完整共享链路能跑通

如果你只完成了第 1 件或第 2 件，离真正“别人可以正常用”还差得很远。
