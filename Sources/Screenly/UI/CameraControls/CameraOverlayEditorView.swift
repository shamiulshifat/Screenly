import SwiftUI

struct CameraOverlayEditorView: View {
    @Binding var layout: CameraOverlayLayout
    let shape: CameraShape

    @State private var dragStart: CameraOverlayLayout?

    var body: some View {
        GeometryReader { proxy in
            let width = max(proxy.size.width * layout.width, 24)
            let height = shape == .circle ? width : width * 0.65

            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.secondary.opacity(0.12))

                overlayShape
                    .fill(Color.blue.opacity(0.35))
                    .overlay(overlayShape.stroke(Color.blue, lineWidth: 2))
                    .frame(width: width, height: height)
                    .position(x: proxy.size.width * layout.x, y: proxy.size.height * layout.y)
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                if dragStart == nil {
                                    dragStart = layout
                                }
                                guard let start = dragStart else { return }
                                let nx = start.x + Double(value.translation.width / proxy.size.width)
                                let ny = start.y + Double(value.translation.height / proxy.size.height)
                                layout.x = min(max(nx, 0.05), 0.95)
                                layout.y = min(max(ny, 0.05), 0.95)
                            }
                            .onEnded { _ in
                                dragStart = nil
                            }
                    )
            }
        }
        .frame(height: 120)
    }

    private var overlayShape: AnyShape {
        switch shape {
        case .circle:
            return AnyShape(Circle())
        case .roundedRectangle:
            return AnyShape(RoundedRectangle(cornerRadius: 14))
        case .rectangle:
            return AnyShape(Rectangle())
        }
    }
}

struct AnyShape: Shape {
    private let pathBuilder: @Sendable (CGRect) -> Path

    init<S: Shape>(_ wrapped: S) {
        pathBuilder = { rect in
            wrapped.path(in: rect)
        }
    }

    func path(in rect: CGRect) -> Path {
        pathBuilder(rect)
    }
}
