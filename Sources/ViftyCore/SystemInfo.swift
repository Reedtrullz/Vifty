import Foundation

public enum SystemInfo {
    public static var modelIdentifier: String {
        var size = 0
        sysctlbyname("hw.model", nil, &size, nil, 0)
        var buffer = [CChar](repeating: 0, count: size)
        sysctlbyname("hw.model", &buffer, &size, nil, 0)
        if let terminator = buffer.firstIndex(of: 0) {
            buffer.removeSubrange(terminator..<buffer.endIndex)
        }
        return String(decoding: buffer.map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }

    public static var isAppleSilicon: Bool {
        #if arch(arm64)
        true
        #else
        false
        #endif
    }

    public static var isMacBookPro: Bool {
        modelIdentifier.hasPrefix("MacBookPro")
    }
}
