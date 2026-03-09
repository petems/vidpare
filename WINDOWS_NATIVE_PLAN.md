# VidPare — Windows Native Conversion Plan

A 1:1 port using Windows-native APIs only. No ffmpeg. Single `.exe` at the end.

---

## Technology Stack

| macOS | Windows Equivalent |
|---|---|
| Swift 5.9+ | C# 12 / .NET 8 |
| SwiftUI + `@Observable` | WinUI 3 (Windows App SDK 1.5+) + CommunityToolkit.Mvvm |
| AVFoundation | Windows Media Foundation (MF) |
| AVPlayer + AVPlayerLayer | `Windows.Media.Playback.MediaPlayer` + `MediaPlayerElement` |
| AVAsset / AVURLAsset | `StorageFile` + `MediaSource` + `IMFSourceReader` |
| AVAssetExportSession | `IMFTranscoder` / custom `IMFSourceReader → IMFSinkWriter` pipeline |
| AVAssetImageGenerator | `IMFSourceReader` with frame seeking |
| NSImage | `SoftwareBitmap` → `BitmapImage` |
| CMTime | `TimeSpan` |
| CMTimeRange | Custom `TrimRange(Start: TimeSpan, End: TimeSpan)` record |
| NSSavePanel / NSOpenPanel | `FileSavePicker` / `FileOpenPicker` (WinUI 3) |
| NSViewRepresentable | Not needed — `MediaPlayerElement` is native XAML |
| Swift Package Manager | .NET SDK (`dotnet build`, `.csproj`) |
| Makefile | `Makefile` or PowerShell task runner |
| XCTest | xUnit / NUnit |
| swift-snapshot-testing | WinAppDriver + screenshot comparison (no direct equivalent) |
| AXAutomation (AX API) | Windows UIAutomation API (`FlaUI` or `WinAppDriver`) |
| Notarization + DMG | Authenticode signing + MSIX or single `.exe` |

---

## Project Structure

Direct 1:1 mapping of the existing source tree:

```
VidPareWin/
├── VidPare.csproj
├── App.xaml / App.xaml.cs           # @main entry + NSApplicationDelegateAdaptor
├── MainWindow.xaml / .cs            # WindowGroup (960×640 default)
├── Models/
│   ├── VideoDocument.cs             # StorageFile + IMFSourceReader metadata
│   ├── TrimState.cs                 # [ObservableProperty] (CommunityToolkit.Mvvm)
│   └── ExportCapabilities.cs        # Format/quality support matrix
├── Views/
│   ├── ContentView.xaml / .cs       # Drop target + editor layout
│   ├── VideoPlayerView.xaml / .cs   # MediaPlayerElement
│   ├── TimelineView.xaml / .cs      # Canvas thumbnail strip + trim handles
│   ├── PlayerControlsView.xaml/.cs  # Play/pause, in/out, time display
│   └── ExportDialog.xaml / .cs      # Sheet with format/quality pickers
├── Services/
│   ├── VideoEngine.cs               # IMFTranscoder / IMFSinkWriter export
│   └── ThumbnailGenerator.cs        # IMFSourceReader frame extraction
├── Utilities/
│   ├── TimeFormatter.cs             # TimeSpan → "MM:SS.ff" etc.
│   └── AccessibilityIds.cs          # AutomationId string constants
├── AXAutomation/                    # UIAutomation-based helpers (FlaUI)
└── DemoRecorder/                    # Windows.Graphics.Capture CLI tool

Tests/VidPareTests/
├── VideoEngineTests.cs
├── VideoDocumentTests.cs
├── TimelineViewTests.cs
├── TimeFormatterTests.cs
└── SnapshotTests.cs                 # WinAppDriver screenshot comparison

Tests/VidPareAcceptanceTests/
└── AcceptanceTests.cs               # FlaUI + WinAppDriver end-to-end
```

---

## Component-by-Component Conversion

