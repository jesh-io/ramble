import SwiftUI
import Charts
import TalkyCore
import TalkyProviders

/// Usage analytics: stat tiles + a daily bar chart (audio / tokens / cost)
/// stacked by model, with hover scrubbing and a per-model table.
struct UsageTab: View {
    @ObservedObject var store: ConfigStore
    @State private var metric: Metric = .audio
    @State private var hoverDay: Date?

    enum Metric: String, CaseIterable, Identifiable {
        case audio = "Audio"
        case tokens = "Tokens"
        case cost = "Cost"
        var id: String { rawValue }
    }

    // MARK: Data

    private struct Point: Identifiable {
        let id = UUID()
        let day: Date
        let model: String
        let minutes: Double
        let tokens: Int
        let cost: Double

        func value(_ metric: Metric) -> Double {
            switch metric {
            case .audio: minutes
            case .tokens: Double(tokens)
            case .cost: cost
            }
        }
    }

    private static let dayFormat: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    private var points: [Point] {
        let providers = ProviderRegistry.allCleanupProviders(store.config)
        func rate(_ model: String) -> (Double, Double) {
            guard let p = providers.first(where: { $0.model == model }) else { return (0, 0) }
            return (p.inputCostPerMTok ?? 0, p.outputCostPerMTok ?? 0)
        }
        let cutoff = Calendar.current.date(byAdding: .day, value: -13, to: Calendar.current.startOfDay(for: Date()))!
        var agg: [String: (minutes: Double, tokensIn: Int, tokensOut: Int)] = [:]
        for e in UsageLog.entries() {
            guard let day = Self.dayFormat.date(from: e.day), day >= cutoff else { continue }
            let key = "\(e.day)|\(displayModel(e.model))"
            var a = agg[key] ?? (0, 0, 0)
            a.minutes += (e.seconds ?? 0) / 60
            a.tokensIn += e.tokensIn ?? 0
            a.tokensOut += e.tokensOut ?? 0
            agg[key] = a
        }
        return agg.compactMap { key, a in
            let parts = key.split(separator: "|")
            guard parts.count == 2, let day = Self.dayFormat.date(from: String(parts[0])) else { return nil }
            let model = String(parts[1])
            let (rIn, rOut) = rate(model)
            return Point(
                day: day, model: model, minutes: a.minutes,
                tokens: a.tokensIn + a.tokensOut,
                cost: Double(a.tokensIn) / 1e6 * rIn + Double(a.tokensOut) / 1e6 * rOut)
        }
    }

    private func displayModel(_ raw: String) -> String {
        raw.hasPrefix("SpeechAnalyzer") ? "dictation" : raw
    }

    /// Fixed slot order by total usage; beyond 4 folds into "Other".
    private func seriesAssignment(_ points: [Point]) -> [String] {
        var totals: [String: Double] = [:]
        for p in points { totals[p.model, default: 0] += p.minutes + Double(p.tokens) / 1000 }
        return totals.sorted { $0.value > $1.value }.map(\.key)
    }

    // Validated categorical slots (dataviz reference palette, light/dark
    // stepped per mode; "Other" is a neutral fold, relief = table below).
    private static let slotColors: [Color] = [
        dynamicColor(light: 0x2A78D6, dark: 0x3987E5),
        dynamicColor(light: 0xEB6834, dark: 0xD95926),
        dynamicColor(light: 0x1BAF7A, dark: 0x199E70),
        dynamicColor(light: 0xEDA100, dark: 0xC98500),
    ]
    private static let otherColor = Color(nsColor: .systemGray)

