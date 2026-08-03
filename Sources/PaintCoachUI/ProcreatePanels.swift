#if canImport(UIKit)
import SwiftUI
import PaintCoachCore

// MARK: - Brush library (IMG_0002 / 0003 / 0004)

/// Two-column brush library: sets on the left, brushes on the right.
struct PCBrushLibrary: View {
    @ObservedObject var model: CanvasModel

    /// Brush sets shown in the left column. The stock Procreate names are used
    /// so the panel matches the screenshots; only the sets we actually ship
    /// resolve to brushes.
    private var sets: [String] { PC.brushSets }

    var body: some View {
        PCPanelCard {
            VStack(spacing: 0) {
                PCPanelHeader(title: "Procreate Library") {}

                HStack(alignment: .top, spacing: 10) {
                    setColumn
                    brushColumn
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 10)
            }
        }
        .frame(width: 372, height: 720)
    }

    private var setColumn: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 6) {
                ForEach(sets, id: \.self) { name in
                    let isSelected = name == model.selectedSet
                    Button {
                        model.selectedSet = name
                    } label: {
                        HStack(spacing: 9) {
                            Image(systemName: "paintbrush.pointed.fill")
                                .font(.system(size: 12))
                                .foregroundStyle(isSelected ? .white : PC.icon)
                                .frame(width: 16)
                            Text(name)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(isSelected ? .white : PC.icon)
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 11)
                        .frame(height: 46)
                        .background(
                            RoundedRectangle(cornerRadius: PC.rowCorner, style: .continuous)
                                .fill(isSelected ? PC.accent : PC.panelRow)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .frame(width: 132)
    }

    private var brushColumn: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 4) {
                ForEach(model.brushesInSelectedSet, id: \.id) { brush in
                    let isSelected = brush.id == model.brushID
                    Button {
                        model.brushID = brush.id
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(brush.name)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.white)
                            PCBrushSwatch(brush: brush)
                                .frame(height: 34)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: PC.rowCorner, style: .continuous)
                                .fill(isSelected ? PC.accent : Color.clear)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.top, 2)
        }
        .frame(maxWidth: .infinity)
    }
}

/// A tapering stroke preview, standing in for Procreate's rendered thumbnails.
struct PCBrushSwatch: View {
    let brush: Brush

    var body: some View {
        Canvas { context, size in
            let midY = size.height / 2
            var path = Path()
            path.move(to: CGPoint(x: 4, y: midY + 6))
            path.addCurve(
                to: CGPoint(x: size.width - 4, y: midY - 4),
                control1: CGPoint(x: size.width * 0.3, y: midY - 14),
                control2: CGPoint(x: size.width * 0.65, y: midY + 12)
            )
            // Spacing stands in for softness: dense brushes read as solid.
            let width = max(3, 13 - brush.spacing * 40)
            context.stroke(
                path,
                with: .color(.white.opacity(0.92)),
                style: StrokeStyle(lineWidth: width, lineCap: .round)
            )
        }
    }
}

// MARK: - Layers (IMG_0005)

/// Layer stack with thumbnail, blend-mode letter, and visibility checkbox.
struct PCLayersPanel: View {
    @ObservedObject var model: CanvasModel

    var body: some View {
        PCPanelCard {
            VStack(spacing: 0) {
                PCPanelHeader(title: "Layers") { model.addLayer() }

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 3) {
                        // Top layer first, matching what the user sees.
                        ForEach(model.layers.reversed()) { layer in
                            row(layer)
                        }
                    }
                    .padding(.horizontal, 9)
                    .padding(.bottom, 10)
                }
            }
        }
        .frame(width: 276)
        .frame(maxHeight: 560)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func row(_ layer: Layer) -> some View {
        let isActive = layer.id == model.activeLayerID
        let isBackground = layer.kind == .backgroundColor

        return HStack(spacing: 0) {
            // Thumbnail: white for the background layer, dark for paint layers.
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(isBackground ? Color.white : Color(white: 0.22))
                .frame(width: 60, height: 44)

            Text(layer.name)
                .font(.system(size: 14))
                .foregroundStyle(.white)
                .padding(.leading, 12)

            Spacer(minLength: 8)

            if !isBackground {
                Text("N")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(isActive ? .white : PC.icon)
                    .padding(.trailing, 10)
            }

            Button {
                model.toggleVisibility(layerID: layer.id)
            } label: {
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(layer.isVisible ? Color.white : Color.clear)
                    .overlay(
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .stroke(Color.white.opacity(0.55), lineWidth: 1.2)
                    )
                    .overlay {
                        if layer.isVisible {
                            Image(systemName: "checkmark")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(isActive ? PC.accent : Color.black)
                        }
                    }
                    .frame(width: 17, height: 17)
            }
            .buttonStyle(.plain)
            .padding(.trailing, 12)
        }
        .padding(4)
        .background(
            RoundedRectangle(cornerRadius: PC.rowCorner, style: .continuous)
                .fill(isActive ? PC.accent : PC.panelRow)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            // The background colour layer cannot be painted on, so it is not
            // selectable — mirrors the Core rule rather than duplicating it.
            if layer.kind == .paint { model.select(layerID: layer.id) }
        }
    }
}

