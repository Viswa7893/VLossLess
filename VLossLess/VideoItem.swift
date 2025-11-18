//
//  VideoItem.swift
//  VLossLess
//
//  Created by IT SF GOC HYD on 18/11/25.
//

import Foundation
import Combine

enum CompressionStatus {
    case pending
    case compressing
    case completed
    case failed
    case cancelled
    
    var displayText: String {
        switch self {
        case .pending: return "Waiting..."
        case .compressing: return "Compressing..."
        case .completed: return "Completed"
        case .failed: return "Failed"
        case .cancelled: return "Cancelled"
        }
    }
    
    var color: String {
        switch self {
        case .pending: return "gray"
        case .compressing: return "blue"
        case .completed: return "green"
        case .failed: return "red"
        case .cancelled: return "orange"
        }
    }
}

class VideoItem: Identifiable, ObservableObject {
    let id = UUID()
    let sourceURL: URL
    
    @Published var fileName: String
    @Published var duration: Double = 0.0
    @Published var originalSize: Int64 = 0
    @Published var estimatedCompressedSize: Int64 = 0
    @Published var actualCompressedSize: Int64 = 0
    @Published var progress: Double = 0.0
    @Published var status: CompressionStatus = .pending
    @Published var estimatedTimeRemaining: String = "Calculating..."
    @Published var compressedURL: URL?
    @Published var errorMessage: String?
    
    // For time estimation
    private var compressionStartTime: Date?
    private var lastProgressUpdate: Date?
    private var lastProgress: Double = 0.0
    
    init(url: URL) {
        self.sourceURL = url
        self.fileName = url.lastPathComponent
    }
    
    func startCompression() {
        compressionStartTime = Date()
        lastProgressUpdate = Date()
        lastProgress = 0.0
        status = .compressing
    }
    
    func updateProgress(_ newProgress: Double) {
        progress = newProgress
        
        // Calculate estimated time remaining
        guard let startTime = compressionStartTime else { return }
        
        let now = Date()
        let elapsed = now.timeIntervalSince(startTime)
        
        if newProgress > 0.01 {
            let totalEstimated = elapsed / newProgress
            let remaining = totalEstimated - elapsed
            estimatedTimeRemaining = formatTimeRemaining(remaining)
        }
        
        lastProgressUpdate = now
        lastProgress = newProgress
    }
    
    func completeCompression(compressedURL: URL, compressedSize: Int64) {
        self.compressedURL = compressedURL
        self.actualCompressedSize = compressedSize
        self.progress = 1.0
        self.status = .completed
        self.estimatedTimeRemaining = "Done"
    }
    
    func failCompression(error: String) {
        self.status = .failed
        self.errorMessage = error
        self.estimatedTimeRemaining = "Failed"
    }
    
    func cancelCompression() {
        self.status = .cancelled
        self.estimatedTimeRemaining = "Cancelled"
    }
    
    private func formatTimeRemaining(_ seconds: TimeInterval) -> String {
        if seconds < 0 { return "Calculating..." }
        
        let totalSeconds = Int(seconds)
        let minutes = totalSeconds / 60
        let secs = totalSeconds % 60
        
        if minutes > 0 {
            return "\(minutes)m \(secs)s remaining"
        } else {
            return "\(secs)s remaining"
        }
    }
    
    var formattedOriginalSize: String {
        return formatFileSize(originalSize)
    }
    
    var formattedEstimatedSize: String {
        return formatFileSize(estimatedCompressedSize)
    }
    
    var formattedActualSize: String {
        return formatFileSize(actualCompressedSize)
    }
    
    var savingsPercentage: Double {
        guard originalSize > 0 else { return 0 }
        let size = actualCompressedSize > 0 ? actualCompressedSize : estimatedCompressedSize
        return Double(originalSize - size) / Double(originalSize) * 100
    }
    
    private func formatFileSize(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowedUnits = [.useAll]
        return formatter.string(fromByteCount: bytes)
    }
}
