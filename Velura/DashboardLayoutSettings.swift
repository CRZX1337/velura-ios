import SwiftUI

enum DashboardModule: String, CaseIterable, Identifiable, Hashable {
    case speed
    case gpsStatus
    case driveMetrics
    case sessionControls
    case safetyNote

    var id: String { rawValue }

    var title: String {
        switch self {
        case .speed: "Live speed"
        case .gpsStatus: "GPS signal"
        case .driveMetrics: "Drive metrics"
        case .sessionControls: "Drive controls"
        case .safetyNote: "Safety note"
        }
    }

    var detail: String {
        switch self {
        case .speed: "Speed reading and dial"
        case .gpsStatus: "GPS connection and accuracy"
        case .driveMetrics: "Distance, top speed and duration"
        case .sessionControls: "Start, pause, resume and finish"
        case .safetyNote: "GPS speed and safe-driving reminder"
        }
    }

    var symbol: String {
        switch self {
        case .speed: "speedometer"
        case .gpsStatus: "location.circle"
        case .driveMetrics: "chart.bar.xaxis"
        case .sessionControls: "play.circle"
        case .safetyNote: "checkmark.shield"
        }
    }

    var isOptional: Bool {
        switch self {
        case .speed, .sessionControls: false
        case .gpsStatus, .driveMetrics, .safetyNote: true
        }
    }
}

enum DashboardLayoutPreset: String, CaseIterable, Identifiable, Hashable {
    case full
    case minimal

    var id: String { rawValue }
    var title: String { self == .full ? "Full" : "Minimal" }

    var moduleOrder: [DashboardModule] {
        switch self {
        case .full: [.speed, .gpsStatus, .driveMetrics, .sessionControls, .safetyNote]
        case .minimal: [.speed, .sessionControls, .gpsStatus, .driveMetrics, .safetyNote]
        }
    }

    var visibleOptionalModules: Set<DashboardModule> {
        switch self {
        case .full: Set(DashboardModule.allCases.filter(\.isOptional))
        case .minimal: []
        }
    }
}

final class AppDashboardLayout: ObservableObject {
    static let shared = AppDashboardLayout()

    @Published private(set) var moduleOrder: [DashboardModule] {
        didSet { UserDefaults.standard.set(moduleOrder.map(\.rawValue), forKey: Self.orderStorageKey) }
    }

    @Published private(set) var visibleOptionalModules: Set<DashboardModule> {
        didSet {
            UserDefaults.standard.set(visibleOptionalModules.map(\.rawValue).sorted(), forKey: Self.visibleStorageKey)
        }
    }

    private static let orderStorageKey = "speedometer.dashboard.moduleOrder"
    private static let visibleStorageKey = "speedometer.dashboard.visibleModules"

    private init() {
        let defaults = UserDefaults.standard
        moduleOrder = Self.normalizedOrder(defaults.stringArray(forKey: Self.orderStorageKey) ?? [])

        if let savedModules = defaults.stringArray(forKey: Self.visibleStorageKey) {
            visibleOptionalModules = Set(savedModules.compactMap(DashboardModule.init(rawValue:)).filter(\.isOptional))
        } else {
            visibleOptionalModules = DashboardLayoutPreset.full.visibleOptionalModules
        }
    }

    func isVisible(_ module: DashboardModule) -> Bool {
        !module.isOptional || visibleOptionalModules.contains(module)
    }

    func setVisible(_ isVisible: Bool, for module: DashboardModule) {
        guard module.isOptional else { return }
        var updated = visibleOptionalModules
        if isVisible {
            updated.insert(module)
        } else {
            updated.remove(module)
        }
        visibleOptionalModules = updated
    }

    func apply(_ preset: DashboardLayoutPreset) {
        moduleOrder = preset.moduleOrder
        visibleOptionalModules = preset.visibleOptionalModules
    }

    func matches(_ preset: DashboardLayoutPreset) -> Bool {
        moduleOrder == preset.moduleOrder && visibleOptionalModules == preset.visibleOptionalModules
    }

    func move(from source: IndexSet, to destination: Int) {
        let moving = source.sorted().map { moduleOrder[$0] }
        var remaining = moduleOrder.enumerated()
            .filter { !source.contains($0.offset) }
            .map(\.element)
        let precedingMovedItems = source.filter { $0 < destination }.count
        let insertionIndex = min(max(0, destination - precedingMovedItems), remaining.count)
        remaining.insert(contentsOf: moving, at: insertionIndex)
        moduleOrder = remaining
    }

    private static func normalizedOrder(_ rawValues: [String]) -> [DashboardModule] {
        var ordered = rawValues.compactMap { DashboardModule(rawValue: $0) }
        var seen = Set<DashboardModule>()
        ordered = ordered.filter { seen.insert($0).inserted }
        ordered.append(contentsOf: DashboardModule.allCases.filter { !seen.contains($0) })
        return ordered
    }
}

