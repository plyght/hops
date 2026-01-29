import Foundation

public enum MountType: String, Codable, Sendable {
    case bind
    case tmpfs
    case devtmpfs
    case proc
    case sysfs
    case overlay
}

public enum MountMode: String, Codable, Sendable {
    case readOnly = "ro"
    case readWrite = "rw"
}

public struct MountConfig: Codable, Sendable, Equatable {
    public var source: String
    public var destination: String
    public var type: MountType
    public var mode: MountMode
    public var options: [String]
    public var overlayLowerDir: String?
    public var overlayUpperDir: String?
    public var overlayWorkDir: String?
    
    public init(
        source: String,
        destination: String,
        type: MountType,
        mode: MountMode = .readOnly,
        options: [String] = [],
        overlayLowerDir: String? = nil,
        overlayUpperDir: String? = nil,
        overlayWorkDir: String? = nil
    ) {
        self.source = source
        self.destination = destination
        self.type = type
        self.mode = mode
        self.options = options
        self.overlayLowerDir = overlayLowerDir
        self.overlayUpperDir = overlayUpperDir
        self.overlayWorkDir = overlayWorkDir
    }
    
    public static func bind(
        source: String,
        destination: String,
        mode: MountMode = .readOnly
    ) -> MountConfig {
        MountConfig(source: source, destination: destination, type: .bind, mode: mode)
    }
    
    public static func tmpfs(
        destination: String,
        size: String? = nil
    ) -> MountConfig {
        var options: [String] = []
        if let size = size {
            options.append("size=\(size)")
        }
        return MountConfig(
            source: "tmpfs",
            destination: destination,
            type: .tmpfs,
            mode: .readWrite,
            options: options
        )
    }
    
    public static func overlay(
        destination: String,
        lowerDir: String,
        upperDir: String,
        workDir: String
    ) -> MountConfig {
        MountConfig(
            source: "overlay",
            destination: destination,
            type: .overlay,
            mode: .readWrite,
            options: [],
            overlayLowerDir: lowerDir,
            overlayUpperDir: upperDir,
            overlayWorkDir: workDir
        )
    }
}
