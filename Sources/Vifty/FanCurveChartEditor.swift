import SwiftUI
import ViftyCore

struct FanCurveChartEditor: View {
    @Binding var startTemp: Double
    @Binding var midTemp: Double
    @Binding var maxTemp: Double
    @Binding var startRPM: Double
    @Binding var midRPM: Double
    @Binding var maxRPM: Double
    let rpmRange: ClosedRange<Double>
    let liveTemperature: Double?
    let fans: [Fan]
    let fanOverrides: [FanCurveOverride]
    let usePerFanOverrides: Bool

    @State private var activeChartPoint: CurveChartPointKind?

    private let tempRange = 35.0...105.0
    private let fanColors: [Color] = [.cyan, .purple, .mint, .pink]
    private let chartHeight: CGFloat = 272

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Curve chart", systemImage: "point.topleft.down.curvedto.point.bottomright.up")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(TemperatureDisplayFormatter.whole(tempRange.lowerBound))-\(TemperatureDisplayFormatter.whole(tempRange.upperBound)) · \(Int(rpmLower.rounded()))-\(Int(rpmUpper.rounded())) RPM")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            if let liveCurveTargetText {
                Text(liveCurveTargetText)
                    .font(.caption2.weight(.semibold).monospacedDigit())
                    .foregroundStyle(.orange)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }

            GeometryReader { geometry in
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(.quaternary)
                    chartGrid(in: plotRect(in: geometry.size))
                    chartAxisLabels(in: geometry.size)
                    chartAxisUnitLabels(in: geometry.size)
                    if let activePoint = activeBasePoint {
                        curvePointAxisGuides(for: [activePoint], color: .accentColor, in: geometry.size)
                    }

                    drawCurve(basePoints, in: geometry.size)
                        .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))

                    ForEach(fanCurveSeries.filter { !$0.matchesBase }) { series in
                        let color = fanColors[series.colorIndex % fanColors.count]
                        drawCurve(series.points, in: geometry.size)
                            .stroke(color.opacity(0.75), style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round, dash: [6, 5]))
                        fanSeriesEndpointMarkers(series.points, color: color, in: geometry.size)
                    }

                    if let activePoint = activeBasePoint {
                        curvePointAxisValueLabels(for: [activePoint], color: .accentColor, in: geometry.size)
                    }

                    if let liveTemperature {
                        liveTemperatureMarker(liveTemperature, in: geometry.size)
                    }

                    ForEach(CurveChartPointKind.allCases) { point in
                        let value = chartValue(for: point)
                        ChartHandle(
                            label: point.label,
                            valueText: value.chartValueText,
                            showsValueLabel: activeChartPoint == point,
                            valueLabelOffsetY: activeHandleLabelOffsetY(for: value),
                            temperature: value.temperature,
                            rpm: value.rpm,
                            accessibilityValueText: value.accessibilityValueText,
                            onHoverChanged: { isHovering in
                                activeChartPoint = isHovering ? point : nil
                            }
                        )
                        .position(position(for: value, in: geometry.size))
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { value in
                                    activeChartPoint = point
                                    setCurvePoint(point, from: value.location, in: geometry.size)
                                }
                                .onEnded { _ in activeChartPoint = nil }
                        )
                    }
                }
            }
            .frame(height: chartHeight)

            curvePointSummaryStrip

            if !fanCurveSeries.isEmpty {
                HStack(spacing: 10) {
                    chartLegendSwatch(.accentColor, label: "Base", dashed: false)
                    ForEach(fanCurveSeries) { series in
                        chartLegendSwatch(
                            fanColors[series.colorIndex % fanColors.count],
                            label: series.matchesBase ? "\(series.name) · Matches base" : series.name,
                            dashed: !series.matchesBase
                        )
                    }
                }
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            }
        }
        .padding(10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .contain)
    }

    private var editorRPMRange: ClosedRange<Double> {
        FanCurveChartGeometry.resolvedRPMRange(
            base: rpmRange,
            fans: [],
            includeFanRanges: false
        )
    }

    private var chartRPMRange: ClosedRange<Double> {
        FanCurveChartGeometry.resolvedRPMRange(
            base: editorRPMRange,
            fans: fans,
            includeFanRanges: usePerFanOverrides
        )
    }

    private var chartPresentation: FanCurveChartPresentation {
        FanCurveChartPresentation.make(
            basePoints: baseChartValues,
            fans: fans,
            overrides: fanOverrides,
            usePerFanOverrides: usePerFanOverrides
        )
    }

    private var rpmLower: Double {
        chartRPMRange.lowerBound
    }

    private var rpmUpper: Double {
        chartRPMRange.upperBound
    }

    private var chartGeometry: FanCurveChartGeometry {
        FanCurveChartGeometry(
            temperatureRange: tempRange,
            rpmRange: chartRPMRange
        )
    }

    private var editorGeometry: FanCurveChartGeometry {
        FanCurveChartGeometry(
            temperatureRange: tempRange,
            rpmRange: editorRPMRange
        )
    }

    private var basePoints: [FanCurveChartPoint] {
        [
            FanCurveChartPoint(id: "start", label: "Start", temperature: startTemp, rpm: startRPM),
            FanCurveChartPoint(id: "ramp", label: "Ramp", temperature: midTemp, rpm: midRPM),
            FanCurveChartPoint(id: "high", label: "High", temperature: maxTemp, rpm: maxRPM)
        ]
    }

    private var baseChartValues: [FanCurveChartValue] {
        basePoints.map { FanCurveChartValue(temperature: $0.temperature, rpm: $0.rpm) }
    }

    private var activeBasePoint: FanCurveChartPoint? {
        guard let activeChartPoint else { return nil }
        return chartValue(for: activeChartPoint)
    }

    private var curvePointSummaryStrip: some View {
        HStack(spacing: 8) {
            ForEach(basePoints) { point in
                CurveChartPointSummaryChip(point: point)
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.78)
    }

    private var liveCurveTargetText: String? {
        guard let liveTemperature else { return nil }
        let targetRPM = targetRPM(at: liveTemperature, points: basePoints)
        return "Live \(TemperatureDisplayFormatter.whole(liveTemperature)) -> Base \(formattedRPM(targetRPM))"
    }

    private var fanCurveSeries: [FanCurveSeriesPresentation] {
        chartPresentation.series
    }

    private func targetRPM(at temperature: Double, points: [FanCurveChartPoint]) -> Int {
        editorGeometry.targetRPM(
            at: temperature,
            points: points.map { FanCurveChartValue(temperature: $0.temperature, rpm: $0.rpm) }
        )
    }

    private func formattedRPM(_ rpm: Int) -> String {
        "\(rpm.formatted(.number.grouping(.automatic))) RPM"
    }

    private func chartValue(for point: CurveChartPointKind) -> FanCurveChartPoint {
        switch point {
        case .start:
            FanCurveChartPoint(id: point.id, label: point.label, temperature: startTemp, rpm: startRPM)
        case .ramp:
            FanCurveChartPoint(id: point.id, label: point.label, temperature: midTemp, rpm: midRPM)
        case .high:
            FanCurveChartPoint(id: point.id, label: point.label, temperature: maxTemp, rpm: maxRPM)
        }
    }

    private func setCurvePoint(_ point: CurveChartPointKind, from location: CGPoint, in size: CGSize) {
        let chartValue = chartGeometry.value(from: location, in: size)
        let value = FanCurveChartValue(
            temperature: chartValue.temperature,
            rpm: clampRPM(chartValue.rpm)
        )

        switch point {
        case .start:
            startTemp = value.temperature
            startRPM = value.rpm
        case .ramp:
            midTemp = value.temperature
            midRPM = value.rpm
        case .high:
            maxTemp = value.temperature
            maxRPM = value.rpm
        }
    }

    private func clamped(_ locationValue: Double, _ lower: Double, _ upper: Double, over span: Double) -> Double {
        guard span > 0 else { return lower }
        let ratio = min(max(locationValue / span, 0), 1)
        return lower + ((upper - lower) * ratio)
    }

    private func clampRPM(_ rpm: Double) -> Double {
        Double(FanCurve.clamp(
            Int(rpm.rounded()),
            Int(editorRPMRange.lowerBound.rounded()),
            Int(editorRPMRange.upperBound.rounded())
        ))
    }

    private func position(for point: FanCurveChartPoint, in size: CGSize) -> CGPoint {
        chartGeometry.position(
            for: FanCurveChartValue(temperature: point.temperature, rpm: point.rpm),
            in: size
        )
    }

    private func position(for point: FanCurveChartValue, in size: CGSize) -> CGPoint {
        chartGeometry.position(for: point, in: size)
    }

    private func plotRect(in size: CGSize) -> CGRect {
        chartGeometry.plotRect(in: size)
    }

    private func ratio(_ value: Double, in range: ClosedRange<Double>) -> Double {
        let span = range.upperBound - range.lowerBound
        guard span > 0 else { return 0 }
        return min(max((value - range.lowerBound) / span, 0), 1)
    }

    private func drawCurve(_ points: [FanCurveChartPoint], in size: CGSize) -> Path {
        drawCurve(
            points.map { FanCurveChartValue(temperature: $0.temperature, rpm: $0.rpm) },
            in: size
        )
    }

    private func drawCurve(_ points: [FanCurveChartValue], in size: CGSize) -> Path {
        var path = Path()
        let sortedPoints = points.sorted { $0.temperature < $1.temperature }
        guard let first = sortedPoints.first else { return path }
        path.move(to: position(for: first, in: size))
        for point in sortedPoints.dropFirst() {
            path.addLine(to: position(for: point, in: size))
        }
        return path
    }

    private func fanSeriesEndpointMarkers(_ points: [FanCurveChartValue], color: Color, in size: CGSize) -> some View {
        ZStack {
            ForEach(Array(points.enumerated()), id: \.offset) { index, point in
                if index == 0 || index == points.count - 1 {
                    Circle()
                        .fill(color)
                        .overlay(Circle().stroke(Color.primary.opacity(0.75), lineWidth: 1))
                        .frame(width: 8, height: 8)
                        .position(position(for: point, in: size))
                }
            }
        }
        .allowsHitTesting(false)
    }

    private func chartGrid(in rect: CGRect) -> some View {
        Path { path in
            for index in 1..<4 {
                let x = rect.minX + rect.width * CGFloat(index) / 4
                path.move(to: CGPoint(x: x, y: rect.minY))
                path.addLine(to: CGPoint(x: x, y: rect.maxY))

                let y = rect.minY + rect.height * CGFloat(index) / 4
                path.move(to: CGPoint(x: rect.minX, y: y))
                path.addLine(to: CGPoint(x: rect.maxX, y: y))
            }
            path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            path.move(to: CGPoint(x: rect.minX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        }
        .stroke(Color.secondary.opacity(0.18), style: StrokeStyle(lineWidth: 1, dash: [2, 5]))
    }

    private func curvePointAxisGuides(for points: [FanCurveChartPoint], color: Color, in size: CGSize) -> some View {
        let rect = plotRect(in: size)
        return ZStack {
            ForEach(points) { point in
                let pointPosition = position(for: point, in: size)
                Path { path in
                    path.move(to: CGPoint(x: rect.minX, y: pointPosition.y))
                    path.addLine(to: pointPosition)
                    path.move(to: pointPosition)
                    path.addLine(to: CGPoint(x: pointPosition.x, y: rect.maxY))
                }
                .stroke(color.opacity(0.18), style: StrokeStyle(lineWidth: 1, dash: [3, 5]))
            }
        }
        .allowsHitTesting(false)
    }

    private func curvePointAxisValueLabels(for points: [FanCurveChartPoint], color: Color, in size: CGSize) -> some View {
        let rect = plotRect(in: size)
        return ZStack {
            ForEach(Array(points.enumerated()), id: \.element.id) { pointIndex, point in
                let pointPosition = position(for: point, in: size)
                CurveChartAxisReadout(text: point.rpmText, color: color, width: 70, alignment: .leading)
                    .position(rpmAxisReadoutPosition(near: pointPosition, pointIndex: pointIndex, in: rect))
                CurveChartAxisReadout(text: point.temperatureText, color: color, width: 42, alignment: .center)
                    .position(temperatureAxisReadoutPosition(near: pointPosition, pointIndex: pointIndex, in: rect))
            }
        }
        .allowsHitTesting(false)
    }

    private func chartAxisLabels(in size: CGSize) -> some View {
        let rect = plotRect(in: size)
        let rpmX = max(rect.minX - 28, 24)
        let tempY = min(rect.maxY + 18, size.height - 10)
        return ZStack {
            CurveChartAxisValue(text: rpmTickLabel(Int(rpmUpper.rounded())), alignment: .trailing)
                .position(x: rpmX, y: rect.minY)
            CurveChartAxisValue(text: rpmTickLabel(Int(((rpmLower + rpmUpper) / 2).rounded())), alignment: .trailing)
                .position(x: rpmX, y: rect.midY)
            CurveChartAxisValue(text: rpmTickLabel(Int(rpmLower.rounded())), alignment: .trailing)
                .position(x: rpmX, y: rect.maxY)
            CurveChartAxisValue(text: temperatureTickLabel(Int(tempRange.lowerBound.rounded())), alignment: .center)
                .position(x: rect.minX, y: tempY)
            CurveChartAxisValue(text: temperatureTickLabel(Int(((tempRange.lowerBound + tempRange.upperBound) / 2).rounded())), alignment: .center)
                .position(x: rect.midX, y: tempY)
            CurveChartAxisValue(text: temperatureTickLabel(Int(tempRange.upperBound.rounded())), alignment: .center)
                .position(x: rect.maxX, y: tempY)
        }
        .allowsHitTesting(false)
    }

    private func chartAxisUnitLabels(in size: CGSize) -> some View {
        let rect = plotRect(in: size)
        return ZStack {
            CurveChartAxisTitle(text: "RPM")
                .position(x: rect.minX + 18, y: rect.minY + 10)
            CurveChartAxisTitle(text: "Temp °C")
                .position(x: rect.maxX - 30, y: rect.maxY - 10)
        }
        .allowsHitTesting(false)
    }

    private func rpmAxisReadoutPosition(near pointPosition: CGPoint, pointIndex: Int, in rect: CGRect) -> CGPoint {
        let xOffset = CGFloat(pointIndex % 2) * 14
        let yOffset = CGFloat(pointIndex - 1) * 10
        let x = rect.minX + 36 + xOffset
        let y = min(max(pointPosition.y + yOffset, rect.minY + 10), rect.maxY - 10)
        return CGPoint(x: x, y: y)
    }

    private func temperatureAxisReadoutPosition(near pointPosition: CGPoint, pointIndex: Int, in rect: CGRect) -> CGPoint {
        let yOffset = CGFloat(pointIndex % 2) * 13
        let x = min(max(pointPosition.x, rect.minX + 22), rect.maxX - 22)
        let y = rect.maxY - 11 - yOffset
        return CGPoint(x: x, y: y)
    }

    private func activeHandleLabelOffsetY(for point: FanCurveChartPoint) -> CGFloat {
        let midpoint = (rpmLower + rpmUpper) / 2
        return point.rpm >= midpoint ? 28 : -28
    }

    private func rpmTickLabel(_ rpm: Int) -> String {
        "\(rpm.formatted(.number.grouping(.automatic))) RPM"
    }

    private func temperatureTickLabel(_ temperature: Int) -> String {
        TemperatureDisplayFormatter.whole(Double(temperature))
    }

    private func liveTemperatureMarker(_ temperature: Double, in size: CGSize) -> some View {
        let rect = plotRect(in: size)
        let x = rect.minX + rect.width * CGFloat(ratio(temperature, in: tempRange.lowerBound...tempRange.upperBound))
        return ZStack {
            Path { path in
                path.move(to: CGPoint(x: x, y: rect.minY))
                path.addLine(to: CGPoint(x: x, y: rect.maxY))
            }
            .stroke(Color.orange.opacity(0.75), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))

            liveTemperatureLabel(temperature, in: size)
                .position(x: min(max(x, rect.minX + 24), rect.maxX - 24), y: rect.minY + 10)
        }
        .allowsHitTesting(false)
    }

    private func liveTemperatureLabel(_ temperature: Double, in size: CGSize) -> some View {
        Text(TemperatureDisplayFormatter.whole(temperature))
            .font(.caption2.weight(.semibold).monospacedDigit())
            .foregroundStyle(.orange)
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
            .background(.regularMaterial, in: Capsule())
            .frame(maxWidth: min(max(size.width - 8, 42), 70))
    }

    private func chartLegendSwatch(_ color: Color, label: String, dashed: Bool) -> some View {
        HStack(spacing: 4) {
            Path { path in
                path.move(to: CGPoint(x: 0, y: 2))
                path.addLine(to: CGPoint(x: 14, y: 2))
            }
            .stroke(color, style: StrokeStyle(lineWidth: dashed ? 2.5 : 3, lineCap: .round, dash: dashed ? [6, 5] : []))
            .frame(width: 14, height: 4)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}

private struct CurveChartAxisValue: View {
    let text: String
    let alignment: Alignment

    var body: some View {
        Text(text)
            .font(.caption2.monospacedDigit())
            .foregroundStyle(.secondary.opacity(0.9))
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .frame(width: 58, alignment: alignment)
            .padding(.horizontal, 3)
            .padding(.vertical, 1)
            .background(.regularMaterial, in: Capsule())
    }
}

private struct CurveChartAxisTitle: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption2.weight(.bold).monospacedDigit())
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(.regularMaterial, in: Capsule())
    }
}

