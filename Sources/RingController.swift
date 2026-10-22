import AppKit
import SwiftUI

/// Janela sem moldura nem fundo, por cima de tudo, onde vive o anel.
final class RingPanel: NSPanel {
    init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: RingView.size, height: RingView.size),
                   styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .popUpMenu
        isMovable = false
        hidesOnDeactivate = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
    }

    override var canBecomeKey: Bool { true }
}

/// Mostra o anel no sítio do cursor e fecha-o quando se clica fora ou se carrega em Esc.
@MainActor
final class RingController {
    static let shared = RingController()

    private(set) var hasShown = false
    private let model = RingModel()
    private lazy var panel: RingPanel = {
        let panel = RingPanel()
        panel.contentView = NSHostingView(rootView: RingView(model: model))
        return panel
    }()
    private var monitors: [Any] = []
    private var visible = false
    /// Onde foi o último clique direito: é aí que está o ficheiro, não no fundo do menu.
    private var lastContextClick: (point: NSPoint, time: Date)?

    private init() {
        model.onDismiss = { [weak self] in self?.dismiss() }
    }

    /// Cria a janela já no arranque, para o primeiro círculo abrir sem atraso.
    func warmUp() {
        _ = panel
    }

    /// Fica sempre à escuta de cliques direitos (e ctrl+clique) noutras apps.
    /// Só lê a posição do rato; cliques não precisam de permissões de Acessibilidade.
    func trackContextClicks() {
        NSEvent.addGlobalMonitorForEvents(matching: [.rightMouseDown, .leftMouseDown]) { event in
            guard event.type == .rightMouseDown || event.modifierFlags.contains(.control) else { return }
            let point = NSEvent.mouseLocation
            MainActor.assumeIsolated { RingController.shared.lastContextClick = (point, Date()) }
        }
    }

    func show(_ urls: [URL]) {
        hasShown = true
        model.load(urls)
        present()
    }

    /// Aberta à mão (sem ficheiro): pergunta qual é.
    func pickFiles() {
        hasShown = true
        NSApp.activate()
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.message = String(localized: "Choose the file to convert. Tip: in Finder, right-click a file → Convert to…")
        panel.prompt = String(localized: "Convert")
        guard panel.runModal() == .OK, !panel.urls.isEmpty else { return }
        show(panel.urls)
    }

    private func present() {
        let size = RingView.size
        // Centra no ficheiro onde se fez o clique direito há pouco; senão, no cursor.
        var anchor = NSEvent.mouseLocation
        if let click = lastContextClick, Date().timeIntervalSince(click.time) < 20 {
            anchor = click.point
        }
        lastContextClick = nil
        var frame = NSRect(x: anchor.x - size / 2, y: anchor.y - size / 2, width: size, height: size)
        if let screen = NSScreen.screens.first(where: { NSMouseInRect(anchor, $0.frame, false) }) ?? NSScreen.main {
            let bounds = screen.visibleFrame
            frame.origin.x = min(max(frame.minX, bounds.minX), bounds.maxX - size)
            frame.origin.y = min(max(frame.minY, bounds.minY), bounds.maxY - size)
        }
        panel.setFrame(frame, display: false)
        panel.alphaValue = 1
        // Painel "não ativante": recebe o Esc sem tirar o Finder da frente, como o Spotlight.
        panel.makeKeyAndOrderFront(nil)
        visible = true
        installMonitors()

        Task {
            try? await Task.sleep(for: .milliseconds(30))
            if model.phase == .picking { model.open = true }
        }
    }

    func dismiss() {
        guard visible else { return }
        visible = false
        removeMonitors()
        model.open = false
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.18
            panel.animator().alphaValue = 0
        }, completionHandler: {
            MainActor.assumeIsolated {
                guard !self.visible else { return }
                self.panel.orderOut(nil)
            }
        })
    }

    private func installMonitors() {
        removeMonitors()
        // Clique noutra app (ou no ambiente de trabalho).
        if let global = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown], handler: { _ in
            MainActor.assumeIsolated { RingController.shared.dismiss() }
        }) { monitors.append(global) }
        // Esc fecha.
        if let local = NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: { event in
            guard event.keyCode == 53 else { return event }
            MainActor.assumeIsolated { RingController.shared.dismiss() }
            return nil
        }) { monitors.append(local) }
    }

    private func removeMonitors() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors.removeAll()
    }
}
