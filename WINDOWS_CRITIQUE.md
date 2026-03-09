# VidPare — Windows Native Plan Critique

Review of `WINDOWS_NATIVE_PLAN.md` identifying issues, risks, and corrections.

---

## What the plan gets right

- **Technology mapping is sound** — Swift → C# / AVFoundation → Media Foundation / SwiftUI → WinUI 3 equivalences are correct at a high level
- **MOV output limitation is honestly called out** — good to flag early rather than discover mid-implementation
- **Project structure mirrors the macOS tree** — makes cross-referencing straightforward during development
- **Windows-exclusive features section is excellent** — taskbar progress, jump lists, and toast notifications are genuine wins that justify the port
- **Phase-based roadmap** — models-first, services-second, UI-third is the right order

---

## Issue 1: Media Foundation complexity is severely underestimated

The plan shows `IMFSourceReader → IMFSinkWriter` passthrough as a ~30-line read loop. In practice:

### No maintained C# Media Foundation wrapper exists

- `MediaFoundation.NET` — abandoned (~2015), no NuGet, targets .NET Framework
- `SharpDX.MediaFoundation` — archived (2019), no longer maintained, no .NET 8 support
- Raw COM interop via `[ComImport]` or CsWin32-generated bindings is the only option — this means hundreds of lines of boilerplate for lifetime management, `HRESULT` error handling, and `IMFMediaBuffer` pin/unpin cycles
- CsWin32 (Microsoft's P/Invoke source generator) can generate the bindings but the developer still owns all the COM reference counting and error handling

### Passthrough remux is not a simple copy loop

The plan's sample code skips over:

- **B-frame reordering** — DTS and PTS are not monotonically increasing; naive timestamp filtering drops frames
- **DTS/PTS discontinuities** — timestamp adjustment after trim must account for decode-order vs presentation-order gaps
- **Keyframe-accurate seeking** — `IMFSourceReader.SetCurrentPosition` seeks to the nearest keyframe *before* the requested time; the loop must discard pre-roll samples
- **Audio/video stream synchronization** — audio and video streams have different sample rates and boundaries; trimming at a video keyframe may leave audio samples straddling the cut point
- **MP4 atom/moov preservation** — metadata atoms (`udta`, `moov` layout) may not be preserved by a raw sample copy; some players depend on atom ordering
- **Edit list handling** — MP4 files with `elst` atoms require special handling during remux

`AVAssetExportSession` on macOS handles all of these silently. The Windows equivalent requires implementing each concern explicitly.

---

## Issue 2: Native AOT claim is incorrect

The plan suggests:

```powershell
dotnet publish -r win-x64 -c Release -p:PublishAot=true
# Output: ~15-25 MB, sub-100ms startup
```

**WinUI 3 does not support Native AOT.** WinUI 3 relies on:

- COM interop (`IUnknown`, `IActivationFactory`)
- Runtime reflection for XAML resource loading
- Dynamic type resolution for data binding

All of these are incompatible with AOT compilation. The self-contained single-file publish (~70-90 MB) is the realistic ceiling. The Native AOT section should be removed from the plan to avoid setting incorrect expectations.

**ReadyToRun (R2R)** is a viable middle ground — partial AOT that works with WinUI 3 and improves startup time modestly:

```powershell
dotnet publish -r win-x64 -c Release -p:PublishReadyToRun=true -p:PublishSingleFile=true --self-contained
```

---

## Issue 3: `Windows.Media.Transcoding` API is ignored

The plan jumps straight to low-level `IMFTranscoder` / `IMFSourceReader` P/Invoke for the re-encode path. The higher-level `Windows.Media.Transcoding.MediaTranscoder` WinRT API is the actual Windows equivalent of `AVAssetExportSession`:

```csharp
var transcoder = new MediaTranscoder();
transcoder.TrimStartTime = trimStart;
transcoder.TrimStopTime = trimEnd;

var profile = MediaEncodingProfile.CreateMp4(VideoEncodingQuality.HD1080p);
var result = await transcoder.PrepareFileTranscodeAsync(source, destination, profile);

if (result.CanTranscode)
{
    var progress = new Progress<double>(p => Progress = p);
    await result.TranscodeAsync().AsTask(ct, progress);
}
```

This provides:

- Built-in trim range support
- Progress callbacks
- Hardware acceleration (same MFT selection as raw MF)
- Proper error handling without COM boilerplate
- Works with `StorageFile` (WinRT file access)

**Recommendation**: Use `MediaTranscoder` for all re-encode presets (High/Medium/Low). Only drop to `IMFSourceReader/SinkWriter` for passthrough remux where the higher-level API lacks a passthrough mode.

---

## Issue 4: Code samples mix WinRT and COM API layers

The plan interleaves two distinct API surfaces:

| API | Layer | Lifetime model | Threading |
|---|---|---|---|
| `MediaClip.CreateFromFileAsync` | WinRT (`Windows.Media.Editing`) | Reference-counted via C#/WinRT projection | STA/MTA aware |
| `IMFSourceReader` | COM (Media Foundation) | Manual `Release()` / `using` via COM wrappers | Must marshal to MTA |

These have different:

- **Lifetime semantics** — WinRT objects are prevented via C#/WinRT; COM objects need explicit `Marshal.ReleaseComObject` or disposable wrappers
- **Error handling** — WinRT throws managed exceptions; COM returns `HRESULT` that must be checked
- **Threading models** — WinRT respects `SynchronizationContext`; raw MF COM calls may require explicit thread marshaling

The plan should clearly separate which components use which API layer, and avoid mixing them within the same method.

---

## Issue 5: Missing abstraction layer

The macOS codebase has no abstraction between business logic and `AVFoundation` — acceptable for a single-platform app where every file imports `AVFoundation`.

The Windows plan copies this pattern: models directly reference `IMFSourceReader`, views directly use `MediaPlayerElement`. This creates two problems:

1. **No code can be compiled or tested without Windows SDK** — even pure business logic files import Windows types
2. **No separation between testable logic and platform integration** — makes unit testing the export state machine, capability resolution, and progress reporting unnecessarily difficult

The plan should define a `VidPare.Core` class library targeting `net8.0` (platform-neutral) containing all models, business logic, and service interfaces. See `LINUX_CODING.md` for the recommended split.

---

## Issue 6: HEVC codec availability is worse than described

The plan states HEVC Video Extensions are "free" on Windows 10. This is not accurate as of 2024:

- **Microsoft Store "HEVC Video Extensions"** — costs $0.99 USD
- **"HEVC Video Extensions from Device Manufacturer"** — free, but only pre-installed by OEMs on new hardware; cannot be installed manually from the Store
- **Windows 11** — HEVC decode/encode is bundled at no cost

The app's "gracefully degrade" messaging should account for the paid codec scenario on Windows 10. Consider linking users to the Store page or detecting the OEM version specifically.

---

## Issue 7: No CI/CD story

The macOS version has pre-commit hooks, `swift test`, and `swift build` in CI. The plan mentions `.pre-commit-config.yaml` with `dotnet format`/`dotnet build`/`dotnet test` but says nothing about:

- **GitHub Actions runners** — WinUI 3 builds require `windows-latest` with Windows SDK installed; these runners cost 2x Linux runner minutes
- **Test execution in CI** — WinUI 3 app tests need a desktop session; headless CI runners may not support `MediaPlayerElement` rendering
- **Build matrix** — `VidPare.Core` tests should run on `ubuntu-latest` (cheap, fast); `VidPare.App` tests on `windows-latest` (expensive, slower)
- **Artifact publishing** — `dotnet publish` output needs to be stored/deployed somewhere

---

## Issue 8: Window sizing API is incomplete

The plan shows:

```csharp
AppWindow.Resize(new SizeInt32(960, 640));
```

In WinUI 3, getting the `AppWindow` from a `Window` requires:

```csharp
var hwnd = WindowNative.GetWindowHandle(window);
var windowId = Win32Interop.GetWindowIdFromWindow(hwnd);
var appWindow = AppWindow.GetFromWindowId(windowId);
appWindow.Resize(new SizeInt32(960, 640));
```

This is a minor point but illustrative of WinUI 3's rougher API surface compared to SwiftUI's `WindowGroup` — many "simple" operations require Win32 interop boilerplate that the plan doesn't account for.

---

## Issue 9: FileSavePicker requires window handle initialization

The plan shows a clean `FileSavePicker` usage:

```csharp
var picker = new FileSavePicker();
var file = await picker.PickSaveFileAsync();
```

In WinUI 3 (non-UWP), pickers must be initialized with the window handle:

```csharp
var picker = new FileSavePicker();
var hwnd = WindowNative.GetWindowHandle(App.MainWindow);
InitializeWithWindow.Initialize(picker, hwnd);
var file = await picker.PickSaveFileAsync();
```

Without this, the picker throws `COMException`. This pattern applies to all WinUI 3 pickers and dialogs — it's a recurring source of developer friction that the plan should acknowledge.

---

## Issue 10: Drag-and-drop implementation gap

The plan mentions `ContentView` as a "drop target" but provides no implementation detail. WinUI 3 drag-and-drop for files requires:

- Setting `AllowDrop="True"` and `CanDrag="False"` on the target element
- Handling `DragOver` to check `DataPackage` for `StorageItems`
- Handling `Drop` to extract `IReadOnlyList<IStorageItem>`
- Converting `IStorageItem` to `StorageFile` for video loading

The macOS version uses SwiftUI's `.onDrop(of:)` modifier which handles UTType filtering automatically. The WinUI 3 equivalent requires manual type checking and is more verbose.

---

## Summary of recommended changes to the plan

| # | Issue | Action |
|---|---|---|
| 1 | MF complexity underestimated | Add a "Media Foundation risks" section; budget 3-4x the estimated effort for passthrough |
| 2 | Native AOT incorrect | Remove the AOT section; replace with ReadyToRun |
| 3 | MediaTranscoder ignored | Use `Windows.Media.Transcoding` for re-encode; document when to drop to raw MF |
| 4 | Mixed API layers | Separate WinRT and COM usage into distinct service classes |
| 5 | No abstraction layer | Add `VidPare.Core` / `VidPare.App` project split |
| 6 | HEVC cost | Correct the "free" claim; add Store link fallback |
| 7 | No CI/CD | Add GitHub Actions workflow with split Linux/Windows runners |
| 8-10 | WinUI 3 boilerplate | Acknowledge Win32 interop friction in API mappings |
