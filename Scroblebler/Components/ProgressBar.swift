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
                    .frame(width: self.progress(value: isDragging ? (dragPosition ?? value) : value,
                                                maxValue: self.maxValue,
                                                width: geometryReader.size.width))
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
                            let x = max(0, min(gesture.location.x, geometryReader.size.width))
                            let percentage = x / geometryReader.size.width
                            dragPosition = percentage * maxValue
                        }
                    }
                    .onEnded { gesture in
                        if let onSeek = onSeek {
                            let x = max(0, min(gesture.location.x, geometryReader.size.width))
                            let percentage = x / geometryReader.size.width
                            let seekPosition = percentage * maxValue
                            onSeek(seekPosition)
                        }
                        isDragging = false
                        dragPosition = nil
                        animationMode = .easeIn
                    }
            )
        }
        .onAppear {
            Task {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                animationMode = .easeIn
            }
        }
        .onReceive(popoverWillHidePublisher, perform: { _ in
            animationMode = nil
        })
    }

    private func progress(value: Double,
                          maxValue: Double,
                          width: CGFloat) -> CGFloat {
        let percentage = value / maxValue
        return width * CGFloat(percentage)
    }
}
