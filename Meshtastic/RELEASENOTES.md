# 1.27.8

* Added a live Packet Stream mode to the debug log viewer — watch mesh packets flow by in real time, paced for readability and bounded for memory
* Made the log filter's Categories and Log Levels sections collapsible to take less space, with Packet Stream as the top option
* Audited the Mesh log category so it shows only over-the-air packet traffic (configuration, admin, persistence, and device serial output now log under their own categories)
* Update NodeList SwipeAction Button to be role: Destructive
* Added com.apple.security.files.user-selected.read-write entitlement to AppSandbox for MacOS for Mesh log download
* Cleaned up bluetooth connecting timeout errors and logic, run 10 2 second timers now



