import subprocess

# Get stage 3 (origin/2.7.10) as our base
result = subprocess.run(['git', 'show', ':3:Meshtastic/Persistence/UpdateCoreData.swift'], 
                      capture_output=True, text=True, 
                      cwd='/home/runner/work/Meshtastic-Apple/Meshtastic-Apple')
content = result.stdout

# Fix 1: Update the async clearCoreDataDatabase to add includeAppLevelData parameter
content = content.replace(
    '\tpublic func clearCoreDataDatabase(includeRoutes: Bool) async {\n\t\tlet context = self.backgroundContext\n\t\tawait context.perform {\n\t\t\tself.clearCoreDataDatabase(context: context, includeRoutes: includeRoutes)',
    '\tpublic func clearCoreDataDatabase(includeRoutes: Bool, includeAppLevelData: Bool = false) async {\n\t\tlet context = self.backgroundContext\n\t\tawait context.perform {\n\t\t\tself.clearCoreDataDatabase(context: context, includeRoutes: includeRoutes, includeAppLevelData: includeAppLevelData)'
)

# Fix 2: Update the nonisolated clearCoreDataDatabase to add includeAppLevelData and use new logic
old_clear = '''\tnonisolated public func clearCoreDataDatabase(context: NSManagedObjectContext, includeRoutes: Bool) {
let persistenceController = PersistenceController.shared.container
for i in 0...persistenceController.managedObjectModel.entities.count-1 {

let entity = persistenceController.managedObjectModel.entities[i]
let query = NSFetchRequest<NSFetchRequestResult>(entityName: entity.name!)
var deleteRequest = NSBatchDeleteRequest(fetchRequest: query)
let entityName = entity.name ?? "UNK"

if includeRoutes {
deleteRequest = NSBatchDeleteRequest(fetchRequest: query)
} else if !includeRoutes {
if !(entityName.contains("RouteEntity") || entityName.contains("LocationEntity")) {
deleteRequest = NSBatchDeleteRequest(fetchRequest: query)
}
}
do {
try context.executeAndMergeChanges(using: deleteRequest)
} catch {
Logger.data.error("\\(error.localizedDescription, privacy: .public)")
}
}
}'''
new_clear = '''\tnonisolated public func clearCoreDataDatabase(context: NSManagedObjectContext, includeRoutes: Bool, includeAppLevelData: Bool = false) {
let persistenceController = PersistenceController.shared.container
for i in 0...persistenceController.managedObjectModel.entities.count-1 {

let entity = persistenceController.managedObjectModel.entities[i]
let query = NSFetchRequest<NSFetchRequestResult>(entityName: entity.name!)
let entityName = entity.name ?? "UNK"

if !includeRoutes, ["RouteEntity", "LocationEntity"].contains(entityName) {
continue
}

if !includeAppLevelData, ["DeviceHardwareEntity", "DeviceHardwareImageEntity", "DeviceHardwareTagEntity"].contains(entityName) {
// These are non-node-specific "app level" data, keep them even when switching nodes
continue
}

// Execute the delete for this entry
let deleteRequest = NSBatchDeleteRequest(fetchRequest: query)
do {
try context.executeAndMergeChanges(using: deleteRequest)
} catch {
Logger.data.error("\\(error.localizedDescription, privacy: .public)")
}
}
}'''
content = content.replace(old_clear, new_clear)

# Fix 3: Replace first Api().loadDeviceHardwareData block (new node insert)
old_hw1 = '''\t\t\t\t\tTask {
Api().loadDeviceHardwareData { (hw) in
let dh = hw.first(where: { $0.hwModel == newUser.hwModelId })
newUser.hwDisplayName = dh?.displayName
}
}
newNode.user = newUser'''
new_hw1 = '''\t\t\t\t\tlet fetchRequest = DeviceHardwareEntity.fetchRequest()
fetchRequest.predicate = NSPredicate(format: "hwModel == %d", newUser.hwModelId)
let fetchedHardware = try context.fetch(fetchRequest)
if let hardwareEntity = fetchedHardware.first {
newUser.hwDisplayName = hardwareEntity.displayName
}
newNode.user = newUser'''
content = content.replace(old_hw1, new_hw1)

# Fix 4: Replace second Api().loadDeviceHardwareData block (existing node update)
old_hw2 = '''\t\t\t\t\tTask {
Api().loadDeviceHardwareData { (hw) in
let dh = hw.first(where: { $0.hwModel == fetchedNode[0].user?.hwModelId ?? 0 })
fetchedNode[0].user?.hwDisplayName = dh?.displayName
}
}
}
} else if packet.hopStart != 0 && packet.hopLimit <= packet.hopStart {'''
new_hw2 = '''\t\t\t\t\tif let user = fetchedNode.first?.user {
let fetchRequest = DeviceHardwareEntity.fetchRequest()
fetchRequest.predicate = NSPredicate(format: "hwModel == %d", user.hwModelId)
let fetchedHardware = try context.fetch(fetchRequest)
if let hardwareEntity = fetchedHardware.first {
user.hwDisplayName = hardwareEntity.displayName
}
}
}
} else if packet.hopStart != 0 && packet.hopLimit <= packet.hopStart {'''
content = content.replace(old_hw2, new_hw2)

with open('Meshtastic/Persistence/UpdateCoreData.swift', 'w') as f:
    f.write(content)

# Verify
import sys
if '<<<<<<' in content:
    print("ERROR: Conflict markers remain!")
    sys.exit(1)
else:
    print("Done - no conflict markers")
    print(f"Lines: {len(content.splitlines())}")
