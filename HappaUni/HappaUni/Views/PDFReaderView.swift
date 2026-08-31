import PDFKit
import SwiftUI
import UIKit

struct PDFReaderView: View {
    let url: URL

    @State private var state = PDFDocumentState.empty
    @State private var searchText = ""
    @State private var requestedPage: Int?
    @State private var requestedZoom: CGFloat?

    var body: some View {
        PDFKitDocumentView(
            url: url,
            requestedPage: $requestedPage,
            requestedZoom: $requestedZoom,
            searchText: searchText,
            state: $state
        )
        .background(Color.black)
        .safeAreaInset(edge: .bottom) {
            HStack(spacing: 14) {
                Button {
                    requestedPage = max(1, state.currentPage - 1)
                } label: {
                    Image(systemName: "chevron.left")
                }
                .disabled(state.currentPage <= 1)

                Text(state.pageCount == 0 ? "正在加载" : "\(state.currentPage) / \(state.pageCount)")
                    .font(.subheadline.monospacedDigit())
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
    @Binding var requestedPage: Int?
    @Binding var requestedZoom: CGFloat?
    let searchText: String
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
    }

    final class Coordinator: NSObject {
        @Binding private var state: PDFDocumentState
        private var observers: [NSObjectProtocol] = []
        private var lastSearchText = ""
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
            view.document = PDFDocument(url: url)
            publish(from: view)
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
