//
//  VideoCompressionManager.swift
//  VLossLess
//
//  Created by IT SF GOC HYD on 18/11/25.
//

import Foundation
import AVFoundation
import AppKit
import UniformTypeIdentifiers
import UserNotifications
import Combine

enum QualityPreset: String, CaseIterable {
    case high = "High Quality"
    case balanced = "Balanced"
    case smaller = "Smaller Size"

    var description: String {
        switch self {
        case .high: return "Best visual quality, moderate compression"
        case .balanced: return "Good balance between quality and size"
        case .smaller: return "Maximum compression, slight quality loss"
        }
    }

    var compressionRatio: Float {
        switch self {
        case .high: return 0.6
        case .balanced: return 0.4
        case .smaller: return 0.2
        }
    }
}

final class VideoCompressionManager: NSObject, ObservableObject {
    // MARK: - Published state for UI
    @Published var selectedVideo: URL?
    @Published var originalSize: String = "0 MB"
    @Published var compressedSize: String = "0 MB"
    @Published var savingsPercentage: Double?
    @Published var isCompressing: Bool = false
    @Published var isCompleted: Bool = false
    @Published var progress: Double = 0.0
    @Published var videoDuration: Double?
    @Published var qualityPreset: QualityPreset = .balanced
    @Published var statusMessage: String = ""

    // MARK: - Private
    private var originalFileSizeBytes: Int64 = 0
    private var compressedFileSizeBytes: Int64 = 0
    private var compressedVideoURL: URL?
    private var isCancelled = false

    private let processingQueue = DispatchQueue(label: "com.vlossless.compression", qos: .userInitiated)

    // MARK: - File handling
    func handleFileDrop(_ url: URL) {
        selectedVideo = url
        loadVideoInfo(from: url)
    }

