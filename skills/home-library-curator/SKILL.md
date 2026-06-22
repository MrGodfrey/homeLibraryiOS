---
name: home-library-curator
description: Curate a homeLibrary CloudKit repository through the local home-library-cloudkit CLI. Use for exporting an AI workspace, generating and validating .homelibpatch files, reviewing changes, and applying approved library metadata or cover updates.
---

# home-library-curator

Use this skill to manage a `homeLibrary` CloudKit repository through the local CLI, not by editing cache files or calling CloudKit directly.

## Non-Negotiable Rules

- Do not read, print, copy, or summarize `markdownNote/test`.
- Do not edit `cloudkit-cache` or any `.derived/AIWorkflow` output as a source of truth.
- Do not call CloudKit APIs directly from the agent; use `home-library-cloudkit`.
- Do not bypass `validate-patch`.
- Do not silently delete books, remove covers, replace existing covers, or replace non-empty fields.
- High-risk operations require `review-patch` and an approved `ReviewDecision.json`.
- For main repositories, use read-only export/validate/dry-run until the user explicitly asks to apply.
- Test-only auto approval is allowed only for `--remote memory` or `AIWorkflowTest-*` while `HOME_LIBRARY_CLOUDKIT_LIVE_TESTS=1`.
- Keep real snapshots, patches, review decisions, apply results, tokens, and account data under `.derived/AIWorkflow/`, which must remain git ignored.

## Standard Workflow

1. Build the CLI if needed:

   ```bash
   scripts/build_home_library_cloudkit.sh
   ```

   For real CloudKit access, set an Apple signing identity:

   ```bash
   CLI_BIN="$(HOME_LIBRARY_CODESIGN_IDENTITY="<Apple signing identity>" HOME_LIBRARY_CLOUDKIT_ENVIRONMENT=production scripts/build_home_library_cloudkit.sh)"
   ```

   In signed mode, use the executable path printed by the script. It may be inside `.build/debug/home-library-cloudkit.app/Contents/MacOS/` because macOS restricted CloudKit entitlements require an embedded provisioning profile. Production is the default and is required for the user's release iPhone library; use `HOME_LIBRARY_CLOUDKIT_ENVIRONMENT=development` only for explicitly isolated tests.

   Do not run multiple signed CLI builds or commands in parallel. The signed wrapper is rebuilt in place.

2. Run doctor:

   ```bash
   .build/debug/home-library-cloudkit doctor
   ```

3. List repositories:

   ```bash
   .build/debug/home-library-cloudkit repos
   ```

4. Export an AI workspace:

   ```bash
   .build/debug/home-library-cloudkit export-ai-workspace \
     --repo <repo-id> \
     --output .derived/AIWorkflow/AIWorkspace.zip
   ```

5. Read `LibrarySnapshot.json`, `MissingMetadataReport.json`, `DuplicateCandidates.json`, `CoverStatus.json`, and `PatchSchema.json` from the workspace.

6. Generate a `.homelibpatch` with:

   - `schemaVersion: 1`
   - `targetRepository`
   - `baseSnapshot`
   - operations from `createBook`, `updateBook`, `updateBookCover`, `removeBookCover`, `deleteBook`
   - evidence URLs for every researched claim
   - `expectedUpdatedAt` and `expectedRecordChangeTag` for existing-book operations
   - `expectedCurrentCoverAssetID` for cover replacement/removal

7. Validate before review or apply:

   ```bash
   .build/debug/home-library-cloudkit validate-patch \
     .derived/AIWorkflow/suggested.homelibpatch \
     --repo <repo-id> \
     --result .derived/AIWorkflow/PatchValidationResult.json
   ```

8. Review high-risk operations:

   ```bash
   .build/debug/home-library-cloudkit review-patch \
     .derived/AIWorkflow/suggested.homelibpatch \
     --repo <repo-id> \
     --result .derived/AIWorkflow/ReviewDecision.json
   ```

9. Apply only after validation and required approval:

   ```bash
   .build/debug/home-library-cloudkit apply-patch \
     .derived/AIWorkflow/suggested.homelibpatch \
     --review-decision .derived/AIWorkflow/ReviewDecision.json \
     --result .derived/AIWorkflow/ApplyResult.json
   ```

10. Read `ApplyResult.json` and summarize:

    - applied
    - skipped
    - conflicts
    - failed
    - retryable failed

11. For protected real CloudKit verification, use a signed CLI and an isolated test repository prefix:

    ```bash
   HOME_LIBRARY_CLOUDKIT_LIVE_TESTS=1 \
   HOME_LIBRARY_CLOUDKIT_CONTAINER=iCloud.yu.homeLibrary \
   HOME_LIBRARY_CLOUDKIT_ENVIRONMENT=production \
   HOME_LIBRARY_TEST_REPOSITORY_PREFIX=AIWorkflowTest \
   HOME_LIBRARY_TEST_SIMULATOR_NAME="iPhone 17 Pro" \
   HOME_LIBRARY_REPO_ROOT="$PWD" \
    "$CLI_BIN" run-live-test --result .derived/AIWorkflow/CloudKitLiveResult.json
    ```

    When `HOME_LIBRARY_TEST_SIMULATOR_NAME` is set, `run-live-test` also builds and launches the iOS app on that booted simulator, then verifies that the app can read the CLI-written test book before cleanup.

## Patch Guidance

- Prefer `fillIfEmpty` for metadata cleanup.
- Use `replaceIfCurrentValue` only when the current value is known and included.
- Do not invent ISBNs, publication years, publishers, translators, or cover sources.
- Chinese books should prefer Chinese-language publication evidence when available.
- If ISBN candidates disagree, do not apply; report the ambiguity.
- Cover payloads can be pre-compressed, but the CLI always recompresses with the app-aligned rule: max edge `720 px`, target `220 KB`, `coverAssetID = cover-<sha256 final data>`.
- Delete operations must describe the reason and evidence, and must go through review.

## Memory Test Workflow

Use this for local dry runs that do not touch CloudKit:

```bash
.build/debug/home-library-cloudkit doctor --remote memory
.build/debug/home-library-cloudkit repos --remote memory
.build/debug/home-library-cloudkit export-ai-workspace --remote memory --repo memory --output .derived/AIWorkflow/CommandWorkspace
.build/debug/home-library-cloudkit validate-patch .derived/AIWorkflow/suggested.homelibpatch --snapshot .derived/AIWorkflow/CommandWorkspace/LibrarySnapshot.json
.build/debug/home-library-cloudkit review-patch .derived/AIWorkflow/suggested.homelibpatch --snapshot .derived/AIWorkflow/CommandWorkspace/LibrarySnapshot.json --result .derived/AIWorkflow/ReviewDecision.json --auto-approve-test-only --remote memory
.build/debug/home-library-cloudkit apply-patch .derived/AIWorkflow/suggested.homelibpatch --remote memory --review-decision .derived/AIWorkflow/ReviewDecision.json --result .derived/AIWorkflow/ApplyResult.json
```
