import StoreKit
import SwiftUI

@MainActor
final class SponsorshipStore: ObservableObject {
    private let productIDs: [String]

    @Published private(set) var products: [Product] = []
    @Published private(set) var loading = false
    @Published private(set) var purchasing = false
    @Published private(set) var notice: String?

    init(productIDs: [String]? = nil) {
        let configured = Bundle.main.object(forInfoDictionaryKey: "CommandCSponsorshipProductIDs") as? String ?? ""
        self.productIDs = productIDs ?? configured.split { $0.isWhitespace || $0 == "," }.map(String.init)
    }

    var enabled: Bool { !productIDs.isEmpty }

    func load() async {
        guard enabled, !loading else { return }
        loading = true
        notice = nil
        defer { loading = false }
        do {
            products = try await Product.products(for: productIDs)
                .filter { $0.type == .consumable }
                .sorted { $0.price < $1.price }
            if products.isEmpty { notice = "当前 App Store 地区暂无可用的赞助选项。" }
        } catch {
            guard !Task.isCancelled else { return }
            notice = "暂时无法加载赞助选项，请稍后重试。"
        }
    }

    func purchase(_ product: Product) async {
        guard !purchasing, products.contains(where: { $0.id == product.id }) else { return }
        guard AppStore.canMakePayments else {
            notice = "这台设备的 App Store 设置限制了付款。"
            return
        }
        purchasing = true
        notice = nil
        defer { purchasing = false }
        do {
            switch try await product.purchase() {
            case .success(let result): await finish(result)
            case .pending: notice = "赞助正在等待 Apple 确认。"
            case .userCancelled: break
            @unknown default: notice = "请在 App Store 购买记录中查看结果。"
            }
        } catch {
            notice = "系统未确认赞助结果，请查看 App Store 购买记录。"
        }
    }

    func observeTransactions() async {
        guard enabled else { return }
        for await result in StoreKit.Transaction.updates {
            await finish(result)
        }
    }

    private func finish(_ result: VerificationResult<StoreKit.Transaction>) async {
        switch result {
        case .verified(let transaction):
            guard productIDs.contains(transaction.productID), transaction.productType == .consumable else { return }
            await transaction.finish()
            if transaction.revocationDate == nil { notice = "感谢你的支持。" }
        case .unverified(let transaction, _):
            guard productIDs.contains(transaction.productID) else { return }
            notice = "暂时无法验证赞助，请查看 App Store 购买记录。"
        }
    }
}

@MainActor
struct SponsorshipView: View {
    @ObservedObject var store: SponsorshipStore

    var body: some View {
        List {
            Section {
                Text("欢迎自愿赞助，帮助维护 CommandC。是否赞助不影响应用功能。")
                Text("赞助为单次付款，由 Apple 处理。价格以系统付款界面为准。")
                    .foregroundColor(.secondary)
            }
            if store.loading {
                ProgressView("正在读取 App Store 价格…")
            }
            ForEach(store.products, id: \.id) { product in
                Button {
                    Task { await store.purchase(product) }
                } label: {
                    HStack {
                        Text(product.displayName)
                        Spacer()
                        Text(product.displayPrice).monospacedDigit()
                    }
                }.disabled(store.loading || store.purchasing)
            }
            if let notice = store.notice { Text(notice).foregroundColor(.secondary) }
            if store.products.isEmpty && !store.loading {
                Button("重新加载") { Task { await store.load() } }
            }
        }
        .navigationTitle("支持开发者")
        .task { await store.load() }
    }
}
