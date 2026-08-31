import CryptoKit
import Foundation
import PDFKit
import PencilKit
import SwiftUI
import UIKit

struct PDFReaderView: View {
    let url: URL

    @State private var state = PDFDocumentState.empty
    @State private var searchText = ""
    @State private var requestedPage: Int?
    @State private var requestedZoom: CGFloat?
    @State private var isMarkupEnabled = false
    @State private var markupSettings = PDFMarkupSettings()
    @State private var markupCommand: PDFMarkupCommand?

    var body: some View {
        PDFKitDocumentView(
            url: url,
            requestedPage: $requestedPage,
            requestedZoom: $requestedZoom,
            searchText: searchText,
            isMarkupEnabled: isMarkupEnabled,
            markupSettings: markupSettings,
            markupCommand: $markupCommand,
            state: $state
        )
        .background(Color.black)
        .safeAreaInset(edge: .top) {
            if isMarkupEnabled {
                PDFMarkupToolbar(
                    settings: $markupSettings,
                    command: $markupCommand
                )
                .padding(.horizontal)
                .padding(.top, 8)
            }
        }
        .safeAreaInset(edge: .bottom) {
            HStack(spacing: 14) {
                Button {
                    isMarkupEnabled.toggle()
                } label: {
                    Image(systemName: isMarkupEnabled ? "pencil.tip.crop.circle.badge.minus" : "pencil.tip.crop.circle.badge.plus")
                }
                .accessibilityLabel(isMarkupEnabled ? "退出书写" : "Apple Pencil 书写")
                .tint(isMarkupEnabled ? .accentColor : nil)

                Button {
                    requestedPage = max(1, state.currentPage - 1)
                } label: {
                    Image(systemName: "chevron.left")
                }
                .disabled(state.currentPage <= 1)

                Text(
                    state.errorMessage
                    ?? (state.pageCount == 0 ? "正在加载" : "\(state.currentPage) / \(state.pageCount)")
                )
                    .font(.subheadline.monospacedDigit())
                    .lineLimit(1)
                    .frame(minWidth: 68)

                Button {
                    requestedPage = min(state.pageCount, state.currentPage + 1)
                } label: {
                    Image(systemName: "chevron.right")
                }
                .disabled(state.currentPage == 0 || state.currentPage >= state.pageCount)

                Divider().frame(height: 22)

                Button {
                    requestedZoom = max(0.5, state.zoomScale - 0.2)
                } label: {
                    Image(systemName: "minus.magnifyingglass")
                }

                Button {
                    requestedZoom = min(5, state.zoomScale + 0.2)
                } label: {
                    Image(systemName: "plus.magnifyingglass")
                }

                TextField("搜索", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 130)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 11)
            .background(Color(uiColor: .secondarySystemBackground), in: Capsule())
            .shadow(color: .black.opacity(0.28), radius: 12, y: 5)
            .padding(.horizontal)
            .padding(.top, 8)
        }
    }
}

private enum PDFMarkupTool: String, CaseIterable, Identifiable {
    case pen
    case highlighter
    case eraser

    var id: String { rawValue }

    var title: String {
        switch self {
        case .pen: "钢笔"
        case .highlighter: "荧光笔"
        case .eraser: "橡皮擦"
        }
    }

    var systemImage: String {
        switch self {
        case .pen: "pencil.tip"
        case .highlighter: "highlighter"
        case .eraser: "eraser"
        }
    }
}

private enum PDFMarkupColor: String, CaseIterable, Identifiable {
    case graphite
    case blue
    case red
    case yellow

    var id: String { rawValue }

    var uiColor: UIColor {
        switch self {
        case .graphite: .label
        case .blue: .systemBlue
        case .red: .systemRed
        case .yellow: .systemYellow
        }
    }
}

private struct PDFMarkupSettings: Equatable {
    var tool: PDFMarkupTool = .pen
    var color: PDFMarkupColor = .blue
    var width: CGFloat = 4
}

