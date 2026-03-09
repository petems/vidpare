# VidPare — Linux-First Development Strategy

How to structure the Windows port so that business logic, models, and unit tests can be developed and tested on Linux (or macOS) using `dotnet` CLI, before a final build on a Windows machine.

---

## Principle

Split the solution into two projects:

- **`VidPare.Core`** — targets `net8.0` (platform-neutral). Contains all models, business logic, service interfaces, and utilities. Builds and tests on Linux, macOS, and Windows.
- **`VidPare.App`** — targets `net8.0-windows10.0.22000.0`. Contains WinUI 3 views, Media Foundation implementations, and Windows-specific integrations. Builds only on Windows.

This split means ~30-35% of the implementation work happens on Linux with fast iteration, and the remaining ~65-70% is done on a Windows machine.

---

## Solution structure

```
VidPare.sln
├── src/
│   ├── VidPare.Core/                          # net8.0 — builds on Linux
│   │   ├── VidPare.Core.csproj
│   │   ├── Models/
│   │   │   ├── TrimState.cs                   # TimeSpan-based trim boundaries
│   │   │   ├── ExportFormat.cs                # MP4H264, MP4HEVC enums
│   │   │   ├── QualityPreset.cs               # Passthrough, High, Medium, Low
│   │   │   ├── ExportCapabilities.cs          # Support matrix + resolution logic
│   │   │   ├── ExportSupport.cs               # Supported/unsupported with reason
│   │   │   ├── ResolvedExportSelection.cs     # Final format+quality after fallback
│   │   │   ├── VideoMetadata.cs               # Duration, codec, size, resolution
│   │   │   └── ExportRequest.cs               # Input parameters for export
│   │   ├── Services/
│   │   │   ├── IVideoEngine.cs                # Export interface
│   │   │   ├── IVideoMetadataReader.cs        # Metadata loading interface
│   │   │   ├── IThumbnailGenerator.cs         # Thumbnail extraction interface
│   │   │   ├── IMediaPlayback.cs              # Playback control interface
│   │   │   └── ExportSizeEstimator.cs         # Pure math — estimate output size
│   │   ├── Utilities/
│   │   │   ├── TimeFormatter.cs               # TimeSpan → "MM:SS.ff"
│   │   │   └── AccessibilityIds.cs            # AutomationId string constants
│   │   └── Errors/
│   │       └── ExportError.cs                 # Exception types
│   │
│   └── VidPare.App/                           # net8.0-windows — Windows only
│       ├── VidPare.App.csproj
│       ├── App.xaml / App.xaml.cs
│       ├── MainWindow.xaml / .cs
│       ├── Views/
│       │   ├── ContentView.xaml / .cs
│       │   ├── VideoPlayerView.xaml / .cs
│       │   ├── TimelineView.xaml / .cs
│       │   ├── PlayerControlsView.xaml / .cs
│       │   └── ExportDialog.xaml / .cs
│       ├── Services/
│       │   ├── MediaFoundationVideoEngine.cs  # IVideoEngine via MF
│       │   ├── MediaFoundationMetadataReader.cs
│       │   ├── MediaFoundationThumbnailGenerator.cs
│       │   └── WinUIMediaPlayback.cs          # IMediaPlayback via MediaPlayer
│       └── Platform/
│           ├── TaskbarProgress.cs             # ITaskbarList3 integration
│           ├── JumpListManager.cs
│           └── ToastNotifications.cs
│
└── tests/
    ├── VidPare.Core.Tests/                    # net8.0 — runs on Linux!
    │   ├── VidPare.Core.Tests.csproj
    │   ├── Models/
    │   │   ├── TrimStateTests.cs
    │   │   ├── ExportCapabilitiesTests.cs
    │   │   ├── ExportFormatTests.cs
    │   │   └── QualityPresetTests.cs
    │   ├── Services/
    │   │   ├── ExportSizeEstimatorTests.cs
    │   │   └── VideoEngineLogicTests.cs       # Business logic with mocked interfaces
    │   └── Utilities/
    │       └── TimeFormatterTests.cs
    │
    └── VidPare.App.Tests/                     # net8.0-windows — requires Windows
        ├── VidPare.App.Tests.csproj
        ├── Integration/
        │   ├── MediaFoundationEngineTests.cs
        │   └── ThumbnailGeneratorTests.cs
        └── Acceptance/
            └── AcceptanceTests.cs             # FlaUI end-to-end
```

