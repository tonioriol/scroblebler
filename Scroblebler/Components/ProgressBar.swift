//
//  ProgressBar.swift
//  Scroblebler
//
//  Created by Victor Gama on 25/11/2022.
//

import SwiftUI
import AppKit
import Combine

struct ProgressBar: View {
    private let value: Double
    private let maxValue: Double
    private let backgroundEnabled: Bool
    private let backgroundColor: Color
    private let foregroundColor: Color
    private let onSeek: ((Double) -> Void)?
    @State private var animationMode: Animation?
    @State private var isDragging: Bool = false
    @State private var dragPosition: Double?
    @State private var appearanceToken = UUID()

    private var popoverWillHidePublisher: AnyPublisher<Notification, Never> {
        NotificationCenter.default
            .publisher(for: NSNotification.Name("ScrobleblerWillHide"))
            .eraseToAnyPublisher()
    }

    init(value: Double,
         maxValue: Double,
         backgroundEnabled: Bool = true,
         backgroundColor: Color = Color(.red),
         foregroundColor: Color = Color.red.opacity(0.3),
         onSeek: ((Double) -> Void)? = nil) {
        self.value = value
        self.maxValue = maxValue
        self.backgroundEnabled = backgroundEnabled
        self.backgroundColor = backgroundColor
        self.foregroundColor = foregroundColor
        self.onSeek = onSeek
    }

    var body: some View {
        GeometryReader { geometryReader in
            ZStack(alignment: .leading) {
                if self.backgroundEnabled {
                    Capsule()
                        .foregroundColor(self.backgroundColor)
                        .opacity(0.3)
                }

                Capsule()
                    .frame(
                        width: self.progress(
                            value: isDragging ? (dragPosition ?? value) : value,
                            maxValue: self.maxValue,
                            width: geometryReader.size.width
                        )
                    )
                    .foregroundColor(self.foregroundColor)
                    .animation(animationMode)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        if onSeek != nil {
                            isDragging = true
                            animationMode = nil

                            let width = geometryReader.size.width
                            guard width.isFinite, width > 0, maxValue.isFinite, maxValue > 0 else {
                                dragPosition = 0
                                return
                            }

                            let x = max(0, min(gesture.location.x, width))
                            let percentage = x / width
                            dragPosition = percentage * maxValue
                        }
                    }
                    .onEnded { gesture in
                        if let onSeek = onSeek {
                            let width = geometryReader.size.width
                            guard width.isFinite, width > 0, maxValue.isFinite, maxValue > 0 else {
                                isDragging = false
                                dragPosition = nil
                                animationMode = .easeIn
                                return
                            }

                            let x = max(0, min(gesture.location.x, width))
                            let percentage = x / width
                            let seekPosition = percentage * maxValue
                            onSeek(seekPosition)
                        }
                        isDragging = false
                        dragPosition = nil
                        animationMode = .easeIn
                    }
            )
        }
        .id(appearanceToken)
        .onAppear {
            // Avoid stacking multiple delayed Tasks (can cause intermittent duplicated rendering).
            animationMode = nil
            let token = UUID()
            appearanceToken = token
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard appearanceToken == token else { return }
                animationMode = .easeIn
            }
        }
        .onDisappear {
            // Cancel any pending delayed animation.
            appearanceToken = UUID()
            animationMode = nil
        }
        .onReceive(popoverWillHidePublisher, perform: { _ in
            animationMode = nil
        })
    }

    private func progress(value: Double,
                          maxValue: Double,
                          width: CGFloat) -> CGFloat {
        guard value.isFinite, maxValue.isFinite, maxValue > 0, width.isFinite, width > 0 else {
            return 0
        }

        let raw = value / maxValue
        let percentage = min(max(raw, 0), 1)
        return width * CGFloat(percentage)
    }
}