### 1. Entry Point / App Shell

**macOS**: `VidPareApp.swift` — `@main`, `WindowGroup`, `@NSApplicationDelegateAdaptor`

**Windows**:
```csharp
// App.xaml.cs
public partial class App : Application
{
    protected override void OnLaunched(LaunchActivatedEventArgs args)
    {
        var window = new MainWindow();
        window.Activate();
    }
}
```
- `VIDPARE_OPEN_FILE` env var: read via `Environment.GetEnvironmentVariable()` — identical behavior
- Default window size: `AppWindow.Resize(new SizeInt32(960, 640))`
- Title bar: `ExtendsContentIntoTitleBar = true` for a similar borderless feel

---

### 2. VideoDocument (Model)

**macOS**: Wraps `AVURLAsset`, loads codec/duration/size via async `loadValues(forKeys:)`.

**Windows**:
```csharp
[ObservableObject]
public partial class VideoDocument
{
    [ObservableProperty] private TimeSpan duration;
    [ObservableProperty] private SizeInt32 naturalSize;
    [ObservableProperty] private string codecName = "";
    [ObservableProperty] private long fileSize;

    public async Task LoadMetadataAsync(StorageFile file)
    {
        // Basic metadata via MediaClip
        var clip = await MediaClip.CreateFromFileAsync(file);
        Duration = clip.OriginalDuration;

        // Detailed codec info via P/Invoke to IMFSourceReader
        using var reader = new MFSourceReader(file.Path);
        NaturalSize = reader.GetVideoSize();
        CodecName   = reader.GetCodecFriendlyName(); // MF_MT_SUBTYPE GUID → "H.264", "HEVC"
        FileSize    = (await file.GetBasicPropertiesAsync()).Size;
    }

    public static bool CanOpen(StorageFile file) =>
        file.FileType.ToLower() is ".mp4" or ".mov" or ".m4v";
}
```

For `IMFSourceReader` codec detection: query `MF_MT_SUBTYPE` on the first video stream — `MFVideoFormat_H264`, `MFVideoFormat_HEVC`, `MFVideoFormat_MP4V`.

**MOV caveat**: Windows Media Foundation reads MOV/MP4 containers via the same MPEG-4 source, so reading MOV works. Writing MOV from MF is not natively supported (see Limitations section).

---

### 3. TrimState (Model)

**macOS**: `@Observable`, `CMTime` boundaries, `ExportFormat`/`QualityPreset` enums.

**Windows** — drop-in equivalent with `CommunityToolkit.Mvvm`:
```csharp
[ObservableObject]
public partial class TrimState
{
    [ObservableProperty] private TimeSpan startTime;
    [ObservableProperty] private TimeSpan endTime;
    [ObservableProperty] private ExportFormat exportFormat;
    [ObservableProperty] private QualityPreset qualityPreset;

    public TimeSpan Duration => EndTime - StartTime;
    public TrimRange TrimRange => new(StartTime, EndTime);

    public void Reset(TimeSpan videoDuration)
    {
        StartTime = TimeSpan.Zero;
        EndTime   = videoDuration;
    }
}

public enum ExportFormat { MP4H264, MP4HEVC }  // MOV dropped (see Limitations)
public enum QualityPreset { Passthrough, High, Medium, Low }
```

`CMTime` → `TimeSpan` throughout. `TimeSpan` uses 100-nanosecond ticks — sufficient precision for video editing.

---

### 4. ExportCapabilities (Model)

Logic is pure business logic with no platform APIs — translates 1:1.

Only difference: capability detection calls `MFTranscodeGetOutputAvailableTypes()` instead of `AVAssetExportSession.allExportPresets()` to check which formats/encoders are available on the machine.

HEVC encode availability: check if `MFVideoFormat_HEVC` encoder MFT is registered:
```csharp
bool HevcEncodeAvailable() =>
    MFTEnumEx(MFT_CATEGORY_VIDEO_ENCODER, MFVideoFormat_HEVC).Any();
```

