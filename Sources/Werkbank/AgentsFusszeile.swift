// DIE FUSSZEILE DES TABS „AGENTS" UND WAS SIE VOM KERN LIEST (14.09.2026,
// Auftrag agentsui Nr. 6). Bis zu diesem Tag stand hier das Aufgaben-Blatt aus
// Fassung 26 (AgentsBlatt.swift); seit Abnahme des Nutzers der Welten-Ansicht
// zeigt der Tab die Welten (WeltenBlatt.swift), und von jenem Blatt bleibt nur,
// was beide brauchen: die Fusszeile mit Traeger, Kern, Lebenszeichen,
// Agent-Verkehr, Tageslimit und Maschinen, die Antwort des Kerns auf eine
// Handlung und die Zeitform der Verlaeufe.
//
// KEIN EIGENES POLLEN: gelesen wird `kern.aufgaben`, das Ereignis
// `awb:aufgaben` (app/src/main/aufgaben.ts), das der Kern im Takt schickt.
// Die Welten kommen aus demselben Ereignis, Feld `welten` (WeltenNutzlast.swift).
import AppKit
import SwiftUI
import WerkbankProtokoll

// MARK: Die Nutzlast `awb:aufgaben` (app/src/main/aufgaben.ts)

private func text(_ j: [String: Any], _ k: String) -> String { j[k] as? String ?? "" }
/// Eine Zahl aus dem JSON -- aber kein Wahrheitswert. `is Bool` taugt dafuer nicht:
/// Swift bruecht jede NSNumber 0 oder 1 zu Bool (gemessen: Rang 1 kam als nil an).
private func zahl(_ j: [String: Any], _ k: String) -> Double? {
    guard let n = j[k] as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID() else { return nil }
    return n.doubleValue
}
private func objekt(_ j: [String: Any], _ k: String) -> [String: Any] { j[k] as? [String: Any] ?? [:] }
private func liste(_ j: [String: Any], _ k: String) -> [[String: Any]] { j[k] as? [[String: Any]] ?? [] }

struct TraegerStandAnzeige: Equatable, Sendable {
    let laeuft: Bool, seit: String?, aufgaben: Int
    let lebenszeit: String?, lebensOk: Bool?, lebensGrund: String?
    let agentVerkehr: String
    let verbraucht: Double?, erlaubt: Double?
    let maschinen: [String]
}

/// Was die Fusszeile aus `awb:aufgaben` braucht. Die Welten liest WeltenNutzlast.swift.
struct AufgabenNutzlast: Equatable, Sendable {
    let traeger: TraegerStandAnzeige
    let kernSauber: Bool?
    let fehler: [Quellfehler]
    let geladen: Bool
    /// Auftrag fernwelten: die Maschinen der Welten mit Verbindung und Traegern (`welten.maschinen`).
    var maschinen: [WeltMaschine] = []

    struct Quellfehler: Equatable, Sendable { let quelle, text: String }

    /// Nachsichtig gelesen: ein fehlendes Feld heisst „leer", nicht „kaputt" --
    /// der Kern darf Felder dazulegen, ohne dass diese Seite bricht.
    static func lesen(_ daten: Data) -> AufgabenNutzlast? {
        guard let j = try? JSONSerialization.jsonObject(with: daten) as? [String: Any] else { return nil }
        let t = objekt(j, "traeger"), lz = objekt(t, "lebenszeichen"), tl = objekt(t, "tageslimit")
        return AufgabenNutzlast(
            traeger: TraegerStandAnzeige(
                laeuft: t["laeuft"] as? Bool ?? false, seit: t["seit"] as? String, aufgaben: Int(zahl(t, "aufgaben") ?? 0),
                lebenszeit: lz["zeit"] as? String, lebensOk: lz["ok"] as? Bool, lebensGrund: lz["grund"] as? String,
                agentVerkehr: text(t, "agent_verkehr"), verbraucht: zahl(tl, "verbraucht"), erlaubt: zahl(tl, "erlaubt"),
                maschinen: t["maschinen"] as? [String] ?? []),
            kernSauber: j["kern_sauber"] as? Bool,
            fehler: liste(j, "fehler").map { Quellfehler(quelle: text($0, "quelle"), text: text($0, "text")) },
            geladen: j["geladen"] as? Bool ?? true,
            maschinen: liste(objekt(j, "welten"), "maschinen").map(WeltMaschine.init))
    }
}

