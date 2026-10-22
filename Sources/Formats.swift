import Foundation
import UniformTypeIdentifiers

/// Tipo de ficheiro de entrada — decide que conversões fazem sentido.
enum FileKind: String {
    case text, image, pdf, audio, video

    static func detect(_ url: URL) -> FileKind? {
        let type = (try? url.resourceValues(forKeys: [.contentTypeKey]))?.contentType
            ?? UTType(filenameExtension: url.pathExtension)
        guard let type else { return nil }

        if type.conforms(to: .pdf) { return .pdf }
        if type.conforms(to: .image) { return .image }
        // Áudio antes de vídeo: ambos são "audiovisual content".
        if type.conforms(to: .audio) { return .audio }
        if type.conforms(to: .movie) { return .video }
        if type.conforms(to: .text) || type.conforms(to: .rtfd) || type.conforms(to: .webArchive) { return .text }
        let wordTypes = ["com.microsoft.word.doc",
                         "org.openxmlformats.wordprocessingml.document",
                         "org.oasis-open.opendocument.text"]
        if wordTypes.compactMap({ UTType($0) }).contains(where: { type.conforms(to: $0) }) { return .text }
        return nil
    }
}

/// Formato de saída que aparece como bolha no seletor.
struct Format: Hashable, Identifiable {
    let ext: String
    let name: String
    let group: FileKind
    var id: String { ext }

    static let pdf  = Format(ext: "pdf",  name: "PDF",        group: .pdf)
    static let docx = Format(ext: "docx", name: "Word",       group: .text)
    static let doc  = Format(ext: "doc",  name: String(localized: "Word 97"),    group: .text)
    static let txt  = Format(ext: "txt",  name: String(localized: "Text"),      group: .text)
    static let rtf  = Format(ext: "rtf",  name: String(localized: "Rich Text"),  group: .text)
    static let html = Format(ext: "html", name: String(localized: "Web page"), group: .text)
    static let odt  = Format(ext: "odt",  name: String(localized: "OpenDocument"),    group: .text)

    static let jpg  = Format(ext: "jpg",  name: "JPEG",       group: .image)
    static let png  = Format(ext: "png",  name: "PNG",        group: .image)
    static let heic = Format(ext: "heic", name: "HEIC",       group: .image)
    static let tiff = Format(ext: "tiff", name: "TIFF",       group: .image)
    static let gif  = Format(ext: "gif",  name: "GIF",        group: .image)
    static let bmp  = Format(ext: "bmp",  name: "BMP",        group: .image)
    static let webp = Format(ext: "webp", name: "WebP",       group: .image)

    static let m4a  = Format(ext: "m4a",  name: String(localized: "AAC audio"),  group: .audio)
    static let wav  = Format(ext: "wav",  name: "WAV",        group: .audio)
    static let aiff = Format(ext: "aiff", name: "AIFF",       group: .audio)
    static let flac = Format(ext: "flac", name: "FLAC",       group: .audio)

    static let mp4  = Format(ext: "mp4",  name: "MP4",        group: .video)
    static let mov  = Format(ext: "mov",  name: "QuickTime",  group: .video)
    static let m4v  = Format(ext: "m4v",  name: "M4V",        group: .video)

    static func targets(for kind: FileKind) -> [Format] {
        switch kind {
        case .text:  [.pdf, .docx, .txt, .rtf, .html, .odt, .doc]
        case .image: [.jpg, .png, .heic, .pdf, .tiff, .gif, .bmp, .webp].filter { $0.group != .image || Converter.canWriteImage($0.ext) }
        case .pdf:   [.png, .jpg, .txt, .docx, .rtf]
        case .audio: [.m4a, .wav, .aiff, .flac]
        case .video: [.mp4, .mov, .m4v, .m4a]
        }
    }

    /// Junta extensões que são o mesmo formato (jpeg/jpg, tif/tiff…).
    static func normalized(_ ext: String) -> String {
        switch ext.lowercased() {
        case "jpeg", "jpe": "jpg"
        case "tif": "tiff"
        case "htm": "html"
        case "aif": "aiff"
        case "text": "txt"
        default: ext.lowercased()
        }
    }
}
