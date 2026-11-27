import SwiftUI

/// Honest OTA progress presentation:
/// - local download/upload progress comes from URLSession byte callbacks;
/// - overall percentage is milestone-weighted, not a time prediction;
/// - reboot/flash verification pauses the bar until the new build responds;
/// - remote HTTPS OTA stays indeterminate because its transfer runs on the
///   ESP32 while its MQTT connection is offline.
struct FirmwareProgressView: View {
    let progress: FirmwareProgressState
    let running: Bool

    private var isFailure: Bool { progress.phase == .failed }
    private var isComplete: Bool { progress.phase == .complete }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 7) {
                Image(systemName: isFailure ? "exclamationmark.triangle.fill" :
                      isComplete ? "checkmark.circle.fill" : "arrow.down.circle")
                    .foregroundStyle(isFailure ? Color.red : isComplete ? Color.green : Theme.yellow)
                Text(isFailure ? "Update failed" :
                     isComplete ? "Firmware verified" : progress.phase.rawValue)
                    .font(.subheadline.weight(.semibold))
                Spacer(minLength: 0)
                if progress.stageNumber > 0 && !isComplete && !isFailure {
                    Text("Step \(progress.stageNumber) of 5")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }

            if let overall = progress.overall {
                HStack {
                    Text("Overall update")
                        .font(.caption.weight(.medium))
                    Spacer()
                    Text("\(progress.overallPercent ?? 0)%")
                        .font(.caption.monospacedDigit().weight(.semibold))
                }
                ProgressView(value: max(0, min(1, overall)), total: 1)
                    .tint(isFailure ? Color.red : isComplete ? Color.green : Theme.yellow)
                    .accessibilityLabel("Overall firmware update milestones")
                    .accessibilityValue("\(progress.overallPercent ?? 0) percent")
            } else if running && !isFailure {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("Working · percentage unavailable")
                        .font(.caption).foregroundStyle(.secondary)
                }
            } else if !isFailure && !isComplete {
                Text("Update status is not verified.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            if let portion = progress.phaseFraction,
               progress.phase == .uploading || progress.phase == .downloading {
                HStack {
                    Text(progress.phase == .uploading ? "HTTP transfer" : "GitHub download")
                        .font(.caption)
                    Spacer()
                    Text("\(progress.phasePercent ?? 0)%")
                        .font(.caption.monospacedDigit().weight(.medium))
                }
                ProgressView(value: max(0, min(1, portion)), total: 1)
                    .tint(Theme.yellow)
                    .accessibilityLabel(progress.phase == .uploading ? "Firmware HTTP upload bytes" : "Firmware download bytes")
                    .accessibilityValue("\(progress.phasePercent ?? 0) percent")
                if let amount = progress.bytesLabel {
                    Text(amount)
                        .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                }
            }

            Text(progress.detail)
                .font(.caption).foregroundStyle(isFailure ? Color.red : .secondary)
                .fixedSize(horizontal: false, vertical: true)

            if progress.phase == .remote {
                Text("Remote OTA: the bridge downloads and flashes independently, so no byte percentage is available until it reconnects.")
                    .font(.caption2).foregroundStyle(.secondary)
            } else if progress.overall != nil && !isComplete && !isFailure {
                Text("Overall bar tracks completed stages and measured transfer bytes. It does not estimate remaining time or assume the ESP32 has finished flashing.")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            if let attempt = progress.attempt, attempt > 1 {
                Text("Upload attempt \(attempt) of 4")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}
