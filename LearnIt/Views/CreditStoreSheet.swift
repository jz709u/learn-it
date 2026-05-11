import SwiftUI

struct CreditStoreSheet: View {
    @EnvironmentObject private var creditStore: ImportCreditStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    headerCard
                    catalogCard
                    notesCard
                }
                .padding(20)
            }
            .background(
                LinearGradient(
                    colors: [
                        Color(red: 0.95, green: 0.97, blue: 1.0),
                        Color(red: 0.89, green: 0.93, blue: 0.99)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()
            )
            .navigationTitle("AI Credits")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .task {
            await creditStore.loadProducts()
        }
    }

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("AI Import Credits")
                .font(.system(size: 28, weight: .bold, design: .rounded))

            Text("Current balance: \(creditStore.balance) credits")
                .font(.headline)

            Text("OpenAI imports use 1 credit only after the deck is created and saved successfully.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .foregroundStyle(Color.black)
        .padding(18)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private var catalogCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(CreditCatalogItem.all) { item in
                HStack(alignment: .center, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) {
                            Text(item.title)
                                .font(.headline)
                            if let badge = item.badge {
                                Text(badge)
                                    .font(.caption.weight(.semibold))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color.orange.opacity(0.18), in: Capsule())
                            }
                        }

                        Text("1 credit = 1 processed file")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Button {
                        Task {
                            await creditStore.purchase(item)
                        }
                    } label: {
                        Text(creditStore.displayPrice(for: item))
                            .font(.headline.weight(.semibold))
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(creditStore.isPurchasing || creditStore.isLoadingProducts)
                }
                .padding(.vertical, 4)
            }
        }
        .foregroundStyle(Color.black)
        .padding(18)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private var notesCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("How Credits Work")
                .font(.headline)
            Text("Local Process and Apple Intelligence do not use credits.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text("Credits are only deducted when an OpenAI import succeeds.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text("OpenAI mode is a credit-backed cloud import flow managed by the app.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text("Credit purchases are tracked locally so the app can preserve your balance and deduct only on successful imports.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .foregroundStyle(Color.black)
        .padding(18)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }
}
