import CryptoKit
import Foundation

public extension String {
    var trimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var nilIfEmpty: String? {
        let value = trimmed
        return value.isEmpty ? nil : value
    }
}

public enum HomeLibraryJSONCodec {
    private static let formatterWithFractionalSeconds: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let formatterWithoutFractionalSeconds: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    public static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let rawValue = try container.decode(String.self)

            if let date = decodeDate(rawValue) {
                return date
            }

            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unsupported date format: \(rawValue)"
            )
        }
        return decoder
    }

    public static func makeEncoder(prettyPrinted: Bool = true) -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(encodeDate(date))
        }
        if prettyPrinted {
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        } else {
            encoder.outputFormatting = [.sortedKeys]
        }
        return encoder
    }

    public static func decodeDate(_ rawValue: String) -> Date? {
        formatterWithFractionalSeconds.date(from: rawValue) ?? formatterWithoutFractionalSeconds.date(from: rawValue)
    }

    public static func encodeDate(_ date: Date) -> String {
        formatterWithFractionalSeconds.string(from: date)
    }
}

public enum HomeLibraryHash {
    public static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    public static func coverAssetID(for data: Data) -> String {
        "cover-\(sha256Hex(data))"
    }

    public static func digestString(for data: Data) -> String {
        "sha256.\(sha256Hex(data))"
    }
}

public enum CLIErrorCategory: Sendable {
    case general
    case retryableCloudKit
    case cloudKitConflict
}

public struct CLIError: Error, CustomStringConvertible {
    public let message: String
    public let exitCode: Int32
    public let category: CLIErrorCategory

    public init(_ message: String, exitCode: Int32 = 1, category: CLIErrorCategory = .general) {
        self.message = message
        self.exitCode = exitCode
        self.category = category
    }

    public var description: String {
        message
    }
}

public enum FileSystem {
    public static func defaultWorkflowDirectory(root: URL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)) -> URL {
        root.appendingPathComponent(".derived/AIWorkflow", isDirectory: true)
    }

    public static func ensureDirectory(_ url: URL) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    public static func writeJSON<T: Encodable>(_ value: T, to url: URL) throws {
        try ensureDirectory(url.deletingLastPathComponent())
        let data = try HomeLibraryJSONCodec.makeEncoder().encode(value)
        try data.write(to: url, options: [.atomic])
    }

    public static func readJSON<T: Decodable>(_ type: T.Type, from url: URL) throws -> T {
        let data = try Data(contentsOf: url)
        return try HomeLibraryJSONCodec.makeDecoder().decode(type, from: data)
    }
}