private enum PDFMarkupCommand: Equatable {
    case undo(UUID)
    case redo(UUID)
    case clearPage(UUID)
}

private struct PDFMarkupToolbar: View {
    @Binding var settings: PDFMarkupSettings
    @Binding var command: PDFMarkupCommand?

    var body: some View {
        HStack(spacing: 10) {
            ForEach(PDFMarkupTool.allCases) { tool in
                Button {
                    settings.tool = tool
                } label: {
                    Image(systemName: tool.systemImage)
                        .frame(width: 30, height: 30)
                        .background(
                            settings.tool == tool ? Color.accentColor.opacity(0.22) : .clear,
                            in: Circle()
                        )
                }
                .accessibilityLabel(tool.title)
            }

            if settings.tool != .eraser {
                Divider().frame(height: 24)
                ForEach(PDFMarkupColor.allCases) { color in
                    Button {
                        settings.color = color
                    } label: {
                        Circle()
                            .fill(Color(uiColor: color.uiColor))
                            .overlay {
                                Circle()
                                    .stroke(.white, lineWidth: settings.color == color ? 2 : 0)
                                    .padding(2)
                            }
                            .frame(width: 22, height: 22)
                    }
                    .accessibilityLabel(color.rawValue)
                }

                Slider(value: $settings.width, in: 1...12, step: 1)
                    .frame(width: 84)
                    .accessibilityLabel("笔触粗细")
            }

            Divider().frame(height: 24)

            Button {
                command = .undo(UUID())
            } label: {
                Image(systemName: "arrow.uturn.backward")
            }
            .accessibilityLabel("撤销")

            Button {
                command = .redo(UUID())
            } label: {
                Image(systemName: "arrow.uturn.forward")
            }
            .accessibilityLabel("重做")

            Button(role: .destructive) {
                command = .clearPage(UUID())
            } label: {
                Image(systemName: "trash")
            }
            .accessibilityLabel("清空本页笔记")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .foregroundStyle(.primary)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay {
            Capsule().stroke(.white.opacity(0.14), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.2), radius: 12, y: 5)
    }
}

private struct PDFKitDocumentView: UIViewRepresentable {
    let url: URL
    @Binding var requestedPage: Int?
    @Binding var requestedZoom: CGFloat?
    let searchText: String
    let isMarkupEnabled: Bool
    let markupSettings: PDFMarkupSettings
    @Binding var markupCommand: PDFMarkupCommand?
    @Binding var state: PDFDocumentState

    func makeCoordinator() -> Coordinator {
        Coordinator(state: $state)
    }

    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        view.backgroundColor = .black
        context.coordinator.observe(view)
        context.coordinator.load(url: url, into: view)
        return view
    }

    func updateUIView(_ view: PDFView, context: Context) {
        if context.coordinator.loadedURL != url {
            context.coordinator.load(url: url, into: view)
        }
        if let requestedPage, let page = view.document?.page(at: requestedPage - 1) {
            view.go(to: page)
            DispatchQueue.main.async { self.requestedPage = nil }
        }
        if let requestedZoom {
            view.scaleFactor = requestedZoom
            DispatchQueue.main.async { self.requestedZoom = nil }
        }
        context.coordinator.updateSearch(searchText, in: view)
        context.coordinator.updateMarkup(
            isEnabled: isMarkupEnabled,
            settings: markupSettings,
            command: markupCommand,
            in: view
        )
        if markupCommand != nil {
            DispatchQueue.main.async { markupCommand = nil }
        }
    }

    final class Coordinator: NSObject {
        @Binding private var state: PDFDocumentState
        private var observers: [NSObjectProtocol] = []
        private var lastSearchText = ""
        private var lastMarkupCommand: PDFMarkupCommand?
        private var overlayProvider: PDFInkOverlayProvider?
        var loadedURL: URL?

