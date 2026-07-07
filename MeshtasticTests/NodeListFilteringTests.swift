//
//  NodeListFilteringTests.swift
//  Meshtastic
//
//  Coverage for the off-main node-list filtering path introduced in
//  "perf: move node-list filtering off the main thread" (PR #2055).
//
//  The node LIST view no longer routes through `NodeFilterParameters.matches(...)`
//  (which still backs UserList / MeshMap and is covered by NodeFilterParametersTests).
//  It now uses a separate pipeline in `NodeList.swift`:
//
//    • `makeNodeListPredicate` — the SwiftData `#Predicate` shared by the live `@Query`
//      and the off-main fetch, so the two sets can't drift.
//    • `computeNodeOrder` — runs that fetch off the main actor on a fresh `ModelContext`
//      and returns the matching node `num`s in `lastHeard`-descending order.
//
//  These tests exercise that pipeline directly. Two of them pin the review fixes from
//  the PR:
//
//    • `makeNodeListPredicate(_:applyFavoriteFilter:)` — the off-main fetch drops the
//      `favorite` gate (`applyFavoriteFilter: false`) so it stays a SUPERSET; a node just
//      toggled favorite in the live context can't be hidden by the background context
//      lagging the save. The live `@Query` re-applies the filter.
//    • `computeNodeOrder` returns `[Int64]?` — `nil` only on a fetch throw (so the caller
//      preserves the current list); an empty match set is `[]`, not `nil`.
//
//  The suite shares `sharedModelContainer` with every other SwiftData test, so it never
//  asserts on global counts — only on membership / relative order of its own unique `num`
//  range (8_15x_xxx). `computeNodeOrder` reads through a fresh `ModelContext`, so seeded
//  rows are always saved before the call.
//

import CoreLocation
import Foundation
import SwiftData
import Testing

@testable import Meshtastic

/// Isolated `UserDefaults` suite so the `@AppStorage`-backed filter flags start empty and
/// don't collide with other suites running in parallel.
@MainActor
private func makeIsolatedDefaults(_ suiteName: String) -> UserDefaults {
	let defaults = UserDefaults(suiteName: suiteName)!
	defaults.removePersistentDomain(forName: suiteName)
	return defaults
}

@MainActor
@Suite("Node list off-main filtering", .serialized)
struct NodeListFilteringTests {

	let defaults: UserDefaults

	init() {
		defaults = makeIsolatedDefaults("NodeListFilteringTests")
	}

	// MARK: - Fixtures

	/// Inserts a node with the given scalar attributes into the shared container's main context.
	@discardableResult
	private func makeNode(
		num: Int64,
		favorite: Bool = false,
		ignored: Bool = false,
		viaMqtt: Bool = false,
		hopsAway: Int32 = 0,
		lastHeard: Date? = nil
	) -> NodeInfoEntity {
		let node = NodeInfoEntity()
		node.num = num
		node.id = num
		node.favorite = favorite
		node.ignored = ignored
		node.viaMqtt = viaMqtt
		node.hopsAway = hopsAway
		node.lastHeard = lastHeard
		sharedModelContainer.mainContext.insert(node)
		return node
	}

	/// Attaches a `UserEntity` (search fields / role / pki state) to a node.
	private func attachUser(
		to node: NodeInfoEntity,
		longName: String? = nil,
		shortName: String? = nil,
		role: Int32 = 0,
		pkiEncrypted: Bool = false
	) {
		let user = UserEntity()
		user.num = node.num
		user.userId = "!\(String(node.num, radix: 16))"
		user.longName = longName
		user.shortName = shortName
		user.role = role
		user.pkiEncrypted = pkiEncrypted
		sharedModelContainer.mainContext.insert(user)
		node.user = user
	}

	/// Persists seeded rows so the off-main / fresh-context fetches see them.
	private func save() throws {
		try sharedModelContainer.mainContext.save()
	}

	/// Fetches the `num`s matching a predicate through a fresh context, mirroring how both the
	/// `@Query` and `computeNodeOrder` consume `makeNodeListPredicate`.
	private func fetchNums(_ predicate: Predicate<NodeInfoEntity>) throws -> Set<Int64> {
		let context = ModelContext(sharedModelContainer)
		return Set(try context.fetch(FetchDescriptor<NodeInfoEntity>(predicate: predicate)).map(\.num))
	}

	// MARK: - makeNodeListPredicate: favorite superset (review fix)

