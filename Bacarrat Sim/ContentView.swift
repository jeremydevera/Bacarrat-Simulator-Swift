//
//  ContentView.swift
//  Bacarrat Sim
//
//  Created by Jeremy De Vera on 4/20/26.
//

import Combine
import SwiftUI
import Charts
import SwiftData

enum BaccaratSide: String, CaseIterable, Identifiable, Codable {
    case banker = "Banker"
    case player = "Player"
    case tie = "Tie"

    var id: String { rawValue }

    static func randomWeighted() -> BaccaratSide {
        let rand = Double.random(in: 0...1)
        // Standard Baccarat probabilities
        if rand < 0.4586 {
            return .banker
        } else if rand < 0.4586 + 0.4462 {
            return .player
        } else {
            return .tie
        }
    }

    var color: Color {
        switch self {
        case .banker:
            return .red
        case .player:
            return .blue
        case .tie:
            return .green
        }
    }
}

enum BetOutcome: String, Codable {
    case win = "Win"
    case loss = "Loss"
    case stopLoss = "Stop"
    case push = "Push"

    var color: Color {
        switch self {
        case .win:
            return .green
        case .loss:
            return .orange
        case .stopLoss:
            return .red
        case .push:
            return .yellow
        }
    }
}

private enum BettingStrategy: String, CaseIterable, Codable {
    case classic = "Classic Martingale"
    case mod = "Mod Martingale"
}

private struct BaccaratTable: Identifiable {
    let id: Int
    let name: String
    var result: BaccaratSide
    var nextResultDate: Date
}

private struct ActiveBet {
    let tableID: Int
    let amount: Int
    let side: BaccaratSide
    let streakStep: Int
    let streakGroupID: UUID
}

@Model
final class BetHistoryEntry: Identifiable {
    var id: UUID
    var timestamp: Date
    var tableID: Int
    var betAmount: Int
    var betSide: BaccaratSide
    var result: BaccaratSide
    var outcome: BetOutcome
    var streakStep: Int
    var streakGroupID: UUID

    init(
        id: UUID = UUID(),
        timestamp: Date,
        tableID: Int,
        betAmount: Int,
        betSide: BaccaratSide,
        result: BaccaratSide,
        outcome: BetOutcome,
        streakStep: Int,
        streakGroupID: UUID
    ) {
        self.id = id
        self.timestamp = timestamp
        self.tableID = tableID
        self.betAmount = betAmount
        self.betSide = betSide
        self.result = result
        self.outcome = outcome
        self.streakStep = streakStep
        self.streakGroupID = streakGroupID
    }
}

@Model
final class DailyProfitRecord: Identifiable {
    var id: UUID
    var day: Date
    var profit: Int
    var handsPlayed: Int = 0
    
    init(id: UUID = UUID(), day: Date, profit: Int, handsPlayed: Int = 0) {
        self.id = id
        self.day = day
        self.profit = profit
        self.handsPlayed = handsPlayed
    }
}

@Model
final class StrategyMaxLossRecord: Identifiable {
    @Attribute(.unique) var id: String
    var maxLossCount: Int
    var strategyName: String = ""
    var stopLossAmount: Int = 0
    var warningLevel: Int = 0
    
    init(id: String, maxLossCount: Int = 0, strategyName: String, stopLossAmount: Int, warningLevel: Int) {
        self.id = id
        self.maxLossCount = maxLossCount
        self.strategyName = strategyName
        self.stopLossAmount = stopLossAmount
        self.warningLevel = warningLevel
    }
}

private enum RootTab: Hashable {
    case simulator
    case history
    case analytics
}

private enum SimulationSpeed: Int, CaseIterable, Identifiable {
    case twoX = 2
    case fiftyX = 50
    case oneHundredX = 100

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .twoX: return "2x"
        case .fiftyX: return "50x"
        case .oneHundredX: return "100x"
        }
    }
}

private struct StopLossAlertContext: Identifiable {
    let id = UUID()
    let message: String
    let autoContinued: Bool
}

private enum BetResolution {
    case none
    case win
    case loss
    case stopLoss
    case push
}

private struct ProfitPoint: Identifiable {
    let id = UUID()
    let index: Int
    let profit: Int
}

// Wrapper to provide the SwiftData ModelContainer safely to the app logic
struct ContentView: View {
    var body: some View {
        BaccaratSimulatorView()
            .modelContainer(for: [BetHistoryEntry.self, DailyProfitRecord.self, StrategyMaxLossRecord.self])
    }
}

struct BaccaratSimulatorView: View {
    private static let tableCount = 30
    private static let stopLossLevels = 20
    private static let defaultStopLossLevel = 11
    private static let simulationLoopInterval = Duration.milliseconds(8)
    
