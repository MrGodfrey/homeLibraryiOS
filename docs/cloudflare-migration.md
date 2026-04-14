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

当前 app 不再依赖 iCloud，改为本地 JSON 持久化。

迁移流程：

1. 使用 `scripts/import_from_cloudflare.mjs`
2. 从源仓库调用 `wrangler` 访问远端 D1 / R2
3. 生成当前 app 可直接使用的 `homeLibrary/SeedBooks.json`
4. app 首次启动且本地书库为空时，自动把 `SeedBooks.json` 复制到本地存储

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
- 如果当前 app 已经在本地生成过书库文件，种子文件不会覆盖现有本地数据
