// BrowserApp/BrowserApp/Browser/AddressBarView.swift

import SwiftUI

struct AddressBarView: View {
    @Binding var urlString: String
    let onSubmit: () -> Void
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "lock.fill")
                    .foregroundColor(.green)
                    .font(.caption)

                TextField("URL veya arama", text: $urlString)
                    .textFieldStyle(.plain)
                    .autocapitalization(.none)
                    .disableAutocorrection(true)
                    .keyboardType(.webSearch)
                    .focused($isFocused)
                    .onSubmit {
                        isFocused = false
                        onSubmit()
                    }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color(.systemGray6))
            .cornerRadius(12)
        }
    }
}