---

### 5. VideoPlayerView

**macOS**: `NSViewRepresentable` wrapping `AVPlayerLayer` in a bare `NSView`.

**Windows**: Not needed — `MediaPlayerElement` is a native XAML control:
```xaml
<MediaPlayerElement x:Name="playerElement"
                    AreTransportControlsEnabled="False"
                    Stretch="Uniform" />
```
```csharp
// Attach player
playerElement.SetMediaPlayer(_mediaPlayer);
_mediaPlayer.Source = MediaSource.CreateFromStorageFile(file);
```

This is actually simpler than the macOS approach.

---

### 6. TimelineView

**macOS**: SwiftUI `Canvas`/`GeometryReader` with `DragGesture` for trim handles. Dimmed overlays drawn with colored rectangles.

**Windows**: WinUI 3 `Canvas` with `PointerPressed`/`PointerMoved`/`PointerReleased` events:
```xaml
<Canvas x:Name="timelineCanvas"
        PointerPressed="Timeline_PointerPressed"
        PointerMoved="Timeline_PointerMoved"
        PointerReleased="Timeline_PointerReleased">
    <!-- Thumbnail images positioned by code-behind -->
    <!-- Dim overlays as Rectangle elements -->
    <!-- Trim handles as styled Rectangle/Path elements -->
    <!-- Playhead as a thin vertical Line -->
</Canvas>
```

Coordinate math (`xPosition(for:totalSeconds:in:)` etc.) translates 1:1 — pure arithmetic, no platform API.

Thumbnails: `Image` elements with `SoftwareBitmapSource` sources loaded from `ThumbnailGenerator`.

---

### 7. PlayerControlsView

No platform-specific APIs — layout and bindings translate directly:

- `Button` (play/pause, in/out point)
- `TextBlock` with monospaced font for time display
- `AutomationProperties.AutomationId` replaces `.accessibilityIdentifier()` for test targeting

---

### 8. ExportSheet / ExportDialog

**macOS**: SwiftUI sheet with `NSSavePanel`.

**Windows**: `ContentDialog` (modal overlay) + `FileSavePicker`:
```csharp
var picker = new FileSavePicker();
picker.SuggestedStartLocation = PickerLocationId.VideosLibrary;
picker.FileTypeChoices.Add("MP4 Video", new List<string> { ".mp4" });
picker.SuggestedFileName = suggestedName;
var file = await picker.PickSaveFileAsync();
```

Progress display, format/quality pickers, completion view: all pure UI — translate 1:1 conceptually.

"Reveal in Finder" → "Show in Explorer":
```csharp
Process.Start("explorer.exe", $"/select,\"{outputPath}\"");
```

Success sound (`AudioServicesPlaySystemSound`) → `SystemSounds.Asterisk.Play()` or `MediaPlayer.Play()` with a bundled sound resource.

---

### 9. VideoEngine (Service) — Most Complex Component

This is the heart of the port. Full breakdown:

#### 9a. Passthrough Remux (lossless trim, no re-encode)

AVFoundation: `AVAssetExportSession` with `AVAssetExportPresetPassthrough` does a bit-perfect copy trimmed to keyframe boundaries. Media Foundation equivalent uses a raw sample copy pipeline:

```
IMFSourceReader (input file)
    ↓  [no decode MFT — raw compressed samples]
IMFSinkWriter (output file)
    ↓  [IMFSinkWriter in passthrough mode: SetInputMediaType matches output]
MP4 container
```

