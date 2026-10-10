import Foundation

/// Where the team console is served. Production is fixed; tests point it at a
/// fixture origin. Only this origin may load in the Pages web view's main frame
/// or talk to the native bridge.
public struct ConsoleEnvironment: Equatable, Sendable {
    public static let production = ConsoleEnvironment(origin: URL(string: "https://console.nimbalyst.com")!)

    /// Scheme, host and (optional) port. No path.
    public let origin: URL

    public init(origin: URL) {
        self.origin = origin
    }

    /// `window.location.origin` form: scheme://host[:port], no trailing slash.
    public var originString: String {
        origin.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    public var scheme: String { origin.scheme?.lowercased() ?? "https" }
    public var host: String { origin.host?.lowercased() ?? "" }
    public var port: Int? { origin.port }

    /// True when `url` is on exactly this origin (scheme, host, port).
    public func isConsoleOrigin(_ url: URL) -> Bool {
        url.scheme?.lowercased() == scheme
            && url.host?.lowercased() == host
            && effectivePort(url.port, scheme: url.scheme) == effectivePort(port, scheme: scheme)
    }

    /// True for a WebKit security origin triple on this origin.
    public func isConsoleOrigin(protocol scheme: String, host: String, port: Int) -> Bool {
        scheme.lowercased() == self.scheme
            && host.lowercased() == self.host
            && effectivePort(port == 0 ? nil : port, scheme: scheme) == effectivePort(self.port, scheme: self.scheme)
    }

    /// The absolute console URL for a route path (`/org/...`, with query and fragment).
    public func url(for path: String) -> URL? {
        guard path.hasPrefix("/") else { return nil }
        return URL(string: origin.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + path)
    }

    private func effectivePort(_ port: Int?, scheme: String?) -> Int {
        if let port { return port }
        return scheme?.lowercased() == "http" ? 80 : 443
    }
}

/// A console page the Pages screen can show: a path under `/org/<org>/`.
///
/// The org segment is a route key: today always the Stytch org id
/// (`organization-...`), and possibly a slug in the future. `orgId` is only set
/// when the key is an org id, matching the console's own `orgIdFromConsolePath`.
public struct ConsoleRoute: Hashable, Sendable {
    /// Path plus query and fragment, percent-encoded as it appears in the URL.
    public let path: String
    public let orgKey: String
    /// The team project segment, when the path is under `/project/<id>`.
    public let teamProjectId: String?

    public var orgId: String? { orgKey.hasPrefix("organization-") ? orgKey : nil }
    public var isTeamProjectPath: Bool { teamProjectId != nil }

    private static let orgKeyCharacters = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-")
    private static let segmentCharacters = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-.~%")

    /// Parse a console path (`/org/<org>/...`, optional `?query` and `#fragment`).
    /// Rejects traversal, empty segments, control characters and anything that
    /// is not under `/org/<key>`.
    public init?(path: String) {
        guard path.count <= 2048, path.hasPrefix("/org/") else { return nil }
        guard !path.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) || $0 == " " || $0 == "\\" }) else { return nil }
        let pathOnly = path.split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false)[0]
            .split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false)[0]
        let segments = pathOnly.split(separator: "/", omittingEmptySubsequences: false).dropFirst()
        // Leading "/" yields an empty first element, dropped above. Every other
        // segment must be non-empty except a single trailing slash.
        var parts = Array(segments)
        if parts.last == "" { parts.removeLast() }
        guard parts.count >= 2, parts[0] == "org", !parts.contains(""),
              !parts.contains(where: { $0 == "." || $0 == ".." || $0.lowercased().contains("%2e%2e") || $0.lowercased().contains("%2f") })
        else { return nil }
        let orgKey = String(parts[1])
        guard (1...128).contains(orgKey.count),
              orgKey.unicodeScalars.allSatisfy(Self.orgKeyCharacters.contains) else { return nil }
        for part in parts.dropFirst(2) {
            guard part.count <= 256, part.unicodeScalars.allSatisfy(Self.segmentCharacters.contains) else { return nil }
        }
        var teamProjectId: String?
        if parts.count >= 4, parts[2] == "project" {
            teamProjectId = String(parts[3]).removingPercentEncoding ?? String(parts[3])
        }
        self.path = path
        self.orgKey = orgKey
        self.teamProjectId = teamProjectId
    }

    /// The route for an absolute console URL on `environment`'s origin.
    public init?(url: URL, environment: ConsoleEnvironment = .production) {
        guard environment.isConsoleOrigin(url),
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        var path = components.percentEncodedPath
        if let query = components.percentEncodedQuery { path += "?\(query)" }
        if let fragment = components.percentEncodedFragment { path += "#\(fragment)" }
        self.init(path: path)
    }

    /// The team Wiki home for a project.
    public static func wiki(orgId: String, teamProjectId: String) -> ConsoleRoute? {
        ConsoleRoute(path: "/org/\(encode(orgId))/project/\(encode(teamProjectId))/wiki")
    }

    /// The team Trackers home for a project.
    public static func trackers(orgId: String, teamProjectId: String) -> ConsoleRoute? {
        ConsoleRoute(path: "/org/\(encode(orgId))/project/\(encode(teamProjectId))/trackers")
    }

    private static func encode(_ segment: String) -> String {
        segment.addingPercentEncoding(withAllowedCharacters: CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-.~")) ?? segment
    }
}
