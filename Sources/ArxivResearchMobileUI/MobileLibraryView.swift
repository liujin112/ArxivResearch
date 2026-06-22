import SwiftUI
import Foundation
import ArxivResearchCore

public struct MobileLibraryView: View {
    @StateObject private var state: MobileAppState

    @MainActor
    public init(state: MobileAppState = MobileAppState()) {
        _state = StateObject(wrappedValue: state)
    }

    public var body: some View {
        TabView {
            NavigationStack {
                LibraryListView()
                    .environmentObject(state)
            }
            .tabItem {
                Label("Library", systemImage: "books.vertical")
            }

            NavigationStack {
                SubscriptionsView()
                    .environmentObject(state)
            }
            .tabItem {
                Label("Subscriptions", systemImage: "dot.radiowaves.left.and.right")
            }

            NavigationStack {
                JobsView()
                    .environmentObject(state)
            }
            .tabItem {
                Label("Jobs", systemImage: "list.bullet.rectangle")
            }

            NavigationStack {
                SyncStatusView()
                    .environmentObject(state)
            }
            .tabItem {
                Label("Sync", systemImage: "icloud")
            }
        }
    }
}

private struct LibraryListView: View {
    @EnvironmentObject private var state: MobileAppState

    var body: some View {
        List {
            filterSection
            ForEach(state.filteredPapers) { paper in
                NavigationLink(value: paper.id) {
                    PaperRowView(paper: paper, analysis: state.latestAnalysis(for: paper))
                }
            }
        }
        .navigationTitle("Library")
        .navigationDestination(for: Paper.ID.self) { paperID in
            if let paper = state.papers.first(where: { $0.id == paperID }) {
                PaperDetailView(paper: paper)
                    .environmentObject(state)
            } else {
                ContentUnavailableView("Paper unavailable", systemImage: "doc.text.magnifyingglass")
            }
        }
        .searchable(text: $state.searchText, prompt: "Search papers")
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button {
                    state.refresh()
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
            }
        }
    }

    private var filterSection: some View {
        Section {
            Picker("Status", selection: statusSelection) {
                Text("Any Status").tag(String?.none)
                ForEach(PaperStatus.allCases, id: \.self) { status in
                    Text(status.label).tag(Optional(status.rawValue))
                }
            }
            Picker("Tag", selection: $state.tagFilter) {
                Text("Any Tag").tag(String?.none)
                ForEach(state.availableTags, id: \.self) { tag in
                    Text(tag).tag(Optional(tag))
                }
            }
            if state.statusFilter != nil || state.tagFilter != nil || !state.searchText.isEmpty {
                Button("Clear Filters") {
                    state.clearFilters()
                }
            }
        }
    }

    private var statusSelection: Binding<String?> {
        Binding(
            get: { state.statusFilter?.rawValue },
            set: { value in
                state.statusFilter = value.flatMap(PaperStatus.init(rawValue:))
            }
        )
    }
}

private struct PaperRowView: View {
    var paper: Paper
    var analysis: LLMAnalysis?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(paper.title)
                .font(.headline)
                .lineLimit(2)
            Text(paper.authors.joined(separator: ", "))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            HStack {
                Text(paper.status.label)
                if let score = analysis?.relevanceScore {
                    Text(score, format: .number.precision(.fractionLength(1)))
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}

private struct PaperDetailView: View {
    @EnvironmentObject private var state: MobileAppState
    var paper: Paper

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text(paper.title)
                    .font(.title2)
                    .fontWeight(.semibold)

                Text(paper.authors.joined(separator: ", "))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                tagFlow

                if let analysis = state.latestAnalysis(for: paper) {
                    analysisSection(analysis)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Abstract")
                        .font(.headline)
                    Text(paper.abstract)
                        .textSelection(.enabled)
                }

                if let deepRead = state.latestDeepRead(for: paper), !deepRead.markdown.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Deep Read")
                            .font(.headline)
                        Text(deepRead.markdown)
                            .font(.body.monospaced())
                            .textSelection(.enabled)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
        }
        .navigationTitle(paper.arxivID)
        .toolbar {
            ToolbarItemGroup(placement: .automatic) {
                Button {
                    state.queueSummary(for: paper)
                } label: {
                    Label("Summarize", systemImage: "text.badge.checkmark")
                }

                Button {
                    state.queueDeepRead(for: paper)
                } label: {
                    Label("Deep Read", systemImage: "doc.text.magnifyingglass")
                }
            }
        }
    }

