import Foundation
import SwiftUI
import AppKit
import ArxivResearchCore

private enum WorkspaceTheme {
    static let accent = Color(red: 0.27, green: 0.29, blue: 0.78)
    static let pageBackground = Color(red: 0.982, green: 0.982, blue: 0.982)
    static let sidebarBackground = Color(red: 0.965, green: 0.965, blue: 0.968)
    static let selectedNavigation = Color(red: 0.922, green: 0.914, blue: 0.933)
}

enum WorkspaceDestination: String, CaseIterable, Identifiable {
    case briefing
    case library
    case subscriptions
    case saved
    case activity

    var id: String { rawValue }

    var title: String {
        switch self {
        case .briefing: "Briefing"
        case .library: "Library"
        case .subscriptions: "Subscriptions"
        case .saved: "Saved"
        case .activity: "Activity"
        }
    }

    var systemImage: String {
        switch self {
        case .briefing: "sun.max"
        case .library: "books.vertical"
        case .subscriptions: "calendar.badge.clock"
        case .saved: "bookmark"
        case .activity: "clock"
        }
    }
}

enum BriefingTab: String, CaseIterable, Identifiable {
    case topPicks = "Top picks"
    case allNew = "All new"
    case unread = "Unread"

    var id: String { rawValue }
}

struct ResearchWorkspaceView: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.openSettings) private var openSettings
    @Environment(\.scenePhase) private var scenePhase
    @State private var destination = WorkspaceDestination.briefing
    @State private var briefingTab = BriefingTab.topPicks
    @State private var searchText = ""
    @State private var isLibraryPrimed = false
    @State private var isLibraryContextRailVisible = true
    @FocusState private var isSearchFocused: Bool

    var body: some View {
        GeometryReader { geometry in
            HStack(spacing: 0) {
                BriefingNavigationRail(
                    destination: $destination,
                    openSettings: openSettings
                )
                .frame(width: navigationWidth(for: geometry.size.width))
                Divider()
                content
            }
        }
        .frame(minWidth: 1_280, minHeight: 760)
        .tint(WorkspaceTheme.accent)
        .toolbar {
            ToolbarItemGroup(placement: .navigation) {
                Button {
                    destination = .briefing
                } label: {
                    Image(systemName: "chevron.left")
                }
                .disabled(destination == .briefing)
                .help("Back to briefing")

                Button {} label: {
                    Image(systemName: "chevron.right")
                }
                .disabled(true)
                .help("Forward")
            }

            ToolbarItem(placement: .principal) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("Search arXiv papers, authors, topics…", text: $searchText)
                        .textFieldStyle(.plain)
                        .focused($isSearchFocused)
                    Text("⌘K")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .frame(minWidth: 340, idealWidth: 540, maxWidth: 620)
                .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
                .overlay {
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color(nsColor: .separatorColor).opacity(0.7), lineWidth: 1)
                }
            }

            ToolbarItemGroup(placement: .primaryAction) {
                if destination == .library {
                    Button {
                        withAnimation(.snappy) {
                            isLibraryContextRailVisible.toggle()
                        }
                    } label: {
                        Label("Context", systemImage: "sidebar.right")
                    }
                    .labelStyle(.titleAndIcon)
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .help("Show or hide the Library context rail")
                } else {
                    Button {
                        state.beginNewQuery()
                    } label: {
                        Label("New Subscription", systemImage: "plus")
                    }
                    .labelStyle(.titleAndIcon)
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .help("Create a new arXiv subscription")

                    Button {
                        withAnimation(.snappy) {
                            state.isActivityRailVisible.toggle()
                        }
                    } label: {
                        Label("Activity", systemImage: "waveform.path.ecg")
                    }
                    .labelStyle(.titleAndIcon)
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .help("Show automation health and recent activity")
                }

                Menu {
                    Button("Reload Library", systemImage: "arrow.clockwise") {
                        state.reload()
                    }
                    Button("Run Pending Jobs", systemImage: "play.circle") {
                        Task { await state.runPendingJobs() }
                    }
                    .disabled(state.pendingJobCount == 0)
                    Divider()
                    Button("Settings…", systemImage: "gearshape") {
                        openSettings()
                    }
                } label: {
                    Label("More", systemImage: "ellipsis")
                }
                .controlSize(.large)
            }
        }
        .safeAreaInset(edge: .bottom) {
            StatusBarView()
        }
        .sheet(isPresented: $state.isShowingQueryEditor) {
            QueryEditorSheetView(profile: state.editingQueryProfile)
                .environmentObject(state)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                state.refreshExternalChanges()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .arxivFocusPaperSearch)) { _ in
            destination = .briefing
            isSearchFocused = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .arxivShowActivity)) { _ in
            destination = .briefing
            withAnimation(.snappy) {
                state.isActivityRailVisible = true
            }
        }
        .task {
            guard !isLibraryPrimed else { return }
            // Build the retained Library after the first Briefing frame so the
            // first navigation never has to construct its full hierarchy.
            do {
                try await Task.sleep(for: .milliseconds(180))
            } catch {
                return
            }
            isLibraryPrimed = true
        }
    }

    private func navigationWidth(for totalWidth: CGFloat) -> CGFloat {
        min(max(totalWidth * 0.15, 220), 240)
    }

    @ViewBuilder
    private var content: some View {
        ZStack {
            DailyBriefingView(
                selectedTab: $briefingTab,
                searchText: searchText,
                openPaper: {
                    destination = .library
                },
                openActivity: {
                    destination = .activity
                }
            )
            .opacity(destination == .briefing ? 1 : 0)
            .allowsHitTesting(destination == .briefing)
            .accessibilityHidden(destination != .briefing)
            .zIndex(destination == .briefing ? 1 : 0)

            if isLibraryPrimed || destination == .library {
                LibraryWorkspaceView(
                    searchText: searchText,
                    isPrimed: $isLibraryPrimed,
                    isContextRailVisible: $isLibraryContextRailVisible
                )
                .opacity(destination == .library ? 1 : 0)
                .allowsHitTesting(destination == .library)
                .accessibilityHidden(destination != .library)
                .zIndex(destination == .library ? 1 : 0)
            }

            switch destination {
            case .subscriptions:
                SubscriptionOverviewView()
                    .zIndex(1)
            case .saved:
                SavedPapersView(openPaper: { destination = .library })
                    .zIndex(1)
            case .activity:
                FullActivityView()
                    .zIndex(1)
            case .briefing, .library:
                EmptyView()
            }
        }
    }
}

private struct BriefingNavigationRail: View {
    @EnvironmentObject private var state: AppState
    @Binding var destination: WorkspaceDestination
    let openSettings: OpenSettingsAction
    @State private var libraryDatesExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(WorkspaceDestination.allCases) { item in
                navigationButton(for: item)

                if item == .library, destination == .library, libraryDatesExpanded {
                    LibraryDateNavigation(destination: $destination)
                        .transition(.opacity)
                }
            }

            Divider()
                .padding(.vertical, 8)

            Button {
                openSettings()
            } label: {
                Label("Settings", systemImage: "gearshape")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())

            Spacer()

