//
//  ContentView.swift
//  VLossLess - Enhanced with Stunning Animations
//

import SwiftUI
import AVFoundation
import UniformTypeIdentifiers

struct MainVideoView: View {
    @StateObject private var batchManager = BatchCompressionManager()
    @State private var isDragging = false
    @State private var showingQualitySettings = false
    @State private var animateBackground = false
    
    var body: some View {
        ZStack {
            // Animated background
            AnimatedGradientBackground(isAnimating: $animateBackground)
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Header
                HeaderView()
                    .padding(.bottom, 20)
                
                // Main content area
                if batchManager.videoItems.isEmpty {
                    EmptyStateView(onSelectFiles: {
                        batchManager.selectMultipleVideos()
                    })
                } else {
                    VideoListView(batchManager: batchManager)
                }
                
                // Footer with controls
                FooterControlsView(
                    batchManager: batchManager,
                    showingQualitySettings: $showingQualitySettings
                )
            }
        }
        .frame(minWidth: 1000, minHeight: 700)
        .sheet(isPresented: $showingQualitySettings) {
            QualitySettingsView(batchManager: batchManager)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true)) {
                animateBackground = true
            }
        }
    }
}

// MARK: - Animated Background
struct AnimatedGradientBackground: View {
    @Binding var isAnimating: Bool
    
    var body: some View {
        ZStack {
            LinearGradient(
                gradient: Gradient(colors: [
                    Color(red: 0.05, green: 0.05, blue: 0.15),
                    Color(red: 0.1, green: 0.05, blue: 0.2)
                ]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            
            RadialGradient(
                gradient: Gradient(colors: [
                    Color.purple.opacity(isAnimating ? 0.3 : 0.1),
                    Color.clear
                ]),
                center: .topLeading,
                startRadius: 0,
                endRadius: 600
            )
            .animation(.easeInOut(duration: 3).repeatForever(autoreverses: true), value: isAnimating)
            
            RadialGradient(
                gradient: Gradient(colors: [
                    Color.blue.opacity(isAnimating ? 0.2 : 0.05),
                    Color.clear
                ]),
                center: .bottomTrailing,
                startRadius: 0,
                endRadius: 500
            )
            .animation(.easeInOut(duration: 4).repeatForever(autoreverses: true), value: isAnimating)
        }
    }
}

// MARK: - Header
struct HeaderView: View {
    @State private var glowAnimation = false
    
    var body: some View {
        VStack(spacing: 8) {
            HStack {
                ZStack {
                    Image(systemName: "video.badge.waveform.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.purple, .blue],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .blur(radius: glowAnimation ? 8 : 4)
                        .opacity(0.7)
                    
                    Image(systemName: "video.badge.waveform.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.purple, .blue],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }
                .animation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true), value: glowAnimation)
                .onAppear { glowAnimation = true }
                
                Text("VLossLess")
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.white, .white.opacity(0.8)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                
                Spacer()
            }
            .padding(.horizontal, 30)
            .padding(.top, 30)
            
            HStack {
                Text("Batch Video Compression")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white.opacity(0.7))
                
                Spacer()
            }
            .padding(.horizontal, 30)
        }
    }
}

// MARK: - Empty State
struct EmptyStateView: View {
    @State private var pulseAnimation = false
    let onSelectFiles: () -> Void
    
    var body: some View {
        VStack(spacing: 30) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [.purple.opacity(0.2), .blue.opacity(0.2)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 120, height: 120)
                    .scaleEffect(pulseAnimation ? 1.1 : 1.0)
                    .opacity(pulseAnimation ? 0.5 : 1.0)
                    .animation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true), value: pulseAnimation)
                
                Image(systemName: "plus.rectangle.on.folder.fill")
                    .font(.system(size: 60))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.purple, .blue, .cyan],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
            .onAppear { pulseAnimation = true }
            
