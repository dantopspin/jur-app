// Terms and Privacy inside the app: the same pages as the website, bundled (so they open
// instantly and offline), shown in a sheet with a Terms / Privacy switch, in the app's
// type and colours. The website pages hold Russian and English; the sheet shows the half
// in the app's language (Russian for Kazakh until a Kazakh text exists).
// Update the copies with ios/scripts/copy_legal.sh after editing legal/*.html.
import SwiftUI
import WebKit

enum LegalDoc: String, Identifiable, CaseIterable {
    case terms, privacy
    var id: String { rawValue }

    /// The website's address for this page: links to it open the sheet instead.
    init?(_ url: URL) {
        guard url.host == Config.termsURL.host else { return nil }
        switch url.path {
        case Config.termsURL.path: self = .terms
        case Config.privacyURL.path: self = .privacy
        default: return nil
        }
    }

    var title: String { t(self == .terms ? "settings.terms" : "settings.privacy") }
    var file: URL? { Bundle.main.url(forResource: rawValue, withExtension: "html") }
}

extension View {
    /// Links to Terms or Privacy anywhere below open the in-app sheet. Apply at the root
    /// and inside sheets that show legal links (a sheet can't present from the root).
    func legalLinks() -> some View { modifier(LegalLinks()) }
}

private struct LegalLinks: ViewModifier {
    @State private var doc: LegalDoc?

    func body(content: Content) -> some View {
        content
            .environment(\.openURL, OpenURLAction { url in
                if let d = LegalDoc(url) { doc = d; return .handled }
                return .systemAction
            })
            .sheet(item: $doc) { LegalView(doc: $0) }
    }
}

struct LegalView: View {
    @State var doc: LegalDoc
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("", selection: $doc) {
                    ForEach(LegalDoc.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, Layout.margin)
                .padding(.vertical, Sp.sm)
                LegalPage(doc: doc)
                    .id(doc)
                    .transition(.opacity)
            }
            .background(Color.q.bg)
            .animation(Motion.adaptive(Motion.fade), value: doc)
            .navigationTitle(doc.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button(t("common.done")) { dismiss() } }
            }
        }
    }
}

/// One bundled page in a web view, restyled to match the app.
private struct LegalPage: UIViewRepresentable {
    let doc: LegalDoc

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let english = L10n.current == .en
        // Keep one language half, drop the site's top links, and use the app's faces.
        let js = """
        (function() {
          var hr = document.getElementById('en');
          if (hr) {
            var main = hr.parentNode, kids = Array.prototype.slice.call(main.children), i = kids.indexOf(hr);
            kids.forEach(function(el, j) { if (\(english ? "j <= i" : "j >= i")) el.remove(); });
          }
          var nav = document.querySelector('nav'); if (nav) nav.remove();
          var s = document.createElement('style');
          s.textContent = 'body{font:17px/1.6 Manrope,-apple-system,sans-serif;font-weight:500;-webkit-text-size-adjust:100%}' +
            'h1{font-family:Unbounded,-apple-system,sans-serif;font-weight:700;font-size:24px;line-height:1.3}' +
            'h2{font-weight:800;font-size:18px}main{padding:8px 16px 48px}';
          document.head.appendChild(s);
        })();
        """
        config.userContentController.addUserScript(WKUserScript(source: js, injectionTime: .atDocumentEnd, forMainFrameOnly: true))
        let view = WKWebView(frame: .zero, configuration: config)
        view.isOpaque = false
        view.backgroundColor = .clear
        view.scrollView.backgroundColor = .clear
        view.navigationDelegate = context.coordinator
        if let file = doc.file { view.loadFileURL(file, allowingReadAccessTo: file.deletingLastPathComponent()) }
        return view
    }

    func updateUIView(_ view: WKWebView, context: Context) {}

    /// The bundled page itself loads; any other link (mail, the website) leaves the app.
    final class Coordinator: NSObject, WKNavigationDelegate {
        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction) async -> WKNavigationActionPolicy {
            guard let url = action.request.url else { return .cancel }
            if url.isFileURL { return .allow }
            await UIApplication.shared.open(url)
            return .cancel
        }
    }
}