            VStack(alignment: .leading, spacing: 3) {
                Text("ArxivResearch")
                    .font(.caption.weight(.semibold))
                Text("Local research workspace")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(12)
        }
        .padding(.top, 10)
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity)
        .background(WorkspaceTheme.sidebarBackground)
    }

    private func navigationButton(for item: WorkspaceDestination) -> some View {
        Button {
            if item == .library {
                if destination == .library {
                    libraryDatesExpanded.toggle()
                } else {
                    destination = .library
                    libraryDatesExpanded = true
                }
            } else {
                destination = item
                libraryDatesExpanded = false
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: item.systemImage)
                    .font(.system(size: 16))
                    .frame(width: 22)
                Text(item.title)
                    .font(.body)
                Spacer(minLength: 8)

                if item == .library {
                    Text("\(state.papers.count)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                    Image(systemName: libraryDatesExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                } else if item == .saved {
                    Text("\(state.savedPaperCount)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if item == .activity, state.failedJobs.count > 0 {
                    Text("\(state.failedJobs.count)")
                        .font(.caption2.bold())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.red, in: Capsule())
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .foregroundStyle(destination == item ? WorkspaceTheme.accent : .primary)
            .background(
                destination == item ? WorkspaceTheme.selectedNavigation : .clear,
                in: RoundedRectangle(cornerRadius: 7)
            )
            .overlay(alignment: .leading) {
                if destination == item {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(WorkspaceTheme.accent)
                        .frame(width: 3, height: 26)
                        .offset(x: -12)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .accessibilityAddTraits(destination == item ? .isSelected : [])
    }
}

private struct LibraryDateNavigation: View {
    @EnvironmentObject private var state: AppState
    @Binding var destination: WorkspaceDestination

    var body: some View {
        let weekBucket = state.libraryWeekBucket
        let dateBuckets = state.libraryDateBuckets

        VStack(alignment: .leading, spacing: 5) {
            Menu {
                Picker("Date field", selection: dateFieldBinding) {
                    ForEach(PaperDateField.allCases, id: \.self) { field in
                        Text(field.displayName).tag(field)
                    }
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "calendar.badge.clock")
                        .frame(width: 18)
                    Text("Group by")
                    Spacer()
                    Text(state.libraryDateField.displayName)
                        .foregroundStyle(WorkspaceTheme.accent)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .font(.caption)
                .padding(.horizontal, 10)
                .frame(maxWidth: .infinity, minHeight: 34)
                .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 7))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
            .help("Count papers by the date they were added locally, published, or updated on arXiv")

            ScrollView {
                LazyVStack(spacing: 2) {
                    dateButton(
                        title: "All dates",
                        count: state.papers.count,
                        selection: .all,
                        systemImage: "calendar"
                    )
                    dateButton(
                        title: weekBucket.title,
                        count: weekBucket.count,
                        selection: weekBucket.selection,
                        systemImage: "calendar.badge.checkmark"
                    )

                    ForEach(dateBuckets) { bucket in
                        dateButton(
                            title: displayTitle(for: bucket.selection, fallback: bucket.title),
                            count: bucket.count,
                            selection: bucket.selection,
                            systemImage: "calendar.day.timeline.left"
                        )
                    }
                }
            }
            .scrollIndicators(.automatic)
            .frame(maxHeight: 232)
        }
        .padding(.leading, 24)
        .padding(.trailing, 4)
        .padding(.bottom, 4)
    }

    private var dateFieldBinding: Binding<PaperDateField> {
        Binding {
            state.libraryDateField
        } set: { field in
            guard state.libraryDateField != field else { return }
            state.libraryDateField = field
            state.sidebarSelection = .all
            destination = .library
        }
    }

    private func dateButton(
        title: String,
        count: Int,
        selection: LibrarySidebarSelection,
        systemImage: String
    ) -> some View {
        let isSelected = state.sidebarSelection == selection
        return Button {
            state.sidebarSelection = selection
            destination = .library
        } label: {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.caption)
                    .frame(width: 18)
                Text(title)
                    .lineLimit(1)
                Spacer(minLength: 6)
                Text("\(count)")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.quaternary, in: Capsule())
            }
            .font(.caption)
            .foregroundStyle(isSelected ? WorkspaceTheme.accent : .secondary)
            .padding(.horizontal, 9)
            .frame(maxWidth: .infinity, minHeight: 32, alignment: .leading)
            .background(
                isSelected ? WorkspaceTheme.accent.opacity(0.08) : .clear,
                in: RoundedRectangle(cornerRadius: 6)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .accessibilityLabel("\(title), \(count) papers")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func displayTitle(for selection: LibrarySidebarSelection, fallback: String) -> String {
        guard case let .date(_, date) = selection else { return fallback }
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return "Today" }
        if calendar.isDateInYesterday(date) { return "Yesterday" }
        if calendar.component(.year, from: date) == calendar.component(.year, from: Date()) {
            return date.formatted(.dateTime.month(.abbreviated).day())
        }
        return date.formatted(.dateTime.year().month(.abbreviated).day())
    }
}

private struct DailyBriefingView: View {
    @EnvironmentObject private var state: AppState
    @Binding var selectedTab: BriefingTab
    let searchText: String
    let openPaper: () -> Void
    let openActivity: () -> Void
    @State private var debouncedSearchText = ""

    var body: some View {
        GeometryReader { geometry in
            HStack(spacing: 0) {
                VStack(spacing: 0) {
                    briefingHeader
                    tabBar
                    Divider()
                    paperFeed
                }

                if state.isActivityRailVisible {
                    Divider()
                    AutomationActivityRail(openActivity: openActivity)
                        .frame(width: activityRailWidth(for: geometry.size.width))
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
        }
        .background(WorkspaceTheme.pageBackground)
        .task(id: searchText) {
            do {
                try await Task.sleep(for: .milliseconds(180))
            } catch {
                return
            }
            debouncedSearchText = searchText
        }
    }

    private func activityRailWidth(for availableWidth: CGFloat) -> CGFloat {
        min(max(availableWidth * 0.30, 330), 410)
    }

    private var briefingHeader: some View {
        HStack(alignment: .center, spacing: 18) {
            VStack(alignment: .leading, spacing: 5) {
                Text("Today’s Briefing")
                    .font(.system(size: 32, weight: .bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
                    .layoutPriority(2)
                Text(Date.now.formatted(.dateTime.weekday(.wide).month(.wide).day().year()))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 24)

            Text("\(displayedPapers.count) papers across \(state.enabledSubscriptionCount) subscriptions")
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.82)
                .layoutPriority(1)

            Button("Review top papers") {
                if let first = topPicks.first {
                    state.focusPaper(id: first.id)
                    openPaper()
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(topPicks.isEmpty)

            if state.isFetching {
                HStack(spacing: 8) {
                    ProgressView(value: state.activeOperation?.progress)
                        .progressViewStyle(.circular)
                        .controlSize(.small)
                    Text(state.activeOperation?.detail ?? "Fetching…")
                        .font(.caption)
                    Button("Cancel") {
                        state.cancelActiveOperation()
                    }
                    .buttonStyle(.link)
                }
            } else {
                Button("Fetch now") {
                    state.startDailyFetch()
                }
                .buttonStyle(.link)
                .disabled(state.enabledSubscriptionCount == 0)
            }
        }
        .padding(.horizontal, 22)
        .padding(.top, 28)
        .padding(.bottom, 28)
    }

    private var tabBar: some View {
        HStack(spacing: 18) {
            ForEach(BriefingTab.allCases) { tab in
                Button {
                    selectedTab = tab
                } label: {
                    VStack(spacing: 9) {
                        Text(tab.rawValue)
                            .font(.system(size: 15, weight: selectedTab == tab ? .semibold : .regular))
                            .foregroundStyle(selectedTab == tab ? WorkspaceTheme.accent : .secondary)
                        Rectangle()
                            .fill(selectedTab == tab ? WorkspaceTheme.accent : .clear)
                            .frame(width: 92, height: 2, alignment: .leading)
                    }
                    .frame(width: 108, alignment: .leading)
                    .frame(minHeight: 42, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .contentShape(Rectangle())
            }
            Spacer()
        }
        .padding(.horizontal, 56)
    }

    private var paperFeed: some View {
        BriefingPaperFeed(
            papers: displayedPapers,
            analyses: state.latestAnalysesByPaperID,
            selectedPaperID: displayedPapers.contains(where: { $0.id == state.selectedPaperID })
                ? state.selectedPaperID
                : displayedPapers.first?.id,
            selectPaper: { state.focusPaper(id: $0) },
            savePaper: { state.setInterested(paperID: $0) },
            deepReadPaper: { state.queueDeepRead(paperID: $0) },
            openPaper: openPaper
        )
        .equatable()
    }

    private var topPicks: [Paper] {
        filtered(state.briefingPapers)
    }

    private var displayedPapers: [Paper] {
        switch selectedTab {
        case .topPicks:
            Array(topPicks.prefix(20))
        case .allNew:
            Array(filtered(state.recentPapers).prefix(60))
        case .unread:
            Array(filtered(state.recentPapers.filter { $0.status == .new || $0.status == .summarized }).prefix(60))
        }
    }

    private func filtered(_ papers: [Paper]) -> [Paper] {
        let query = debouncedSearchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return papers }
        return papers.filter { paper in
            let analysis = state.latestAnalysesByPaperID[paper.arxivID]
            return [paper.title, paper.authors.joined(separator: " "), paper.tags.joined(separator: " "), analysis?.oneSentenceSummary ?? ""]
                .joined(separator: " ")
                .lowercased()
                .contains(query)
        }
    }
}

private struct BriefingPaperFeed: View, Equatable {
    let papers: [Paper]
    let analyses: [String: LLMAnalysis]
    let selectedPaperID: Paper.ID?
    let selectPaper: (Paper.ID) -> Void
    let savePaper: (Paper.ID) -> Void
    let deepReadPaper: (Paper.ID) -> Void
    let openPaper: () -> Void

    nonisolated static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.papers == rhs.papers
            && lhs.analyses == rhs.analyses
            && lhs.selectedPaperID == rhs.selectedPaperID
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(Array(papers.enumerated()), id: \.element.id) { index, paper in
                    BriefingPaperRow(
                        rank: index + 1,
                        paper: paper,
                        analysis: analyses[paper.arxivID],
                        isSelected: selectedPaperID == paper.id,
                        selectPaper: selectPaper,
                        savePaper: savePaper,
                        deepReadPaper: deepReadPaper,
                        openPaper: openPaper
                    )
                    if index < papers.count - 1 {
                        Divider()
                    }
                }
            }
            .padding(.leading, 30)
            .padding(.bottom, 28)
        }
        .overlay {
            if papers.isEmpty {
                ContentUnavailableView(
                    "No papers in this view",
                    systemImage: "doc.text.magnifyingglass",
                    description: Text("Try another briefing tab or fetch your subscriptions.")
                )
            }
        }
    }
}

private struct BriefingPaperRow: View {
    let rank: Int
    let paper: Paper
    let analysis: LLMAnalysis?
    let isSelected: Bool
    let selectPaper: (Paper.ID) -> Void
    let savePaper: (Paper.ID) -> Void
    let deepReadPaper: (Paper.ID) -> Void
    let openPaper: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 18) {
            Text("\(rank)")
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 28, alignment: .trailing)

            VStack(alignment: .leading, spacing: 9) {
                HStack(alignment: .top, spacing: 12) {
                    Button {
                        selectPaper(paper.id)
                    } label: {
                        Text(paper.title)
                            .font(.system(size: 20, weight: .semibold))
                            .multilineTextAlignment(.leading)
                            .foregroundStyle(.primary)
                    }
                    .buttonStyle(.plain)

                    Spacer(minLength: 12)

                    Button {
                        savePaper(paper.id)
                    } label: {
                        Label(paper.status == .interested ? "Saved" : "Save", systemImage: paper.status == .interested ? "bookmark.fill" : "bookmark")
                    }
                    .buttonStyle(.borderless)

                    Button {
                        deepReadPaper(paper.id)
                    } label: {
                        Label("Deep Read", systemImage: "book")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                }

                HStack(spacing: 8) {
                    if let analysis {
                        RelevanceLabel(score: normalizedScore(analysis.relevanceScore))
                    }
                    if let category = paper.primaryCategory {
                        Text(category)
                    }
                    if let date = paper.publishedAt ?? paper.updatedAt {
                        Text(date.formatted(date: .abbreviated, time: .omitted))
                    }
                }
                .font(.system(size: 13))
                .foregroundStyle(.secondary)

                Text(personalizedReason)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .lineSpacing(3)

                HStack(spacing: 6) {
                    ForEach(Array(tags.prefix(3)), id: \.self) { tag in
                        TagChipView(tag: tag)
                    }
                    if tags.count > 3 {
                        Text("+\(tags.count - 3)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(.quaternary, in: Capsule())
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 18)
        .background(isSelected ? WorkspaceTheme.accent.opacity(0.055) : .clear)
        .overlay(alignment: .leading) {
            if isSelected {
                Rectangle().fill(WorkspaceTheme.accent).frame(width: 2)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            selectPaper(paper.id)
        }
        .onTapGesture(count: 2) {
            selectPaper(paper.id)
            openPaper()
        }
    }

    private var personalizedReason: String {
        let rationale = analysis?.rationale.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !rationale.isEmpty { return rationale }
        let summary = analysis?.oneSentenceSummary.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !summary.isEmpty { return summary }
        return paper.abstract
    }

    private var tags: [String] {
        analysis?.canonicalTags.isEmpty == false ? analysis?.canonicalTags ?? [] : paper.tags
    }

    private func normalizedScore(_ score: Double) -> Int {
        Int((score <= 1 ? score * 100 : score).rounded())
    }
}

private struct RelevanceLabel: View {
    let score: Int

    var body: some View {
        HStack(spacing: 6) {
            Text("\(score)")
                .font(.caption.weight(.bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(color, in: RoundedRectangle(cornerRadius: 5))
            Text(label)
                .foregroundStyle(color)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Relevance \(score), \(label)")
    }

    private var label: String {
        if score >= 85 { return "Very high" }
        if score >= 65 { return "High" }
        if score >= 40 { return "Medium" }
        return "Low"
    }

    private var color: Color {
        if score >= 85 { return .orange }
        if score >= 65 { return Color(red: 0.78, green: 0.55, blue: 0.03) }
        if score >= 40 { return .secondary }
        return .secondary
    }
}

private struct AutomationActivityRail: View {
    @EnvironmentObject private var state: AppState
    let openActivity: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Text("Automation & Activity")
                        .font(.headline)
                    Spacer()
                    Button {
                        withAnimation(.snappy) { state.isActivityRailVisible = false }
                    } label: {
                        Image(systemName: "chevron.up")
                            .frame(width: 32, height: 32)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .contentShape(Rectangle())
                    .help("Hide activity")
                }

                AutomationHealthSummary()
                Divider()

                if let operation = state.activeOperation {
                    CurrentOperationView(operation: operation)
                }

                if !state.failedJobs.isEmpty || state.automationLastError != nil {
                    FailureSummaryView()
                }

                if state.launchAgentStatus?.isLoaded != true {
                    AutomationHelperRepairView()
                }

                AutomationQueueSummary()
                Divider()

                RecentActivityTimeline(jobs: Array(state.recentJobs.prefix(5)))

                Button("View all activity") {
                    openActivity()
                }
                .buttonStyle(.link)

                SettingsLink {
                    Text("Automation settings")
                }
            }
            .padding(18)
        }
        .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color(nsColor: .separatorColor).opacity(0.72), lineWidth: 1)
        }
        .padding(.horizontal, 14)
        .padding(.top, 44)
        .padding(.bottom, 14)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.32))
    }
}

private struct AutomationHealthSummary: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            Label(healthTitle, systemImage: healthIcon)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(healthColor)

            LabeledContent("Last successful fetch", value: state.lastSuccessfulFetchAt?.formatted(date: .abbreviated, time: .shortened) ?? "Not yet")
            LabeledContent("Next scheduled run", value: nextRunText)
            LabeledContent("Schedule", value: "Per subscription")
            LabeledContent("Time zone", value: TimeZone.current.localizedName(for: .standard, locale: .current) ?? TimeZone.current.identifier)
            LabeledContent("Subscriptions", value: "\(state.enabledSubscriptionCount) enabled · \(state.failedJobs.count) failed")
        }
        .font(.caption)
    }

    private var needsAttention: Bool {
        state.launchAgentStatus?.isLoaded != true
            || !state.failedJobs.isEmpty
            || state.automationLastError != nil
    }

    private var healthTitle: String {
        if state.launchAgentStatus == nil, state.launchAgentStatusError == nil {
            return "Checking automation…"
        }
        return needsAttention ? "Needs attention" : "On schedule"
    }
    private var healthIcon: String {
        if state.launchAgentStatus == nil, state.launchAgentStatusError == nil {
            return "arrow.triangle.2.circlepath"
        }
        return needsAttention ? "exclamationmark.triangle" : "checkmark.circle"
    }
    private var healthColor: Color {
        if state.launchAgentStatus == nil, state.launchAgentStatusError == nil {
            return .secondary
        }
        return needsAttention ? .red : .green
    }

    private var nextRunText: String {
        guard state.launchAgentStatus?.isLoaded == true else { return "Not scheduled" }
        guard let next = state.nextScheduledFetchAt else { return "Not scheduled" }
        if next <= Date() { return "Due now" }
        return next.formatted(date: .abbreviated, time: .shortened)
    }
}

private struct AutomationHelperRepairView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Label("Background helper", systemImage: "timer")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text(helperState)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            Text(state.launchAgentStatusError ?? "Scheduled fetching is not active on this Mac.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(3)
            HStack {
                SettingsLink {
                    Text("Details")
                }
                .buttonStyle(.link)
                Spacer()
                Button(state.launchAgentStatus?.isInstalled == true ? "Repair" : "Install helper") {
                    state.installLaunchAgent()
                }
                .buttonStyle(.borderedProminent)
                .disabled(state.isWorking)
            }
        }
        .padding(12)
        .background(Color.red.opacity(0.045), in: RoundedRectangle(cornerRadius: 9))
        .overlay {
            RoundedRectangle(cornerRadius: 9)
                .stroke(Color.red.opacity(0.16), lineWidth: 1)
        }
    }

    private var helperState: String {
        switch state.launchAgentStatus?.state {
        case .installedNotLoaded: "Needs repair"
        case .loaded: "Loaded"
        case .running: "Running"
        case .notInstalled, nil: "Not installed"
        }
    }
}

