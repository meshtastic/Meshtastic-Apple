import subprocess

# Get stage 3 (origin/2.7.10) as our base
result = subprocess.run(['git', 'show', ':3:Meshtastic/Helpers/MeshPackets.swift'], 
                      capture_output=True, text=True, 
                      cwd='/home/runner/work/Meshtastic-Apple/Meshtastic-Apple')
content = result.stdout

# Fix 1: Add pioEnv after deviceId in the insert path of myInfoPacket
content = content.replace(
    '\t\t\t\t\tmyInfoEntity.deviceId = myInfo.deviceID\n\t\t\t\t\tdo {\n\t\t\t\t\t\ttry context.save()\n\t\t\t\t\t\tLogger.data.info("💾 Saved a new myInfo',
    '\t\t\t\t\tmyInfoEntity.deviceId = myInfo.deviceID\n\t\t\t\t\tmyInfoEntity.pioEnv = myInfo.pioEnv\n\t\t\t\t\t\n\t\t\t\t\tdo {\n\t\t\t\t\t\ttry context.save()\n\t\t\t\t\t\tLogger.data.info("💾 Saved a new myInfo'
)

# Fix 2: Add pioEnv in the update path of myInfoPacket  
content = content.replace(
    '\t\t\t\t\tfetchedMyInfo[0].rebootCount = Int32(myInfo.rebootCount)\n\t\t\t\t\t\n\t\t\t\t\tdo {\n\t\t\t\t\t\ttry context.save()\n\t\t\t\t\t\tLogger.data.info("💾 Updated myInfo',
    '\t\t\t\t\tfetchedMyInfo[0].rebootCount = Int32(myInfo.rebootCount)\n\t\t\t\t\tfetchedMyInfo[0].pioEnv = myInfo.pioEnv\n\t\t\t\t\t\n\t\t\t\t\tdo {\n\t\t\t\t\t\ttry context.save()\n\t\t\t\t\t\tLogger.data.info("💾 Updated myInfo'
)

# Fix 3: Replace first Api().loadDeviceHardwareData block (new node insert)
old_hw1 = '''\t\t\t\t\tnewUser.hwModelId = Int32(nodeInfo.user.hwModel.rawValue)
Task {
Api().loadDeviceHardwareData { (hw) in
let dh = hw.first(where: { $0.hwModel == newUser.hwModelId })
newUser.hwDisplayName = dh?.displayName
}
}
newUser.isLicensed'''
new_hw1 = '''\t\t\t\t\tnewUser.hwModelId = Int32(nodeInfo.user.hwModel.rawValue)

let fetchRequest = DeviceHardwareEntity.fetchRequest()
fetchRequest.predicate = NSPredicate(format: "hwModel == %d", newUser.hwModelId)
let fetchedHardware = try context.fetch(fetchRequest)
if let hardwareEntity = fetchedHardware.first {
newUser.hwDisplayName = hardwareEntity.displayName
}

newUser.isLicensed'''
content = content.replace(old_hw1, new_hw1)

# Fix 4: Replace second Api().loadDeviceHardwareData block (existing node update)
old_hw2 = '''\t\t\t\t\t\tTask {
Api().loadDeviceHardwareData { (hw: [DeviceHardware]) in
guard !hw.isEmpty,
  let firstNode = fetchedNode.first,
  let user = firstNode.user else {
Logger.data.error("Error: Required DeviceHardware data is missing or array is empty.")
return
}

let dh = hw.first(where: { $0.hwModel == user.hwModelId })

if let deviceHardware = dh {
firstNode.user?.hwDisplayName = deviceHardware.displayName
} else {
Logger.data.error("No matching hardware model found for ID: \\(user.hwModelId, privacy: .public)")
}
}
}
} else {'''
new_hw2 = '''\t\t\t\t\t\t
if let user = fetchedNode.first?.user {
let fetchRequest = DeviceHardwareEntity.fetchRequest()
fetchRequest.predicate = NSPredicate(format: "hwModel == %d", user.hwModelId)
let fetchedHardware = try context.fetch(fetchRequest)
if let hardwareEntity = fetchedHardware.first {
user.hwDisplayName = hardwareEntity.displayName
}
}
} else {'''
content = content.replace(old_hw2, new_hw2)

with open('Meshtastic/Helpers/MeshPackets.swift', 'w') as f:
    f.write(content)
print("Done")
print("Conflict markers remaining:", content.count('<<<<<<'))
