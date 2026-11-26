import SwiftUI
import AppKit
import ServiceManagement
import AVFoundation

/// Every option, saved on this Mac.
final class SettingsStore: ObservableObject {
    static let shared = SettingsStore()
    private static func flag(_ k: String, _ d: Bool) -> Bool { UserDefaults.standard.object(forKey: "s." + k) as? Bool ?? d }
    private static func num(_ k: String, _ d: Double) -> Double { UserDefaults.standard.object(forKey: "s." + k) as? Double ?? d }
    private static func int(_ k: String, _ d: Int) -> Int { UserDefaults.standard.object(forKey: "s." + k) as? Int ?? d }
    private func put(_ k: String, _ v: Any) { UserDefaults.standard.set(v, forKey: "s." + k) }

    // Show / hide
    @Published var islandOn: Bool       { didSet { put("islandOn", islandOn) } }
    @Published var toastsOn: Bool       { didSet { put("toastsOn", toastsOn) } }
    @Published var edgeSlidersOn: Bool  { didSet { put("edgeSlidersOn", edgeSlidersOn) } }
    @Published var widgetOn: Bool       { didSet { put("widgetOn", widgetOn) } }
    @Published var desktopLyricsOn: Bool { didSet { put("desktopLyricsOn", desktopLyricsOn) } }
    @Published var glowOn: Bool         { didSet { put("glowOn", glowOn) } }
    @Published var lockLyricsOn: Bool   { didSet { put("lockLyricsOn", lockLyricsOn) } }
    // Island
    @Published var floatingIsland: Bool { didSet { put("floatingIsland", floatingIsland) } }
    @Published var openOnClick: Bool    { didSet { put("openOnClick", openOnClick) } }
    @Published var hideWhenIdle: Bool   { didSet { put("hideWhenIdle", hideWhenIdle) } }
    @Published var glassStyle: Bool     { didSet { put("glassStyle", glassStyle) } }
    @Published var islandScale: Double  { didSet { put("islandScale", islandScale) } }
    @Published var animSpeed: Double    { didSet { put("animSpeed", animSpeed) } }
    // Lyrics / lock / desktop
    @Published var lyricStyle: Int      { didSet { put("lyricStyle", lyricStyle) } }
    @Published var starsOn: Bool        { didSet { put("starsOn", starsOn) } }
    @Published var lockRecordOn: Bool   { didSet { put("lockRecordOn", lockRecordOn) } }
    @Published var widgetStyle: Int     { didSet { put("widgetStyle", widgetStyle) } }
    // Needle-parity extras
    @Published var bigIsland: Bool      { didSet { put("bigIsland", bigIsland) } }
    @Published var turntable: Bool      { didSet { put("turntable", turntable) } }
    @Published var clockFont: Int       { didSet { put("clockFont", clockFont) } }
    @Published var screenKeeper: Bool   { didSet { put("screenKeeper", screenKeeper) } }
    // Key sounds
    @Published var keySoundsOn: Bool    { didSet { put("keySoundsOn", keySoundsOn) } }
    @Published var keySoundSet: Int     { didSet { put("keySoundSet", keySoundSet) } }
    @Published var keySoundVolume: Double { didSet { put("keySoundVolume", keySoundVolume) } }
    // Equalizer, glass, lock screen, lyrics look
    @Published var eqOn: Bool           { didSet { put("eqOn", eqOn) } }
    @Published var eqBars: Int          { didSet { put("eqBars", eqBars) } }
    @Published var eqColorMode: Int     { didSet { put("eqColorMode", eqColorMode) } }       // 0 white, 1 rainbow
    @Published var eqSensitivity: Double { didSet { put("eqSensitivity", eqSensitivity) } }
    @Published var glassMaterial: Int   { didSet { put("glassMaterial", glassMaterial) } }
    @Published var glassTint: Double    { didSet { put("glassTint", glassTint) } }
    @Published var keepOpen: Bool       { didSet { put("keepOpen", keepOpen) } }
    @Published var lockStage: Int       { didSet { put("lockStage", lockStage) } }           // 0 record, 1 cover, 2 lyrics
    @Published var lockDim: Double      { didSet { put("lockDim", lockDim) } }
    @Published var lockRecordSize: Double { didSet { put("lockRecordSize", lockRecordSize) } }
    @Published var lockTitleOn: Bool    { didSet { put("lockTitleOn", lockTitleOn) } }
    @Published var lockNextLineOn: Bool { didSet { put("lockNextLineOn", lockNextLineOn) } }
    @Published var lockVerticalTitle: Bool { didSet { put("lockVerticalTitle", lockVerticalTitle) } }
    @Published var constellationBehind: Bool { didSet { put("constellationBehind", constellationBehind) } }
    @Published var lockControlsOn: Bool { didSet { put("lockControlsOn", lockControlsOn) } }
    @Published var lockSoundsOn: Bool   { didSet { put("lockSoundsOn", lockSoundsOn) } }
    @Published var lockGlass: Int       { didSet { put("lockGlass", lockGlass) } }           // 0 liquid, 1 clear, 2 off
    @Published var lensBend: Double     { didSet { put("lensBend", lensBend) } }             // how much the lens bends the lines beside it
    @Published var lyricBackground: Int { didSet { put("lyricBackground", lyricBackground) } } // 0 dark, 1 album blur
    @Published var lyricScatter: Double { didSet { put("lyricScatter", lyricScatter) } }
    @Published var lyricOffset: Double  { didSet { put("lyricOffset", lyricOffset) } }       // seconds the lyrics run early
    @Published var lyricColorMode: Int  { didSet { put("lyricColorMode", lyricColorMode) } }   // 0 white, 1 album, 2 custom
    @Published var lyricR: Double       { didSet { put("lyricR", lyricR) } }
    @Published var lyricG: Double       { didSet { put("lyricG", lyricG) } }
    @Published var lyricB: Double       { didSet { put("lyricB", lyricB) } }
    // Beat Glow
    @Published var glowOnlyWhilePlaying: Bool { didSet { put("glowOnlyWhilePlaying", glowOnlyWhilePlaying) } }
    @Published var glowColorMode: Int   { didSet { put("glowColorMode", glowColorMode) } }   // 0 album, 1 custom, 2 rainbow
    @Published var glowR: Double        { didSet { put("glowR", glowR) } }
    @Published var glowG: Double        { didSet { put("glowG", glowG) } }
    @Published var glowB: Double        { didSet { put("glowB", glowB) } }
    @Published var glowStyle: Int       { didSet { put("glowStyle", glowStyle) } }           // 0 rim, 1 edges, 2 corners, 3 sides
    @Published var glowMotion: Int      { didSet { put("glowMotion", glowMotion) } }         // 0 to the beat, 1 steady
    @Published var glowOnLock: Bool     { didSet { put("glowOnLock", glowOnLock) } }
    @Published var glowIntensity: Double { didSet { put("glowIntensity", glowIntensity) } }
    @Published var glowThickness: Double { didSet { put("glowThickness", glowThickness) } }
    @Published var glowBlur: Double     { didSet { put("glowBlur", glowBlur) } }
    @Published var glowBPM: Double      { didSet { put("glowBPM", glowBPM) } }
    // Other
    @Published var faceLockOn: Bool     { didSet { put("faceLockOn", faceLockOn) } }
    @Published var fahrenheit: Bool     { didSet { put("fahrenheit", fahrenheit) } }
    @Published var showMenuIcon: Bool   { didSet { put("showMenuIcon", showMenuIcon) } }
    @Published var browsersOn: Bool     { didSet { put("browsersOn", browsersOn) } }
    @Published var toastHeadphones: Bool { didSet { put("toastHeadphones", toastHeadphones) } }
    @Published var toastCharging: Bool  { didSet { put("toastCharging", toastCharging) } }
    @Published var toastFocus: Bool     { didSet { put("toastFocus", toastFocus) } }
    @Published var toastVolume: Bool    { didSet { put("toastVolume", toastVolume) } }
    /// Dashboard icons the user has switched off (by name).
    @Published var railHidden: [String] { didSet { UserDefaults.standard.set(railHidden, forKey: "s.railHidden") } }
    @Published var launchAtLogin: Bool  {
        didSet { if launchAtLogin { try? SMAppService.mainApp.register() } else { try? SMAppService.mainApp.unregister() } }
    }