private struct AutomationQueueSummary: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack {
                Text("Queue")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text("\(runningJobs.count) running · \(failedJobs.count) failed")
                    .font(.caption)
                    .foregroundStyle(failedJobs.isEmpty ? Color.secondary : Color.red)
            }

            if activeJobs.isEmpty {
                Label("Queue is clear", systemImage: "checkmark.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(activeJobs.prefix(4)) { job in
                    HStack(spacing: 8) {
                        Image(systemName: job.state == .running ? "arrow.triangle.2.circlepath" : "clock")
                            .foregroundStyle(job.state == .running ? .blue : .secondary)
                            .frame(width: 16)
                        Text(queueTitle(job))
                            .font(.caption)
                            .lineLimit(1)
                        Spacer()
                        Text(job.state == .running ? "Running" : "Queued")
                            .font(.caption2)
                            .foregroundStyle(job.state == .running ? .blue : .secondary)
                    }
                }
            }
        }
    }

    private var activeJobs: [SyncJob] {
        state.recentJobs.filter { $0.state == .running || $0.state == .pending }
    }

    private var runningJobs: [SyncJob] { state.recentJobs.filter { $0.state == .running } }
    private var failedJobs: [SyncJob] { state.recentJobs.filter { $0.state == .failed } }

    private func queueTitle(_ job: SyncJob) -> String {
        switch job.kind {
        case .fetchArxiv: "Fetch subscription"
        case .summarizeAbstract: "Analyze abstract"
        case .deepRead: "Deep read"
        case .syncNotion: "Sync to Notion"
        case .syncZotero: "Sync to Zotero"
        }
    }
}

private struct CurrentOperationView: View {
    @EnvironmentObject private var state: AppState
    let operation: ActiveOperationState

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Label(operation.title, systemImage: "arrow.triangle.2.circlepath")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text("In progress")
                    .font(.caption)
                    .foregroundStyle(.blue)
            }
            Text(operation.detail)
                .font(.caption)
                .foregroundStyle(.secondary)
            ProgressView(value: operation.progress)
            HStack {
                if operation.totalUnitCount > 0 {
                    Text("\(operation.completedUnitCount)/\(operation.totalUnitCount) subscriptions")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Cancel") {
                    state.cancelActiveOperation()
                }
            }
        }
        .padding(12)
        .background(WorkspaceTheme.accent.opacity(0.055), in: RoundedRectangle(cornerRadius: 9))
    }
}

private struct FailureSummaryView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Label("Action required", systemImage: "xmark.circle")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.red)
                Spacer()
                Text("Failed")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            Text(errorText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(4)
                .textSelection(.enabled)
            HStack {
                Spacer()
                Button("Retry failed") {
                    state.retryFailedJobs()
                }
                .buttonStyle(.borderedProminent)
                .tint(.indigo)
                .disabled(state.failedJobs.isEmpty || state.isWorking)
            }
        }
        .padding(12)
        .background(Color.red.opacity(0.055), in: RoundedRectangle(cornerRadius: 9))
    }

    private var errorText: String {
        state.failedJobs.first?.lastError ?? state.automationLastError ?? "The most recent automation run did not finish."
    }
}

private struct RecentActivityTimeline: View {
    @EnvironmentObject private var state: AppState
    let jobs: [SyncJob]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Recent activity")
                .font(.subheadline.weight(.semibold))
            if jobs.isEmpty {
                Text("No activity yet")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(jobs) { job in
                    HStack(alignment: .top, spacing: 9) {
                        Image(systemName: icon(for: job.state))
                            .foregroundStyle(color(for: job.state))
                            .frame(width: 16)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(activityTitle(job))
                                .font(.caption)
                                .lineLimit(1)
                            Text(payload(job))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Spacer()
                        Text((job.completedAt ?? job.claimedAt ?? job.scheduledAt).formatted(date: .omitted, time: .shortened))
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
        }
    }

    private func activityTitle(_ job: SyncJob) -> String {
        let verb: String
        switch job.kind {
        case .fetchArxiv: verb = "Fetch"
        case .summarizeAbstract: verb = "LLM analysis"
        case .deepRead: verb = "Deep read"
        case .syncNotion: verb = "Notion sync"
        case .syncZotero: verb = "Zotero sync"
        }
        switch job.state {
        case .pending: return "\(verb) queued"
        case .running: return "\(verb) started"
        case .succeeded: return "\(verb) completed"
        case .failed: return "\(verb) failed"
        }
    }

    private func payload(_ job: SyncJob) -> String {
        guard let typed = try? job.typedPayload() else {
            return String(data: job.payload, encoding: .utf8) ?? ""
        }
        switch typed {
        case let .paper(id):
            return state.papers.first(where: { $0.arxivID == id })?.title ?? id
        case let .queryProfile(id):
            return state.queryProfiles.first(where: { $0.id == id })?.name ?? "Subscription"
        case let .raw(value):
            return value
        }
    }

    private func icon(for state: SyncJob.State) -> String {
        switch state {
        case .pending: "clock"
        case .running: "arrow.triangle.2.circlepath"
        case .succeeded: "checkmark.circle"
        case .failed: "xmark.circle"
        }
    }

    private func color(for state: SyncJob.State) -> Color {
        switch state {
        case .pending: .secondary
        case .running: .blue
        case .succeeded: .green
        case .failed: .red
        }
    }
}

private enum LibraryShelfSelection: Hashable {
    case all
    case query(QueryProfile.ID)
    case saved
}

private enum LibraryContextTab: String, CaseIterable, Identifiable {
    case paper = "Paper"
    case activity = "Activity"

    var id: String { rawValue }
}

private struct LibraryShelfItem: Identifiable {
    let selection: LibraryShelfSelection
    let title: String
    let count: Int

    var id: LibraryShelfSelection { selection }
}

private struct LibraryWorkspaceView: View {
    @EnvironmentObject private var state: AppState
    let searchText: String
    @Binding var isPrimed: Bool
    @Binding var isContextRailVisible: Bool
    @State private var selectedShelf = LibraryShelfSelection.all
    @State private var contextTab = LibraryContextTab.paper
    @State private var debouncedSearchText = ""
    @State private var statusFilter = "all"
    @State private var sortOption = PaperSortOption.dateDescending

