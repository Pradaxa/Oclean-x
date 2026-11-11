import SwiftUI
import WebKit

/* El render 3D EXACTO de la web (three.js + dentadura.glb + denture.js) dentro
   de un WKWebView. Se sirve por un esquema propio (app://) porque los módulos
   ES y el fetch del GLB no funcionan sobre file://. */
final class LocalSchemeHandler: NSObject, WKURLSchemeHandler {
    private let root: URL
    // Canal JS->nativo por fetch: window.webkit.messageHandlers no es fiable
    // en paginas servidas por esquema propio; un fetch a app://local/__zones/...
    // siempre llega aqui.
    var onZones: ((String) -> Void)?
    init(root: URL) { self.root = root }

    func webView(_ webView: WKWebView, start task: WKURLSchemeTask) {
        guard let url = task.request.url else {
            task.didFailWithError(URLError(.badURL)); return
        }
        var path = url.path
        if path.hasPrefix("/") { path.removeFirst() }
        if path.hasPrefix("__zones/") {
            let cls = String(path.dropFirst("__zones/".count))
            let cb = onZones
            DispatchQueue.main.async { cb?(cls) }
            let resp = URLResponse(url: url, mimeType: "text/plain", expectedContentLength: 0, textEncodingName: nil)
            task.didReceive(resp)
            task.didReceive(Data())
            task.didFinish()
            return
        }
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

/* Control nativo del render: los gestos (arrastrar, pellizcar, doble toque) se
   capturan en SwiftUI y se mandan al JS, que es quien dibuja. Los pointer events
   del WKWebView se desactivan (disablePointerDrag) para no rotar dos veces.
   El estado se expone en accessibilityValue para las pruebas de UI. */
final class DentureController: ObservableObject {
    weak var webView: WKWebView?
    @Published private(set) var a11y = "rotY 0.00 rotX 0.00 zoom 1.00"
    @Published var zonesState = "?" // clases con las que el JS montó el render por última vez
    private var rotY: Double = 0
    private var rotX: Double = 0
    private var zoom: Double = 1

    private func updateA11y() {
        a11y = String(format: "rotY %.2f rotX %.2f zoom %.2f", rotY, rotX, zoom)
        webView?.accessibilityValue = a11y
    }

    func resetA11y() {
        rotY = 0; rotX = 0; zoom = 1
        updateA11y()
    }

    func dragBy(dx: Double, dy: Double) {
        rotY += dx * 0.011
        rotX = max(-0.85, min(0.85, rotX + dy * 0.007))
        webView?.evaluateJavaScript("window.dragRot && window.dragRot(\(dx),\(dy));", completionHandler: nil)
        updateA11y()
    }

    func pinchBy(_ factor: Double) {
        zoom = max(0.5, min(3, zoom * factor))
        webView?.evaluateJavaScript("window.pinchZoom && window.pinchZoom(\(factor));", completionHandler: nil)
        updateA11y()
    }

    func resetView() {
        resetA11y()
        webView?.evaluateJavaScript("window.resetRot && window.resetRot();", completionHandler: nil)
    }
}

struct DentureView: View {
    var classes: [ZoneClass]?
    // @StateObject para que el controller sobreviva a las recomputaciones de la vista
    @StateObject private var controller = DentureController()
    @State private var lastDrag: CGSize = .zero
    @State private var lastPinch: CGFloat = 1

    var body: some View {
        ZStack {
            DentureWebView(classes: classes, controller: controller)
            // Estado del gesto visible solo para las pruebas de UI (1px, transparente)
            Text(controller.a11y + " z=" + controller.zonesState)
                .font(.system(size: 1))
                .foregroundColor(.clear)
                .allowsHitTesting(false)
                .accessibilityIdentifier("rot-state")
        }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .local)
                    .onChanged { v in
                        let dx = v.translation.width - lastDrag.width
                        let dy = v.translation.height - lastDrag.height
                        lastDrag = v.translation
                        if dx != 0 || dy != 0 { controller.dragBy(dx: dx, dy: dy) }
                    }
                    .onEnded { _ in lastDrag = .zero }
                    .simultaneously(with:
                        MagnificationGesture()
                            .onChanged { m in
                                let f = m / lastPinch
                                lastPinch = m
                                if f != 1 { controller.pinchBy(Double(f)) }
                            }
                            .onEnded { _ in lastPinch = 1 }
                    )
            )
            // Doble toque: volver a la posición inicial (como el doble clic de la web)
            .simultaneousGesture(TapGesture(count: 2).onEnded { controller.resetView() })
    }
}

private struct DentureWebView: UIViewRepresentable {
    var classes: [ZoneClass]?
    let controller: DentureController

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let root = Bundle.main.resourceURL!.appendingPathComponent("web")
        let handler = LocalSchemeHandler(root: root)
        handler.onZones = { [weak controller] s in
            controller?.zonesState = s
        }
        config.setURLSchemeHandler(handler, forURLScheme: "app")
        config.userContentController.add(context.coordinator, name: "zones")
        context.coordinator.controller = controller
        let wv = WKWebView(frame: .zero, configuration: config)
        wv.isOpaque = false
        wv.backgroundColor = .clear
        wv.scrollView.isScrollEnabled = false
        wv.scrollView.backgroundColor = .clear
        wv.navigationDelegate = context.coordinator
        wv.accessibilityIdentifier = "denture-3d"
        wv.load(URLRequest(url: URL(string: "app://local/denture.html")!))
        context.coordinator.webView = wv
        controller.webView = wv
        controller.resetA11y()
        return wv
    }

    func updateUIView(_ wv: WKWebView, context: Context) {
        context.coordinator.apply(classes: classes)
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        weak var webView: WKWebView?
        weak var controller: DentureController?
        var loaded = false
        var pending: [ZoneClass]??
        private var lastArr: String?

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            if message.name == "zones", let s = message.body as? String {
                DispatchQueue.main.async { self.controller?.zonesState = s }
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            loaded = true
            lastArr = nil // página nueva: hay que reaplicar aunque las clases no hayan cambiado
            if let p = pending { apply(classes: p); pending = nil }
        }

        private func showError(_ webView: WKWebView, _ msg: String) {
            let html = "<html><body style=\"background:transparent;color:#e0455a;font:13px -apple-system;padding:12px\">3D no cargó: \(msg)</body></html>"
            webView.loadHTMLString(html, baseURL: nil)
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            showError(webView, error.localizedDescription)
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            showError(webView, error.localizedDescription)
        }

        func apply(classes: [ZoneClass]?) {
            guard loaded, let wv = webView else { pending = classes; return }
            let arr = (classes ?? Array(repeating: .none, count: 8)).map { "\"\($0.rawValue)\"" }.joined(separator: ",")
            guard arr != lastArr else { return } // no remontar el 3D si nada cambió (mata un arrastre en curso)
            lastArr = arr
            wv.evaluateJavaScript("window.setZones && window.setZones([\(arr)]);", completionHandler: nil)
        }
    }
}