```csharp
// Passthrough remux: read raw samples, write to sink
using var reader = MFCreateSourceReaderFromURL(inputPath);
using var writer = MFCreateSinkWriterFromURL(outputPath);

// Copy media types (no transcode)
var videoType = reader.GetCurrentMediaType(MF_SOURCE_READER_FIRST_VIDEO_STREAM);
var audioType = reader.GetCurrentMediaType(MF_SOURCE_READER_FIRST_AUDIO_STREAM);
int videoStream = writer.AddStream(videoType);
int audioStream = writer.AddStream(audioType);
writer.SetInputMediaType(videoStream, videoType, encodingParameters: null);
writer.SetInputMediaType(audioStream, audioType, encodingParameters: null);

writer.BeginWriting();

while (true)
{
    var (sample, flags, timestamp, streamIndex) = reader.ReadSample(...);
    if (flags.HasFlag(MF_SOURCE_READERF_ENDOFSTREAM)) break;

    // Trim range filter
    if (timestamp < trimStart) { sample.Dispose(); continue; }
    if (timestamp > trimEnd)   { sample.Dispose(); break; }

    // Adjust timestamps to start from zero
    sample.SetSampleTime(timestamp - trimStart);
    writer.WriteSample(streamIndex == videoStreamIndex ? videoStream : audioStream, sample);
}

writer.Finalize();
```

**Keyframe snapping**: When seeking in `IMFSourceReader`, pass `MFBYPASS_TRANSFORM_FLAG` or use `MF_SOURCE_READER_MEDIASOURCE` with `MFPKEY_SOURCEREADER_DISCONNECT_MEDIASOURCE` to seek to nearest prior keyframe. The `MF_SOURCE_READERF_CURRENTMEDIATYPECHANGED` flag indicates IDR/keyframe. This replicates AVAssetExportSession's passthrough keyframe-snap behavior.

#### 9b. Re-encode (High/Medium/Low)

Use `IMFTranscoder` — the higher-level API:
```csharp
var transcoder = new MFTranscoder();
var profile = MFCreateTranscodeProfile();

// Set video encoding attributes
profile.SetVideoAttributes(new Dictionary<Guid, object>
{
    [MF_MT_SUBTYPE]              = format == ExportFormat.MP4HEVC
                                    ? MFVideoFormat_HEVC : MFVideoFormat_H264,
    [MF_MT_AVG_BITRATE]          = bitrate,
    [MF_MT_MPEG2_PROFILE]        = eAVEncH264VProfile_Main,
    [MF_MT_INTERLACE_MODE]       = MFVideoInterlace_Progressive,
});
profile.SetAudioAttributes(...);
profile.SetContainerAttributes(new() { [MF_TRANSCODE_CONTAINERTYPE] = MFTranscodeContainerType_MPEG4 });

var topology = await transcoder.GetPartialTopologyAsync(mediaSource, profile);
var session  = await MFCreateMediaSession(null);
session.SetTopology(0, topology);
session.Start(Guid.Empty, new PropVariant(trimStart));
```

Hardware acceleration is automatic via Media Foundation's MFT selection — Intel Quick Sync, NVIDIA NVENC, AMD VCE are all picked up when available, same as VideoToolbox on macOS.

#### 9c. Progress Polling

`AVAssetExportSession.progress` is unreliable on macOS so a 0.5s timer is used. On Windows, `IMFMediaSession` fires `MESessionProgress` events, but polling `IMFTranscoder` progress is similarly inconsistent. Use the same 0.5s timer pattern:
```csharp
// IMFMediaSession clock position / total duration
var clock = session.GetClock() as IMFPresentationClock;
var position = clock.GetTime();
Progress = (double)position.Ticks / trimDuration.Ticks;
```

#### 9d. Atomic File Replacement

`FileManager.replaceItemAt()` → `File.Replace(tempPath, finalPath, backupPath)` — identical semantics.

Temp file naming: `.vidpare-{Guid}-{filename}` — keep as-is.

---

### 10. ThumbnailGenerator (Service)

**macOS**: `AVAssetImageGenerator.generateCGImagesAsynchronously()` with `appliesPreferredTrackTransform = true`.

