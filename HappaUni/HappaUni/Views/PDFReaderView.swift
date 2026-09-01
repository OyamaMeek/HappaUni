import CryptoKit
import Foundation
import PDFKit
import PencilKit
import SwiftUI
import UIKit

struct PDFReaderView: View {
    let url: URL
    let initialPage: Int
    let onPageChanged: (Int) -> Void

    @State private var state = PDFDocumentState.empty
    @State private var searchText = ""
    @Binding var requestedPage: Int?
    @State private var requestedZoom: CGFloat?
    @State private var isMarkupEnabled = false

    var body: some View {
        PDFKitDocumentView(
            url: url,
            initialPage: initialPage,
            requestedPage: $requestedPage,
            requestedZoom: $requestedZoom,
            searchText: searchText,
            isMarkupEnabled: isMarkupEnabled,
            onPageChanged: onPageChanged,
            state: $state
        )
        .background(Color.black)
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

private struct PDFKitDocumentView: UIViewRepresentable {
    let url: URL
    let initialPage: Int
    @Binding var requestedPage: Int?
    @Binding var requestedZoom: CGFloat?
    let searchText: String
    let isMarkupEnabled: Bool
    let onPageChanged: (Int) -> Void
    @Binding var state: PDFDocumentState

    func makeCoordinator() -> Coordinator {
        Coordinator(state: $state, onPageChanged: onPageChanged)
    }

    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        view.backgroundColor = .black
        context.coordinator.observe(view)
        context.coordinator.load(url: url, initialPage: initialPage, into: view)
        return view
    }

    func updateUIView(_ view: PDFView, context: Context) {
        if context.coordinator.loadedURL != url {
            context.coordinator.load(url: url, initialPage: initialPage, into: view)
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
        context.coordinator.updateMarkup(isEnabled: isMarkupEnabled, in: view)
    }

    final class Coordinator: NSObject {
        @Binding private var state: PDFDocumentState
        private let onPageChanged: (Int) -> Void
        private var observers: [NSObjectProtocol] = []
        private var lastSearchText = ""
        private var overlayProvider: PDFInkOverlayProvider?
        var loadedURL: URL?

        init(state: Binding<PDFDocumentState>, onPageChanged: @escaping (Int) -> Void) {
            _state = state
            self.onPageChanged = onPageChanged
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

        func load(url: URL, initialPage: Int, into view: PDFView) {
            loadedURL = url
            view.document = nil
            view.pageOverlayViewProvider = nil
            state = .empty

            // PDFKit must create PDFDocument on the main thread. Creating it in a
            // background queue can return an empty document on newer iPadOS builds.
            DispatchQueue.main.async { [weak self, weak view] in
                guard let self, let view, self.loadedURL == url else { return }
                guard FileManager.default.fileExists(atPath: url.path) else {
                    self.state = .failed("PDF 文件不存在")
                    return
                }

                guard let document = PDFDocument(url: url), document.pageCount > 0 else {
                    self.state = .failed("无法加载 PDF")
                    return
                }

                let provider = PDFInkOverlayProvider(
                    document: document,
                    documentURL: url,
                    drawingData: PDFAnnotationStore.load(for: url)
                )
                self.overlayProvider = provider
                view.pageOverlayViewProvider = provider
                view.document = document
                view.autoScales = true
                let restoredPage = min(max(initialPage, 1), document.pageCount)
                if let page = document.page(at: restoredPage - 1) {
                    view.go(to: page)
                }
                self.publish(from: view)
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

        func updateMarkup(isEnabled: Bool, in view: PDFView) {
            overlayProvider?.configure(isEnabled: isEnabled, in: view)
        }

        private func publish(from view: PDFView?) {
            guard let view else { return }
            state = PDFService.state(
                for: view.document,
                currentPage: view.currentPage,
                zoomScale: view.scaleFactor
            )
            if state.currentPage > 0 {
                onPageChanged(state.currentPage)
            }
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
    private var toolPicker: PKToolPicker?

    init(document: PDFDocument, documentURL: URL, drawingData: [Int: Data]) {
        self.document = document
        self.documentURL = documentURL
        self.drawingData = drawingData
        super.init()
    }

    func pdfView(_ view: PDFView, overlayViewFor page: PDFPage) -> UIView? {
        let pageIndex = document.index(for: page)
        guard pageIndex != NSNotFound else { return nil }

        let canvas = PKCanvasView()
        canvas.backgroundColor = .clear
        canvas.isOpaque = false
        canvas.drawingPolicy = .anyInput
        canvas.delegate = self
        canvas.drawing = drawing(for: pageIndex)
        canvases[pageIndex] = canvas
        configureCanvas(canvas)
        if isMarkupEnabled {
            presentNativeToolPicker(for: canvas)
        }
        return canvas
    }

    func configure(isEnabled: Bool, in view: PDFView) {
        isMarkupEnabled = isEnabled
        canvases.values.forEach(configureCanvas)
        if isEnabled {
            if let canvas = canvas(for: view.currentPage) {
                presentNativeToolPicker(for: canvas)
            }
        } else {
            canvases.values.forEach { canvas in
                toolPicker?.setVisible(false, forFirstResponder: canvas)
                canvas.resignFirstResponder()
            }
        }
    }

    func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
        persistDrawing(for: canvasView)
    }

    private func configureCanvas(_ canvas: PKCanvasView) {
        canvas.isUserInteractionEnabled = isMarkupEnabled
    }

    private func presentNativeToolPicker(for canvas: PKCanvasView, retryIfNeeded: Bool = true) {
        guard let window = canvas.window else {
            guard retryIfNeeded else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self, weak canvas] in
                guard let self, let canvas, self.isMarkupEnabled else { return }
                self.presentNativeToolPicker(for: canvas, retryIfNeeded: false)
            }
            return
        }

        let picker = PKToolPicker.shared(for: window) ?? toolPicker ?? PKToolPicker()
        toolPicker = picker
        picker.addObserver(canvas)
        canvas.isUserInteractionEnabled = true
        canvas.becomeFirstResponder()
        picker.setVisible(true, forFirstResponder: canvas)
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

    static func delete(for documentURL: URL, in directory: URL? = nil) throws {
        let fileURL = try resolvedDirectory(directory)
            .appendingPathComponent(identifier(for: documentURL))
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        try FileManager.default.removeItem(at: fileURL)
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