        init(state: Binding<PDFDocumentState>) {
            _state = state
        }

        deinit {
            observers.forEach(NotificationCenter.default.removeObserver)
        }

        func observe(_ view: PDFView) {
            let center = NotificationCenter.default
            observers = [
                center.addObserver(forName: .PDFViewPageChanged, object: view, queue: .main) { [weak self, weak view] _ in
                    self?.publish(from: view)
                },
                center.addObserver(forName: .PDFViewScaleChanged, object: view, queue: .main) { [weak self, weak view] _ in
                    self?.publish(from: view)
                }
            ]
        }

        func load(url: URL, into view: PDFView) {
            loadedURL = url
            view.document = nil
            view.pageOverlayViewProvider = nil
            state = .empty

            DispatchQueue.global(qos: .userInitiated).async { [weak self, weak view] in
                let document: PDFDocument? = autoreleasepool {
                    guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else {
                        return nil
                    }
                    return PDFDocument(data: data)
                }
                let annotationData = PDFAnnotationStore.load(for: url)

                DispatchQueue.main.async {
                    guard let self, let view, self.loadedURL == url else { return }
                    guard let document, document.pageCount > 0 else {
                        self.state = .failed("无法加载 PDF")
                        return
                    }

                    view.document = document
                    view.autoScales = true
                    let provider = PDFInkOverlayProvider(
                        document: document,
                        documentURL: url,
                        drawingData: annotationData
                    )
                    self.overlayProvider = provider
                    view.pageOverlayViewProvider = provider
                    self.publish(from: view)
                }
            }
        }

        func updateSearch(_ searchText: String, in view: PDFView) {
            guard searchText != lastSearchText else { return }
            lastSearchText = searchText
            let selections = searchText.isEmpty ? [] : (view.document?.findString(searchText, withOptions: .caseInsensitive) ?? [])
            if let first = selections.first {
                view.setCurrentSelection(first, animate: true)
                view.go(to: first)
            }
            state = PDFService.state(
                for: view.document,
                currentPage: view.currentPage,
                zoomScale: view.scaleFactor,
                searchMatchCount: selections.count
            )
        }

        func updateMarkup(
            isEnabled: Bool,
            settings: PDFMarkupSettings,
            command: PDFMarkupCommand?,
            in view: PDFView
        ) {
            overlayProvider?.configure(isEnabled: isEnabled, settings: settings)
            guard let command, command != lastMarkupCommand else { return }
            lastMarkupCommand = command

            switch command {
            case .undo:
                overlayProvider?.undo(on: view.currentPage)
            case .redo:
                overlayProvider?.redo(on: view.currentPage)
            case .clearPage:
                overlayProvider?.clear(on: view.currentPage)
            }
        }

        private func publish(from view: PDFView?) {
            guard let view else { return }
            state = PDFService.state(
                for: view.document,
                currentPage: view.currentPage,
                zoomScale: view.scaleFactor
            )
        }
    }
}

private final class PDFInkOverlayProvider: NSObject, PDFPageOverlayViewProvider, PKCanvasViewDelegate {
    private let document: PDFDocument
    private let documentURL: URL
    private var drawingData: [Int: Data]
    private var canvases: [Int: PKCanvasView] = [:]
    private var saveWorkItem: DispatchWorkItem?
    private var isMarkupEnabled = false
    private var settings = PDFMarkupSettings()

    init(document: PDFDocument, documentURL: URL, drawingData: [Int: Data]) {
        self.document = document
        self.documentURL = documentURL
        self.drawingData = drawingData
    }

    func pdfView(_ view: PDFView, overlayViewFor page: PDFPage) -> UIView? {
        let pageIndex = document.index(for: page)
        guard pageIndex != NSNotFound else { return nil }

        let canvas = PKCanvasView()
        canvas.backgroundColor = .clear
        canvas.isOpaque = false
        canvas.drawingPolicy = .pencilOnly
        canvas.delegate = self
        canvas.drawing = drawing(for: pageIndex)
        canvases[pageIndex] = canvas
        applyConfiguration(to: canvas)
        return canvas
    }

