import AVFoundation
@testable import VidPare
import XCTest

final class VideoEngineExportLifecycleTests: XCTestCase {

    // MARK: - Export lifecycle integration

    @MainActor
    func testExportLifecycle_successWithFixture() async throws {
        let fixtureURL = try fixtureURL(named: "sample", ext: "mp4")
        let asset = AVURLAsset(url: fixtureURL)
        let duration = try await asset.load(.duration)
        let maxTrimDuration: Double = 1.0
        let minTrimDuration: Double = 0.2
        let halfDuration = CMTimeGetSeconds(duration) / 2.0
        let clampedTrimDuration = min(maxTrimDuration, max(minTrimDuration, halfDuration))
        let end = CMTime(seconds: clampedTrimDuration, preferredTimescale: 600)
        let trimRange = CMTimeRange(start: .zero, end: end)

        let outputURL = uniqueTempURL(ext: "mp4")
        defer { try? FileManager.default.removeItem(at: outputURL) }

        let engine = VideoEngine()
        let result = try await engine.export(
            asset: asset,
            trimRange: trimRange,
            format: .mp4H264,
            quality: .passthrough,
            outputURL: outputURL
        )

        XCTAssertEqual(result.outputURL, outputURL)
        XCTAssertGreaterThan(result.duration, 0)
        XCTAssertGreaterThan(result.fileSize, 0)
        XCTAssertTrue(FileManager.default.fileExists(atPath: outputURL.path))
        XCTAssertFalse(engine.isExporting)
        XCTAssertEqual(engine.progress, 1.0)
    }

    @MainActor
    func testExportLifecycle_failRemovesOutputFile() async throws {
        let fixtureURL = try fixtureURL(named: "sample", ext: "mp4")
        let asset = AVURLAsset(url: fixtureURL)

        // Use a non-existent parent directory so the export session cannot
        // write its temp file, causing a genuine export failure.
        let nonExistentDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("vidpare-nonexistent-\(UUID().uuidString)")
        let outputURL = nonExistentDir.appendingPathComponent("output.mp4")

        let engine = VideoEngine()
        do {
            _ = try await engine.export(
                asset: asset,
                trimRange: CMTimeRange(start: .zero, duration: CMTime(seconds: 1.0, preferredTimescale: 600)),
                format: .mp4H264,
                quality: .low,
                outputURL: outputURL
            )
            XCTFail("Expected export failure with non-writable output path")
        } catch {
            // expected
        }

        XCTAssertFalse(FileManager.default.fileExists(atPath: outputURL.path))
        XCTAssertFalse(engine.isExporting, "isExporting should be reset after failure")
        XCTAssertEqual(engine.progress, 0, "progress should be reset after failure")
    }

    @MainActor
    func testExportLifecycle_successGIFWithFixture() async throws {
        let fixtureURL = try fixtureURL(named: "sample", ext: "mp4")
        let asset = AVURLAsset(url: fixtureURL)
        let trimRange = CMTimeRange(start: .zero, duration: CMTime(seconds: 1.0, preferredTimescale: 600))
        let outputURL = uniqueTempURL(ext: "gif")
        defer { try? FileManager.default.removeItem(at: outputURL) }

        let engine = VideoEngine()
        let result = try await engine.export(
            asset: asset,
            trimRange: trimRange,
            format: .gif,
            quality: .high,
            outputURL: outputURL,
            gifSettings: GIFExportSettings(frameRate: .fps8, scale: .small)
        )

        XCTAssertEqual(result.outputURL, outputURL)
        XCTAssertGreaterThan(result.duration, 0)
        XCTAssertGreaterThan(result.fileSize, 0)
        XCTAssertTrue(FileManager.default.fileExists(atPath: outputURL.path))
        XCTAssertFalse(engine.isExporting)
        XCTAssertEqual(engine.progress, 1.0)
    }

    @MainActor
    func testExportLifecycle_gifDurationOverLimitThrows() async throws {
        let fixtureURL = try fixtureURL(named: "sample", ext: "mp4")
        let asset = AVURLAsset(url: fixtureURL)
        let outputURL = uniqueTempURL(ext: "gif")
        defer { try? FileManager.default.removeItem(at: outputURL) }

        let engine = VideoEngine()
        do {
            _ = try await engine.export(
                asset: asset,
                trimRange: CMTimeRange(start: .zero, duration: CMTime(seconds: 16.0, preferredTimescale: 600)),
                format: .gif,
                quality: .high,
                outputURL: outputURL
            )
            XCTFail("Expected GIF duration limit error")
        } catch let error as ExportError {
            switch error {
            case .gifDurationLimitExceeded:
                break
            default:
                XCTFail("Expected gifDurationLimitExceeded, got \(error)")
            }
        }
    }

