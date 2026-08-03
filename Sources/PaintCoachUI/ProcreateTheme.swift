#if canImport(UIKit)
import SwiftUI

/// Colours, metrics, and icon names measured from the reference screenshots.
///
/// Everything the chrome draws routes through here so a value can be corrected
/// in one place after seeing it on a device.
///
/// Screenshots are 1440x1080 for a 1024x768pt landscape iPad, so measured
/// pixels were divided by 1.40625 to reach the point values below.
public enum PC {

    // MARK: - Colour

    /// Top bar. Slightly darker than the canvas backdrop.
    public static let topBar = Color(white: 0.118)
    /// The grid area surrounding the canvas.
    public static let backdrop = Color(white: 0.157)
    /// Grid rule over `backdrop` — barely visible, as in the screenshots.
    public static let grid = Color.white.opacity(0.035)
    /// Floating panels (brush library, layers, menus).
    public static let panel = Color(white: 0.173)
    /// Inset rows inside panels.
    public static let panelRow = Color(white: 0.216)
    /// The left size/opacity slider column.
    public static let sidebar = Color(white: 0.106)
    /// Slider troughs.
    public static let trough = Color.white.opacity(0.10)
    /// Slider thumbs.
    public static let thumb = Color(white: 0.78)
    /// Selection blue.
    public static let accent = Color(red: 0.04, green: 0.52, blue: 1.0)
    /// Idle icon grey.
    public static let icon = Color(white: 0.62)
    /// Disabled icon grey.
    public static let iconDim = Color(white: 0.34)

    // MARK: - Metric

    public static let topBarHeight: CGFloat = 33
    public static let topButton: CGFloat = 26
    public static let topIconSize: CGFloat = 17
    public static let colorWell: CGFloat = 22
    public static let galleryFont: CGFloat = 18

    public static let sidebarWidth: CGFloat = 38
    public static let sliderTrack: CGFloat = 25
    public static let sliderLength: CGFloat = 124
    public static let sidebarCorner: CGFloat = 12

    public static let panelCorner: CGFloat = 14
    public static let rowCorner: CGFloat = 8

    // MARK: - Icons

    // Grouped so a symbol that reads wrong on device can be swapped centrally.
    public static let iconActions = "wrench.and.screwdriver.fill"
    public static let iconAdjust = "wand.and.stars"
    public static let iconSelect = "lasso"
    public static let iconTransform = "arrow.up.right"
    public static let iconBrush = "paintbrush.pointed.fill"
    public static let iconSmudge = "hand.draw.fill"
    public static let iconEraser = "eraser.fill"
    public static let iconLayers = "square.on.square"
    public static let iconUndo = "arrow.uturn.backward"
    public static let iconRedo = "arrow.uturn.forward"

    /// Procreate's stock brush set names, in the order the screenshots show them.
    public static let brushSets = [
        "Recent", "Pencils", "Pens", "Inks", "Markers", "Pastels", "Oils",
        "Paints", "Gouache", "Watercolors", "Charcoals", "Basics", "Lettering",
        "Comics", "Design"
    ]
}

// MARK: - Which panel is open

/// Exactly one panel is visible at a time, matching Procreate's behaviour.
public enum PCPanel: Equatable {
    case none
    case actions
    case adjustments
    case selection
    case transform
    case brushLibrary
    case layers
    case color
}

/// The three paint tools on the right of the top bar.
public enum PCTool: Equatable {
    case brush, smudge, eraser
}

// MARK: - Primitives

/// The faint grid the canvas floats on.
struct PCGridBackdrop: View {
    var body: some View {
        Canvas { context, size in
            let step: CGFloat = 22
            var path = Path()
            var x: CGFloat = 0
            while x <= size.width {
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: size.height))
                x += step
            }
            var y: CGFloat = 0
            while y <= size.height {
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: size.width, y: y))
                y += step
            }
            context.stroke(path, with: .color(PC.grid), lineWidth: 1)
        }
        .background(PC.backdrop)
        .ignoresSafeArea()
    }
}

/// Procreate's vertical slider: rounded trough, pill thumb, drag anywhere.
struct PCVerticalSlider: View {
    @Binding var value: Double
    var range: ClosedRange<Double> = 0...1

    private let thumbHeight: CGFloat = 15

    var body: some View {
        GeometryReader { geo in
            let height = geo.size.height
            let span = range.upperBound - range.lowerBound
            let fraction = span > 0
                ? (value - range.lowerBound) / span
                : 0
            let travel = height - thumbHeight

            ZStack(alignment: .bottom) {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(PC.trough)

                Capsule()
                    .fill(PC.thumb)
                    .frame(height: thumbHeight)
                    .offset(y: -CGFloat(fraction) * travel)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        // Slider grows upward, so invert the y axis.
                        let raw = 1 - (drag.location.y / max(height, 1))
                        let clamped = min(max(raw, 0), 1)
                        value = range.lowerBound + Double(clamped) * span
                    }
            )
        }
        .frame(width: PC.sliderTrack, height: PC.sliderLength)
    }
}

/// A circular top-bar button that fills blue while its panel is open.
struct PCCircleButton: View {
    let symbol: String
    let isActive: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(isActive ? PC.accent : Color.white.opacity(0.09))
                Image(systemName: symbol)
                    .font(.system(size: PC.topIconSize * 0.62, weight: .medium))
                    .foregroundStyle(isActive ? Color.white : PC.icon)
            }
            .frame(width: PC.topButton, height: PC.topButton)
        }
        .buttonStyle(.plain)
    }
}

/// A bare top-bar icon that tints blue when its tool or panel is active.
struct PCBarIcon: View {
    let symbol: String
    let isActive: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: PC.topIconSize, weight: .regular))
                .foregroundStyle(isActive ? PC.accent : PC.icon)
                .frame(width: PC.topButton + 6, height: PC.topButton)
        }
        .buttonStyle(.plain)
    }
}

/// Panel chrome: dark rounded card with a shadow, as seen in every screenshot.
struct PCPanelCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .background(
                RoundedRectangle(cornerRadius: PC.panelCorner, style: .continuous)
                    .fill(PC.panel)
                    .shadow(color: .black.opacity(0.45), radius: 18, y: 6)
            )
    }
}

/// The "Title ⌄" header shared by the brush library and layers panels.
struct PCPanelHeader: View {
    let title: String
    var trailingSymbol: String? = "plus"
    var trailingAction: (() -> Void)?

    var body: some View {
        HStack(spacing: 7) {
            Text(title)
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(.white)
            Image(systemName: "chevron.down.circle.fill")
                .font(.system(size: 13))
                .foregroundStyle(PC.iconDim)

            Spacer()

            if let trailingSymbol {
                Button { trailingAction?() } label: {
                    Image(systemName: trailingSymbol)
                        .font(.system(size: 19, weight: .light))
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 12)
        .padding(.bottom, 8)
    }
}
#endif