---

## Project files

### VidPare.Core.csproj (Linux-compatible)

```xml
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <TargetFramework>net8.0</TargetFramework>
    <Nullable>enable</Nullable>
    <ImplicitUsings>enable</ImplicitUsings>
    <RootNamespace>VidPare.Core</RootNamespace>
  </PropertyGroup>

  <ItemGroup>
    <PackageReference Include="CommunityToolkit.Mvvm" Version="8.*" />
  </ItemGroup>
</Project>
```

`CommunityToolkit.Mvvm` targets `netstandard2.0` — fully portable, works on Linux.

### VidPare.Core.Tests.csproj (Linux-compatible)

```xml
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <TargetFramework>net8.0</TargetFramework>
    <Nullable>enable</Nullable>
    <ImplicitUsings>enable</ImplicitUsings>
    <IsPackable>false</IsPackable>
  </PropertyGroup>

  <ItemGroup>
    <PackageReference Include="xunit" Version="2.*" />
    <PackageReference Include="xunit.runner.visualstudio" Version="2.*" />
    <PackageReference Include="Moq" Version="4.*" />
    <PackageReference Include="Microsoft.NET.Test.Sdk" Version="17.*" />
  </ItemGroup>

  <ItemGroup>
    <ProjectReference Include="../../src/VidPare.Core/VidPare.Core.csproj" />
  </ItemGroup>
</Project>
```

### VidPare.App.csproj (Windows-only)

```xml
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <OutputType>WinExe</OutputType>
    <TargetFramework>net8.0-windows10.0.22000.0</TargetFramework>
    <UseWinUI>true</UseWinUI>
    <Nullable>enable</Nullable>
    <ImplicitUsings>enable</ImplicitUsings>
    <RootNamespace>VidPare.App</RootNamespace>
  </PropertyGroup>

  <ItemGroup>
    <PackageReference Include="Microsoft.WindowsAppSDK" Version="1.5.*" />
    <PackageReference Include="CommunityToolkit.WinUI" Version="7.*" />
  </ItemGroup>

  <ItemGroup>
    <ProjectReference Include="../VidPare.Core/VidPare.Core.csproj" />
  </ItemGroup>
</Project>
```

---

## Component-by-component portability

### Tier 1 — Fully portable, develop and test on Linux

These components have zero platform dependencies. Port them first.

#### TrimState.cs

Swift `CMTime` → C# `TimeSpan`. All operations are arithmetic.

```csharp
using CommunityToolkit.Mvvm.ComponentModel;

namespace VidPare.Core.Models;

public partial class TrimState : ObservableObject
{
    [ObservableProperty] private TimeSpan _startTime;
    [ObservableProperty] private TimeSpan _endTime;

    public TimeSpan Duration =>
        EndTime > StartTime ? EndTime - StartTime : TimeSpan.Zero;

    public TrimRange TrimRange =>
        new(StartTime, EndTime > StartTime ? EndTime : StartTime);

    public void Reset(TimeSpan videoDuration)
    {
        var sanitized = videoDuration > TimeSpan.Zero ? videoDuration : TimeSpan.Zero;
        StartTime = TimeSpan.Zero;
        EndTime = sanitized;
    }

    public bool IsAtOrPastEnd(TimeSpan time) => time >= EndTime;
}

public readonly record struct TrimRange(TimeSpan Start, TimeSpan End)
{
    public TimeSpan Duration => End - Start;
}
```

#### ExportFormat.cs & QualityPreset.cs

Remove `AVFileType` / `UTType` dependencies. Use string constants.

```csharp
namespace VidPare.Core.Models;

public enum ExportFormat
{
    Mp4H264,
    Mp4HEVC
    // MOV dropped — no native Windows MF MOV sink
}

public enum QualityPreset
{
    Passthrough,
    High,
    Medium,
    Low
}

public static class ExportFormatExtensions
{
    public static string FileExtension(this ExportFormat f) => "mp4";
    public static string ContainerLabel(this ExportFormat f) => "MP4";
    public static bool IsHEVC(this ExportFormat f) => f == ExportFormat.Mp4HEVC;
}

public static class QualityPresetExtensions
{
    public static bool IsPassthrough(this QualityPreset q) => q == QualityPreset.Passthrough;
}
```

