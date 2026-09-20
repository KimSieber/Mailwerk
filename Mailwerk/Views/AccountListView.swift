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
    @State private var editingAccount: MailAccount?
    @Environment(\.dismiss) private var dismiss
    
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
                        Button {
                            editingAccount = account
                        } label: {
                            HStack(spacing: 10) {
                                // Farbpunkt, falls eine Farbe gewählt ist
                                if let colorHex = account.colorHex {
                                    Circle()
                                        .fill(Color(hex: colorHex))
                                        .frame(width: 12, height: 12)
                                }
                                VStack(alignment: .leading) {
                                    Text(account.displayName)
                                        .font(.headline)
                                    Text(account.username)
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .tint(.primary)
                    }
                    .onDelete { indexSet in
                        for index in indexSet {
                            try? accountStore.removeAccount(accountStore.accounts[index])
                        }
                    }
                }
            }
            .navigationTitle("Postfächer")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                }
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
            .sheet(item: $editingAccount) { account in
                EditAccountView(accountStore: accountStore, account: account)
            }
        }
    }
}
