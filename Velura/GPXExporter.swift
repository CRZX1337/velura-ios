import Foundation

enum GPXExportError: LocalizedError, Equatable {
    case emptyRoute
    case noValidCoordinates
    case fileWriteFailed(String)

    var errorDescription: String? {
        switch self {
        case .emptyRoute:
            "This drive has no recorded route points to export."
        case .noValidCoordinates:
            "No valid GPS coordinates were found in this drive's route."
        case .fileWriteFailed(let reason):
            "Could not create GPX export file. \(reason)"
        }
    }
}

enum GPXExporter {
    static let maxAccurateVerticalAccuracy: Double = 25

    static func suggestedFilename(for drive: DriveRecord, timeZone: TimeZone = .current) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        return "Velura-Drive-\(formatter.string(from: drive.date)).gpx"
    }

    static func makeGPXString(
        for drive: DriveRecord,
        trackName: String? = nil
    ) throws -> String {
        guard !drive.routeCoordinates.isEmpty else {
            throw GPXExportError.emptyRoute
        }

        let validPoints = drive.routeCoordinates.filter { point in
            point.latitude.isFinite && point.longitude.isFinite
                && (-90.0...90.0).contains(point.latitude)
                && (-180.0...180.0).contains(point.longitude)
        }
        guard !validPoints.isEmpty else {
            throw GPXExportError.noValidCoordinates
        }

        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        isoFormatter.timeZone = TimeZone(secondsFromGMT: 0)

        let resolvedName = trackName ?? "Velura Drive \(isoFormatter.string(from: drive.date))"
        let escapedName = escapeXML(resolvedName)
        let metadataTime = isoFormatter.string(from: drive.date)

        var segments: [[DriveRoutePoint]] = []
        var currentSegmentIndex: Int?
        for point in validPoints {
            if currentSegmentIndex != point.segmentIndex {
                segments.append([])
                currentSegmentIndex = point.segmentIndex
            }
            segments[segments.count - 1].append(point)
        }

        var lines: [String] = []
        lines.reserveCapacity(validPoints.count * 6 + 20)
        lines.append(#"<?xml version="1.0" encoding="UTF-8"?>"#)
        lines.append(#"<gpx version="1.1" creator="Velura iOS" xmlns="http://www.topografix.com/GPX/1/1" xmlns:velura="https://velura.app/ns/gpx/1" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:schemaLocation="http://www.topografix.com/GPX/1/1 http://www.topografix.com/GPX/1/1/gpx.xsd">"#)
        lines.append("  <metadata>")
        lines.append("    <name>\(escapedName)</name>")
        lines.append("    <time>\(metadataTime)</time>")
        lines.append("  </metadata>")
        lines.append("  <trk>")
        lines.append("    <name>\(escapedName)</name>")

        for segment in segments where !segment.isEmpty {
            lines.append("    <trkseg>")
            for point in segment {
                let lat = String(format: "%.7f", locale: Locale(identifier: "en_US_POSIX"), point.latitude)
                let lon = String(format: "%.7f", locale: Locale(identifier: "en_US_POSIX"), point.longitude)
                lines.append("      <trkpt lat=\"\(lat)\" lon=\"\(lon)\">")

                if let altitude = point.altitudeMeters, altitude.isFinite {
                    let verticalOK = point.verticalAccuracy.map { $0.isFinite && $0 >= 0 && $0 <= maxAccurateVerticalAccuracy } ?? true
                    if verticalOK {
                        let ele = String(format: "%.2f", locale: Locale(identifier: "en_US_POSIX"), altitude)
                        lines.append("        <ele>\(ele)</ele>")
                    }
                }

                lines.append("        <time>\(isoFormatter.string(from: point.timestamp))</time>")

                if let speedKmh = point.speedKmh, speedKmh.isFinite, speedKmh >= 0, speedKmh <= 360 {
                    let speedMps = speedKmh / 3.6
                    let kmhText = String(format: "%.2f", locale: Locale(identifier: "en_US_POSIX"), speedKmh)
                    let mpsText = String(format: "%.3f", locale: Locale(identifier: "en_US_POSIX"), speedMps)
                    lines.append("        <extensions>")
                    lines.append("          <velura:speedKmh>\(kmhText)</velura:speedKmh>")
                    lines.append("          <velura:speedMps>\(mpsText)</velura:speedMps>")
                    lines.append("        </extensions>")
                }

                lines.append("      </trkpt>")
            }
            lines.append("    </trkseg>")
        }

        lines.append("  </trk>")
        lines.append("</gpx>")
        return lines.joined(separator: "\n") + "\n"
    }

    static func writeTemporaryGPXFile(
        for drive: DriveRecord,
        directory: URL = FileManager.default.temporaryDirectory
    ) throws -> URL {
        let xml = try makeGPXString(for: drive)
        let filename = suggestedFilename(for: drive)
        let fileURL = directory.appendingPathComponent(filename)
        do {
            try Data(xml.utf8).write(to: fileURL, options: .atomic)
            return fileURL
        } catch {
            throw GPXExportError.fileWriteFailed(error.localizedDescription)
        }
    }

    static func escapeXML(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }
}