#### ExportCapabilities.cs

Already pure business logic on macOS (only `Foundation` import). Translates 1:1 — the capability matrix, `resolvedSelection()` fallback chain, and support queries are all platform-free.

#### ExportSizeEstimator.cs

Extract from `VideoEngine.estimateOutputSize()` — pure math, zero platform APIs:

```csharp
namespace VidPare.Core.Services;

public static class ExportSizeEstimator
{
    public static long Estimate(long fileSize, TimeSpan videoDuration, TrimRange trimRange, QualityPreset quality)
    {
        var totalSeconds = videoDuration.TotalSeconds;
        var trimSeconds = trimRange.Duration.TotalSeconds;
        if (totalSeconds <= 0 || !double.IsFinite(totalSeconds)) return 0;

        var rawRatio = trimSeconds / totalSeconds;
        if (!double.IsFinite(rawRatio)) return 0;
        var ratio = Math.Clamp(rawRatio, 0.0, 1.0);

        var multiplier = quality switch
        {
            QualityPreset.Passthrough => 1.0,
            QualityPreset.High => 0.9,
            QualityPreset.Medium => 0.5,
            QualityPreset.Low => 0.25,
            _ => 1.0
        };

        return (long)(fileSize * ratio * multiplier);
    }

    public static QualityPreset EffectiveQuality(ExportFormat format, QualityPreset quality, bool sourceIsHEVC) =>
        (format.IsHEVC() && quality.IsPassthrough() && !sourceIsHEVC)
            ? QualityPreset.High
            : quality;
}
```

#### TimeFormatter.cs

`TimeSpan.TotalSeconds` → string formatting. Identical logic to Swift version.

#### AccessibilityIds.cs

String constants only. Copy as-is.

#### ExportError.cs

Exception types. No platform dependency.

#### Service interfaces

```csharp
namespace VidPare.Core.Services;

public record VideoMetadata(
    TimeSpan Duration,
    string CodecName,
    long FileSize,
    int Width,
    int Height
);

public record ExportRequest(
    string InputPath,
    string OutputPath,
    TrimRange TrimRange,
    ExportFormat Format,
    QualityPreset Quality,
    bool SourceIsHEVC = false
);

public record ExportResult(
    string OutputPath,
    TimeSpan Elapsed,
    long FileSize
);

public interface IVideoEngine
{
    Task<ExportResult> ExportAsync(
        ExportRequest request,
        IProgress<double>? progress = null,
        CancellationToken ct = default);
    void Cancel();
}

public interface IVideoMetadataReader
{
    Task<VideoMetadata> ReadAsync(string filePath, CancellationToken ct = default);
    bool CanOpen(string filePath);
}

public interface IThumbnailGenerator
{
    Task<IReadOnlyList<byte[]>> GenerateAsync(
        string filePath,
        int count,
        CancellationToken ct = default);
}
```

---

### Tier 2 — Interface on Linux, mock-test on Linux, implement on Windows

These components have platform-neutral *orchestration logic* that can be tested with mocked interfaces on Linux, even though the actual implementation requires Windows.

#### ViewModel / export orchestration

The export flow — validate capabilities → resolve format/quality → start export → poll progress → finalize — is testable logic:

```csharp
// In VidPare.Core — testable on Linux
public class ExportOrchestrator
{
    private readonly IVideoEngine _engine;
    private readonly IVideoMetadataReader _metadata;

    public ExportOrchestrator(IVideoEngine engine, IVideoMetadataReader metadata)
    {
        _engine = engine;
        _metadata = metadata;
    }

    public async Task<ExportResult> ExecuteAsync(
        string inputPath,
        string outputPath,
        TrimState trimState,
        ExportCapabilities capabilities,
        bool sourceIsHEVC,
        IProgress<double>? progress = null,
        CancellationToken ct = default)
    {
        var effectiveQuality = ExportSizeEstimator.EffectiveQuality(
            trimState.ExportFormat, trimState.QualityPreset, sourceIsHEVC);

        var resolved = capabilities.ResolvedSelection(
            trimState.ExportFormat, effectiveQuality);

        if (!capabilities.IsSupported(resolved.Format, resolved.Quality))
            throw new ExportException(resolved.AdjustmentReason ?? "Unsupported");

        var request = new ExportRequest(
            inputPath, outputPath, trimState.TrimRange,
            resolved.Format, resolved.Quality, sourceIsHEVC);

        return await _engine.ExportAsync(request, progress, ct);
    }
}
```

