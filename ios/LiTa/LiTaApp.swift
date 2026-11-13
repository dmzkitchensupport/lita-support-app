import SwiftUI
import WebKit

// LiTa Support · contenedor iOS.
// Abre el acceso único (app.litasupport.com) y deja navegar solo a los dominios de LiTa y
// de los portales de cliente (WKAppBoundDomains en Info.plist). Cualquier otro enlace
// (correo, teléfono, sitios externos) se abre fuera de la app.

let inicioURL = URL(string: "https://app.litasupport.com/index.html")!
let dominiosPropios: Set<String> = [
    "app.litasupport.com", "litasupport.com",
    "vitality-control.github.io", "cdjsupport.github.io",
]

@main
struct LiTaApp: App {
    var body: some Scene {
        WindowGroup {
            PantallaPrincipal()
                .ignoresSafeArea(.container, edges: .bottom)
                .background(Color(red: 0x15 / 255, green: 0x18 / 255, blue: 0x1A / 255).ignoresSafeArea())
        }
    }
}

final class EstadoWeb: ObservableObject {
    @Published var sinConexion = false
    @Published var cargando = true
    weak var webView: WKWebView?

    func reintentar() {
        sinConexion = false
        cargando = true
        if let wv = webView {
            if wv.url == nil { wv.load(URLRequest(url: inicioURL)) } else { wv.reload() }
        }
    }
}

struct PantallaPrincipal: View {
    @StateObject private var estado = EstadoWeb()

    var body: some View {
        ZStack {
            VistaWeb(estado: estado)
            if estado.sinConexion {
                VistaSinConexion { estado.reintentar() }
            } else if estado.cargando {
                ProgressView().tint(Color(red: 0xC6 / 255, green: 0x8A / 255, blue: 0x3D / 255))
            }
        }
    }
}

struct VistaSinConexion: View {
    let reintentar: () -> Void
    private let tinta = Color(red: 0x15 / 255, green: 0x18 / 255, blue: 0x1A / 255)
    private let ocre = Color(red: 0xC6 / 255, green: 0x8A / 255, blue: 0x3D / 255)

    var body: some View {
        VStack(spacing: 18) {
            Text("Sin conexión")
                .font(.system(size: 24, weight: .semibold))
                .foregroundColor(.white)
            Text("LiTa Support necesita internet para cargar tu portal. Revisa tu Wi-Fi o datos y vuelve a intentar.")
                .font(.system(size: 16))
                .foregroundColor(.white.opacity(0.75))
                .multilineTextAlignment(.center)
            Button(action: reintentar) {
                Text("Reintentar")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(tinta)
                    .frame(maxWidth: .infinity, minHeight: 54)
                    .background(ocre)
                    .cornerRadius(14)
            }
        }
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(tinta.ignoresSafeArea())
    }
}

struct VistaWeb: UIViewRepresentable {
    @ObservedObject var estado: EstadoWeb

    func makeCoordinator() -> Coordinador { Coordinador(estado: estado) }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.limitsNavigationsToAppBoundDomains = true
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        config.websiteDataStore = .default()

        let wv = WKWebView(frame: .zero, configuration: config)
        wv.navigationDelegate = context.coordinator
        wv.uiDelegate = context.coordinator
        wv.allowsBackForwardNavigationGestures = true
        wv.isOpaque = false
        wv.backgroundColor = UIColor(red: 0x15 / 255, green: 0x18 / 255, blue: 0x1A / 255, alpha: 1)
        wv.scrollView.contentInsetAdjustmentBehavior = .automatic

        let refresco = UIRefreshControl()
        refresco.addTarget(context.coordinator, action: #selector(Coordinador.recargar(_:)), for: .valueChanged)
        wv.scrollView.refreshControl = refresco

        estado.webView = wv
        wv.load(URLRequest(url: inicioURL))
        return wv
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    final class Coordinador: NSObject, WKNavigationDelegate, WKUIDelegate {
        let estado: EstadoWeb
        init(estado: EstadoWeb) { self.estado = estado }

        @objc func recargar(_ sender: UIRefreshControl) {
            estado.webView?.reload()
            sender.endRefreshing()
        }

        private func esPropio(_ url: URL) -> Bool {
            guard let host = url.host?.lowercased() else { return false }
            return dominiosPropios.contains(host)
        }

        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard let url = action.request.url else { return decisionHandler(.cancel) }
            let esquema = url.scheme?.lowercased() ?? ""
            if esquema == "about" || esquema == "blob" || esquema == "data" {
                return decisionHandler(.allow)
            }
            if (esquema == "https" && esPropio(url)) {
                return decisionHandler(.allow)
            }
            // Correo, teléfono, WhatsApp y sitios externos: fuera de la app.
            UIApplication.shared.open(url)
            decisionHandler(.cancel)
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            DispatchQueue.main.async { self.estado.cargando = true }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            DispatchQueue.main.async {
                self.estado.cargando = false
                self.estado.sinConexion = false
            }
        }

        private func manejarError(_ error: Error) {
            let e = error as NSError
            if e.domain == NSURLErrorDomain && e.code == NSURLErrorCancelled { return }
            if e.domain == "WebKitErrorDomain" && e.code == 102 { return } // navegación cancelada por política
            DispatchQueue.main.async {
                self.estado.cargando = false
                self.estado.sinConexion = true
            }
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            manejarError(error)
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            manejarError(error)
        }

        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
            webView.reload()
        }

        // target="_blank": abrir en la misma vista si es propio, fuera si no.
        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                     for action: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
            if let url = action.request.url {
                if esPropio(url) { webView.load(action.request) } else { UIApplication.shared.open(url) }
            }
            return nil
        }

        // Cámara y micrófono para la evidencia: el sistema ya pidió permiso con los textos del Info.plist.
        func webView(_ webView: WKWebView, requestMediaCapturePermissionFor origin: WKSecurityOrigin,
                     initiatedByFrame frame: WKFrameInfo, type: WKMediaCaptureType,
                     decisionHandler: @escaping (WKPermissionDecision) -> Void) {
            decisionHandler(dominiosPropios.contains(origin.host.lowercased()) ? .grant : .deny)
        }

        func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String,
                     initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
            let a = UIAlertController(title: nil, message: message, preferredStyle: .alert)
            a.addAction(UIAlertAction(title: "Aceptar", style: .default) { _ in completionHandler() })
            presentar(a, o: completionHandler)
        }

        func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String,
                     initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
            let a = UIAlertController(title: nil, message: message, preferredStyle: .alert)
            a.addAction(UIAlertAction(title: "Cancelar", style: .cancel) { _ in completionHandler(false) })
            a.addAction(UIAlertAction(title: "Aceptar", style: .default) { _ in completionHandler(true) })
            presentar(a) { completionHandler(false) }
        }

        private func presentar(_ a: UIAlertController, o fallback: @escaping () -> Void) {
            guard let raiz = UIApplication.shared.connectedScenes
                .compactMap({ ($0 as? UIWindowScene)?.keyWindow?.rootViewController }).first else {
                return fallback()
            }
            var arriba = raiz
            while let p = arriba.presentedViewController { arriba = p }
            arriba.present(a, animated: true)
        }
    }
}