private struct CurveChartAxisReadout: View {
    let text: String
    let color: Color
    let width: CGFloat
    let alignment: Alignment

    var body: some View {
        Text(text)
            .font(.caption2.weight(.semibold).monospacedDigit())
            .foregroundStyle(color)
            .lineLimit(1)
            .minimumScaleFactor(0.65)
            .frame(width: width, alignment: alignment)
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .background(.regularMaterial, in: Capsule())
            .overlay(Capsule().stroke(color.opacity(0.5), lineWidth: 0.75))
    }
}

private enum CurveChartPointKind: String, CaseIterable, Identifiable {
    case start
    case ramp
    case high

    var id: String { rawValue }

    var label: String {
        switch self {
        case .start:
            "Start"
        case .ramp:
            "Ramp"
        case .high:
            "High"
        }
    }
}

private struct FanCurveChartPoint: Identifiable {
    let id: String
    let label: String
    let temperature: Double
    let rpm: Double

    var chartValueText: String {
        "\(temperatureText) · \(rpmText)"
    }

    var temperatureText: String {
        TemperatureDisplayFormatter.whole(temperature)
    }

    var rpmText: String {
        "\(Int(rpm.rounded()).formatted(.number.grouping(.automatic))) RPM"
    }

    var accessibilityValueText: String {
        "\(TemperatureDisplayFormatter.whole(temperature)), \(Int(rpm.rounded())) RPM"
    }
}

