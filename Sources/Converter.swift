import AppKit
import AVFoundation
import ImageIO
import PDFKit
import UniformTypeIdentifiers

enum ConversionError: LocalizedError {
    case unreadable
    case locked
    case unsupported
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .unreadable: String(localized: "Couldn’t open the file.")
        case .locked: String(localized: "The PDF is password protected.")
        case .unsupported: String(localized: "This conversion isn’t supported for this file.")
        case .failed(let detail): detail.isEmpty ? String(localized: "The conversion failed.") : String(localized: "The conversion failed: \(detail)")
        }
    }
}

/// Faz as conversões só com o que vem no macOS (AppKit, ImageIO, PDFKit, AVFoundation, afconvert).
enum Converter {

    /// Converte `input` para `format` e devolve o ficheiro (ou pasta) criado ao lado do original.
    static func convert(_ input: URL, kind: FileKind, to format: Format) async throws -> URL {
        switch kind {
        case .text:  return try await MainActor.run { try convertText(input, to: format) }
        case .image: return try convertImage(input, to: format)
        case .pdf:   return try await convertPDF(input, to: format)
        case .audio: return try await convertAudio(input, to: format)
        case .video: return try await convertVideo(input, to: format)
        }
    }

    // MARK: - Documentos

    @MainActor
    private static func convertText(_ input: URL, to format: Format) throws -> URL {
        let text = try readAttributedText(input)
        return try writeText(text, besides: input, as: format)
    }

    @MainActor
    private static func readAttributedText(_ url: URL) throws -> NSAttributedString {
        let type = UTType(filenameExtension: url.pathExtension)
        let isPlain = type.map { $0.conforms(to: .plainText) } ?? false
        if isPlain {
            var encoding = String.Encoding.utf8
            let string = (try? String(contentsOf: url, usedEncoding: &encoding))
                ?? (try? String(contentsOf: url, encoding: .isoLatin1))
            guard let string else { throw ConversionError.unreadable }
            return NSAttributedString(string: string, attributes: [
                // Uma fonte com nome real: a do sistema vira Times no Word.
                .font: NSFont(name: "Helvetica Neue", size: 12) ?? NSFont.systemFont(ofSize: 12),
                .foregroundColor: NSColor.black,
            ])
        }
        do {
            return try NSAttributedString(url: url, options: [:], documentAttributes: nil)
        } catch {
            throw ConversionError.unreadable
        }
    }

    @MainActor
    private static func writeText(_ text: NSAttributedString, besides input: URL, as format: Format) throws -> URL {
        let out = destination(besides: input, ext: format.ext)
        let range = NSRange(location: 0, length: text.length)
        do {
            switch format.ext {
            case "txt":
                try text.string.write(to: out, atomically: true, encoding: .utf8)
            case "pdf":
                try printToPDF(text, to: out)
            default:
                let type: NSAttributedString.DocumentType = switch format.ext {
                case "docx": .officeOpenXML
                case "doc":  .docFormat
                case "odt":  .openDocument
                case "html": .html
                case "rtf":  .rtf
                default: throw ConversionError.unsupported
                }
                let data = try text.data(from: range, documentAttributes: [.documentType: type])
                try data.write(to: out)
            }
        } catch let error as ConversionError {
            try? FileManager.default.removeItem(at: out)
            throw error
        } catch {
            try? FileManager.default.removeItem(at: out)
            throw ConversionError.failed(error.localizedDescription)
        }
        return out
    }

    /// Paginação em A4 através do motor de impressão do macOS.
    @MainActor
    private static func printToPDF(_ text: NSAttributedString, to url: URL) throws {
        let info = (NSPrintInfo.shared.copy() as? NSPrintInfo) ?? NSPrintInfo()
        info.paperSize = NSSize(width: 595, height: 842)
        info.topMargin = 56; info.bottomMargin = 56
        info.leftMargin = 56; info.rightMargin = 56
        info.horizontalPagination = .fit
        info.verticalPagination = .automatic
        info.isHorizontallyCentered = false
        info.isVerticallyCentered = false
        info.jobDisposition = .save
        info.dictionary()[NSPrintInfo.AttributeKey.jobSavingURL] = url

        // Texto sem cor definida ficaria branco num Mac em modo escuro.
        let page = NSMutableAttributedString(attributedString: text)
        page.enumerateAttribute(.foregroundColor, in: NSRange(location: 0, length: page.length)) { value, range, _ in
            if value == nil { page.addAttribute(.foregroundColor, value: NSColor.black, range: range) }
        }

        let width = info.paperSize.width - info.leftMargin - info.rightMargin
        let view = NSTextView(frame: NSRect(x: 0, y: 0, width: width, height: 100))
        view.appearance = NSAppearance(named: .aqua)
        view.drawsBackground = true
        view.backgroundColor = .white
        view.isVerticallyResizable = true
        view.isHorizontallyResizable = false
        view.textContainer?.widthTracksTextView = true
        view.textStorage?.setAttributedString(page)
        if let container = view.textContainer { view.layoutManager?.ensureLayout(for: container) }
        view.sizeToFit()

        let operation = NSPrintOperation(view: view, printInfo: info)
        operation.showsPrintPanel = false
        operation.showsProgressPanel = false
        guard operation.run(), FileManager.default.fileExists(atPath: url.path) else {
            throw ConversionError.failed(String(localized: "couldn’t create the PDF"))
        }
    }