/// Die Antwort des Kerns auf eine Handlung (`WeltenHandlungsErgebnis` in app/src/main/welten.ts).
struct HandlungsAntwort: Sendable {
    var ok = false, meldung = "", rueckfrage: String? = nil, warnungen: [String] = [], pfad = "", pane = "", sitzung = ""
    /// `welt:maschinen`: die Maschinen nach der Probe.
    var maschinen: [WeltMaschine] = []

    init(ok: Bool, meldung: String) { self.ok = ok; self.meldung = meldung }

    init(_ a: KernAntwort) {
        guard a.ok, let w = a.wertJSON, let j = try? JSONSerialization.jsonObject(with: w) as? [String: Any] else {
            meldung = a.fehler ?? "Der Kern hat nicht geantwortet."
            return
        }
        ok = j["ok"] as? Bool ?? false
        meldung = text(j, "meldung"); rueckfrage = j["rueckfrage"] as? String
        warnungen = j["warnungen"] as? [String] ?? []
        pfad = text(j, "pfad"); pane = text(j, "pane"); sitzung = text(j, "sitzung")
        maschinen = liste(j, "maschinen").map(WeltMaschine.init)
    }
}

// MARK: Worte und Zeiten

enum AgentsWorte {
    static func maschine(_ m: String) -> String { m == "mac" ? "Mac" : m }

    /// Eine Zeit aus dem Verlauf: heute als Uhrzeit, sonst mit Tag.
    static func uhrzeit(_ iso: String?) -> String {
        guard let iso, !iso.isEmpty else { return "" }
        let f = ISO8601DateFormatter()
        var d = f.date(from: iso)
        if d == nil { f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]; d = f.date(from: iso) }
        guard let d else { return iso }
        let aus = DateFormatter()
        aus.locale = Locale(identifier: "de_DE")
        aus.dateFormat = Calendar.current.isDateInToday(d) ? "HH:mm" : "dd.MM. HH:mm"
        return aus.string(from: d)
    }

    /// Die Fusszeile, als Woerter -- dieselben fuer Bildschirm und Auskunft.
    static func fuss(_ n: AufgabenNutzlast?) -> [(art: Punktart?, text: String)] {
        guard let n else { return [(nil, "Kein Stand vom Kern")] }
        let t = n.traeger
        var raus: [(Punktart?, String)] = []
        let aufgaben = t.aufgaben == 1 ? "1 Aufgabe" : "\(t.aufgaben) Aufgaben"
        raus.append(t.laeuft ? (.laeuft, "Träger läuft\(t.seit.map { " seit \(uhrzeit($0))" } ?? ""), \(aufgaben)") : (.aus, "Träger läuft nicht, \(aufgaben)"))
        switch n.kernSauber {
        case true?: raus.append((.laeuft, "Kern sauber"))
        case false?: raus.append((.will, "Kern nicht sauber"))
        case nil: raus.append((.ruhig, "Kern ungeprüft"))
        }
        if let z = t.lebenszeit {
            let ok = t.lebensOk == true
            raus.append((ok ? .laeuft : .aus, "Lebenszeichen \(uhrzeit(z)) \(ok ? "ok" : "fehlgeschlagen")\(!ok && !(t.lebensGrund ?? "").isEmpty ? ": \(t.lebensGrund!)" : "")"))
        } else {
            raus.append((.ruhig, "noch kein Lebenszeichen"))
        }
        raus.append(t.agentVerkehr == "pausiert" ? (.pausiert, "Agent-Verkehr pausiert") : (.laeuft, "Agent-Verkehr offen"))
        if let v = t.verbraucht, let e = t.erlaubt {
            raus.append((v > e ? .will : nil, "Tageslimit \(Int(v.rounded())) von \(Int(e.rounded()))"))
        } else {
            raus.append((nil, "Tageslimit unbekannt"))
        }
        if !t.maschinen.isEmpty { raus.append((nil, t.maschinen.map(maschine).joined(separator: ", "))) }
        // Auftrag fernwelten: dahinter jede Agent-Maschine, die der Kern schon gefragt hat, mit Verbindung und Traegern.
        raus += WeltenWorte.maschinenFuss(n.maschinen)
        return raus
    }
}

// MARK: Die Fusszeile

struct AgentsFusszeile: View {
    let nutzlast: AufgabenNutzlast?

    var body: some View {
        let teile = AgentsWorte.fuss(nutzlast)
        HStack(spacing: 8) {
            ForEach(Array(teile.enumerated()), id: \.offset) { i, t in
                if i > 0 { Text("·").foregroundStyle(.tertiary).accessibilityHidden(true) }
                HStack(spacing: 4) {
                    if let p = t.art { Zustandspunkt(art: p) }
                    Text(t.text).lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .font(.callout)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("agents-fuss")
    }
}