            VStack(spacing: 12) {
                Text("Add Videos to Compress")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundColor(.white)
                
                Text("Select multiple videos to batch compress")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.white.opacity(0.6))
            }
            
            Button(action: onSelectFiles) {
                HStack(spacing: 10) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 18))
                    Text("Select Videos")
                        .font(.system(size: 18, weight: .bold))
                }
                .foregroundColor(.white)
                .frame(width: 200, height: 50)
                .background(
                    LinearGradient(
                        colors: [.purple, .blue],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .cornerRadius(14)
                .shadow(color: .blue.opacity(0.5), radius: 20)
            }
            .buttonStyle(PlainButtonStyle())
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Video List View
struct VideoListView: View {
    @ObservedObject var batchManager: BatchCompressionManager
    
    var body: some View {
        VStack(spacing: 16) {
            // Overall progress
            if batchManager.isProcessing {
                HStack(spacing: 12) {
                    ProgressView(value: batchManager.overallProgress)
                        .progressViewStyle(LinearProgressViewStyle(tint: .blue))
                        .frame(maxWidth: .infinity)
                    
                    Text("\(Int(batchManager.overallProgress * 100))%")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.white)
                        .frame(width: 50)
                }
                .padding(.horizontal, 30)
                
                if !batchManager.currentlyProcessing.isEmpty {
                    Text("Processing: \(batchManager.currentlyProcessing)")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.white.opacity(0.7))
                        .padding(.horizontal, 30)
                }
            }
            
            // Video list
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(batchManager.videoItems) { item in
                        VideoItemRow(item: item, onRemove: {
                            if !batchManager.isProcessing {
                                batchManager.removeVideo(item)
                            }
                        })
                    }
                }
                .padding(.horizontal, 30)
                .padding(.vertical, 16)
            }
        }
    }
}

// MARK: - Video Item Row
struct VideoItemRow: View {
    @ObservedObject var item: VideoItem
    let onRemove: () -> Void
    
    var body: some View {
        HStack(spacing: 16) {
            // Circular Progress
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.1), lineWidth: 6)
                    .frame(width: 70, height: 70)
                
                Circle()
                    .trim(from: 0, to: item.progress)
                    .stroke(
                        LinearGradient(
                            colors: statusColor,
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        style: StrokeStyle(lineWidth: 6, lineCap: .round)
                    )
                    .frame(width: 70, height: 70)
                    .rotationEffect(.degrees(-90))
                    .animation(.easeOut, value: item.progress)
                
                if item.status == .completed {
                    Image(systemName: "checkmark")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(.green)
                } else if item.status == .failed {
                    Image(systemName: "xmark")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(.red)
                } else {
                    Text("\(Int(item.progress * 100))%")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.white)
                }
            }
            
            // Video Info
            VStack(alignment: .leading, spacing: 6) {
                Text(item.fileName)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                
                HStack(spacing: 12) {
                    Label(formatDuration(item.duration), systemImage: "clock")
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.6))
                    
                    Label(item.formattedOriginalSize, systemImage: "doc")
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.6))
                }
                
                HStack(spacing: 8) {
                    if item.status == .completed {
                        Text("Compressed: \(item.formattedActualSize)")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.green)
                        
                        Text("(\(String(format: "%.1f", item.savingsPercentage))% saved)")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.green.opacity(0.8))
                    } else {
                        Text("Est. size: \(item.formattedEstimatedSize)")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.white.opacity(0.5))
                    }
                }
                
                // Status and time
                HStack(spacing: 8) {
                    Text(item.status.displayText)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(statusTextColor)
                    
                    if item.status == .compressing {
                        Text("• \(item.estimatedTimeRemaining)")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.white.opacity(0.6))
                    }
                }
            }
            
            Spacer()
            
            // Remove button
            if item.status != .compressing {
                Button(action: onRemove) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundColor(.white.opacity(0.5))
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                )
        )
    }
    
    private var statusColor: [Color] {
        switch item.status {
        case .pending: return [.gray, .gray.opacity(0.5)]
        case .compressing: return [.blue, .purple]
        case .completed: return [.green, .mint]
        case .failed: return [.red, .orange]
        case .cancelled: return [.orange, .yellow]
        }
    }
    
    private var statusTextColor: Color {
        switch item.status {
        case .pending: return .gray
        case .compressing: return .blue
        case .completed: return .green
        case .failed: return .red
        case .cancelled: return .orange
        }
    }
    
    private func formatDuration(_ seconds: Double) -> String {
        guard seconds > 0 else { return "0:00" }
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", mins, secs)
    }
}

// MARK: - Footer Controls
struct FooterControlsView: View {
    @ObservedObject var batchManager: BatchCompressionManager
    @Binding var showingQualitySettings: Bool
    @State private var hoveredButton: String?
    