    // MARK: - Imagens

    /// Lista pedida ao sistema uma só vez (não muda enquanto a app corre).
    private static let writableImageTypes = Set(CGImageDestinationCopyTypeIdentifiers() as? [String] ?? [])

    static func canWriteImage(_ ext: String) -> Bool {
        writableImageTypes.contains(imageType(for: ext).identifier)
    }

    private static func imageType(for ext: String) -> UTType {
        switch ext {
        case "jpg": .jpeg
        case "webp": .webP
        default: UTType(filenameExtension: ext) ?? .png
        }
    }

    private static func convertImage(_ input: URL, to format: Format) throws -> URL {
        if format.ext == "pdf" { return try imageToPDF(input) }

        guard let source = CGImageSourceCreateWithURL(input as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else { throw ConversionError.unreadable }
        // Mantém metadados (incluindo a orientação da foto).
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] ?? [:]

        let out = destination(besides: input, ext: format.ext)
        try writeImage(image, to: out, ext: format.ext, properties: properties)
        return out
    }

    private static func imageToPDF(_ input: URL) throws -> URL {
        guard let image = NSImage(contentsOf: input), image.size.width > 0 else { throw ConversionError.unreadable }
        // A4 ao alto ou deitado, conforme a imagem.
        let landscape = image.size.width > image.size.height
        let box = landscape ? CGRect(x: 0, y: 0, width: 842, height: 595) : CGRect(x: 0, y: 0, width: 595, height: 842)
        guard let page = PDFPage(image: image, options: [.mediaBox: box, .upscaleIfSmaller: true]) else {
            throw ConversionError.failed(String(localized: "couldn’t create the page"))
        }
        let document = PDFDocument()
        document.insert(page, at: 0)
        let out = destination(besides: input, ext: "pdf")
        guard document.write(to: out) else { throw ConversionError.failed(String(localized: "couldn’t save the PDF")) }
        return out
    }