**Windows**: `IMFSourceReader` with `MF_SOURCE_READER_ENABLE_ADVANCED_VIDEO_PROCESSING` attribute (handles rotation via video processing MFT):
```csharp
public async Task<List<BitmapImage>> GenerateThumbnailsAsync(
    string filePath, int count, CancellationToken ct)
{
    using var attributes = MFCreateAttributes(1);
    attributes.SetUINT32(MF_SOURCE_READER_ENABLE_ADVANCED_VIDEO_PROCESSING, 1); // rotation fix

    using var reader = MFCreateSourceReaderFromURL(filePath, attributes);
    // Set output format to RGB32 for easy bitmap conversion
    reader.SetCurrentMediaType(MF_SOURCE_READER_FIRST_VIDEO_STREAM, MFMediaType_Video_RGB32);

    var results = new List<BitmapImage>();
    var timestamps = DistributeEvenly(duration, count); // same heuristic as Swift

    foreach (var ts in timestamps)
    {
        reader.SetCurrentPosition(ts);
        var (sample, ...) = reader.ReadSample(MF_SOURCE_READER_FIRST_VIDEO_STREAM, ...);
        var bitmap = SampleToBitmapImage(sample); // IMFSample → SoftwareBitmap → BitmapImage
        results.Add(bitmap);
    }
    return results;
}
```

`appliesPreferredTrackTransform = true` equivalent: `MF_SOURCE_READER_ENABLE_ADVANCED_VIDEO_PROCESSING` enables the Video Processor MFT which handles `MF_MT_VIDEO_ROTATION` automatically.

---

### 11. TimeFormatter (Utility)

Pure string formatting — translates 1:1. `CMTime.seconds` → `TimeSpan.TotalSeconds`. Zero platform APIs.

---

### 12. AXAutomation / DemoRecorder

**macOS AXAutomation**: Carbon AX API (`AXUIElementRef`, `AXCopyAttributeValue`).

**Windows AXAutomation**: `FlaUI` library (wrapper over Windows UIAutomation COM API):
```csharp
using FlaUI.Core;
using FlaUI.UIA3;

var app   = Application.Launch("VidPare.exe");
var auto  = new UIA3Automation();
var win   = app.GetMainWindow(auto);
var btn   = win.FindFirstDescendant(cf => cf.ByAutomationId("playPauseButton"));
btn.AsButton().Invoke();
```

Mouse simulation → `FlaUI.Core.Input.Mouse.MoveTo()` / `Click()`.
Keyboard simulation → `FlaUI.Core.Input.Keyboard.Type()`.

**DemoRecorder**: `Windows.Graphics.Capture` API for zero-copy window recording:
```csharp
var item    = GraphicsCaptureItem.CreateFromWindowId(windowId);
var session = Direct3D11CaptureFramePool.Create(device, pixelFormat, frameCount, item.Size);
session.FrameArrived += (pool, _) =>
{
    using var frame = pool.TryGetNextFrame();
    // Write frame.Surface (IDXGISurface) to video via IMFSinkWriter
};
session.StartCapture();
```

This is actually more capable than the macOS approach — `Windows.Graphics.Capture` has lower latency and better HDR support.

---

### 13. Build, Packaging & Delivery

**.csproj**:
```xml
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <OutputType>WinExe</OutputType>
    <TargetFramework>net8.0-windows10.0.22000.0</TargetFramework>
    <UseWinUI>true</UseWinUI>
    <Nullable>enable</Nullable>
    <ImplicitUsings>enable</ImplicitUsings>
  </PropertyGroup>
  <ItemGroup>
    <PackageReference Include="Microsoft.WindowsAppSDK"      Version="1.5.*" />
    <PackageReference Include="CommunityToolkit.Mvvm"        Version="8.*"  />
    <PackageReference Include="CommunityToolkit.WinUI"       Version="7.*"  />
    <!-- For tests only: -->
    <PackageReference Include="FlaUI.UIA3"                   Version="4.*"  />
    <PackageReference Include="xunit"                        Version="2.*"  />
  </ItemGroup>
</Project>
```

