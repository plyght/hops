import Foundation

public enum Color: String {
    case black = "\u{001B}[30m"
    case red = "\u{001B}[31m"
    case green = "\u{001B}[32m"
    case yellow = "\u{001B}[33m"
    case blue = "\u{001B}[34m"
    case magenta = "\u{001B}[35m"
    case cyan = "\u{001B}[36m"
    case white = "\u{001B}[37m"
    case reset = "\u{001B}[0m"
    case bold = "\u{001B}[1m"
    
    public var code: String { rawValue }
}

public struct ColoredOutput {
    public static func print(_ items: Any..., separator: String = " ", terminator: String = "\n", color: Color? = nil, style: Color? = nil) {
        let message = items.map { "\($0)" }.joined(separator: separator)
        if let color = color {
            let styleCode = style?.code ?? ""
            Swift.print("\(styleCode)\(color.code)\(message)\(Color.reset.code)", terminator: terminator)
        } else {
            Swift.print(message, terminator: terminator)
        }
    }
    
    public static func format(_ message: String, color: Color, style: Color? = nil) -> String {
        let styleCode = style?.code ?? ""
        return "\(styleCode)\(color.code)\(message)\(Color.reset.code)"
    }
    
    public static func success(_ message: String) {
        print("✓ \(message)", color: .green, style: .bold)
    }
    
    public static func error(_ message: String) {
        print("✗ \(message)", color: .red, style: .bold)
    }
    
    public static func warning(_ message: String) {
        print("! \(message)", color: .yellow, style: .bold)
    }
    
    public static func info(_ message: String) {
        print("ℹ \(message)", color: .cyan)
    }
}

public class Spinner {
    private let frames = ["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"]
    private var currentFrame = 0
    private var isRunning = false
    private let message: String
    private let queue = DispatchQueue(label: "com.hops.spinner")
    
    public init(message: String) {
        self.message = message
    }
    
    public func start() {
        isRunning = true
        queue.async {
            print(terminator: "\u{001B}[?25l")
            while self.isRunning {
                let frame = self.frames[self.currentFrame]
                print("\r\(Color.cyan.code)\(frame)\(Color.reset.code) \(self.message)", terminator: "")
                fflush(stdout)
                self.currentFrame = (self.currentFrame + 1) % self.frames.count
                Thread.sleep(forTimeInterval: 0.1)
            }
        }
    }
    
    public func stop(success: Bool = true, completionMessage: String? = nil) {
        isRunning = false
        Thread.sleep(forTimeInterval: 0.15)
        print("\r\u{001B}[K", terminator: "")
        print(terminator: "\u{001B}[?25h")
        
        if let msg = completionMessage {
            if success {
                ColoredOutput.success(msg)
            } else {
                ColoredOutput.error(msg)
            }
        }
    }
}
