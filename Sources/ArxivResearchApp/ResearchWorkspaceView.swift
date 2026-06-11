import Foundation
import SwiftUI
import AppKit
import ArxivResearchCore

struct ResearchWorkspaceView: View {
    @EnvironmentObject private var state: AppState
    private let toolbarTooltips = [
        "Refresh": "Reload local papers and query settings",
        "Fetch Now": "Fetch the selected arXiv query now",
        "Interested": "Mark the selected paper as interested",
        "Deep Read": "Queue a full-paper LLM deep read for the selected paper",
        "Run Jobs": "Run pending LLM, Notion, and Zotero jobs",
        "Sync Notion": "Queue Notion sync for the selected paper",
        "Send to Zotero": "Queue Zotero sync for the selected paper"
    ]

    var body: some View {
        NavigationSplitView {
            QuerySidebarView()
                .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 320)
        } content: {
            PaperListView()
                .navigationSplitViewColumnWidth(min: 320, ideal: 420, max: 560)
        } detail: {
            PaperDetailView()
        }
        .toolbar {
            ToolbarItemGroup {
                ToolbarHelpButton(
                    title: "Refresh",
                    systemImage: "arrow.clockwise",
                    help: "Reload local papers and query settings",
                    isDisabled: state.isWorking
                ) {
                    state.reload()
                }
                .help("Reload local papers and query settings")
                ToolbarHelpButton(
                    title: "Fetch Now",
                    systemImage: "tray.and.arrow.down",
                    help: "Fetch the selected arXiv query now",
                    isDisabled: state.isWorking
                ) {
                    Task { await state.fetchSelectedQueryNow() }
                }
                .help("Fetch the selected arXiv query now")
                ToolbarHelpButton(
                    title: "Interested",
                    systemImage: "star",
                    help: "Mark the selected paper as interested",
                    isDisabled: state.selectedPaper == nil || state.isWorking
                ) {
                    state.markInterested()
                }
                .help("Mark the selected paper as interested")
                ToolbarHelpButton(
                    title: "Deep Read",
                    systemImage: "doc.text.magnifyingglass",
                    help: "Queue a full-paper LLM deep read for the selected paper",
                    isDisabled: state.selectedPaper == nil || state.isWorking
                ) {
                    state.queueDeepRead()
                }
                .help("Queue a full-paper LLM deep read for the selected paper")
                ToolbarHelpButton(
                    title: "Run Jobs",
                    systemImage: "play.circle",
                    help: "Run pending LLM, Notion, and Zotero jobs",
                    isDisabled: state.pendingJobCount == 0 || state.isWorking
                ) {
                    Task { await state.runPendingJobs() }
                }
                .help("Run pending LLM, Notion, and Zotero jobs")
                ToolbarHelpButton(
                    title: "Sync Notion",
                    systemImage: "square.and.arrow.up",
                    help: "Queue Notion sync for the selected paper",
                    isDisabled: state.selectedPaper == nil || state.isWorking
                ) {
                    state.syncNotion()
                }
                .help("Queue Notion sync for the selected paper")
                ToolbarHelpButton(
                    title: "Send to Zotero",
                    systemImage: "books.vertical",
                    help: "Queue Zotero sync for the selected paper",
                    isDisabled: state.selectedPaper == nil || state.isWorking
                ) {
                    state.syncZotero()
                }
                .help("Queue Zotero sync for the selected paper")
            }
        }
        .safeAreaInset(edge: .bottom) {
            StatusBarView()
        }
        .background {
            ToolbarTooltipInstaller(tooltips: toolbarTooltips)
                .frame(width: 0, height: 0)
        }
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

    var body: some View {
        VStack(spacing: 0) {
            List(selection: $state.selectedQueryID) {
                Section("Subscriptions") {
                    ForEach(state.queryProfiles) { profile in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(profile.name)
                                .font(.headline)
                            Text(ArxivQueryBuilder.displayRawQuery(profile.rawQuery))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                            Text("Every \(profile.refreshIntervalHours)h")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                        .tag(profile.id)
                    }
                }
            }
            .overlay {
                if state.queryProfiles.isEmpty {
                    ContentUnavailableView("No Queries", systemImage: "magnifyingglass", description: Text("Create a query to start tracking arXiv."))
                }
            }
            Divider()
            QueryEditorView()
        }
    }
}

