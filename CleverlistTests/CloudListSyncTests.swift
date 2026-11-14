import Foundation
import Testing
@testable import Cleverlist

@Suite(.serialized)
@MainActor
struct CloudListSyncTests {
    private func withStore(_ body: (CleverlistStore, URL) throws -> Void) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try body(CleverlistStore(directory: directory), directory)
    }

    private struct StoredCloudState: Codable {
        var version = 1
        var bindings: [CloudListBinding]
        var lastAccountName: String?
        var engineStates: [String: String] = [:]
        var systemFields: [String: Data] = [:]
        var acknowledged: [String: String] = [:]
    }

    @Test func cachedAccountKeepsOfflineListsEditableAfterRelaunch() throws {
        try withStore { store, _ in
            let listID = store.activeLists[0].id
            let binding = CloudListBinding(id: listID, zoneName: "cleverlist-v1-" + UUID().uuidString,
                                           ownerName: "owner", accountName: "cached-account", isOwner: true)
            let state = StoredCloudState(bindings: [binding], lastAccountName: "cached-account")
            try JSONEncoder().encode(state).write(to: store.cloudStateURL)
            let sync = CloudSyncService(store: store)
            #expect(sync.accountName == "cached-account")
            #expect(store.canEdit(listID))
            #expect(store.activeLists.contains { $0.id == listID })
            store.save(ShoppingItem(listID: listID, productID: store.activeProducts[0].id, amount: "2"))
            #expect(store.items(in: listID).count == 1)
        }
    }

    @Test func retiredOwnerZoneDoesNotHideTheRetainedPrivateList() throws {
        try withStore { store, _ in
            let listID = store.activeLists[0].id
            let binding = CloudListBinding(id: listID, zoneName: "cleverlist-v1-" + UUID().uuidString,
                                           ownerName: "owner", accountName: "previous-account",
                                           isOwner: true, isActive: false)
            let state = StoredCloudState(bindings: [binding], lastAccountName: nil)
            try JSONEncoder().encode(state).write(to: store.cloudStateURL)
            let sync = CloudSyncService(store: store)
            #expect(sync.binding(for: listID) == nil)
            #expect(store.canEdit(listID))
            #expect(store.activeLists.contains { $0.id == listID })
        }
    }

    @Test func sharedDetailsNeverFallBackToPrivateCatalog() throws {
        try withStore { store, _ in
            let product = Product(name: LocalizedName(sv: "Hemlig", de: "Geheim", en: "Secret"))
            store.save(product)
            let unit = store.catalog(.unit)[0]
            let item = ShoppingItem(listID: store.activeLists[0].id, productID: product.id,
                                    unitID: unit.id, sharedDetails: SharedItemDetails(product: nil, terms: []))
            #expect(store.product(for: item) == nil)
            #expect(store.term(unit.id, for: item) == nil)
        }
    }

    @Test func exportIncludesOnlyReferencedNames() throws {
        try withStore { store, _ in
            var product = store.activeProducts[0]
            product.storeIDs = store.catalog(.store).map(\.id)
            store.save(product)
            let item = ShoppingItem(listID: store.activeLists[0].id, productID: product.id,
                                    unitID: store.catalog(.unit)[0].id)
            let details = store.sharingDetails(for: item)
            #expect(details.product?.storeIDs.isEmpty == true)
            let allowed = Set([item.unitID, product.typeID, product.sectionID].compactMap { $0 })
            #expect(Set(details.terms.map(\.id)).isSubset(of: allowed))
            #expect(!details.terms.contains { $0.kind == .store })
        }
    }

    @Test func rejectsWrongListAndUnexpectedMetadata() throws {
        let list = ShoppingList(name: "Shared")
        var item = ShoppingItem(listID: list.id, productID: UUID(),
                                sharedDetails: SharedItemDetails(product: nil, terms: []))
        let valid = CloudListPayload(item: item)
        _ = try valid.validated(listID: list.id, recordName: item.id.uuidString)
        #expect(throws: CloudListError.self) {
            try valid.validated(listID: UUID(), recordName: item.id.uuidString)
        }
        #expect(throws: CloudListError.self) {
            try CloudListPayload(version: 99, item: item).validated(listID: list.id, recordName: item.id.uuidString)
        }
        item.sharedDetails?.terms = [CatalogTerm(name: LocalizedName(sv: "Privat", de: "Privat", en: "Private"), kind: .store)]
        #expect(throws: CloudListError.self) {
            try CloudListPayload(item: item).validated(listID: list.id, recordName: item.id.uuidString)
        }
        item.sharedDetails = nil
        #expect(throws: CloudListError.self) {
            try CloudListPayload(item: item).validated(listID: list.id, recordName: item.id.uuidString)
        }
    }

    @Test func crossListOverwriteRollsBack() throws {
        try withStore { store, _ in
            let privateID = store.activeLists[0].id
            let sharedList = ShoppingList(name: "Shared")
            store.save(sharedList)
            let original = ShoppingItem(listID: privateID, productID: store.activeProducts[0].id)
            store.save(original)
            let before = store.items
            var forged = original
            forged.listID = sharedList.id
            forged.revision = 999
            #expect(throws: CloudListError.self) {
                try store.applyCloud(list: nil, item: forged, listID: sharedList.id)
            }
            #expect(store.items == before)
        }
    }

    @Test func conflictsConvergeAndDeletedItemsStayDeleted() throws {
        try withStore { store, _ in
            let listID = store.activeLists[0].id
            var a = ShoppingItem(listID: listID, productID: store.activeProducts[0].id,
                                 amount: "2", revision: 10, deviceID: "A")
            var b = a
            b.amount = "3"
            b.deviceID = "B"
            try store.applyCloud(list: nil, item: b, listID: listID)
            try store.applyCloud(list: nil, item: a, listID: listID)
            #expect(store.items.first { $0.id == a.id }?.amount == "3")
            a.revision = 11
            a.isDeleted = true
            try store.applyCloud(list: nil, item: a, listID: listID)
            try store.applyCloud(list: nil, item: b, listID: listID)
            #expect(store.items(in: listID).isEmpty)
            let before = store.items
            try store.applyCloud(list: nil, item: a, listID: listID)
            #expect(store.items == before)
        }
    }

    @Test func offlineEditsAndSharedNamesSurviveReload() throws {
        try withStore { store, directory in
            let listID = store.activeLists[0].id
            var item = ShoppingItem(listID: listID, productID: store.activeProducts[0].id,
                                    amount: "4", comment: "Keep", isChecked: true)
            item.sharedDetails = store.sharingDetails(for: item)
            store.save(item)
            let reopened = CleverlistStore(directory: directory)
            #expect(reopened.items == store.items)
            #expect(reopened.items[0].sharedDetails == item.sharedDetails)
        }
    }

    @Test func receivedSharedItemUsesIndependentLocalManualProduct() throws {
        try withStore { store, _ in
            let listID = store.activeLists[0].id
            let sourceProduct = Product(
                name: LocalizedName(sv: "Delad", de: "Geteilt", en: "Shared"),
                typeID: store.catalog(.type)[0].id,
                sectionID: store.catalog(.section)[0].id
            )
            var incoming = ShoppingItem(
                listID: listID,
                productID: sourceProduct.id,
                sharedDetails: SharedItemDetails(product: sourceProduct, terms: [])
            )

            try store.applyCloud(list: nil, item: incoming, listID: listID)

            let received = try #require(store.items.first { $0.id == incoming.id })
            let localProduct = try #require(store.product(received.productID))
            #expect(localProduct.id != sourceProduct.id)
            #expect(localProduct.name == sourceProduct.name)
            #expect(localProduct.sharedProductID == sourceProduct.id)
            #expect(localProduct.typeID == nil)
            #expect(localProduct.sectionID == nil)
            #expect(received.sharedDetails == nil)

            var customized = localProduct
            customized.name = LocalizedName(sv: "Min", de: "Meine", en: "Mine")
            customized.storeIDs = [store.catalog(.store)[0].id]
            customized.typeID = store.catalog(.type)[1].id
            customized.sectionID = store.catalog(.section)[1].id
            store.save(customized)

            incoming.amount = "2"
            incoming.revision = 1
            try store.applyCloud(list: nil, item: incoming, listID: listID)

            let updated = try #require(store.items.first { $0.id == incoming.id })
            #expect(updated.productID == localProduct.id)
            #expect(store.product(updated.productID)?.name == customized.name)
            #expect(store.product(updated.productID)?.storeIDs == customized.storeIDs)
            #expect(store.product(updated.productID)?.typeID == customized.typeID)
            #expect(store.product(updated.productID)?.sectionID == customized.sectionID)

            let secondIncoming = ShoppingItem(
                listID: listID,
                productID: sourceProduct.id,
                sharedDetails: SharedItemDetails(product: sourceProduct, terms: [])
            )
            try store.applyCloud(list: nil, item: secondIncoming, listID: listID)

            let secondReceived = try #require(store.items.first { $0.id == secondIncoming.id })
            #expect(secondReceived.productID == localProduct.id)
            #expect(store.customProducts.filter { $0.sharedProductID == sourceProduct.id }.count == 1)
        }
    }

    @Test func readOnlyAndHiddenListsRejectEdits() throws {
        try withStore { store, _ in
            let list = store.activeLists[0]
            let item = ShoppingItem(listID: list.id, productID: store.activeProducts[0].id)
            store.save(item)
            let before = store.items
            store.readOnlyCloudListIDs.insert(list.id)
            store.delete(item)
            store.save(ShoppingItem(listID: list.id, productID: UUID()))
            #expect(store.items == before)
            store.hiddenCloudListIDs.insert(list.id)
            #expect(store.activeLists.isEmpty)
            #expect(store.items(in: list.id).isEmpty)
            #expect(!store.canEdit(list.id))
        }
    }

    @Test func deletingLocalListDoesNotDeleteSharedList() throws {
        try withStore { store, _ in
            let list = store.activeLists[0]
            store.linkedCloudListIDs.insert(list.id)
            store.delete(list)
            #expect(store.activeLists.contains { $0.id == list.id })
        }
    }

    @Test func removingSharedListKeepsPrivateListAndCatalog() throws {
        try withStore { store, directory in
            let privateList = store.activeLists[0]
            let shared = ShoppingList(name: "Shared")
            store.save(shared)
            store.save(ShoppingItem(listID: shared.id, productID: store.activeProducts[0].id))
            let products = store.products
            try store.removeCloudList(shared.id)
            let reopened = CleverlistStore(directory: directory)
            #expect(reopened.activeLists == [privateList])
            #expect(reopened.items.isEmpty)
            #expect(reopened.products == products)
        }
    }
}
