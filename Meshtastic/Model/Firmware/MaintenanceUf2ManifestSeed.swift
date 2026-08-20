//
//  MaintenanceUf2ManifestSeed.swift
//  Meshtastic
//
//  Bundled seed copy of api.meshtastic.org's `resource/maintenanceUf2` manifest — the OTAFIX
//  board map and pinned digests MaintenanceUF2.swift used to hardcode directly, mirrored verbatim
//  from Meshtastic-Android's own device_bootloader_ota_quirks-adjacent manifest via the shared
//  `meshtastic/api` endpoint (see api/data/maintenanceUf2.json, api/src/lib/maintenanceUf2.ts).
//
//  Stored as base64-encoded Swift source rather than a bundled JSON resource file: this project's
//  resource files are individually registered in project.yml + project.pbxproj (regenerated via
//  `xcodegen generate`), which isn't available in every environment that touches this branch —
//  whereas `Meshtastic/Model` is an Xcode "synced folder" group, so a new .swift file here needs
//  no project-file regeneration at all. Base64 (not a Swift string literal of the raw JSON) avoids
//  any ambiguity from multiline-string-literal newline trimming corrupting the exact bytes a
//  digest is computed over — see MaintenanceUf2ManifestSeedTests for the byte-fidelity assertion.
//
//  Do not hand-edit the encoded payload. Regenerate it by base64-encoding
//  api/data/maintenanceUf2.json (e.g. `base64 -i api/data/maintenanceUf2.json`), re-wrapping at
//  76 chars/line, then update MaintenanceUF2.expectedManifestSHA256 to match.
//

import Foundation

enum MaintenanceUf2ManifestSeed {