**Single `.exe` publish**:
```powershell
dotnet publish -r win-x64 `
  -c Release `
  --self-contained true `
  -p:PublishSingleFile=true `
  -p:IncludeNativeLibrariesForSelfExtract=true
# Output: publish/VidPare.exe (~70-90 MB with .NET runtime)
```

**Smaller binary with Native AOT** (no JIT, faster startup):
```powershell
dotnet publish -r win-x64 -c Release -p:PublishAot=true
# Output: ~15-25 MB, sub-100ms startup
# Trade-off: no reflection, stricter trimming, longer build time
```

**MSIX package** (optional, for Store or clean install/uninstall):
```powershell
dotnet publish ... && makeappx pack /d publish/ /p VidPare.msix
signtool sign /fd SHA256 /a VidPare.msix
```

**Minimum Windows version**: Windows 10 2004 (build 19041) for WinUI 3 + Windows Media Foundation features used. Windows 11 recommended for HEVC hardware encode without codec pack.

---

## What Would NOT Be Possible

### 1. MOV Output
`IMFSinkWriter` and `IMFTranscoder` only write MPEG-4 containers (`.mp4`, `.m4v`). There is no native Windows MF sink for QuickTime MOV. **The MOV export format must be dropped.** Output options would be MP4 H.264 and MP4 HEVC only (unless a third-party container library is used, which breaks the native-only requirement).

### 2. HEVC Playback and Encode Without Codec Pack
On Windows 10, HEVC decode/encode requires the **HEVC Video Extensions** from the Microsoft Store (free). On Windows 11, it is pre-installed. An app cannot bundle the HEVC codec; the installer must handle this or gracefully degrade. The app should detect availability via `MFTEnumEx(MFT_CATEGORY_VIDEO_ENCODER, MFVideoFormat_HEVC)` and show a warning if missing.

### 3. Bit-Perfect Passthrough Quality Guarantee
Apple's `AVAssetExportSession` passthrough uses a highly optimized, containerized pipeline with guarantees about sample integrity. The `IMFSourceReader → IMFSinkWriter` passthrough approach described above achieves the same goal but lacks Apple's explicit guarantee. In practice it is lossless for well-formed MP4 inputs, but edge cases (malformed pts/dts, B-frame reorder buffers, non-standard atoms) may behave differently.

### 4. ProRes Codec
ProRes is an Apple proprietary codec. There is no Windows Media Foundation MFT for ProRes encode or decode. Not relevant to VidPare's current feature set, but rules out any future ProRes export path.

### 5. Hardware-Accelerated Thumbnail Extraction on All GPUs
`AVAssetImageGenerator` uses VideoToolbox which is Metal-accelerated on all Apple Silicon. On Windows, `IMFSourceReader` frame extraction uses software decode by default unless explicitly using DXVA2/D3D11VA. Adding hardware-accelerated decode for thumbnails requires more plumbing and is GPU-vendor-specific.

### 6. Snapshot Testing Parity
`swift-snapshot-testing` is a mature, well-integrated SwiftUI snapshot library. No equivalent exists for WinUI 3. Alternatives (WinAppDriver screenshots, Playwright, custom rendering comparisons) work but require significantly more test infrastructure and are less reliable due to font rendering differences across machines.

### 7. `@Observable` Macro Ergonomics
Swift's `@Observable` macro generates extremely clean code with fine-grained dependency tracking. `CommunityToolkit.Mvvm`'s `[ObservableProperty]` is the closest equivalent but requires more boilerplate and uses coarser change notification (`INotifyPropertyChanged`).

### 8. Native Drag-and-Drop File Reveal
"Reveal in Finder" via `NSWorkspace.selectFile()` provides a polished animation. `Process.Start("explorer.exe", "/select,path")` works on Windows but uses a separate Explorer window, which is less refined.

