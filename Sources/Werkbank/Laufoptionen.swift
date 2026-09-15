// Womit die App gestartet wurde. Alles kommt aus Argumenten oder der Umgebung,
// nichts steht fest verdrahtet -- dieselbe Regel wie in app/src/main/config.ts.
import AppKit
import Foundation

enum TerminalArt: String, Sendable {
    /// SwiftTerm zeichnet den Steuermodus-Strom (`%output`) aus dem Kern -- wie xterm.js heute.
    case strom
    /// SwiftTerm haelt einen echten tmux-Client (`tmux attach -t <sitzung>`) je Ansicht.
    case attach
}

struct Laufoptionen: Sendable {
    /// Kein Fenster auf dem Bildschirm, kein Dock-Symbol: der Modus jeder Pruefung.
    var kopflos = false
    /// Sichtbar, aber HINTER allem und ohne Fokus -- der Modus einer
    /// Sichtpruefung an der laufenden Maschine (regeln/tests-und-eingriffe.md:
    /// „Ein Testfenster laeuft hinter seinen Fenstern und nimmt nie den
    /// Fokus"). Ohne ihn gab es nur die Wahl zwischen kopflos und einem
    /// Fenster, das sich vor Arbeit des Nutzers schiebt.
    var ohneFokus = false
    var terminal: TerminalArt = .strom
    /// Pfad des Mantel-Sockets des Kerns (AWB_MANTEL_SOCKET).
    var mantelSocket = ""
    var mantelToken = ""
    /// Pfad des eigenen Steuerkanals (`awbmac-ctl`), leer = keiner.
    var steuerSocket = ""
    /// tmux-Socketname des Kerns (AWB_TMUX_SOCKET), fuer die attach-Variante.
    var tmuxSocket = ""
    var tmuxBin = "tmux"
    /// Das Laufverzeichnis (AWBMAC_LAUFDIR): in einer Pruefung liegt dort die
    /// gemerkte Fensterlage.
    var laufdir = ""

    /// Laeuft die App als PRUEFUNG? Kopflos oder sichtbar ohne Fokus -- beides
    /// ist ein Testlauf, und beide duerfen die Live-Umgebung nicht anfassen
    /// (regeln/tests-und-eingriffe.md). Woran das haengt: die Fensterlage, die
    /// zugeklappten Projekte und die Ablage der Voreinstellungen
    /// (Merker.swift).
    var pruefmodus: Bool { kopflos || ohneFokus }

    static func lesen(argv: [String] = CommandLine.arguments,
                      env: [String: String] = ProcessInfo.processInfo.environment) -> Laufoptionen {
        var o = Laufoptionen()
        o.mantelSocket = env["AWB_MANTEL_SOCKET"] ?? ""
        o.mantelToken = env["AWB_MANTEL_TOKEN"] ?? ""
        o.steuerSocket = env["AWBMAC_CONTROL_SOCKET"] ?? ""
        o.tmuxSocket = env["AWB_TMUX_SOCKET"] ?? ""
        o.tmuxBin = env["AWBMAC_TMUX_BIN"] ?? "tmux"
        o.laufdir = env["AWBMAC_LAUFDIR"] ?? ""
        o.ohneFokus = (env["AWBMAC_OHNE_FOKUS"] ?? "") == "1"
        if let t = env["AWBMAC_TERMINAL"], let art = TerminalArt(rawValue: t) { o.terminal = art }
        var i = 1
        while i < argv.count {
            let a = argv[i]
            switch a {
            case "--kopflos": o.kopflos = true
            case "--ohne-fokus": o.ohneFokus = true
            case "--terminal":
                i += 1
                if i < argv.count, let art = TerminalArt(rawValue: argv[i]) { o.terminal = art }
            case "--steuer-socket":
                i += 1
                if i < argv.count { o.steuerSocket = argv[i] }
            default:
                if a.hasPrefix("--terminal="), let art = TerminalArt(rawValue: String(a.dropFirst(11))) { o.terminal = art }
            }
            i += 1
        }
        return o
    }
}

/// EIN FENSTER ZEIGEN, OHNE JEMANDEM DIE TASTATUR WEGZUNEHMEN (08.09.2026).
///
/// `--ohne-fokus` gibt es, damit an einem SICHTBAREN Fenster geprueft werden
/// kann, waehrend jemand daneben weiterarbeitet (regeln/tests-und-eingriffe.md).
/// Das Hauptfenster hielt sich daran (main.swift), die drei Fenster daneben
/// nicht: `makeKeyAndOrderFront` plus `NSApp.activate()` holt die ganze App nach
/// vorn, und ein Steuerkanal-Aufruf riss damit mitten in einer Pruefung das
/// Fenster vor Arbeit des Nutzers. `orderFrontRegardless` zeigt es, ohne die App
/// zu aktivieren -- was `open -g` fuer eine fremde App tut, tut das hier fuer
/// die eigene.
///
/// EINE STELLE fuer alle: Einstellungs-, Verbrauchs- und Sitzungsfenster rufen
/// diesen Weg. Drei Kopien waeren drei Gelegenheiten, es beim naechsten Fenster
/// wieder zu vergessen.
extension NSWindow {
    @MainActor
    func vorZeigen(ohneFokus: Bool) {
        if !isVisible { center() }
        guard !ohneFokus else { orderFrontRegardless(); return }
        Fensterweg.aktivierungen += 1
        makeKeyAndOrderFront(nil)
        NSApp.activate()
    }
}

/// WIE OFT EIN FENSTER DIE APP NACH VORN GEHOLT HAT (08.09.2026).
///
/// Gemessen wird der WEG, nicht sein Ausgang. Der Ausgang taugt nicht als
/// Zusage: macOS 26 lehnt die Aktivierung einer App, die nie aktiv war, von
/// sich aus ab -- gemessen an dieser Suite, `NSApp.isActive` blieb auch mit
/// `NSApp.activate()` falsch und `NSApp.keyWindow` leer. Damit waere „die App
/// ist nicht vorn" grün, ohne etwas über den Code zu sagen, und der Aufruf
/// bliebe stehen, bis das System seine Meinung ändert oder die App aus einem
/// anderen Grund gerade aktiv ist. Die Zahl hier zaehlt jeden Aufruf, der
/// aktivieren WOLLTE; unter `--ohne-fokus` muss sie 0 bleiben
/// (`ui.fenster.aktivierungen`).
@MainActor
enum Fensterweg {
    static var aktivierungen = 0
}
