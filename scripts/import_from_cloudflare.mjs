#!/usr/bin/env node

import {mkdtemp, readFile, rm, stat, writeFile} from "node:fs/promises";
import {tmpdir} from "node:os";
import path from "node:path";
import {spawn} from "node:child_process";

const args = process.argv.slice(2);

function readArg(flag, fallback = null) {
  const index = args.indexOf(flag);
  if (index === -1) {
    return fallback;
  }

  return args[index + 1] ?? fallback;
}

const sourceRepo = readArg("--source-repo", "/Users/wangyu/code/Home-library");
const outputPath = readArg("--output", path.resolve("homeLibrary/SeedBooks.json"));
const bucketName = readArg("--bucket", "homelibrary");

function run(command, commandArgs, options = {}) {
  return new Promise((resolve, reject) => {
    const child = spawn(command, commandArgs, {
      cwd: options.cwd,
      env: process.env,
      stdio: ["ignore", "pipe", "pipe"],
    });

    let stdout = "";
    let stderr = "";

    child.stdout.on("data", (chunk) => {
      stdout += chunk.toString();
    });

    child.stderr.on("data", (chunk) => {
      stderr += chunk.toString();
    });

    child.on("error", reject);
    child.on("close", (code) => {
      if (code === 0) {
        resolve({stdout, stderr});
        return;
      }

      reject(new Error(`${command} ${commandArgs.join(" ")} failed with code ${code}\n${stderr || stdout}`));
    });
  });
}

function stripWranglerBanner(text) {
  const jsonStart = text.indexOf("[");
  if (jsonStart === -1) {
    throw new Error("Wrangler output does not contain JSON payload.");
  }

  return text.slice(jsonStart);
}

function toISO8601(value) {
  if (!value) {
    return new Date().toISOString();
  }

  const normalized = value.replace(" ", "T") + "Z";
  const date = new Date(normalized);

  if (Number.isNaN(date.getTime())) {
    throw new Error(`Unsupported date value: ${value}`);
  }

  return date.toISOString();
}

async function downloadCover(coverObjectKey, targetDir) {
  const filename = coverObjectKey.replaceAll("/", "__");
  const filePath = path.join(targetDir, filename);

  await run(
    "npx",
    ["wrangler", "r2", "object", "get", `${bucketName}/${coverObjectKey}`, "--remote", "--file", filePath],
    {cwd: sourceRepo},
  );

  const data = await readFile(filePath);
  return data.toString("base64");
}

async function main() {
  console.log(`Using source repo: ${sourceRepo}`);
  console.log(`Writing seed file: ${outputPath}`);

  const {stdout} = await run(
    "npx",
    [
      "wrangler",
      "d1",
      "execute",
      "home-library",
      "--remote",
      "--command",
      "SELECT id, title, author, publisher, year, isbn, location, cover_url, cover_object_key, owner_email, created_at, updated_at FROM books ORDER BY datetime(created_at) DESC;",
      "--json",
    ],
    {cwd: sourceRepo},
  );

  const payload = JSON.parse(stripWranglerBanner(stdout));
  const rows = payload[0]?.results ?? [];

  console.log(`Fetched ${rows.length} books from D1.`);

  const tempDir = await mkdtemp(path.join(tmpdir(), "home-library-covers-"));

  try {
    const seedBooks = [];

    for (let index = 0; index < rows.length; index += 1) {
      const row = rows[index];
      const hasCover = typeof row.cover_object_key === "string" && row.cover_object_key.length > 0;
      const coverData = hasCover ? await downloadCover(row.cover_object_key, tempDir) : null;

      seedBooks.push({
        id: row.id,
        title: row.title ?? "",
        author: row.author ?? "",
        publisher: row.publisher ?? "",
        year: row.year ?? "",
        location: row.location === "重庆" ? "重庆" : "成都",
        customFields: row.isbn ? {ISBN: row.isbn} : {},
        coverData,
        createdAt: toISO8601(row.created_at),
        updatedAt: toISO8601(row.updated_at),
      });

      console.log(`[${index + 1}/${rows.length}] ${row.title}${hasCover ? "" : " (no cover)"}`);
    }

    const seedPayload = {
      schemaVersion: 1,
      source: "cloudflare:d1/home-library+r2/homelibrary",
      exportedAt: new Date().toISOString(),
      books: seedBooks,
    };

    await writeFile(outputPath, JSON.stringify(seedPayload, null, 2));
    const outputStats = await stat(outputPath);

    console.log(`Seed file written: ${outputPath}`);
    console.log(`Seed file size: ${(outputStats.size / 1024 / 1024).toFixed(2)} MB`);
  } finally {
    await rm(tempDir, {recursive: true, force: true});
  }
}

main().catch((error) => {
  console.error(error instanceof Error ? error.message : String(error));
  process.exitCode = 1;
});
