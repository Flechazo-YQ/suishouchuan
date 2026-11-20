#if canImport(CommandV) && canImport(StoreKitTest)
import StoreKit
import StoreKitTest
import XCTest
@testable import CommandV

@MainActor
final class SponsorshipStoreTests: XCTestCase {
    func testUnconfiguredStoreIsDisabled() async {
        let store = SponsorshipStore(productIDs: [])
        XCTAssertFalse(store.enabled)
        await store.load()
        XCTAssertTrue(store.products.isEmpty)
    }

    func testOptionalConsumableCanBePurchasedTwiceInXcode() async throws {
        let fixture = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "CommandCSponsorshipFixture", withExtension: "storekit"))
        let session = try SKTestSession(contentsOf: fixture)
        session.resetToDefaultState()
        session.clearTransactions()
        session.disableDialogs = true
        defer { session.clearTransactions(); session.resetToDefaultState() }

        let id = "com.flechazoyq.commandv.sponsorship.once"
        let store = SponsorshipStore(productIDs: [id])
        await store.load()
        XCTAssertEqual(store.products.map(\.id), [id])
        let product = try XCTUnwrap(store.products.first)
        XCTAssertEqual(product.type, .consumable)
        XCTAssertFalse(product.displayPrice.isEmpty)

        await store.purchase(product)
        XCTAssertEqual(store.notice, "感谢你的支持。")
        XCTAssertEqual(session.allTransactions().count, 1)
        await store.purchase(product)
        XCTAssertEqual(store.notice, "感谢你的支持。")
        XCTAssertEqual(session.allTransactions().count, 2)

        for await result in StoreKit.Transaction.unfinished {
            if case .verified(let transaction) = result {
                XCTAssertNotEqual(transaction.productID, id, "Consumable still pending completion")
            }
        }
    }
}
#endif
