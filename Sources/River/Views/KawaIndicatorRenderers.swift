import Metal
import OSLog
import SwiftUI

/// The muted 川 strokes Glass starts from, and preparing shows held still.
enum KawaMutedStrokes {
    /// 川 in the panel's points, built once: every frame fills it.
    static let path = Path(KawaMark.path(transform: KawaIndicatorEngine.panelTransform))

    static func draw(in context: inout GraphicsContext, presence: Double, colors: Palette.HUD) {
        guard presence > 0 else { return }
        var layer = context
        layer.opacity = presence * Constants.kawaMutedOpacity
        layer.fill(path, with: .color(Color(nsColor: colors.text)))
    }
}

/// Glass, ported from the Glass study's renderer and its shader: the strokes, with
/// `KawaGlass.metal` applied over them as a layer effect, which sets their ink strength.
enum GlassRenderer {
    /// The strokes the shader samples, at full strength and the muted strokes' presence: the
    /// shader dims them to muted, then to the ink under the frost or where it is cleared.
    static func drawStrokes(in context: inout GraphicsContext, channels: KawaIndicatorChannels, colors: Palette.HUD) {
        // A layer effect runs only over what the layer drew, so the pane is covered first, in
        // the panel's own tint at the faintest opacity: the frost and its veil then reach the
        // panel's edges instead of stopping a few points around the mark.
        context.fill(Path(CGRect(x: 0, y: 0, width: Constants.indicatorPanelWidth, height: Constants.indicatorPanelHeight)),
                     with: .color(Color(nsColor: colors.tint).opacity(1.0 / 255)))
        guard channels.muted > 0 else { return }
        var layer = context
        layer.opacity = channels.muted
        layer.fill(KawaMutedStrokes.path, with: .color(Color(nsColor: colors.text)))
    }

    /// The frost, ripples and light for one frame.
    static func shader(_ library: ShaderLibrary, channels: KawaIndicatorChannels, time: Double, engine: KawaIndicatorEngine,
                       reduceMotion: Bool, colors: Palette.HUD) -> Shader {
        let arguments = arguments(channels: channels, time: time, engine: engine, reduceMotion: reduceMotion, colors: colors)
        return Shader(function: ShaderFunction(library: library, name: functionName), arguments: arguments.map(\.value.shaderArgument))
    }

    /// One value `kawaGlass` takes, in a form a test can compare.
    enum Argument: Equatable {
        case float(Double)
        case float2(Double, Double)
        case color(NSColor)
        /// Reaches the shader as two parameters: the floats and their count.
        case floats([Float])

        var shaderArgument: Shader.Argument {
            switch self {
            case .float(let x): .float(x)
            case .float2(let x, let y): .float2(x, y)
            case .color(let color): .color(Color(nsColor: color))
            case .floats(let floats): .floatArray(floats)
            }
        }
    }

    /// The shader's interface: every argument `kawaGlass` takes after the layer, named as
    /// `KawaGlass.metal` names its parameter and in its order, so a test holds the two together.
    /// Every tuned value comes from `Constants` and every color from `Palette.HUD`; the shader
    /// holds none of its own.
    static func arguments(channels: KawaIndicatorChannels, time: Double, engine: KawaIndicatorEngine,
                          reduceMotion: Bool, colors: Palette.HUD) -> [(name: String, value: Argument)] {
        typealias C = Constants
        // Toward the light, which is where a slope facing it catches it.
        let light = HUDSurface.lightDirection
        return [
            ("time", .float(time)), ("clearTime", .float(channels.clearTime)),
            ("form", .float(channels.form)), ("inkUp", .float(channels.inkUp)),
            ("frost", .float(C.kawaGlassFrost)), ("blur", .float(C.kawaGlassBlur)),
            ("veilAmount", .float(C.kawaGlassVeil)), ("grainAmount", .float(C.kawaGlassGrain)),
            ("muted", .float(C.kawaMutedOpacity)), ("inkFrost", .float(C.kawaGlassFrostedInk)), ("inkClear", .float(C.kawaGlassClearInk)),
            ("refract", .float(C.kawaGlassRefractionScale * C.kawaGlassRefraction)),
            ("spec", .float(C.kawaGlassHighlightScale * C.kawaGlassHighlights)),
            ("light", .float2(-light.dx, -light.dy)),
            ("size", .float(C.kawaGlassRippleSize)), ("speed", .float(C.kawaGlassRippleSpeed)),
            ("wavelength", .float(C.kawaGlassWavelength)), ("life", .float(C.kawaGlassRippleSeconds)),
            ("hold", .float(C.kawaGlassWindowHoldSeconds)), ("fade", .float(C.kawaGlassWindowFadeSeconds)),
            ("flat", .float(reduceMotion ? 1 : 0)), ("clearing", .float(engine.clearing)),
            ("veil", .color(colors.glassVeil)),
            ("highlight", .color(colors.glassHighlight)), ("highlightAmount", .float(colors.glassHighlightAmount)),
            ("shade", .color(colors.glassShade)), ("shadeAmount", .float(colors.glassShadeAmount)),
            ("drops", .floats(packed(engine.drops))),
        ]
    }

    /// Floats per drop in the shader's `drops`, as its `STRIDE`.
    static let dropStride = 5

    /// The drops as the shader reads them: x, y, time, ring strength and window radius each.
    /// One spent drop when there are none, so the array argument is never empty.
    static func packed(_ drops: [KawaIndicatorEngine.Drop]) -> [Float] {
        guard !drops.isEmpty else { return [0, 0, -1000, 0, 0] }
        return drops.flatMap { [Float($0.x), Float($0.y), Float($0.time), Float($0.strength), Float($0.windowRadius)] }
    }

    static let functionName = "kawaGlass"

    /// How far the shader samples from a pixel: the refraction plus the frost's blur, rounded up.
    static let maxSampleOffset = CGSize(width: 6, height: 6)

    /// The bundle's shader library, or nil (logged once) when it is missing or will not load, so
    /// the panel draws the muted strokes instead of going blank. `make verify` is the real guard.
    static let library: ShaderLibrary? = load(Bundle.main.url(forResource: "KawaGlass", withExtension: "metallib"))

    static func load(_ url: URL?) -> ShaderLibrary? {
        guard let url, let device = MTLCreateSystemDefaultDevice(),
              let compiled = try? device.makeLibrary(URL: url), compiled.makeFunction(name: functionName) != nil else {
            Logger(subsystem: Constants.loggingSubsystem, category: "indicator")
                .error("Glass shader library missing or invalid; drawing the muted strokes")
            return nil
        }
        return ShaderLibrary(url: url)
    }
}
