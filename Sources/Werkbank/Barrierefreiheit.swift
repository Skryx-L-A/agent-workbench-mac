// DER BARRIEREFREIHEITSBAUM, WIE VOICEOVER IHN SIEHT (Abnahme, 08.09.2026).
//
// `apple-native-design/reference/abnahme.md`, Merkmal 4: „Schaltflaechen ohne
// Beschriftung im Barrierefreiheitsbaum. VoiceOver liest den Symbolnamen vor.
// Gegenprobe: Accessibility Inspector oder VoiceOver einschalten und einmal
// durchgehen." Der Inspector ist ein Programm mit Fenster und braucht einen
// Menschen davor. Diese Datei macht dieselbe Gegenprobe maschinell: sie geht
// den Baum ab, den AppKit an VoiceOver reicht, und meldet jedes Element, das
// bedienbar ist und keine Beschriftung traegt.
//
// Was hier NICHT geprueft wird, weil es kein Programm entscheiden kann: ob die
// Beschriftung auch die richtige ist. „Knopf" ist eine Beschriftung und
// trotzdem nutzlos. Dafuer stehen die Woerter in `mac/ABNAHME.md`.
import AppKit

@MainActor
enum Barrierefreiheit {
    /// Die Rollen, bei denen eine fehlende Beschriftung ein Befund ist: alles,
    /// was ein Mensch bedient. Text, Bilder und Gruppen sind ausgenommen --
    /// sie tragen ihren Inhalt selbst.
    static let bedienbar: Set<String> = [
        NSAccessibility.Role.button.rawValue,
        NSAccessibility.Role.checkBox.rawValue,
        NSAccessibility.Role.radioButton.rawValue,
        NSAccessibility.Role.popUpButton.rawValue,
        NSAccessibility.Role.menuButton.rawValue,
        NSAccessibility.Role.slider.rawValue,
        NSAccessibility.Role.textField.rawValue,
        NSAccessibility.Role.comboBox.rawValue,
        NSAccessibility.Role.disclosureTriangle.rawValue,
    ]

    /// Die drei Knoepfe, die das System selbst in die Titelleiste setzt. Sie
    /// kommen ohne `accessibilityLabel`, weil VoiceOver sie an ihrer UNTERROLLE
    /// erkennt und von sich aus „Schliessen-Taste" sagt (gemessen 08.09.2026);
    /// von hier aus ist an ihnen nichts zu beschriften. Die Unterrolle ist der
    /// Weg, auf dem das System sie selbst auszeichnet -- die Objektgleichheit mit
    /// `NSWindow.standardWindowButton` ist es NICHT: der Baum reicht
    /// Stellvertreter heraus, kein Vergleich trifft (gemessen 08.09.2026).
    static let systemknoepfe: Set<String> = [
        NSAccessibility.Subrole.closeButton.rawValue,
        NSAccessibility.Subrole.minimizeButton.rawValue,
        NSAccessibility.Subrole.zoomButton.rawValue,
        NSAccessibility.Subrole.fullScreenButton.rawValue,
    ]

    struct Knoten {
        let rolle: String
        let label: String
        let kennung: String
        let hilfe: String
        let wert: String
        /// Der Titel, den AppKit dem Element gibt (bei einem Systemknopf oft das
        /// Einzige, was er traegt).
        let titel: String
        /// Die Rollenbeschreibung, die VoiceOver hinter der Beschriftung sagt --
        /// „Schaltflaeche", „Schliessen-Knopf". Sie unterscheidet die Knoepfe des
        /// Systems von den eigenen.
        let rollentext: String
        /// Die Lage auf dem Bildschirm -- nur zum Nachsehen im Bericht.
        let rahmen: NSRect
        /// Die Unterrolle, mit der AppKit die Knoepfe des Systems kennzeichnet:
        /// `AXCloseButton`, `AXMinimizeButton`, `AXFullScreenButton`.
        let unterrolle: String
        /// Ob dieses Element einer der drei Fensterknoepfe des Systems ist.
        let system: Bool
    }