    private static func writeImage(_ image: CGImage, to url: URL, ext: String, properties: [CFString: Any] = [:]) throws {
        var image = image
        // JPEG e BMP não têm transparência: põe fundo branco em vez de preto.
        if ["jpg", "bmp"].contains(ext), image.alphaInfo != .none, image.alphaInfo != .noneSkipLast, image.alphaInfo != .noneSkipFirst {
            image = flattened(image) ?? image
        }
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, imageType(for: ext).identifier as CFString, 1, nil) else {
            throw ConversionError.unsupported
        }
        var options = properties
        options[kCGImageDestinationLossyCompressionQuality] = 0.9
        CGImageDestinationAddImage(destination, image, options as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            try? FileManager.default.removeItem(at: url)
            throw ConversionError.failed(String(localized: "couldn’t save the image"))
        }
    }

    private static func flattened(_ image: CGImage) -> CGImage? {
        let rect = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        guard let context = whiteCanvas(width: image.width, height: image.height) else { return nil }
        context.draw(image, in: rect)
        return context.makeImage()
    }

    private static func whiteCanvas(width: Int, height: Int) -> CGContext? {
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
        else { return nil }
        context.setFillColor(.white)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return context
    }

    // MARK: - PDF

    private static func convertPDF(_ input: URL, to format: Format) async throws -> URL {
        guard let document = PDFDocument(url: input) else { throw ConversionError.unreadable }
        if document.isLocked { throw ConversionError.locked }

        switch format.ext {
        case "png", "jpg":
            return try pdfToImages(document, input: input, ext: format.ext)
        case "txt":
            let out = destination(besides: input, ext: "txt")
            try (document.string ?? "").write(to: out, atomically: true, encoding: .utf8)
            return out
        default:
            let text = NSMutableAttributedString()
            for index in 0..<document.pageCount {
                guard let page = document.page(at: index)?.attributedString else { continue }
                if text.length > 0 { text.append(NSAttributedString(string: "\n\n")) }
                text.append(page)
            }
            // Cópia imutável que só passa a ser usada no main thread.
            nonisolated(unsafe) let snapshot = NSAttributedString(attributedString: text)
            return try await MainActor.run { try writeText(snapshot, besides: input, as: format) }
        }
    }

    /// Uma imagem por página. Várias páginas vão para uma pasta própria.
    private static func pdfToImages(_ document: PDFDocument, input: URL, ext: String) throws -> URL {
        let base = input.deletingPathExtension().lastPathComponent
        let pages = document.pageCount
        guard pages > 0 else { throw ConversionError.unreadable }

        var folder: URL?
        if pages > 1 {
            let dir = destination(besides: input, ext: nil, suffix: String(localized: " (pages)"))
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: false)
            folder = dir
        }

        for index in 0..<pages {
            guard let page = document.page(at: index), let image = render(page, scale: 2) else { continue }
            let out = folder.map { $0.appendingPathComponent("\(base) \(index + 1)").appendingPathExtension(ext) }
                ?? destination(besides: input, ext: ext)
            try writeImage(image, to: out, ext: ext)
            if folder == nil { return out }
        }
        return folder!
    }

    private static func render(_ page: PDFPage, scale: CGFloat) -> CGImage? {
        var size = page.bounds(for: .mediaBox).size
        if page.rotation % 180 != 0 { size = CGSize(width: size.height, height: size.width) }
        let width = Int(size.width * scale), height = Int(size.height * scale)
        guard width > 0, height > 0, let context = whiteCanvas(width: width, height: height) else { return nil }
        context.scaleBy(x: scale, y: scale)
        // A thumbnail já trata da rotação da página.
        let thumbnail = page.thumbnail(of: size, for: .mediaBox)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        thumbnail.draw(in: CGRect(origin: .zero, size: size))
        NSGraphicsContext.restoreGraphicsState()
        return context.makeImage()
    }

    // MARK: - Áudio

    private static func convertAudio(_ input: URL, to format: Format) async throws -> URL {
        // AAC fica com o AVFoundation, que escolhe sozinho a qualidade certa para o ficheiro.
        if format.ext == "m4a" { return try await convertVideo(input, to: format) }
        let args: [String] = switch format.ext {
        case "wav":  ["-f", "WAVE", "-d", "LEI16"]
        case "aiff": ["-f", "AIFF", "-d", "BEI16"]
        case "flac": ["-f", "flac", "-d", "flac"]
        default: throw ConversionError.unsupported
        }
        let out = destination(besides: input, ext: format.ext)
        do {
            try await run("/usr/bin/afconvert", args + [input.path, out.path])
        } catch {
            try? FileManager.default.removeItem(at: out)
            throw error
        }
        return out
    }

    private static func run(_ tool: String, _ arguments: [String]) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: tool)
            process.arguments = arguments
            let errors = Pipe()
            process.standardError = errors
            process.standardOutput = FileHandle.nullDevice
            process.terminationHandler = { process in
                if process.terminationStatus == 0 {
                    continuation.resume()
                } else {
                    let message = String(data: errors.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                    continuation.resume(throwing: ConversionError.failed(message.trimmingCharacters(in: .whitespacesAndNewlines)))
                }
            }
            do { try process.run() } catch { continuation.resume(throwing: ConversionError.failed(error.localizedDescription)) }
        }
    }

    // MARK: - Vídeo

    private static func convertVideo(_ input: URL, to format: Format) async throws -> URL {
        let asset = AVURLAsset(url: input)
        let fileType: AVFileType = switch format.ext {
        case "mp4": .mp4
        case "mov": .mov
        case "m4v": .m4v
        case "m4a": .m4a
        default: throw ConversionError.unsupported
        }

        var preset = AVAssetExportPresetHighestQuality
        if fileType == .m4a {
            let audio = (try? await asset.loadTracks(withMediaType: .audio)) ?? []
            if audio.isEmpty { throw ConversionError.failed(String(localized: "this file has no sound")) }
            preset = AVAssetExportPresetAppleM4A
        } else if await AVAssetExportSession.compatibility(ofExportPreset: AVAssetExportPresetPassthrough, with: asset, outputFileType: fileType) {
            // Só muda o "envelope" sem recomprimir: rápido e sem perder qualidade.
            preset = AVAssetExportPresetPassthrough
        }
        guard let session = AVAssetExportSession(asset: asset, presetName: preset) else { throw ConversionError.unsupported }

        let out = destination(besides: input, ext: format.ext)
        do {
            try await session.export(to: out, as: fileType)
        } catch {
            try? FileManager.default.removeItem(at: out)
            throw ConversionError.failed(error.localizedDescription)
        }
        return out
    }

    // MARK: - Destino

    /// `foto.png` → `foto.jpg`, ou `foto (2).jpg` se já existir.
    static func destination(besides input: URL, ext: String?, suffix: String = "") -> URL {
        let dir = input.deletingLastPathComponent()
        let base = input.deletingPathExtension().lastPathComponent + suffix
        func make(_ name: String) -> URL {
            let url = dir.appendingPathComponent(name)
            return ext.map { url.appendingPathExtension($0) } ?? url
        }
        var url = make(base)
        var n = 2
        while FileManager.default.fileExists(atPath: url.path) {
            url = make("\(base) (\(n))")
            n += 1
        }
        return url
    }
}
