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
        case .high: return 0.85      // 85% - minimal quality loss
        case .balanced: return 0.70  // 70% - good balance
        case .smaller: return 0.50   // 50% - more compression but still decent
        }
    }
}

final class BatchCompressionManager: NSObject, ObservableObject {
    // MARK: - Published state
    @Published var videoItems: [VideoItem] = []
    @Published var isProcessing: Bool = false
    @Published var overallProgress: Double = 0.0
    @Published var qualityPreset: QualityPreset = .balanced
    @Published var currentlyProcessing: String = ""
    
    // MARK: - Private
    private let processingQueue = DispatchQueue(label: "com.vlossless.batch", qos: .userInitiated)
    private var isCancelled = false
    private var currentReader: AVAssetReader?
    private var currentWriter: AVAssetWriter?
    
    // MARK: - File Selection
    func selectMultipleVideos() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            let panel = NSOpenPanel()
            panel.allowsMultipleSelection = true
            panel.canChooseDirectories = false
            panel.canChooseFiles = true
            panel.allowedContentTypes = [.movie, .video, .mpeg4Movie, .quickTimeMovie]
            panel.message = "Select videos to compress"
            
            panel.begin { response in
                if response == .OK {
                    self.addVideos(urls: panel.urls)
                }
            }
        }
    }
    
    func addVideos(urls: [URL]) {
        for url in urls {
            // Check if already added
            if videoItems.contains(where: { $0.sourceURL == url }) {
                continue
            }
            
            let item = VideoItem(url: url)
            videoItems.append(item)
            loadVideoInfo(for: item)
        }
    }
    
    func removeVideo(_ item: VideoItem) {
        videoItems.removeAll { $0.id == item.id }
    }
    
    func clearAll() {
        videoItems.removeAll()
        overallProgress = 0.0
        currentlyProcessing = ""
    }
    
    // MARK: - Video Info Loading
    private func loadVideoInfo(for item: VideoItem) {
        let asset = AVAsset(url: item.sourceURL)
        
        Task {
            do {
                // Load duration
                let duration = try await asset.load(.duration)
                await MainActor.run {
                    item.duration = CMTimeGetSeconds(duration)
                }
                
                // Load file size
                let attributes = try FileManager.default.attributesOfItem(atPath: item.sourceURL.path)
                if let fileSize = attributes[.size] as? Int64 {
                    let estimatedSize = Int64(Float(fileSize) * qualityPreset.compressionRatio)
                    await MainActor.run {
                        item.originalSize = fileSize
                        item.estimatedCompressedSize = estimatedSize
                    }
                }
            } catch {
                print("Error loading video info: \(error)")
            }
        }
    }
    
    // MARK: - Batch Compression
    func startBatchCompression() {
        guard !videoItems.isEmpty else { return }
        
        isProcessing = true
        isCancelled = false
        overallProgress = 0.0
        
        // Reset all items to pending
        for item in videoItems {
            if item.status != .completed {
                item.status = .pending
                item.progress = 0.0
            }
        }
        
        processingQueue.async { [weak self] in
            self?.processNextVideo()
        }
    }
    
    func cancelBatchCompression() {
        isCancelled = true
        currentReader?.cancelReading()
        currentWriter?.cancelWriting()
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.isProcessing = false
            self.currentlyProcessing = ""
            
            // Cancel all pending items
            for item in self.videoItems where item.status == .pending || item.status == .compressing {
                item.cancelCompression()
            }
        }
    }
    
    private func processNextVideo() {
        guard !isCancelled else {
            DispatchQueue.main.async { [weak self] in
                self?.isProcessing = false
            }
            return
        }
        
        // Find next pending video
        guard let nextItem = videoItems.first(where: { $0.status == .pending }) else {
            // All done
            DispatchQueue.main.async { [weak self] in
                self?.isProcessing = false
                self?.currentlyProcessing = ""
                self?.showNotification(title: "Batch Complete", body: "All videos compressed successfully!")
            }
            return
        }
        
        DispatchQueue.main.async { [weak self] in
            self?.currentlyProcessing = nextItem.fileName
            nextItem.startCompression()
        }
        
        // Compress this video
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("compressed_\(nextItem.id.uuidString).mp4")
        
        do {
            try compressVideo(item: nextItem, destination: outputURL)
            
            // Update overall progress
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                let completed = self.videoItems.filter { $0.status == .completed }.count
                self.overallProgress = Double(completed) / Double(self.videoItems.count)
            }
            
            // Process next
            processNextVideo()
        } catch {
            DispatchQueue.main.async {
                nextItem.failCompression(error: error.localizedDescription)
            }
            // Continue with next video even if one fails
            processNextVideo()
        }
    }
    
    // MARK: - Single Video Compression
    private func compressVideo(item: VideoItem, destination: URL) throws {
        try? FileManager.default.removeItem(at: destination)
        
        let asset = AVURLAsset(url: item.sourceURL)
        
        guard let videoTrack = asset.tracks(withMediaType: .video).first else {
            throw NSError(domain: "VideoCompression", code: -1,
                         userInfo: [NSLocalizedDescriptionKey: "No video track found"])
        }
        
        let audioTrack = asset.tracks(withMediaType: .audio).first
        
        // Calculate target bitrate
        let originalBitrate = max(videoTrack.estimatedDataRate, 500_000)
        let targetBitrate = Int(originalBitrate * qualityPreset.compressionRatio)
        
        // Create reader and writer
        let reader = try AVAssetReader(asset: asset)
        let writer = try AVAssetWriter(outputURL: destination, fileType: .mp4)
        
        self.currentReader = reader
        self.currentWriter = writer
        
        // Video settings
        let videoReaderSettings: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
        ]
        let videoOutput = AVAssetReaderTrackOutput(track: videoTrack, outputSettings: videoReaderSettings)
        videoOutput.alwaysCopiesSampleData = false
        
        let videoWriterSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: videoTrack.naturalSize.width,
            AVVideoHeightKey: videoTrack.naturalSize.height,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: targetBitrate,
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
                AVVideoMaxKeyFrameIntervalKey: 30
            ]
        ]
        let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoWriterSettings)
        videoInput.expectsMediaDataInRealTime = false
        
        reader.add(videoOutput)
        writer.add(videoInput)
        
        // Audio setup
        var audioInput: AVAssetWriterInput?
        var audioOutput: AVAssetReaderTrackOutput?
        
        if let aTrack = audioTrack {
            let audioReaderSettings: [String: Any] = [
                AVFormatIDKey: kAudioFormatLinearPCM
            ]
            audioOutput = AVAssetReaderTrackOutput(track: aTrack, outputSettings: audioReaderSettings)
            audioOutput?.alwaysCopiesSampleData = false
            
            let audioWriterSettings: [String: Any] = [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVNumberOfChannelsKey: 2,
                AVSampleRateKey: 44100,
                AVEncoderBitRateKey: 128000
            ]
            audioInput = AVAssetWriterInput(mediaType: .audio, outputSettings: audioWriterSettings)
            audioInput?.expectsMediaDataInRealTime = false
            
            if let ao = audioOutput { reader.add(ao) }
            if let ai = audioInput { writer.add(ai) }
        }
        
        writer.startWriting()
        reader.startReading()
        writer.startSession(atSourceTime: .zero)
        
        let group = DispatchGroup()
        let durationSeconds = asset.duration.seconds > 0 ? asset.duration.seconds : 1.0
        
        // Process video track
        group.enter()
        let videoQueue = DispatchQueue(label: "videoQueue", qos: .userInitiated)
        videoInput.requestMediaDataWhenReady(on: videoQueue) { [weak self] in
            guard let self = self else { return }
            
            while videoInput.isReadyForMoreMediaData {
                if self.isCancelled {
                    reader.cancelReading()
                    writer.cancelWriting()
                    videoInput.markAsFinished()
                    group.leave()
                    return
                }
                
                if let sampleBuffer = videoOutput.copyNextSampleBuffer() {
                    if !videoInput.append(sampleBuffer) {
                        videoInput.markAsFinished()
                        group.leave()
                        return
                    }
                    
                    // Update progress
                    if let pts = sampleBuffer.presentationTimeStamp.seconds as Double? {
                        let progress = min(pts / durationSeconds, 0.9)
                        DispatchQueue.main.async {
                            item.updateProgress(progress)
                        }
                    }
                } else {
                    videoInput.markAsFinished()
                    group.leave()
                    break
                }
            }
        }
        
        // Process audio track
        if let audioInput = audioInput, let audioOutput = audioOutput {
            group.enter()
            let audioQueue = DispatchQueue(label: "audioQueue", qos: .userInitiated)
            audioInput.requestMediaDataWhenReady(on: audioQueue) { [weak self] in
                guard let self = self else { return }
                
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
                            audioInput.markAsFinished()
                            group.leave()
                            return
                        }
                    } else {
                        audioInput.markAsFinished()
                        group.leave()
                        break
                    }
                }
            }
        }
        
        // Wait for completion
        group.wait()
        
        if isCancelled {
            throw NSError(domain: "VideoCompression", code: -2,
                         userInfo: [NSLocalizedDescriptionKey: "Cancelled by user"])
        }
        
        // Finish writing
        let semaphore = DispatchSemaphore(value: 0)
        var writeError: Error?
        
        writer.finishWriting {
            if writer.status == .completed {
                do {
                    let attributes = try FileManager.default.attributesOfItem(atPath: destination.path)
                    if let fileSize = attributes[.size] as? Int64 {
                        DispatchQueue.main.async {
                            item.completeCompression(compressedURL: destination, compressedSize: fileSize)
                        }
                    }
                } catch {
                    writeError = error
                }
            } else {
                writeError = writer.error ?? NSError(domain: "VideoCompression", code: -3,
                                                     userInfo: [NSLocalizedDescriptionKey: "Writer failed"])
            }
            semaphore.signal()
        }
        
        semaphore.wait()
        
        if let error = writeError {
            throw error
        }
    }
    
    // MARK: - Save All to Folder
    func saveAllToFolder() {
        let completedItems = videoItems.filter { $0.status == .completed && $0.compressedURL != nil }
        
        guard !completedItems.isEmpty else {
            showNotification(title: "No Videos", body: "No compressed videos to save")
            return
        }
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            let panel = NSOpenPanel()
            panel.canChooseDirectories = true
            panel.canChooseFiles = false
            panel.canCreateDirectories = true
            panel.message = "Choose folder to save compressed videos"
            panel.prompt = "Save Here"
            
            panel.begin { response in
                if response == .OK, let destinationFolder = panel.url {
                    self.saveFilesToFolder(items: completedItems, folder: destinationFolder)
                }
            }
        }
    }
    
    private func saveFilesToFolder(items: [VideoItem], folder: URL) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            var savedCount = 0
            var errors: [String] = []
            
            for item in items {
                guard let sourceURL = item.compressedURL else { continue }
                
                let fileName = item.fileName.replacingOccurrences(of: " ", with: "_")
                let destinationURL = folder.appendingPathComponent("compressed_\(fileName)")
                
                do {
                    // Remove existing file if present
                    if FileManager.default.fileExists(atPath: destinationURL.path) {
                        try FileManager.default.removeItem(at: destinationURL)
                    }
                    
                    // Copy compressed video
                    try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
                    savedCount += 1
                } catch {
                    errors.append("\(fileName): \(error.localizedDescription)")
                }
            }
            
            DispatchQueue.main.async {
                if errors.isEmpty {
                    self.showNotification(
                        title: "Videos Saved",
                        body: "Successfully saved \(savedCount) compressed video\(savedCount == 1 ? "" : "s")!"
                    )
                    NSWorkspace.shared.activateFileViewerSelecting([folder])
                } else {
                    self.showNotification(
                        title: "Partial Save",
                        body: "Saved \(savedCount) videos. \(errors.count) failed."
                    )
                }
            }
        }
    }
    
    // MARK: - Helpers
    private func showNotification(title: String, body: String) {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            if granted {
                let content = UNMutableNotificationContent()
                content.title = title
                content.body = body
                content.sound = .default
                
                let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
                UNUserNotificationCenter.current().add(request)
            }
        }
    }
}
