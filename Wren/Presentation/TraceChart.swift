import SwiftUI

// MARK: - Trace engine

/// One draw pass per sample instead of Swift Charts' mark machinery: area
/// gradient, line, threshold rules and axes all rendered in a single Canvas.
/// The shapes match the old charts — monotone cubic for continuous series,
/// step-end for the pressure bands.
enum TraceInterpolation {
    case monotone
    case stepEnd
}

struct TraceRule {
    var value: Double
    var color: Color
}

struct TraceCanvas: View {
    let points: [HistoryPoint]
    var value: (HistoryPoint) -> Double
    var tint: Color = Palette.accent
    var areaTopOpacity: Double = 0.22
    var areaBottomOpacity: Double = 0.02
    var interpolation: TraceInterpolation = .monotone
    var fixedDomain: ClosedRange<Double>? = nil
    var yTicks: [Double]? = nil
    var yLabel: (Double) -> String = { _ in "" }
    var rules: [TraceRule] = []
    var showsAxes = true
    var showsEndpoint = false

    var body: some View {
        Canvas { context, size in
            draw(&context, size: size)
        }
        .accessibilityHidden(true)
    }

    private func draw(_ context: inout GraphicsContext, size: CGSize) {
        guard let first = points.first, let last = points.last else { return }

        let series = points.map { (x: $0.timestamp, y: value($0)) }
        let (domain, ticks) = yScale(for: series.map(\.y))
        let xMin = first.timestamp.timeIntervalSinceReferenceDate
        let xMax = max(last.timestamp.timeIntervalSinceReferenceDate, xMin + 0.001)

        var leading: CGFloat = 0
        var bottom: CGFloat = 0
        // Tick labels are laid out once per redraw: measurement and drawing
        // share the resolved text instead of resolving each string twice.
        var yLabels: [(value: Double, label: GraphicsContext.ResolvedText)] = []
        if showsAxes {
            let font = Typeface.label(9.5)
            let proposal = CGSize(width: 1000, height: 50)
            yLabels = ticks.map { ($0, context.resolve(Text(yLabel($0)).font(font))) }
            let widest = yLabels
                .map { $0.label.measure(in: proposal).width }
                .max() ?? 0
            leading = min(widest + 8, size.width * 0.35)
            bottom = 16
        }

        let plot = CGRect(
            x: leading,
            y: 6,
            width: max(size.width - leading - 6, 1),
            height: max(size.height - 6 - bottom, 1)
        )

        func point(_ sample: (x: Date, y: Double)) -> CGPoint {
            let t = sample.x.timeIntervalSinceReferenceDate
            let clampedY = min(max(sample.y, domain.lowerBound), domain.upperBound)
            let span = domain.upperBound - domain.lowerBound
            let yFraction = span > 0 ? (clampedY - domain.lowerBound) / span : 0
            return CGPoint(
                x: plot.minX + CGFloat((t - xMin) / (xMax - xMin)) * plot.width,
                y: plot.maxY - CGFloat(yFraction) * plot.height
            )
        }

        if showsAxes {
            drawAxes(&context, plot: plot, yLabels: yLabels, domain: domain, xMin: xMin, xMax: xMax)
        }

        let path = tracePath(series.map(point))
        var area = path
        area.addLine(to: CGPoint(x: plot.maxX, y: plot.maxY))
        area.addLine(to: CGPoint(x: plot.minX, y: plot.maxY))
        area.closeSubpath()
        context.fill(
            area,
            with: .linearGradient(
                Gradient(colors: [tint.opacity(areaTopOpacity), tint.opacity(areaBottomOpacity)]),
                startPoint: CGPoint(x: 0, y: plot.minY),
                endPoint: CGPoint(x: 0, y: plot.maxY)
            )
        )
        context.stroke(path, with: .color(tint), style: StrokeStyle(lineWidth: 1.5, lineCap: .round))

        for rule in rules {
            guard rule.value >= domain.lowerBound, rule.value <= domain.upperBound else { continue }
            let span = domain.upperBound - domain.lowerBound
            let y = plot.maxY - CGFloat((rule.value - domain.lowerBound) / span) * plot.height
            var dashed = Path()
            dashed.move(to: CGPoint(x: plot.minX, y: y))
            dashed.addLine(to: CGPoint(x: plot.maxX, y: y))
            context.stroke(dashed, with: .color(rule.color), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
        }

        if showsEndpoint, let tail = series.last {
            let p = point(tail)
            context.fill(
                Path(ellipseIn: CGRect(x: p.x - 3.2, y: p.y - 3.2, width: 6.4, height: 6.4)),
                with: .color(tint)
            )
        }
    }

    private func drawAxes(
        _ context: inout GraphicsContext,
        plot: CGRect,
        yLabels: [(value: Double, label: GraphicsContext.ResolvedText)],
        domain: ClosedRange<Double>,
        xMin: TimeInterval,
        xMax: TimeInterval
    ) {
        let font = Typeface.label(9.5)

        for entry in yLabels {
            let y = yPosition(for: entry.value, in: plot, domain: domain)
            var grid = Path()
            grid.move(to: CGPoint(x: plot.minX, y: y))
            grid.addLine(to: CGPoint(x: plot.maxX, y: y))
            context.stroke(grid, with: .color(Palette.rule), style: StrokeStyle(lineWidth: 1))
            drawResolved(&context, entry.label, at: CGPoint(x: plot.minX - 6, y: y), anchor: .trailing)
        }

        let times = (0..<4).map { xMin + (xMax - xMin) * Double($0) / 3 }
        for (index, time) in times.enumerated() {
            let x = plot.minX + CGFloat((time - xMin) / (xMax - xMin)) * plot.width
            var grid = Path()
            grid.move(to: CGPoint(x: x, y: plot.minY))
            grid.addLine(to: CGPoint(x: x, y: plot.maxY))
            context.stroke(grid, with: .color(Palette.rule.opacity(0.6)), style: StrokeStyle(lineWidth: 1))

            // Minute resolution repeats itself on spans under a few minutes.
            let style: Date.FormatStyle = xMax - xMin < 240
                ? .dateTime.hour().minute().second()
                : .dateTime.hour().minute()
            let label = Date(timeIntervalSinceReferenceDate: time).formatted(style)
            let anchor: UnitPoint = index == 0 ? .leading : (index == times.count - 1 ? .trailing : .center)
            drawResolved(&context, context.resolve(Text(label).font(font)), at: CGPoint(x: x, y: plot.maxY + 5), anchor: anchor)
        }
    }

    private func yPosition(for value: Double, in plot: CGRect, domain: ClosedRange<Double>) -> CGFloat {
        let span = domain.upperBound - domain.lowerBound
        let fraction = span > 0 ? (value - domain.lowerBound) / span : 0
        return plot.maxY - CGFloat(fraction) * plot.height
    }

    private func drawResolved(
        _ context: inout GraphicsContext,
        _ text: GraphicsContext.ResolvedText,
        at point: CGPoint,
        anchor: UnitPoint
    ) {
        var resolved = text
        resolved.shading = .color(Palette.inkSoft)
        context.draw(resolved, at: point, anchor: anchor)
    }

    private func yScale(for values: [Double]) -> (domain: ClosedRange<Double>, ticks: [Double]) {
        if let fixedDomain {
            return (fixedDomain, yTicks ?? [])
        }
        var lo = values.min() ?? 0
        var hi = values.max() ?? 1
        let floorZero = lo >= 0
        // Tick labels must read as distinct numbers: on narrow ranges the byte
        // and rate formatters round neighbors to the same string, so widen the
        // domain until the labels separate. The pad floors at the value
        // magnitude because a flat series has no range to grow from.
        for _ in 0..<10 {
            let scale = TraceCanvas.autoScale(lo: lo, hi: hi)
            let labels = scale.ticks.map(yLabel)
            if labels.allSatisfy({ $0.isEmpty }) || Set(labels).count == labels.count {
                return scale
            }
            let pad = max((hi - lo) * 0.75, (abs(lo) + abs(hi) + 1) / 32, 1)
            if floorZero {
                lo = max(lo - pad, 0)
                hi += pad
            } else {
                lo -= pad
                hi += pad
            }
        }
        return TraceCanvas.autoScale(lo: lo, hi: hi)
    }

    static func autoScale(lo: Double, hi: Double) -> (domain: ClosedRange<Double>, ticks: [Double]) {
        var lower = lo
        var upper = hi
        if upper - lower < 1e-9 {
            lower -= 1
            upper += 1
        }
        let step = niceStep((upper - lower) / 2)
        lower = (lower / step).rounded(.down) * step
        upper = (upper / step).rounded(.up) * step
        var ticks: [Double] = []
        var value = lower
        while value <= upper + step * 0.001 {
            ticks.append(value)
            value += step
        }
        return (lower...upper, ticks)
    }

    private static func niceStep(_ raw: Double) -> Double {
        guard raw > 0, raw.isFinite else { return 1 }
        let magnitude = pow(10, floor(log10(raw)))
        let normalized = raw / magnitude
        let nice: Double
        switch normalized {
        case ..<1.5: nice = 1
        case ..<3: nice = 2
        case ..<7: nice = 5
        default: nice = 10
        }
        return nice * magnitude
    }

    private func tracePath(_ pts: [CGPoint]) -> Path {
        switch interpolation {
        case .stepEnd:
            return stepPath(pts)
        case .monotone:
            return monotonePath(pts)
        }
    }

    private func stepPath(_ pts: [CGPoint]) -> Path {
        guard var current = pts.first else { return Path() }
        var path = Path()
        path.move(to: current)
        for p in pts.dropFirst() {
            path.addLine(to: CGPoint(x: p.x, y: current.y))
            path.addLine(to: p)
            current = p
        }
        return path
    }

    /// Monotone cubic (Fritsch–Carlson) — the same curve shape Swift Charts
    /// draws for `.interpolationMethod(.monotone)`.
    private func monotonePath(_ pts: [CGPoint]) -> Path {
        guard pts.count > 1 else { return Path() }
        let n = pts.count
        var slopes = [Double](repeating: 0, count: n - 1)
        for i in 0..<(n - 1) {
            let dx = Double(pts[i + 1].x - pts[i].x)
            slopes[i] = dx != 0 ? Double(pts[i + 1].y - pts[i].y) / dx : 0
        }
        var tangents = [Double](repeating: 0, count: n)
        tangents[0] = slopes[0]
        tangents[n - 1] = slopes[n - 2]
        if n > 2 {
            for i in 1..<(n - 1) {
                if slopes[i - 1] * slopes[i] <= 0 {
                    tangents[i] = 0
                } else {
                    let w1 = 2 * Double(pts[i + 1].x - pts[i].x) + Double(pts[i].x - pts[i - 1].x)
                    let w2 = Double(pts[i + 1].x - pts[i].x) + 2 * Double(pts[i].x - pts[i - 1].x)
                    tangents[i] = (w1 + w2) / (w1 / slopes[i - 1] + w2 / slopes[i])
                }
            }
        }
        var path = Path()
        path.move(to: pts[0])
        for i in 0..<(n - 1) {
            let dx = Double(pts[i + 1].x - pts[i].x) / 3
            path.addCurve(
                to: pts[i + 1],
                control1: CGPoint(x: pts[i].x + dx, y: pts[i].y + dx * tangents[i]),
                control2: CGPoint(x: pts[i + 1].x - dx, y: pts[i + 1].y - dx * tangents[i + 1])
            )
        }
        return path
    }
}

// MARK: - Traces

/// Callers own decimation (`decimatedForDrawing()`); these draw the points they're given.
struct CPUHistoryChart: View {
    let points: [HistoryPoint]

