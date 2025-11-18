//
//  ContentView.swift
//  VLossLess
//
//  Created by IT SF GOC HYD on 18/11/25.
//

import SwiftUI
import AVFoundation
import UniformTypeIdentifiers

struct ContentView: View {
    @StateObject private var compressionManager = VideoCompressionManager()
    @State private var isDragging = false
    @State private var showingQualitySettings = false
    
    var body: some View {
        ZStack {
            // Background gradient
            LinearGradient(
                gradient: Gradient(colors: [
                    Color(red: 0.05, green: 0.05, blue: 0.15),
                    Color(red: 0.1, green: 0.05, blue: 0.2)
                ]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Header
                HeaderView()
                
                // Main content area
                if compressionManager.selectedVideo == nil {
                    DropZoneView(
                        isDragging: $isDragging,
                        onFileDrop: compressionManager.handleFileDrop
                    )
                } else {
                    VideoProcessingView(compressionManager: compressionManager)
                }
                
                // Footer with settings
                FooterView(
                    compressionManager: compressionManager,
                    showingQualitySettings: $showingQualitySettings
                )
            }
        }
        .frame(minWidth: 800, minHeight: 600)
        .sheet(isPresented: $showingQualitySettings) {
            QualitySettingsView(compressionManager: compressionManager)
        }
    }
}

// MARK: - Header View
struct HeaderView: View {
    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Image(systemName: "video.badge.waveform.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.purple, .blue],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                
                Text("VLossLess")
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                
                Spacer()
            }
            .padding(.horizontal, 30)
            .padding(.top, 30)
            
            HStack {
                Text("Professional Video Compression")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white.opacity(0.7))
                
                Spacer()
            }
            .padding(.horizontal, 30)
        }
        .padding(.bottom, 20)
    }
}

// MARK: - Drop Zone View
struct DropZoneView: View {
    @Binding var isDragging: Bool
    let onFileDrop: (URL) -> Void
    
    var body: some View {
        VStack(spacing: 30) {
            ZStack {
                RoundedRectangle(cornerRadius: 20)
                    .strokeBorder(
                        style: StrokeStyle(lineWidth: 3, dash: [10])
                    )
                    .foregroundColor(isDragging ? .blue : .white.opacity(0.3))
                    .background(
                        RoundedRectangle(cornerRadius: 20)
                            .fill(isDragging ? Color.blue.opacity(0.1) : Color.white.opacity(0.05))
                    )
                    .animation(.easeInOut(duration: 0.2), value: isDragging)
                
                VStack(spacing: 20) {
                    Image(systemName: "arrow.down.doc.fill")
                        .font(.system(size: 60))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.purple, .blue],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    
                    VStack(spacing: 8) {
                        Text("Drop your video here")
                            .font(.system(size: 24, weight: .semibold))
                            .foregroundColor(.white)
                        
                        Text("or click to browse")
                            .font(.system(size: 16))
                            .foregroundColor(.white.opacity(0.6))
                    }
                    
                    Text("Supports MP4, MOV, AVI, MKV")
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.4))
                        .padding(.top, 10)
                }
                .padding(40)
            }
            .frame(maxWidth: 600, maxHeight: 400)
            .padding(.horizontal, 40)
            .onDrop(of: [.fileURL], isTargeted: $isDragging) { providers in
                providers.first?.loadDataRepresentation(forTypeIdentifier: UTType.fileURL.identifier) { data, error in
                    guard let data = data,
                          let path = String(data: data, encoding: .utf8),
                          let url = URL(string: path) else { return }
                    
                    DispatchQueue.main.async {
                        onFileDrop(url)
                    }
                }
                return true
            }
            .onTapGesture {
                selectFile(onFileDrop: onFileDrop)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private func selectFile(onFileDrop: @escaping (URL) -> Void) {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.movie, .video, .mpeg4Movie, .quickTimeMovie, .avi]
        
        if panel.runModal() == .OK, let url = panel.url {
            onFileDrop(url)
        }
    }
}

