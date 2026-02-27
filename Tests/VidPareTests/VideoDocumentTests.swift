import AVFoundation
@testable import VidPare
import XCTest

final class VideoDocumentTests: XCTestCase {
    func testVideoDocumentRejectsUnsupportedFormat() async {
        let url = URL(fileURLWithPath: "/tmp/test.mkv")
        let doc = VideoDocument(url: url)

        do {
            try await doc.loadMetadata()
            XCTFail("Expected unsupportedFormat error")
        } catch let error as VideoDocumentError {
            if case .unsupportedFormat(let ext) = error {
                XCTAssertEqual(ext, "mkv")
            } else {
                XCTFail("Expected unsupportedFormat, got \(error)")
            }
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    func testVideoDocumentRejectsNoVideoTrack() async throws {
        let sayPath = "/usr/bin/say"
        let afconvertPath = "/usr/bin/afconvert"
        guard FileManager.default.isExecutableFile(atPath: sayPath) else {
            throw XCTSkip("Skipping: \(sayPath) is not available on this runner.")
        }
        guard FileManager.default.isExecutableFile(atPath: afconvertPath) else {
            throw XCTSkip("Skipping: \(afconvertPath) is not available on this runner.")
        }

        let uid = UUID().uuidString
        let m4aURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("test_audio_\(uid).m4a")
        let mp4URL = FileManager.default.temporaryDirectory
            .appendingPathComponent("test_audio_\(uid).mp4")
        defer {
            try? FileManager.default.removeItem(at: m4aURL)
            try? FileManager.default.removeItem(at: mp4URL)
        }

        // Create a valid audio-only M4A via macOS `say` command.
        let sayProcess = Process()
        sayProcess.executableURL = URL(fileURLWithPath: sayPath)
        sayProcess.arguments = ["-o", m4aURL.path, "--data-format=aac", "test"]
        try sayProcess.run()
        sayProcess.waitUntilExit()
        guard sayProcess.terminationStatus == 0 else {
            throw XCTSkip("Skipping: `say` failed with status \(sayProcess.terminationStatus).")
        }

        // Convert to MP4 container via afconvert so VideoDocument.canOpen passes.
        let convertProcess = Process()
        convertProcess.executableURL = URL(fileURLWithPath: afconvertPath)
        convertProcess.arguments = [m4aURL.path, mp4URL.path, "-d", "aac", "-f", "mp4f"]
        try convertProcess.run()
        convertProcess.waitUntilExit()
        guard convertProcess.terminationStatus == 0 else {
            throw XCTSkip("Skipping: `afconvert` failed with status \(convertProcess.terminationStatus).")
        }

        let doc = VideoDocument(url: mp4URL)
        do {
            try await doc.loadMetadata()
            XCTFail("Expected noVideoTrack error")
        } catch let error as VideoDocumentError {
            if case .noVideoTrack = error {
                // Expected
            } else {
                XCTFail("Expected noVideoTrack, got \(error)")
            }
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    func testVideoDocumentSupportedTypes() {
        XCTAssertTrue(VideoDocument.canOpen(url: URL(fileURLWithPath: "/test.mp4")))
        XCTAssertTrue(VideoDocument.canOpen(url: URL(fileURLWithPath: "/test.MOV")))
        XCTAssertTrue(VideoDocument.canOpen(url: URL(fileURLWithPath: "/test.m4v")))
        XCTAssertFalse(VideoDocument.canOpen(url: URL(fileURLWithPath: "/test.mkv")))
        XCTAssertFalse(VideoDocument.canOpen(url: URL(fileURLWithPath: "/test.avi")))
        XCTAssertFalse(VideoDocument.canOpen(url: URL(fileURLWithPath: "/test.webm")))
    }
}