    private static func dynamicColor(light: Int, dark: Int) -> Color {
        func nsColor(_ hex: Int) -> NSColor {
            NSColor(
                red: CGFloat((hex >> 16) & 0xFF) / 255,
                green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
        }
        return Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? nsColor(dark) : nsColor(light)
        })
    }

    // MARK: Body

    var body: some View {
        let points = points
        let series = seriesAssignment(points)
        let top = Array(series.prefix(4))
        let folded = points.map { p in
            top.contains(p.model)
                ? p
                : Point(day: p.day, model: "Other", minutes: p.minutes, tokens: p.tokens, cost: p.cost)
        }
        let domain = top + (series.count > 4 ? ["Other"] : [])
        let range = Array(Self.slotColors.prefix(top.count)) + (series.count > 4 ? [Self.otherColor] : [])

        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                tiles(points)
                if points.isEmpty {
                    emptyState
                } else {
                    chartCard(folded, domain: domain, range: range)
                    breakdown(points, series: series)
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: Tiles

    private func tiles(_ points: [Point]) -> some View {
        let today = Calendar.current.startOfDay(for: Date())
        let todayPoints = points.filter { $0.day == today }
        let audioToday = todayPoints.reduce(0) { $0 + $1.minutes }
        let tokensToday = todayPoints.reduce(0) { $0 + $1.tokens }
        let activeDays = Set(points.filter { $0.cost > 0 }.map(\.day))
        let totalCost = points.reduce(0) { $0 + $1.cost }
        let monthly = activeDays.isEmpty ? 0 : totalCost / Double(activeDays.count) * 30

        return HStack(spacing: 12) {
            tile("Audio today", value: String(format: "%.0f min", audioToday), symbol: "waveform", tint: Self.slotColors[0])
            tile("Tokens today", value: tokensToday.formatted(.number.notation(.compactName)), symbol: "text.word.spacing", tint: Self.slotColors[1])
            tile("Est. monthly", value: totalCost == 0 ? "$0" : String(format: "$%.2f", monthly), symbol: "dollarsign.circle", tint: Self.slotColors[2])
        }
    }

    private func tile(_ label: String, value: String, symbol: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(label, systemImage: symbol)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title2.weight(.semibold))
                .monospacedDigit()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBackground)
        .overlay(alignment: .topTrailing) {
            Circle().fill(tint.opacity(0.15)).frame(width: 8, height: 8).padding(10)
        }
    }

    // MARK: Chart

    private func chartCard(_ points: [Point], domain: [String], range: [Color]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(hoverReadout(points) ?? "Last 14 days")
                    .font(.callout.weight(.medium))
                    .monospacedDigit()
                    .foregroundStyle(hoverDay == nil ? .secondary : .primary)
                Spacer()
                Picker("", selection: $metric) {
                    ForEach(Metric.allCases) { m in
                        Text(m.rawValue).tag(m)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
            }

            let today = Calendar.current.startOfDay(for: Date())
            let windowStart = Calendar.current.date(byAdding: .day, value: -13, to: today)!
            let windowEnd = Calendar.current.date(byAdding: .day, value: 1, to: today)!

            Chart(points) { point in
                BarMark(
                    x: .value("Day", point.day, unit: .day),
                    y: .value(metric.rawValue, point.value(metric)),
                    width: .fixed(18)
                )
                .foregroundStyle(by: .value("Model", point.model))
                .cornerRadius(3)
                .opacity(hoverDay == nil || hoverDay == point.day ? 1 : 0.35)
            }
            // Pin the axis to the full window — otherwise a sparse ledger
            // collapses the domain and one day's bar fills the plot.
            .chartXScale(domain: windowStart...windowEnd)
            .chartForegroundStyleScale(domain: domain, range: range)
            .chartXAxis {
                AxisMarks(values: .stride(by: .day, count: 2)) {
                    AxisGridLine().foregroundStyle(.quaternary)
                    AxisValueLabel(format: .dateTime.month(.defaultDigits).day(), centered: true)
                        .font(.caption2)
                }
            }
            .chartYAxis {
                AxisMarks(position: .trailing) {
                    AxisGridLine().foregroundStyle(.quaternary)
                    AxisValueLabel().font(.caption2)
                }
            }
            .chartLegend(position: .bottom, spacing: 8)
            .chartOverlay { proxy in
                GeometryReader { geo in
                    Rectangle().fill(.clear).contentShape(Rectangle())
                        .onContinuousHover { phase in
                            switch phase {
                            case .active(let location):
                                let plotOrigin = geo[proxy.plotFrame!].origin
                                let x = location.x - plotOrigin.x
                                if let day: Date = proxy.value(atX: x) {
                                    hoverDay = Calendar.current.startOfDay(for: day)
                                }
                            case .ended:
                                hoverDay = nil
                            }
                        }
                }
            }
            .frame(height: 200)
        }
        .padding(14)
        .background(cardBackground)
    }

    private func hoverReadout(_ points: [Point]) -> String? {
        guard let hoverDay else { return nil }
        let dayPoints = points.filter { $0.day == hoverDay }
        guard !dayPoints.isEmpty else {
            return hoverDay.formatted(.dateTime.month().day()) + " — no usage"
        }
        let total = dayPoints.reduce(0.0) { $0 + $1.value(metric) }
        let formatted = switch metric {
        case .audio: String(format: "%.1f min", total)
        case .tokens: Int(total).formatted(.number.notation(.compactName)) + " tokens"
        case .cost: String(format: "$%.4f", total)
        }
        return hoverDay.formatted(.dateTime.month().day()) + " — " + formatted
    }

    // MARK: Table (relief + detail)

    private func breakdown(_ points: [Point], series: [String]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("By model — last 14 days")
                .font(.callout.weight(.semibold))
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
                GridRow {
                    Text("Model").gridColumnAlignment(.leading)
                    Text("Audio").gridColumnAlignment(.trailing)
                    Text("Tokens").gridColumnAlignment(.trailing)
                    Text("Cost").gridColumnAlignment(.trailing)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                Divider()
                ForEach(series, id: \.self) { model in
                    let rows = points.filter { $0.model == model }
                    let minutes = rows.reduce(0) { $0 + $1.minutes }
                    let tokens = rows.reduce(0) { $0 + $1.tokens }
                    let cost = rows.reduce(0) { $0 + $1.cost }
                    GridRow {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(colorFor(model, series: series))
                                .frame(width: 7, height: 7)
                            Text(model).font(.callout)
                        }
                        Text(minutes > 0 ? String(format: "%.0f min", minutes) : "—")
                        Text(tokens > 0 ? tokens.formatted(.number.notation(.compactName)) : "—")
                        Text(cost > 0 ? String(format: "$%.4f", cost) : "free")
                    }
                    .font(.callout)
                    .monospacedDigit()
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBackground)
    }

    private func colorFor(_ model: String, series: [String]) -> Color {
        guard let index = series.firstIndex(of: model), index < 4 else { return Self.otherColor }
        return Self.slotColors[index]
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "chart.bar.xaxis")
                .font(.system(size: 30))
                .foregroundStyle(.tertiary)
            Text("No usage yet")
                .font(.headline)
            Text("Dictate something — audio time and model tokens land here automatically.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 44)
        .background(cardBackground)
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(Color(nsColor: .controlBackgroundColor))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.07))
            }
    }
}