    var body: some View {
        VStack(spacing: 16) {
            Divider()
                .background(Color.white.opacity(0.1))
            
            // Action buttons
            HStack(spacing: 12) {
                if !batchManager.videoItems.isEmpty && !batchManager.isProcessing {
                    ActionButton(
                        icon: "plus.circle.fill",
                        title: "Add More",
                        gradient: [.white.opacity(0.2), .white.opacity(0.1)],
                        isHovered: hoveredButton == "add"
                    ) {
                        batchManager.selectMultipleVideos()
                    }
                    .onHover { hoveredButton = $0 ? "add" : nil }
                    
                    ActionButton(
                        icon: "trash.fill",
                        title: "Clear All",
                        gradient: [.red.opacity(0.3), .red.opacity(0.2)],
                        isHovered: hoveredButton == "clear"
                    ) {
                        batchManager.clearAll()
                    }
                    .onHover { hoveredButton = $0 ? "clear" : nil }
                }
                
                Spacer()
                
                if batchManager.isProcessing {
                    ActionButton(
                        icon: "stop.fill",
                        title: "Cancel",
                        gradient: [.orange, .red],
                        isHovered: hoveredButton == "cancel"
                    ) {
                        batchManager.cancelBatchCompression()
                    }
                    .onHover { hoveredButton = $0 ? "cancel" : nil }
                } else if !batchManager.videoItems.isEmpty {
                    let hasCompleted = batchManager.videoItems.contains { $0.status == .completed }
                    
                    ActionButton(
                        icon: "play.fill",
                        title: "Start Compressing",
                        gradient: [.blue, .purple],
                        isHovered: hoveredButton == "start"
                    ) {
                        batchManager.startBatchCompression()
                    }
                    .onHover { hoveredButton = $0 ? "start" : nil }
                    
                    if hasCompleted {
                        ActionButton(
                            icon: "arrow.down.doc.fill",
                            title: "Save as ZIP",
                            gradient: [.green, .mint],
                            isHovered: hoveredButton == "save"
                        ) {
                            batchManager.saveAllAsZip()
                        }
                        .onHover { hoveredButton = $0 ? "save" : nil }
                    }
                }
            }
            .padding(.horizontal, 30)
            
            // Quality settings
            HStack {
                Button(action: {
                    showingQualitySettings = true
                }) {
                    HStack(spacing: 8) {
                        Image(systemName: "slider.horizontal.3")
                        Text("Quality: \(batchManager.qualityPreset.rawValue)")
                    }
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white.opacity(0.8))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(
                        Capsule()
                            .fill(.ultraThinMaterial)
                            .overlay(
                                Capsule().stroke(Color.white.opacity(0.2), lineWidth: 1)
                            )
                    )
                }
                .buttonStyle(PlainButtonStyle())
                .disabled(batchManager.isProcessing)
                
                Spacer()
                
                Text("Codec: H.264")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white.opacity(0.5))
            }
            .padding(.horizontal, 30)
        }
        .padding(.vertical, 20)
    }
}

// MARK: - Action Button
struct ActionButton: View {
    let icon: String
    let title: String
    let gradient: [Color]
    let isHovered: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                Text(title)
                    .font(.system(size: 14, weight: .bold))
            }
            .foregroundColor(.white)
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: gradient,
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .overlay(
                        Capsule().stroke(Color.white.opacity(0.2), lineWidth: 1)
                    )
            )
            .shadow(color: isHovered ? gradient.first?.opacity(0.5) ?? .clear : .clear, radius: 15)
            .scaleEffect(isHovered ? 1.05 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isHovered)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Quality Settings View
struct QualitySettingsView: View {
    @ObservedObject var batchManager: BatchCompressionManager
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        VStack(spacing: 24) {
            Text("Compression Quality")
                .font(.system(size: 28, weight: .bold))
                .foregroundColor(.primary)
            
            VStack(spacing: 16) {
                ForEach(QualityPreset.allCases, id: \.self) { preset in
                    QualityOptionButton(
                        preset: preset,
                        isSelected: batchManager.qualityPreset == preset,
                        action: {
                            batchManager.qualityPreset = preset
                        }
                    )
                }
            }
            
            Button("Done") {
                dismiss()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.top, 20)
        }
        .padding(40)
        .frame(width: 450)
    }
}

// MARK: - Quality Option Button
struct QualityOptionButton: View {
    let preset: QualityPreset
    let isSelected: Bool
    let action: () -> Void
    @State private var isHovered = false
    
    var body: some View {
        Button(action: action) {
            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    Text(preset.rawValue)
                        .font(.system(size: 17, weight: .bold))
                    Text(preset.description)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 24))
                        .foregroundColor(.blue)
                }
            }
            .padding(18)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(isSelected ? Color.blue.opacity(0.15) : (isHovered ? Color.gray.opacity(0.15) : Color.gray.opacity(0.08)))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(isSelected ? Color.blue.opacity(0.5) : Color.clear, lineWidth: 2)
            )
            .scaleEffect(isHovered ? 1.02 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isHovered)
        }
        .buttonStyle(PlainButtonStyle())
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

#Preview {
    MainVideoView()
}