    private func loadVideoInfo(from url: URL) {
        let asset = AVAsset(url: url)

        Task { @MainActor in
            do {
                let duration = try await asset.load(.duration)
                self.videoDuration = CMTimeGetSeconds(duration)
            } catch {
                print("Error loading duration: \(error)")
            }
        }

        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            if let fileSize = attributes[.size] as? Int64 {
                originalFileSizeBytes = fileSize
                originalSize = formatFileSize(fileSize)

                let estimatedCompressedSize = Int64(Float(fileSize) * qualityPreset.compressionRatio)
                compressedSize = formatFileSize(estimatedCompressedSize)

                let savings = Double(fileSize - estimatedCompressedSize) / Double(fileSize) * 100
                savingsPercentage = savings
            }
        } catch {
            print("Error getting file size: \(error)")
        }
    }

    // MARK: - Public API
    func startCompression() {
        guard let videoURL = selectedVideo else { return }
        isCompressing = true
        isCompleted = false
        progress = 0
        isCancelled = false
        statusMessage = "Initializing compression..."

        let tmp = FileManager.default.temporaryDirectory
        let outputURL = tmp.appendingPathComponent("compressed_\(UUID().uuidString).mp4")
        try? FileManager.default.removeItem(at: outputURL)

        processingQueue.async { [weak self] in
            guard let self = self else { return }
            do {
                try self.compressVideoSingleReader(source: videoURL, destination: outputURL)
            } catch {
                DispatchQueue.main.async {
                    self.handleCompressionFailed(error: error)
                }
            }
        }
    }

    func cancelCompression() {
        isCancelled = true
        // Actual cancellation actions occur inside compression function
    }

    func saveCompressedVideo() {
        guard let compressedURL = compressedVideoURL else { return }

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            let savePanel = NSSavePanel()
            savePanel.allowedContentTypes = [UTType.mpeg4Movie]
            savePanel.nameFieldStringValue = "compressed_\(self.selectedVideo?.deletingPathExtension().lastPathComponent ?? "video").mp4"
            savePanel.canCreateDirectories = true
            savePanel.canSelectHiddenExtension = true

            savePanel.begin { response in
                if response == .OK, let destinationURL = savePanel.url {
                    DispatchQueue.global(qos: .userInitiated).async {
                        do {
                            if FileManager.default.fileExists(atPath: destinationURL.path) {
                                try FileManager.default.removeItem(at: destinationURL)
                            }
                            try FileManager.default.copyItem(at: compressedURL, to: destinationURL)
                            DispatchQueue.main.async {
                                self.showNotification(title: "Video Saved", body: "Compressed video saved successfully!")
                                NSWorkspace.shared.activateFileViewerSelecting([destinationURL])
                            }
                        } catch {
                            DispatchQueue.main.async {
                                self.showNotification(title: "Save Failed", body: "Failed to save the video: \(error.localizedDescription)")
                            }
                        }
                    }
                }
            }
        }
    }

    func reset() {
        if let tempURL = compressedVideoURL {
            try? FileManager.default.removeItem(at: tempURL)
        }

        selectedVideo = nil
        originalSize = "0 MB"
        compressedSize = "0 MB"
        savingsPercentage = nil
        isCompressing = false
        isCompleted = false
        progress = 0.0
        videoDuration = nil
        originalFileSizeBytes = 0
        compressedFileSizeBytes = 0
        compressedVideoURL = nil
        statusMessage = ""
        isCancelled = false

        print("🔄 Reset complete")
    }

    // MARK: - Core single-reader compression
    private func compressVideoSingleReader(source: URL, destination: URL) throws {
        let asset = AVURLAsset(url: source)

        // Ensure tracks exist
        guard let videoTrack = asset.tracks(withMediaType: .video).first else {
            throw NSError(domain: "VideoCompression", code: -1, userInfo: [NSLocalizedDescriptionKey: "No video track found"])
        }

        let audioTrack = asset.tracks(withMediaType: .audio).first

        // Estimate bitrate and target
        let originalBitrate = max(videoTrack.estimatedDataRate, 500_000) // fallback
        let targetBitrate = Int(originalBitrate * qualityPreset.compressionRatio)

        // Resolution (keep same by default)
        let width = Int(videoTrack.naturalSize.width)
        let height = Int(videoTrack.naturalSize.height)

        // Create reader & writer
        let reader = try AVAssetReader(asset: asset)
        guard let writer = try? AVAssetWriter(outputURL: destination, fileType: .mp4) else {
            throw NSError(domain: "VideoCompression", code: -2, userInfo: [NSLocalizedDescriptionKey: "Cannot create AVAssetWriter"])
        }

        // Video settings for writer
        let videoCompressionProps: [String: Any] = [
            AVVideoAverageBitRateKey: targetBitrate,
            AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel
        ]

        let videoWriterSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: videoCompressionProps
        ]

        let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoWriterSettings)
        videoInput.expectsMediaDataInRealTime = false
        videoInput.transform = videoTrack.preferredTransform

        // Reader video output (decompressed CVPixelBuffers)
        let videoReaderSettings: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
        ]
        let videoOutput = AVAssetReaderTrackOutput(track: videoTrack, outputSettings: videoReaderSettings)
        videoOutput.alwaysCopiesSampleData = false

        // Add to reader/writer
        if reader.canAdd(videoOutput) { reader.add(videoOutput) }
        if writer.canAdd(videoInput) { writer.add(videoInput) }

        // Audio setup (if present)
        var audioInput: AVAssetWriterInput?
        var audioOutput: AVAssetReaderTrackOutput?

        if let aTrack = audioTrack {
            let audioWriterSettings: [String: Any] = [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: 44100,
                AVNumberOfChannelsKey: 2,
                AVEncoderBitRateKey: 128000
            ]
            audioInput = AVAssetWriterInput(mediaType: .audio, outputSettings: audioWriterSettings)
            audioInput?.expectsMediaDataInRealTime = false

            let audioReaderSettings: [String: Any] = [
                AVFormatIDKey: kAudioFormatLinearPCM
            ]
            audioOutput = AVAssetReaderTrackOutput(track: aTrack, outputSettings: audioReaderSettings)
            audioOutput?.alwaysCopiesSampleData = false

            if let ao = audioOutput, reader.canAdd(ao) { reader.add(ao) }
            if let ai = audioInput, writer.canAdd(ai) { writer.add(ai) }
        }

        // Prepare start
        writer.startWriting()
        reader.startReading()
        writer.startSession(atSourceTime: .zero)

        DispatchQueue.main.async {
            self.statusMessage = "Compressing..."
            self.progress = 0.01
        }

        // Use DispatchGroup to coordinate finish
        let group = DispatchGroup()

        // Track progress by presentation timestamp
        let durationSeconds = asset.duration.seconds > 0 ? asset.duration.seconds : Double(videoTrack.timeRange.duration.seconds)

        // VIDEO processing
        group.enter()
        let videoQueue = DispatchQueue(label: "videoQueue", qos: .userInitiated)
        videoInput.requestMediaDataWhenReady(on: videoQueue) {
            while videoInput.isReadyForMoreMediaData {
                if self.isCancelled {
                    reader.cancelReading()
                    writer.cancelWriting()
                    videoInput.markAsFinished()
                    group.leave()
                    return
                }

                if let sampleBuffer = videoOutput.copyNextSampleBuffer() {
                    // Append sample
                    if !videoInput.append(sampleBuffer) {
                        // Append failed; bail
                        print("video append failed: \(String(describing: writer.error))")
                        videoInput.markAsFinished()
                        group.leave()
                        return
                    }

                    // Update progress using presentation time
                    if let pts = sampleBuffer.presentationTimeStamp.seconds as Double? {
                        let p = min(max(pts / max(durationSeconds, 0.0001), 0.0), 1.0)
                        DispatchQueue.main.async {
                            // cap video contribution to 0.9 (audio will be last 10%)
                            self.progress = min(0.9, p * 0.9)
                        }
                    }
                } else {
                    videoInput.markAsFinished()
                    group.leave()
                    break
                }
            }
        }

        // AUDIO processing (if present)
        if let audioInput = audioInput, let audioOutput = audioOutput {
            group.enter()
            let audioQueue = DispatchQueue(label: "audioQueue", qos: .userInitiated)
            audioInput.requestMediaDataWhenReady(on: audioQueue) {
                while audioInput.isReadyForMoreMediaData {
                    if self.isCancelled {
                        reader.cancelReading()
                        writer.cancelWriting()
                        audioInput.markAsFinished()
                        group.leave()
                        return
                    }

                    if let sampleBuffer = audioOutput.copyNextSampleBuffer() {
                        if !audioInput.append(sampleBuffer) {
                            print("audio append failed: \(String(describing: writer.error))")
                            audioInput.markAsFinished()
                            group.leave()
                            return
                        }
                        // small progress bump for audio
                        DispatchQueue.main.async {
                            self.progress = max(self.progress, 0.92)
                        }
                    } else {
                        audioInput.markAsFinished()
                        group.leave()
                        break
                    }
                }
            }
        }

        // When both finished, finalize
        group.notify(queue: processingQueue) {
            // If cancelled already, just return
            if self.isCancelled {
                DispatchQueue.main.async {
                    self.isCompressing = false
                    self.statusMessage = "Cancelled"
                }
                return
            }

            writer.finishWriting {
                // Ensure reader finished well
                if reader.status == .failed {
                    DispatchQueue.main.async {
                        self.handleCompressionFailed(error: reader.error)
                    }
                    return
                }

                if writer.status == .completed {
                    // Get file size
                    do {
                        let attributes = try FileManager.default.attributesOfItem(atPath: destination.path)
                        if let fileSize = attributes[.size] as? Int64 {
                            self.compressedFileSizeBytes = fileSize
                            DispatchQueue.main.async {
                                self.compressedSize = self.formatFileSize(fileSize)
                                let savings = Double(max(0, self.originalFileSizeBytes - fileSize)) / Double(max(1, self.originalFileSizeBytes)) * 100
                                self.savingsPercentage = savings
                                self.isCompleted = true
                                self.isCompressing = false
                                self.progress = 1.0
                                self.statusMessage = "Compression complete!"
                                self.compressedVideoURL = destination
                                self.showNotification(title: "Compression Complete", body: "Your video has been compressed successfully!")
                            }
                        }
                    } catch {
                        DispatchQueue.main.async {
                            self.isCompressing = false
                            self.statusMessage = "Compression completed but failed to read file size"
                        }
                    }
                } else {
                    DispatchQueue.main.async {
                        self.handleCompressionFailed(error: writer.error)
                    }
                }
            }
        }
    }

    // MARK: - Helpers
    private func formatFileSize(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowedUnits = [.useAll]
        return formatter.string(fromByteCount: bytes)
    }

    private func showNotification(title: String, body: String) {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { granted, error in
            if granted {
                self.deliverNotification(title: title, body: body)
            }
        }
    }

    private func deliverNotification(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error { print("Notification error: \(error)") }
        }
    }

    private func handleCompressionFailed(error: Error?) {
        print("❌ Compression failed: \(error?.localizedDescription ?? "Unknown")")
        DispatchQueue.main.async {
            self.isCompressing = false
            self.statusMessage = "Failed"
            self.showNotification(title: "Compression Failed", body: error?.localizedDescription ?? "An unknown error occurred")
        }
    }
}
