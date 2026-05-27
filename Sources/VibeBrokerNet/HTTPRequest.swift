import Foundation

public struct HTTPRequest: Sendable {
    public let method: String
    public let path: String
    public let query: [String: String]
    public let headers: [String: String]
    public let body: Data

    public enum ParseError: Error { case malformed }

    public static func parse(_ data: Data) throws -> HTTPRequest {
        // Find header / body boundary: "\r\n\r\n".
        guard let separatorRange = data.range(of: Data("\r\n\r\n".utf8)) else {
            throw ParseError.malformed
        }
        let headerData = data.subdata(in: 0..<separatorRange.lowerBound)
        let bodyData = data.subdata(in: separatorRange.upperBound..<data.count)

        guard let headerString = String(data: headerData, encoding: .utf8) else {
            throw ParseError.malformed
        }
        let lines = headerString.components(separatedBy: "\r\n")
        guard !lines.isEmpty else { throw ParseError.malformed }

        let requestLine = lines[0].components(separatedBy: " ")
        guard requestLine.count >= 2 else { throw ParseError.malformed }
        let method = requestLine[0]
        let rawTarget = requestLine[1]

        let (path, query) = splitPathAndQuery(rawTarget)

        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let name = String(line[..<colon]).trimmingCharacters(in: .whitespaces).lowercased()
            let value = String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
            headers[name] = value
        }

        return HTTPRequest(method: method, path: path, query: query, headers: headers, body: bodyData)
    }

    private static func splitPathAndQuery(_ target: String) -> (String, [String: String]) {
        guard let qmark = target.firstIndex(of: "?") else {
            return (target, [:])
        }
        let path = String(target[..<qmark])
        let queryString = String(target[target.index(after: qmark)...])
        var query: [String: String] = [:]
        for pair in queryString.components(separatedBy: "&") {
            let kv = pair.components(separatedBy: "=")
            if kv.count == 2 {
                query[kv[0]] = kv[1].removingPercentEncoding ?? kv[1]
            } else if kv.count == 1, !kv[0].isEmpty {
                query[kv[0]] = ""
            }
        }
        return (path, query)
    }
}
