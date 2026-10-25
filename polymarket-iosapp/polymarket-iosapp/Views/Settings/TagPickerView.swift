//
//  TagPickerView.swift
//  polymarket-iosapp
//

import SwiftUI

struct TagPickerView: View {
    @Binding var selected: [PMTag]

    @Environment(AppServices.self) private var services
    @State private var allTags: [PMTag] = []
    @State private var remoteTags: [PMTag] = []
    @State private var query = ""
    @State private var isLoading = false
    @State private var errorMessage: String?

    private var candidates: [PMTag] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        let local = q.isEmpty
            ? allTags
            : allTags.filter { $0.label.lowercased().contains(q) || $0.slug.contains(q) }
        var seen = Set(local.map(\.id))
        return local + remoteTags.filter { seen.insert($0.id).inserted }
    }

    var body: some View {
        List {
            if !selected.isEmpty {
                Section("選択中") {
                    ForEach(selected) { tag in row(tag) }
                }
            }
            Section {
                if let errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.triangle").foregroundStyle(.red)
                }
                ForEach(candidates) { tag in row(tag) }
            } header: {
                Text("タグ")
            }
        }
        .overlay { if isLoading && allTags.isEmpty { ProgressView() } }
        .searchable(text: $query, prompt: "タグを検索（例: crypto, politics）")
        .navigationTitle("タグを選択")
        .task { await loadTags() }
        .task(id: query) { await searchRemote() }
    }

    private func row(_ tag: PMTag) -> some View {
        Button {
            toggle(tag)
        } label: {
            HStack {
                VStack(alignment: .leading) {
                    Text(tag.label)
                    Text(tag.slug).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if selected.contains(where: { $0.id == tag.id }) {
                    Image(systemName: "checkmark").foregroundStyle(Color.accentColor)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func toggle(_ tag: PMTag) {
        if let index = selected.firstIndex(where: { $0.id == tag.id }) {
            selected.remove(at: index)
        } else {
            selected.append(tag)
        }
    }

    private func loadTags() async {
        guard allTags.isEmpty else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            allTags = try await services.gamma.allTags()
                .sorted { $0.label.localizedCaseInsensitiveCompare($1.label) == .orderedAscending }
            errorMessage = nil
        } catch {
            if !error.isCancellation { errorMessage = error.localizedDescription }
        }
    }

    /// 一覧にないタグも検索 API から補完する
    private func searchRemote() async {
        let text = query.trimmingCharacters(in: .whitespaces)
        guard text.count >= 2 else {
            remoteTags = []
            return
        }
        try? await Task.sleep(for: .milliseconds(350))
        guard !Task.isCancelled else { return }
        remoteTags = (try? await services.gamma.search(text).tags) ?? []
    }
}