    var body: some View {
        let papers = filteredPapers
        GeometryReader { geometry in
            HStack(spacing: 0) {
                libraryContent(papers: papers)
                if isContextRailVisible {
                    Divider()
                    LibraryContextRail(
                        selectedTab: $contextTab,
                        isVisible: $isContextRailVisible
                    )
                    .frame(width: contextRailWidth(for: geometry.size.width))
                    .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
        }
        .onAppear {
            isPrimed = true
        }
        .task(id: searchText) {
            do {
                try await Task.sleep(for: .milliseconds(160))
            } catch {
                return
            }
            debouncedSearchText = searchText
        }
        .background(WorkspaceTheme.pageBackground)
    }

    private func libraryContent(papers: [Paper]) -> some View {
        VStack(spacing: 0) {
            libraryHeader
            shelfStrip
            Divider()
            HStack {
                Text(sectionTitle)
                    .font(.title3.weight(.semibold))
                Spacer()
                Text("\(papers.count) papers")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 28)
            .padding(.top, 22)
            .padding(.bottom, 10)

            if papers.isEmpty {
                ContentUnavailableView(
                    "No matching papers",
                    systemImage: "doc.text.magnifyingglass",
                    description: Text("Try another shelf, search, or filter.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(papers.enumerated()), id: \.element.id) { index, paper in
                            LibraryPaperRow(
                                rank: index + 1,
                                paper: paper,
                                analysis: state.latestAnalysesByPaperID[paper.arxivID],
                                isSelected: state.selectedPaperID == paper.id
                            )
                            Divider()
                                .padding(.leading, 64)
                        }
                    }
                    .padding(.horizontal, 20)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var libraryHeader: some View {
        HStack(alignment: .center, spacing: 16) {
            Text("Library")
                .font(.system(size: 30, weight: .bold))
            Text("\(state.papers.count) papers")
                .font(.callout)
                .foregroundStyle(.secondary)

            Spacer(minLength: 18)

            Menu {
                Picker("Status", selection: $statusFilter) {
                    Text("All statuses").tag("all")
                    ForEach(PaperStatus.allCases, id: \.rawValue) { status in
                        Text(status.rawValue.capitalized).tag(status.rawValue)
                    }
                }
                Picker("Sort", selection: $sortOption) {
                    ForEach(PaperSortOption.allCases, id: \.self) { option in
                        Text(option.displayName).tag(option)
                    }
                }
            } label: {
                Label("Filters", systemImage: "line.3.horizontal.decrease")
            }
            .buttonStyle(.bordered)
            .controlSize(.large)

            Button {
                state.beginNewQuery()
            } label: {
                Label("New subscription", systemImage: "plus")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 15)
                    .padding(.vertical, 9)
                    .background(WorkspaceTheme.accent, in: RoundedRectangle(cornerRadius: 7))
                    .contentShape(RoundedRectangle(cornerRadius: 7))
            }
            .buttonStyle(.plain)
            .contentShape(RoundedRectangle(cornerRadius: 7))
        }
        .padding(.horizontal, 28)
        .padding(.top, 24)
        .padding(.bottom, 18)
    }

    private var shelfStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 0) {
                ForEach(shelfItems) { item in
                    Button {
                        selectedShelf = item.selection
                    } label: {
                        HStack(spacing: 9) {
                            Text(item.title)
                                .font(.callout.weight(selectedShelf == item.selection ? .semibold : .regular))
                            Text("\(item.count)")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(.quaternary, in: Capsule())
                        }
                        .foregroundStyle(selectedShelf == item.selection ? WorkspaceTheme.accent : .primary)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 14)
                        .frame(minHeight: 44)
                        .overlay(alignment: .bottom) {
                            if selectedShelf == item.selection {
                                Rectangle()
                                    .fill(WorkspaceTheme.accent)
                                    .frame(height: 2)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .contentShape(Rectangle())

                    Divider()
                        .frame(height: 44)
                }
            }
        }
        .background(Color(nsColor: .textBackgroundColor).opacity(0.5))
    }

    private var shelfItems: [LibraryShelfItem] {
        var items = [LibraryShelfItem(selection: .all, title: "All papers", count: state.papers.count)]
        items += state.queryProfiles.prefix(3).map { profile in
            LibraryShelfItem(
                selection: .query(profile.id),
                title: profile.name,
                count: state.papers.lazy.filter { $0.queryProfileIDs.contains(profile.id) }.count
            )
        }
        items.append(LibraryShelfItem(selection: .saved, title: "Saved", count: state.savedPaperCount))
        return items
    }

    private var filteredPapers: [Paper] {
        let queryProfileID: QueryProfile.ID?
        let shelfStatus: PaperStatus?
        switch selectedShelf {
        case .all:
            queryProfileID = nil
            shelfStatus = statusFilter == "all" ? nil : PaperStatus(rawValue: statusFilter)
        case let .query(id):
            queryProfileID = id
            shelfStatus = statusFilter == "all" ? nil : PaperStatus(rawValue: statusFilter)
        case .saved:
            queryProfileID = nil
            shelfStatus = .interested
        }

        return PaperFilter.apply(
            state.papers,
            criteria: PaperFilterCriteria(
                searchText: debouncedSearchText,
                status: shelfStatus,
                tags: [],
                dateRange: .all,
                dateField: state.libraryDateField,
                sort: sortOption,
                queryProfileID: queryProfileID,
                libraryDate: state.selectedLibraryDateFilter
            ),
            analysesByPaperID: state.latestAnalysesByPaperID
        )
    }

    private var sectionTitle: String {
        switch state.selectedLibraryDateFilter {
        case .all:
            return selectedShelf == .saved ? "Saved papers" : "Latest in \(shelfTitle)"
        case let .thisWeek(field, _):
            return "\(field.displayName) this week · \(shelfTitle)"
        case let .day(field, date):
            return "\(field.displayName) \(date.formatted(.dateTime.month(.abbreviated).day())) · \(shelfTitle)"
        }
    }

    private var shelfTitle: String {
        switch selectedShelf {
        case .all:
            return "All papers"
        case let .query(id):
            return state.queryProfiles.first(where: { $0.id == id })?.name ?? "Subscription"
        case .saved:
            return "Saved"
        }
    }

    private func contextRailWidth(for totalWidth: CGFloat) -> CGFloat {
        min(max(totalWidth * 0.44, 360), 430)
    }
}

private struct LibraryPaperRow: View {
    @EnvironmentObject private var state: AppState
    let rank: Int
    let paper: Paper
    let analysis: LLMAnalysis?
    let isSelected: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 18) {
            Text("\(rank)")
                .font(.title3)
                .foregroundStyle(.secondary)
                .frame(width: 28, alignment: .trailing)

            VStack(alignment: .leading, spacing: 8) {
                Text(paper.title)
                    .font(.system(size: 17, weight: .semibold))
                    .lineLimit(2)

                HStack(spacing: 8) {
                    if let analysis {
                        RelevanceLabel(score: RelevanceScore.displayScore(analysis.relevanceScore))
                    }
                    if let category = paper.primaryCategory {
                        Text(category)
                    }
                    Text(displayDate)
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                Text(summary)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .lineSpacing(2)

                HStack(spacing: 6) {
                    ForEach(Array(tags.prefix(3)), id: \.self) { tag in
                        TagChipView(tag: tag)
                    }
                    if tags.count > 3 {
                        Text("+\(tags.count - 3)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(.quaternary, in: Capsule())
                    }
                }
            }

            Spacer(minLength: 12)

            HStack(spacing: 14) {
                Button {
                    state.setInterested(paperID: paper.id)
                } label: {
                    Label(paper.status == .interested ? "Saved" : "Save", systemImage: paper.status == .interested ? "bookmark.fill" : "bookmark")
                        .padding(.horizontal, 6)
                        .padding(.vertical, 7)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .contentShape(Rectangle())

                Button {
                    state.focusPaper(id: paper.id, replaceSelection: true)
                    state.queueDeepRead(paperID: paper.id)
                } label: {
                    Label("Deep Read", systemImage: "book")
                }
                .buttonStyle(.bordered)
            }
            .font(.callout)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 18)
        .background(isSelected ? WorkspaceTheme.accent.opacity(0.025) : .clear)
        .contentShape(Rectangle())
        .onTapGesture {
            state.focusPaper(id: paper.id, replaceSelection: true)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(paper.title)
        .accessibilityValue(accessibilitySummary)
        .accessibilityHint("Select to show paper context")
        .accessibilityAddTraits(.isButton)
    }

    private var summary: String {
        let value = analysis?.oneSentenceSummary.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return value.isEmpty ? paper.abstract : value
    }

    private var tags: [String] {
        let values = analysis?.canonicalTags.isEmpty == false ? analysis?.canonicalTags ?? [] : paper.tags
        return values.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    private var displayDate: String {
        (paper.addedAt ?? paper.updatedAt ?? paper.publishedAt)?.formatted(date: .abbreviated, time: .omitted) ?? "No date"
    }

    private var accessibilitySummary: String {
        let score = analysis.map { "relevance \(RelevanceScore.displayScore($0.relevanceScore)) out of 100" }
        return [score, paper.primaryCategory, displayDate, paper.status.rawValue]
            .compactMap { $0 }
            .joined(separator: ", ")
    }
}

private struct LibraryContextRail: View {
    @EnvironmentObject private var state: AppState
    @Binding var selectedTab: LibraryContextTab
    @Binding var isVisible: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                ForEach(LibraryContextTab.allCases) { tab in
                    Button {
                        selectedTab = tab
                    } label: {
                        Text(tab.rawValue)
                            .font(.callout.weight(selectedTab == tab ? .semibold : .regular))
                            .foregroundStyle(selectedTab == tab ? WorkspaceTheme.accent : .primary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .overlay(alignment: .bottom) {
                                if selectedTab == tab {
                                    Rectangle().fill(WorkspaceTheme.accent).frame(height: 2)
                                }
                            }
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .contentShape(Rectangle())
                }

                Button {
                    withAnimation(.snappy) { isVisible = false }
                } label: {
                    Image(systemName: "xmark")
                        .frame(width: 38, height: 38)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .contentShape(Rectangle())
                .help("Hide context rail")
            }
            Divider()

            switch selectedTab {
            case .paper:
                paperContext
            case .activity:
                activityContext
            }
        }
        .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color(nsColor: .separatorColor).opacity(0.7), lineWidth: 1)
        }
        .padding(12)
        .background(WorkspaceTheme.pageBackground)
    }

    @ViewBuilder
    private var paperContext: some View {
        if let paper = state.selectedPaper {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(paper.title)
                        .font(.system(size: 20, weight: .semibold))
                        .lineLimit(4)

                    HStack(spacing: 8) {
                        if let analysis = state.selectedPaperAnalysis {
                            RelevanceLabel(score: RelevanceScore.displayScore(analysis.relevanceScore))
                        }
                        if let category = paper.primaryCategory {
                            Text(category)
                        }
                        Text((paper.addedAt ?? paper.updatedAt ?? paper.publishedAt)?.formatted(date: .abbreviated, time: .omitted) ?? "")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)

                    if let analysis = state.selectedPaperAnalysis {
                        contextSection("LLM Summary", text: analysis.oneSentenceSummary)
                        contextSection("Why it matters", text: analysis.rationale)
                    } else {
                        contextSection("Abstract", text: paper.abstract)
                    }

                    if !contextTags(paper).isEmpty {
                        TagStripView(tags: contextTags(paper), displayMode: .chips, layout: .wrap)
                    }

                    Button {
                        state.queueDeepRead(paperID: paper.id)
                    } label: {
                        Label("Deep Read", systemImage: "book")
                            .font(.callout.weight(.semibold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 9)
                            .background(WorkspaceTheme.accent, in: RoundedRectangle(cornerRadius: 7))
                            .contentShape(RoundedRectangle(cornerRadius: 7))
                    }
                    .buttonStyle(.plain)
                    .contentShape(RoundedRectangle(cornerRadius: 7))

                    HStack(spacing: 10) {
                        Button {
                            state.setInterested(paperID: paper.id)
                        } label: {
                            Label(paper.status == .interested ? "Saved" : "Save", systemImage: paper.status == .interested ? "bookmark.fill" : "bookmark")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)

                        if let url = paper.absURL {
                            Link(destination: url) {
                                Label("Open on arXiv", systemImage: "arrow.up.right.square")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                        }
                    }

                    Divider()
                        .padding(.vertical, 2)

                    compactAutomation
                }
                .padding(18)
            }
        } else {
            ContentUnavailableView("Select a paper", systemImage: "doc.text", description: Text("Paper context will appear here."))
        }
    }

    private var activityContext: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                AutomationHealthSummary()
                if let operation = state.activeOperation {
                    Divider()
                    CurrentOperationView(operation: operation)
                }
                if !state.failedJobs.isEmpty || state.automationLastError != nil {
                    FailureSummaryView()
                }
                Divider()
                AutomationQueueSummary()
                Divider()
                RecentActivityTimeline(jobs: Array(state.recentJobs.prefix(8)))
            }
            .padding(18)
        }
    }

    private var compactAutomation: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Automation & Activity")
                    .font(.headline)
                Spacer()
                Button {
                    selectedTab = .activity
                } label: {
                    Image(systemName: "chevron.up")
                        .frame(width: 32, height: 32)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .contentShape(Rectangle())
            }

            Label(automationHealthTitle, systemImage: automationHealthIcon)
                .font(.callout.weight(.semibold))
                .foregroundStyle(automationNeedsAttention ? Color.red : Color.green)

            LabeledContent("Next fetch", value: nextFetchText)
                .font(.caption)

            if let operation = state.activeOperation {
                VStack(alignment: .leading, spacing: 7) {
                    HStack {
                        Text(operation.title)
                            .lineLimit(1)
                        Spacer()
                        Text("In progress")
                            .foregroundStyle(.blue)
                    }
                    .font(.caption)
                    ProgressView(value: operation.progress)
                    if operation.totalUnitCount > 0 {
                        Text("\(operation.completedUnitCount) / \(operation.totalUnitCount)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Button("View activity") {
                selectedTab = .activity
            }
            .buttonStyle(.link)
        }
    }

    @ViewBuilder
    private func contextSection(_ title: String, text: String) -> some View {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !value.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(value)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineSpacing(3)
                    .textSelection(.enabled)
            }
        }
    }

    private func contextTags(_ paper: Paper) -> [String] {
        let values = state.selectedPaperAnalysis?.canonicalTags.isEmpty == false
            ? state.selectedPaperAnalysis?.canonicalTags ?? []
            : paper.tags
        return Array(values.prefix(5))
    }

    private var automationNeedsAttention: Bool {
        state.launchAgentStatus?.isLoaded != true || !state.failedJobs.isEmpty || state.automationLastError != nil
    }

    private var automationHealthTitle: String {
        automationNeedsAttention ? "Needs attention" : "On schedule"
    }

    private var automationHealthIcon: String {
        automationNeedsAttention ? "exclamationmark.triangle" : "checkmark.circle"
    }

    private var nextFetchText: String {
        guard state.launchAgentStatus?.isLoaded == true, let next = state.nextScheduledFetchAt else {
            return "Not scheduled"
        }
        if next <= Date() { return "Due now" }
        return next.formatted(date: .abbreviated, time: .shortened)
    }
}

private struct SubscriptionOverviewView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Subscriptions")
                        .font(.largeTitle.bold())
                    Text("Manage what ArxivResearch fetches and when.")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("New Subscription", systemImage: "plus") {
                    state.beginNewQuery()
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(28)
            Divider()

            List(state.queryProfiles) { profile in
                HStack(spacing: 14) {
                    Image(systemName: profile.isEnabled ? "checkmark.circle.fill" : "pause.circle")
                        .foregroundStyle(profile.isEnabled ? .green : .secondary)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(profile.name)
                            .font(.headline)
                        Text(profile.isEnabled ? "Every \(profile.refreshIntervalHours) hours" : "Paused")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(profile.lastFetchedAt?.formatted(date: .abbreviated, time: .shortened) ?? "Never fetched")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("Fetch") {
                        Task { await state.fetchQuery(id: profile.id) }
                    }
                    .disabled(state.isWorking)
                    Button("Edit") {
                        state.beginEditQuery(id: profile.id)
                    }
                }
                .padding(.vertical, 6)
            }
            .listStyle(.inset)
        }
    }
}

