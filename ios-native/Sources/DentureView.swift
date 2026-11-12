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
    var onRot: ((String) -> Void)?   // "rotY/rotX/zoom" mientras se gira
    var onLock: ((String) -> Void)?  // "1"/"0": bloquear el scroll durante el arrastre
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
        if path.hasPrefix("__rot/") {
            let s = String(path.dropFirst("__rot/".count))
            let cb = onRot
            DispatchQueue.main.async { cb?(s) }
            let resp = URLResponse(url: url, mimeType: "text/plain", expectedContentLength: 0, textEncodingName: nil)
            task.didReceive(resp)
            task.didReceive(Data())
            task.didFinish()
            return
        }
        if path.hasPrefix("__lock/") {
            let s = String(path.dropFirst("__lock/".count))
            let cb = onLock
            DispatchQueue.main.async { cb?(s) }
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

/* Estado del render 3D. Los gestos (arrastrar, pellizcar, doble toque) los
   procesa el propio JS con pointer events, como en la web: conducirlos desde
   SwiftUI con evaluateJavaScript por frame hacia que el render fuera a golpes
   en el iPhone real. El JS reporta aqui su estado por el canal fetch
   (__rot/__lock) para las pruebas de UI y para bloquear el scroll. */
final class DentureController: ObservableObject {
    weak var webView: WKWebView?
    @Published private(set) var a11y = "rotY 0.00 rotX 0.00 zoom 1.00"
    @Published var zonesState = "?" // clases con las que el JS montó el render por última vez

    func resetA11y() {
        a11y = "rotY 0.00 rotX 0.00 zoom 1.00"
        webView?.accessibilityValue = a11y
    }

    // "rotY/rotX/zoom" ya formateado por el JS con 2 decimales
    func reportRot(_ s: String) {
        let p = s.split(separator: "/")
        guard p.count == 3 else { return }
        a11y = "rotY \(p[0]) rotX \(p[1]) zoom \(p[2])"
        webView?.accessibilityValue = a11y
    }
}

/* Bloqueo del ScrollView de Hoy mientras se arrastra el 3D. */
final class ScrollLock: ObservableObject {
    @Published var locked = false
}

struct DentureView: View {
    var classes: [ZoneClass]?
    var scrollLock: ScrollLock? = nil
    // @StateObject para que el controller sobreviva a las recomputaciones de la vista
    @StateObject private var controller = DentureController()

    var body: some View {
        ZStack {
            DentureWebView(classes: classes, controller: controller, scrollLock: scrollLock)
            // Estado del gesto visible solo para las pruebas de UI (1px, transparente)
            Text(controller.a11y + " z=" + controller.zonesState)
                .font(.system(size: 1))
                .foregroundColor(.clear)
                .allowsHitTesting(false)
                .accessibilityIdentifier("rot-state")
        }
            .contentShape(Rectangle())
    }
}

private struct DentureWebView: UIViewRepresentable {
    var classes: [ZoneClass]?
    let controller: DentureController
    var scrollLock: ScrollLock? = nil

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let root = Bundle.main.resourceURL!.appendingPathComponent("web")
        let handler = LocalSchemeHandler(root: root)
        handler.onZones = { [weak controller] s in
            controller?.zonesState = s
        }
        handler.onRot = { [weak controller] s in
            controller?.reportRot(s)
        }
        handler.onLock = { [weak scrollLock] s in
            scrollLock?.locked = (s == "1")
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
        // ?diag=1 solo en simulador: la página escribe en una esquina lo que
        // montó, para verificarlo en las capturas. En el iPhone de Adrián no
        // aparece nada.
        #if targetEnvironment(simulator)
        wv.load(URLRequest(url: URL(string: "app://local/denture.html?diag=1")!))
        #else
        wv.load(URLRequest(url: URL(string: "app://local/denture.html")!))
        #endif
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
        private var lastArr: String?

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            if message.name == "zones", let s = message.body as? String {
                DispatchQueue.main.async { self.controller?.zonesState = s }
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            // Página nueva: hay que reaplicar aunque las clases no hayan cambiado
            let arr = lastArr
            lastArr = nil
            if let arr { send(arr, attempt: 0) }
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
            let arr = (classes ?? Array(repeating: .none, count: 8)).map { "\"\($0.rawValue)\"" }.joined(separator: ",")
            guard arr != lastArr else { return } // mismo estado: no repintar (el recoloreado es barato pero innecesario)
            lastArr = arr
            send(arr, attempt: 0)
        }

        /* evaluateJavaScript devuelve 0 si window.setZones aún no existe (la
           página no ha parseado el script clásico) o falla mientras la página
           carga: reintenta durante 2 minutos. Con 20 intentos (10s) se agotaba
           antes de tiempo cuando el simulador de CI va lento y las clases
           reales no llegaban nunca. */
        private func send(_ arr: String, attempt: Int) {
            guard let wv = webView else { return }
            wv.evaluateJavaScript("window.setZones ? (window.setZones([\(arr)]), 1) : 0") { [weak self] res, _ in
                guard let self else { return }
                if let n = res as? Int, n == 1 { return }
                if attempt < 240 {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { self.send(arr, attempt: attempt + 1) }
                }
            }
        }
    }
}
