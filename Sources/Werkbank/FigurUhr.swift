// DIE GEMEINSAME UHR DER AGENTENFIGUREN (09.10.2026, Auftrag figur-uhr).
//
// Bis heute trug jede Figur und jeder „arbeitet"-Ring eine eigene
// `TimelineView(.animation(minimumInterval: 1/30))`. Gemessen am Live-Mantel
// (`sample`, Leerlauf, 25-34 % CPU): der Hauptfaden war fast nur im
// Anzeigezyklus, groesster eigener Posten `Agentenfigur.body` und
// `FigurZeichner.zeichnen`. Jede TimelineView hatte ihren eigenen Takt, und sie
// tickte auch hinter verdeckten oder minimierten Fenstern weiter.
//
// Jetzt gibt es EINE Uhr fuer alle:
//   - Ein `CADisplayLink` mit 30 Bildern je Sekunde setzt einmal je Bild `t`
//     (Einstellung `figurenBildrate`, Vorgabe 30, nur fuer die Figuren).
//     Jede bewegte Figur liest `t` (Observation) und wird im selben Durchgang
//     neu gezeichnet: ein Takt fuer alle statt einer je Figur.
//   - `t` ist dieselbe Groesse wie vorher `TimelineView`s
//     `date.timeIntervalSinceReferenceDate`: die Wanduhr zum Zielbild. Die
//     Figur zeichnet weiter `zeichnen(t: t + versatz)`, der Ring dreht weiter
//     nach `t mod umlauf`. Bildrate, Ausdruck, Bewegung und Versatz je Figur
//     bleiben gleich; „Bewegung reduzieren" und `figurStandbild` lesen die Uhr
//     gar nicht.
//   - Die Uhr steht, solange kein Fenster der App sichtbar ist (verdeckt,
//     minimiert, App ausgeblendet, anderer Schreibtisch, Bildschirm aus). Wird
//     eines sichtbar, springt `t` sofort auf jetzt: die Figur steht da, wo sie
//     ohne Pause auch stuende, denn ihre Pose ist eine Funktion der Uhrzeit.
//
// Kopflos (Pruefungen) ist nie ein Fenster auf dem Bildschirm; die Uhr laeuft
// dort nie an. `awbmac-ctl agents` nennt ihren Zustand unter `figurUhr`.
// `AWBMAC_FIGURUHR_SICHTBAR=immer` laesst sie ohne Ruecksicht auf die Fenster
// laufen -- nur fuer die Messung einer Testinstanz, deren Fenster nach der
// Hausregel hinter den Fenstern des Menschen liegt und deshalb verdeckt ist.
import AppKit
import QuartzCore
import SwiftUI

@MainActor
@Observable
final class FigurUhr {
    static let geteilt = FigurUhr()
    /// Vorgabe: dieselbe Bildrate wie zuvor `TimelineView(.animation(minimumInterval: 1.0 / 30))`.
    static let vorgabeBildrate: Double = 30

    /// Sekunden seit dem Referenzdatum, wie `TimelineView.Context.date.timeIntervalSinceReferenceDate`.
    /// Setzt nur die Uhr selbst (und eine Pruefung, die eine feste Zeit braucht).
    var t: TimeInterval = Date().timeIntervalSinceReferenceDate

    private static let immerSichtbar = ProcessInfo.processInfo.environment["AWBMAC_FIGURUHR_SICHTBAR"] == "immer"

    /// Bilder je Sekunde, nur fuer Figuren und Ringe. Kommt als `figurenBildrate` mit `awb:model`
    /// aus den Einstellungen (wb-state, 10 bis 60); der Rest der App bleibt unberuehrt.
    @ObservationIgnored private(set) var bildrate: Double = FigurUhr.vorgabeBildrate
    @ObservationIgnored private(set) var sichtbar = false
    @ObservationIgnored private(set) var takte = 0
    @ObservationIgnored private var link: CADisplayLink?
    @ObservationIgnored private var ziel: Taktziel?
    @ObservationIgnored private var letztesBild: CFTimeInterval = 0
    @ObservationIgnored private var beobachter: [NSObjectProtocol] = []

