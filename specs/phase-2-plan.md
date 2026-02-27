# Next Steps

## Important Issues (Next Iteration)

| **Issue**                  | **Detail**                                                                                                                                                              |
| -------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Overloaded ContentView** | Acts as a "massive controller." Extract an `EditorViewModel` for better testability.                                                                                    |
| **Thumbnail Race**         | No cancellation token; rapid file switching can cause stale thumbnails to overwrite current ones. Add a `loadID` or `Task` cancellation.                                |
| **Continuation Hang**      | `generateThumbnails` ignores callback errors. If `AVAssetImageGenerator` fails to invoke a callback, `withCheckedContinuation` hangs.                                   |
| **Codec Semantics**        | `ExportFormat` names imply codec control (e.g., `.mp4HEVC`), but only the container is set. `AVAssetExportSession` may not guarantee the codec without `AVAssetWriter`. |
| **Fragile Index Lookup**   | `times.firstIndex` using `CMTimeCompare` can miss due to rounding. Use an enumerated index instead.                                                                     |
| **Incompatibility**        | Passthrough + incompatible container (e.g., ProRes `.mov` -> `.mp4`) will fail. UI should prevent this.                                                                 |

## Testing Gaps

Current tests (`TimeFormatterTests`, `VideoEngineTests`) are purposeful but minimal.

| **Untested Critical Path** | **Recommendation**                                                        |
| -------------------------- | ------------------------------------------------------------------------- |
| **Export Lifecycle**        | Bundle a tiny MP4 fixture; add an integration test for success/fail/cancel. |
| **Thumbnail Ordering**     | Test with rapid file switching to ensure correct delivery.                |
| **Timeline Constraints**   | Extract drag-handle logic to a ViewModel for unit testing.                |
| **Security Lifecycle**     | At minimum, document manual test steps for resource access.               |

### Phase 2: Should Fix (Next Iteration)

4. Refactor: Extract `EditorViewModel` from `ContentView`.
5. Add thumbnail generation cancellation.
6. Implement one fixture-based export integration test.
7. Preflight export compatibility using `AVAssetExportSession.exportPresets(compatibleWith:)`.

### Phase 3: Nice to Have

8. Apply `preferredTransform` to `naturalSize` for rotated videos.
9. Update format picker UX to show "Same as source" during passthrough.

## Codex Report

### Open Findings (Ordered by Severity)

**[P0] Potential user data loss on failed export path cleanup**
Unconditional cleanup deletes whatever is at the chosen output path on failure/cancel, which can remove pre-existing user files if they selected an existing filename.
File: `VideoEngine.swift:69` and `VideoEngine.swift:87`

**[P1] Timeline drag math likely incorrect for handle gestures**
`DragGesture` uses `value.location.x` from the handle's local gesture context, then divides by full timeline width. That usually produces wrong/unstable trim movement rather than true timeline-relative dragging.
File: `TimelineView.swift:120`

**[P1] Passthrough + fixed output type can fail for valid sources**
In passthrough, format picker is disabled, but export still uses `trimState.exportFormat.fileType` (default MP4), which can be incompatible with source/container combinations. No compatibility preflight with `supportedFileTypes`.
Files: `ExportSheet.swift:58`, `VideoEngine.swift:35`

**[P2] Concurrency warning in thumbnail generation (Sendable capture)**
Build emits a Sendable warning for captured `[NSValue]` in async callback closure. This can become stricter with compiler/language mode upgrades.
File: `ThumbnailGenerator.swift:37`

**[P2] Load race when opening files quickly**
`loadVideo` launches async work without cancellation/identity checks; an earlier task can finish after a later one and overwrite state with stale doc/player/thumbnails.
File: `ContentView.swift:207`

### Resolved Findings

**[P1] MVP verification claims trim-restricted playback, but implementation doesn't enforce it**
*Fixed in commit `17c3551`* — time observer now clamps playback at endTime and loops to startTime.
Files: `mvp-plan.md:129`, `ContentView.swift:267`

**@MainActor Missing on VideoEngine**
*Fixed in commit `6361195`* — `VideoEngine` annotated as `@MainActor`; progress polling no longer uses `DispatchQueue.main.async` wrappers.
File: `VideoEngine.swift`

### What's Good

- Clear MVP scope and architecture; docs and code structure align well overall. Files: `README.md`, `mvp-plan.md`
- Good use of `@Observable` and separation of concerns (`VideoDocument`, `VideoEngine`, `ThumbnailGenerator`).
- Sensible handling for invalid/indefinite times and trim sanitization in state model. File: `TrimState.swift`
- Export UX has practical touches (estimated size, progress, cancel, reveal in Finder). File: `ExportSheet.swift`
- Test coverage for formatter/math/state edge cases is solid for an MVP baseline, and `swift test` passes (35/35).

### Areas To Improve Next

- Make export cleanup safe: only delete files created during this export attempt.
- Fix timeline drag coordinate mapping to timeline/global space.
- Add export compatibility preflight (`supportedFileTypes`) and passthrough container logic.
- Add async load cancellation/tokening to avoid stale UI state races.
- Resolve Sendable warning in thumbnail pipeline before stricter compiler modes.