struct DashboardLayoutSettingsSection: View {
    @ObservedObject var layout: AppDashboardLayout
    @ObservedObject private var appearance = AppAppearance.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showingEditor = false

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(spacing: 10) {
                Image(systemName: "square.grid.2x2.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(SpeedometerStyle.accent)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Dashboard layout")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(SpeedometerStyle.foreground)
                    Text("Choose modules and arrange their order")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(SpeedometerStyle.secondary)
                }
            }

            HStack(spacing: 8) {
                ForEach(DashboardLayoutPreset.allCases) { preset in
                    presetButton(preset)
                }
            }

            Button {
                showingEditor = true
            } label: {
                HStack(spacing: 9) {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 12, weight: .semibold))
                    Text("Edit modules")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                    Spacer()
                    Text("\(layout.visibleOptionalModules.count) optional on")
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(SpeedometerStyle.secondary)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(SpeedometerStyle.secondary)
                }
                .foregroundStyle(SpeedometerStyle.accent)
                .padding(.horizontal, 13)
                .frame(height: 42)
                .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 14))
            }
            .buttonStyle(.plain)

            Text("Live speed and drive controls are always included.")
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundStyle(SpeedometerStyle.secondary)
        }
        .padding(15)
        .background(SpeedometerStyle.foreground.opacity(0.025), in: RoundedRectangle(cornerRadius: 21, style: .continuous))
        .glassEffect(.regular, in: .rect(cornerRadius: 21))
        .sheet(isPresented: $showingEditor) {
            NavigationStack {
                DashboardLayoutEditor(layout: layout)
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
            .presentationBackground(SpeedometerStyle.background)
        }
    }

    private func presetButton(_ preset: DashboardLayoutPreset) -> some View {
        let isSelected = layout.matches(preset)
        return Button {
            withAnimation(VeluraMotion.animation(VeluraMotion.selection, reduceMotion: reduceMotion)) { layout.apply(preset) }
        } label: {
            HStack(spacing: 7) {
                Image(systemName: preset == .full ? "rectangle.stack" : "rectangle.compress.vertical")
                    .font(.system(size: 12, weight: .semibold))
                Text(preset.title)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                Spacer(minLength: 0)
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 11, weight: .semibold))
                }
            }
            .foregroundStyle(isSelected ? SpeedometerStyle.foreground : SpeedometerStyle.secondary)
            .padding(.horizontal, 11)
            .frame(maxWidth: .infinity)
            .frame(height: 40)
            .background(isSelected ? SpeedometerStyle.accent.opacity(0.16) : SpeedometerStyle.foreground.opacity(0.025), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .stroke(isSelected ? SpeedometerStyle.accent.opacity(0.55) : SpeedometerStyle.foreground.opacity(0.07), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct DashboardLayoutEditor: View {
    @ObservedObject var layout: AppDashboardLayout
    @ObservedObject private var appearance = AppAppearance.shared
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        List {
            Section {
                ForEach(layout.moduleOrder) { module in
                    moduleRow(module)
                        .listRowBackground(SpeedometerStyle.foreground.opacity(0.025))
                }
                .onMove(perform: layout.move)
            } header: {
                Text("DASHBOARD MODULES")
                    .foregroundStyle(SpeedometerStyle.secondary)
            } footer: {
                Text("Drag rows to reorder. Live speed and drive controls are always on; other modules can be hidden.")
                    .foregroundStyle(SpeedometerStyle.secondary)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(SpeedometerStyle.background)
        .animation(VeluraMotion.animation(VeluraMotion.content, reduceMotion: reduceMotion), value: layout.moduleOrder)
        .animation(VeluraMotion.animation(VeluraMotion.content, reduceMotion: reduceMotion), value: layout.visibleOptionalModules)
        .navigationTitle("Dashboard layout")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Done") { dismiss() }
                    .foregroundStyle(SpeedometerStyle.accent)
            }
            ToolbarItem(placement: .topBarTrailing) {
                EditButton()
                    .tint(SpeedometerStyle.accent)
            }
        }
    }

    @ViewBuilder
    private func moduleRow(_ module: DashboardModule) -> some View {
        if module.isOptional {
            Toggle(isOn: Binding(
                get: { layout.isVisible(module) },
                set: { layout.setVisible($0, for: module) }
            )) {
                moduleLabel(module)
            }
            .tint(SpeedometerStyle.accent)
            .accessibilityLabel("Show \(module.title)")
        } else {
            HStack(spacing: 12) {
                moduleLabel(module)
                Spacer(minLength: 8)
                Text("ALWAYS ON")
                    .font(.system(size: 8, weight: .bold, design: .rounded))
                    .tracking(0.7)
                    .foregroundStyle(SpeedometerStyle.accent)
            }
            .accessibilityElement(children: .combine)
        }
    }

    private func moduleLabel(_ module: DashboardModule) -> some View {
        HStack(spacing: 11) {
            Image(systemName: module.symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(SpeedometerStyle.accent)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 3) {
                Text(module.title)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(SpeedometerStyle.foreground)
                Text(module.detail)
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(SpeedometerStyle.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
    }
}