private struct SavedPapersView: View {
    @EnvironmentObject private var state: AppState
    let openPaper: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Saved Papers")
                .font(.largeTitle.bold())
                .padding(28)
            Divider()
            ScrollView {
                LazyVStack(spacing: 0) {
                    let saved = state.papers.filter { $0.status == .interested }
                    ForEach(Array(saved.enumerated()), id: \.element.id) { index, paper in
                        BriefingPaperRow(
                            rank: index + 1,
                            paper: paper,
                            analysis: state.latestAnalysesByPaperID[paper.arxivID],
                            isSelected: state.selectedPaperID == paper.id,
                            selectPaper: { state.focusPaper(id: $0) },
                            savePaper: { state.setInterested(paperID: $0) },
                            deepReadPaper: { state.queueDeepRead(paperID: $0) },
                            openPaper: openPaper
                        )
                        Divider().padding(.leading, 72)
                    }
                }
                .padding(.horizontal, 28)
            }
            .overlay {
                if state.papers.allSatisfy({ $0.status != .interested }) {
                    ContentUnavailableView("No saved papers", systemImage: "bookmark", description: Text("Save papers from your briefing to collect them here."))
                }
            }
        }
    }
}

private struct FullActivityView: View {
    var body: some View {
        HStack {
            Spacer()
            AutomationActivityRail(openActivity: {})
                .frame(maxWidth: 520)
            Spacer()
        }
        .background(Color(nsColor: .textBackgroundColor))
    }
}

@MainActor
private struct ToolbarHelpButton: NSViewRepresentable {
    let title: String
    let systemImage: String
    let help: String
    let isDisabled: Bool
    let action: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(action: action)
    }

    func makeNSView(context: Context) -> NSButton {
        let button = NSButton()
        button.bezelStyle = .texturedRounded
        button.controlSize = .small
        button.imagePosition = .imageOnly
        button.imageScaling = .scaleProportionallyDown
        button.setButtonType(.momentaryPushIn)
        button.target = context.coordinator
        button.action = #selector(Coordinator.performAction)
        button.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            button.widthAnchor.constraint(equalToConstant: 28),
            button.heightAnchor.constraint(equalToConstant: 28)
        ])
        return button
    }

    func updateNSView(_ button: NSButton, context: Context) {
        context.coordinator.action = action
        button.image = NSImage(systemSymbolName: systemImage, accessibilityDescription: title)
        button.toolTip = help
        button.isEnabled = !isDisabled
        button.setAccessibilityLabel(title)
        button.setAccessibilityHelp(help)
    }

    @MainActor
    final class Coordinator: NSObject {
        var action: () -> Void

        init(action: @escaping () -> Void) {
            self.action = action
        }

        @objc func performAction() {
            action()
        }
    }
}

@MainActor
private struct ToolbarTooltipInstaller: NSViewRepresentable {
    let tooltips: [String: String]

    func makeCoordinator() -> Coordinator {
        Coordinator(tooltips: tooltips)
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        context.coordinator.installSoon(from: view)
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        context.coordinator.tooltips = tooltips
        context.coordinator.installSoon(from: view)
    }

    @MainActor
    final class Coordinator {
        var tooltips: [String: String]

        init(tooltips: [String: String]) {
            self.tooltips = tooltips
        }

        func installSoon(from view: NSView) {
            DispatchQueue.main.async { [weak view, weak self] in
                guard let view, let self else { return }
                self.install(from: view)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak view, weak self] in
                guard let view, let self else { return }
                self.install(from: view)
            }
        }

        private func install(from view: NSView) {
            guard let toolbar = view.window?.toolbar else { return }
            for item in toolbar.items {
                guard let tooltip = tooltips[item.label] ?? tooltips[item.paletteLabel] else { continue }
                item.toolTip = tooltip
                item.view?.toolTip = tooltip
                item.view?.setAccessibilityHelp(tooltip)
            }
        }
    }
}

struct QuerySidebarView: View {
    @EnvironmentObject private var state: AppState
    @SceneStorage("library.dateBucketsExpanded.v2") private var dateBucketsExpanded = false
    @State private var queryPendingDeletion: QueryProfile?

    var body: some View {
        let weekBucket = state.libraryWeekBucket
        let dateBuckets = state.libraryDateBuckets

        List(selection: sidebarSelection) {
            Section("Library") {
                Label("All Papers", systemImage: "tray.full")
                    .badge(state.papers.count)
                    .tag(LibrarySidebarSelection.all)
                Picker("Date Field", selection: libraryDateField) {
                    ForEach(PaperDateField.allCases, id: \.self) { field in
                        Text(field.displayName).tag(field)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .help("Choose whether library date groups use local added date, arXiv published date, or arXiv updated date")

                Label(weekBucket.title, systemImage: "calendar")
                    .badge(weekBucket.count)
                    .tag(weekBucket.selection)

                if !dateBuckets.isEmpty {
                    DisclosureGroup(isExpanded: $dateBucketsExpanded) {
                        ForEach(dateBuckets) { bucket in
                            Label(bucket.title, systemImage: "calendar")
                                .badge(bucket.count)
                                .tag(bucket.selection)
                        }
                    } label: {
                        Label("Dates", systemImage: "calendar.badge.clock")
                            .badge(dateBuckets.reduce(0) { $0 + $1.count })
                    }
                }
            }

            Section("Subscriptions") {
                Button {
                    state.beginNewQuery()
                } label: {
                    Label("New Query", systemImage: "plus")
                }
                .buttonStyle(.plain)

                ForEach(state.queryProfiles) { profile in
                    QuerySubscriptionRow(profile: profile, paperCount: state.queryPaperCount(id: profile.id))
                        .tag(LibrarySidebarSelection.query(profile.id))
                        .contextMenu {
                            Button {
                                state.beginEditQuery(id: profile.id)
                            } label: {
                                Label("Edit", systemImage: "pencil")
                            }
                            Button {
                                Task { await state.fetchQuery(id: profile.id) }
                            } label: {
                                Label("Fetch Now", systemImage: "tray.and.arrow.down")
                            }
                            .disabled(state.isWorking)
                            Button {
                                state.toggleQueryEnabled(id: profile.id)
                            } label: {
                                Label(profile.isEnabled ? "Disable" : "Enable", systemImage: profile.isEnabled ? "pause.circle" : "play.circle")
                            }
                            Divider()
                            Button(role: .destructive) {
                                queryPendingDeletion = profile
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                }
            }
        }
        .overlay {
            if state.queryProfiles.isEmpty && state.papers.isEmpty {
                ContentUnavailableView("No Papers", systemImage: "doc.text.magnifyingglass", description: Text("Create a query subscription to start tracking arXiv."))
            }
        }
        .confirmationDialog("Delete Query", isPresented: deleteDialogBinding) {
            Button("Delete Query Only") {
                if let queryPendingDeletion {
                    state.deleteQuery(id: queryPendingDeletion.id, deleteAssociatedPapers: false)
                }
                queryPendingDeletion = nil
            }
            Button("Delete Query and Papers", role: .destructive) {
                if let queryPendingDeletion {
                    state.deleteQuery(id: queryPendingDeletion.id, deleteAssociatedPapers: true)
                }
                queryPendingDeletion = nil
            }
            Button("Cancel", role: .cancel) {
                queryPendingDeletion = nil
            }
        } message: {
            Text("You can keep existing papers, or remove all paper entries associated with this query.")
        }
    }

    private var libraryDateField: Binding<PaperDateField> {
        Binding {
            state.libraryDateField
        } set: { field in
            state.libraryDateField = field
            switch state.sidebarSelection {
            case .thisWeek:
                state.sidebarSelection = .thisWeek(field)
            case .date:
                state.sidebarSelection = .all
            case .all, .query:
                break
            }
        }
    }

    private var sidebarSelection: Binding<LibrarySidebarSelection?> {
        Binding {
            state.sidebarSelection
        } set: { selection in
            state.sidebarSelection = selection ?? .all
            if case let .query(id) = selection {
                state.selectedQueryID = id
            }
        }
    }

    private var deleteDialogBinding: Binding<Bool> {
        Binding {
            queryPendingDeletion != nil
        } set: { isPresented in
            if !isPresented {
                queryPendingDeletion = nil
            }
        }
    }
}

struct QuerySubscriptionRow: View {
    let profile: QueryProfile
    let paperCount: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(profile.name)
                    .font(.headline)
                    .foregroundStyle(profile.isEnabled ? .primary : .secondary)
                Spacer()
                Text("\(paperCount)")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Text(ArxivQueryBuilder.displayRawQuery(profile.requestRawQuery))
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            HStack(spacing: 6) {
                Label(profile.isEnabled ? "Enabled" : "Disabled", systemImage: profile.isEnabled ? "checkmark.circle" : "pause.circle")
                Text("Every \(profile.refreshIntervalHours)h")
                Text("Max \(profile.maxResults)")
            }
            .font(.caption2)
            .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 3)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(profile.name)
        .accessibilityValue("\(paperCount) papers, \(profile.isEnabled ? "enabled" : "disabled"), every \(profile.refreshIntervalHours) hours")
    }
}

struct QueryEditorSheetView: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.dismiss) private var dismiss
    let profile: QueryProfile?
    @State private var name: String
    @State private var rawQuery: String
    @State private var refreshIntervalHours: Int
    @State private var isEnabled: Bool
    @State private var useRawQuery: Bool
    @State private var rootGroup: StructuredQueryGroup
    @State private var maxResults: Int
    @State private var submittedAfterEnabled: Bool
    @State private var submittedAfter: Date

    init(profile: QueryProfile?) {
        self.profile = profile
        _name = State(initialValue: profile?.name ?? "")
        _rawQuery = State(initialValue: profile.map { ArxivQueryBuilder.displayRawQuery($0.rawQuery) } ?? "")
        _refreshIntervalHours = State(initialValue: profile?.refreshIntervalHours ?? 24)
        _isEnabled = State(initialValue: profile?.isEnabled ?? true)
        _useRawQuery = State(initialValue: profile?.usesRawQuery ?? false)
        _rootGroup = State(initialValue: profile?.structuredQueryRoot ?? StructuredQueryGroup())
        _maxResults = State(initialValue: profile?.maxResults ?? 50)
        _submittedAfterEnabled = State(initialValue: profile?.submittedAfter != nil)
        _submittedAfter = State(initialValue: profile?.submittedAfter ?? Date())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(profile == nil ? "New arXiv Query" : "Edit arXiv Query")
                    .font(.title3.weight(.semibold))
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.plain)
                .help("Close")
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    SectionView(title: "Basics") {
                        TextField("Query name", text: $name)
                        Stepper("Refresh every \(refreshIntervalHours) hours", value: $refreshIntervalHours, in: 1...168)
                        Stepper("Fetch up to \(maxResults) papers each run", value: $maxResults, in: 1...500, step: 5)
                        Toggle("Enabled", isOn: $isEnabled)
                    }

