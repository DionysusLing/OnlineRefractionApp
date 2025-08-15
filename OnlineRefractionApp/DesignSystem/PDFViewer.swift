import SwiftUI
import PDFKit

struct PDFViewerBundled: View {
    let fileName: String   // 不含扩展名
    let title: String?     // 现在不用了

    var body: some View {
        NavigationStack {
            PDFKitView(url: Bundle.main.url(forResource: fileName, withExtension: "pdf"))
                .ignoresSafeArea()
        }
        // iOS 16+
        .toolbar(.hidden, for: .navigationBar)
        .toolbarBackground(.hidden, for: .navigationBar)
        // 兼容更老版本
        .navigationBarHidden(true)
    }
}

private struct PDFKitView: UIViewRepresentable {
    let url: URL?

    func makeUIView(context: Context) -> PDFView {
        let v = PDFView()
        v.autoScales = true
        v.displayMode = .singlePageContinuous
        v.displayDirection = .vertical
        v.backgroundColor = .systemBackground
        if let url, let doc = PDFDocument(url: url) {
            v.document = doc
        }
        return v
    }

    func updateUIView(_ uiView: PDFView, context: Context) {}
}