### 9. macOS Keychain Integration
macOS Keychain for secrets storage has no direct Windows equivalent (Windows Credential Manager is different in API shape). Affects future features, not current ones.

### 10. Universal Binary (arm64 + x86_64 in one file)
`make build-universal` builds a fat binary via `lipo`. .NET publishes per-RID: `win-x64` and `win-arm64` must be separate builds. The Windows App SDK 1.5 supports arm64 natively, so both architectures are fully supported — just separate binaries.

---

## Windows-Exclusive Features (Not Possible on macOS)

### 1. Taskbar Export Progress
`ITaskbarList3::SetProgressValue` shows the export percentage directly in the taskbar button's thumbnail overlay — visible without switching to the app window.
```csharp
[ComImport, Guid("ea1afb91-9e28-4b86-90e9-9e9f8a5eefaf")]
interface ITaskbarList3 { ... }
// During export:
taskbar.SetProgressValue(hwnd, (ulong)(progress * 100), 100);
taskbar.SetProgressState(hwnd, TBPF_NORMAL);
```

### 2. Jump Lists (Recent Files in Taskbar)
Right-click the taskbar icon → "Recent" list of trimmed videos:
```csharp
var jumpList = await JumpList.LoadCurrentAsync();
jumpList.Items.Add(JumpListItem.CreateWithArguments(filePath, "Recent"));
await jumpList.SaveAsync();
```

### 3. Windows Toast Notifications
Export completion notification visible even when the app is minimized or not focused:
```csharp
var toast = new ToastNotificationBuilder()
    .AddText("Export complete")
    .AddText(outputFileName)
    .AddButton("Show in Explorer", ToastActivationType.Foreground, "reveal")
    .Build();
ToastNotificationManager.CreateToastNotifier().Show(toast);
```

### 4. File Association + Shell Context Menu
Register `.mp4`, `.mov`, `.m4v` handlers so double-clicking a video file opens VidPare, and right-click in Explorer shows "Trim with VidPare":
```
HKEY_CLASSES_ROOT\.mp4\OpenWithProgIds\VidPare.1
HKEY_CLASSES_ROOT\VidPare.1\shell\open\command = "VidPare.exe" "%1"
```
On macOS, LSFileQuarantineEnabled and Info.plist CFBundleDocumentTypes handle this, but app sandbox restrictions make "Open With" less flexible.

### 5. GPU Selection for Hardware Encode
Windows exposes multiple GPU adapters via `IDXGIFactory1::EnumAdapters`. A preferences panel could let users pick Intel/NVIDIA/AMD for encoding — useful on workstations with discrete + integrated GPUs.

### 6. Windows Hello / Biometric Lock (Future Feature)
Output folders or export destinations could be protected with Windows Hello (fingerprint/face):
```csharp
var result = await UserConsentVerifier.RequestVerificationAsync("Confirm export destination");
```

### 7. Per-Monitor V2 DPI Scaling
WinUI 3 handles `WM_DPICHANGED` per-monitor natively. The player and timeline automatically re-render at the correct physical pixel density across mixed-DPI multi-monitor setups — this is more mature on Windows than macOS.

### 8. Zero-Copy Window Capture for DemoRecorder
`Windows.Graphics.Capture` captures GPU surfaces without a CPU round-trip, enabling higher-framerate, lower-latency demo recording than the macOS approach using `AVFoundation` screen capture.

### 9. NTFS Alternate Data Streams (Niche)
Store trim metadata (in/out points) in an ADS alongside the video file without creating a sidecar file:
```
video.mp4:vidpare-trim.json
```

### 10. Microsoft Store Distribution + Auto-Update
MSIX packaging enables Store distribution with automatic updates and clean uninstall — no equivalent to this level of OS integration on macOS (Sparkle handles updates, DMG does not auto-update).