                    SectionView(title: "Date Constraint") {
                        Toggle("Only include papers submitted after a time", isOn: $submittedAfterEnabled)
                        if submittedAfterEnabled {
                            DatePicker(
                                "Submitted after",
                                selection: $submittedAfter,
                                displayedComponents: [.date, .hourAndMinute]
                            )
                            .help("arXiv submittedDate uses GMT. The selected instant is converted to GMT in the request.")
                            Text("Adds submittedDate:[\(QueryProfile.submittedDateGMTString(from: submittedAfter)) TO *] to the query.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    SectionView(title: "Build Query") {
                        Text("Build a boolean expression. Add terms or nested groups, then choose AND, OR, or ANDNOT between rows. Use Phrase for quoted arXiv terms such as all:\"diffusion model\".")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        QueryExpressionGroupView(group: $rootGroup, title: "Root Group", depth: 0)
                    }

                    SectionView(title: "Field Guide") {
                        ForEach([ArxivSearchField.all, .title, .abstract, .author, .category], id: \.self) { field in
                            Text(field.helpText)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    SectionView(title: "Preview") {
                        Toggle("Advanced raw query override", isOn: $useRawQuery)
                        if useRawQuery {
                            TextField("Raw arXiv query", text: $rawQuery, axis: .vertical)
                                .lineLimit(2...5)
                                .font(.system(.caption, design: .monospaced))
                        }
                        Text(effectiveRawQuery.isEmpty ? "No query terms yet" : effectiveRawQuery)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                            .lineLimit(4)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(8)
                            .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
                        if !previewURL.isEmpty {
                            ScrollView(.horizontal) {
                                Text(previewURL)
                                    .font(.caption2.monospaced())
                                    .foregroundStyle(.secondary)
                                    .textSelection(.enabled)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack {
                Spacer()
                Button {
                    Task { await state.testQuery(rawQuery: effectiveRawQuery, maxResults: maxResults) }
                } label: {
                    Label("Test Query", systemImage: "checkmark.seal")
                }
                .disabled(state.isWorking || effectiveRawQuery.isEmpty)
                Button {
                    state.saveQueryDraft(
                        id: profile?.id,
                        name: name,
                        rawQuery: baseRawQuery,
                        structuredQueryRoot: rootGroup.isEmpty ? nil : rootGroup,
                        usesRawQuery: useRawQuery,
                        refreshIntervalHours: refreshIntervalHours,
                        isEnabled: isEnabled,
                        maxResults: maxResults,
                        submittedAfter: submittedAfterEnabled ? submittedAfter : nil
                    )
                    dismiss()
                } label: {
                    Label("Save", systemImage: "tray.and.arrow.down")
                }
                .keyboardShortcut(.defaultAction)
                .disabled(effectiveRawQuery.isEmpty)
            }
        }
        .padding(18)
        .frame(minWidth: 680, idealWidth: 860, maxWidth: 980, minHeight: 600, idealHeight: 720, maxHeight: 820)
    }

    private var structuredQuery: StructuredArxivQuery {
        StructuredArxivQuery(rootGroup: rootGroup)
    }

    private var effectiveRawQuery: String {
        QueryProfile.composeRequestRawQuery(
            rawQuery: baseRawQuery,
            submittedAfter: submittedAfterEnabled ? submittedAfter : nil
        )
    }

    private var baseRawQuery: String {
        let raw = useRawQuery ? rawQuery : structuredQuery.renderedRawQuery
        return raw.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var previewURL: String {
        let request = ArxivAPIRequest(searchQuery: .raw(effectiveRawQuery), maxResults: maxResults)
        return (try? request.url().absoluteString) ?? ""
    }

}

struct SectionView<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct QueryExpressionGroupView: View {
    @Binding var group: StructuredQueryGroup
    let title: String
    let depth: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Spacer()
            }

            ForEach($group.clauses) { $clause in
                QueryExpressionClauseRowView(
                    clause: $clause,
                    isFirst: group.clauses.first?.id == clause.id,
                    depth: depth
                ) {
                    removeClause(id: clause.id)
                }
            }

            HStack(spacing: 8) {
                Button {
                    appendClause(node: .term(StructuredQueryTerm()))
                } label: {
                    Label("Term", systemImage: "plus.circle")
                }
                .help("Add keyword or phrase term")

                Button {
                    appendClause(node: .group(StructuredQueryGroup()))
                } label: {
                    Label("Group", systemImage: "folder.badge.plus")
                }
                .help("Add nested boolean group")
            }
            .controlSize(.small)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(depth == 0 ? 0 : 10)
        .background {
            if depth > 0 {
                RoundedRectangle(cornerRadius: 6)
                    .fill(.quaternary)
            }
        }
    }

    private func appendClause(node: StructuredQueryNode) {
        group.clauses.append(StructuredQueryClause(connector: .and, node: node))
    }

    private func removeClause(id: UUID) {
        group.clauses.removeAll { $0.id == id }
        if group.clauses.isEmpty {
            group.clauses.append(StructuredQueryClause())
        }
    }
}

struct QueryExpressionClauseRowView: View {
    @Binding var clause: StructuredQueryClause
    let isFirst: Bool
    let depth: Int
    let remove: () -> Void

    var body: some View {
        switch clause.node {
        case .term:
            HStack(alignment: .top, spacing: 8) {
                connectorControl
                QueryExpressionTermRowView(term: termBinding)
                    .layoutPriority(1)
                removeButton
            }
        case .group:
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .center, spacing: 8) {
                    connectorControl
                    Text("Nested group")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    removeButton
                }
                QueryExpressionGroupView(group: groupBinding, title: "Nested Group", depth: depth + 1)
                    .padding(.leading, 28)
            }
        }
    }

    @ViewBuilder
    private var connectorControl: some View {
        if isFirst {
            Text("Start")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 68, alignment: .leading)
                .padding(.top, 5)
        } else {
            Picker("Operator", selection: $clause.connector) {
                ForEach(StructuredQueryConnector.allCases, id: \.self) { connector in
                    Text(connector.displayName).tag(connector)
                }
            }
            .labelsHidden()
            .frame(width: 68)
            .help("Boolean operator before this row")
        }
    }

    private var removeButton: some View {
        Button(role: .destructive) {
            remove()
        } label: {
            Image(systemName: "minus.circle")
        }
        .buttonStyle(.plain)
        .help("Remove row")
    }

    private var termBinding: Binding<StructuredQueryTerm> {
        Binding {
            if case let .term(term) = clause.node {
                return term
            }
            return StructuredQueryTerm()
        } set: { term in
            clause.node = .term(term)
        }
    }

    private var groupBinding: Binding<StructuredQueryGroup> {
        Binding {
            if case let .group(group) = clause.node {
                return group
            }
            return StructuredQueryGroup()
        } set: { group in
            clause.node = .group(group)
        }
    }
}

struct QueryExpressionTermRowView: View {
    @Binding var term: StructuredQueryTerm

    private let fields: [ArxivSearchField] = [.all, .title, .abstract, .author, .category, .comment, .journalReference, .reportNumber]

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Field")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Picker("Field", selection: $term.field) {
                    ForEach(fields, id: \.self) { field in
                        Text("\(field.displayName) (\(field.rawValue))").tag(field)
                    }
                }
                .labelsHidden()
                .frame(width: 138)
                .help(term.field.helpText)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text("Keyword or Phrase")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                TextField("diffusion model", text: $term.value)
                    .frame(minWidth: 140, maxWidth: .infinity)
            }
            .layoutPriority(1)

            VStack(alignment: .leading, spacing: 3) {
                Text("Match")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Picker("Match", selection: $term.match) {
                    Text("Word").tag(QueryTermMatch.token)
                    Text("Phrase").tag(QueryTermMatch.phrase)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 124)
                .help("Phrase adds quotes for exact phrase matching, such as all:\"flow matching\".")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct PaperListView: View {
    @EnvironmentObject private var state: AppState
    @SceneStorage("paper.searchText") private var searchText = ""
    @SceneStorage("paper.statusFilter") private var statusFilter = "all"
    @SceneStorage("paper.tagFilter") private var tagFiltersRaw = "all"
    @SceneStorage("paper.sortFilter") private var sortFilter = PaperSortOption.dateDescending.rawValue
    @SceneStorage("paper.tagDisplayMode") private var tagDisplayModeRaw = TagDisplayMode.chips.rawValue
    @State private var debouncedSearchText = ""
    @State private var visiblePaperLimit = 12

    var body: some View {
        let filteredPapers = makeFilteredPapers()
        let visiblePapers = Array(filteredPapers.prefix(visiblePaperLimit))
        let availableTags = makeAvailableTags()
        let unanalyzedCount = state.papers.lazy.filter { state.latestAnalysesByPaperID[$0.arxivID] == nil }.count

        VStack(spacing: 0) {
            PaperFilterBarView(
                searchText: $searchText,
                statusFilter: $statusFilter,
                tagFiltersRaw: $tagFiltersRaw,
                sortFilter: $sortFilter,
                tagDisplayModeRaw: $tagDisplayModeRaw,
                availableTags: availableTags,
                unanalyzedCount: unanalyzedCount,
                selectedCount: state.selectedPaperIDs.count,
                analyzeMissing: {
                    state.analyzeUnanalyzedPapers()
                },
                analyzeSelected: {
                    state.queueSummaries(paperIDs: Array(state.selectedPaperIDs))
                }
            )
            Divider()
            List(visiblePapers, selection: $state.selectedPaperIDs) { paper in
                PaperRowView(
                    paper: paper,
                    analysis: state.latestAnalysesByPaperID[paper.arxivID],
                    tagDisplayMode: tagDisplayMode
                )
                .contentShape(Rectangle())
                .tag(paper.id)
                .contextMenu {
                    Button {
                        state.queueSummaries(paperIDs: contextPaperIDs(for: paper))
                    } label: {
                        let count = contextPaperIDs(for: paper).count
                        Label(count > 1 ? "Analyze \(count) Abstracts" : "Analyze Abstract", systemImage: "text.badge.checkmark")
                    }
                    Button {
                        state.queueDeepRead(paperID: paper.id)
                    } label: {
                        Label("Deep Read", systemImage: "doc.text.magnifyingglass")
                    }
                    Button {
                        state.setInterested(paperID: paper.id)
                    } label: {
                        Label("Mark Interested", systemImage: "star")
                    }
                    Button {
                        state.syncNotion(paperID: paper.id)
                    } label: {
                        Label("Sync Notion", systemImage: "square.and.arrow.up")
                    }
                    Button {
                        state.syncZotero(paperID: paper.id)
                    } label: {
                        Label("Send to Zotero", systemImage: "books.vertical")
                    }
                    Divider()
                    Button {
                        for paperID in contextPaperIDs(for: paper) {
                            state.archivePaper(paperID: paperID)
                        }
                    } label: {
                        let count = contextPaperIDs(for: paper).count
                        Label(count > 1 ? "Archive \(count) Papers" : "Archive", systemImage: "archivebox")
                    }
                    Button(role: .destructive) {
                        for paperID in contextPaperIDs(for: paper) {
                            state.deletePaper(paperID: paperID)
                        }
                    } label: {
                        let count = contextPaperIDs(for: paper).count
                        Label(count > 1 ? "Delete \(count) Papers" : "Delete", systemImage: "trash")
                    }
                }
                .onAppear {
                    guard paper.id == visiblePapers.last?.id, visiblePaperLimit < filteredPapers.count else {
                        return
                    }
                    visiblePaperLimit += 12
                }
            }
            .overlay {
                if state.papers.isEmpty {
                    ContentUnavailableView("No Papers", systemImage: "doc.text", description: Text("Scheduled fetches will appear here."))
                } else if filteredPapers.isEmpty {
                    ContentUnavailableView("No Matches", systemImage: "line.3.horizontal.decrease.circle", description: Text("Adjust search or filters."))
                }
            }
            .onChange(of: state.selectedPaperIDs) {
                if let paper = filteredPapers.first(where: { state.selectedPaperIDs.contains($0.id) }) {
                    state.focusPaper(id: paper.id)
                }
            }
        }
        .task(id: searchText) {
            do {
                try await Task.sleep(for: .milliseconds(180))
            } catch {
                return
            }
            debouncedSearchText = searchText
            visiblePaperLimit = 12
        }
        .onChange(of: statusFilter) { visiblePaperLimit = 12 }
        .onChange(of: tagFiltersRaw) { visiblePaperLimit = 12 }
        .onChange(of: sortFilter) { visiblePaperLimit = 12 }
        .onChange(of: state.libraryDateField) { visiblePaperLimit = 12 }
        .onChange(of: state.selectedQueryFilterID) { visiblePaperLimit = 12 }
        .onChange(of: state.selectedLibraryDateFilter) { visiblePaperLimit = 12 }
    }

    private func makeFilteredPapers() -> [Paper] {
        PaperFilter.apply(state.papers, criteria: PaperFilterCriteria(
            searchText: debouncedSearchText,
            status: statusFilter == "all" ? nil : PaperStatus(rawValue: statusFilter),
            tags: selectedTagFilters,
            dateRange: .all,
            dateField: state.libraryDateField,
            sort: PaperSortOption(rawValue: sortFilter) ?? .dateDescending,
            queryProfileID: state.selectedQueryFilterID,
            libraryDate: state.selectedLibraryDateFilter
        ), analysesByPaperID: state.latestAnalysesByPaperID)
    }

    private func makeAvailableTags() -> [String] {
        Array(Set(state.papers.flatMap { paper in
            state.latestAnalysesByPaperID[paper.arxivID]?.canonicalTags ?? paper.tags
        })).sorted()
    }

    private var tagDisplayMode: TagDisplayMode {
        TagDisplayMode(rawValue: tagDisplayModeRaw) ?? .chips
    }

    private var selectedTagFilters: Set<String> {
        TagSelectionCodec.decode(tagFiltersRaw)
    }

    private func contextPaperIDs(for paper: Paper) -> [Paper.ID] {
        if state.selectedPaperIDs.contains(paper.id), state.selectedPaperIDs.count > 1 {
            return makeFilteredPapers().map(\.id).filter { state.selectedPaperIDs.contains($0) }
        }
        return [paper.id]
    }
}

struct PaperFilterBarView: View {
    @Binding var searchText: String
    @Binding var statusFilter: String
    @Binding var tagFiltersRaw: String
    @Binding var sortFilter: String
    @Binding var tagDisplayModeRaw: String
    let availableTags: [String]
    let unanalyzedCount: Int
    let selectedCount: Int
    let analyzeMissing: () -> Void
    let analyzeSelected: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search papers", text: $searchText)
                    .textFieldStyle(.plain)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))

            HStack(spacing: 8) {
                Picker("Status", selection: $statusFilter) {
                    Text("All Status").tag("all")
                    ForEach(PaperStatus.allCases, id: \.self) { status in
                        Text(status.rawValue).tag(status.rawValue)
                    }
                }
                .help("Filter by paper status")

                Picker("Sort", selection: $sortFilter) {
                    ForEach(PaperSortOption.allCases, id: \.self) { option in
                        Text(option.displayName).tag(option.rawValue)
                    }
                }
                .help("Sort papers")

                Picker("Tag Display", selection: $tagDisplayModeRaw) {
                    ForEach(TagDisplayMode.allCases, id: \.self) { mode in
                        Label(mode.label, systemImage: mode.systemImage).tag(mode.rawValue)
                    }
                }
                .help("Choose how tags appear in the paper list")

                Button {
                    if selectedCount > 1 {
                        analyzeSelected()
                    } else {
                        analyzeMissing()
                    }
                } label: {
                    Label(selectedCount > 1 ? "Analyze Selected" : "Analyze Missing", systemImage: "sparkles")
                }
                .disabled(selectedCount > 1 ? false : unanalyzedCount == 0)
                .help(selectedCount > 1 ? "Queue abstract analysis for selected papers" : "Queue and start abstract analysis for all papers without LLM analysis")
            }
            .labelsHidden()

            TagFilterDropdownView(selectedTagsRaw: $tagFiltersRaw, availableTags: availableTags)
        }
        .padding(10)
    }
}

