import Testing
@testable import River

@Suite("PixelMark")
struct PixelMarkTests {
    @Test("the r has sixteen pixels, one for each cell of the 4×4 meter")
    func pixelCountMatchesMeter() {
        #expect(PixelMark.cells.count == 16)
        #expect(PixelMark.meterColumns * PixelMark.meterRows == PixelMark.cells.count)
    }

    // The transcribing crest runs the stroke; a pixel missing from the order would never light.
    @Test("the stroke order visits every pixel once, from the stem's foot to the tip")
    func strokeOrderCoversTheR() {
        let fractions = PixelMark.cells.map(\.strokeFraction)
        #expect(Set(fractions).count == PixelMark.cells.count)
        let foot = PixelMark.cells.first { $0.strokeFraction == 0 }
        let tip = PixelMark.cells.first { $0.strokeFraction == 1 }
        #expect(foot?.x == 0 && foot?.y == 5)
        #expect(tip?.x == 5 && tip?.y == 1)
    }

    // Centered, so the meter sits in the middle of the panel rather than on its floor.
    @Test("every meter slot is taken by exactly one pixel, in the grid's middle four columns and rows")
    func slotsAreUniqueAndCentered() {
        let slots = Set(PixelMark.cells.map { "\($0.meterX),\($0.meterY)" })
        #expect(slots.count == PixelMark.cells.count)
        #expect(PixelMark.cells.allSatisfy { (1...4).contains($0.meterX) && (1...4).contains($0.meterY) })
    }

    // The menu bar's frozen reading sits where the live meter does.
    @Test("the Listening glyph occupies the live meter's rows")
    func listeningGlyphMatchesTheMeter() {
        let meterRows = Set(PixelMark.cells.map(\.meterY))
        #expect(PixelMark.staticCells(for: .listening).allSatisfy { meterRows.contains($0.y) })
    }

    // If swapping two pixels' slots shortened the drop, their paths would cross and one
    // pixel would pass through the other mid-flight.
    @Test("no swap of two pixels' slots shortens the drop")
    func pairingIsShortest() {
        func cost(_ cell: PixelMark.Cell, toX x: Int, y: Int) -> Int {
            (cell.x - x) * (cell.x - x) + (cell.y - y) * (cell.y - y)
        }
        let cells = PixelMark.cells
        for i in cells.indices {
            for j in cells.indices where j > i {
                let current = cost(cells[i], toX: cells[i].meterX, y: cells[i].meterY)
                    + cost(cells[j], toX: cells[j].meterX, y: cells[j].meterY)
                let swapped = cost(cells[i], toX: cells[j].meterX, y: cells[j].meterY)
                    + cost(cells[j], toX: cells[i].meterX, y: cells[i].meterY)
                #expect(swapped >= current)
            }
        }
    }

    // Measured on the study page: moving together, no two pixels come closer than half a
    // cell, so any overlap is brief and partial. Every staggered order measured worse.
    @Test("pixels dropping together never come within half a cell of each other")
    func simultaneousTravelKeepsApart() {
        var closest = Double.infinity
        for step in 0...100 {
            let progress = Double(step) / 100
            let positions = PixelMark.cells.map { cell in
                (x: Double(cell.x) + Double(cell.meterX - cell.x) * progress,
                 y: Double(cell.y) + Double(cell.meterY - cell.y) * progress)
            }
            for i in positions.indices {
                for j in positions.indices where j > i {
                    closest = min(closest, max(abs(positions[i].x - positions[j].x), abs(positions[i].y - positions[j].y)))
                }
            }
        }
        #expect(closest >= 0.5)
    }

    @Test("Ready is the r at full ink")
    func readyGlyph() {
        let cells = PixelMark.staticCells(for: .ready)
        #expect(cells.count == PixelMark.cells.count)
        #expect(cells.allSatisfy { $0.ink == 1 })
    }

    // Unlit cells turn the glyph into a gray block at menu bar size, so the reading has none.
    @Test("Listening is a frozen 3·1·4·2 meter reading, centered, with no unlit cells")
    func listeningGlyph() {
        let cells = PixelMark.staticCells(for: .listening)
        #expect(cells.allSatisfy { $0.ink == 1 })
        #expect((1...4).map { x in cells.filter { $0.x == x }.count } == Constants.menuBarListeningHeights)
        let rows = cells.map(\.y)
        #expect(rows.min() == 1 && rows.max() == 4)
    }

    // Same silhouette as Ready, so Transcribing reads as the r at work without motion or color.
    @Test("Transcribing is the r with every other pixel dimmed")
    func transcribingGlyph() {
        let cells = PixelMark.staticCells(for: .transcribing)
        #expect(cells.map { [$0.x, $0.y] } == PixelMark.cells.map { [$0.x, $0.y] })
        #expect(cells.filter { $0.ink == Constants.pixelDitherInk }.count == PixelMark.cells.count / 2)
        #expect(cells.allSatisfy { $0.ink == 1 || $0.ink == Constants.pixelDitherInk })
    }
}

@Suite("Indicator panel geometry")
struct IndicatorPanelGeometryTests {
    // The panel keeps the river capsule's height, so the window, the toast below it, and its
    // position on screen are unchanged.
    @Test("the panel is the 40 pt mark plus 12 pt at the sides and 8 pt above and below")
    func panelGeometry() {
        #expect(Constants.pixelMarkSize == 40)
        #expect(Constants.indicatorPanelWidth == 64)
        #expect(Constants.indicatorPanelHeight == 56)
    }

    // 5 pt cells with 2 pt gaps put every resting edge on a whole pixel, so the r is sharp on
    // 1x displays as well as 2x.
    @Test("the resting mark's cell edges land on device pixels", arguments: [1, 2])
    func restingMarkIsCrisp(scale: Int) {
        for cell in PixelMark.cells {
            let rect = PixelMark.cellRect(x: Double(cell.x), y: Double(cell.y), cell: Constants.pixelCell, gap: Constants.pixelGap)
            for edge in [rect.minX, rect.maxX, rect.minY, rect.maxY] {
                let devicePixels = edge * Double(scale)
                #expect(devicePixels == devicePixels.rounded())
            }
        }
    }

    // Concentric radii: the message rectangle's radius is its padding plus a 4 pt inner radius.
    @Test("the message rectangle keeps the concentric 16 pt radius over 12 pt padding")
    func messageGeometry() {
        #expect(Constants.hudMessageCornerRadius == Constants.hudMessagePadding + 4)
        #expect(Constants.hudStackSpacing == 8)
    }

    @Test("the fade is 0.22 s with a 6 pt rise")
    func fade() {
        #expect(Constants.hudFadeSeconds == 0.22)
        #expect(Constants.hudFadeRise == 6)
    }
}
