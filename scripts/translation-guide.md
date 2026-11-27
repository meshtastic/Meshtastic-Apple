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
| es, fr, it, ja, tr, zh-Hans, zh-Hant, zh-Hant-TW | Professional, siz-form in Turkish |
| pl | Informal, ty-form, matching the Meshtastic Android Polish translation |
| tr | Natural, concise technical Turkish (polite *siz* or neutral imperative in UI labels, matching Apple's Turkish UI conventions) |
| da, ru, sr, uk | Match the existing community translations |

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
| pl | hop, hops | skok, skoki |
| pl | beacon | beacon (kept in English) |
| pl | preset, modem preset names | preset, names kept in English |
| pl | spread factor, coding rate, duty cycle | Kept in English |
| pl | device roles (CLIENT, ROUTER…) | Kept in English |
| pl | Store & Forward, PAX Counter, Range Test, Mesh Beacon, Lockdown | Kept in English |
| pl | node | węzeł |
| pl | Neighbor Info | Info o sąsiadach |
| pl | Local Mesh Discovery | Wykrywanie lokalnych sieci |
| pl | Off-Grid Messaging | Komunikacja off-grid |
| pl | Trace Route | Śledzenie trasy |
| pl | Local Stats | Statystyki lokalne |
| pl | Device/Power/Environment Metrics | metryki urządzenia, metryki zasilania, metryki środowiskowe |
| pl | Host Metrics | Statystyki hosta |
| pl | logs | logi (for example "Logi metryk urządzenia") |
| pl | Remote admin | Zdalne zarządzanie |
| pl | Exchange Positions | Poproś o pozycję |
| pl | Live Activity | Aktywność na żywo |
| pl | Points of Interest | Ciekawe miejsca |
| pl | firmware update | aktualizacja oprogramowania |
| tr | notifications | Bildirimler (Apple platform term) |
| tr | node, nodes | düğüm, düğümler |
| tr | hop, hops | atlama, atlamalar |
| tr | mesh | mesh (or mesh ağı where clarity helps) |
| tr | beacon | işaret (or beacon in technical labels) |
| tr | preset, modem preset names | ön ayar; modem preset names kept in English |
| tr | spread factor, coding rate, duty cycle | Kept in English (or yayılma faktörü / kodlama oranı in explanatory help text) |
| tr | device roles (CLIENT, ROUTER…) | Kept in English |
| tr | Store & Forward, PAX Counter, Range Test, Mesh Beacon, Lockdown | Kept in English |
| tr | Neighbor Info | Komşu Bilgisi |
| tr | Trace Route | Rota İzleme |
| tr | Local Stats | Yerel İstatistikler |
| tr | Device/Power/Environment Metrics | Cihaz / Güç / Ortam Metrikleri |
| tr | Host Metrics | Ana Bilgisayar Metrikleri |
| tr | logs | günlükler |
| tr | Remote admin | Uzaktan yönetim |
| tr | Live Activity | Canlı Etkinlik (Apple platform term) |
| tr | Points of Interest | İlgi Çekici Noktalar |
| tr | firmware update | aygıt yazılımı güncellemesi |
