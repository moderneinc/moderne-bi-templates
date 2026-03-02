# Trace.csv Data Dictionary

The Moderne CLI produces a `trace.csv` file that records telemetry for each CLI command. Traces are **hierarchical** — later commands in the workflow embed all data from earlier stages. For example, a `mod run` trace contains sync and build stage data in addition to run stage data.

Reference: [CLI Telemetry Documentation](https://docs.moderne.io/user-documentation/moderne-cli/how-to-guides/cli-telemetry)

## Trace Hierarchy

Each CLI command produces a trace that includes its own stage plus all prior stages:

| Command | Stages Included |
|---------|-----------------|
| `mod git sync` | Sync |
| `mod build` | Sync + Build |
| `mod run` | Sync + Build + Run |
| `mod git apply` | Sync + Build + Run + Apply |
| `mod git add` | Sync + Build + Run + Apply + Add |
| `mod git commit` | Sync + Build + Run + Apply + Add + Commit |
| `mod git push` | Sync + Build + Run + Apply + Add + Commit + Push |
| `mod exec` | Exec (standalone) |
| `mod git checkout` | Checkout (standalone) |

## Column Reference

### Common Fields (columns 1–4)

Present in all traces.

| Column | Type | Description | Example |
|--------|------|-------------|---------|
| `origin` | string | SCM host | `github.com` |
| `path` | string | Repository path (org/repo) | `openrewrite/rewrite` |
| `branch` | string | Branch name | `main` |
| `developer` | string | User email | `user@example.com` |

### Sync Stage (columns 5–11)

Populated after `mod git sync`.

| Column | Type | Description | Example |
|--------|------|-------------|---------|
| `syncOutcome` | string | Clone/sync result | `Succeeded` |
| `syncCloneUri` | string | Clone URL | `https://github.com/org/repo` |
| `syncLstDownloadUri` | string | LST download URL | (empty if built locally) |
| `syncStartTime` | ISO 8601 | Sync start timestamp | `2026-02-19T00:07:11.946Z` |
| `syncEndTime` | ISO 8601 | Sync end timestamp | `2026-02-19T00:07:13.704Z` |
| `syncChangeset` | string | Git commit SHA at sync | `a3b1862d...` |
| `syncElapsedTimeMs` | integer | Duration in milliseconds | `1758` |

### Build Stage (columns 12–36)

Populated after `mod build`.

| Column | Type | Description | Example |
|--------|------|-------------|---------|
| `buildOutcome` | string | Build result | `Succeeded` |
| `buildStartTime` | ISO 8601 | Build start timestamp | `2026-02-19T00:12:22.215Z` |
| `buildEndTime` | ISO 8601 | Build end timestamp | `2026-02-19T00:12:47.263Z` |
| `buildId` | string | Build identifier | `20260219000719-cYGAL` |
| `buildDependencyResolutionTimeMs` | integer | Dependency resolution time (ms) | `13534` |
| `buildChangeset` | string | Git SHA at build time | `a3b1862d...` |
| `buildMavenVersion` | string | Maven version used | `3.8.4` |
| `buildGradleVersion` | string | Gradle version used | |
| `buildBazelVersion` | string | Bazel version used | |
| `buildDotnetVersion` | string | .NET version used | |
| `buildPythonVersion` | string | Python version used | |
| `buildNodeVersion` | string | Node.js version used | |
| `buildOsName` | string | Build host OS | `Linux` |
| `buildOsVersion` | string | OS kernel version | `4.14.355-280.710.amzn2.x86_64` |
| `buildOsEol` | string | Line ending format | `LF` |
| `buildGitAutocrlf` | string | Git autocrlf setting | `False` |
| `buildGitEol` | string | Git eol setting | `Native` |
| `buildSourceFileCount` | integer | Source files in repo | `256` |
| `buildLineCount` | integer | Total lines of code | `41015` |
| `buildParseErrorCount` | integer | Parse errors during build | `1` |
| `buildWeight` | integer | LST weight | `83285` |
| `buildMaxWeight` | integer | Max single-file weight | `6617` |
| `buildMaxWeightSourceFile` | string | Heaviest file path | `src/test/MessageMLContextTest.java` |
| `buildCliVersion` | string | CLI version used | `3.57.8` |
| `buildElapsedTimeMs` | integer | Build duration (ms) | `25048` |

### Run Stage (columns 37–57)

Populated after `mod run`.

| Column | Type | Description | Example |
|--------|------|-------------|---------|
| `runOutcome` | string | Recipe run result | `Succeeded` |
| `runStartTime` | ISO 8601 | Run start timestamp | `2026-02-19T20:53:58.396Z` |
| `runEndTime` | ISO 8601 | Run end timestamp | `2026-02-19T20:54:29.312Z` |
| `runId` | string | Run identifier | `20260219145356-EWS22` |
| `runUnlicensedAttempt` | boolean | Was this an unlicensed attempt? | `false` |
| `runStreaming` | boolean | Streaming mode? | `false` |
| `runRecipeId` | string | Fully qualified recipe name | `org.openrewrite.java.OrderImports` |
| `runRecipeInstanceName` | string | Display name | `Order imports` |
| `runRecipeOptions` | string | JSON recipe options | `{}` |
| `runRecipeArtifact` | string | Recipe artifact GAV | `org.openrewrite:rewrite-java:8.70.0` |
| `runEstimatedEffortTimeSavingsMs` | integer | Estimated time saved (ms) | `23100000` |
| `runDependencyResolutionTimeMs` | integer | Dependency resolution time (ms) | `0` |
| `runPomCacheHitRate` | float | POM cache hit rate | `0.919` |
| `runResolvedPomCacheHitRate` | float | Resolved POM cache hit rate | `1.0` |
| `runFilesWithFixResults` | integer | Files with fix results | `77` |
| `runFilesWithSearchResults` | integer | Files with search results | `0` |
| `runFilesWithErrors` | integer | Files with errors | `0` |
| `runFilesSearched` | integer | Total files searched | `252` |
| `runDataTables` | integer | Data tables produced | `2` |
| `runThread` | string | Thread name | `ForkJoinPool.commonPool-worker-10` |
| `runElapsedTimeMs` | integer | Recipe run duration (ms) | `30916` |

### Apply Stage (columns 58–62)

Populated after `mod git apply`.

| Column | Type | Description | Example |
|--------|------|-------------|---------|
| `applyOutcome` | string | Apply result | `Succeeded` |
| `applyStartTime` | ISO 8601 | Apply start timestamp | `2026-02-19T21:28:30.330Z` |
| `applyEndTime` | ISO 8601 | Apply end timestamp | `2026-02-19T21:28:30.621Z` |
| `applyId` | string | Apply identifier | `20260219152829-UpYgU` |
| `applyElapsedTimeMs` | integer | Duration (ms) | `291` |

### Add Stage (columns 63–67)

Populated after `mod git add`.

| Column | Type | Description | Example |
|--------|------|-------------|---------|
| `addOutcome` | string | Git add result | `Succeeded` |
| `addStartTime` | ISO 8601 | Add start timestamp | `2026-02-19T21:28:31.090Z` |
| `addEndTime` | ISO 8601 | Add end timestamp | `2026-02-19T21:28:32.485Z` |
| `addId` | string | Add identifier | `20260219152830-FN6kt` |
| `addElapsedTimeMs` | integer | Duration (ms) | `1395` |

### Commit Stage (columns 68–73)

Populated after `mod git commit`.

| Column | Type | Description | Example |
|--------|------|-------------|---------|
| `commitOutcome` | string | Commit result | `Succeeded` |
| `commitStartTime` | ISO 8601 | Commit start timestamp | `2026-02-19T21:28:32.965Z` |
| `commitEndTime` | ISO 8601 | Commit end timestamp | `2026-02-19T21:28:33.064Z` |
| `commitId` | string | Commit identifier | `20260219152832-ztzOh` |
| `commitBranch` | string | Target branch | `main` |
| `commitElapsedTimeMs` | integer | Duration (ms) | `99` |

### Organization (column 74)

| Column | Type | Description | Example |
|--------|------|-------------|---------|
| `organization` | string | Moderne organization identifier | |

**Note:** Push stage columns (`pushOutcome`, `pushStartTime`, `pushEndTime`, `pushId`, `pushElapsedTimeMs`) are present when `mod git push` is used. Traces from `mod exec` and `mod git checkout` are standalone and not part of the main workflow chain.
