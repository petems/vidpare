import AVFoundation
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
  let initialFileURL: URL?

  @State private var document: VideoDocument?
  @State private var trimState = TrimState()
  @State private var videoEngine = VideoEngine()
  @State private var player = AVPlayer()
  @State private var currentTime: CMTime = .zero
  @State private var isPlaying = false
  @State private var thumbnails: [NSImage] = []
  @State private var showExportSheet = false
  @State private var showFileImporter = false
  @State private var errorMessage: String?
  @State private var showError = false
  @State private var timeObserver: Any?
  @State private var isLoadingThumbnails = false
  @State private var currentSecurityScopedURL: URL?

  init(initialFileURL: URL? = nil) {
    self.initialFileURL = initialFileURL
  }

  var body: some View {
    Group {
      if let document {
        videoEditorView(document: document)
      } else {
        dropTargetView
      }
    }
    .frame(minWidth: 800, minHeight: 500)
    .fileImporter(
      isPresented: $showFileImporter,
      allowedContentTypes: [.mpeg4Movie, .quickTimeMovie, .movie],
      allowsMultipleSelection: false
    ) { result in
      switch result {
      case .success(let urls):
        if let url = urls.first {
          loadVideo(url: url)
        }
      case .failure(let error):
        showError(error.localizedDescription)
      }
    }
    .onDrop(of: [.fileURL], isTargeted: nil) { providers in
      handleDrop(providers: providers)
    }
    .alert("Error", isPresented: $showError) {
      Button("OK") {}
    } message: {
      Text(errorMessage ?? "An unknown error occurred.")
    }
    .sheet(isPresented: $showExportSheet) {
      if let document {
        ExportSheet(
          document: document,
          trimState: trimState,
          videoEngine: videoEngine,
          onDismiss: { showExportSheet = false }
        )
      }
    }
    .toolbar {
      ToolbarItemGroup {
        Button {
          showFileImporter = true
        } label: {
          Label("Open", systemImage: "folder")
        }
        .keyboardShortcut("o")
        .disabled(videoEngine.isExporting)
        .accessibilityIdentifier(AccessibilityID.toolbarOpen)

        if document != nil {
          Button {
            showExportSheet = true
          } label: {
            Label("Export", systemImage: "square.and.arrow.up")
          }
          .keyboardShortcut("e")
          .accessibilityIdentifier(AccessibilityID.toolbarExport)
        }
      }
    }
    .navigationTitle(windowTitle)
    .onAppear {
      if let url = initialFileURL {
        loadVideo(url: url)
      }
    }
    .onDisappear {
      removeTimeObserver()
      if let url = currentSecurityScopedURL {
        url.stopAccessingSecurityScopedResource()
        currentSecurityScopedURL = nil
      }
    }
  }

  // MARK: - Subviews

  private var dropTargetView: some View {
    VStack(spacing: 16) {
      Image(systemName: "film")
        .font(.system(size: 48))
        .foregroundStyle(.secondary)
      Text("Drop a video file here")
        .font(.title2)
        .foregroundStyle(.secondary)
      Text("or")
        .foregroundStyle(.quaternary)
      Button("Open File...") {
        showFileImporter = true
      }
      .keyboardShortcut("o")
      .accessibilityIdentifier(AccessibilityID.openFileButton)
      Text("Supports MP4, MOV, M4V")
        .font(.caption)
        .foregroundStyle(.tertiary)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(.black.opacity(0.02))
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier(AccessibilityID.dropTarget)
  }

  private func videoEditorView(document: VideoDocument) -> some View {
    VStack(spacing: 12) {
      VideoPlayerView(player: player)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.black)
        .clipShape(RoundedRectangle(cornerRadius: EditorStyle.deckCornerRadius, style: .continuous))
        .overlay(
          RoundedRectangle(cornerRadius: EditorStyle.deckCornerRadius, style: .continuous)
            .stroke(EditorStyle.trackBaseline, lineWidth: 1)
        )

      editorDeck(document: document)
    }
    .padding(12)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    .background(EditorStyle.panelBackground)
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier(AccessibilityID.videoEditor)
    .onKeyPress(.space) {
      togglePlayback()
      return .handled
    }
    .onKeyPress(characters: CharacterSet(charactersIn: "i")) { _ in
      setInPoint()
      return .handled
    }
    .onKeyPress(characters: CharacterSet(charactersIn: "o")) { _ in
      setOutPoint()
      return .handled
    }
  }

  private func editorDeck(document: VideoDocument) -> some View {
    VStack(spacing: 0) {
      deckChromeStrip

      PlayerControlsView(
        currentTime: currentTime,
        duration: document.duration,
        isPlaying: isPlaying,
        trimState: trimState,
        onPlayPause: togglePlayback,
        onSetInPoint: setInPoint,
        onSetOutPoint: setOutPoint
      )
      .padding(.horizontal, 2)
      .padding(.top, 4)

      TimelineView(
        thumbnails: thumbnails,
        duration: document.duration,
        currentTime: currentTime,
        trimState: trimState,
        onSeek: seek(to:)
      )
      .padding(.horizontal, 12)
      .padding(.vertical, 8)

      HStack {
        Text(document.fileName)
          .font(.system(size: 11, weight: .medium, design: .rounded))
          .lineLimit(1)
          .foregroundStyle(EditorStyle.textSecondary)
        Spacer()
        Text(
          "\(document.formattedResolution) • \(document.codecName) • \(document.formattedFileSize)"
        )
        .font(.system(size: 11, weight: .medium, design: .rounded))
        .foregroundStyle(EditorStyle.textSecondary.opacity(0.85))
      }
      .padding(.horizontal, 14)
      .padding(.top, 2)
      .padding(.bottom, 10)
    }
    .background(EditorStyle.panelBackground)
    .clipShape(RoundedRectangle(cornerRadius: EditorStyle.deckCornerRadius, style: .continuous))
    .overlay(
      RoundedRectangle(cornerRadius: EditorStyle.deckCornerRadius, style: .continuous)
        .stroke(EditorStyle.trackBaseline, lineWidth: 1)
    )
  }

  private var deckChromeStrip: some View {
    HStack(spacing: 10) {
      HStack(spacing: 6) {
        trafficLight(EditorStyle.trafficRed)
        trafficLight(EditorStyle.trafficYellow)
        trafficLight(EditorStyle.trafficGreen)
      }

      Text("VidPare")
        .font(.system(size: 13, weight: .medium, design: .rounded))
        .foregroundStyle(EditorStyle.textSecondary)

      Spacer()
    }
    .padding(.horizontal, 12)
    .frame(maxWidth: .infinity, minHeight: EditorStyle.chromeStripHeight)
    .background(EditorStyle.chromeStripBackground)
  }

  private func trafficLight(_ color: Color) -> some View {
    Circle()
      .fill(color)
      .frame(width: 10, height: 10)
  }

  // MARK: - Window Title

  private var windowTitle: String {
    guard let document else { return "VidPare" }
    let trimDuration = TimeFormatter.shortDuration(from: trimState.duration)
    return "\(document.fileName) — \(trimDuration)"
  }

  // MARK: - Video Loading

  private func loadVideo(url: URL) {
    guard !videoEngine.isExporting else {
      showError("Cannot open a new file while an export is in progress.")
      return
    }

    guard VideoDocument.canOpen(url: url) else {
      showError(VideoDocumentError.unsupportedFormat(url.pathExtension).localizedDescription)
      return
    }

    // Start accessing security-scoped resource
    let accessing = url.startAccessingSecurityScopedResource()

    // Release previous security-scoped access
    if let previousURL = currentSecurityScopedURL {
      previousURL.stopAccessingSecurityScopedResource()
      currentSecurityScopedURL = nil
    }

    let doc = VideoDocument(url: url)
    Task {
      do {
        try await doc.loadMetadata()
        self.document = doc
        if accessing { currentSecurityScopedURL = url }
        trimState.reset(for: doc.duration)
        trimState.exportFormat = doc.passthroughContainerFormat
        trimState.qualityPreset = .passthrough

        // Set up player
        let playerItem = AVPlayerItem(asset: doc.asset)
        player.replaceCurrentItem(with: playerItem)
        setupTimeObserver()

        // Generate thumbnails
        await generateThumbnails(for: doc)
      } catch {
        if accessing { url.stopAccessingSecurityScopedResource() }
        showError(error.localizedDescription)
      }
    }
  }

  private func handleDrop(providers: [NSItemProvider]) -> Bool {
    guard !videoEngine.isExporting else { return false }
    guard let provider = providers.first,
      provider.registeredTypeIdentifiers.contains(UTType.fileURL.identifier)
    else {
      return false
    }
    provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
      guard let data = item as? Data,
        let url = URL(dataRepresentation: data, relativeTo: nil)
      else { return }
      DispatchQueue.main.async {
        loadVideo(url: url)
      }
    }
    return true
  }

  private func generateThumbnails(for doc: VideoDocument) async {
    isLoadingThumbnails = true
    let durationSeconds = CMTimeGetSeconds(doc.duration)
    let count = ThumbnailGenerator.thumbnailCount(forDuration: durationSeconds)
    let generator = ThumbnailGenerator(asset: doc.asset)

    do {
      let images = try await generator.generateThumbnails(count: count)
      self.thumbnails = images
    } catch {
      // Thumbnails are non-critical; proceed without them
    }
    isLoadingThumbnails = false
  }

  // MARK: - Playback

  private func setupTimeObserver() {
    removeTimeObserver()
    let interval = CMTime(seconds: 0.05, preferredTimescale: 600)
    timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { time in
      self.currentTime = time
      self.isPlaying = player.rate > 0
      if self.isPlaying && self.trimState.isAtOrPastEnd(time) {
        self.player.pause()
        self.seek(to: self.trimState.startTime)
      }
    }
  }

  private func removeTimeObserver() {
    if let observer = timeObserver {
      player.removeTimeObserver(observer)
      timeObserver = nil
    }
  }

  private func togglePlayback() {
    if player.rate > 0 {
      player.pause()
    } else {
      if trimState.isAtOrPastEnd(currentTime) {
        seek(to: trimState.startTime)
      }
      player.play()
    }
    isPlaying = player.rate > 0
  }

  private func seek(to time: CMTime) {
    player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero)
    currentTime = time
  }

  private func setInPoint() {
    trimState.startTime = currentTime
    if CMTimeCompare(trimState.startTime, trimState.endTime) >= 0 {
      guard let document else { return }
      trimState.endTime = document.duration
    }
  }

  private func setOutPoint() {
    trimState.endTime = currentTime
    if CMTimeCompare(trimState.endTime, trimState.startTime) <= 0 {
      trimState.startTime = .zero
    }
  }

  // MARK: - Error

  private func showError(_ message: String) {
    errorMessage = message
    showError = true
  }
}
