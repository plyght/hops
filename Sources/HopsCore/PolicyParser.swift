import Foundation
import TOMLKit

public enum PolicyParserError: Error, CustomStringConvertible {
    case invalidTOML(String)
    case missingRequiredField(String)
    case invalidFieldValue(String, String)
    case fileNotFound(String)
    case unreadableFile(String)
    
    public var description: String {
        switch self {
        case .invalidTOML(let message):
            return "Invalid TOML: \(message)"
        case .missingRequiredField(let field):
            return "Missing required field: \(field)"
        case .invalidFieldValue(let field, let reason):
            return "Invalid value for field '\(field)': \(reason)"
        case .fileNotFound(let path):
            return "Policy file not found: \(path)"
        case .unreadableFile(let path):
            return "Cannot read policy file: \(path)"
        }
    }
}

public struct PolicyParser: Sendable {
    public init() {}
    
    public func parse(fromFile path: String) throws -> Policy {
        let url = URL(fileURLWithPath: path)
        guard FileManager.default.fileExists(atPath: path) else {
            throw PolicyParserError.fileNotFound(path)
        }
        
        guard let contents = try? String(contentsOf: url, encoding: .utf8) else {
            throw PolicyParserError.unreadableFile(path)
        }
        
        return try parse(fromString: contents)
    }
    
    public func parse(fromString contents: String) throws -> Policy {
        let toml: TOMLTable
        do {
            toml = try TOMLTable(string: contents)
        } catch {
            throw PolicyParserError.invalidTOML(error.localizedDescription)
        }
        
        guard let name = toml.string(for: "name") else {
            throw PolicyParserError.missingRequiredField("name")
        }
        
        let version = toml.string(for: "version") ?? "1.0.0"
        let description = toml.string(for: "description")
        
        let capabilities = try parseCapabilities(from: toml)
        let sandbox = try parseSandbox(from: toml)
        let metadata = parseMetadata(from: toml)
        
        return Policy(
            name: name,
            version: version,
            description: description,
            capabilities: capabilities,
            sandbox: sandbox,
            metadata: metadata
        )
    }
    
    private func parseCapabilities(from toml: TOMLTable) throws -> CapabilityGrant {
        guard let capTable = toml.table(for: "capabilities") else {
            return .default
        }
        
        let networkStr = capTable.string(for: "network") ?? "disabled"
        guard let network = NetworkCapability(rawValue: networkStr) else {
            throw PolicyParserError.invalidFieldValue("capabilities.network", "unknown value: \(networkStr)")
        }
        
        let filesystemArr = capTable.array(for: "filesystem")?.compactMap { $0.string } ?? []
        var filesystem = Set<FilesystemCapability>()
        for fsStr in filesystemArr {
            guard let fs = FilesystemCapability(rawValue: fsStr) else {
                throw PolicyParserError.invalidFieldValue("capabilities.filesystem", "unknown value: \(fsStr)")
            }
            filesystem.insert(fs)
        }
        
        let allowedPaths = Set(capTable.array(for: "allowed_paths")?.compactMap { $0.string } ?? [])
        let deniedPaths = Set(capTable.array(for: "denied_paths")?.compactMap { $0.string } ?? [])
        
        let resourceLimits = try parseResourceLimits(from: capTable)
        
        return CapabilityGrant(
            network: network,
            filesystem: filesystem,
            allowedPaths: allowedPaths,
            deniedPaths: deniedPaths,
            resourceLimits: resourceLimits
        )
    }
    
    private func parseResourceLimits(from table: TOMLTable) throws -> ResourceLimits {
        guard let limitsTable = table.table(for: "resource_limits") else {
            return ResourceLimits()
        }
        
        let cpus = limitsTable.int(for: "cpus").map { UInt($0) }
        let memoryBytes = limitsTable.int(for: "memory_bytes").map { UInt64($0) }
        let maxProcesses = limitsTable.int(for: "max_processes").map { UInt($0) }
        
        return ResourceLimits(
            cpus: cpus,
            memoryBytes: memoryBytes,
            maxProcesses: maxProcesses
        )
    }
    
    private func parseSandbox(from toml: TOMLTable) throws -> SandboxConfig {
        guard let sandboxTable = toml.table(for: "sandbox") else {
            return .default
        }
        
        let rootPath = sandboxTable.string(for: "root_path") ?? "/"
        let hostname = sandboxTable.string(for: "hostname")
        let workingDirectory = sandboxTable.string(for: "working_directory") ?? "/"
        
        var mounts: [MountConfig] = []
        if let mountsArr = sandboxTable.array(for: "mounts") {
            for mountItem in mountsArr {
                guard let mountTable = mountItem.table else { continue }
                let mount = try parseMount(from: mountTable)
                mounts.append(mount)
            }
        }
        
        var environment: [String: String] = [:]
        if let envTable = sandboxTable.table(for: "environment") {
            for (key, value) in envTable {
                if let strValue = value.string {
                    environment[key] = strValue
                }
            }
        }
        
        return SandboxConfig(
            rootPath: rootPath,
            mounts: mounts,
            hostname: hostname,
            workingDirectory: workingDirectory,
            environment: environment
        )
    }
    
    private func parseMount(from table: TOMLTable) throws -> MountConfig {
        guard let source = table.string(for: "source") else {
            throw PolicyParserError.missingRequiredField("mount.source")
        }
        guard let destination = table.string(for: "destination") else {
            throw PolicyParserError.missingRequiredField("mount.destination")
        }
        
        let typeStr = table.string(for: "type") ?? "bind"
        guard let type = MountType(rawValue: typeStr) else {
            throw PolicyParserError.invalidFieldValue("mount.type", "unknown value: \(typeStr)")
        }
        
        let modeStr = table.string(for: "mode") ?? "ro"
        guard let mode = MountMode(rawValue: modeStr) else {
            throw PolicyParserError.invalidFieldValue("mount.mode", "unknown value: \(modeStr)")
        }
        
        let options = table.array(for: "options")?.compactMap { $0.string } ?? []
        
        return MountConfig(
            source: source,
            destination: destination,
            type: type,
            mode: mode,
            options: options
        )
    }
    
    private func parseMetadata(from toml: TOMLTable) -> [String: String] {
        guard let metaTable = toml.table(for: "metadata") else {
            return [:]
        }
        
        var metadata: [String: String] = [:]
        for (key, value) in metaTable {
            if let strValue = value.string {
                metadata[key] = strValue
            }
        }
        return metadata
    }
}