struct QueryEditorView: View {
    @EnvironmentObject private var state: AppState
    @State private var name = ""
    @State private var rawQuery = ""
    @State private var refreshIntervalHours = 24
    @State private var isEnabled = true
    @State private var isShowingDeleteQueryDialog = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Query")
                    .font(.headline)
                Spacer()
                Button {
                    state.addQuery()
                    syncDraft()
                } label: {
                    Image(systemName: "plus")
                }
                .help("Add query")
                Button {
                    isShowingDeleteQueryDialog = true
                } label: {
                    Image(systemName: "trash")
                }
                .help("Delete selected query")
            }
            TextField("Name", text: $name)
            TextField("Raw arXiv query", text: $rawQuery, axis: .vertical)
                .lineLimit(2...4)
                .font(.system(.caption, design: .monospaced))
            Stepper("Every \(refreshIntervalHours) hours", value: $refreshIntervalHours, in: 1...168)
            Toggle("Enabled", isOn: $isEnabled)
            Button {
                saveDraft()
            } label: {
                Label("Save Query", systemImage: "tray.and.arrow.down")
            }
            HStack {
                Button {
                    saveDraft()
                    Task { await state.testSelectedQuery() }
                } label: {
                    Label("Test Query", systemImage: "checkmark.seal")
                }
                .disabled(state.isWorking)
                Button {
                    saveDraft()
                    Task { await state.fetchSelectedQueryNow() }
                } label: {
                    Label("Fetch Now", systemImage: "tray.and.arrow.down")
                }
                .disabled(state.isWorking)
            }
            if !draftPreviewURL.isEmpty {
                Text(draftPreviewURL)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .textSelection(.enabled)
            }
        }
        .padding(12)
        .onAppear(perform: syncDraft)
        .onChange(of: state.selectedQueryID) {
            syncDraft()
        }
        .confirmationDialog("Delete Query", isPresented: $isShowingDeleteQueryDialog) {
            Button("Delete Query Only") {
                state.deleteSelectedQuery(deleteAssociatedPapers: false)
                syncDraft()
            }
            Button("Delete Query and Papers", role: .destructive) {
                state.deleteSelectedQuery(deleteAssociatedPapers: true)
                syncDraft()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("You can keep existing papers, or remove all paper entries associated with this query.")
        }
    }

    private func syncDraft() {
        guard let query = state.selectedQuery() else {
            name = ""
            rawQuery = ""
            refreshIntervalHours = 24
            isEnabled = true
            return
        }
        name = query.name
        rawQuery = ArxivQueryBuilder.displayRawQuery(query.rawQuery)
        refreshIntervalHours = query.refreshIntervalHours
        isEnabled = query.isEnabled
        state.updateQueryPreview()
    }

    private var draftPreviewURL: String {
        let request = ArxivAPIRequest(searchQuery: .raw(rawQuery), maxResults: 5)
        return (try? request.url().absoluteString) ?? ""
    }

    private func saveDraft() {
        if let id = state.selectedQueryID {
            state.saveQuery(id: id, name: name, rawQuery: rawQuery, refreshIntervalHours: refreshIntervalHours, isEnabled: isEnabled)
        }
    }
}

struct PaperListView: View {
    @EnvironmentObject private var state: AppState
    @SceneStorage("paper.searchText") private var searchText = ""
    @SceneStorage("paper.statusFilter") private var statusFilter = "all"
    @SceneStorage("paper.tagFilter") private var tagFiltersRaw = "all"
    @SceneStorage("paper.dateFilter") private var dateFilter = PaperDateRange.all.rawValue
    @SceneStorage("paper.sortFilter") private var sortFilter = PaperSortOption.dateDescending.rawValue
    @SceneStorage("paper.tagDisplayMode") private var tagDisplayModeRaw = TagDisplayMode.chips.rawValue

