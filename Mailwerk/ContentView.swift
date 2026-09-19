//
//  ContentView.swift
//  Mailwerk
//

import SwiftUI

struct ContentView: View {
    @State private var accountStore = AccountStore()

    var body: some View {
        InboxView(accountStore: accountStore)
    }
}

#Preview {
    ContentView()
}