// MARK: - Video Processing View
struct VideoProcessingView: View {
    @ObservedObject var compressionManager: VideoCompressionManager
    
    var body: some View {
        VStack(spacing: 30) {
            // Video info card
            VideoInfoCard(compressionManager: compressionManager)
            
            // Progress section
            if compressionManager.isCompressing {
                CompressionProgressView(compressionManager: compressionManager)
            }
            
            // Action buttons
            HStack(spacing: 20) {
                if !compressionManager.isCompressing && !compressionManager.isCompleted {
                    Button(action: {
                        compressionManager.startCompression()
                    }) {
                        HStack {
                            Image(systemName: "play.fill")
                            Text("Start Compression")
                                .fontWeight(.semibold)
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(
                            LinearGradient(
                                colors: [.blue, .purple],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .foregroundColor(.white)
                        .cornerRadius(12)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
                
                if compressionManager.isCompleted {
                    Button(action: {
                        compressionManager.saveCompressedVideo()
                    }) {
                        HStack {
                            Image(systemName: "square.and.arrow.down.fill")
                            Text("Save Compressed Video")
                                .fontWeight(.semibold)
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.green)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
                
                Button(action: {
                    compressionManager.reset()
                }) {
                    HStack {
                        Image(systemName: "arrow.counterclockwise")
                        Text("New Video")
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.white.opacity(0.1))
                    .foregroundColor(.white)
                    .cornerRadius(12)
                }
                .buttonStyle(PlainButtonStyle())
            }
            .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.vertical, 20)
    }
}

// MARK: - Video Info Card
struct VideoInfoCard: View {
    @ObservedObject var compressionManager: VideoCompressionManager
    
    var body: some View {
        VStack(spacing: 20) {
            HStack {
                Image(systemName: "film.fill")
                    .font(.system(size: 24))
                    .foregroundColor(.blue)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(compressionManager.selectedVideo?.lastPathComponent ?? "Unknown")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.white)
                    
                    if let duration = compressionManager.videoDuration {
                        Text("Duration: \(formatDuration(duration))")
                            .font(.system(size: 14))
                            .foregroundColor(.white.opacity(0.6))
                    }
                }
                
                Spacer()
            }
            
            Divider()
                .background(Color.white.opacity(0.2))
            
            HStack(spacing: 40) {
                StatView(
                    icon: "doc.fill",
                    title: "Original Size",
                    value: compressionManager.originalSize,
                    color: .orange
                )
                
                Image(systemName: "arrow.right")
                    .foregroundColor(.white.opacity(0.4))
                
                StatView(
                    icon: "doc.badge.arrow.up.fill",
                    title: compressionManager.isCompleted ? "Compressed Size" : "Estimated Size",
                    value: compressionManager.compressedSize,
                    color: .green
                )
                
                if let savings = compressionManager.savingsPercentage {
                    VStack(spacing: 8) {
                        Image(systemName: "chart.line.downtrend.xyaxis")
                            .font(.system(size: 24))
                            .foregroundColor(.purple)
                        
                        Text("\(String(format: "%.1f", savings))%")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundColor(.purple)
                        
                        Text("Saved")
                            .font(.system(size: 12))
                            .foregroundColor(.white.opacity(0.6))
                    }
                }
            }
        }
        .padding(30)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white.opacity(0.08))
        )
        .padding(.horizontal, 40)
    }
    
    private func formatDuration(_ seconds: Double) -> String {
        let minutes = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", minutes, secs)
    }
}

// MARK: - Stat View
struct StatView: View {
    let icon: String
    let title: String
    let value: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 24))
                .foregroundColor(color)
            
            Text(value)
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(.white)
            
            Text(title)
                .font(.system(size: 12))
                .foregroundColor(.white.opacity(0.6))
        }
    }
}

