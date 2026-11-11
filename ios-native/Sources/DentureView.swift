import SwiftUI
import WebKit

/* El render 3D EXACTO de la web (three.js + dentadura.glb + denture.js) dentro
   de un WKWebView. Se sirve por un esquema propio (app://) porque los módulos
   ES y el fetch del GLB no funcionan sobre file://. */
final class LocalSchemeHandler: NSObject, WKURLSchemeHandler {
    private let root: URL
    init(root: URL) { self.root = root }

    func webView(_ webView: WKWebView, start task: WKURLSchemeTask) {
        guard let url = task.request.url else {
            task.didFailWithError(URLError(.badURL)); return
        }
        var path = url.path
        if path.hasPrefix("/") { path.removeFirst() }
        if path.isEmpty { path = "denture.html" }
        let file = root.appendingPathComponent(path)
        let mime: String
        switch (file.pathExtension as NSString).lowercased {
        case "html": mime = "text/html"
        case "js":   mime = "text/javascript"
        case "css":  mime = "text/css"
        case "glb":  mime = "model/gltf-binary"
        case "png":  mime = "image/png"
        case "jpg", "jpeg": mime = "image/jpeg"
        default:     mime = "application/octet-stream"
        }
        guard let data = try? Data(contentsOf: file) else {
            task.didFailWithError(URLError(.fileDoesNotExist)); return
        }
        let resp = URLResponse(url: url, mimeType: mime, expectedContentLength: data.count, textEncodingName: nil)
        task.didReceive(resp)
        task.didReceive(data)
        task.didFinish()
    }

    func webView(_ webView: WKWebView, stop task: WKURLSchemeTask) {}
}

struct DentureView: UIViewRepresentable {
    var classes: [ZoneClass]?

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let root = Bundle.main.resourceURL!.appendingPathComponent("web")
        context.coordinator.root = root
        config.setURLSchemeHandler(LocalSchemeHandler(root: root), forURLScheme: "app")
        let wv = WKWebView(frame: .zero, configuration: config)
        wv.isOpaque = false
        wv.backgroundColor = .clear
        wv.scrollView.isScrollEnabled = false
        wv.scrollView.backgroundColor = .clear
        wv.navigationDelegate = context.coordinator
        wv.load(URLRequest(url: URL(string: "app://local/denture.html")!))
        context.coordinator.webView = wv
        return wv
    }

    func updateUIView(_ wv: WKWebView, context: Context) {
        context.coordinator.apply(classes: classes)
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        weak var webView: WKWebView?
        var root: URL?
        var loaded = false
        var pending: [ZoneClass]??

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            loaded = true
            if let p = pending { apply(classes: p); pending = nil }
        }

        func apply(classes: [ZoneClass]?) {
            guard loaded, let wv = webView else { pending = classes; return }
            let arr = (classes ?? Array(repeating: .none, count: 8)).map { "\"\($0.rawValue)\"" }.joined(separator: ",")
            wv.evaluateJavaScript("window.setZones && window.setZones([\(arr)]);", completionHandler: nil)
        }
    }
}
