//
//  SettingsNodeSortTests.swift
//  Meshtastic
//
//  Regression coverage for the admin / configuration node Picker ordering in
//  `Settings.swift`. The CoreData→SwiftData conversion (PR #1668) collapsed a
//  multi-key `@FetchRequest` sort down to `@Query(sort: \.lastHeard, .reverse)`,
//  which dropped `favorite` as a sort key — favorited nodes stopped appearing at
//  the top of the list.
//
//  Favorite-on-top can't be a SwiftData `SortDescriptor` key (`favorite` is a
//  `Bool`, and `Bool` isn't `Comparable`), so the view restores it in memory via
//  `NodeInfoEntity.adminPickerOrder(_:)`: a stable favorites-first partition over
//  the `@Query`'s already-`lastHeard`-descending results. These tests feed that
//  helper inputs ordered the way the `@Query` delivers them (recency descending)
//  and assert favorites are hoisted while recency order is preserved within each
//  group.
//

import Foundation
import Testing

@testable import Meshtastic

@MainActor
@Suite("Settings admin node sort")
struct SettingsNodeSortTests {

	/// Builds a node with the given favorite flag. `lastHeard` is set for realism but
	/// the partition helper relies on input order, not the value itself.
	private func makeNode(num: Int64, favorite: Bool, lastHeard: Date? = nil) -> NodeInfoEntity {
		let node = NodeInfoEntity()
		node.num = num
		node.id = num
		node.favorite = favorite
		node.lastHeard = lastHeard
		return node
	}

	/// Applies the production ordering helper and returns the resulting `num` order.
	private func orderedNums(_ nodes: [NodeInfoEntity]) -> [Int64] {
		NodeInfoEntity.adminPickerOrder(nodes).map(\.num)
	}

	// MARK: - Tests

	@Test("Favorites are hoisted above non-favorites regardless of recency")
	func favoritesAboveNonFavorites() {
		// As the @Query delivers them: most-recent first. The favorite is the *older*
		// node, so a plain recency order would bury it — the partition must hoist it.
		// This is the exact regression.
		let freshPlain = makeNode(num: 7_700_002, favorite: false)
		let staleFavorite = makeNode(num: 7_700_001, favorite: true)

		#expect(orderedNums([freshPlain, staleFavorite]) == [7_700_001, 7_700_002])
	}

	@Test("Recency order is preserved within the favorites group")
	func recencyPreservedAmongFavorites() {
		// Input is already recency-descending (newer first), as the @Query provides.
		let newerFavorite = makeNode(num: 7_710_002, favorite: true)
		let olderFavorite = makeNode(num: 7_710_001, favorite: true)

		#expect(orderedNums([newerFavorite, olderFavorite]) == [7_710_002, 7_710_001])
	}

	@Test("Recency order is preserved within the non-favorites group")
	func recencyPreservedAmongNonFavorites() {
		let newerPlain = makeNode(num: 7_720_002, favorite: false)
		let olderPlain = makeNode(num: 7_720_001, favorite: false)

		#expect(orderedNums([newerPlain, olderPlain]) == [7_720_002, 7_720_001])
	}

	@Test("Full ordering: favorites first (recency preserved), then non-favorites (recency preserved)")
	func combinedOrdering() {
		// Interleaved and recency-descending within each favorite state, as the
		// @Query delivers: favNew, plainNew, favOld, plainOld.
		let favNew = makeNode(num: 7_730_002, favorite: true)
		let plainNew = makeNode(num: 7_730_004, favorite: false)
		let favOld = makeNode(num: 7_730_001, favorite: true)
		let plainOld = makeNode(num: 7_730_003, favorite: false)

		let order = orderedNums([favNew, plainNew, favOld, plainOld])
		#expect(order == [7_730_002, 7_730_001, 7_730_004, 7_730_003])
	}

	@Test("A never-heard favorite still sorts above a recently-heard non-favorite")
	func favoriteNeverHeardStillFirst() {
		// The @Query orders nil lastHeard last, so a never-heard favorite arrives
		// after the fresh non-favorite; the partition must still hoist it.
		let freshPlain = makeNode(num: 7_740_002, favorite: false, lastHeard: Date(timeIntervalSince1970: 1_700_000_000))
		let favoriteNeverHeard = makeNode(num: 7_740_001, favorite: true, lastHeard: nil)

		#expect(orderedNums([freshPlain, favoriteNeverHeard]) == [7_740_001, 7_740_002])
	}

	@Test("Ordering is a no-op when nodes are already favorites-first")
	func alreadyOrderedIsStable() {
		let fav = makeNode(num: 7_750_001, favorite: true)
		let plain = makeNode(num: 7_750_002, favorite: false)

		#expect(orderedNums([fav, plain]) == [7_750_001, 7_750_002])
	}

	@Test("Empty input yields empty output")
	func emptyInput() {
		#expect(orderedNums([]) == [])
	}
}