// MARK: - Compression Progress View
struct CompressionProgressView: View {
    @ObservedObject var compressionManager: VideoCompressionManager
    
    var body: some View {
        VStack(spacing: 16) {
            Text(compressionManager.statusMessage.isEmpty ? "Compressing..." : compressionManager.statusMessage)
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(.white)
            
            ProgressView(value: compressionManager.progress)
                .progressViewStyle(LinearProgressViewStyle(tint: .blue))
                .scaleEffect(x: 1, y: 2, anchor: .center)
            
            HStack(spacing: 12) {
                Text("\(Int(compressionManager.progress * 100))%")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.white.opacity(0.8))
                
                if compressionManager.progress > 0.01 && compressionManager.progress < 0.90 {
                    Text("•")
                        .foregroundColor(.white.opacity(0.4))
                    
                    Text(estimatedTimeRemaining())
                        .font(.system(size: 14))
                        .foregroundColor(.white.opacity(0.6))
                }
            }
        }
        .padding(30)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white.opacity(0.08))
        )
        .padding(.horizontal, 40)
    }
    
    private func estimatedTimeRemaining() -> String {
        guard let duration = compressionManager.videoDuration,
              compressionManager.progress > 0.05 else {
            return "Estimating..."
        }
        
        // Rough estimate: compression typically takes 0.5-1x the video duration
        let estimatedTotal = duration * 0.7 // Assume 0.7x duration for compression
        let elapsed = estimatedTotal * compressionManager.progress
        let remaining = max(0, estimatedTotal - elapsed)
        
        if remaining < 60 {
            return "\(Int(remaining))s remaining"
        } else {
            return "\(Int(remaining / 60))m \(Int(remaining.truncatingRemainder(dividingBy: 60)))s remaining"
        }
    }
}

// MARK: - Footer View
struct FooterView: View {
    @ObservedObject var compressionManager: VideoCompressionManager
    @Binding var showingQualitySettings: Bool
    
    var body: some View {
        HStack {
            Button(action: {
                showingQualitySettings = true
            }) {
                HStack {
                    Image(systemName: "slider.horizontal.3")
                    Text("Quality: \(compressionManager.qualityPreset.rawValue)")
                }
                .foregroundColor(.white.opacity(0.7))
                .padding(12)
                .background(Color.white.opacity(0.1))
                .cornerRadius(8)
            }
            .buttonStyle(PlainButtonStyle())
            
            Spacer()
            
            Text("Codec: H.265/HEVC")
                .font(.system(size: 12))
                .foregroundColor(.white.opacity(0.5))
        }
        .padding(.horizontal, 30)
        .padding(.vertical, 20)
    }
}

// MARK: - Quality Settings View
struct QualitySettingsView: View {
    @ObservedObject var compressionManager: VideoCompressionManager
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Compression Quality")
                .font(.system(size: 24, weight: .bold))
            
            VStack(spacing: 16) {
                ForEach(QualityPreset.allCases, id: \.self) { preset in
                    QualityOptionButton(
                        preset: preset,
                        isSelected: compressionManager.qualityPreset == preset,
                        action: {
                            compressionManager.qualityPreset = preset
                        }
                    )
                }
            }
            
            Button("Done") {
                dismiss()
            }
            .buttonStyle(.borderedProminent)
            .padding(.top, 20)
        }
        .padding(30)
        .frame(width: 400)
    }
}

// MARK: - Quality Option Button
struct QualityOptionButton: View {
    let preset: QualityPreset
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(preset.rawValue)
                        .font(.system(size: 16, weight: .semibold))
                    Text(preset.description)
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.blue)
                }
            }
            .padding()
            .background(isSelected ? Color.blue.opacity(0.1) : Color.gray.opacity(0.1))
            .cornerRadius(12)
        }
        .buttonStyle(PlainButtonStyle())
    }
}



#Preview {
    ContentView()
}
