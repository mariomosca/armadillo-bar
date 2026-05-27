//
//  ArmadilloCallDetector.swift — Rileva se sei in videochiamata/riunione.
//  © 2026 Andrea Ricciotti / PunxCode — MIT (vedi LICENSE).
//
//  Strategia: invece di "indovinare" l'app (Teams, Meet, Zoom…), chiede al
//  sistema se il MICROFONO o la CAMERA sono in uso. Copre qualsiasi app o tab
//  browser, senza permessi Accessibility.
//
//  - Microfono: CoreAudio kAudioDevicePropertyDeviceIsRunningSomewhere
//    (la stessa proprietà usata da app come MicCheck).
//  - Camera:    CoreMediaIO kCMIODevicePropertyDeviceIsRunningSomewhere.
//
//  Si usa in POLLING on-demand (lo chiamiamo solo quando l'Armadillo sta per
//  parlare): niente listener da rimuovere → si evita il bug noto di
//  AudioObjectRemovePropertyListenerBlock in Swift.
//
//  Nota: alcune app (es. Zoom) tengono il microfono "aperto" anche fuori dalle
//  riunioni. In quei casi isInCall() può risultare true a riunione conclusa:
//  è un fail-safe accettato (meglio un Armadillo zitto di troppo che uno che
//  parla durante una call).
//
import Foundation
import CoreAudio
import CoreMediaIO

enum ArmadilloCallDetector {

    /// True se microfono O camera risultano in uso da qualche processo.
    static func isInCall() -> Bool {
        isMicrophoneInUse() || isCameraInUse()
    }

    // MARK: - Microfono (CoreAudio)

    static func isMicrophoneInUse() -> Bool {
        guard let dev = defaultInputDevice() else { return false }
        var running = UInt32(0)
        var size = UInt32(MemoryLayout<UInt32>.size)
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        let st = AudioObjectGetPropertyData(dev, &addr, 0, nil, &size, &running)
        return st == noErr && running != 0
    }

    private static func defaultInputDevice() -> AudioDeviceID? {
        var id = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        let st = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &id)
        return (st == noErr && id != 0) ? id : nil
    }

    // MARK: - Camera (CoreMediaIO)

    static func isCameraInUse() -> Bool {
        var addr = CMIOObjectPropertyAddress(
            mSelector: CMIOObjectPropertySelector(kCMIOHardwarePropertyDevices),
            mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
            mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain))

        var dataSize: UInt32 = 0
        guard CMIOObjectGetPropertyDataSize(
            CMIOObjectID(kCMIOObjectSystemObject), &addr, 0, nil, &dataSize) == noErr,
            dataSize > 0 else { return false }

        let count = Int(dataSize) / MemoryLayout<CMIOObjectID>.size
        var devices = [CMIOObjectID](repeating: 0, count: count)
        guard CMIOObjectGetPropertyData(
            CMIOObjectID(kCMIOObjectSystemObject), &addr, 0, nil,
            dataSize, &dataSize, &devices) == noErr else { return false }

        for dev in devices {
            var rAddr = CMIOObjectPropertyAddress(
                mSelector: CMIOObjectPropertySelector(kCMIODevicePropertyDeviceIsRunningSomewhere),
                mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeWildcard),
                mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementWildcard))
            var running: UInt32 = 0
            var size = UInt32(MemoryLayout<UInt32>.size)
            if CMIOObjectGetPropertyData(dev, &rAddr, 0, nil, size, &size, &running) == noErr,
               running != 0 {
                return true
            }
        }
        return false
    }
}