    private init() {
        let nc = NotificationCenter.default
        let namen: [Notification.Name] = [
            NSWindow.didChangeOcclusionStateNotification, NSWindow.didMiniaturizeNotification,
            NSWindow.didDeminiaturizeNotification, NSWindow.willCloseNotification,
            NSApplication.didHideNotification, NSApplication.didUnhideNotification,
            NSApplication.didChangeScreenParametersNotification,
        ]
        for name in namen {
            beobachter.append(nc.addObserver(forName: name, object: nil, queue: .main) { [weak self] n in
                let bildschirm = n.name == NSApplication.didChangeScreenParametersNotification
                // Erst im naechsten Durchlauf pruefen: bei `willClose` steht das Fenster noch.
                Task { @MainActor in self?.pruefen(neuerBildschirm: bildschirm) }
            })
        }
        pruefen(neuerBildschirm: false)
    }

    /// Fuer `awbmac-ctl agents` (Feld `figurUhr`) und die Messung.
    func auskunft() -> [String: Any] {
        ["sichtbar": sichtbar, "laeuft": link.map { !$0.isPaused } ?? false, "takte": takte, "bildrate": bildrate]
    }

    /// Ist irgendein Fenster der App wenigstens teilweise auf dem Bildschirm zu sehen?
    private func pruefen(neuerBildschirm: Bool) {
        let app: NSApplication? = NSApp
        let jetzt = Self.immerSichtbar || (app?.windows.contains { $0.isVisible && $0.occlusionState.contains(.visible) } ?? false)
        if neuerBildschirm, let l = link {
            l.invalidate()
            link = nil
        }
        sichtbar = jetzt
        if jetzt {
            if link == nil { link = neuerLink() }
            if link?.isPaused ?? true {
                // Sofort weiter: das erste Bild nach der Pause zeigt die Pose von jetzt.
                t = Date().timeIntervalSinceReferenceDate
                letztesBild = 0
            }
            link?.isPaused = false
        } else {
            link?.isPaused = true
        }
    }

    /// Neue Bildrate aus den Einstellungen; ein unveraenderter Wert aendert nichts.
    func bildrateSetzen(_ neu: Int) {
        let r = Double(min(60, max(10, neu)))
        guard r != bildrate else { return }
        bildrate = r
        link?.preferredFrameRateRange = Self.bereich(r)
    }

    private static func bereich(_ r: Double) -> CAFrameRateRange {
        CAFrameRateRange(minimum: Float(r), maximum: Float(r), preferred: Float(r))
    }

    private func neuerLink() -> CADisplayLink? {
        guard let schirm = NSScreen.main ?? NSScreen.screens.first else { return nil }
        let z = Taktziel { [weak self] l in self?.bild(l) }
        let l = schirm.displayLink(target: z, selector: #selector(Taktziel.bild(_:)))
        l.preferredFrameRateRange = Self.bereich(bildrate)
        l.add(to: .main, forMode: .common)
        ziel = z
        return l
    }

    private func bild(_ l: CADisplayLink) {
        // Wie `minimumInterval`: nie oefter als `bildrate`-mal je Sekunde, auch wenn der
        // Bildschirm (120 Hz) den Wunsch nicht erfuellt.
        guard l.targetTimestamp - letztesBild >= 1 / bildrate - 0.004 else { return }
        letztesBild = l.targetTimestamp
        takte += 1
        t = Date().timeIntervalSinceReferenceDate + (l.targetTimestamp - CACurrentMediaTime())
    }
}

/// Ziel des `CADisplayLink` (der braucht ein Objective-C-Objekt und einen Selektor). Der Link
/// haengt an der Hauptschleife und ruft deshalb auf dem Hauptfaden.
@MainActor
private final class Taktziel: NSObject {
    let wenn: @MainActor (CADisplayLink) -> Void
    init(_ wenn: @escaping @MainActor (CADisplayLink) -> Void) { self.wenn = wenn }
    @objc func bild(_ l: CADisplayLink) { wenn(l) }
}
