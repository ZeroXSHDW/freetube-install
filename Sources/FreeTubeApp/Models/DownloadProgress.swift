import Foundation

struct DownloadProgress: Equatable {
    var totalBytes: Int64 = 0
    var downloadedBytes: Int64 = 0
    var isDownloading: Bool = false
    var error: String? = nil

    var fraction: Double {
        guard totalBytes > 0 else { return 0 }
        return Double(downloadedBytes) / Double(totalBytes)
    }

    var percentage: Int {
        Int(fraction * 100)
    }

    var readableTotal: String {
        ByteCountFormatter.string(fromByteCount: totalBytes, countStyle: .file)
    }

    var readableDownloaded: String {
        ByteCountFormatter.string(fromByteCount: downloadedBytes, countStyle: .file)
    }
}
