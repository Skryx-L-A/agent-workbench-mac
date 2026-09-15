// EIN KLICK AUF EINEN PFAD -- EIN WEG (Auftrag 3.6, 06.09.2026).
//
// Vier Stellen im Fenster fuehren hierher: eine Zeile im Ordner-Blatt, ein
// Treffer der Suche, eine Fundstelle im Gespraech und eine Fundstelle im
// Terminal. Was dann geschieht, ist ueberall dasselbe und steht ueberall an
// derselben Stelle: Text in den Editor (an die Zeile, wenn eine genannt ist),
// Binaeres ans System, ein Ordner ins Ordner-Blatt -- dieselbe Regel wie in der
// Electron-Fassung (renderer.ts `pfadOeffnen`, main/chatpfade.ts).
//
// DIE ENTSCHEIDUNG FAELLT IM KERN, nicht hier. `awb:chat-pfad-oeffnen` sagt,
// ob ein Pfad Text, Binaeres oder ein Ordner ist, liest den Text selbst und
// schickt Binaeres gleich an `shell.openPath`; geoeffnet wird nur, was derselbe
// Prozess vorher als Treffer gemeldet hat. Diese Klasse haelt keinen zweiten
// Massstab daneben -- sie fragt, und sie legt das Ergebnis an seinen Platz.
import AppKit
import WerkbankProtokoll

@MainActor
final class Pfadoeffner {
    @ObservationIgnored let kern: KernVerbindung
    private unowned let editor: EditorBlattZustand

    /// Ein Verzeichnis: das Ordner-Blatt zeigen und bis dorthin aufklappen.
    var ordnerZeigen: ((String) -> Void)?
    /// Eine Zeile fuer den Menschen (Statusfuss bzw. Notiz des Editors).
    var melden: ((String) -> Void)?

    /// Was zuletzt geoeffnet wurde -- fuer `awbmac-ctl ui` und die Suiten.
    private(set) var letzterPfad = ""
    private(set) var letzteArt = ""
    private(set) var letzteMeldung = ""

    init(kern: KernVerbindung, editor: EditorBlattZustand) {
        self.kern = kern
        self.editor = editor
    }

    /// `pfad` darf die Zeilenangabe tragen (`a/b.ts:12:4`). `pane` nennt den
    /// Terminal-Pane, aus dem der Klick kam; leer heisst „die Chat-Sitzung auf
    /// der Buehne bzw. die Ordnerwurzel". `geprueft` sagt, dass der Kern diesen
    /// Pfad in diesem Zug schon als Treffer gemeldet hat.
    @discardableResult
    func oeffnen(_ pfad: String, pane: String = "", geprueft: Bool = false) async -> (ok: Bool, art: String, meldung: String) {
        let k = Pfadlinks.zerlegen(pfad)
        var abs = k.pfad
        if !geprueft {
            let treffer = await kern.pfadePruefen(pane: pane, kandidaten: [k.wortlaut])
            guard let t = treffer.first else {
                return fehler("„\(Pfadlinks.kurzerPfad(k.pfad))“ gibt es nicht (mehr).")
            }
            abs = t.abs
        }
        let o = await kern.pfadOeffnen(abs)
        guard o.fehler.isEmpty else { return fehler(o.fehler) }
        switch o.art {
        case "ordner":
            ordnerZeigen?(abs)
            return erfolg(abs, "ordner", "„\(Pfadlinks.kurzerPfad(abs))“ im Ordner-Blatt.")
        case "extern":
            // Der Kern hat `shell.openPath` schon gerufen -- hier wird nichts
            // gestartet, damit es genau EINEN Weg nach draussen gibt.
            return erfolg(abs, "extern", "„\(Pfadlinks.kurzerPfad(abs))“ an das System gegeben.")
        case "text":
            let zeile = k.zeile
            let spalte = max(1, k.spalte)
            // Innerhalb des Projektordners bleibt die Datei die Datei: derselbe
            // Tab wie aus dem Dateibaum, mit Speichern. Ausserhalb (eine
            // Ergebnisdatei, ein Protokoll) ist sie schreibgeschuetzt --
            // dieselbe Zweiteilung wie `openTab`/`openAbsoluteTab` in
            // editor-view.ts.
            let wurzel = editor.wurzel
            if !wurzel.isEmpty, abs.hasPrefix(wurzel + "/") {
                let rel = String(abs.dropFirst(wurzel.count + 1))
                let ok = await editor.oeffnen(rel, zeile: zeile, spalte: spalte)
                guard ok else { return fehler(editor.notizSichtbar.isEmpty ? "nicht geöffnet" : editor.notizSichtbar) }
                return erfolg(abs, "text", "„\(rel)“ geöffnet.")
            }
            let name = o.name.isEmpty ? (abs.split(separator: "/").last.map(String.init) ?? abs) : o.name
            await editor.oeffnenAbsolut(key: abs, label: name, abs: abs, text: o.inhalt, zeile: zeile, spalte: spalte)
            return erfolg(abs, "text", "„\(name)“ geöffnet (schreibgeschützt).")
        default:
            return fehler("unbekannte Art „\(o.art)“ für \(abs)")
        }
    }

    private func erfolg(_ pfad: String, _ art: String, _ text: String) -> (ok: Bool, art: String, meldung: String) {
        letzterPfad = pfad
        letzteArt = art
        letzteMeldung = text
        melden?(text)
        return (true, art, text)
    }

    private func fehler(_ text: String) -> (ok: Bool, art: String, meldung: String) {
        letzteArt = ""
        letzteMeldung = text
        melden?(text)
        return (false, "", text)
    }

    func auskunft() -> [String: Any] {
        ["pfad": letzterPfad, "art": letzteArt, "meldung": letzteMeldung]
    }
}