    @MainActor
    func testExportLifecycle_gifDurationAtLimitSucceeds() async throws {
        let (asset, extendedFixtureURL) = try await extendedFixtureAsset(
            minimumDurationSeconds: GIFExportSettings.maxDurationSeconds
        )
        defer { try? FileManager.default.removeItem(at: extendedFixtureURL) }

        let outputURL = uniqueTempURL(ext: "gif")
        defer { try? FileManager.default.removeItem(at: outputURL) }

        let engine = VideoEngine()
        let result = try await engine.export(
            asset: asset,
            trimRange: CMTimeRange(
                start: .zero,
                duration: CMTime(seconds: GIFExportSettings.maxDurationSeconds, preferredTimescale: 600)
            ),
            format: .gif,
            quality: .high,
            outputURL: outputURL
        )

        XCTAssertEqual(result.outputURL, outputURL)
        XCTAssertGreaterThan(result.duration, 0)
        XCTAssertGreaterThan(result.fileSize, 0)
        XCTAssertTrue(FileManager.default.fileExists(atPath: outputURL.path))
        XCTAssertFalse(engine.isExporting)
        XCTAssertEqual(engine.progress, 1.0)
    }

    @MainActor
    func testExportLifecycle_cancelRemovesPartialOutput() async throws {
        let fixtureURL = try fixtureURL(named: "sample", ext: "mp4")
        let asset = AVURLAsset(url: fixtureURL)
        let outputURL = uniqueTempURL(ext: "mp4")
        defer { try? FileManager.default.removeItem(at: outputURL) }

        let engine = VideoEngine()
        let longTrim = CMTimeRange(start: .zero, duration: try await asset.load(.duration))

        let task = Task {
            try await engine.export(
                asset: asset,
                trimRange: longTrim,
                format: .mp4H264,
                quality: .low,
                outputURL: outputURL
            )
        }

        let didStartExport = await waitForExportToStart(engine, timeoutSeconds: 3.0)
        XCTAssertTrue(didStartExport, "Expected export to start before cancellation")
        guard didStartExport else {
            task.cancel()
            _ = try? await task.value
            return
        }

        engine.cancelExport()

        do {
            _ = try await task.value
            XCTFail("Expected cancelled export")
        } catch let error as ExportError {
            if case .cancelled = error {
                // expected
            } else {
                XCTFail("Expected cancelled export error, got \(error)")
            }
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }

        XCTAssertFalse(engine.isExporting, "isExporting should be reset after cancel")
        XCTAssertEqual(engine.progress, 0, "progress should be reset after cancel")
        XCTAssertFalse(FileManager.default.fileExists(atPath: outputURL.path))
    }

    @MainActor
    func testExportLifecycle_cancelRemovesPartialOutput_gif() async throws {
        let (asset, extendedFixtureURL) = try await extendedFixtureAsset(
            minimumDurationSeconds: GIFExportSettings.maxDurationSeconds
        )
        defer { try? FileManager.default.removeItem(at: extendedFixtureURL) }

        let outputURL = uniqueTempURL(ext: "gif")
        defer { try? FileManager.default.removeItem(at: outputURL) }

        let engine = VideoEngine()
        let longTrim = CMTimeRange(
            start: .zero,
            duration: CMTime(seconds: GIFExportSettings.maxDurationSeconds, preferredTimescale: 600)
        )

        let task = Task {
            try await engine.export(
                asset: asset,
                trimRange: longTrim,
                format: .gif,
                quality: .high,
                outputURL: outputURL,
                gifSettings: GIFExportSettings(frameRate: .fps15, scale: .full)
            )
        }

        let didStartExport = await waitForExportToStart(engine, timeoutSeconds: 3.0)
        XCTAssertTrue(didStartExport, "Expected GIF export to start before cancellation")
        guard didStartExport else {
            task.cancel()
            _ = try? await task.value
            return
        }

        engine.cancelExport()

        do {
            _ = try await task.value
            XCTFail("Expected cancelled GIF export")
        } catch let error as ExportError {
            if case .cancelled = error {
                // expected
            } else {
                XCTFail("Expected cancelled export error, got \(error)")
            }
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }

        XCTAssertFalse(engine.isExporting, "isExporting should be reset after cancel")
        XCTAssertEqual(engine.progress, 0, "progress should be reset after cancel")
        XCTAssertFalse(FileManager.default.fileExists(atPath: outputURL.path))
    }
}

