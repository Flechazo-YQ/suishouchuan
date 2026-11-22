#if canImport(CommandV) && canImport(StoreKitTest)
import Combine
import StoreKit
import StoreKitTest
import XCTest
@testable import CommandV

@MainActor
final class SponsorshipStoreTests: XCTestCase {
    func testUnconfiguredStoreIsDisabled() async {
        let store = SponsorshipStore(productIDs: [], storefrontCountry: { "CHN" })
        XCTAssertFalse(store.enabled)
        await store.load()
        XCTAssertTrue(store.products.isEmpty)
    }

    func testUnknownAndOverseasStorefrontsHideSponsorship() async {
        var country: String?
        let store = SponsorshipStore(productIDs: ["com.flechazoyq.commandv.sponsorship.once"], storefrontCountry: { country })
        for code in [nil, "USA", "HKG", "TWN", "MAC"] {
            country = code
            await store.load()
            XCTAssertFalse(store.enabled)
            XCTAssertTrue(store.products.isEmpty)
        }
        country = "CHN"
        await store.refreshStorefront()
        XCTAssertTrue(store.enabled)
        country = "JPN"
        await store.refreshStorefront()
        XCTAssertFalse(store.enabled)
    }

    func testOptionalConsumableCanBePurchasedTwiceInXcode() async throws {
        guard #available(iOS 17.0, *) else { throw XCTSkip("StoreKit's test purchase API requires iOS 17") }
        let fixture = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "CommandCSponsorshipFixture", withExtension: "storekit"))
        let session = try SKTestSession(contentsOf: fixture)
        session.resetToDefaultState()
        session.clearTransactions()
        session.disableDialogs = true
        defer { session.clearTransactions(); session.resetToDefaultState() }

        let id = "com.flechazoyq.commandv.sponsorship.once"
        let store = SponsorshipStore(productIDs: [id], storefrontCountry: { "CHN" })
        await store.load()
        XCTAssertEqual(store.products.map(\.id), [id])
        let product = try XCTUnwrap(store.products.first)
        XCTAssertEqual(product.type, .consumable)
        XCTAssertFalse(product.displayPrice.isEmpty)

        let listener = Task { await store.observeTransactions() }
        defer { listener.cancel() }
        await Task.yield()
        for count in 1...2 {
            let verified = expectation(description: "Verified sponsorship \(count)")
            let notice = store.$notice.dropFirst().filter { $0 == "感谢你的支持。" }.first()
                .sink { _ in verified.fulfill() }
            _ = try await session.buyProduct(identifier: id, options: [])
            await fulfillment(of: [verified], timeout: 10)
            notice.cancel()
            XCTAssertEqual(session.allTransactions().count, count)
        }
    }
}
#endif
