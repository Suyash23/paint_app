import SwiftUI
import PaintCoachCore
import PaintCoachUI

@main
struct PaintCoachApp: App {
    var body: some Scene {
        WindowGroup {
            // Deliberately smaller than the 2732x2048 screen-size preset while
            // bringing this up: each layer cache is width * height * 4 bytes, so
            // full size costs ~22 MB per layer. Fine on device, slower to iterate.
            PaintView(
                document: Document(
                    canvasSize: CanvasSize(width: 1536, height: 1152),
                    backgroundColor: .white
                )
            )
        }
    }
}
