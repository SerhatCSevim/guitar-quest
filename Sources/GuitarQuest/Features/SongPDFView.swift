// PDF tab pages next to the recording (PDFKit). Pages can follow the video through page anchors.
import SwiftUI
import AppKit
import PDFKit

struct PDFKitView: NSViewRepresentable {
    let document: PDFDocument
    @Binding var page: Int          // 0-based page shown
    var zoom: CGFloat = 1           // 1 = fit the width; 1.3 = 30 % larger …
    var onUserPageChange: (Int) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> PDFView {
        let v = PDFView()
        v.document = document
        v.displayMode = .singlePageContinuous
        v.displayDirection = .vertical
        v.autoScales = true
        v.backgroundColor = NSColor(white: 0.93, alpha: 1)
        v.pageBreakMargins = NSEdgeInsets(top: 6, left: 6, bottom: 6, right: 6)
        NotificationCenter.default.addObserver(context.coordinator, selector: #selector(Coordinator.pageChanged(_:)), name: .PDFViewPageChanged, object: v)
        context.coordinator.view = v
        return v
    }

    func updateNSView(_ v: PDFView, context: Context) {
        context.coordinator.parent = self
        if v.document !== document { v.document = document }
        if zoom != context.coordinator.appliedZoom {
            context.coordinator.appliedZoom = zoom
            if zoom == 1 { v.autoScales = true } else { v.autoScales = false; v.scaleFactor = v.scaleFactorForSizeToFit * zoom }
        }
        if let p = document.page(at: page), v.currentPage !== p, !context.coordinator.suppress {
            context.coordinator.suppress = true
            v.go(to: p)
            context.coordinator.suppress = false
        }
    }

    final class Coordinator: NSObject {
        var parent: PDFKitView
        weak var view: PDFView?
        var suppress = false
        var appliedZoom: CGFloat = 1
        init(_ parent: PDFKitView) { self.parent = parent }
        @objc func pageChanged(_ n: Notification) {
            guard !suppress, let v = view, let cur = v.currentPage else { return }
            let idx = parent.document.index(for: cur)
            if idx != parent.page { DispatchQueue.main.async { self.parent.onUserPageChange(idx) } }
        }
    }
}

/// The card: page controls, "the video is on this page" marks, and the pages themselves.
struct PDFTabCard: View {
    @Bindable var controller: SongPlayerController
    var onImportTab: () -> Void

    @State private var zoom: CGFloat = 1
    @State private var confirmRemove = false

    var body: some View {
        if let doc = controller.pdf {
            Card(padding: EdgeInsets(top: 10, leading: 12, bottom: 10, trailing: 12)) {
                VStack(alignment: .leading, spacing: 8) {
                    FlowLayout(hSpacing: 8, vSpacing: 8, alignment: .center) {
                        Text("Tab (PDF)").font(.system(size: 15, weight: .bold)).foregroundStyle(Theme.ink)
                        if let n = controller.song.pdfOriginalName { SmallText(n, muted: true) }
                        HStack(spacing: 4) {
                            GQButton("", icon: "chevron.left", small: true, disabled: controller.pdfPage <= 0) { controller.userChangedPage(controller.pdfPage - 1) }
                            Text("Page \(controller.pdfPage + 1) of \(doc.pageCount)").font(.system(size: 13, weight: .semibold)).frame(minWidth: 90)
                            GQButton("", icon: "chevron.right", small: true, disabled: controller.pdfPage >= doc.pageCount - 1) { controller.userChangedPage(controller.pdfPage + 1) }
                        }
                        HStack(spacing: 4) {
                            GQButton("−", small: true) { zoom = max(0.6, zoom - 0.15) }
                            GQButton("Fit", small: true) { zoom = 1 }
                            GQButton("+", small: true) { zoom = min(3, zoom + 0.15) }
                        }
                        if controller.player != nil {
                            GQButton("Mark: video is on this page", icon: "bookmark.fill", style: .primary, small: true) { controller.markPage() }
                                .help("Press while the video plays this page; the pages will then turn by themselves")
                        }
                        GQButton("Import Guitar Pro / MusicXML tab…", style: .ghost, small: true, action: onImportTab)
                        GQButton("Remove PDF", style: .ghost, small: true) { confirmRemove = true }
                    }
                    if !controller.song.pageAnchors.isEmpty {
                        FlowLayout(hSpacing: 6, vSpacing: 6) {
                            ForEach(controller.song.pageAnchors.sorted { $0.mediaTime < $1.mediaTime }, id: \.page) { a in
                                HStack(spacing: 4) {
                                    Text("page \(a.page + 1) ↔ \(SongPlayerController.clockPrecise(a.mediaTime))").font(.system(size: 12, weight: .semibold))
                                    Button { controller.removePageAnchor(a.page) } label: { Image(systemName: "xmark").font(.system(size: 9, weight: .bold)) }.buttonStyle(.plain)
                                }
                                .padding(.vertical, 4).padding(.horizontal, 8).background(Theme.tealSoft).foregroundStyle(Theme.teal).clipShape(Capsule())
                            }
                            GQButton("Clear", style: .ghost, small: true) { controller.clearPageAnchors() }
                        }
                    } else if controller.player != nil {
                        SmallText("Pages do not turn by themselves yet: play the video, and on each page press “Mark: video is on this page”.", muted: true)
                    }
                    PDFKitView(document: doc, page: Binding(get: { controller.pdfPage }, set: { controller.userChangedPage($0) }), zoom: zoom,
                               onUserPageChange: { controller.userChangedPage($0) })
                        .frame(height: 640)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
            }
            .padding(.bottom, 16)
            .alert("Remove the PDF from this song?", isPresented: $confirmRemove) {
                Button("Remove", role: .destructive) { controller.removePDF() }
                Button("Cancel", role: .cancel) {}
            } message: { Text("Only the copy inside Guitar Quest is removed; your original file stays where it is.") }
        }
    }
}