// MARK: - Private helpers (fixture & temp URL)

extension VideoEngineExportLifecycleTests {
    private func fixtureURL(named name: String, ext: String) throws -> URL {
        guard let url = Bundle.module.url(forResource: name, withExtension: ext) else {
            throw XCTSkip("Missing fixture: \(name).\(ext)")
        }
        return url
    }

    private func uniqueTempURL(ext: String) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("VideoEngineTests_\(UUID().uuidString)")
            .appendingPathExtension(ext)
    }

    private func extendedFixtureAsset(minimumDurationSeconds: Double) async throws -> (AVURLAsset, URL) {
        let fixtureURL = try fixtureURL(named: "sample", ext: "mp4")
        let sourceAsset = AVURLAsset(url: fixtureURL)
        let sourceDuration = try await sourceAsset.load(.duration)
        let sourceDurationSeconds = CMTimeGetSeconds(sourceDuration)

        guard sourceDurationSeconds.isFinite, sourceDurationSeconds > 0 else {
            throw XCTSkip("Fixture duration must be positive")
        }

        let loopCount = max(1, Int(ceil(minimumDurationSeconds / sourceDurationSeconds)))
        let composition = AVMutableComposition()
        guard
            let sourceVideoTrack = try await sourceAsset.loadTracks(withMediaType: .video).first,
            let videoTrack = composition.addMutableTrack(
                withMediaType: .video,
                preferredTrackID: kCMPersistentTrackID_Invalid
            )
        else {
            throw XCTSkip("Fixture is missing a video track")
        }

        let sourceAudioTrack = try await sourceAsset.loadTracks(withMediaType: .audio).first
        let audioTrack = composition.addMutableTrack(
            withMediaType: .audio,
            preferredTrackID: kCMPersistentTrackID_Invalid
        )

        var insertionTime: CMTime = .zero
        for _ in 0..<loopCount {
            let sourceRange = CMTimeRange(start: .zero, duration: sourceDuration)
            try videoTrack.insertTimeRange(sourceRange, of: sourceVideoTrack, at: insertionTime)
            if let sourceAudioTrack, let audioTrack {
                try audioTrack.insertTimeRange(sourceRange, of: sourceAudioTrack, at: insertionTime)
            }
            insertionTime = CMTimeAdd(insertionTime, sourceDuration)
        }
        videoTrack.preferredTransform = try await sourceVideoTrack.load(.preferredTransform)

        let extendedURL = uniqueTempURL(ext: "mp4")
        try? FileManager.default.removeItem(at: extendedURL)
        guard let session = AVAssetExportSession(
            asset: composition,
            presetName: AVAssetExportPresetHighestQuality
        ) else {
            throw XCTSkip("Failed to create export session for extended fixture")
        }
        session.outputURL = extendedURL
        session.outputFileType = .mp4
        await session.export()
        guard session.status == .completed else {
            throw XCTSkip("Failed to build extended fixture: \(session.error?.localizedDescription ?? "unknown error")")
        }

        return (AVURLAsset(url: extendedURL), extendedURL)
    }

    @MainActor
    private func waitForExportToStart(
        _ engine: VideoEngine,
        timeoutSeconds: TimeInterval
    ) async -> Bool {
        let exportStarted = expectation(description: "Export started")
        var didStartExport = false

        let pollingTask = Task { @MainActor in
            let pollingIntervalNanos: UInt64 = 10_000_000
            let timeoutDate = Date().addingTimeInterval(timeoutSeconds)

            while Date() < timeoutDate {
                if engine.isExporting {
                    didStartExport = true
                    exportStarted.fulfill()
                    return
                }

                try? await Task.sleep(nanoseconds: pollingIntervalNanos)
            }
        }

        await fulfillment(of: [exportStarted], timeout: timeoutSeconds + 0.5)
        pollingTask.cancel()
        return didStartExport
    }
}
