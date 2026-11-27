import Foundation

/// What Keystone actually knows about an OTA operation. The overall value is
/// milestone-weighted (download 20%, restart/prep 10%, upload 60%,
/// installation acknowledgment 5%, confirmed new build 5%). It is NOT a
/// prediction of remaining time. Download/upload percentages are measured from
/// URLSession's transferred bytes; no guessed motion during ESP32 reboot.
struct FirmwareProgressState: Equatable {
    enum Phase: String {
        case checking = "Checking release"
        case downloading = "Downloading firmware"
        case preparing = "Preparing bridge"
        case uploading = "Transferring to bridge"
        case installing = "Waiting for flash confirmation"
        case reconnecting = "Verifying new firmware"
        case complete = "Update confirmed"
        case failed = "Update failed"
        case remote = "Internet OTA"
    }

    var phase: Phase
    var detail: String
    var overall: Double?
    var phaseFraction: Double?
    var bytesDone: Int64?
    var bytesTotal: Int64?
    var attempt: Int?
    var stageNumber: Int

    var overallPercent: Int? {
        overall.map { Int((max(0, min(1, $0)) * 100).rounded()) }
    }
    var phasePercent: Int? {
        phaseFraction.map { Int((max(0, min(1, $0)) * 100).rounded()) }
    }
    var bytesLabel: String? {
        guard let bytesDone, let bytesTotal, bytesTotal > 0 else { return nil }
        let done = Double(bytesDone) / 1_048_576
        let total = Double(bytesTotal) / 1_048_576
        return String(format: "%.2f / %.2f MiB", done, total)
    }

    static func local(_ phase: Phase, _ detail: String, fraction: Double? = nil,
                      bytes: Int64? = nil, total: Int64? = nil,
                      attempt: Int? = nil) -> Self {
        // The bar only advances on verified milestones or observed bytes.
        // Do not show 100% until a fresh /api/info confirms the installed build.
        let base: Double
        let weight: Double
        let stage: Int
        switch phase {
        case .checking:
            base = 0; weight = 0; stage = 1
        case .downloading:
            base = 0; weight = 0.20; stage = 1
        case .preparing:
            base = 0.20; weight = 0; stage = 2
        case .uploading:
            base = 0.30; weight = 0.60; stage = 3
        case .installing:
            base = 0.90; weight = 0; stage = 4
        case .reconnecting:
            base = 0.95; weight = 0; stage = 5
        case .complete:
            base = 1; weight = 0; stage = 5
        case .failed:
            base = 0; weight = 0; stage = 0
        case .remote:
            base = 0; weight = 0; stage = 0
        }
        let overall = phase == .failed || phase == .remote ? nil :
            min(1, base + weight * max(0, min(1, fraction ?? 0)))
        return Self(phase: phase, detail: detail, overall: overall,
                    phaseFraction: fraction.map { max(0, min(1, $0)) },
                    bytesDone: bytes, bytesTotal: total,
                    attempt: attempt, stageNumber: stage)
    }

    static func internet(_ detail: String) -> Self {
        // Internet OTA happens on the ESP32. The relay is disconnected during
        // downloading/flashing, so the iPhone has no reliable byte count.
        // An indeterminate progress indicator is honest; a percent is not.
        Self(phase: .remote, detail: detail, overall: nil,
             phaseFraction: nil, bytesDone: nil, bytesTotal: nil,
             attempt: nil, stageNumber: 0)
    }
}

/// URLSession provides genuine download and upload byte counts through these
/// delegate callbacks. The delegate queue is serialized by URLSession; throttle
/// updates to whole percentages to avoid filling the main actor queue.
final class FirmwareBytesDelegate: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let onBytes: @Sendable (Int64, Int64) -> Void
    private var lastPercent = -1
    private var lastUnknownBytes: Int64 = 0
    // A download delegate can receive a file URL that becomes invalid as soon
    // as didFinishDownloadingTo returns. Preserve a private copy before then.
    private let retainedDownload = FileManager.default.temporaryDirectory
        .appendingPathComponent("KeystoneOTA-\(UUID().uuidString).bin")

    func readDownloadedFile(fallback URL: URL) throws -> Data {
        let path = FileManager.default.fileExists(atPath: retainedDownload.path) ?
                   retainedDownload : URL
        defer { try? FileManager.default.removeItem(at: retainedDownload) }
        return try Data(contentsOf: path)
    }

    init(onBytes: @escaping @Sendable (Int64, Int64) -> Void) {
        self.onBytes = onBytes
    }

    private func report(_ done: Int64, _ expected: Int64) {
        if expected > 0 {
            let pct = Int((Double(done) / Double(expected) * 100).rounded(.down))
            if pct == lastPercent { return }
            lastPercent = pct
        } else {
            if done - lastUnknownBytes < 65536 { return }
            lastUnknownBytes = done
        }
        onBytes(done, expected)
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64,
                    totalBytesWritten: Int64,
                    totalBytesExpectedToWrite: Int64) {
        report(totalBytesWritten, totalBytesExpectedToWrite)
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didFinishDownloadingTo location: URL) {
        // The file may be deleted after this delegate callback returns.
        // Keep a private copy until the install() caller validates the image.
        try? FileManager.default.copyItem(at: location, to: retainedDownload)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask,
                    didSendBodyData bytesSent: Int64,
                    totalBytesSent: Int64, totalBytesExpectedToSend: Int64) {
        report(totalBytesSent, totalBytesExpectedToSend)
    }
}
