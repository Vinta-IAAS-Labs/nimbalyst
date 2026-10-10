import Foundation

/// What the Pages web view does with a navigation it is asked to make.
public enum ConsoleNavigationAction: Equatable, Sendable {
    /// Let WebKit perform the navigation.
    case allow
    /// Cancel it and load this console URL in the Pages web view instead
    /// (a `nimbalyst://console/...` rewrite, or a `_blank` team link).
    case load(URL)
    /// A Personal page (`/app/...`): only the author's desktop has it.
    case personalPages
    /// The console wants to sign in. The embedded console never does that
    /// itself; native mints a session instead.
    case reauthenticate
    /// A known app route such as `nimbalyst://session/<id>`.
    case appRoute(NimbalystExternalURLRoute)
    /// Another `nimbalyst://` link (tracker, invite, feedback request): desktop only in v1.
    case desktopOnly
    /// Open outside the app (Safari or Mail), as the transcript does.
    case openExternally(URL)
    case cancel
}

/// The Pages screen's navigation table. Pure, so every row is unit tested.
public enum ConsoleNavigationPolicy {
    /// - Parameters:
    ///   - isMainFrame: the navigation targets the top-level document.
    ///   - opensNewWindow: `target="_blank"` or `window.open` (no target frame).
    public static func decide(
        url: URL,
        isMainFrame: Bool,
        opensNewWindow: Bool = false,
        environment: ConsoleEnvironment = .production
    ) -> ConsoleNavigationAction {
        let scheme = url.scheme?.lowercased() ?? ""

        // A subframe never changes what the reader is looking at and never
        // leaves the app. The console's CSP decides which frames may load.
        if !isMainFrame && !opensNewWindow {
            return ["https", "about", "blob", "data"].contains(scheme) ? .allow : .cancel
        }

        switch scheme {
        case "about":
            return url.absoluteString == "about:blank" && !opensNewWindow ? .allow : .cancel

        case "https", "http":
            guard environment.isConsoleOrigin(url) else { return .openExternally(url) }
            return decideConsole(url: url, opensNewWindow: opensNewWindow, environment: environment)

        case "mailto":
            return .openExternally(url)

        case "nimbalyst":
            switch NimbalystExternalURLRouter.route(url) {
            case .console(let route):
                return environment.url(for: route.path).map(ConsoleNavigationAction.load) ?? .cancel
            case .consolePersonal:
                return .personalPages
            case .session(let id):
                return .appRoute(.session(id: id))
            case .openPairingScanner:
                return .appRoute(.openPairingScanner)
            case .authCallback:
                // Web content must never complete the app's own sign-in.
                return .cancel
            case .unsupported:
                return url.host?.lowercased() == "console" ? .cancel : .desktopOnly
            }

        default:
            return .cancel
        }
    }

    private static func decideConsole(url: URL, opensNewWindow: Bool, environment: ConsoleEnvironment) -> ConsoleNavigationAction {
        let path = url.path
        if path == "/app" || path.hasPrefix("/app/") { return .personalPages }
        if path == "/authenticate/native" {
            return opensNewWindow ? .load(url) : .allow
        }
        if path == "/login" || path.hasPrefix("/login/") || path == "/authenticate" || path.hasPrefix("/authenticate/") {
            return .reauthenticate
        }
        if path.isEmpty || path == "/" || ConsoleRoute(url: url, environment: environment) != nil {
            return opensNewWindow ? .load(url) : .allow
        }
        // Public wiki pages, `/connect`, and anything else the embed does not
        // host stay in Safari (the AASA excludes them, so Safari keeps them).
        return .openExternally(url)
    }
}