	/// Byte-identical to the `api/data/maintenanceUf2.json` this was generated from.
	static let rawJSON: Data = {
		let base64Chunks: [String] = [
		"ewogICJtYW5pZmVzdFZlcnNpb24iOiAxLAogICJvdGFmaXhSZWxlYXNlVGFnIjogIjAuOS4yLU9U",
		"QUZJWDIuMy1CUDEuNSIsCiAgIm90YWZpeEJhc2UiOiAiaHR0cHM6Ly9naXRodWIuY29tL21lc2h0",
		"YXN0aWMvQWRhZnJ1aXRfblJGNTJfQm9vdGxvYWRlcl9PVEFGSVgvcmVsZWFzZXMvZG93bmxvYWQv",
		"MC45LjItT1RBRklYMi4zLUJQMS41IiwKICAiZXJhc2UiOiB7CiAgICAibnJmNTIiOiB7CiAgICAg",
		"ICI2LjEuMSI6IHsKICAgICAgICAiZmlsZU5hbWUiOiAibnJmX2VyYXNlMi51ZjIiLAogICAgICAg",
		"ICJzaGEyNTYiOiAiNGI3NzhhM2RlZjE5ODU0NDE1ZGI2NGNiNTFiZmQyOWMxNWIxMWNjNDYwMDYz",
		"NTNkZDUxOGY2MmQwOWVmZTNmZSIsCiAgICAgICAgImV4cGVjdGVkRmlyc3RUYXJnZXRBZGRyZXNz",
		"IjogMTU1NjQ4CiAgICAgIH0sCiAgICAgICI3LjMuMCI6IHsKICAgICAgICAiZmlsZU5hbWUiOiAi",
		"bnJmX2VyYXNlX3NkN18zLnVmMiIsCiAgICAgICAgInNoYTI1NiI6ICIxMzk0MWJlZGNlMDA5ZTYx",
		"MjU1YzM3YjE1MjRkMTFjYTYwNGU4OGMzOGU3NTg4YmI4YjM5MWUyOTk4ZGE0NjhmIiwKICAgICAg",
		"ICAiZXhwZWN0ZWRGaXJzdFRhcmdldEFkZHJlc3MiOiAxNTk3NDQKICAgICAgfQogICAgfSwKICAg",
		"ICJycDIwNDAiOiB7CiAgICAgICJmaWxlTmFtZSI6ICJwaWNvX2VyYXNlLnVmMiIsCiAgICAgICJz",
		"aGEyNTYiOiAiMDhhYTdkNTYxZThiOGJmMmY5YjA2MWIzNTA2ZmI0ZDhmMTM1ZTgzMmVmZTBmM2Fl",
		"OTc4MjQxZGIyZGEwYzg1MyIKICAgIH0KICB9LAogICJvdGFmaXhCeUJvYXJkSWQiOiB7CiAgICAi",
		"SFQtbjUyNjIiOiB7CiAgICAgICJvdGFmaXhCb2FyZFNsdWciOiAiaGVsdGVjX3QxMTQiLAogICAg",
		"ICAic2hhMjU2IjogImFlOTJkMzU3N2NiNThkZDliNDNjOWI2MWZmYjliZmZmZGEwNWIwZWNhNDEx",
		"M2EwZWM0MmEzN2NkOGJlNTNiMTkiCiAgICB9LAogICAgIk1pbmV3U2VtaS1NWDI1TEUwMSI6IHsK",
		"ICAgICAgIm90YWZpeEJvYXJkU2x1ZyI6ICJtaW5ld3NlbWlfbXgyNWxlMDEiLAogICAgICAic2hh",
		"MjU2IjogImUwOTU2NGZkOGRkMDNmYzI1ZDc2ZGNiNzMyYTAyMTRjNzk2NTNkYTNiMTMwMjQwOTQ5",
		"Yjc4MzI1NGQzZGZjMWIiCiAgICB9LAogICAgIlRSQUNLRVIgTDEiOiB7CiAgICAgICJvdGFmaXhC",
		"b2FyZFNsdWciOiAid2lvX3RyYWNrZXJfbDEiLAogICAgICAic2hhMjU2IjogIjcwZmJjZTBlZGE5",
		"ZDcwZDdiZDhhNDM2NzA1N2JhZGY1ZWMzMTA4MzhiZjMyMjEzNzBkNDVhNTZmMDQ5NTZiOWUiCiAg",
		"ICB9LAogICAgIldpc0Jsb2NrLVJBSzQ2MzEtQm9hcmQiOiB7CiAgICAgICJvdGFmaXhCb2FyZFNs",
		"dWciOiAid2lzY29yZV9yYWs0NjMxX2JvYXJkIiwKICAgICAgInNoYTI1NiI6ICI4NzQxYmM2Nzdh",
		"M2MyNGYyODQyMmM1ZmZiODA3NjFkZTdkOThhMTI3YTNiMDE5MWJhNjU4NWJmNTdjZTlmMzA1Igog",
		"ICAgfSwKICAgICJXaXNNZXNoLVRhZyI6IHsKICAgICAgIm90YWZpeEJvYXJkU2x1ZyI6ICJ3aXNt",
		"ZXNoX3RhZyIsCiAgICAgICJzaGEyNTYiOiAiOTZkNDJlMTk5MGUxNzI1MWU4YzYyNWU5OGExNTUx",
		"Y2FjMTJjNmUyOTExMWJjMmU1OWFiN2M5ZmU2ZGVjODc1OCIKICAgIH0sCiAgICAiblJGNTI4NDAt",
		"U2VlZWRTZW5zZUNBUFNvbGFyUDEtdjEiOiB7CiAgICAgICJvdGFmaXhCb2FyZFNsdWciOiAic2Vu",
		"c2VjYXBfc29sYXJfcDEiLAogICAgICAic2hhMjU2IjogIjliNGJjZTQ4YzFiNDgzMDYxNzcxNWM1",
		"NjE5NDU3YmNlNmIyMWYzMDc5ODAzZTM1ZTEzNDMzZGU3NzAxMjkwZjUiCiAgICB9LAogICAgIm5S",
		"RjUyODQwLVNlZWVkWGlhby12MSI6IHsKICAgICAgIm90YWZpeEJvYXJkU2x1ZyI6ICJ4aWFvX25y",
		"ZjUyODQwX2JsZSIsCiAgICAgICJzaGEyNTYiOiAiZmY4YTA5MTZlOThjY2ViMzk0ZmQ2NjU5MGJj",
		"Y2MxN2Y2MzYxMmMxMWZmNTZiMDg2ZWY4OGJkNDM2YzhkZjY3ZiIKICAgIH0sCiAgICAiblJGNTI4",
		"NDAtU2VlZWRYaWFvU2Vuc2UtdjEiOiB7CiAgICAgICJvdGFmaXhCb2FyZFNsdWciOiAieGlhb19u",
		"cmY1Mjg0MF9ibGVfc2Vuc2UiLAogICAgICAic2hhMjU2IjogImZjMjMzZDgzYTEwMTE0MTk2MjVm",
		"Y2I1MGI0OTA4NDU3ODQ2MGMyNWJiYzAyNzAzNzRjYTE3Njc1N2EzYzQwZGEiCiAgICB9LAogICAg",
		"Im5SRjUyODQwLVQxMDAwLUUtdjEiOiB7CiAgICAgICJvdGFmaXhCb2FyZFNsdWciOiAidDEwMDBf",
		"ZSIsCiAgICAgICJzaGEyNTYiOiAiNWMwNjVlMTFiOGFjZDViMGNlZmE5Mjk1Zjk4YmNhMTUxMjMw",
		"NmNmYTQ3ODg1NmFhNzZhODcxMTI0YTkwNGNjNCIKICAgIH0sCiAgICAiblJGNTI4NDAtVEVjaG8t",
		"djEiOiB7CiAgICAgICJvdGFmaXhCb2FyZFNsdWciOiAibGlseWdvX3RlY2hvIiwKICAgICAgInNo",
		"YTI1NiI6ICIyZGRiMzYxODhmZmU1MjFjMjcwYmIyY2U4NDQxZDc0MmQwZmU0NTMyNWM1N2U0ZGI2",
		"NDc1YmY2MzE2MmE1OWIwIgogICAgfSwKICAgICJuUkY1Mjg0MC1UaGlua05vZGUtTTMtdjEiOiB7",
		"CiAgICAgICJvdGFmaXhCb2FyZFNsdWciOiAidGhpbmtub2RlX20zIiwKICAgICAgInNoYTI1NiI6",
		"ICJiZjkwOTc5ZjJmNmFkYzk2ZWY2Y2EwOWMyODBiMmFiN2U2NmNiOGNlMjY1NGZjODBkYTliMjA0",
		"MDdiZmI4NzA4IgogICAgfSwKICAgICJuUkY1Mjg0MC1UaGlua05vZGVNMS12MSI6IHsKICAgICAg",
		"Im90YWZpeEJvYXJkU2x1ZyI6ICJ0aGlua25vZGVfbTEiLAogICAgICAic2hhMjU2IjogImFhMDcy",
		"MWI1NzNjNjBlMGIxNzkyNzRkNWE1Mjk2YmFjN2E4NDM2ZmFmMzM5Y2ZjMDMxMTZlYmU4YTQzNzU3",
		"OTUiCiAgICB9LAogICAgIm5SRjUyODQwLVRoaW5rTm9kZU02LXYxIjogewogICAgICAib3RhZml4",
		"Qm9hcmRTbHVnIjogInRoaW5rbm9kZV9tNiIsCiAgICAgICJzaGEyNTYiOiAiYWFmOTQ5NTNhNTQw",
		"YTE4ZjNlNDhmNGNkZWMwYzc4MjkwYWQzYzVmODc0MGFlYTI2ZmEzYjNjZTM2MzJhOGQ0YSIKICAg",
		"IH0sCiAgICAiblJGNTI4NDAtcHJvbWljcm8iOiB7CiAgICAgICJvdGFmaXhCb2FyZFNsdWciOiAi",
		"cHJvbWljcm9fbnJmNTI4NDAiLAogICAgICAic2hhMjU2IjogIjQ2ZWYzNDQwZjE1MWQ2ZjI2MDYw",
		"NzViY2QxYWE4M2RiMjVhNjYwZGE3ZDI1Yjk4OGFlYjQ3ZWYzNTBjOTg3OTQiCiAgICB9CiAgfSwK",
		"ICAib3RhZml4U3VwcG9ydGVkVGFyZ2V0cyI6IFsKICAgICJyYWs0NjMxIiwKICAgICJyYWtfd2lz",
		"bWVzaHRhZyIsCiAgICAidC1lY2hvIiwKICAgICJoZWx0ZWMtbWVzaC1ub2RlLXQxMTQiLAogICAg",
		"Im5yZjUyX3Byb21pY3JvX2RpeV90Y3hvIiwKICAgICJ0aGlua25vZGVfbTEiLAogICAgInRoaW5r",
		"bm9kZV9tMyIsCiAgICAidGhpbmtub2RlX202IiwKICAgICJ0cmFja2VyLXQxMDAwLWUiLAogICAg",
		"InNlZWVkX3dpb190cmFja2VyX0wxIiwKICAgICJzZWVlZF93aW9fdHJhY2tlcl9MMV9laW5rIiwK",
		"ICAgICJzZWVlZF9zb2xhcl9ub2RlIiwKICAgICJzZWVlZF94aWFvX25yZjUyODQwX2tpdCIKICBd",
		"Cn0K"
		]
		guard let data = Data(base64Encoded: base64Chunks.joined()) else {
			// Cannot happen for a compile-time-constant, tool-generated payload — a corrupt build
			// would fail here loudly rather than silently seeding an empty manifest.
			fatalError("MaintenanceUf2ManifestSeed.rawJSON failed to base64-decode")
		}
		return data
	}()
}
