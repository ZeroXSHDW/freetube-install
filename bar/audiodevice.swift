import CoreAudio
import Foundation

// Print the name of the system default output audio device.
var defaultDevice = AudioObjectID(0)
var deviceSize = UInt32(MemoryLayout<AudioObjectID>.size)
var deviceAddr = AudioObjectPropertyAddress(
    mSelector: kAudioHardwarePropertyDefaultOutputDevice,
    mScope: kAudioObjectPropertyScopeGlobal,
    mElement: kAudioObjectPropertyElementMain
)
AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &deviceAddr, 0, nil, &deviceSize, &defaultDevice)

var nameAddr = AudioObjectPropertyAddress(
    mSelector: kAudioDevicePropertyDeviceNameCFString,
    mScope: kAudioObjectPropertyScopeGlobal,
    mElement: kAudioObjectPropertyElementMain
)
var cfName: Unmanaged<CFString>?
var nameSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
AudioObjectGetPropertyData(defaultDevice, &nameAddr, 0, nil, &nameSize, &cfName)

if let name = cfName?.takeRetainedValue() as String? {
    print(name)
}