// MARK: - Actions menu (IMG_0007)

/// Wrench menu: icon tab strip over grouped rows.
struct PCActionsPanel: View {
    @State private var tab = 5

    private let tabs: [(String, String)] = [
        ("plus.square.on.square", "Add"),
        ("crop", "Canvas"),
        ("square.and.arrow.up", "Share"),
        ("play.fill", "Video"),
        ("switch.2", "Prefs"),
        ("questionmark.circle.fill", "Help")
    ]

    var body: some View {
        PCPanelCard {
            VStack(alignment: .leading, spacing: 0) {
                Text("Actions")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.top, 13)

                HStack(spacing: 0) {
                    ForEach(Array(tabs.enumerated()), id: \.offset) { index, item in
                        Button { tab = index } label: {
                            VStack(spacing: 4) {
                                Image(systemName: item.0)
                                    .font(.system(size: 16))
                                Text(item.1).font(.system(size: 10))
                            }
                            .foregroundStyle(tab == index ? PC.accent : PC.icon)
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 12)

                PCMenuGroup(["Help Center", "Talk to our team"])
                PCMenuGroup(["Procreate Community", "Procreate Beginners Series"])
                PCMenuGroup(["Download 3D model pack", "Advanced settings"])
                    .padding(.bottom, 12)
            }
        }
        .frame(width: 280)
    }
}

// MARK: - Adjustments menu (IMG_0008)

/// Wand menu: the adjustment list, grouped exactly as the screenshot shows.
struct PCAdjustmentsPanel: View {
    var body: some View {
        PCPanelCard {
            VStack(alignment: .leading, spacing: 0) {
                Text("Adjustments")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.top, 13)
                    .padding(.bottom, 10)

                PCMenuGroup([
                    "Hue, Saturation, Brightness", "Color Balance",
                    "Curves", "Gradient Map"
                ])
                PCMenuGroup(["Gaussian Blur", "Motion Blur", "Perspective Blur"])
                PCMenuGroup([
                    "Noise", "Sharpen", "Bloom",
                    "Glitch", "Halftone", "Chromatic Aberration"
                ])
                PCMenuGroup(["Liquify", "Clone"])
                    .padding(.bottom, 12)
            }
        }
        .frame(width: 236)
    }
}

/// One group of rows separated by hairlines, as used by both dark menus.
struct PCMenuGroup: View {
    private let items: [String]
    init(_ items: [String]) { self.items = items }

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.offset) { index, title in
                Text(title)
                    .font(.system(size: 15))
                    .foregroundStyle(Color(white: 0.86))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
                    .frame(height: 34)

                if index < items.count - 1 {
                    Rectangle()
                        .fill(Color.white.opacity(0.07))
                        .frame(height: 1)
                        .padding(.leading, 14)
                }
            }
        }
        .background(PC.panelRow.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: PC.rowCorner, style: .continuous))
        .padding(.horizontal, 12)
        .padding(.bottom, 10)
    }
}

// MARK: - Bottom bars (IMG_0009 selection / IMG_0010 transform)

/// Segmented mode row over a labelled action row, shared by both bottom bars.
struct PCBottomBar: View {
    let modes: [(String, String)]
    @Binding var selectedMode: Int
    let actions: [(String, String, Bool)]

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                ForEach(Array(modes.enumerated()), id: \.offset) { index, mode in
                    Button { selectedMode = index } label: {
                        HStack(spacing: 7) {
                            Image(systemName: mode.0).font(.system(size: 13))
                            Text(mode.1).font(.system(size: 13))
                        }
                        .foregroundStyle(selectedMode == index ? .white : PC.icon)
                        .frame(maxWidth: .infinity)
                        .frame(height: 28)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(selectedMode == index ? PC.accent : Color.clear)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(3)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.white.opacity(0.08))
            )
            .padding(.horizontal, 14)
            .padding(.top, 10)

            HStack(spacing: 0) {
                ForEach(Array(actions.enumerated()), id: \.offset) { _, action in
                    VStack(spacing: 5) {
                        Image(systemName: action.0).font(.system(size: 16))
                        Text(action.1).font(.system(size: 11))
                    }
                    // Dimmed entries mirror Procreate's disabled state.
                    .foregroundStyle(action.2 ? PC.accent : PC.icon)
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(.vertical, 12)
        }
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(white: 0.15))
                .shadow(color: .black.opacity(0.4), radius: 14, y: 4)
        )
    }
}
#endif
