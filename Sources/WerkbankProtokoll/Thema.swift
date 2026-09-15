// DAS THEMA DES KERNS (`awb:thema-neu`, `awb:thema-daten`; main/thema.ts).
//
// Der Kern rechnet die vier Zustandsfarben EINMAL aus und schickt sie an jedes
// Fenster: die Werte, die der Mensch in den Einstellungen gewaehlt hat
// (`zustandsfarben`), und dieselben Werte kontrastgeprueft gegen den Grund des
// wirksamen Erscheinungsbildes (`zustandsfarbenLesbar`). Die Mac-Fassung nimmt
// die geprueften -- so steht dort dieselbe Farbe wie in der Electron-Fassung,
// und eine Aenderung in den Einstellungen kommt ohne Zutun an.
//
// Nicht zu verwechseln mit den ROLLEN-Farben `laeuft/will/aus/fern` derselben
// Datei: die sind der feste Akzent der Umgebung (Unterstrich am gewaehlten
// Editor-Tab, linker Rand einer Antragskarte, Schrift einer Fehlerzeile) und
// nicht vom Menschen einstellbar. Die Zustandspunkte lesen `--zustand-*`, also
// die hier. Siehe mac/PLAN.md, „Zwei Paletten, zwei Aufgaben".
import Foundation

public struct ThemaNutzlast: Sendable, Equatable {
    /// Die Einstellung, wie sie dasteht: 'system', 'hell' oder 'dunkel'.
    public let thema: String
    /// 'hell' oder 'dunkel' -- 'system' ist hier schon aufgeloest.
    public let wirksam: String
    /// Die vier Farben, wie der Mensch sie gesetzt hat: laeuft, wartet, fertig, tot.
    public let zustandsfarben: [String: String]
    /// Dieselben vier, kontrastgeprueft gegen den Grund des Erscheinungsbildes.
    public let zustandsfarbenLesbar: [String: String]

    public init(thema: String = "", wirksam: String = "", zustandsfarben: [String: String] = [:], zustandsfarbenLesbar: [String: String] = [:]) {
        self.thema = thema
        self.wirksam = wirksam
        self.zustandsfarben = zustandsfarben
        self.zustandsfarbenLesbar = zustandsfarbenLesbar
    }

    public init(json j: JSONWert) {
        thema = j["thema"].text ?? ""
        wirksam = j["wirksam"].text ?? ""
        zustandsfarben = (j["zustandsfarben"].objekt ?? [:]).compactMapValues(\.text)
        zustandsfarbenLesbar = (j["zustandsfarbenLesbar"].objekt ?? [:]).compactMapValues(\.text)
    }

    public static func lesen(_ daten: Data) -> ThemaNutzlast { ThemaNutzlast(json: JSONWert.lesen(daten)) }

    /// Ob ueberhaupt etwas angekommen ist -- ohne das bleibt es bei den Systemfarben.
    public var da: Bool { !zustandsfarbenLesbar.isEmpty }
}
