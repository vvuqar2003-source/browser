// BrowserApp/BrowserApp/AdBlock/AdBlocker.swift

import Foundation
import WebKit
import Combine

class AdBlocker: ObservableObject {
    @Published var isEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: "adBlockEnabled")
            if isEnabled {
                loadRules()
            } else {
                removeRules()
            }
        }
    }
    @Published var blockedCount: Int = 0
    @Published var isLoading: Bool = false
    @Published var lastUpdate: Date?

    private var contentRules: [WKContentRuleList] = []
    private var webView: WKWebView?

    private let filterURLs = [
        "https://easylist.to/easylist/easylist.txt",
        "https://easylist.to/easylist/easyprivacy.txt",
        "https://raw.githubusercontent.com/uBlockOrigin/uAssets/master/filters/filters.txt"
    ]

    init() {
        self.isEnabled = UserDefaults.standard.bool(forKey: "adBlockEnabled")
        if let lastUpdateData = UserDefaults.standard.object(forKey: "adBlockLastUpdate") as? Date {
            self.lastUpdate = lastUpdateData
        }
    }

    func loadRules() {
        guard isEnabled else { return }

        let lastUpdate = UserDefaults.standard.object(forKey: "adBlockLastUpdate") as? Date
        let oneWeekAgo = Calendar.current.date(byAdding: .day, value: -7, to: Date())!

        if let lastUpdate = lastUpdate, lastUpdate > oneWeekAgo {
            loadCachedRules()
            return
        }

        fetchAndCompileRules()
    }

    func updateRules() {
        fetchAndCompileRules()
    }

    private func loadCachedRules() {
        WKContentRuleListStore.default().lookUpContentRuleList(forIdentifier: "AdBlockRules") { [weak self] ruleList, error in
            DispatchQueue.main.async {
                if let ruleList = ruleList {
                    self?.contentRules = [ruleList]
                    if let webView = self?.webView {
                        self?.applyRules(to: webView)
                    }
                }
            }
        }
    }

    private func fetchAndCompileRules() {
        isLoading = true

        let group = DispatchGroup()
        var allRules: [String] = []
        let lock = NSLock()

        for urlString in filterURLs {
            guard let url = URL(string: urlString) else { continue }
            group.enter()

            URLSession.shared.dataTask(with: url) { [weak self] data, response, error in
                defer { group.leave() }
                guard let data = data, let content = String(data: data, encoding: .utf8) else { return }

                let rules = self?.parseFilterList(content) ?? []
                lock.lock()
                allRules.append(contentsOf: rules)
                lock.unlock()
            }.resume()
        }

        group.notify(queue: .main) { [weak self] in
            self?.compileRules(allRules)
        }
    }

    private func parseFilterList(_ content: String) -> [String] {
        var rules: [String] = []
        let lines = content.components(separatedBy: .newlines)

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.isEmpty || trimmed.hasPrefix("!") || trimmed.hasPrefix("[") {
                continue
            }

            if trimmed.hasPrefix("||") {
                let domain = String(trimmed.dropFirst(2))
                if let rule = createURLBlockRule(for: domain) {
                    rules.append(rule)
                }
            } else if trimmed.contains("##") || trimmed.contains("#@#") || trimmed.contains("#?#") {
                continue
            }
        }

        return rules
    }

    private func createURLBlockRule(for domain: String) -> String? {
        let cleanDomain = domain
            .replacingOccurrences(of: "^", with: "")
            .replacingOccurrences(of: "*", with: ".*")
            .replacingOccurrences(of: "|", with: "")

        let escapedDomain = NSRegularExpression.escapedPattern(for: cleanDomain)

        let rule = """
        {
            "trigger": {
                "url-filter": ".*\(escapedDomain).*",
                "resource-type": ["document", "image", "script", "style-sheet", "media", "raw", "font"]
            },
            "action": {
                "type": "block"
            }
        }
        """
        return rule
    }

    private func compileRules(_ rules: [String]) {
        let rulesJSON = "[\(rules.joined(separator: ","))]"

        WKContentRuleListStore.default().compileContentRuleList(
            forIdentifier: "AdBlockRules",
            encodedContentRuleList: rulesJSON
        ) { [weak self] ruleList, error in
            DispatchQueue.main.async {
                self?.isLoading = false

                if let ruleList = ruleList {
                    self?.contentRules = [ruleList]
                    UserDefaults.standard.set(Date(), forKey: "adBlockLastUpdate")
                    self?.lastUpdate = Date()

                    if let webView = self?.webView {
                        self?.applyRules(to: webView)
                    }
                }
            }
        }
    }

    func applyRules(to webView: WKWebView) {
        self.webView = webView

        for rule in contentRules {
            webView.configuration.userContentController.add(rule)
        }
    }

    private func removeRules() {
        guard let webView = webView else { return }

        for rule in contentRules {
            webView.configuration.userContentController.remove(rule)
        }
        contentRules.removeAll()
    }

    func incrementBlockedCount() {
        DispatchQueue.main.async {
            self.blockedCount += 1
        }
    }
}
