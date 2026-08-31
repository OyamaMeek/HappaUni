import CoreGraphics
import PDFKit

struct PDFDocumentState: Equatable {
    let pageCount: Int
    let currentPage: Int
    let zoomScale: CGFloat
    let searchMatchCount: Int

    static let empty = PDFDocumentState(pageCount: 0, currentPage: 0, zoomScale: 1, searchMatchCount: 0)
}

enum PDFService {
    static func state(
        for document: PDFDocument?,
        currentPage: PDFPage?,
        zoomScale: CGFloat,
        searchMatchCount: Int = 0
    ) -> PDFDocumentState {
        guard let document else { return .empty }
        let pageIndex = currentPage.flatMap { document.index(for: $0) }
        return PDFDocumentState(
            pageCount: document.pageCount,
            currentPage: pageIndex.map { $0 + 1 } ?? (document.pageCount > 0 ? 1 : 0),
            zoomScale: zoomScale,
            searchMatchCount: searchMatchCount
        )
    }
}
