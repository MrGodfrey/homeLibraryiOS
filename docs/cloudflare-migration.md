# Cloudflare Migration

## 原仓库存储结构

源仓库 `/Users/wangyu/code/Home-library` 的数据保存在 Cloudflare：

- `D1` 数据库：`home-library`
- 数据表：`books`
- `R2` bucket：`homelibrary`
- 封面键字段：`cover_object_key`

其中：

- 书籍基础字段存在 D1 `books` 表
- 封面二进制文件存在 R2
- `books.cover_object_key` 用来定位 R2 对象

## 当前 app 的迁移方式

当前 app 默认支持两种导入落点：

- 本地模式：首次空库时自动把种子数据导入本地缓存
- CloudKit 模式：首次创建且远端空仓库时，自动把同一份种子数据写入 CloudKit

导入完成后，后续开发迭代都直接使用本地缓存 / CloudKit 数据，不需要重复手动迁移旧库。

迁移流程：

1. 使用 `scripts/import_from_cloudflare.mjs`
2. 从源仓库调用 `wrangler` 访问远端 D1 / R2
3. 生成当前 app 可直接使用的结构化种子文件 `homeLibrary/SeedBooks.json`
4. app 运行时在空仓库上自动消费该种子文件

## 运行方法

在当前仓库根目录执行：

```bash
node scripts/import_from_cloudflare.mjs --source-repo /Users/wangyu/code/Home-library
```

默认输出：

```text
homeLibrary/SeedBooks.json
```

可选参数：

- `--source-repo`：源仓库路径
- `--output`：种子文件输出路径
- `--bucket`：R2 bucket 名，默认 `homelibrary`

## 注意

- 该脚本依赖源仓库中的 `wrangler` 和当前机器上的 Cloudflare 登录态
- `SeedBooks.json` 会随 app 一起打包，因此真机本地模式也能直接看到旧数据
- `homeLibrary/SeedBooks.json` 是本地生成文件，默认不纳入 git，但只要文件存在就会被 Xcode 打包进 app bundle
- 如果当前本地缓存或 CloudKit 仓库已经有数据，种子文件不会覆盖现有数据