    /// Der ganze Baum eines Fensters, flach. `tiefe` begrenzt den Abstieg --
    /// eine Terminalflaeche haengt sonst tausende Zellen daran.
    static func baum(_ fenster: NSWindow, tiefe: Int = 12) -> [Knoten] {
        var raus: [Knoten] = []
        func gehen(_ x: Any, _ rest: Int) {
            // `NSAccessibilityProtocol` ist das, was AppKit an VoiceOver
            // reicht -- NSView, NSWindow und die Stellvertreter, die SwiftUI
            // dafuer baut, erfuellen es alle.
            guard rest > 0, let e = x as? NSAccessibilityProtocol else { return }
            let rolle = (e.accessibilityRole()?.rawValue) ?? ""
            let label = e.accessibilityLabel() ?? ""
            let kennung = e.accessibilityIdentifier() ?? ""
            let hilfe = e.accessibilityHelp() ?? ""
            let wert = (e.accessibilityValue() as? String) ?? ""
            let titel = e.accessibilityTitle() ?? ""
            let rollentext = e.accessibilityRoleDescription() ?? ""
            let rahmen = e.accessibilityFrame()
            let unterrolle = e.accessibilitySubrole()?.rawValue ?? ""
            let system = Self.systemknoepfe.contains(unterrolle)
            if !rolle.isEmpty {
                raus.append(Knoten(rolle: rolle, label: label, kennung: kennung, hilfe: hilfe,
                                   wert: wert, titel: titel, rollentext: rollentext,
                                   rahmen: rahmen, unterrolle: unterrolle, system: system))
            }
            for k in (e.accessibilityChildren() ?? []) { gehen(k, rest - 1) }
        }
        gehen(fenster, tiefe)
        return raus
    }

    /// Die Auskunft fuer `awbmac-ctl barrierefreiheit`, EIN Fenster.
    static func auskunft(_ fenster: NSWindow, tiefe: Int = 12) -> [String: Any] {
        let knoten = baum(fenster, tiefe: tiefe)
        let ohne = knoten.filter { bedienbar.contains($0.rolle) && $0.label.isEmpty && $0.wert.isEmpty && $0.titel.isEmpty }
        func zeile(_ k: Knoten) -> [String: Any] {
            [
                "rolle": k.rolle, "label": k.label, "titel": k.titel, "kennung": k.kennung,
                "hilfe": k.hilfe, "rollentext": k.rollentext,
                "unterrolle": k.unterrolle, "system": k.system,
                "y": Int(k.rahmen.midY), "x": Int(k.rahmen.midX),
            ]
        }
        return [
            "titel": fenster.title,
            "knoten": knoten.count,
            "bedienbar": knoten.filter { bedienbar.contains($0.rolle) }.count,
            "ohneLabel": ohne.count,
            "ohneLabelEigen": ohne.filter { !$0.system }.count,
            "fehlend": ohne.map(zeile),
            "elemente": knoten.filter { bedienbar.contains($0.rolle) }.map(zeile),
        ]
    }

    /// Dieselbe Gegenprobe ueber JEDES Fenster, das gerade steht -- Hauptfenster,
    /// Einstellungen, Verbrauch, Sitzungsblatt, Agents. Ein Blatt, das nur ein
    /// Mensch oeffnet, wird sonst nie gemessen; die Suite oeffnet sie deshalb
    /// vorher alle ueber die Menueleiste.
    static func auskunftAlle(tiefe: Int = 12) -> [String: Any] {
        let fenster = NSApp.windows.filter { $0.contentView != nil }
        let je = fenster.map { auskunft($0, tiefe: tiefe) }
        func summe(_ feld: String) -> Int { je.reduce(0) { $0 + (($1[feld] as? Int) ?? 0) } }
        return [
            "fenster": je,
            "anzahl": je.count,
            "knoten": summe("knoten"),
            "bedienbar": summe("bedienbar"),
            "ohneLabel": summe("ohneLabel"),
            "ohneLabelEigen": summe("ohneLabelEigen"),
        ]
    }
}
