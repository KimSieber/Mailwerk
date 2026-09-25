//
//  ContentView.swift
//  Mailwerk
//

import SwiftUI

struct ContentView: View {
    let filterLists: any FilterListRepository

    @State private var accountStore = AccountStore()
    @State private var spamSettings = SpamSettings()

    var body: some View {
        InboxView(
            accountStore: accountStore,
            filterLists: filterLists,
            spamSettings: spamSettings
        )
    }
}

#Preview {
    ContentView(filterLists: InMemoryFilterListRepository())
}
