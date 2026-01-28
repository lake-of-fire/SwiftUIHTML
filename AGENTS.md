# Repository Guidelines

## Project Structure & Module Organization
- `Sources/SwiftUIHTML` holds the reusable rendering core; `Example` contains the SwiftUI host app and its unit/UI test targets.  
- `SwiftUIHTMLExampleTests` and `SwiftUIHTMLExampleUITests` live next to the example project and keep the snapshot/test helpers, including `ViewSnapshotTester.swift`.  
- `SwiftUIHTMLExampleTests/__Snapshots__/HTMLBasicTests` stores the PNG baselines and HTML payloads.  
- `scripts/` hosts the snapshot-reporting helpers, OCR utilities, and the new `run_ios_snapshots.sh` driver.  
- `mise.toml` defines high-level automation tasks invoked with `mise <task>` while `Package.swift` drives SwiftPM dependency resolution.

## Build, Test, and Development Commands
- `mise ios-snapshots`: boots the current iOS simulator, records every snapshot with `SWIFTUIHTML_SNAPSHOT_RECORD=1`, and produces `/tmp/swiftuihtml-ios-snapshot-report-*/index.html`.  
- `mise ios-snapshot-single TEST_ONLY=...`: focuses on one XCTest and emits a mini report for that snapshot.  
- `python3 scripts/snapshot_report.py --artifacts <dir> --baseline SwiftUIHTMLExampleTests/__Snapshots__/HTMLBasicTests --title "<label>" --out-prefix /tmp/...`: regenerates the HTML dashboard; add `--test-log` to include xcodebuild results.  
- `xcodebuild test -scheme SwiftUIHTMLExample ...`: used when you need finer control, but prefer the `mise` wrapper for consistent artifact capture.

## Coding Style & Naming Conventions
- Follow Swift conventions: 4-space indentation, `camelCase` for variables/methods, `PascalCase` for types/protocols, and `lower_snake_case` for snapshot file stems (e.g., `testBulletImageAlignment.bulletImageAlignment.png`).  
- Keep UI modifiers chained cleanly, avoid deeply nested closures, and prefer short helper functions (see `ViewSnapshotTester`).  
- No automated formatter is enforced, but align new Swift files with the surrounding style and run `swift build`/`swift test` to surface formatter warnings.

## Testing Guidelines
- Snapshot tests live in `HTMLBasicTests`; each snapshot helper is also exposed through `HTMLBasicXCTest` so `xcodebuild -only-testing` can exercise the view.  
- Naming follows `test<ScenarioDescription>`; the snapshot artifact includes the test name plus logic-specific suffixes (e.g., `.longWordsWithImages_byCharWrapping`).  
- Always run through `mise ios-snapshots` (or the single/test-specific task) so artifacts, OCR logs, and HTML inputs are collected together with the report.

## Snapshot Reporting & Diagnostics
- `scripts/run_ios_snapshots.sh` now copies the simulator’s `artifactsRoot` back into `/tmp/swiftuihtml-ios-artifacts`, ensuring `snapshot_report.py` can find both baseline and new images.  
- Diagnostic logs (`SWIFTUIHTML_ATTACHMENT_LOGS`, margin diagnostics, OCR json files) live under `/tmp/swiftuihtml-ios-artifacts` and are attached to XCTActivities. Link them from reports when investigating regressions.

## Commit & Pull Request Guidelines
- Write imperative commit messages (`Fix list-item gap`, `Align bullet-plus-image snapshot`). Include the test(s) you updated if relevant.  
- PRs should describe what snapshot regressions exist, list which mise task(s) were run (e.g., `mise ios-snapshots`), and attach the latest report path (e.g., `/tmp/swiftuihtml-ios-snapshot-report-<timestamp>/index.html`). Add screenshots or report snippets when visual diffs matter.