	@Test("Favorite filter: applyFavoriteFilter false keeps the fetch a superset")
	func favoriteFilterSupersetWhenNotApplied() throws {
		let favNum: Int64 = 8_150_001
		let plainNum: Int64 = 8_150_002
		makeNode(num: favNum, favorite: true)
		makeNode(num: plainNum, favorite: false)
		try save()

		let filters = NodeFilterParameters(store: defaults)
		filters.isFavorite = true
		let inputs = NodePredicateInputs(filters)

		// Live @Query behavior: favorite gate applied — non-favorite excluded.
		let applied = try fetchNums(makeNodeListPredicate(inputs, applyFavoriteFilter: true))
		#expect(applied.contains(favNum))
		#expect(!applied.contains(plainNum))

		// Off-main fetch behavior: favorite gate dropped — result is a SUPERSET so a just-toggled
		// favorite can never be hidden by the background context lagging the save.
		let superset = try fetchNums(makeNodeListPredicate(inputs, applyFavoriteFilter: false))
		#expect(superset.contains(favNum))
		#expect(superset.contains(plainNum))
	}

	@Test("Favorite filter is applied by default")
	func favoriteFilterAppliedByDefault() throws {
		let favNum: Int64 = 8_150_011
		let plainNum: Int64 = 8_150_012
		makeNode(num: favNum, favorite: true)
		makeNode(num: plainNum, favorite: false)
		try save()

		let filters = NodeFilterParameters(store: defaults)
		filters.isFavorite = true

		let result = try fetchNums(makeNodeListPredicate(NodePredicateInputs(filters)))
		#expect(result.contains(favNum))
		#expect(!result.contains(plainNum))
	}

	// MARK: - makeNodeListPredicate: other filters

	@Test("Ignored filter partitions ignored from non-ignored nodes")
	func ignoredFilterPartitions() throws {
		let normalNum: Int64 = 8_151_001
		let ignoredNum: Int64 = 8_151_002
		makeNode(num: normalNum, ignored: false)
		makeNode(num: ignoredNum, ignored: true)
		try save()

		let showNormal = NodeFilterParameters(store: defaults) // isIgnored defaults false
		let normals = try fetchNums(makeNodeListPredicate(NodePredicateInputs(showNormal)))
		#expect(normals.contains(normalNum))
		#expect(!normals.contains(ignoredNum))

		let showIgnored = NodeFilterParameters(store: defaults)
		showIgnored.isIgnored = true
		let ignored = try fetchNums(makeNodeListPredicate(NodePredicateInputs(showIgnored)))
		#expect(ignored.contains(ignoredNum))
		#expect(!ignored.contains(normalNum))
	}

	@Test("Via LoRa only excludes MQTT nodes; Via MQTT only excludes LoRa nodes")
	func viaTransportFilters() throws {
		let loraNum: Int64 = 8_152_001
		let mqttNum: Int64 = 8_152_002
		makeNode(num: loraNum, viaMqtt: false)
		makeNode(num: mqttNum, viaMqtt: true)
		try save()

		let loraOnly = NodeFilterParameters(store: defaults)
		loraOnly.viaLora = true
		loraOnly.viaMqtt = false
		let lora = try fetchNums(makeNodeListPredicate(NodePredicateInputs(loraOnly)))
		#expect(lora.contains(loraNum))
		#expect(!lora.contains(mqttNum))

		let mqttOnly = NodeFilterParameters(store: defaults)
		mqttOnly.viaLora = false
		mqttOnly.viaMqtt = true
		let mqtt = try fetchNums(makeNodeListPredicate(NodePredicateInputs(mqttOnly)))
		#expect(mqtt.contains(mqttNum))
		#expect(!mqtt.contains(loraNum))
	}

	@Test("Hops filter: direct-only keeps 0-hop nodes; max keeps nodes within range")
	func hopsFilters() throws {
		let directNum: Int64 = 8_153_001
		let twoHopNum: Int64 = 8_153_002
		let fiveHopNum: Int64 = 8_153_003
		makeNode(num: directNum, hopsAway: 0)
		makeNode(num: twoHopNum, hopsAway: 2)
		makeNode(num: fiveHopNum, hopsAway: 5)
		try save()

		// hopsAway == 0.0 -> direct nodes only.
		let directOnly = NodeFilterParameters(store: defaults)
		directOnly.hopsAway = 0.0
		let direct = try fetchNums(makeNodeListPredicate(NodePredicateInputs(directOnly)))
		#expect(direct.contains(directNum))
		#expect(!direct.contains(twoHopNum))
		#expect(!direct.contains(fiveHopNum))

		// hopsAway == 3.0 -> 0 < hops <= 3 (direct excluded).
		let maxThree = NodeFilterParameters(store: defaults)
		maxThree.hopsAway = 3.0
		let within = try fetchNums(makeNodeListPredicate(NodePredicateInputs(maxThree)))
		#expect(within.contains(twoHopNum))
		#expect(!within.contains(directNum))
		#expect(!within.contains(fiveHopNum))
	}

