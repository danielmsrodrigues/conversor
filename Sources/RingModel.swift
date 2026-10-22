import AppKit
import SwiftUI

/// Estado do anel: que ficheiros, que formatos, em que fase está.
@MainActor
final class RingModel: ObservableObject {
    enum Phase: Equatable {
        case picking
        case working(Format)
        case done([URL], failures: [String])
        case failed(String)
    }

    @Published private(set) var files: [URL] = []
    @Published private(set) var kind: FileKind?
    @Published private(set) var targets: [Format] = []
    @Published private(set) var phase: Phase = .picking
    @Published var open = false
    @Published var hovered: Format?

    /// Pedido para fechar o anel (o controlador trata da janela).
    var onDismiss: () -> Void = {}

    var isWorking: Bool { if case .working = phase { true } else { false } }

    func load(_ urls: [URL]) {
        let urls = urls.filter { url in
            var isDir: ObjCBool = false
            return url.isFileURL && FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) && !isDir.boolValue
        }
        hovered = nil
        open = false
        guard let first = urls.first else {
            files = []; kind = nil; targets = []
            phase = .failed(String(localized: "Choose a file (folders don’t work)."))
            return
        }
        guard let kind = FileKind.detect(first) else {
            files = [first]; self.kind = nil; targets = []
            phase = .failed(first.pathExtension.isEmpty
                ? String(localized: "I can’t convert files without an extension yet.")
                : String(localized: "I can’t convert .\(first.pathExtension) files yet."))
            return
        }

        // Vários ficheiros de uma vez: fica com os do mesmo tipo que o primeiro.
        let same = urls.filter { FileKind.detect($0) == kind }
        let sourceExts = Set(same.map { Format.normalized($0.pathExtension) })
        files = same
        self.kind = kind
        targets = Format.targets(for: kind).filter { !(sourceExts.count == 1 && sourceExts.contains($0.ext)) }
        phase = .picking
    }

    func convert(to format: Format) {
        guard let kind, !files.isEmpty, !isWorking else { return }
        let files = files
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            open = false
            hovered = nil
            phase = .working(format)
        }
        Task {
            let started = ContinuousClock.now
            var outputs: [URL] = []
            var failures: [String] = []
            for file in files {
                do {
                    outputs.append(try await Converter.convert(file, kind: kind, to: format))
                } catch {
                    failures.append(files.count == 1 ? error.localizedDescription : "\(file.lastPathComponent): \(error.localizedDescription)")
                }
            }
            let result: Phase = outputs.isEmpty
                ? .failed(failures.joined(separator: "\n"))
                : .done(outputs, failures: failures)
            // Deixa as bolhas acabarem de recolher antes de mostrar o resultado.
            try? await Task.sleep(until: started + .milliseconds(380))
            withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) { phase = result }

            // Fecha sozinho; os erros ficam mais tempo para dar para ler.
            let wait: Duration = failures.isEmpty ? .milliseconds(1400) : .seconds(5)
            try? await Task.sleep(for: wait)
            if phase == result { onDismiss() }
        }
    }

    func reveal() {
        if case .done(let outputs, _) = phase { NSWorkspace.shared.activateFileViewerSelecting(outputs) }
        onDismiss()
    }
}
