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
        
        guard let name = toml["name"]?.string else {
            throw PolicyParserError.missingRequiredField("name")
        }
        
        let version = toml["version"]?.string ?? "1.0.0"
        let description = toml["description"]?.string
        
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
        guard let capTable = toml["capabilities"]?.table else {
            return .default
        }
        
        let networkStr = capTable["network"]?.string ?? "disabled"
        guard let network = NetworkCapability(rawValue: networkStr) else {
            throw PolicyParserError.invalidFieldValue("capabilities.network", "unknown value: \(networkStr)")
        }
        
        var filesystem = Set<FilesystemCapability>()
        if let filesystemArr = capTable["filesystem"]?.array {
            for item in filesystemArr {
                if let fsStr = item.string {
                    guard let fs = FilesystemCapability(rawValue: fsStr) else {
                        throw PolicyParserError.invalidFieldValue("capabilities.filesystem", "unknown value: \(fsStr)")
                    }
                    filesystem.insert(fs)
                }
            }
        }
        
        var allowedPaths = Set<String>()
        if let allowedArr = capTable["allowed_paths"]?.array {
            for item in allowedArr {
                if let path = item.string {
                    allowedPaths.insert(path)
                }
            }
        }
        
        var deniedPaths = Set<String>()
        if let deniedArr = capTable["denied_paths"]?.array {
            for item in deniedArr {
                if let path = item.string {
                    deniedPaths.insert(path)
                }
            }
        }
        
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
        guard let limitsTable = table["resource_limits"]?.table else {
            return ResourceLimits()
        }
        
        let cpus = limitsTable["cpus"]?.int.map { UInt($0) }
        let memoryBytes = limitsTable["memory_bytes"]?.int.map { UInt64($0) }
        let maxProcesses = limitsTable["max_processes"]?.int.map { UInt($0) }
        
        return ResourceLimits(
            cpus: cpus,
            memoryBytes: memoryBytes,
            maxProcesses: maxProcesses
        )
    }
    
    private func parseSandbox(from toml: TOMLTable) throws -> SandboxConfig {
        guard let sandboxTable = toml["sandbox"]?.table else {
            return .default
        }
        
        let rootPath = sandboxTable["root_path"]?.string ?? "/"
        let hostname = sandboxTable["hostname"]?.string
        let workingDirectory = sandboxTable["working_directory"]?.string ?? "/"
        
        var mounts: [MountConfig] = []
        if let mountsArr = sandboxTable["mounts"]?.array {
            for mountItem in mountsArr {
                guard let mountTable = mountItem.table else { continue }
                let mount = try parseMount(from: mountTable)
                mounts.append(mount)
            }
        }
        
        var environment: [String: String] = [:]
        if let envTable = sandboxTable["environment"]?.table {
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
        guard let source = table["source"]?.string else {
            throw PolicyParserError.missingRequiredField("mount.source")
        }
        guard let destination = table["destination"]?.string else {
            throw PolicyParserError.missingRequiredField("mount.destination")
        }
        
        let typeStr = table["type"]?.string ?? "bind"
        guard let type = MountType(rawValue: typeStr) else {
            throw PolicyParserError.invalidFieldValue("mount.type", "unknown value: \(typeStr)")
        }
        
        let modeStr = table["mode"]?.string ?? "ro"
        guard let mode = MountMode(rawValue: modeStr) else {
            throw PolicyParserError.invalidFieldValue("mount.mode", "unknown value: \(modeStr)")
        }
        
        var options: [String] = []
        if let optionsArr = table["options"]?.array {
            for item in optionsArr {
                if let opt = item.string {
                    options.append(opt)
                }
            }
        }
        
        return MountConfig(
            source: source,
            destination: destination,
            type: type,
            mode: mode,
            options: options
        )
    }
    
    private func parseMetadata(from toml: TOMLTable) -> [String: String] {
        guard let metaTable = toml["metadata"]?.table else {
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