Test this on Linux with `Moq`:

```csharp
[Fact]
public async Task ExecuteAsync_HevcPassthroughOnNonHevcSource_PromotesToHigh()
{
    var mockEngine = new Mock<IVideoEngine>();
    mockEngine
        .Setup(e => e.ExportAsync(It.IsAny<ExportRequest>(), It.IsAny<IProgress<double>>(), It.IsAny<CancellationToken>()))
        .ReturnsAsync(new ExportResult("/out.mp4", TimeSpan.FromSeconds(2), 1000));

    var orchestrator = new ExportOrchestrator(mockEngine.Object, Mock.Of<IVideoMetadataReader>());
    var trimState = new TrimState { ExportFormat = ExportFormat.Mp4HEVC, QualityPreset = QualityPreset.Passthrough };
    // ... set up capabilities matrix ...

    await orchestrator.ExecuteAsync("/in.mp4", "/out.mp4", trimState, capabilities, sourceIsHEVC: false);

    mockEngine.Verify(e => e.ExportAsync(
        It.Is<ExportRequest>(r => r.Quality == QualityPreset.High),
        It.IsAny<IProgress<double>>(),
        It.IsAny<CancellationToken>()), Times.Once);
}
```

---

### Tier 3 — Windows-only, cannot be done on Linux

| Component | Windows dependency | Notes |
|---|---|---|
| All WinUI 3 XAML (Views/) | Windows App SDK, XAML compiler | No Linux runtime for WinUI 3 |
| `MediaPlayerElement` + `MediaPlayer` | Windows.Media.Playback (WinRT) | Video rendering is Windows-only |
| `MediaFoundationVideoEngine` | `IMFSourceReader` / `IMFSinkWriter` (COM) | Passthrough remux — core complexity |
| `MediaTranscoder` re-encode | `Windows.Media.Transcoding` (WinRT) | Re-encode presets |
| `MediaFoundationThumbnailGenerator` | `IMFSourceReader` frame extraction | Thumbnail pipeline |
| `FileSavePicker` / `FileOpenPicker` | WinUI 3 pickers (need HWND init) | File dialogs |
| Taskbar progress | `ITaskbarList3` COM interface | Windows shell integration |
| Jump lists | `Windows.UI.StartScreen.JumpList` | Taskbar right-click menu |
| Toast notifications | `Windows.UI.Notifications` | Export completion alerts |
| FlaUI acceptance tests | Windows UIAutomation COM API | End-to-end testing |
| Snapshot / visual tests | WinUI 3 rendering context | Need Windows desktop session |
| MSIX packaging | Windows SDK `makeappx` / `signtool` | Distribution packaging |

---

## Unit tests portable to Linux

The macOS test suite maps to Linux-compatible tests as follows:

| macOS test file | Lines | Linux-portable? | C# equivalent |
|---|---|---|---|
| `VideoEngineTests.swift` | 597 | ~70% — all sizing/capability logic | `ExportSizeEstimatorTests.cs`, `ExportCapabilitiesTests.cs`, `ExportOrchestratorTests.cs` |
| `TimeFormatterTests.swift` | 32 | 100% | `TimeFormatterTests.cs` |
| `VideoDocumentTests.swift` | 87 | ~60% — format validation, `CanOpen` | `VideoMetadataTests.cs` (mock metadata reader) |
| `TimelineViewTests.swift` | 93 | ~50% — coordinate math only | `TimelineCoordinateTests.cs` (extract math) |
| `SnapshotTests.swift` | 138 | 0% — requires rendering | Windows-only |
| `AcceptanceTests.swift` | 51 | 0% — requires UI automation | Windows-only |
| `TrimHandleTests.swift` | 261 | 0% — requires UI automation | Windows-only |