    private init() {
        islandOn = Self.flag("islandOn", true); toastsOn = Self.flag("toastsOn", true)
        edgeSlidersOn = Self.flag("edgeSlidersOn", true); widgetOn = Self.flag("widgetOn", true)
        desktopLyricsOn = Self.flag("desktopLyricsOn", false); glowOn = Self.flag("glowOn", true)
        lockLyricsOn = Self.flag("lockLyricsOn", true)
        floatingIsland = Self.flag("floatingIsland", false); openOnClick = Self.flag("openOnClick", true)
        hideWhenIdle = Self.flag("hideWhenIdle", false); glassStyle = Self.flag("glassStyle", false)
        islandScale = Self.num("islandScale", 1); animSpeed = Self.num("animSpeed", 1)
        lyricStyle = Self.int("lyricStyle", 0)
        starsOn = Self.flag("starsOn", true); lockRecordOn = Self.flag("lockRecordOn", true)
        widgetStyle = Self.int("widgetStyle", 0)
        bigIsland = Self.flag("bigIsland", false); turntable = Self.flag("turntable", true)
        clockFont = Self.int("clockFont", 0); screenKeeper = Self.flag("screenKeeper", false)
        keySoundsOn = Self.flag("keySoundsOn", false); keySoundSet = Self.int("keySoundSet", 0)
        keySoundVolume = Self.num("keySoundVolume", 0.5)
        glowOnlyWhilePlaying = Self.flag("glowOnlyWhilePlaying", true); glowColorMode = Self.int("glowColorMode", 0)
        glowR = Self.num("glowR", 1); glowG = Self.num("glowG", 0.4); glowB = Self.num("glowB", 0.3)
        glowStyle = Self.int("glowStyle", 0); glowMotion = Self.int("glowMotion", 0); glowOnLock = Self.flag("glowOnLock", true); glowIntensity = Self.num("glowIntensity", 1)
        glowThickness = Self.num("glowThickness", 6); glowBlur = Self.num("glowBlur", 12)
        
        glowBPM = Self.num("glowBPM", 100)
        eqOn = Self.flag("eqOn", true); eqBars = Self.int("eqBars", 5); eqColorMode = Self.int("eqColorMode", 0)
        eqSensitivity = Self.num("eqSensitivity", 1); glassMaterial = Self.int("glassMaterial", 0)
        glassTint = Self.num("glassTint", 0.3); keepOpen = Self.flag("keepOpen", false)
        lockStage = Self.int("lockStage", 2); lockDim = Self.num("lockDim", 0.6); lockRecordSize = Self.num("lockRecordSize", 160)
        lockTitleOn = Self.flag("lockTitleOn", true); lockNextLineOn = Self.flag("lockNextLineOn", true); lockVerticalTitle = Self.flag("lockVerticalTitle", true); constellationBehind = Self.flag("constellationBehind", false)
        lockControlsOn = Self.flag("lockControlsOn", true); lockSoundsOn = Self.flag("lockSoundsOn", true)
        lockGlass = Self.int("lockGlass", 0); lensBend = Self.num("lensBend", 0.5)
        lyricBackground = Self.int("lyricBackground", 1)
        lyricOffset = Self.num("lyricOffset", 0.35); lyricScatter = Self.num("lyricScatter", 0.3)
        lyricColorMode = Self.int("lyricColorMode", 1)
        lyricR = Self.num("lyricR", 1); lyricG = Self.num("lyricG", 1); lyricB = Self.num("lyricB", 1)
        faceLockOn = Self.flag("faceLockOn", false); fahrenheit = Self.flag("fahrenheit", false)
        showMenuIcon = Self.flag("showMenuIcon", true); browsersOn = Self.flag("browsersOn", true)
        toastHeadphones = Self.flag("toastHeadphones", true); toastCharging = Self.flag("toastCharging", true)
        toastFocus = Self.flag("toastFocus", true); toastVolume = Self.flag("toastVolume", true)
        railHidden = UserDefaults.standard.stringArray(forKey: "s.railHidden") ?? []
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    func railOn(_ key: String) -> Bool { !railHidden.contains(key) }
    func setRail(_ key: String, _ on: Bool) {
        if on { railHidden.removeAll { $0 == key } } else if !railHidden.contains(key) { railHidden.append(key) }
    }

    func temp(_ c: Int) -> Int { fahrenheit ? Int((Double(c) * 9 / 5 + 32).rounded()) : c }

    func resetGlow() {
        glowOnlyWhilePlaying = true; glowColorMode = 0; glowR = 1; glowG = 0.4; glowB = 0.3; glowStyle = 0; glowMotion = 0
        glowIntensity = 1; glowThickness = 6; glowBlur = 12; glowBPM = 100
    }
}