    private var tagFlow: some View {
        let tags = Array(Set(paper.tags + (state.latestAnalysis(for: paper)?.canonicalTags ?? []))).sorted()
        return LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 96), spacing: 8, alignment: .leading)],
            alignment: .leading,
            spacing: 8
        ) {
            ForEach(tags, id: \.self) { tag in
                Text(tag)
                    .font(.caption)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.thinMaterial, in: Capsule())
            }
        }
    }

    private func analysisSection(_ analysis: LLMAnalysis) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Analysis")
                    .font(.headline)
                Spacer()
                Text(analysis.relevanceScore, format: .number.precision(.fractionLength(1)))
                    .font(.headline)
            }
            Text(analysis.oneSentenceSummary)
            if !analysis.rationale.isEmpty {
                Text(analysis.rationale)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct SubscriptionsView: View {
    @EnvironmentObject private var state: MobileAppState

    var body: some View {
        List {
            if state.queryProfiles.isEmpty {
                ContentUnavailableView("No subscriptions", systemImage: "dot.radiowaves.left.and.right")
            } else {
                ForEach(state.queryProfiles) { profile in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(profile.name)
                                .font(.headline)
                            Spacer()
                            Text(profile.isEnabled ? "On" : "Off")
                                .font(.caption)
                                .foregroundStyle(profile.isEnabled ? .green : .secondary)
                        }
                        Text(profile.requestRawQuery)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Text("\(profile.maxResults) results every \(profile.refreshIntervalHours)h")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .navigationTitle("Subscriptions")
    }
}

private struct JobsView: View {
    @EnvironmentObject private var state: MobileAppState

    var body: some View {
        List {
            if state.jobs.isEmpty {
                ContentUnavailableView("No jobs", systemImage: "list.bullet.rectangle")
            } else {
                ForEach(state.jobs) { job in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(job.kind.label)
                                .font(.headline)
                            Spacer()
                            Text(job.state.label)
                                .font(.caption)
                                .foregroundStyle(job.state.tint)
                        }
                        Text(job.payload.paperIDString ?? "No paper payload")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        if let lastError = job.lastError, !lastError.isEmpty {
                            Text(lastError)
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .navigationTitle("Jobs")
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button {
                    state.refresh()
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
            }
        }
    }
}

private struct SyncStatusView: View {
    @EnvironmentObject private var state: MobileAppState

    var body: some View {
        List {
            Section("Local Cache") {
                LabeledContent("Papers", value: "\(state.papers.count)")
                LabeledContent("Subscriptions", value: "\(state.queryProfiles.count)")
                LabeledContent("Jobs", value: "\(state.jobs.count)")
            }
            Section("Queue") {
                LabeledContent("Pending", value: "\(state.jobs.filter { $0.state == .pending }.count)")
                LabeledContent("Running", value: "\(state.jobs.filter { $0.state == .running }.count)")
                LabeledContent("Failed", value: "\(state.jobs.filter { $0.state == .failed }.count)")
            }
            Section("Status") {
                Text(state.statusMessage)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Sync")
    }
}

private extension PaperStatus {
    var label: String {
        switch self {
        case .new: "New"
        case .summarized: "Summarized"
        case .interested: "Interested"
        case .deepReading: "Deep Reading"
        case .deepRead: "Deep Read"
        case .archived: "Archived"
        }
    }
}

private extension SyncJob.Kind {
    var label: String {
        switch self {
        case .fetchArxiv: "Fetch arXiv"
        case .summarizeAbstract: "Summarize"
        case .deepRead: "Deep Read"
        case .syncNotion: "Notion Sync"
        case .syncZotero: "Zotero Sync"
        }
    }
}

private extension SyncJob.State {
    var label: String {
        switch self {
        case .pending: "Pending"
        case .running: "Running"
        case .succeeded: "Succeeded"
        case .failed: "Failed"
        }
    }

    var tint: Color {
        switch self {
        case .pending: .secondary
        case .running: .blue
        case .succeeded: .green
        case .failed: .red
        }
    }
}

private extension Data {
    var paperIDString: String? {
        String(data: self, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