### 11. Windows Subsystem for Android / WSL2 Interop (Niche)
Not relevant to VidPare directly, but Windows allows deeper cross-environment scripting that could enable advanced batch processing workflows.

---

## macOS Features Lost in Conversion

| Feature | macOS | Windows Status |
|---|---|---|
| MOV output | ✅ | ❌ No native MF MOV sink |
| HEVC out-of-box | ✅ | ⚠️ Requires codec pack on Win 10 |
| ProRes encode | ✅ (M-series) | ❌ No Windows MFT |
| AirDrop export destination | ✅ | ❌ |
| Quick Look preview | ✅ | ❌ |
| Spotlight indexing of export metadata | ✅ | ❌ (Windows Search, different) |
| `@Observable` fine-grained reactivity | ✅ | ⚠️ Coarser with MVVM toolkit |
| Native swift-snapshot-testing | ✅ | ⚠️ WinAppDriver workaround |
| Universal binary (single fat .exe) | ✅ (lipo) | ❌ Separate win-x64 / win-arm64 |
| Notarization (Gatekeeper) | ✅ | N/A (Authenticode instead) |
| macOS Keychain | ✅ | ⚠️ Windows Credential Manager |
| DMG drag-install UX | ✅ | N/A (MSIX or direct EXE) |

---

## Pre-Commit Hooks (Windows Equivalent)

```yaml
# .pre-commit-config.yaml — Windows CI equivalent
repos:
  - repo: local
    hooks:
      - id: dotnet-format
        name: dotnet format
        entry: dotnet format --verify-no-changes
        language: system
        types: [csharp]
      - id: dotnet-build
        name: dotnet build
        entry: dotnet build -c Release
        language: system
        pass_filenames: false
      - id: dotnet-test
        name: dotnet test
        entry: dotnet test --filter "Category!=Acceptance"
        language: system
        pass_filenames: false
        stages: [push]
```

---

## Development Roadmap

| Phase | Scope | Notes |
|---|---|---|
| 1 | Models + Services (no UI) | `VideoDocument`, `TrimState`, `VideoEngine`, `ThumbnailGenerator`, `TimeFormatter`. All testable without UI. |
| 2 | Passthrough export pipeline | Core `IMFSourceReader → IMFSinkWriter` passthrough. Write unit tests first. |
| 3 | Re-encode presets | `IMFTranscoder` for High/Medium/Low. Add `ExportCapabilities` detection. |
| 4 | Basic WinUI 3 shell | `ContentView` with drop target, `MediaPlayerElement` playback, file open. |
| 5 | Timeline + controls | `TimelineView` canvas, trim handles, `PlayerControlsView`. Port coordinate math directly. |
| 6 | Export dialog | `ExportDialog` with format/quality pickers, progress, completion view. |
| 7 | Unit + snapshot tests | Port all unit tests. Add WinAppDriver snapshot baseline captures. |
| 8 | AXAutomation + DemoRecorder | FlaUI wrapper, `Windows.Graphics.Capture` recording. |
| 9 | Windows-exclusive features | Taskbar progress, jump lists, toast notifications, shell association. |
| 10 | Packaging + signing | `dotnet publish --self-contained`, Authenticode, optional MSIX. |

---

## Summary

A 1:1 port is feasible using C# / .NET 8 / WinUI 3 / Windows Media Foundation. The architecture maps cleanly: `@Observable` → `[ObservableProperty]`, `AVPlayer` → `MediaPlayer`, `AVAssetExportSession` → `IMFSourceReader/SinkWriter`. The passthrough remux pipeline (the core value proposition) is reproducible at the API level without ffmpeg.

The two meaningful losses are **MOV output** (no native Windows MF container sink) and **HEVC out-of-box** on Windows 10 without a codec pack. Both are solvable with user-facing messaging.

The Windows version gains significant OS integration improvements: **taskbar progress**, **jump lists**, **toast notifications**, and **shell context menu** — features that macOS app sandbox restrictions make harder or impossible to deliver.