**Estimated portable test coverage**: ~400-500 lines of C# unit tests runnable on Linux.

---

## Development workflow

### On Linux (or macOS)

```bash
# Build core library
dotnet build src/VidPare.Core/

# Run all portable tests
dotnet test tests/VidPare.Core.Tests/

# Format
dotnet format src/VidPare.Core/
dotnet format tests/VidPare.Core.Tests/
```

### On Windows (when ready for UI + integration)

```powershell
# Build everything (Core + App)
dotnet build VidPare.sln

# Run all tests
dotnet test VidPare.sln

# Run only core tests (fast)
dotnet test tests/VidPare.Core.Tests/

# Run only integration tests
dotnet test tests/VidPare.App.Tests/ --filter "Category!=Acceptance"

# Publish
dotnet publish src/VidPare.App/ -r win-x64 -c Release --self-contained -p:PublishSingleFile=true
```

### CI pipeline (GitHub Actions)

```yaml
jobs:
  core-tests:
    runs-on: ubuntu-latest          # cheap, fast
    steps:
      - uses: actions/setup-dotnet@v4
        with: { dotnet-version: '8.0.x' }
      - run: dotnet test tests/VidPare.Core.Tests/ --configuration Release

  windows-build:
    runs-on: windows-latest          # 2x cost, but required
    needs: core-tests                # only run if core passes
    steps:
      - uses: actions/setup-dotnet@v4
        with: { dotnet-version: '8.0.x' }
      - run: dotnet build VidPare.sln --configuration Release
      - run: dotnet test tests/VidPare.App.Tests/ --configuration Release --filter "Category!=Acceptance"
      - run: dotnet publish src/VidPare.App/ -r win-x64 -c Release --self-contained -p:PublishSingleFile=true
      - uses: actions/upload-artifact@v4
        with:
          name: VidPare-win-x64
          path: src/VidPare.App/bin/Release/net8.0-windows10.0.22000.0/win-x64/publish/
```

---

## Effort breakdown

| Tier | Work | % of total | Environment |
|---|---|---|---|
| 1 — Models, enums, utilities, interfaces | All business logic + portable unit tests | ~25% | Linux |
| 2 — Orchestration layer + mock-tested logic | Export flow, capability resolution, progress | ~10% | Linux |
| 3 — WinUI 3 views | All XAML + code-behind | ~25% | Windows |
| 3 — Media Foundation services | Passthrough remux, re-encode, thumbnails, metadata | ~25% | Windows |
| 3 — Windows integrations | Taskbar, jump lists, toast, shell, pickers | ~10% | Windows |
| 3 — Integration + acceptance tests | MF tests, FlaUI, snapshots | ~5% | Windows |

**Total Linux-portable: ~35%. Total Windows-required: ~65%.**

The Linux-portable 35% should be done first — it establishes the domain model, proves the architecture, and provides a fast test suite that runs in CI on cheap Linux runners. The Windows 65% then fills in the platform implementations against well-defined interfaces.

---

## Migration order

1. **Create solution + `VidPare.Core` project on Linux** — scaffold `.sln`, `.csproj`, directory structure
2. **Port models** — `TrimState`, `ExportFormat`, `QualityPreset`, `ExportCapabilities`, `ExportSupport`, `ResolvedExportSelection`, `VideoMetadata`
3. **Port utilities** — `TimeFormatter`, `AccessibilityIds`
4. **Define service interfaces** — `IVideoEngine`, `IVideoMetadataReader`, `IThumbnailGenerator`
5. **Port business logic** — `ExportSizeEstimator`, `ExportOrchestrator`, `ExportError`
6. **Port unit tests** — translate `VideoEngineTests` (capability/sizing logic), `TimeFormatterTests`, `VideoDocumentTests` (format validation)
7. **Set up CI** — GitHub Actions with `ubuntu-latest` for core tests
8. **Switch to Windows** — create `VidPare.App`, implement WinUI 3 shell, Media Foundation services
9. **Add Windows CI job** — `windows-latest` for build + integration tests
10. **Windows-exclusive features** — taskbar, jump lists, toast, shell association
