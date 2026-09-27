import CoreGraphics

/// The pixel-grid r (planning 0029): one map and one cell layout that every surface draws
/// — the live indicator, the menu bar glyphs, and the app icon — so they match by
/// construction (identity-studies working rule 8).
enum PixelMark {
    /// One pixel of the r and where it goes: its place along the stroke for the
    /// transcribing crest, and the meter slot it drops into while listening.
    struct Cell: Equatable {
        let x: Int
        let y: Int
        /// 0 at the stem's foot, 1 at the tip.
        let strokeFraction: Double
        let meterColumn: Int
        /// 0 is the meter's bottom row.
        let meterStack: Int

        // The meter is centered in the grid: the middle four columns and the middle four rows.
        var meterX: Int { meterColumn + 1 }
        var meterY: Int { PixelMark.meterBottomRow - meterStack }
        // A checkerboard: the static Transcribing reading keeps half the pixels at full ink.
        var isDitherBright: Bool { (x + y) % 2 == 0 }
    }

    /// A cell of a static reading, as the menu bar glyphs and the app icon draw it.
    struct StaticCell: Equatable {
        let x: Int
        let y: Int
        let ink: Double
    }

    static let size = 6
    static let meterColumns = 4
    static let meterRows = 4
    static let meterBottomRow = (size + meterRows) / 2 - 1

    static let map = [
        "XX.XX.",
        "XXX..X",
        "XX....",
        "XX....",
        "XX....",
        "XX....",
    ]

    // Stem foot, up the stem, over the shoulder, out to the tip.
    static let strokeOrder: [(x: Int, y: Int)] = [
        (0, 5), (1, 5), (0, 4), (1, 4), (0, 3), (1, 3), (0, 2), (1, 2),
        (0, 1), (0, 0), (1, 0), (1, 1), (2, 1), (3, 0), (4, 0), (5, 1),
    ]

    static let cells: [Cell] = makeCells()

    static func ditherInk(_ cell: Cell) -> Double {
        cell.isDitherBright ? 1 : Constants.pixelDitherInk
    }

    static func staticCells(for glyph: MenuBarPresentation.Glyph) -> [StaticCell] {
        switch glyph {
        case .ready:
            return cells.map { StaticCell(x: $0.x, y: $0.y, ink: 1) }
        case .listening:
            // A frozen meter reading, where the live meter sits. No unlit cells: at menu bar
            // size they turn the glyph into a gray block.
            return Constants.menuBarListeningHeights.enumerated().flatMap { column, height in
                (0..<height).map { stack in StaticCell(x: column + 1, y: meterBottomRow - stack, ink: 1) }
            }
        case .transcribing:
            return cells.map { StaticCell(x: $0.x, y: $0.y, ink: ditherInk($0)) }
        }
    }

    static func cellRect(x: Double, y: Double, cell: Double, gap: Double) -> CGRect {
        CGRect(x: x * (cell + gap), y: y * (cell + gap), width: cell, height: cell)
    }

    static func extent(cell: Double, gap: Double) -> Double {
        Double(size) * cell + Double(size - 1) * gap
    }

    static func cornerRadius(cell: Double) -> Double {
        cell * Constants.pixelCornerFraction
    }

    private static func makeCells() -> [Cell] {
        let positions = map.enumerated().flatMap { y, row in
            row.enumerated().compactMap { x, character in character == "X" ? (x: x, y: y) : nil }
        }
        precondition(positions.count == meterColumns * meterRows, "every pixel of the r needs one meter slot")
        let slots = (0..<meterColumns).flatMap { column in
            (0..<meterRows).map { stack in (column: column, stack: stack, x: column + 1, y: meterBottomRow - stack) }
        }
        // Pair pixels with slots by the shortest total squared travel: when all sixteen move
        // at once, no two paths cross, so no pixel passes through another mid-flight.
        func cost(_ position: (x: Int, y: Int), _ slot: (column: Int, stack: Int, x: Int, y: Int)) -> Int {
            (position.x - slot.x) * (position.x - slot.x) + (position.y - slot.y) * (position.y - slot.y)
        }
        var pick = Array(positions.indices)
        var improved = true
        while improved {
            improved = false
            for i in positions.indices {
                for j in positions.indices where j > i {
                    let current = cost(positions[i], slots[pick[i]]) + cost(positions[j], slots[pick[j]])
                    let swapped = cost(positions[i], slots[pick[j]]) + cost(positions[j], slots[pick[i]])
                    if swapped < current {
                        pick.swapAt(i, j)
                        improved = true
                    }
                }
            }
        }
        let lastStroke = Double(strokeOrder.count - 1)
        return positions.enumerated().map { index, position in
            let rank = strokeOrder.firstIndex { $0.x == position.x && $0.y == position.y } ?? 0
            let slot = slots[pick[index]]
            return Cell(x: position.x, y: position.y, strokeFraction: Double(rank) / lastStroke,
                        meterColumn: slot.column, meterStack: slot.stack)
        }
    }
}
