import SwiftUI

/// The streaming transcript (0025 prototype): the text decoded so far, on the HUD surface, a
/// fixed size, scrolling when the text outgrows it and following the newest line. The top of
/// the indicator's stack; `RiverIndicatorView` decides when it shows and fades it.
struct TranscriptPanelView: View {
    let text: String
    @Environment(\.colorScheme) private var colorScheme

    // Shown while the user has the live text on (planning 0034), from the first decoded text
    // until the cycle returns to idle.
    static func isVisible(state: RiverState, text: String, isShown: Bool) -> Bool {
        isShown && state != .idle && !text.isEmpty
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Constants.transcriptPanelCornerRadius, style: .continuous)
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 0) {
                    Text(text)
                        .font(.system(size: Constants.transcriptFontSize))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                    Color.clear.frame(height: 0).id(Self.endID)
                }
                .padding(.horizontal, Constants.transcriptPanelHorizontalPadding)
                .padding(.vertical, Constants.transcriptPanelVerticalPadding)
            }
            .onChange(of: text) { _, _ in
                proxy.scrollTo(Self.endID, anchor: .bottom)
            }
        }
        .frame(width: Constants.transcriptPanelWidth, height: Constants.transcriptPanelHeight)
        .clipShape(shape)
        .foregroundStyle(Color(nsColor: Palette.HUD.for(colorScheme).text))
        .modifier(HUDSurface(cornerRadius: Constants.transcriptPanelCornerRadius, edge: .window))
        .accessibilityLabel("Transcript")
    }

    private static let endID = "end"
}