    func configure(isEnabled: Bool, settings: PDFMarkupSettings) {
        isMarkupEnabled = isEnabled
        self.settings = settings
        canvases.values.forEach(applyConfiguration)
    }

    func undo(on page: PDFPage?) {
        canvas(for: page)?.undoManager?.undo()
    }

    func redo(on page: PDFPage?) {
        canvas(for: page)?.undoManager?.redo()
    }

    func clear(on page: PDFPage?) {
        guard let canvas = canvas(for: page) else { return }
        canvas.drawing = PKDrawing()
        persistDrawing(for: canvas)
    }

    func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
        persistDrawing(for: canvasView)
    }

    private func applyConfiguration(to canvas: PKCanvasView) {
        canvas.isUserInteractionEnabled = isMarkupEnabled
        switch settings.tool {
        case .pen:
            canvas.tool = PKInkingTool(.pen, color: settings.color.uiColor, width: settings.width)
        case .highlighter:
            canvas.tool = PKInkingTool(
                .marker,
                color: settings.color.uiColor.withAlphaComponent(0.35),
                width: settings.width * 2.4
            )
        case .eraser:
            canvas.tool = PKEraserTool(.vector)
        }
    }

    private func canvas(for page: PDFPage?) -> PKCanvasView? {
        guard let page else { return nil }
        let index = document.index(for: page)
        guard index != NSNotFound else { return nil }
        return canvases[index]
    }

    private func drawing(for pageIndex: Int) -> PKDrawing {
        guard let data = drawingData[pageIndex], let drawing = try? PKDrawing(data: data) else {
            return PKDrawing()
        }
        return drawing
    }

    private func persistDrawing(for canvas: PKCanvasView) {
        guard let entry = canvases.first(where: { $0.value === canvas }) else { return }
        drawingData[entry.key] = canvas.drawing.dataRepresentation()
        saveWorkItem?.cancel()

        let drawingData = drawingData
        let documentURL = documentURL
        let workItem = DispatchWorkItem {
            try? PDFAnnotationStore.save(drawingData, for: documentURL)
        }
        saveWorkItem = workItem
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 0.45, execute: workItem)
    }
}

struct PDFAnnotationArchive: Codable {
    var drawings: [Int: Data]
}

enum PDFAnnotationStore {
    static func load(for documentURL: URL, in directory: URL? = nil) -> [Int: Data] {
        let fileURL = archiveURL(for: documentURL, in: directory)
        guard
            let data = try? Data(contentsOf: fileURL),
            let archive = try? JSONDecoder().decode(PDFAnnotationArchive.self, from: data)
        else {
            return [:]
        }
        return archive.drawings
    }

    static func save(
        _ drawings: [Int: Data],
        for documentURL: URL,
        in directory: URL? = nil
    ) throws {
        let targetDirectory = try resolvedDirectory(directory)
        let fileURL = targetDirectory.appendingPathComponent(identifier(for: documentURL))
        let data = try JSONEncoder().encode(PDFAnnotationArchive(drawings: drawings))
        try data.write(to: fileURL, options: .atomic)
    }

    static func identifier(for documentURL: URL) -> String {
        let path = documentURL.standardizedFileURL.path
        let digest = SHA256.hash(data: Data(path.utf8))
        return digest.map { String(format: "%02x", $0) }.joined() + ".annotations"
    }

    private static func archiveURL(for documentURL: URL, in directory: URL?) -> URL {
        let directory = (try? resolvedDirectory(directory)) ?? documentURL.deletingLastPathComponent()
        return directory.appendingPathComponent(identifier(for: documentURL))
    }

    private static func resolvedDirectory(_ directory: URL?) throws -> URL {
        let directory = directory ?? FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("HappaUni/PDFAnnotations", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}