	// MARK: - computeNodeOrder: ordering & post-predicate

	@Test("computeNodeOrder returns matches in lastHeard-descending order")
	func ordersByLastHeardDescending() throws {
		let now = Date()
		let newNum: Int64 = 8_154_001
		let midNum: Int64 = 8_154_002
		let oldNum: Int64 = 8_154_003
		makeNode(num: newNum, lastHeard: now)
		makeNode(num: midNum, lastHeard: now.addingTimeInterval(-3_600))
		makeNode(num: oldNum, lastHeard: now.addingTimeInterval(-7_200))
		try save()

		let snapshot = FilterSnapshot(NodeFilterParameters(store: defaults), activeNodeNum: nil)
		let result = try #require(computeNodeOrder(container: sharedModelContainer, snapshot: snapshot))

		let mine = result.filter { [newNum, midNum, oldNum].contains($0) }
		#expect(mine == [newNum, midNum, oldNum])
	}

	@Test("computeNodeOrder narrows by search term against user fields")
	func searchNarrowsByUserFields() throws {
		let matchNum: Int64 = 8_155_001
		let otherNum: Int64 = 8_155_002
		let match = makeNode(num: matchNum, lastHeard: Date())
		attachUser(to: match, longName: "Zephyr Ridge Repeater")
		let other = makeNode(num: otherNum, lastHeard: Date())
		attachUser(to: other, longName: "Downtown Base")
		try save()

		let filters = NodeFilterParameters(store: defaults)
		filters.searchText = "zephyr" // case-insensitive
		let snapshot = FilterSnapshot(filters, activeNodeNum: nil)
		let result = try #require(computeNodeOrder(container: sharedModelContainer, snapshot: snapshot))

		#expect(result.contains(matchNum))
		#expect(!result.contains(otherNum))
	}

	@Test("computeNodeOrder keeps the favorite fetch a superset end-to-end")
	func computeNodeOrderFavoriteSuperset() throws {
		let favNum: Int64 = 8_156_001
		let plainNum: Int64 = 8_156_002
		makeNode(num: favNum, favorite: true, lastHeard: Date())
		makeNode(num: plainNum, favorite: false, lastHeard: Date())
		try save()

		let filters = NodeFilterParameters(store: defaults)
		filters.isFavorite = true
		let snapshot = FilterSnapshot(filters, activeNodeNum: nil)
		let result = try #require(computeNodeOrder(container: sharedModelContainer, snapshot: snapshot))

		// The off-main pass intentionally returns BOTH (the live @Query enforces the favorite gate
		// when recompute() maps these nums onto live objects) — so a favorite toggled in the live
		// context can't be dropped by a lagging background save.
		#expect(result.contains(favNum))
		#expect(result.contains(plainNum))
	}

	@Test("computeNodeOrder online filter excludes stale nodes")
	func onlineFilterExcludesStale() throws {
		let recentNum: Int64 = 8_157_001
		let staleNum: Int64 = 8_157_002
		makeNode(num: recentNum, lastHeard: Date())
		makeNode(num: staleNum, lastHeard: Date().addingTimeInterval(-10_000)) // older than the 2h window
		try save()

		let filters = NodeFilterParameters(store: defaults)
		filters.isOnline = true
		let snapshot = FilterSnapshot(filters, activeNodeNum: nil)
		let result = try #require(computeNodeOrder(container: sharedModelContainer, snapshot: snapshot))

		#expect(result.contains(recentNum))
		#expect(!result.contains(staleNum))
	}

	@Test("computeNodeOrder returns an empty match set as [], not nil")
	func emptyMatchSetIsNonNil() throws {
		let hiddenNum: Int64 = 8_158_001
		let node = makeNode(num: hiddenNum, lastHeard: Date())
		attachUser(to: node, longName: "Findable Node")
		try save()

		let filters = NodeFilterParameters(store: defaults)
		// A term no seeded node contains — matches nothing, which must be [] (non-nil).
		filters.searchText = "zzz-no-such-node-zzz"
		let snapshot = FilterSnapshot(filters, activeNodeNum: nil)
		let result = try #require(computeNodeOrder(container: sharedModelContainer, snapshot: snapshot))

		#expect(!result.contains(hiddenNum))
	}
}