    var body: some View {
        VStack(spacing: 0) {
            PaperFilterBarView(
                searchText: $searchText,
                statusFilter: $statusFilter,
                tagFiltersRaw: $tagFiltersRaw,
                dateFilter: $dateFilter,
                sortFilter: $sortFilter,
                tagDisplayModeRaw: $tagDisplayModeRaw,
                availableTags: availableTags
            )
            Divider()
            List(filteredPapers, selection: $state.selectedPaperID) { paper in
                Button {
                    state.selectPaper(paper)
                } label: {
                    PaperRowView(
                        paper: paper,
                        analysis: state.latestAnalysesByPaperID[paper.arxivID],
                        tagDisplayMode: tagDisplayMode
                    )
                }
                .buttonStyle(.plain)
                .tag(paper.id)
                .contextMenu {
                    Button {
                        state.queueSummary(paperID: paper.id)
                    } label: {
                        Label("Analyze Abstract", systemImage: "text.badge.checkmark")
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
                        state.archivePaper(paperID: paper.id)
                    } label: {
                        Label("Archive", systemImage: "archivebox")
                    }
                    Button(role: .destructive) {
                        state.deletePaper(paperID: paper.id)
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
            .overlay {
                if state.papers.isEmpty {
                    ContentUnavailableView("No Papers", systemImage: "doc.text", description: Text("Scheduled fetches will appear here."))
                } else if filteredPapers.isEmpty {
                    ContentUnavailableView("No Matches", systemImage: "line.3.horizontal.decrease.circle", description: Text("Adjust search or filters."))
                }
            }
            .onChange(of: state.selectedPaperID) {
                if let id = state.selectedPaperID,
                   let paper = state.papers.first(where: { $0.id == id }) {
                    state.selectPaper(paper)
                }
            }
        }
    }

    private var filteredPapers: [Paper] {
        PaperFilter.apply(state.papers, criteria: PaperFilterCriteria(
            searchText: searchText,
            status: statusFilter == "all" ? nil : PaperStatus(rawValue: statusFilter),
            tags: selectedTagFilters,
            dateRange: PaperDateRange(rawValue: dateFilter) ?? .all,
            sort: PaperSortOption(rawValue: sortFilter) ?? .dateDescending
        ), analysesByPaperID: state.latestAnalysesByPaperID)
    }

    private var availableTags: [String] {
        Array(Set(state.papers.flatMap(\.tags))).sorted()
    }

    private var tagDisplayMode: TagDisplayMode {
        TagDisplayMode(rawValue: tagDisplayModeRaw) ?? .chips
    }

    private var selectedTagFilters: Set<String> {
        TagSelectionCodec.decode(tagFiltersRaw)
    }
}

struct PaperFilterBarView: View {
    @Binding var searchText: String
    @Binding var statusFilter: String
    @Binding var tagFiltersRaw: String
    @Binding var dateFilter: String
    @Binding var sortFilter: String
    @Binding var tagDisplayModeRaw: String
    let availableTags: [String]

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

                Picker("Date", selection: $dateFilter) {
                    ForEach(PaperDateRange.allCases, id: \.self) { range in
                        Text(range.displayName).tag(range.rawValue)
                    }
                }
                .help("Filter by updated or published date")

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
                            .background(Color.accentColor, in: Capsule())
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
            Text(paper.abstract)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(3)
            if !paper.tags.isEmpty {
                TagStripView(tags: paper.tags, displayMode: tagDisplayMode)
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
                MarkdownWebView(html: state.renderedPaperDetailHTML)
            } else {
                ContentUnavailableView("Select a Paper", systemImage: "doc.richtext", description: Text("The abstract, analysis, and deep-read Markdown will render here."))
            }
        }
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
                        .foregroundStyle(Color.accentColor)
                }
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .foregroundStyle(.primary)
            .background(
                isSelected ? Color.accentColor.opacity(0.16) : fill.opacity(tag == nil ? 0.08 : 0.14),
                in: Capsule()
            )
            .overlay {
                Capsule().stroke(isSelected ? Color.accentColor.opacity(0.6) : fill.opacity(0.24), lineWidth: 0.8)
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
            .font(.caption2.weight(.medium))
            .lineLimit(1)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
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
                .disabled(jobs.filter { $0.state != .running }.isEmpty || state.isWorking)
                .help("Delete all non-running jobs")
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
                .disabled(jobs.filter { $0.state != .running }.isEmpty || state.isWorking)
                .help("Delete non-running \(title) jobs")
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
            }
            HStack(spacing: 8) {
                Button {
                    Task { await state.runJob(jobID: job.id) }
                } label: {
                    Image(systemName: "play.circle")
                }
                .buttonStyle(.borderless)
                .disabled((job.state != .pending && job.state != .failed) || state.isWorking)
                .help("Start this job")
                Button(role: .destructive) {
                    state.deleteJob(jobID: job.id)
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .disabled(job.state == .running || state.isWorking)
                .help("Delete this job")
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
