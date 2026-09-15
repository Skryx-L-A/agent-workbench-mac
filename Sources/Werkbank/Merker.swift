// WO DIE APP MERKT, WAS EIN NEUSTART WIEDERFINDEN SOLL (08.09.2026).
//
// Im Betrieb in den Voreinstellungen der App (`agent-workbench.werkbank`), wie
// jede Mac-App. In einer PRUEFUNG in einer Datei im Laufverzeichnis -- kopflos
// wie sichtbar-ohne-Fokus.
//
// DER GRUND, GEMESSEN. `UserDefaults.standard` und `setFrameAutosaveName`
// folgen HOME NICHT: die Voreinstellungen liegen hinter `cfprefsd`, einem
// eigenen Prozess mit eigener Sicht. Eine Pruefung mit Wegwerf-HOME schrieb
// deshalb trotzdem in die echte Ablage des Menschen -- zuletzt das
// Einstellungsfenster ueber `setFrameAutosaveName("Einstellungen")`, das dabei
// „NSWindow Frame Einstellungen" in `agent-workbench.werkbank` ablegte. Unter Last
// fiel darueber `test-mac-fenster.sh` Zusage 6, die genau das bewacht:
// „Voreinstellungen des Menschen vorher X nachher Y". Eine Pruefung fasst die
// Live-Umgebung nie an (regeln/tests-und-eingriffe.md).
//
// WARUM EINE DATEI UND KEINE EIGENE VOREINSTELLUNGS-ABLAGE. `UserDefaults(suiteName:)`
// waere die naheliegende Antwort, legt ihre plist aber wieder unter dem ECHTEN
// `~/Library/Preferences` an -- und bliebe dort liegen, sobald eine Pruefung
// hart abgeraeumt wird, statt sich zu beenden. Eine Datei im Laufverzeichnis
// geht mit dem Laufverzeichnis, ist im Test lesbar, und die Suiten pruefen sie
// schon so (`fensterlage.txt`, `zugeklappte-projekte.txt`).
import Foundation

enum Merker {
    /// Die Datei zu diesem Namen -- oder nil, wenn das hier der Betrieb ist.
    static func datei(_ name: String, _ o: Laufoptionen) -> String? {
        guard o.pruefmodus, !o.laufdir.isEmpty else { return nil }
        return (o.laufdir as NSString).appendingPathComponent(name)
    }

    /// Ein gemerkter Text.
    static func text(datei: String, schluessel: String, _ o: Laufoptionen) -> String? {
        if let pfad = Self.datei(datei, o) {
            let t = (try? String(contentsOfFile: pfad, encoding: .utf8))?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return (t?.isEmpty ?? true) ? nil : t
        }
        let t = UserDefaults.standard.string(forKey: schluessel)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return (t?.isEmpty ?? true) ? nil : t
    }

    static func setzen(_ text: String, datei: String, schluessel: String, _ o: Laufoptionen) {
        if let pfad = Self.datei(datei, o) {
            try? text.write(toFile: pfad, atomically: true, encoding: .utf8)
        } else {
            UserDefaults.standard.set(text, forKey: schluessel)
        }
    }

    /// Eine gemerkte Liste -- eine Zeile je Eintrag, damit die Datei lesbar bleibt.
    static func liste(datei: String, schluessel: String, _ o: Laufoptionen) -> [String] {
        if Self.datei(datei, o) != nil {
            let t = text(datei: datei, schluessel: schluessel, o) ?? ""
            return t.split(separator: "\n").map(String.init).filter { !$0.isEmpty }
        }
        return UserDefaults.standard.stringArray(forKey: schluessel) ?? []
    }

    static func setzen(_ liste: [String], datei: String, schluessel: String, _ o: Laufoptionen) {
        if Self.datei(datei, o) != nil {
            setzen(liste.joined(separator: "\n"), datei: datei, schluessel: schluessel, o)
        } else {
            UserDefaults.standard.set(liste, forKey: schluessel)
        }
    }

    // Die drei Namen, unter denen gemerkt wird. Sie stehen hier zusammen,
    // damit eine Suite sie nachschlagen kann statt sie zu raten.
    static let fensterlage = "fensterlage.txt"
    static let einstellungslage = "einstellungsfenster-lage.txt"
    static let zugeklappteProjekte = "zugeklappte-projekte.txt"
}
