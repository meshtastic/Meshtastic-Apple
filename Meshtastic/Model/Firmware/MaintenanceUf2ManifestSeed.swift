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
		"ewogICJtYW5pZmVzdFZlcnNpb24iOiAxLAogICJvdGFmaXhSZWxlYXNlVGFnIjogIjAuOS4yLU9U"
		"QUZJWDIuMy1CUDEuNSIsCiAgIm90YWZpeEJhc2UiOiAiaHR0cHM6Ly9naXRodWIuY29tL21lc2h0"
		"YXN0aWMvQWRhZnJ1aXRfblJGNTJfQm9vdGxvYWRlcl9PVEFGSVgvcmVsZWFzZXMvZG93bmxvYWQv"
		"MC45LjItT1RBRklYMi4zLUJQMS41IiwKICAiZXJhc2UiOiB7CiAgICAiczE0MF82XzFfMSI6IHsK"
		"ICAgICAgImZpbGVOYW1lIjogIm5yZl9lcmFzZTIudWYyIiwKICAgICAgInNoYTI1NiI6ICI0Yjc3"
		"OGEzZGVmMTk4NTQ0MTVkYjY0Y2I1MWJmZDI5YzE1YjExY2M0NjAwNjM1M2RkNTE4ZjYyZDA5ZWZl"
		"M2ZlIiwKICAgICAgImV4cGVjdGVkRmlyc3RUYXJnZXRBZGRyZXNzIjogMTU1NjQ4CiAgICB9LAog"
		"ICAgInMxNDBfN18zXzAiOiB7CiAgICAgICJmaWxlTmFtZSI6ICJucmZfZXJhc2Vfc2Q3XzMudWYy"
		"IiwKICAgICAgInNoYTI1NiI6ICIxMzk0MWJlZGNlMDA5ZTYxMjU1YzM3YjE1MjRkMTFjYTYwNGU4"
		"OGMzOGU3NTg4YmI4YjM5MWUyOTk4ZGE0NjhmIiwKICAgICAgImV4cGVjdGVkRmlyc3RUYXJnZXRB"
		"ZGRyZXNzIjogMTU5NzQ0CiAgICB9LAogICAgInJwMjA0MCI6IHsKICAgICAgImZpbGVOYW1lIjog"
		"InBpY29fZXJhc2UudWYyIiwKICAgICAgInNoYTI1NiI6ICIwOGFhN2Q1NjFlOGI4YmYyZjliMDYx"
		"YjM1MDZmYjRkOGYxMzVlODMyZWZlMGYzYWU5NzgyNDFkYjJkYTBjODUzIgogICAgfQogIH0sCiAg"
		"Im90YWZpeEJ5Qm9hcmRJZCI6IHsKICAgICJIVC1uNTI2MiI6IHsKICAgICAgImJvYXJkIjogImhl"
		"bHRlY190MTE0IiwKICAgICAgInNoYTI1NiI6ICJhZTkyZDM1NzdjYjU4ZGQ5YjQzYzliNjFmZmI5"
		"YmZmZmRhMDViMGVjYTQxMTNhMGVjNDJhMzdjZDhiZTUzYjE5IgogICAgfSwKICAgICJNaW5ld1Nl"
		"bWktTVgyNUxFMDEiOiB7CiAgICAgICJib2FyZCI6ICJtaW5ld3NlbWlfbXgyNWxlMDEiLAogICAg"
		"ICAic2hhMjU2IjogImUwOTU2NGZkOGRkMDNmYzI1ZDc2ZGNiNzMyYTAyMTRjNzk2NTNkYTNiMTMw"
		"MjQwOTQ5Yjc4MzI1NGQzZGZjMWIiCiAgICB9LAogICAgIlRSQUNLRVIgTDEiOiB7CiAgICAgICJi"
		"b2FyZCI6ICJ3aW9fdHJhY2tlcl9sMSIsCiAgICAgICJzaGEyNTYiOiAiNzBmYmNlMGVkYTlkNzBk"
		"N2JkOGE0MzY3MDU3YmFkZjVlYzMxMDgzOGJmMzIyMTM3MGQ0NWE1NmYwNDk1NmI5ZSIKICAgIH0s"
		"CiAgICAiV2lzQmxvY2stUkFLNDYzMS1Cb2FyZCI6IHsKICAgICAgImJvYXJkIjogIndpc2NvcmVf"
		"cmFrNDYzMV9ib2FyZCIsCiAgICAgICJzaGEyNTYiOiAiODc0MWJjNjc3YTNjMjRmMjg0MjJjNWZm"
		"YjgwNzYxZGU3ZDk4YTEyN2EzYjAxOTFiYTY1ODViZjU3Y2U5ZjMwNSIKICAgIH0sCiAgICAiV2lz"
		"TWVzaC1UYWciOiB7CiAgICAgICJib2FyZCI6ICJ3aXNtZXNoX3RhZyIsCiAgICAgICJzaGEyNTYi"
		"OiAiOTZkNDJlMTk5MGUxNzI1MWU4YzYyNWU5OGExNTUxY2FjMTJjNmUyOTExMWJjMmU1OWFiN2M5"
		"ZmU2ZGVjODc1OCIKICAgIH0sCiAgICAiblJGNTI4NDAtU2VlZWRTZW5zZUNBUFNvbGFyUDEtdjEi"
		"OiB7CiAgICAgICJib2FyZCI6ICJzZW5zZWNhcF9zb2xhcl9wMSIsCiAgICAgICJzaGEyNTYiOiAi"
		"OWI0YmNlNDhjMWI0ODMwNjE3NzE1YzU2MTk0NTdiY2U2YjIxZjMwNzk4MDNlMzVlMTM0MzNkZTc3"
		"MDEyOTBmNSIKICAgIH0sCiAgICAiblJGNTI4NDAtU2VlZWRYaWFvLXYxIjogewogICAgICAiYm9h"
		"cmQiOiAieGlhb19ucmY1Mjg0MF9ibGUiLAogICAgICAic2hhMjU2IjogImZmOGEwOTE2ZTk4Y2Nl"
		"YjM5NGZkNjY1OTBiY2NjMTdmNjM2MTJjMTFmZjU2YjA4NmVmODhiZDQzNmM4ZGY2N2YiCiAgICB9"
		"LAogICAgIm5SRjUyODQwLVNlZWVkWGlhb1NlbnNlLXYxIjogewogICAgICAiYm9hcmQiOiAieGlh"
		"b19ucmY1Mjg0MF9ibGVfc2Vuc2UiLAogICAgICAic2hhMjU2IjogImZjMjMzZDgzYTEwMTE0MTk2"
		"MjVmY2I1MGI0OTA4NDU3ODQ2MGMyNWJiYzAyNzAzNzRjYTE3Njc1N2EzYzQwZGEiCiAgICB9LAog"
		"ICAgIm5SRjUyODQwLVQxMDAwLUUtdjEiOiB7CiAgICAgICJib2FyZCI6ICJ0MTAwMF9lIiwKICAg"
		"ICAgInNoYTI1NiI6ICI1YzA2NWUxMWI4YWNkNWIwY2VmYTkyOTVmOThiY2ExNTEyMzA2Y2ZhNDc4"
		"ODU2YWE3NmE4NzExMjRhOTA0Y2M0IgogICAgfSwKICAgICJuUkY1Mjg0MC1URWNoby12MSI6IHsK"
		"ICAgICAgImJvYXJkIjogImxpbHlnb190ZWNobyIsCiAgICAgICJzaGEyNTYiOiAiMmRkYjM2MTg4"
		"ZmZlNTIxYzI3MGJiMmNlODQ0MWQ3NDJkMGZlNDUzMjVjNTdlNGRiNjQ3NWJmNjMxNjJhNTliMCIK"
		"ICAgIH0sCiAgICAiblJGNTI4NDAtVGhpbmtOb2RlLU0zLXYxIjogewogICAgICAiYm9hcmQiOiAi"
		"dGhpbmtub2RlX20zIiwKICAgICAgInNoYTI1NiI6ICJiZjkwOTc5ZjJmNmFkYzk2ZWY2Y2EwOWMy"
		"ODBiMmFiN2U2NmNiOGNlMjY1NGZjODBkYTliMjA0MDdiZmI4NzA4IgogICAgfSwKICAgICJuUkY1"
		"Mjg0MC1UaGlua05vZGVNMS12MSI6IHsKICAgICAgImJvYXJkIjogInRoaW5rbm9kZV9tMSIsCiAg"
		"ICAgICJzaGEyNTYiOiAiYWEwNzIxYjU3M2M2MGUwYjE3OTI3NGQ1YTUyOTZiYWM3YTg0MzZmYWYz"
		"MzljZmMwMzExNmViZThhNDM3NTc5NSIKICAgIH0sCiAgICAiblJGNTI4NDAtVGhpbmtOb2RlTTYt"
		"djEiOiB7CiAgICAgICJib2FyZCI6ICJ0aGlua25vZGVfbTYiLAogICAgICAic2hhMjU2IjogImFh"
		"Zjk0OTUzYTU0MGExOGYzZTQ4ZjRjZGVjMGM3ODI5MGFkM2M1Zjg3NDBhZWEyNmZhM2IzY2UzNjMy"
		"YThkNGEiCiAgICB9LAogICAgIm5SRjUyODQwLXByb21pY3JvIjogewogICAgICAiYm9hcmQiOiAi"
		"cHJvbWljcm9fbnJmNTI4NDAiLAogICAgICAic2hhMjU2IjogIjQ2ZWYzNDQwZjE1MWQ2ZjI2MDYw"
		"NzViY2QxYWE4M2RiMjVhNjYwZGE3ZDI1Yjk4OGFlYjQ3ZWYzNTBjOTg3OTQiCiAgICB9CiAgfSwK"
		"ICAib3RhZml4U3VwcG9ydGVkVGFyZ2V0cyI6IFsKICAgICJyYWs0NjMxIiwKICAgICJyYWtfd2lz"
		"bWVzaHRhZyIsCiAgICAidC1lY2hvIiwKICAgICJoZWx0ZWMtbWVzaC1ub2RlLXQxMTQiLAogICAg"
		"Im5yZjUyX3Byb21pY3JvX2RpeV90Y3hvIiwKICAgICJ0aGlua25vZGVfbTEiLAogICAgInRoaW5r"
		"bm9kZV9tMyIsCiAgICAidGhpbmtub2RlX202IiwKICAgICJ0cmFja2VyLXQxMDAwLWUiLAogICAg"
		"InNlZWVkX3dpb190cmFja2VyX0wxIiwKICAgICJzZWVlZF93aW9fdHJhY2tlcl9MMV9laW5rIiwK"
		"ICAgICJzZWVlZF9zb2xhcl9ub2RlIiwKICAgICJzZWVlZF94aWFvX25yZjUyODQwX2tpdCIKICBd"
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