    private static let pesoFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "PHP"
        formatter.currencySymbol = "PHP "
        formatter.maximumFractionDigits = 0
        formatter.locale = Locale(identifier: "en_PH")
        return formatter
    }()

    private static let detailedDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, h:mm:ss.SSS a"
        return formatter
    }()

    @Environment(\.modelContext) private var modelContext

    @AppStorage("bettingStrategy") private var strategy: BettingStrategy = .classic
    @AppStorage("saveHistoryEnabled") private var saveHistoryEnabled = false
    @AppStorage("totalProfit") private var totalProfit = 0
    @AppStorage("warningBetText") private var warningBetText = "5"

    // Manual snapshots so the app never lags from thousands of real-time query updates
    @State private var snapshotEntries: [BetHistoryEntry] = []
    @State private var snapshotDailyProfits: [DailyProfitRecord] = []
    @State private var snapshotMaxLosses: [StrategyMaxLossRecord] = []
    
    // Instant caches to make updates hyper-fast
    @State private var dailyProfitsCache: [Date: DailyProfitRecord] = [:]
    @State private var maxLossCache: [String: StrategyMaxLossRecord] = [:]

    @State private var storedBetsQueue: [Int] = []

    @State private var selectedTab: RootTab = .simulator
    @State private var simulationReferenceTime = Date()
    @State private var currentTime = Date()
    @State private var tables = BaccaratSimulatorView.makeInitialTables(countdown: 20)
    
    @State private var startingBetText = "20"
    @State private var tableTimerText = "20"
    
    @State private var selectedStopLoss = 20_480
    @State private var selectedSide: BaccaratSide = .player
    @State private var activeBet: ActiveBet?
    @State private var nextBetAmount = 20
    @State private var nextStreakStep = 1
    @State private var currentStreakGroupID = UUID()
    @State private var simulationStatus = "Press Play to start the session."
    @State private var isSessionRunning = false
    @State private var expandedHistoryDays: Set<Date> = []
    @State private var selectedSpeed: SimulationSpeed = .twoX
    @State private var autoContinueEnabled = false
    @State private var stopLossAlert: StopLossAlertContext?
    @State private var stopLossDismissTask: Task<Void, Never>?
    @State private var simulationLoopTask: Task<Void, Never>?
    @FocusState private var focusedField: FieldFocus?

    private enum FieldFocus {
        case startingBet
        case tableTimer
        case warningBet
    }

    private var startingBet: Int {
        let value = Int(startingBetText) ?? 0
        return max(1, value)
    }

    private var tableTimer: Int {
        let value = Int(tableTimerText) ?? 20
        return max(1, value) // Prevent crashing from generating infinite hands at 0 seconds
    }

    private var warningBetLevel: Int {
        let value = Int(warningBetText) ?? 5
        return max(1, value)
    }

    private var stopLossOptions: [Int] {
        guard startingBet > 0 else { return [] }

        return (0..<Self.stopLossLevels).map { level in
            startingBet * (1 << level)
        }
    }

    private var defaultStopLossAmount: Int {
        let index = min(max(Self.defaultStopLossLevel - 1, 0), max(stopLossOptions.count - 1, 0))
        return stopLossOptions[index]
    }

    private var completedStopLossGroupIDs: Set<UUID> {
        Set(snapshotEntries.filter { $0.outcome == .stopLoss }.map(\.streakGroupID))
    }

    private var simulatedElapsedLabel: String {
        let elapsed = max(0, Int(currentTime.timeIntervalSince(simulationReferenceTime)))
        let days = elapsed / 86_400
        let hours = (elapsed % 86_400) / 3_600
        let minutes = (elapsed % 3_600) / 60
        return "\(days)d \(hours)h \(minutes)m"
    }

    private var groupedHistoryEntries: [(day: Date, entries: [BetHistoryEntry])] {
        let grouped = Dictionary(grouping: snapshotEntries) { entry in
            historyDay(for: entry.timestamp)
        }
        return grouped.keys.sorted(by: >).map { day in
            (day: day, entries: grouped[day] ?? [])
        }
    }

    private var profitHistory: [ProfitPoint] {
        var currentProfit = 0
        var points: [ProfitPoint] = []
        
        // Ensure starting point is exactly 0
        points.append(ProfitPoint(index: 0, profit: 0))
        
        // Reverse so we process oldest bets first
        for (index, entry) in snapshotEntries.reversed().enumerated() {
            switch entry.outcome {
            case .win:
                if entry.betSide == .tie {
                    currentProfit += entry.betAmount * 8
                } else {
                    currentProfit += entry.betAmount // Ignoring house commission for simplicity
                }
            case .loss, .stopLoss:
                currentProfit -= entry.betAmount
            case .push:
                break // No change in profit
            }
            points.append(ProfitPoint(index: index + 1, profit: currentProfit))
        }
        return points
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            simulatorTab
                .tabItem {
                    Label("Tables", systemImage: "square.grid.3x3.fill")
                }
                .tag(RootTab.simulator)

            historyTab
                .tabItem {
                    Label("History", systemImage: "clock.arrow.circlepath")
                }
                .tag(RootTab.history)
            
            analyticsTab
                .tabItem {
                    Label("Analytics", systemImage: "chart.pie.fill")
                }
                .tag(RootTab.analytics)
        }
        .preferredColorScheme(.dark)
        .tint(.white)
        .overlay {
            if let alert = stopLossAlert {
                stopLossOverlay(for: alert)
            }
        }
        .simultaneousGesture(
            TapGesture().onEnded {
                dismissKeyboard()
            }
        )
        .onAppear {
            simulationReferenceTime = currentTime
            applyStartingBetChanges(resetProgression: true)
            ensureCurrentHistoryDayExpanded()
            loadCaches()
            refreshData() // Load data initially
        }
        .onDisappear {
            stopSimulationLoop()
        }
        .onChange(of: startingBetText) { _, _ in
            applyStartingBetChanges(resetProgression: true)
        }
        .onChange(of: selectedSide) { _, _ in
            nextBetAmount = startingBet
            activeBet = nil
            simulationStatus = isSessionRunning
                ? "Bet side changed to \(selectedSide.rawValue). Waiting for a new table."
                : "Bet side changed to \(selectedSide.rawValue). Press Play to start the session."
        }
        .onChange(of: selectedStopLoss) { _, newValue in
            if nextBetAmount > newValue {
                nextBetAmount = startingBet
                activeBet = nil
                simulationStatus = "Stop loss updated to \(currencyString(newValue)). Progression reset."
            }
        }
        .onChange(of: currentTime) { _, _ in
            ensureCurrentHistoryDayExpanded()
        }
    }

    private var simulatorTab: some View {
        ZStack {
            backgroundView

            GeometryReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        headerCard

                        LazyVGrid(columns: compactColumns(for: proxy.size.width), spacing: 6) {
                            ForEach(tables) { table in
                                tableCard(for: table)
                            }
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.top, 10)
                    .padding(.bottom, 178)
                }
                .scrollDismissesKeyboard(.interactively)
            }
        }
        .safeAreaInset(edge: .bottom) {
            stickyControlsBar
        }
    }

    private var historyTab: some View {
        ZStack {
            backgroundView

            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("History")
                        .font(.title2.weight(.bold))
                        .foregroundStyle(.white)

                    Spacer()

                    // Manual refresh button
                    Button(action: refreshData) {
                        Image(systemName: "arrow.clockwise")
                    }
                    .font(.caption.weight(.semibold))
                    .buttonStyle(.bordered)
                    .tint(.blue)

                    Button("Clear", role: .destructive, action: clearHistory)
                        .font(.caption.weight(.semibold))
                        .buttonStyle(.bordered)
                        .tint(.red)
                        .disabled(snapshotEntries.isEmpty && snapshotDailyProfits.isEmpty && snapshotMaxLosses.isEmpty)
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)

                if saveHistoryEnabled {
                    // Show Total Earned when detailed history is on
                    HStack {
                        Text("Total Earned:")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                        Spacer()
                        Text(currencyString(totalProfit))
                            .font(.headline.weight(.bold))
                            .foregroundStyle(totalProfit >= 0 ? .green : .red)
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 4)

                    if snapshotEntries.isEmpty {
                        Spacer()
                        ContentUnavailableView(
                            "No History Yet",
                            systemImage: "clock.badge.xmark",
                            description: Text("Play a session to save detailed results here.")
                        )
                        .foregroundStyle(.white)
                        Spacer()
                    } else {
                        List {
                            ForEach(groupedHistoryEntries, id: \.day) { group in
                                DisclosureGroup(
                                    isExpanded: bindingForExpandedHistoryDay(group.day),
                                    content: {
                                        ForEach(group.entries) { entry in
                                            historyRow(entry, isHighlighted: completedStopLossGroupIDs.contains(entry.streakGroupID))
                                                .padding(.top, 6)
                                        }
                                    },
                                    label: {
                                        HStack {
                                            Text(group.day.formatted(date: .complete, time: .omitted))
                                                .font(.headline)
                                                .foregroundStyle(.white)

                                            Spacer()

                                            Text("\(group.entries.count)")
                                                .font(.caption.weight(.bold))
                                                .foregroundStyle(.white.opacity(0.75))
                                                .padding(.horizontal, 8)
                                                .padding(.vertical, 4)
                                                .background(Color.white.opacity(0.08))
                                                .clipShape(Capsule())
                                        }
                                    }
                                )
                                .tint(.white)
                                .listRowBackground(Color.white.opacity(0.06))
                            }
                        }
                        .scrollContentBackground(.hidden)
                        .background(Color.clear)
                    }
                } else {
                    if snapshotDailyProfits.isEmpty {
                        Spacer()
                        ContentUnavailableView(
                            "No Data",
                            systemImage: "calendar",
                            description: Text("Play a session to see your daily earnings.")
                        )
                        .foregroundStyle(.white)
                        Spacer()
                    } else {
                        List {
                            ForEach(snapshotDailyProfits.sorted(by: { $0.day > $1.day })) { record in
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(record.day.formatted(date: .abbreviated, time: .omitted))
                                            .font(.headline)
                                            .foregroundStyle(.white)
                                        Text("\(record.handsPlayed) hands played")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Text(currencyString(record.profit))
                                        .font(.body.weight(.bold))
                                        .foregroundStyle(record.profit >= 0 ? .green : .red)
                                }
                                .listRowBackground(Color.white.opacity(0.06))
                            }
                        }
                        .scrollContentBackground(.hidden)
                        .background(Color.clear)
                    }
                }
            }
        }
    }
    
    private var analyticsTab: some View {
        ZStack {
            backgroundView

            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Analytics")
                        .font(.title2.weight(.bold))
                        .foregroundStyle(.white)
                    
                    Spacer()
                    
                    // Manual refresh button
                    Button(action: refreshData) {
                        Image(systemName: "arrow.clockwise")
                    }
                    .font(.caption.weight(.semibold))
                    .buttonStyle(.bordered)
                    .tint(.blue)
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)

                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        maxLossSection

                        if saveHistoryEnabled {
                            if snapshotEntries.isEmpty {
                                ContentUnavailableView(
                                    "No Data",
                                    systemImage: "chart.pie",
                                    description: Text("Play a session to generate analytics.")
                                )
                                .foregroundStyle(.white)
                                .padding(.top, 40)
                            } else {
                                pieChartSection
                                profitChartSection
                            }
                        } else {
                            if snapshotDailyProfits.isEmpty {
                                ContentUnavailableView(
                                    "No Data",
                                    systemImage: "chart.line.uptrend.xyaxis",
                                    description: Text("Play a session to generate daily analytics.")
                                )
                                .foregroundStyle(.white)
                                .padding(.top, 40)
                            } else {
                                dailyProfitChartSection
                            }
                        }
                    }
                    .padding(.bottom, 40)
                }
            }
        }
    }

    private var maxLossSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Max Bet Losses (Stop Loss Hits)")
                .font(.headline)
                .foregroundStyle(.white)
            
            let hasData = snapshotMaxLosses.contains(where: { $0.maxLossCount > 0 })
            
            if !hasData {
                Text("No data yet.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                let sortedRecords = snapshotMaxLosses.sorted {
                    if $0.strategyName != $1.strategyName { return $0.strategyName < $1.strategyName }
                    if $0.warningLevel != $1.warningLevel { return $0.warningLevel < $1.warningLevel }
                    return $0.stopLossAmount < $1.stopLossAmount
                }
                
                ForEach(Array(sortedRecords.enumerated()), id: \.element.id) { index, record in
                    if record.maxLossCount > 0 {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                if record.strategyName == BettingStrategy.mod.rawValue {
                                    Text("\(record.strategyName) (Lvl \(record.warningLevel))")
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(.white)
                                } else {
                                    Text(record.strategyName)
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(.white)
                                }
                                Text("Stop Loss: \(currencyString(record.stopLossAmount))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text("\(record.maxLossCount)")
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(.red)
                        }
                        .padding(.vertical, 6)
                        
                        if index < sortedRecords.count - 1 {
                            Divider().background(Color.white.opacity(0.1))
                        }
                    }
                }
            }
        }
        .padding()
        .background(Color.white.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .padding(.horizontal, 16)
    }
    
    private var pieChartSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Result Distribution")
                .font(.headline)
                .foregroundStyle(.white)
            
            let counts = BaccaratSide.allCases.map { side in
                (side: side, count: snapshotEntries.filter { $0.result == side }.count)
            }
            
            Chart(counts, id: \.side) { item in
                SectorMark(
                    angle: .value("Count", item.count),
                    innerRadius: .ratio(0.5),
                    angularInset: 1.5
                )
                .foregroundStyle(item.side.color)
                .annotation(position: .overlay) {
                    if item.count > 0 {
                        Text("\(item.count)")
                            .font(.caption.bold())
                            .foregroundStyle(.white)
                            .shadow(radius: 2)
                    }
                }
            }
            .frame(height: 220)
            
            // Legend
            HStack(spacing: 16) {
                ForEach(BaccaratSide.allCases) { side in
                    HStack(spacing: 6) {
                        Circle().fill(side.color).frame(width: 10, height: 10)
                        Text(side.rawValue)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.white)
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 4)
        }
        .padding()
        .background(Color.white.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .padding(.horizontal, 16)
    }

    private var profitChartSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Cumulative Profit / Loss")
                .font(.headline)
                .foregroundStyle(.white)
            
            Chart {
                ForEach(profitHistory) { point in
                    LineMark(
                        x: .value("Bet #", point.index),
                        y: .value("Profit", point.profit)
                    )
                    .foregroundStyle(.cyan)
                    .interpolationMethod(.linear)
                    
                    AreaMark(
                        x: .value("Bet #", point.index),
                        y: .value("Profit", point.profit)
                    )
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.cyan.opacity(0.4), .clear],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .interpolationMethod(.linear)
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading) { value in
                    AxisGridLine().foregroundStyle(.white.opacity(0.1))
                    AxisValueLabel() {
                        if let intVal = value.as(Int.self) {
                            Text("\(intVal)")
                                .foregroundStyle(.white.opacity(0.7))
                        }
                    }
                }
            }
            .chartXAxis {
                AxisMarks { _ in
                    AxisGridLine().foregroundStyle(.white.opacity(0.1))
                }
            }
            .frame(height: 250)
        }
        .padding()
        .background(Color.white.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .padding(.horizontal, 16)
    }

    private var dailyProfitChartSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Cumulative Daily Profit")
                .font(.headline)
                .foregroundStyle(.white)
            
            let cumulativeData: [(day: Date, profit: Int)] = {
                var total = 0
                return snapshotDailyProfits.sorted(by: { $0.day < $1.day }).map { record in
                    total += record.profit
                    return (day: record.day, profit: total)
                }
            }()
            
            Chart {
                ForEach(cumulativeData, id: \.day) { point in
                    LineMark(
                        x: .value("Date", point.day),
                        y: .value("Profit", point.profit)
                    )
                    .foregroundStyle(.cyan)
                    .interpolationMethod(.linear)
                    
                    AreaMark(
                        x: .value("Date", point.day),
                        y: .value("Profit", point.profit)
                    )
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.cyan.opacity(0.4), .clear],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .interpolationMethod(.linear)
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading) { value in
                    AxisGridLine().foregroundStyle(.white.opacity(0.1))
                    AxisValueLabel() {
                        if let intVal = value.as(Int.self) {
                            Text("\(intVal)")
                                .foregroundStyle(.white.opacity(0.7))
                        }
                    }
                }
            }
            .chartXAxis {
                AxisMarks { value in
                    AxisGridLine().foregroundStyle(.white.opacity(0.1))
                    AxisValueLabel(format: .dateTime.month().day())
                }
            }
            .frame(height: 250)
        }
        .padding()
        .background(Color.white.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .padding(.horizontal, 16)
    }

    private var backgroundView: some View {
        LinearGradient(
            colors: [
                Color(red: 0.03, green: 0.05, blue: 0.09),
                Color(red: 0.07, green: 0.10, blue: 0.16)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
    }

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Menu {
                    ForEach(BettingStrategy.allCases, id: \.self) { strat in
                        Button(strat.rawValue) {
                            strategy = strat
                            applyStartingBetChanges(resetProgression: true)
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(strategy.rawValue)
                            .font(.title2.weight(.bold))
                            .foregroundStyle(.white)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.white.opacity(0.7))
                    }
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 2) {
                    Text("Total Earned")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(currencyString(totalProfit))
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(totalProfit >= 0 ? .green : .red)
                }
            }

            HStack(spacing: 12) {
                headerPill(title: "Current", value: currencyString(activeBet?.amount ?? nextBetAmount))
                headerPill(title: "Table", value: activeBet.map { "T\($0.tableID)" } ?? "--")
                if strategy == .mod {
                    headerPill(title: "Queued", value: "\(storedBetsQueue.count)")
                }
                headerPill(title: "Status", value: isSessionRunning ? "Running" : "Stopped")
                headerPill(title: "Speed", value: selectedSpeed.label)
            }

            Text(simulationStatus)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .padding(12)
        .background(Color.white.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.white.opacity(0.08))
        }
    }

    private func headerPill(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.white)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var stickyControlsBar: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                compactField(title: "Bet", content: {
                    TextField("Bet", text: $startingBetText)
                        .keyboardType(.numberPad)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.white)
                        .focused($focusedField, equals: .startingBet)
                })

                compactField(title: "Stop", content: {
                    Menu {
                        ForEach(stopLossOptions, id: \.self) { amount in
                            Button(currencyString(amount)) {
                                selectedStopLoss = amount
                            }
                        }
                    } label: {
                        dropdownLabel(text: currencyString(selectedStopLoss), tint: .white)
                    }
                })

                compactField(title: "Timer", content: {
                    TextField("Sec", text: $tableTimerText)
                        .keyboardType(.numberPad)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.white)
                        .focused($focusedField, equals: .tableTimer)
                })
            }

            HStack(spacing: 8) {
                compactField(title: "Side", content: {
                    Menu {
                        ForEach(BaccaratSide.allCases) { side in
                            Button(side.rawValue) {
                                selectedSide = side
                            }
                        }
                    } label: {
                        dropdownLabel(text: selectedSide.rawValue, tint: selectedSide.color)
                    }
                })
                
                if strategy == .mod {
                    compactField(title: "Warning", content: {
                        TextField("Level", text: $warningBetText)
                            .keyboardType(.numberPad)
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.white)
                            .focused($focusedField, equals: .warningBet)
                    })
                }

                compactField(title: "Speed", content: {
                    Menu {
                        ForEach(SimulationSpeed.allCases) { speed in
                            Button(speed.label) {
                                selectedSpeed = speed
                            }
                        }
                    } label: {
                        dropdownLabel(text: selectedSpeed.label, tint: .white)
                    }
                })
            }

            HStack(spacing: 12) {
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Auto Continue")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                        Text(autoContinueEnabled ? "On" : "Off")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    Toggle("", isOn: $autoContinueEnabled)
                        .labelsHidden()
                        .tint(.green)
                }
                
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Save History")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                        Text(saveHistoryEnabled ? "On" : "Off")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    Toggle("", isOn: $saveHistoryEnabled)
                        .labelsHidden()
                        .tint(.green)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text("Sim Time")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white)
                    Text(simulatedElapsedLabel)
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 8) {
                stickyButton(title: isSessionRunning ? "Pause" : "Play", systemImage: isSessionRunning ? "pause.fill" : "play.fill", tint: .green, action: toggleSession)
                stickyButton(title: "Stop", systemImage: "stop.fill", tint: .red, action: stopAndResetSimTime)
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .background(.ultraThinMaterial)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Color.white.opacity(0.08))
                .frame(height: 1)
        }
    }

    private func compactField<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)

            content()
                .padding(.horizontal, 10)
                .frame(maxWidth: .infinity, minHeight: 34, alignment: .leading)
                .background(Color.white.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity)
    }

    private func dropdownLabel(text: String, tint: Color) -> some View {
        HStack(spacing: 8) {
            Text(text)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.75)

            Spacer(minLength: 0)

            Image(systemName: "chevron.down")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.7))
        }
        .contentShape(Rectangle())
    }

    private func stickyButton(title: String, systemImage: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.footnote.weight(.bold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
        }
        .buttonStyle(.borderedProminent)
        .tint(tint.opacity(0.8))
    }

    private func compactColumns(for width: CGFloat) -> [GridItem] {
        let columnCount = width > 700 ? 10 : width > 500 ? 8 : 6
        return Array(repeating: GridItem(.flexible(), spacing: 6), count: columnCount)
    }

    private func tableCard(for table: BaccaratTable) -> some View {
        let secondsRemaining = max(0, Int(ceil(table.nextResultDate.timeIntervalSince(currentTime))))
        let isActiveTable = activeBet?.tableID == table.id

        return VStack(spacing: 4) {
            HStack(spacing: 4) {
                Text("T\(table.id)")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.white)

                Spacer(minLength: 0)

                if isActiveTable {
                    coinMarker
                }
            }

            Text(table.result == .tie ? "TIE" : String(table.result.rawValue.first ?? "B"))
                .font(.system(size: table.result == .tie ? 14 : 18, weight: .bold, design: .rounded))
                .foregroundStyle(table.result.color)

            Text("\(secondsRemaining)s")
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(.white.opacity(0.9))

            if let activeBet, activeBet.tableID == table.id {
                Text(currencyString(activeBet.amount))
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .foregroundStyle(.yellow)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, minHeight: 72)
        .background(Color.white.opacity(isActiveTable ? 0.14 : 0.06))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(isActiveTable ? selectedSide.color.opacity(0.7) : Color.white.opacity(0.08))
        }
    }

    private func historyRow(_ entry: BetHistoryEntry, isHighlighted: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(entry.outcome.rawValue)
                    .font(.caption.weight(.bold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background((isHighlighted ? Color.red : entry.outcome.color).opacity(0.22))
                    .foregroundStyle(isHighlighted ? Color.red : entry.outcome.color)
                    .clipShape(Capsule())

                Spacer()

                Text(Self.detailedDateFormatter.string(from: entry.timestamp))
                    .font(.caption)
                    .foregroundStyle(isHighlighted ? Color.red.opacity(0.82) : .secondary)
            }

            Text("Table \(entry.tableID) • \(currencyString(entry.betAmount)) on \(entry.betSide.rawValue)")
                .font(.body.weight(.semibold))
                .foregroundStyle(isHighlighted ? Color.red.opacity(0.94) : .white)

            Text("Result: \(entry.result.rawValue) • Streak \(entry.streakStep)")
                .font(.caption)
                .foregroundStyle(isHighlighted ? Color.red.opacity(0.82) : .secondary)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 6)
        .background(isHighlighted ? Color.red.opacity(0.08) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    @ViewBuilder
    private func stopLossOverlay(for alert: StopLossAlertContext) -> some View {
        if alert.autoContinued {
            VStack {
                HStack {
                    Spacer()

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Stop Loss Hit")
                            .font(.headline.weight(.bold))
                            .foregroundStyle(.white)

                        Text(alert.message)
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.86))

                        Button("Stop Simulator", action: haltFromStopLoss)
                            .font(.caption.weight(.bold))
                            .buttonStyle(.borderedProminent)
                            .tint(.red)
                    }
                    .padding(14)
                    .frame(maxWidth: 320, alignment: .leading)
                    .background(Color.black.opacity(0.82))
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.08))
                    }
                }
                .padding(.top, 16)
                .padding(.horizontal, 16)

                Spacer()
            }
            .transition(.move(edge: .top).combined(with: .opacity))
        } else {
            ZStack {
                Color.black.opacity(0.45)
                    .ignoresSafeArea()

                VStack(alignment: .leading, spacing: 14) {
                    Text("Stop Loss Hit")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(.white)

                    Text(alert.message)
                        .font(.body)
                        .foregroundStyle(.white.opacity(0.86))

                    HStack(spacing: 10) {
                        stickyButton(title: "Continue", systemImage: "play.fill", tint: .green, action: continueAfterStopLoss)
                        stickyButton(title: "Stop", systemImage: "stop.fill", tint: .red, action: haltFromStopLoss)
                    }
                }
                .padding(18)
                .frame(maxWidth: 340)
                .background(Color(red: 0.08, green: 0.10, blue: 0.16))
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.08))
                }
                .padding(.horizontal, 20)
            }
            .transition(.opacity)
        }
    }

    private var coinMarker: some View {
        Circle()
            .fill(
                RadialGradient(
                    colors: [
                        Color.yellow.opacity(0.98),
                        Color.orange.opacity(0.95),
                        Color.brown.opacity(0.90)
                    ],
                    center: .topLeading,
                    startRadius: 2,
                    endRadius: 18
                )
            )
            .frame(width: 18, height: 18)
            .overlay {
                Circle()
                    .strokeBorder(Color.white.opacity(0.35), lineWidth: 1)
            }
    }

    private func processSimulation(until targetTime: Date) {
        guard targetTime > currentTime else { return }

        var processedEvents = 0
        var lastProcessedTime = currentTime
        var historyDidChange = false

        // Dynamic per-tick cap to avoid main-thread starvation
        let baseCap = 25_000
        let speedFactor = max(1, selectedSpeed.rawValue / 100)
        let maxEventsThisTick = min(200_000, baseCap * speedFactor)

        while let index = nextDueTableIndex(onOrBefore: targetTime), processedEvents < maxEventsThisTick {
            let eventTime = tables[index].nextResultDate
            let newResult = BaccaratSide.randomWeighted()
            tables[index].result = newResult
            tables[index].nextResultDate = eventTime.addingTimeInterval(TimeInterval(tableTimer))
            lastProcessedTime = eventTime

            if activeBet?.tableID == tables[index].id {
                // Save the table that just resolved to avoid immediately selecting it again
                let currentTableID = tables[index].id
                let resolution = resolveActiveBet(with: newResult, eventTime: eventTime)
                if resolution != .none { historyDidChange = true }

                if resolution == .stopLoss {
                    if autoContinueEnabled {
                        queueNextBaseBet(at: eventTime, previousTableID: currentTableID)
                    } else {
                        currentTime = eventTime
                        if historyDidChange {
                            try? modelContext.save()
                        }
                        return
                    }
                } else {
                    ensureActiveBet(at: eventTime, previousTableID: currentTableID)
                }
            }

            processedEvents += 1
        }

        // If we hit our cap, advance only to the last processed event to prevent an ever-growing backlog.
        if processedEvents >= maxEventsThisTick {
            currentTime = lastProcessedTime
        } else {
            currentTime = processedEvents > 0 ? max(lastProcessedTime, targetTime) : targetTime
        }

        if historyDidChange {
            try? modelContext.save()
        }
    }

    private func nextDueTableIndex(onOrBefore targetTime: Date) -> Int? {
        tables.enumerated()
            .filter { $0.element.nextResultDate <= targetTime }
            .min { $0.element.nextResultDate < $1.element.nextResultDate }?
            .offset
    }

    private func updateDailyProfit(for eventTime: Date, profitChange: Int) {
        let day = Calendar.current.startOfDay(for: eventTime)
        if let record = dailyProfitsCache[day] {
            record.profit += profitChange
            record.handsPlayed += 1
        } else {
            let newRecord = DailyProfitRecord(day: day, profit: profitChange, handsPlayed: 1)
            modelContext.insert(newRecord)
            dailyProfitsCache[day] = newRecord
        }
    }

    private func incrementMaxLoss() {
        let key = strategy == .mod ? "Mod-\(warningBetLevel)-\(selectedStopLoss)" : "Classic-0-\(selectedStopLoss)"
        
        if let record = maxLossCache[key] {
            record.maxLossCount += 1
        } else {
            let newRecord = StrategyMaxLossRecord(
                id: key,
                maxLossCount: 1,
                strategyName: strategy.rawValue,
                stopLossAmount: selectedStopLoss,
                warningLevel: strategy == .mod ? warningBetLevel : 0
            )
            modelContext.insert(newRecord)
            maxLossCache[key] = newRecord
        }
    }

    private func resolveActiveBet(with result: BaccaratSide, eventTime: Date) -> BetResolution {
        guard let activeBet else { return .none }
        // Removed speed cap from allowHistory per instructions
        // let allowHistory = saveHistoryEnabled && selectedSpeed.rawValue < 3200
        var profitChange = 0

        if result == activeBet.side {
            profitChange = (result == .tie) ? activeBet.amount * 8 : activeBet.amount
            totalProfit += profitChange
            updateDailyProfit(for: eventTime, profitChange: profitChange)
            
            if saveHistoryEnabled {
                appendHistory(for: activeBet, result: result, outcome: .win, timestamp: eventTime)
            }
            
            if strategy == .mod, !storedBetsQueue.isEmpty {
                nextBetAmount = storedBetsQueue.removeFirst()
                nextStreakStep = 1
                currentStreakGroupID = UUID()
                simulationStatus = "Win on Table \(activeBet.tableID). Playing queued bet \(currencyString(nextBetAmount))."
            } else {
                nextBetAmount = startingBet
                nextStreakStep = 1
                currentStreakGroupID = UUID()
                simulationStatus = "Win on Table \(activeBet.tableID). Resetting to \(currencyString(startingBet))."
            }
            
            self.activeBet = nil
            return .win
        }
        
        if result == .tie {
            updateDailyProfit(for: eventTime, profitChange: 0)
            if saveHistoryEnabled {
                appendHistory(for: activeBet, result: result, outcome: .push, timestamp: eventTime)
            }
            simulationStatus = "Tie on Table \(activeBet.tableID). Bet pushed."
            self.activeBet = nil
            return .push
        }

        profitChange = -activeBet.amount
        totalProfit += profitChange
        updateDailyProfit(for: eventTime, profitChange: profitChange)

        if activeBet.amount >= selectedStopLoss {
            incrementMaxLoss()
            if saveHistoryEnabled {
                appendHistory(for: activeBet, result: result, outcome: .stopLoss, timestamp: eventTime)
            }
            nextBetAmount = startingBet
            nextStreakStep = 1
            currentStreakGroupID = UUID()
            storedBetsQueue.removeAll() // Clear queue on Stop Loss to prevent catastrophic follow-up bets
            let message = "Loss on Table \(activeBet.tableID) at \(currencyString(activeBet.amount))."
            presentStopLossAlert(
                message: autoContinueEnabled
                    ? "\(message) Auto Continue placed the next base bet."
                    : "\(message) Continue to start again from \(currencyString(startingBet)).",
                autoContinued: autoContinueEnabled
            )
            simulationStatus = autoContinueEnabled
                ? "Loss on Table \(activeBet.tableID) at \(currencyString(activeBet.amount)). Auto continuing from \(currencyString(startingBet))."
                : "Loss on Table \(activeBet.tableID) at \(currencyString(activeBet.amount)). Waiting for your decision."
            self.activeBet = nil
            if !autoContinueEnabled {
                isSessionRunning = false
            }
            return .stopLoss
        }

        if saveHistoryEnabled {
            appendHistory(for: activeBet, result: result, outcome: .loss, timestamp: eventTime)
        }
        
        let doubledBet = min(activeBet.amount * 2, selectedStopLoss)
        
        if strategy == .mod, activeBet.streakStep == warningBetLevel {
            storedBetsQueue.append(doubledBet)
            nextBetAmount = startingBet
            nextStreakStep = 1
            currentStreakGroupID = UUID()
            simulationStatus = "Warning hit on Table \(activeBet.tableID). Stored \(currencyString(doubledBet)). Resetting to \(currencyString(startingBet))."
        } else {
            nextBetAmount = doubledBet
            nextStreakStep = activeBet.streakStep + 1
            simulationStatus = "Loss on Table \(activeBet.tableID). Next bet is \(currencyString(doubledBet)) on \(selectedSide.rawValue)."
        }
        
        self.activeBet = nil
        return .loss
    }

    private func randomEligibleTable(after time: Date, excluding previousTableID: Int? = nil) -> BaccaratTable? {
        let eligibleTables = tables.filter { table in
            guard table.nextResultDate > time else { return false }

            if let previousTableID {
                return table.id != previousTableID
            }

            return true
        }

        return eligibleTables.randomElement()
    }

    private func setActiveBet(on table: BaccaratTable, updateStatus: Bool) {
        activeBet = ActiveBet(
            tableID: table.id,
            amount: nextBetAmount,
            side: selectedSide,
            streakStep: nextStreakStep,
            streakGroupID: currentStreakGroupID
        )

        if updateStatus {
            simulationStatus = "Betting \(currencyString(nextBetAmount)) on \(selectedSide.rawValue) at Table \(table.id) • Streak \(nextStreakStep)."
        }
    }

    private func ensureActiveBet(at time: Date, previousTableID: Int? = nil) {
        if let activeBet,
           let activeTable = tables.first(where: { $0.id == activeBet.tableID }),
           activeTable.nextResultDate <= time {
            self.activeBet = nil
        }

        guard activeBet == nil, !tables.isEmpty else { return }
        guard let nextTable = randomEligibleTable(after: time, excluding: previousTableID) else { return }

        setActiveBet(on: nextTable, updateStatus: true)
    }

    private func queueNextBaseBet(at time: Date, previousTableID: Int? = nil) {
        guard activeBet == nil, !tables.isEmpty else { return }

        guard let nextTable = randomEligibleTable(after: time, excluding: previousTableID) else { return }

        setActiveBet(on: nextTable, updateStatus: false)
    }

    private func durationToTimeInterval(_ duration: Duration) -> TimeInterval {
        let components = duration.components
        return TimeInterval(components.seconds) + (TimeInterval(components.attoseconds) / 1_000_000_000_000_000_000)
    }

    @MainActor
    private func advanceSimulation(realSecondsElapsed: TimeInterval) {
        guard isSessionRunning else { return }
        if !autoContinueEnabled && stopLossAlert != nil { return }

        let simulatedSecondsToAdvance = Double(selectedSpeed.rawValue) * realSecondsElapsed
        let targetTime = currentTime.addingTimeInterval(simulatedSecondsToAdvance)

        processSimulation(until: targetTime)

        if autoContinueEnabled || stopLossAlert == nil {
            ensureActiveBet(at: currentTime)
        }
    }

    @MainActor
    private func startSimulationLoop() {
        stopSimulationLoop()

        simulationLoopTask = Task {
            let clock = ContinuousClock()
            var lastInstant = clock.now

            while !Task.isCancelled {
                try? await clock.sleep(for: Self.simulationLoopInterval)

                let now = clock.now
                let elapsed = durationToTimeInterval(lastInstant.duration(to: now))
                lastInstant = now

                await MainActor.run {
                    advanceSimulation(realSecondsElapsed: elapsed)
                }
            }
        }
    }

    @MainActor
    private func stopSimulationLoop() {
        simulationLoopTask?.cancel()
        simulationLoopTask = nil
    }

    private func toggleSession() {
        isSessionRunning.toggle()

        if isSessionRunning {
            startSimulationLoop()
            simulationStatus = activeBet == nil
                ? "Session started. Selecting a table for \(currencyString(nextBetAmount))."
                : "Session resumed."
            ensureActiveBet(at: currentTime)
        } else {
            stopSimulationLoop()
            simulationStatus = "Session paused."
        }
    }

    private func stopAndResetSimTime() {
        dismissStopLossPopup()
        isSessionRunning = false
        stopSimulationLoop()
        activeBet = nil
        nextBetAmount = startingBet
        nextStreakStep = 1
        currentStreakGroupID = UUID()
        storedBetsQueue.removeAll()
        
        // Reset Time and Tables back to Zero base
        let now = Date()
        currentTime = now
        simulationReferenceTime = now
        tables = Self.makeInitialTables(countdown: tableTimer, now: now)
        
        simulationStatus = "Session stopped. Sim Time reset. Press Play to start again."
    }

    private func haltFromStopLoss() {
        dismissStopLossPopup()
        isSessionRunning = false
        stopSimulationLoop()
        activeBet = nil
        nextBetAmount = startingBet
        nextStreakStep = 1
        currentStreakGroupID = UUID()
        storedBetsQueue.removeAll()
        
        simulationStatus = "Session stopped from Stop Loss. Press Play to start again."
    }

    private func continueAfterStopLoss() {
        dismissStopLossPopup()
        isSessionRunning = true
        startSimulationLoop()
        simulationStatus = "Continuing after stop loss from \(currencyString(startingBet))."
        ensureActiveBet(at: currentTime)
    }

    private func dismissStopLossPopup() {
        stopLossDismissTask?.cancel()
        stopLossDismissTask = nil
        stopLossAlert = nil
    }

    private func presentStopLossAlert(message: String, autoContinued: Bool) {
        dismissStopLossPopup()

        let alert = StopLossAlertContext(message: message, autoContinued: autoContinued)
        stopLossAlert = alert

        guard autoContinued else { return }

        stopLossDismissTask = Task {
            try? await Task.sleep(for: .seconds(2.5))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                if stopLossAlert?.id == alert.id {
                    dismissStopLossPopup()
                }
            }
        }
    }

    // Loads the caches into memory so we can update them in a microsecond
    private func loadCaches() {
        if let dailies = try? modelContext.fetch(FetchDescriptor<DailyProfitRecord>()) {
            for d in dailies {
                dailyProfitsCache[d.day] = d
            }
        }
        if let maxLosses = try? modelContext.fetch(FetchDescriptor<StrategyMaxLossRecord>()) {
            for m in maxLosses {
                maxLossCache[m.id] = m
            }
        }
    }

    // Fetches the latest data manually from the database.
    private func refreshData() {
        do {
            let desc1 = FetchDescriptor<BetHistoryEntry>(sortBy: [SortDescriptor(\.timestamp, order: .reverse)])
            snapshotEntries = try modelContext.fetch(desc1)
            
            let desc2 = FetchDescriptor<DailyProfitRecord>(sortBy: [SortDescriptor(\.day, order: .reverse)])
            snapshotDailyProfits = try modelContext.fetch(desc2)

            let desc3 = FetchDescriptor<StrategyMaxLossRecord>()
            snapshotMaxLosses = try modelContext.fetch(desc3)
        } catch {
            print("Failed to fetch data: \(error)")
        }
    }

    private func appendHistory(for activeBet: ActiveBet, result: BaccaratSide, outcome: BetOutcome, timestamp: Date) {
        let newEntry = BetHistoryEntry(
            id: UUID(),
            timestamp: timestamp,
            tableID: activeBet.tableID,
            betAmount: activeBet.amount,
            betSide: activeBet.side,
            result: result,
            outcome: outcome,
            streakStep: activeBet.streakStep,
            streakGroupID: activeBet.streakGroupID
        )
        modelContext.insert(newEntry)
    }

    private func clearHistory() {
        // Clear UI snapshots immediately to keep UI responsive
        snapshotEntries = []
        snapshotDailyProfits = []
        snapshotMaxLosses = []
        dailyProfitsCache.removeAll()
        maxLossCache.removeAll()
        totalProfit = 0

        do {
            // Instantly wipe all models using SwiftData's native batch delete API
            try modelContext.delete(model: BetHistoryEntry.self)
            try modelContext.delete(model: DailyProfitRecord.self)
            try modelContext.delete(model: StrategyMaxLossRecord.self)
            try modelContext.save()
        } catch {
            print("Failed to clear history: \(error)")
        }
    }

    private func applyStartingBetChanges(resetProgression: Bool) {
        guard !stopLossOptions.isEmpty else { return }

        if !stopLossOptions.contains(selectedStopLoss) {
            selectedStopLoss = defaultStopLossAmount
        }

        if resetProgression {
            nextBetAmount = startingBet
            nextStreakStep = 1
            currentStreakGroupID = UUID()
            activeBet = nil
            storedBetsQueue.removeAll()
            simulationStatus = isSessionRunning
                ? "Starting bet set to \(currencyString(startingBet)). Waiting for a new table."
                : "Starting bet set to \(currencyString(startingBet)). Press Play to start the session."
        }
    }

    private func currencyString(_ amount: Int) -> String {
        Self.pesoFormatter.string(from: NSNumber(value: amount)) ?? "PHP \(amount)"
    }

    private func dismissKeyboard() {
        focusedField = nil
    }

    private func historyDay(for date: Date) -> Date {
        Calendar.current.startOfDay(for: date)
    }

    private func bindingForExpandedHistoryDay(_ day: Date) -> Binding<Bool> {
        Binding(
            get: { expandedHistoryDays.contains(day) },
            set: { isExpanded in
                if isExpanded {
                    expandedHistoryDays.insert(day)
                } else {
                    expandedHistoryDays.remove(day)
                }
            }
        )
    }

    private func ensureCurrentHistoryDayExpanded() {
        expandedHistoryDays.insert(historyDay(for: currentTime))
    }

    fileprivate static func makeInitialTables(countdown: Int, now: Date = Date()) -> [BaccaratTable] {
        return (1...tableCount).map { number in
            BaccaratTable(
                id: number,
                name: "Table \(number)",
                result: .randomWeighted(),
                nextResultDate: now.addingTimeInterval(TimeInterval(Int.random(in: 1...max(1, countdown))))
            )
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
