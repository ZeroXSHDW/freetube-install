import Foundation

struct Version {
    static func compare(_ v1: String, _ v2: String) -> Int {
        let p1 = v1.split(separator: ".").compactMap { Int($0) }
        let p2 = v2.split(separator: ".").compactMap { Int($0) }
        let count = max(p1.count, p2.count)
        for i in 0..<count {
            let n1 = i < p1.count ? p1[i] : 0
            let n2 = i < p2.count ? p2[i] : 0
            if n1 < n2 { return -1 }
            if n1 > n2 { return 1 }
        }
        return 0
    }
}