struct TagFilterDropdownView: View {
    @Binding var selectedTagsRaw: String
    let availableTags: [String]
    @State private var isShowingPopover = false

    private var selectedTags: Set<String> {
        TagSelectionCodec.decode(selectedTagsRaw)
    }

    private var title: String {
        if selectedTags.isEmpty {
            return "All Tags"
        }
        if selectedTags.count == 1, let tag = selectedTags.first {
            return tag
        }
        return "\(selectedTags.count) Tags"
    }

    var body: some View {
        HStack(spacing: 8) {
            Button {
                isShowingPopover.toggle()
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: "tag")
                        .foregroundStyle(.secondary)
                    Text(title)
                        .font(.callout)
                        .lineLimit(1)
                    if !selectedTags.isEmpty {
                        Text("\(selectedTags.count)")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(WorkspaceTheme.accent, in: Capsule())
                    }
                    Image(systemName: "chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(.quaternary, in: Capsule())
            }
            .buttonStyle(.plain)
            .disabled(availableTags.isEmpty)
            .help(availableTags.isEmpty ? "No tags are available yet" : "Filter papers by one or more tags")
            .popover(isPresented: $isShowingPopover, arrowEdge: .bottom) {
                TagFilterPopoverView(selectedTagsRaw: $selectedTagsRaw, availableTags: availableTags)
            }

            if !selectedTags.isEmpty {
                Button {
                    selectedTagsRaw = TagSelectionCodec.encode([])
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Clear tag filters")
            }

            Spacer(minLength: 0)
        }
    }
}

struct TagFilterPopoverView: View {
    @Binding var selectedTagsRaw: String
    let availableTags: [String]

    private var selectedTags: Set<String> {
        TagSelectionCodec.decode(selectedTagsRaw)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Filter Tags")
                    .font(.headline)
                Spacer()
                Button("Clear") {
                    selectedTagsRaw = TagSelectionCodec.encode([])
                }
                .disabled(selectedTags.isEmpty)
            }

            Divider()

            if availableTags.isEmpty {
                Text("No tags yet")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 12)
            } else {
                ScrollView {
                    WrappingTagLayout(horizontalSpacing: 8, verticalSpacing: 8) {
                        SelectableTagChipButton(
                            title: "All Tags",
                            tag: nil,
                            isSelected: selectedTags.isEmpty
                        ) {
                            selectedTagsRaw = TagSelectionCodec.encode([])
                        }
                        ForEach(availableTags, id: \.self) { tag in
                            SelectableTagChipButton(
                                title: tag,
                                tag: tag,
                                isSelected: selectedTags.contains(tag)
                            ) {
                                toggle(tag)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 1)
                }
                .frame(maxHeight: 260)
            }

            Text(selectedTags.isEmpty ? "Showing all tagged and untagged papers" : "Showing papers with any selected tag")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .frame(width: 380)
    }

    private func toggle(_ tag: String) {
        var tags = selectedTags
        if tags.contains(tag) {
            tags.remove(tag)
        } else {
            tags.insert(tag)
        }
        selectedTagsRaw = TagSelectionCodec.encode(tags)
    }
}

struct PaperRowView: View {
    let paper: Paper
    let analysis: LLMAnalysis?
    let tagDisplayMode: TagDisplayMode

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(paper.title)
                    .font(.headline)
                    .lineLimit(3)
                Spacer()
                if let analysis {
                    ScoreBadgeView(score: analysis.relevanceScore)
                }
                Text(paper.status.rawValue)
                    .font(.caption)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
            }
            Text(paper.authors.joined(separator: ", "))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Text(summaryPreview)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(3)
            if !displayTags.isEmpty {
                TagStripView(tags: displayTags, displayMode: tagDisplayMode)
            }
            HStack {
                if let category = paper.primaryCategory {
                    Text(category)
                }
                Text(paper.arxivID)
            }
            .font(.caption2)
            .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(paper.title)
        .accessibilityValue(accessibilitySummary)
        .accessibilityHint("Select to preview this paper")
    }

    private var summaryPreview: String {
        let summary = analysis?.oneSentenceSummary.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return summary.isEmpty ? paper.abstract : summary
    }

    private var displayTags: [String] {
        let tags = analysis?.canonicalTags ?? paper.tags
        return tags.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    private var accessibilitySummary: String {
        let score = analysis.map { "relevance \(RelevanceScore.displayScore($0.relevanceScore)) out of 100" }
        return [
            score,
            paper.status.rawValue,
            paper.primaryCategory,
            paper.arxivID
        ]
        .compactMap { $0 }
        .joined(separator: ", ")
    }
}

struct PaperDetailView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        VStack(spacing: 0) {
            if let paper = state.selectedPaper {
                DetailHeaderView(
                    paper: paper,
                    analysis: state.selectedPaperAnalysis,
                    tags: state.selectedPaperAnalysis?.canonicalTags ?? paper.tags
                )
                Divider()
                NativePaperDocumentView(paper: paper, deepReadMarkdown: state.deepReadMarkdown)
            } else {
                ContentUnavailableView("Select a Paper", systemImage: "doc.richtext", description: Text("The abstract, analysis, and deep-read Markdown will render here."))
            }
        }
    }
}

private struct NativePaperDocumentView: View {
    let paper: Paper
    let deepReadMarkdown: String

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Abstract")
                    .font(.title2.weight(.semibold))
                Text(paper.abstract)
                    .font(.body)
                    .lineSpacing(4)
                    .textSelection(.enabled)

                if !deepReadMarkdown.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Divider()
                        .padding(.vertical, 4)
                    Text("Deep Read")
                        .font(.title2.weight(.semibold))
                    Text(deepReadText)
                        .font(.body)
                        .lineSpacing(4)
                        .textSelection(.enabled)
                }
            }
            .frame(maxWidth: 760, alignment: .leading)
            .padding(.horizontal, 28)
            .padding(.vertical, 24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var deepReadText: AttributedString {
        (try? AttributedString(markdown: deepReadMarkdown)) ?? AttributedString(deepReadMarkdown)
    }
}

