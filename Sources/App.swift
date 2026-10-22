import AppKit
import ServiceManagement

/// App sem janela nem ícone no Dock: só aparece o anel quando é chamada.
@main
enum ConversorMain {
    static func main() {
        MainActor.assumeIsolated {
            let app = NSApplication.shared
            let delegate = AppDelegate()
            app.delegate = delegate
            app.setActivationPolicy(.accessory)
            app.run()
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let services = ServiceProvider()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Usado pelo desinstalador: sai dos itens de início e fecha.
        if CommandLine.arguments.contains("--unregister") {
            try? SMAppService.mainApp.unregister()
            UserDefaults.standard.removeObject(forKey: "didRegisterLoginItem")
            NSApp.terminate(nil)
            return
        }
        NSApp.servicesProvider = services
        NSUpdateDynamicServices()
        RingController.shared.trackContextClicks()
        RingController.shared.warmUp()
        registerLoginItemOnce()
        // Ao iniciar sessão (ou com --background) fica só à espera, sem perguntar nada.
        // Aberta à mão no Finder/Dock = evento "open application"; o arranque de sessão não o traz.
        let event = NSAppleEventManager.shared().currentAppleEvent
        let openedByHand = event?.eventID == kAEOpenApplication
            && event?.paramDescriptor(forKeyword: keyAEPropData)?.enumCodeValue != keyAELaunchedAsLogInItem
        if !openedByHand || CommandLine.arguments.contains("--background") { return }
        // Se ninguém pediu nada logo a seguir ao arranque, foi aberta à mão.
        Task {
            try? await Task.sleep(for: .milliseconds(800))
            if !RingController.shared.hasShown { RingController.shared.pickFiles() }
        }
    }

    /// Arranca com o Mac, para saber sempre onde foi o clique direito.
    /// Só se pede uma vez: se o desligares em Definições → Geral → Itens de início, fica desligado.
    private func registerLoginItemOnce() {
        let key = "didRegisterLoginItem"
        guard !UserDefaults.standard.bool(forKey: key), Bundle.main.bundlePath.contains("/Applications/") else { return }
        do {
            try SMAppService.mainApp.register()
            UserDefaults.standard.set(true, forKey: key)
        } catch {
            NSLog("Conversor: não foi possível ficar nos itens de início: \(error)")
        }
    }

    /// "Abrir com → Conversor" no Finder.
    func application(_ application: NSApplication, open urls: [URL]) {
        RingController.shared.show(urls)
    }

    /// Duplo clique na app quando já está a correr.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        RingController.shared.pickFiles()
        return false
    }
}

/// Botão direito num ficheiro no Finder → "Converter para…".
final class ServiceProvider: NSObject {
    @objc func convertFiles(_ pasteboard: NSPasteboard, userData: String?, error: AutoreleasingUnsafeMutablePointer<NSString?>) {
        let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        MainActor.assumeIsolated { RingController.shared.show(urls) }
    }
}
