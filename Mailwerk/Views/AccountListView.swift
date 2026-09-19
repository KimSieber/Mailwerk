//
//  AccountListView.swift
//  Mailwerk
//
//  Created by Kim Sieber on 18.09.26.
//


//
//  AccountListView.swift
//  Mailwerk
//

import SwiftUI

struct AccountListView: View {
    let accountStore: AccountStore
    @State private var showingAddAccount = false
    
    var body: some View {
        NavigationStack {
            List {
                if accountStore.accounts.isEmpty {
                    ContentUnavailableView(
                        "Keine Postfächer",
                        systemImage: "envelope",
                        description: Text("Füge dein erstes Postfach hinzu.")
                    )
                } else {
                    ForEach(accountStore.accounts) { account in
                        VStack(alignment: .leading) {
                            Text(account.displayName)
                                .font(.headline)
                            Text(account.username)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .onDelete { indexSet in
                        for index in indexSet {
                            try? accountStore.removeAccount(accountStore.accounts[index])
                        }
                    }
                }
            }
            .navigationTitle("Mailwerk")
            .toolbar {
                ToolbarItem {
                    Button {
                        showingAddAccount = true
                    } label: {
                        Label("Postfach hinzufügen", systemImage: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingAddAccount) {
                AddAccountView(accountStore: accountStore)
            }
        }
    }
}