    var body: some View {
        TraceCanvas(
            points: points,
            value: { $0.cpuUsedPercent },
            fixedDomain: 0...100,
            yTicks: [0, 50, 100],
            yLabel: { "\(Int($0))%" },
            rules: [TraceRule(value: 80, color: Palette.health(.highLoad).opacity(0.45))]
        )
    }
}

struct PressureHistoryChart: View {
    let points: [HistoryPoint]

    var body: some View {
        TraceCanvas(
            points: points,
            value: { Double($0.pressureRaw) },
            areaTopOpacity: 0.2,
            interpolation: .stepEnd,
            fixedDomain: 0...4,
            yTicks: [0, 1, 2, 4],
            yLabel: { raw in
                switch Int(raw) {
                case 1: return "Warn"
                case 2: return "Urgent"
                case 4: return "Critical"
                default: return "Normal"
                }
            },
            rules: [
                TraceRule(value: 1, color: Palette.health(.moderateLoad).opacity(0.5)),
                TraceRule(value: 2, color: Palette.health(.highLoad).opacity(0.5))
            ]
        )
    }
}

struct SwapHistoryChart: View {
    let points: [HistoryPoint]

    var body: some View {
        TraceCanvas(
            points: points,
            value: { Double($0.swapUsedBytes) },
            areaTopOpacity: 0.18,
            yLabel: { Formatters.bytes(UInt64(max($0, 0))) }
        )
    }
}

struct ThroughputChart: View {
    let points: [HistoryPoint]
    let keyPath: KeyPath<HistoryPoint, UInt64>
    let tint: Color

    var body: some View {
        TraceCanvas(
            points: points,
            value: { Double($0[keyPath: keyPath]) },
            tint: tint,
            yLabel: { Formatters.rate(UInt64(max($0, 0))) }
        )
    }
}

/// The live trace that runs through the readout band.
struct PulseTrace: View {
    let points: [HistoryPoint]
    var keyPath: KeyPath<HistoryPoint, Double>
    var tint: Color = Palette.accent

    var body: some View {
        TraceCanvas(
            points: points,
            value: { $0[keyPath: keyPath] },
            tint: tint,
            areaTopOpacity: 0.32,
            fixedDomain: 0...100,
            showsAxes: false,
            showsEndpoint: true
        )
    }
}
