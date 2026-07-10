import Foundation

struct JSONLineBuffer: Sendable {
    private var storage = Data()

    mutating func append(_ data: Data) -> [Data] {
        storage.append(data)
        var lines: [Data] = []

        while let newlineIndex = storage.firstIndex(of: 0x0A) {
            var line = Data(storage[..<newlineIndex])
            let nextIndex = storage.index(after: newlineIndex)
            storage.removeSubrange(storage.startIndex..<nextIndex)

            if line.last == 0x0D {
                line.removeLast()
            }
            if !line.isEmpty {
                lines.append(line)
            }
        }

        return lines
    }

    var pendingByteCount: Int {
        storage.count
    }
}
