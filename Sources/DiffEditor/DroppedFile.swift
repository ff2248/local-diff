import Foundation

/// 拖放進文字框的檔案。讀取前先檢查大小，避免誤拖大檔把 App 卡住。
enum DroppedFile {
    static let maximumSize = 5 * 1024 * 1024

    enum LoadError: Error, Equatable {
        case multipleFiles, tooLarge, notText

        func message(_ strings: Strings) -> String {
            switch self {
            case .multipleFiles: strings.dropMultipleFiles
            case .tooLarge: strings.dropTooLarge
            case .notText: strings.dropNotText
            }
        }
    }

    static func load(_ urls: [URL]) throws(LoadError) -> String {
        guard urls.count == 1, let url = urls.first else { throw .multipleFiles }
        guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
              values.isRegularFile == true else { throw .notText }
        guard let size = values.fileSize, size <= maximumSize else { throw .tooLarge }
        guard let data = try? Data(contentsOf: url), !data.contains(0),
              var text = String(data: data, encoding: .utf8) else { throw .notText }
        if text.hasPrefix("\u{FEFF}") { text.removeFirst() }
        return text
    }
}