struct DetailHeaderView: View {
    let paper: Paper
    let analysis: LLMAnalysis?
    let tags: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(paper.title)
                .font(.title2.weight(.semibold))
                .lineLimit(3)
            HStack {
                Label(paper.arxivID, systemImage: "number")
                    .textSelection(.enabled)
                if let category = paper.primaryCategory {
                    Label(category, systemImage: "tag")
                }
                if let analysis {
                    ScoreBadgeView(score: analysis.relevanceScore)
                }
                Spacer()
                if let url = paper.absURL {
                    Link(destination: url) {
                        Label("arXiv", systemImage: "safari")
                    }
                }
                if let url = paper.pdfURL {
                    Link(destination: url) {
                        Label("PDF", systemImage: "doc")
                    }
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            if !tags.isEmpty {
                TagStripView(tags: tags, displayMode: .chips, layout: .wrap)
            }
            if let analysis {
                VStack(alignment: .leading, spacing: 6) {
                    if !analysis.oneSentenceSummary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text("LLM Summary")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text(analysis.oneSentenceSummary)
                            .font(.callout)
                            .textSelection(.enabled)
                    }
                    if !analysis.rationale.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text("Why It Matters")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .padding(.top, 2)
                        Text(analysis.rationale)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(16)
    }
}

struct ScoreBadgeView: View {
    let score: Double

    var body: some View {
        Text("\(RelevanceScore.displayScore(score))")
            .font(.caption.weight(.semibold))
            .monospacedDigit()
            .foregroundStyle(.white)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(scoreColor, in: Capsule())
            .help("Personalized relevance score")
            .accessibilityLabel("Relevance score \(RelevanceScore.displayScore(score)) out of 100")
    }

    private var scoreColor: Color {
        switch RelevanceScore.displayScore(score) {
        case 80...100:
            .green
        case 50..<80:
            .orange
        default:
            .secondary
        }
    }
}

enum TagDisplayMode: String, CaseIterable {
    case chips
    case dots

    var label: String {
        switch self {
        case .chips:
            "Text Tags"
        case .dots:
            "Color Dots"
        }
    }

    var systemImage: String {
        switch self {
        case .chips:
            "tag"
        case .dots:
            "circle.grid.3x3.fill"
        }
    }
}

enum TagStripLayout {
    case scroll
    case wrap
}

struct TagStripView: View {
    let tags: [String]
    let displayMode: TagDisplayMode
    var layout: TagStripLayout = .scroll

    var body: some View {
        switch displayMode {
        case .chips:
            if layout == .wrap {
                WrappingTagLayout(horizontalSpacing: 6, verticalSpacing: 6) {
                    ForEach(tags, id: \.self) { tag in
                        TagChipView(tag: tag)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(tags, id: \.self) { tag in
                            TagChipView(tag: tag)
                        }
                    }
                }
            }
        case .dots:
            if layout == .wrap {
                WrappingTagLayout(horizontalSpacing: 5, verticalSpacing: 5) {
                    ForEach(tags, id: \.self) { tag in
                        TagDotView(tag: tag)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityLabel(tags.joined(separator: ", "))
            } else {
                HStack(spacing: 5) {
                    ForEach(tags, id: \.self) { tag in
                        TagDotView(tag: tag)
                    }
                }
                .accessibilityLabel(tags.joined(separator: ", "))
            }
        }
    }
}

struct TagDotView: View {
    let tag: String

    var body: some View {
        Circle()
            .fill(TagColorPalette.color(for: tag))
            .frame(width: 9, height: 9)
            .overlay {
                Circle().stroke(.white.opacity(0.7), lineWidth: 1)
            }
            .help(tag)
    }
}

struct SelectableTagChipButton: View {
    let title: String
    let tag: String?
    let isSelected: Bool
    let action: () -> Void

    private var fill: Color {
        if let tag {
            return TagColorPalette.color(for: tag)
        }
        return .secondary
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Circle()
                    .fill(fill)
                    .frame(width: 8, height: 8)
                Text(title)
                    .font(.caption.weight(isSelected ? .semibold : .regular))
                    .lineLimit(1)
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(WorkspaceTheme.accent)
                }
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .foregroundStyle(.primary)
            .background(
                isSelected ? WorkspaceTheme.accent.opacity(0.16) : fill.opacity(tag == nil ? 0.08 : 0.14),
                in: Capsule()
            )
            .overlay {
                Capsule().stroke(isSelected ? WorkspaceTheme.accent.opacity(0.6) : fill.opacity(0.24), lineWidth: 0.8)
            }
        }
        .buttonStyle(.plain)
        .help(title)
    }
}

struct TagChipView: View {
    let tag: String

    var body: some View {
        Text(tag)
            .font(.system(size: 11, weight: .medium))
            .lineLimit(1)
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .foregroundStyle(TagColorPalette.foreground(for: tag))
            .background(TagColorPalette.color(for: tag).opacity(0.18), in: Capsule())
            .overlay {
                Capsule().stroke(TagColorPalette.color(for: tag).opacity(0.35), lineWidth: 0.7)
            }
            .help(tag)
    }
}

struct WrappingTagLayout: Layout {
    var horizontalSpacing: CGFloat = 6
    var verticalSpacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let fallbackWidth = subviews.reduce(CGFloat.zero) { partial, subview in
            partial + subview.sizeThatFits(.unspecified).width + horizontalSpacing
        }
        let maxWidth = max(proposal.width ?? fallbackWidth, 1)
        let rows = makeRows(in: maxWidth, subviews: subviews)
        let width = proposal.width ?? rows.map(\.width).max() ?? 0
        let height = rows.reduce(CGFloat.zero) { partial, row in
            partial + row.height
        } + CGFloat(max(rows.count - 1, 0)) * verticalSpacing
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let rows = makeRows(in: max(bounds.width, 1), subviews: subviews)
        var y = bounds.minY
        for row in rows {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(
                    at: CGPoint(x: x, y: y + (row.height - size.height) / 2),
                    proposal: ProposedViewSize(size)
                )
                x += size.width + horizontalSpacing
            }
            y += row.height + verticalSpacing
        }
    }

    private func makeRows(in maxWidth: CGFloat, subviews: Subviews) -> [TagLayoutRow] {
        var rows: [TagLayoutRow] = []
        var current = TagLayoutRow()

        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let spacing = current.indices.isEmpty ? 0 : horizontalSpacing
            if !current.indices.isEmpty, current.width + spacing + size.width > maxWidth {
                rows.append(current)
                current = TagLayoutRow()
            }
            current.indices.append(index)
            current.width += (current.indices.count == 1 ? 0 : horizontalSpacing) + size.width
            current.height = max(current.height, size.height)
        }

        if !current.indices.isEmpty {
            rows.append(current)
        }

        return rows
    }

    private struct TagLayoutRow {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }
}

enum TagSelectionCodec {
    static func decode(_ raw: String) -> Set<String> {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != "all" else { return [] }
        if let data = trimmed.data(using: .utf8),
           let decoded = try? JSONDecoder().decode([String].self, from: data) {
            return Set(decoded.map { normalize($0) }.filter { !$0.isEmpty })
        }
        return Set(trimmed.split(separator: "\n").map { normalize(String($0)) }.filter { !$0.isEmpty })
    }

    static func encode(_ tags: Set<String>) -> String {
        let normalized = tags.map { normalize($0) }.filter { !$0.isEmpty }.sorted()
        guard !normalized.isEmpty else { return "all" }
        if let data = try? JSONEncoder().encode(normalized),
           let encoded = String(data: data, encoding: .utf8) {
            return encoded
        }
        return normalized.joined(separator: "\n")
    }

    private static func normalize(_ tag: String) -> String {
        tag.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

enum TagColorPalette {
    private static let colors: [Color] = [
        Color(red: 0.10, green: 0.48, blue: 0.77),
        Color(red: 0.82, green: 0.30, blue: 0.37),
        Color(red: 0.23, green: 0.56, blue: 0.38),
        Color(red: 0.62, green: 0.39, blue: 0.76),
        Color(red: 0.72, green: 0.45, blue: 0.18),
        Color(red: 0.05, green: 0.55, blue: 0.58),
        Color(red: 0.68, green: 0.37, blue: 0.56),
        Color(red: 0.39, green: 0.49, blue: 0.18),
        Color(red: 0.46, green: 0.43, blue: 0.78),
        Color(red: 0.70, green: 0.26, blue: 0.19)
    ]

    static func color(for tag: String) -> Color {
        colors[index(for: tag)]
    }

    static func foreground(for tag: String) -> Color {
        colors[index(for: tag)].opacity(0.95)
    }

    private static func index(for tag: String) -> Int {
        let normalized = tag.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in normalized.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return Int(hash % UInt64(colors.count))
    }
}

struct StatusBarView: View {
    @EnvironmentObject private var state: AppState
    @State private var isShowingJobs = false

    var body: some View {
        HStack {
            Text(state.statusMessage)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Button {
                isShowingJobs.toggle()
            } label: {
                Label(state.jobStatusText, systemImage: state.isWorking ? "clock.arrow.circlepath" : "list.bullet.rectangle")
                    .font(.caption)
            }
            .buttonStyle(.plain)
            .help("Show recent queued, running, failed, and completed jobs")
            .popover(isPresented: $isShowingJobs, arrowEdge: .bottom) {
                JobStatusPopoverView(jobs: state.recentJobs)
                    .frame(width: 760, height: 420)
            }
            Text("\(state.papers.count) papers")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.bar)
    }
}

struct JobStatusPopoverView: View {
    @EnvironmentObject private var state: AppState
    let jobs: [SyncJob]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Jobs")
                    .font(.headline)
                Spacer()
                Button {
                    Task { await state.runPendingJobs() }
                } label: {
                    Label("Start All", systemImage: "play.fill")
                }
                .disabled(state.pendingJobCount == 0 || state.isWorking)
                .help("Start every pending job")
                Button(role: .destructive) {
                    state.clearJobs()
                } label: {
                    Label("Clear", systemImage: "trash")
                }
                .disabled(jobs.isEmpty || state.isWorking)
                .help("Delete all jobs, including stuck running jobs")
            }
            .padding([.horizontal, .top], 14)
            .padding(.bottom, 8)
            Divider()
            if jobs.isEmpty {
                ContentUnavailableView("No Jobs", systemImage: "list.bullet.rectangle")
            } else {
                HStack(alignment: .top, spacing: 0) {
                    JobBucketView(
                        title: "LLM",
                        systemImage: "brain",
                        jobs: jobs.filter { $0.kind == .summarizeAbstract || $0.kind == .deepRead },
                        startAll: {
                            Task {
                                await state.runPendingJobs(kind: .summarizeAbstract)
                                await state.runPendingJobs(kind: .deepRead)
                            }
                        },
                        clear: {
                            state.clearJobs(kind: .summarizeAbstract)
                            state.clearJobs(kind: .deepRead)
                        }
                    )
                    Divider()
                    JobBucketView(
                        title: "Notion",
                        systemImage: "square.grid.2x2",
                        jobs: jobs.filter { $0.kind == .syncNotion },
                        startAll: { Task { await state.runPendingJobs(kind: .syncNotion) } },
                        clear: { state.clearJobs(kind: .syncNotion) }
                    )
                    Divider()
                    JobBucketView(
                        title: "Zotero",
                        systemImage: "books.vertical",
                        jobs: jobs.filter { $0.kind == .syncZotero },
                        startAll: { Task { await state.runPendingJobs(kind: .syncZotero) } },
                        clear: { state.clearJobs(kind: .syncZotero) }
                    )
                }
            }
        }
    }
}

struct JobBucketView: View {
    @EnvironmentObject private var state: AppState
    let title: String
    let systemImage: String
    let jobs: [SyncJob]
    let startAll: () -> Void
    let clear: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(title, systemImage: systemImage)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text("\(jobs.filter { $0.state == .pending }.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 8) {
                Button {
                    startAll()
                } label: {
                    Image(systemName: "play.fill")
                }
                .buttonStyle(.borderless)
                .disabled(jobs.filter { $0.state == .pending }.isEmpty || state.isWorking)
                .help("Start pending \(title) jobs")
                Button(role: .destructive) {
                    clear()
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .disabled(jobs.isEmpty || state.isWorking)
                .help("Delete finished and queued \(title) jobs; active jobs are preserved")
            }
            if jobs.isEmpty {
                ContentUnavailableView("No \(title) Jobs", systemImage: systemImage)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(jobs) { job in
                    JobRowView(job: job)
                }
                .listStyle(.plain)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

struct JobRowView: View {
    @EnvironmentObject private var state: AppState
    let job: SyncJob

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Label(job.kind.rawValue, systemImage: iconName(for: job.state))
                    .font(.caption.weight(.medium))
                Spacer()
                Text(job.state.rawValue)
                    .font(.caption2)
                    .foregroundStyle(color(for: job.state))
            }
            Text(jobPayload(job))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            if let lastError = job.lastError, !lastError.isEmpty {
                Text(lastError)
                    .font(.caption2)
                    .foregroundStyle(.red)
                    .lineLimit(3)
                    .textSelection(.enabled)
                    .help(lastError)
                    .contextMenu {
                        Button("Copy Error") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(lastError, forType: .string)
                        }
                    }
            }
            HStack(spacing: 8) {
                Button {
                    Task { await state.runJob(jobID: job.id) }
                } label: {
                    Image(systemName: "play.circle")
                }
                .buttonStyle(.borderless)
                .disabled((job.state != .pending && job.state != .failed) || state.isWorking)
                .help(job.state == .running ? "This job is already running" : "Start this job")
                Button(role: .destructive) {
                    state.deleteJob(jobID: job.id)
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .disabled(state.isWorking || job.state == .running)
                .help(job.state == .running ? "Active jobs cannot be deleted" : "Delete this job")
            }
        }
        .padding(.vertical, 4)
    }

    private func jobPayload(_ job: SyncJob) -> String {
        String(data: job.payload, encoding: .utf8) ?? "No payload"
    }

    private func iconName(for state: SyncJob.State) -> String {
        switch state {
        case .pending:
            "clock"
        case .running:
            "play.circle"
        case .succeeded:
            "checkmark.circle"
        case .failed:
            "exclamationmark.triangle"
        }
    }

    private func color(for state: SyncJob.State) -> Color {
        switch state {
        case .pending:
            .secondary
        case .running:
            .blue
        case .succeeded:
            .green
        case .failed:
            .red
        }
    }
}