private struct CurveChartPointSummaryChip: View {
    let point: FanCurveChartPoint

    var body: some View {
        HStack(spacing: 6) {
            Text(point.label)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 1) {
                Text(point.temperatureText)
                    .font(.caption2.weight(.semibold).monospacedDigit())
                Text(point.rpmText)
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.72)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .background(.regularMaterial, in: Capsule())
        .accessibilityHidden(true)
    }
}

private struct ChartHandle: View {
    let label: String
    let valueText: String
    let showsValueLabel: Bool
    let valueLabelOffsetY: CGFloat
    let temperature: Double
    let rpm: Double
    let accessibilityValueText: String
    let onHoverChanged: (Bool) -> Void

    var body: some View {
        ZStack {
            if showsValueLabel {
                CurveChartHandleValueLabel(label: label, valueText: valueText)
                    .offset(y: valueLabelOffsetY)
                    .transition(.opacity)
            }

            Circle()
                .fill(Color.accentColor)
                .frame(width: 18, height: 18)
                .overlay(Circle().stroke(.white.opacity(0.9), lineWidth: 2))
                .shadow(color: .black.opacity(0.25), radius: 2, y: 1)
        }
        .frame(width: 118, height: 58)
        .onHover(perform: onHoverChanged)
        .help("\(label): \(TemperatureDisplayFormatter.whole(temperature)) · \(Int(rpm.rounded()).formatted(.number.grouping(.automatic))) RPM")
        .accessibilityLabel("\(label) curve point")
        .accessibilityValue(accessibilityValueText)
        .accessibilityHint("Drag to edit with a pointer. Use Exact points below for keyboard editing.")
    }
}

private struct CurveChartHandleValueLabel: View {
    let label: String
    let valueText: String

    var body: some View {
        VStack(spacing: 1) {
            Text(label)
                .font(.caption2.weight(.bold))
                .foregroundStyle(.secondary)
            Text(valueText)
                .font(.caption2.weight(.semibold).monospacedDigit())
                .foregroundStyle(.primary)
        }
        .lineLimit(1)
        .minimumScaleFactor(0.68)
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().stroke(Color.accentColor.opacity(0.45), lineWidth: 0.75))
        .allowsHitTesting(false)
    }
}
