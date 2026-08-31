import SwiftData
import SwiftUI

struct MetadataEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Bindable var document: LibraryDocument
    @Query(sort: \LibraryFolder.name) private var folders: [LibraryFolder]

    @State private var name = ""
    @State private var tagsText = ""
    @State private var selectedFolderID: UUID?
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("名称") {
                    TextField("资料名称", text: $name)
                }

                Section("标签") {
                    TextField("用逗号分隔，例如：课程, 论文", text: $tagsText)
                    Text("标签会参与资料库搜索。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("文件夹") {
                    Picker("位置", selection: $selectedFolderID) {
                        Text("未分类").tag(UUID?.none)
                        ForEach(folders) { folder in
                            Text(folder.name).tag(Optional(folder.id))
                        }
                    }
                }

                Section("资料") {
                    LabeledContent("类型", value: document.type.displayName)
                    LabeledContent("大小", value: document.formattedSize)
                }
            }
            .navigationTitle("资料信息")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存", action: save)
                        .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .task {
                name = document.name
                tagsText = document.tags.joined(separator: ", ")
                selectedFolderID = document.folderID
            }
            .alert("无法保存资料信息", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("确定", role: .cancel) { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    private func save() {
        let originalValues = (
            name: document.name,
            tags: document.tags,
            folderID: document.folderID,
            modifiedAt: document.modifiedAt
        )

        document.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        document.tags = tagsText.split(separator: ",").map(String.init)
        document.folderID = selectedFolderID
        document.modifiedAt = .now

        do {
            try modelContext.save()
            dismiss()
        } catch {
            document.name = originalValues.name
            document.tags = originalValues.tags
            document.folderID = originalValues.folderID
            document.modifiedAt = originalValues.modifiedAt
            errorMessage = error.localizedDescription
        }
    }
}
