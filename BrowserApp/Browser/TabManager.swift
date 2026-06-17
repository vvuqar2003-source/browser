import SwiftUI

class Tab: Identifiable {
    let id = UUID()
    let viewModel = BrowserViewModel()
}

class TabManager: ObservableObject {
    @Published var tabs: [Tab] = []
    @Published var activeTabId: UUID?
    @Published var showTabGrid = false

    var activeTab: Tab? {
        tabs.first { $0.id == activeTabId }
    }

    init() {
        addNewTab()
    }

    @discardableResult
    func addNewTab() -> Tab {
        let tab = Tab()
        tabs.append(tab)
        activeTabId = tab.id
        return tab
    }

    func closeTab(_ id: UUID) {
        tabs.removeAll { $0.id == id }
        if activeTabId == id {
            activeTabId = tabs.last?.id
        }
        if tabs.isEmpty {
            addNewTab()
        }
    }

    func switchTo(_ id: UUID) {
        activeTabId = id
        showTabGrid = false
    }
}
