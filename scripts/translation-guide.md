# Translation guide

`scripts/translate-catalog.sh` passes this file to Xcode's translation agent with every
batch. What it says here overrides Apple's style guide for the language. Add to it when
a choice is settled, so later runs make the same one.

## The app

Meshtastic is an app for LoRa mesh radios. People use it to message over the mesh,
see nodes on a map, read telemetry and positions, manage channels, and bridge to MQTT.
Most are hobbyists, hikers, preppers and emergency volunteers, often outdoors.

## Never translate

Meshtastic, LoRa, MQTT, BLE, GPS, TAK, CoT, PKC, SNR, GPIO, DFU, API, Wi-Fi,
Bluetooth, IAQ, ATAK, WinTAK, mPWRD-OS, iOS, macOS, CarPlay, SiriKit.

## Everywhere

- Keep format specifiers (`%@`, `%lld`, `%1$@`) and markdown exactly as in English.
- Reuse terms from the language's existing strings, reviewed or machine translated,
  before choosing a new one.
- Use the platform's own words for system features, as Apple does in that language
  (for example "Mitteilungen" for notifications in German).

## Tone

| Language | Tone |
|---|---|
| de | Informal, du-form |
| pt-BR | Informal, você, matching the Brazilian Meshtastic community |
| ko | Formal 합쇼체 |
| es, fr, it, ja, zh-Hans, zh-Hant, zh-Hant-TW | Professional |
| da, pl, ru, sr, uk | Match the existing community translations |

## Settled terms

| Language | English | Use |
|---|---|---|
| de | hop, hops | Hop, Hops (not Sprung, Sprünge) |
| de | notifications | Mitteilungen |
| es | you | tú (not usted) |
| es | mesh | malla |
| es | hop | salto |
| es | beacon | baliza |
| es | preset | preajuste |
| es | traceroute | rastreo de ruta |
| es | modem preset names | Kept in English |
