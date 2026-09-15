// Das Sitzungsfenster (Auftrag 2.7, ⌘N): eine neue Sitzung anlegen, eine
// bekannte fortsetzen oder beenden. Ein eigenes Fenster wie in der
// Electron-Fassung (sitzungsfenster.ts), als `Form(.grouped)` mit Gruppen --
// Ordner, Maschine, Rolle, Programm, Modell, Denkstufe, Kontextfenster --
// und darunter die bekannten Sitzungen nach Ordner. Daten und Texte kommen
// vom Kern (`awb:sitz-daten`, `awb:sitz-daten-neu`, `awb:sitz-wahl-daten`,
// `awb:sitz-texte`); gestartet, fortgesetzt und beendet wird ueber dieselben
// Kanaele wie dort (`awb:sitz-neu[-wahl|-chat]`, `awb:sitz-fortsetzen`,
// `awb:sitz-beenden`, `awb:sitz-fern-pruefen`).
//
// DIE AUFLAGE AUS DIESEM HAUS, wie beim Einstellungsfenster: `bauen()` baut
// und liest, ohne zu zeigen (der Weg des Steuerkanals, `awbmac-ctl sitzung`);
// `zeigen()` ist der einzige Weg auf den Bildschirm (⌘N) und kopflos
// wirkungslos. Der Ordnerdialog (NSOpenPanel) und die Rueckfrage vor dem
// Beenden (NSAlert-Sheet) entstehen nur nach einem Klick des Menschen im
// sichtbaren Fenster; kopflos springen die Attrappen des Kerns ein
// (`AWB_ORDNER_DIALOG`, `AWB_RUECKFRAGE`), dieselben, mit denen die
// Electron-Suite prueft.
//
// Textstile, Systemfarben, Systemakzent; keine festen Punktgroessen fuer Text,
// keine fest verdrahteten Farben, keine Emojis.
import AppKit
import SwiftUI
import WerkbankProtokoll

/// Welche Art Sitzung entsteht: ein Orchestrator in tmux (`awb:sitz-neu`) oder
/// eine Chat-Sitzung als Prozess dieser App (`awb:sitz-neu-chat`).
enum SitzungsRolle: String, CaseIterable, Sendable {
    case orchestrator, chat
}

// MARK: Der Zustand

@MainActor
@Observable
final class SitzungsZustand {
    let kern: KernVerbindung
    /// Kopflos: kein Dialog, kein Sheet, `echt` nie wahr.
    let kopflos: Bool

    private(set) var daten: SitzungsDaten?
    private(set) var texte = Texte()
    private(set) var wahlDaten: WahlDaten?
    private(set) var wahlFehler = ""
    private(set) var wahlLaedt = false
    /// Die Wahl fuer genau diese Sitzung, vorbelegt aus den Einstellungen.
    var wahl = SitzungsWahl()
    var rolle: SitzungsRolle = .orchestrator
    var name = ""
    /// Die Zielmaschine; leer heisst die eigene.
    var maschine = ""
    var fernPfad = ""
    private(set) var fernStatus = ""
    private(set) var fernStatusArt = ""
    private(set) var fernPrueft = false
    var suche = ""
    var zustandFilter = "alle"
    var gewaehlt = ""
    /// Die Fusszeile: die letzte Meldung des Kerns, wortwoertlich, mit Art ("", "gut", "fehler").
    private(set) var status = ""
    private(set) var statusArt = ""
    private(set) var beschaeftigt = false
    private(set) var kontextStand: [String: KontextAntwort] = [:]
    /// Die letzte Rueckfrage (vor dem Beenden) und ihre Antwort -- fuer `awbmac-ctl ui` und den Beleg.
    private(set) var letzteRueckfrage: (titel: String, text: String, knopf: String, antwort: String)?
    private(set) var zeichnungen = 0
    /// Das Fenster stellt die Rueckfrage (Sheet); kopflos entscheidet die Attrappe. Antwort: ja/nein.
    @ObservationIgnored var frage: ((_ titel: String, _ text: String, _ knopf: String) async -> Bool)?
    /// Das Fenster oeffnet den Ordnerdialog (NSOpenPanel); leer heisst abgebrochen. Kopflos nil.
    @ObservationIgnored var ordnerWaehlen: (() async -> String)?
    @ObservationIgnored private var kontextLaeuft: Set<String> = []
    @ObservationIgnored private var handlung: Task<Void, Never>?

    init(kern: KernVerbindung, kopflos: Bool) {
        self.kern = kern
        self.kopflos = kopflos
    }

    // MARK: Laden

    func laden() async {
        let t = await kern.invoke("awb:sitz-texte")
        if let w = t.wertJSON { texte = Texte(json: JSONWert.lesen(w)) }
        let d = await kern.invoke("awb:sitz-daten")
        if let w = d.wertJSON { datenAngekommen(w) }
        await wahlLaden()
    }

    /// Ein neuer Stand (`awb:sitz-daten-neu` oder die Antwort auf `awb:sitz-daten`). Derselbe Stand baut nicht neu.
    func datenAngekommen(_ zeile: Data) {
        let neu = SitzungsDaten.lesen(zeile)
        if let alt = daten, alt == neu { return }
        let spracheAlt = daten?.sprache
        daten = neu
        if !gewaehlt.isEmpty, !neu.sitzungen.contains(where: { $0.id == gewaehlt }) { gewaehlt = "" }
        if !maschine.isEmpty, maschine != neu.machine, !neu.remoteMachines.contains(maschine) { maschine = "" }
        zeichnungen += 1
        if spracheAlt != nil, spracheAlt != neu.sprache {
            Task { @MainActor in
                let t = await kern.invoke("awb:sitz-texte")
                if let w = t.wertJSON { texte = Texte(json: JSONWert.lesen(w)) }
            }
        }
    }

    /// `awb:sitz-startfehler`: der Grund, warum eine Sitzung nicht kam -- in die Fusszeile.
    func startfehlerAngekommen(_ zeile: Data) {
        let j = JSONWert.lesen(zeile)
        let kurz = j["kurz"].text ?? ""
        let grund = j["grund"].text ?? ""
        let ort = j["ort"].text ?? ""
        let text = [kurz.isEmpty ? "" : kurz, grund].filter { !$0.isEmpty }.joined(separator: "\n")
        melde(text.isEmpty ? "Die Sitzung in \(ort) ist nicht gestartet." : text, "fehler")
    }

    /// Was zur Wahl steht -- einmal, und die Vorbelegung aus den Einstellungen (wahlHolen in sitzung.ts).
    func wahlLaden() async {
        wahlLaedt = true
        let a = await kern.invoke("awb:sitz-wahl-daten")
        wahlLaedt = false
        guard let w = a.wertJSON else { wahlFehler = a.fehler ?? "keine Antwort"; return }
        let d = WahlDaten.lesen(w)
        wahlDaten = d
        wahlFehler = ""
        if wahl.harness.isEmpty { wahl.harness = d.einstellung.harness }
        if wahl.model.isEmpty { wahl.model = d.einstellung.model }
        if wahl.effort.isEmpty { wahl.effort = d.einstellung.effort }
        if wahl.kontext == 0 { wahl.kontext = d.einstellung.kontext }
    }

    func kontextHolen(_ modellId: String) {
        guard !modellId.isEmpty, !kontextLaeuft.contains(modellId), kontextStand[modellId] == nil else { return }
        kontextLaeuft.insert(modellId)
        Task { @MainActor in
            let a = await kern.invoke("awb:kontext-stufen", [modellId])
            kontextStand[modellId] = KontextAntwort.lesen(a.wertJSON)
            kontextLaeuft.remove(modellId)
        }
    }

    // MARK: Abgeleitetes

    var eigeneMaschine: String { daten?.machine ?? "" }
    var remoteMachines: [String] { daten?.remoteMachines ?? [] }
    /// Die Maschine, an die der Start geht: leer heisst die eigene.
    var zielMaschine: String { maschine.isEmpty ? eigeneMaschine : maschine }
    var fern: Bool { !zielMaschine.isEmpty && zielMaschine != eigeneMaschine }
    /// Die Optionen des Maschinenwaehlers -- nur, wenn es mehr als die eigene gibt (sitzung.ts).
    var maschinenOptionen: [String] { remoteMachines.isEmpty ? [] : [eigeneMaschine] + remoteMachines }
    /// Die Ordner, die auf der gewaehlten Fernmaschine schon eine Sitzung tragen (die datalist der Electron-Fassung).
    var bekannteFernOrdner: [String] {
        guard fern, let d = daten else { return [] }
        var gesehen: Set<String> = []
        return d.sitzungen.filter { $0.machine == zielMaschine }.map(\.dir).filter { gesehen.insert($0).inserted }
    }

    var aktuellesModell: WahlModell? { wahlDaten?.modelle.first { $0.id == wahl.model } }
    var stufen: [String] { wahlDaten?.stufen(fuer: wahl.harness) ?? [] }
    /// Die Flaggen, die WIRKLICH mitgehen: keine, solange die Wahl die der Einstellungen ist.
    var flaggen: [String] { wahlIstVorgabe ? [] : wahl.flaggen(lokal: aktuellesModell?.lokal ?? false, stufen: stufen) }
    /// Die Wahl ist die aus den Einstellungen: dann geht der Start ohne Flaggen (`awb:sitz-neu`).
    var wahlIstVorgabe: Bool {
        guard let e = wahlDaten?.einstellung else { return true }
        return wahl.harness == e.harness && wahl.model == e.model && (wahl.effort == e.effort || !stufen.contains(wahl.effort))
            && (wahl.kontext == 0 || wahl.kontext == e.kontext || !(aktuellesModell?.lokal ?? false))
    }
    /// Die Wahl, die mitgeht -- wie `neueSitzungMitWahl` in sitzung.ts.
    var wahlZumStart: SitzungsWahl {
        SitzungsWahl(harness: wahl.harness, model: wahl.model,
                     effort: stufen.contains(wahl.effort) ? wahl.effort : "",
                     kontext: (aktuellesModell?.lokal ?? false) ? wahl.kontext : 0)
    }

    var alleZeilen: [SitzungsZeileDaten] { daten?.sitzungen ?? [] }
    /// Die Zustands-Chips aus den Werten, die wirklich vorkommen; leer bei nur einem (filter.ts `chipsAus`).
    var zustandChips: [(wert: String, label: String)] {
        var zahl: [String: Int] = [:]
        var reihenfolge: [String] = []
        for z in alleZeilen { if zahl[z.state] == nil { reihenfolge.append(z.state) }; zahl[z.state, default: 0] += 1 }
        guard zahl.count >= 2 else { return [] }
        let sortiert = reihenfolge.sorted { (zahl[$0] ?? 0) > (zahl[$1] ?? 0) }
        return [("alle", texte.t("wort.alle", ["n": String(alleZeilen.count)]))]
            + sortiert.map { ($0, "\(zustandWort($0)) \(zahl[$0] ?? 0)") }
    }
    var sichtbareZeilen: [SitzungsZeileDaten] {
        alleZeilen.filter { $0.passt(suche: suche) && (zustandFilter == "alle" || $0.state == zustandFilter) }
    }
    var gruppen: [SitzungsGruppe] { SitzungsDaten.gruppieren(sichtbareZeilen) }
    var gewaehlteZeile: SitzungsZeileDaten? { alleZeilen.first { $0.id == gewaehlt } }
    var grundText: String { gewaehlteZeile?.grund ?? texte.t("satz.waehleSitzung") }
    var fortsetzenGesperrt: Bool { beschaeftigt || !(gewaehlteZeile?.fortsetzbar ?? false) }
    var beendenGesperrt: Bool { beschaeftigt || !(gewaehlteZeile?.laeuftGerade ?? false) }
    var startGesperrt: Bool { beschaeftigt || (rolle == .orchestrator && wahl.model.isEmpty && !wahlIstVorgabe) }

    /// Der Zustand als Wort (zustandMarke in sitzung.ts) -- aus der Texttabelle des Kerns.
    func zustandWort(_ state: String, startet: Bool = false, startFehler: Bool = false) -> String {
        if startet { return texte.t("zustand.startet") }
        if startFehler { return texte.t("zustand.startFehler") }
        switch state {
        case "running": return texte.t("zustand.laeuft")
        case "attention": return texte.t("zustand.wartet")
        case "unreachable": return texte.t("zustand.fern")
        default: return texte.t("zustand.beendet")
        }
    }

    /// Wann zuletzt: `dd.MM. HH:mm` wie `wann()` in sitzung.ts.
    func wann(_ iso: String) -> String {
        guard !iso.isEmpty else { return texte.t("zeit.nieAktiv") }
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let d = f.date(from: iso) ?? { f.formatOptions = [.withInternetDateTime]; return f.date(from: iso) }()
        guard let datum = d else { return iso }
        let aus = DateFormatter()
        aus.dateFormat = "dd.MM. HH:mm"
        return aus.string(from: datum)
    }

    /// Die Titel der Gruppen, wie das Blatt sie zeigt -- die Abnahme liest sie.
    var gruppenTitel: [String] {
        var t = [texte.t("gruppe.ordner")]
        if !maschinenOptionen.isEmpty { t.append(texte.t("gruppe.maschine")) }
        t.append(texte.t("gruppe.rolle"))
        if rolle == .orchestrator {
            t += [texte.t("gruppe.harness"), texte.t("gruppe.modell"), texte.t("gruppe.effort")]
            if aktuellesModell?.lokal ?? false { t.append(texte.t("wahl.kontext")) }
        }
        t.append(texte.t("gruppe.sitzungen"))
        return t
    }

    func melde(_ text: String, _ art: String = "") {
        status = text
        statusArt = art
    }

    // MARK: Die Wahl

    func harnessWaehlen(_ id: String) {
        guard wahl.harness != id, let d = wahlDaten else { return }
        wahl.harness = id
        let passend = d.modelle(fuer: id)
        wahl.model = passend.contains { $0.id == wahl.model } ? wahl.model : (passend.first?.id ?? "")
        let s = d.stufen(fuer: id)
        if !s.contains(wahl.effort) { wahl.effort = s.last ?? "" }
        wahl.kontext = 0
    }

    func modellWaehlen(_ id: String) {
        guard wahl.model != id else { return }
        wahl.model = id
        wahl.kontext = 0
    }

    // MARK: Die Handlungen -- dieselben Kanaele wie die Electron-Fassung

    private func antwort(_ a: KernAntwort) -> (ok: Bool, meldung: String, command: String) {
        let j = a.wertJSON.map(JSONWert.lesen) ?? .null
        return (j["ok"].bool ?? false, j["meldung"].text ?? (a.fehler ?? ""), j["command"].text ?? "")
    }

    private func meldeAntwort(_ r: (ok: Bool, meldung: String, command: String)) {
        melde(r.command.isEmpty ? r.meldung : "\(r.meldung)\n\(r.command)", r.ok ? "gut" : "fehler")
    }

    /// Eine neue Sitzung: Orchestrator (`awb:sitz-neu` ohne eigene Wahl, sonst
    /// `awb:sitz-neu-wahl`) oder Chat (`awb:sitz-neu-chat`). `echt`: der Mensch
    /// hat im sichtbaren Fenster geklickt -- nur dann gibt es einen Ordnerdialog.
    func neu(echt: Bool) {
        guard !beschaeftigt else { return }
        if rolle == .orchestrator, fern, fernPfad.trimmingCharacters(in: .whitespaces).isEmpty {
            melde(texte.t("satz.erstOrdnerEintragen", ["maschine": zielMaschine]), "fehler")
            return
        }
        let e = echt && !kopflos
        beschaeftigt = true
        melde(texte.t("satz.startetGerade"))
        handlung = Task { @MainActor in
            defer { beschaeftigt = false }
            var ordner = ""
            if e, rolle == .chat || !fern, let waehlen = ordnerWaehlen {
                ordner = await waehlen()
                if ordner.isEmpty { melde("Abgebrochen -- es wurde nichts gestartet.", "fehler"); return }
            }
            let r: (ok: Bool, meldung: String, command: String)
            switch rolle {
            case .chat:
                r = antwort(await kern.invoke("awb:sitz-neu-chat", [name, e, ordner]))
            case .orchestrator:
                let ziel = fern ? zielMaschine : ""
                if wahlIstVorgabe {
                    r = antwort(await kern.invoke("awb:sitz-neu", [name, ziel, fernPfad, e, ordner]))
                } else {
                    r = antwort(await kern.invoke("awb:sitz-neu-wahl", [name, ziel, fernPfad, wahlZumStart.fuerJSON, e, ordner]))
                }
            }
            meldeAntwort(r)
            if r.ok {
                name = ""
                fernPfad = ""
                fernStatus = ""
                // Die Wahl gilt EINER Sitzung; danach wieder die Einstellungen (sitzung.ts).
                wahl = SitzungsWahl()
                wahlDaten = nil
                await wahlLaden()
            }
        }
    }

    func fortsetzen(echt: Bool) {
        guard !beschaeftigt, let z = gewaehlteZeile, z.fortsetzbar else { return }
        beschaeftigt = true
        melde(texte.t("satz.holeZurueck"))
        handlung = Task { @MainActor in
            defer { beschaeftigt = false }
            meldeAntwort(antwort(await kern.invoke("awb:sitz-fortsetzen", [z.id, echt && !kopflos])))
        }
    }

    /// Beenden mit Rueckfrage: das Fenster fragt (Sheet; kopflos die Attrappe
    /// `AWB_RUECKFRAGE`), dann `awb:sitz-beenden` mit `bestaetigt`, damit der
    /// Kern nicht ein zweites Mal fragt. Nein heisst: nichts wird gerufen.
    func beenden(echt: Bool) {
        guard !beschaeftigt, let z = gewaehlteZeile, z.laeuftGerade else { return }
        beschaeftigt = true
        handlung = Task { @MainActor in
            defer { beschaeftigt = false }
            let titel = texte.t("frage.beenden", ["name": z.name])
            let text = texte.t("frage.beendenText")
            let knopf = texte.t("knopf.beenden")
            let ja = await frage?(titel, text, knopf) ?? false
            letzteRueckfrage = (titel, text, knopf, ja ? "ja" : "nein")
            guard ja else { melde(texte.t("satz.abgebrochenNichtsBeendet"), "fehler"); return }
            meldeAntwort(antwort(await kern.invoke("awb:sitz-beenden", [z.id, echt && !kopflos, true])))
        }
    }

    /// Der Pruefen-Knopf neben dem Fernpfad -- dieselbe Pruefung, die der Start noch einmal tut.
    func fernPruefen() {
        guard fern, !fernPrueft else { return }
        let pfad = fernPfad.trimmingCharacters(in: .whitespaces)
        guard !pfad.isEmpty else { fernStatus = texte.t("satz.erstPfadEintragen"); fernStatusArt = "fehler"; return }
        fernPrueft = true
        fernStatus = texte.t("satz.pruefeGerade")
        fernStatusArt = ""
        handlung = Task { @MainActor in
            defer { fernPrueft = false }
            let a = await kern.invoke("awb:sitz-fern-pruefen", [zielMaschine, pfad])
            let j = a.wertJSON.map(JSONWert.lesen) ?? .null
            fernStatus = j["meldung"].text ?? (a.fehler ?? "")
            fernStatusArt = (j["ok"].bool ?? false) ? "gut" : "fehler"
        }
    }

    /// Warten, bis die laufende Handlung durch ist (hoechstens `sekunden`) -- fuer den Steuerkanal.
    func handlungAbwarten(sekunden: Double = 20) async {
        let bis = Date().addingTimeInterval(sekunden)
        while beschaeftigt || fernPrueft, Date() < bis {
            try? await Task.sleep(for: .milliseconds(30))
        }
    }

    // MARK: Der Steuerkanal -- klicken, tippen, lesen (kein Mensch)

    @discardableResult
    func klick(_ kennung: String) -> Bool {
        if kennung.hasPrefix("zeile:") {
            let id = String(kennung.dropFirst(6))
            guard alleZeilen.contains(where: { $0.id == id }) else { return false }
            gewaehlt = id
            return true
        }
        if kennung.hasPrefix("filter:") { zustandFilter = String(kennung.dropFirst(7)); return true }
        if kennung.hasPrefix("rolle:") { return eingabe("neu-rolle", String(kennung.dropFirst(6))) }
        if kennung.hasPrefix("harness:") { return eingabe("neu-harness", String(kennung.dropFirst(8))) }
        if kennung.hasPrefix("modell:") { return eingabe("neu-modell", String(kennung.dropFirst(7))) }
        if kennung.hasPrefix("effort:") { return eingabe("neu-effort", String(kennung.dropFirst(7))) }
        if kennung.hasPrefix("kontext:") { return eingabe("neu-kontext", String(kennung.dropFirst(8))) }
        switch kennung {
        case "neu-start": neu(echt: false); return true
        case "fort-start": fortsetzen(echt: false); return true
        case "beenden-start": beenden(echt: false); return true
        case "neu-fern-pruefen": fernPruefen(); return true
        default: return false
        }
    }

    @discardableResult
    func eingabe(_ kennung: String, _ wert: String) -> Bool {
        switch kennung {
        case "neu-name": name = wert
        case "neu-fern-pfad": fernPfad = wert; fernStatus = ""
        case "neu-maschine":
            guard wert == eigeneMaschine || remoteMachines.contains(wert) else { return false }
            maschine = wert == eigeneMaschine ? "" : wert
            fernStatus = ""
        case "such-feld": suche = wert
        case "zustand-filter": zustandFilter = wert
        case "neu-rolle":
            guard let r = SitzungsRolle(rawValue: wert) else { return false }
            rolle = r
        case "neu-harness":
            guard wahlDaten?.harnesses.contains(where: { $0.id == wert }) ?? false else { return false }
            harnessWaehlen(wert)
        case "neu-modell":
            guard wahlDaten?.modelle(fuer: wahl.harness).contains(where: { $0.id == wert }) ?? false else { return false }
            modellWaehlen(wert)
        case "neu-effort":
            guard stufen.contains(wert) else { return false }
            wahl.effort = wert
        case "neu-kontext":
            guard let n = Int(wert) else { return false }
            wahl.kontext = n
        default: return false
        }
        return true
    }

    /// NUR LESEN, wie `sitzung-zustand` der Electron-Fassung.
    func zustandAuskunft(_ kennung: String) -> [String: Any] {
        if kennung.hasPrefix("zeile:") {
            let id = String(kennung.dropFirst(6))
            guard let z = alleZeilen.first(where: { $0.id == id }) else { return ["da": false] }
            return ["da": true, "gewaehlt": gewaehlt == id, "fortsetzbar": z.fortsetzbar, "sichtbar": sichtbareZeilen.contains { $0.id == id },
                    "text": zeilenText(z), "state": z.state, "grund": z.grund]
        }
        switch kennung {
        case "neu-name": return ["da": true, "wert": name]
        case "neu-maschine": return ["da": !maschinenOptionen.isEmpty, "wert": zielMaschine, "optionen": maschinenOptionen]
        case "neu-fern": return ["da": true, "angezeigt": fern && rolle == .orchestrator,
                                 "text": fern ? "\(texte.t("platzhalter.fernpfad", ["maschine": zielMaschine])) \(texte.t("knopf.pruefen")) \(fernStatus)" : ""]
        case "neu-fern-pfad": return ["da": true, "wert": fernPfad]
        case "neu-fern-status": return ["da": true, "text": fernStatus, "art": fernStatusArt]
        case "neu-fern-ordner": return ["da": true, "optionen": bekannteFernOrdner]
        case "neu-rolle": return ["da": true, "wert": rolle.rawValue, "optionen": SitzungsRolle.allCases.map(\.rawValue),
                                  "text": SitzungsRolle.allCases.map { texte.t("rolle.\($0.rawValue)") }.joined(separator: " ")]
        case "neu-harness":
            let hs = wahlDaten?.harnesses ?? []
            return ["da": rolle == .orchestrator, "wert": wahl.harness, "optionen": hs.map { ["wert": $0.id, "label": $0.label] },
                    "text": hs.map { harnessText($0) }.joined(separator: " | ")]
        case "neu-modell":
            let ms = wahlDaten?.modelle(fuer: wahl.harness) ?? []
            return ["da": rolle == .orchestrator, "wert": wahl.model, "optionen": ms.map { ["wert": $0.id, "label": $0.label] },
                    "text": (ms.map { "\($0.label) \($0.id)" } + [deckelText]).joined(separator: " | ")]
        case "neu-effort":
            return ["da": rolle == .orchestrator, "wert": stufen.contains(wahl.effort) ? wahl.effort : "", "optionen": stufen,
                    "text": (stufen.isEmpty ? [texte.t("wahl.keineStufen")] : stufen + [deckelText]).joined(separator: " ")]
        case "neu-kontext":
            var text = texte.t("wahl.kontextNurLokal")
            var optionen: [Int] = []
            if aktuellesModell?.lokal ?? false, case .sicht(let s)? = kontextStand[wahl.model] { optionen = s.stufen.map(\.tokens); text = s.stufen.map(\.label).joined(separator: " ") }
            return ["da": aktuellesModell?.lokal ?? false, "wert": wahl.kontext, "optionen": optionen, "text": text]
        case "neu-flaggen": return ["da": true, "text": flaggen.isEmpty ? texte.t("wahl.flaggenLeer") : flaggen.joined(separator: " ")]
        case "neu-start": return ["da": true, "gesperrt": startGesperrt, "text": rolle == .chat ? texte.t("knopf.neuChat") : texte.t("knopf.start")]
        case "fort-start": return ["da": true, "gesperrt": fortsetzenGesperrt, "text": texte.t("knopf.fortsetzen")]
        case "beenden-start": return ["da": true, "gesperrt": beendenGesperrt, "text": texte.t("knopf.beenden")]
        case "fort-grund": return ["da": true, "text": grundText]
        case "such-feld": return ["da": true, "wert": suche]
        case "zustand-chips":
            let chips = zustandChips
            return ["da": !chips.isEmpty, "wert": zustandFilter, "optionen": chips.map(\.wert), "text": chips.map(\.label).joined(separator: " ")]
        case "gruppen": return ["da": true, "titel": gruppenTitel]
        case "statuszeile": return ["da": true, "text": status, "art": statusArt]
        default: return ["da": false]
        }
    }

    func harnessText(_ h: WahlHarness) -> String { h.binaer ? h.label : "\(h.label) · \(texte.t("wahl.nichtStartbar"))" }

    /// Die Deckelzeile unter der Stufenwahl: Registry-Wahrheit aus dem Kern, keine zweite Tabelle.
    var deckelText: String {
        guard !wahl.model.isEmpty else { return "" }
        guard let d = wahlDaten?.deckel(fuer: wahl.model) else { return texte.t("wahl.keinDeckel") }
        return texte.t("wahl.deckel", ["deckel": d.cap, "quelle": d.quelle])
    }

    func zeilenText(_ z: SitzungsZeileDaten) -> String {
        let womit = z.model.isEmpty ? (z.harness.isEmpty ? "claude" : z.harness) : "\(z.harness) · \(z.model)"
        return "\(z.name) \(zustandWort(z.state, startet: z.startet, startFehler: z.startFehler)) \(womit) — \(wann(z.lastActive))"
    }

    /// Alles, was das Blatt als Text zeigt -- fuer `grep` in einer Suite.
    func blattText() -> String {
        // Der Titel steht in der TITELLEISTE, nicht mehr im Blatt (08.09.2026),
        // und was hier steht, soll sein, was das Blatt wirklich zeigt.
        var t: [String] = [texte.t("kopf.unterzeile")]
        t += gruppenTitel
        t.append(name)
        if !maschinenOptionen.isEmpty { t.append(zielMaschine) }
        if fern { t += [fernPfad, fernStatus] }
        t.append(texte.t("rolle.\(rolle.rawValue)"))
        if rolle == .orchestrator {
            t += (wahlDaten?.harnesses ?? []).map { harnessText($0) }
            t += (wahlDaten?.modelle(fuer: wahl.harness) ?? []).map { "\($0.label) \($0.id)" }
            t += stufen
            t.append(deckelText)
            t.append(flaggen.isEmpty ? texte.t("wahl.flaggenLeer") : flaggen.joined(separator: " "))
        } else {
            t.append(texte.t("rolle.chatHinweis"))
        }
        for g in gruppen {
            t.append("\(g.zeilen.first?.ordnerName ?? "") \(g.machine == eigeneMaschine ? g.dir : "\(g.machine):\(g.dir)")")
            t += g.zeilen.map { zeilenText($0) }
        }
        t += [grundText, status]
        return t.filter { !$0.isEmpty }.joined(separator: "\n")
    }
}

// MARK: Das Fenster

@MainActor
final class SitzungsFenster: NSObject, NSWindowDelegate {
    let zustand: SitzungsZustand
    let fenster: NSWindow
    private let oberflaeche: Oberflaeche
    /// Die ganzen Laufoptionen, nicht nur `kopflos`: `zeigen()` braucht daneben
    /// `ohneFokus` (Laufoptionen.swift, `vorZeigen`).
    private let optionen: Laufoptionen
    private var kopflos: Bool { optionen.kopflos }
    private var geladen = false

    init(kern: KernVerbindung, optionen: Laufoptionen, oberflaeche: Oberflaeche) {
        self.optionen = optionen
        self.oberflaeche = oberflaeche
        zustand = SitzungsZustand(kern: kern, kopflos: optionen.kopflos)
        // 900 x 620, mindestens 700 x 460: die Masse der Electron-Fassung
        // (sitzungsfenster.ts) -- breit genug fuer einen Pfad in einer Zeile.
        fenster = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 620),
                           styleMask: [.titled, .closable, .miniaturizable, .resizable],
                           backing: .buffered, defer: false)
        super.init()
        fenster.title = "Sitzungen"
        fenster.minSize = NSSize(width: 700, height: 460)
        fenster.isReleasedWhenClosed = false
        fenster.titlebarSeparatorStyle = .automatic
        fenster.delegate = self
        fenster.identifier = NSUserInterfaceItemIdentifier("sitzungen")
        let inhalt = NSHostingController(rootView: SitzungsBlattAnsicht(zustand: zustand))
        inhalt.sizingOptions = []
        fenster.contentViewController = inhalt
        fenster.setContentSize(NSSize(width: 900, height: 620))
        zustand.frage = { [weak self] titel, text, knopf in await self?.rueckfrage(titel, text, knopf: knopf) ?? false }
        if !kopflos { zustand.ordnerWaehlen = { [weak self] in await self?.ordnerDialog() ?? "" } }
        kern.aufSitzungNeu = { [weak self] zeile in self?.zustand.datenAngekommen(zeile) }
        kern.aufStartfehler = { [weak self] zeile in self?.zustand.startfehlerAngekommen(zeile) }
    }

    /// Bauen und laden, OHNE zu zeigen -- der Weg des Steuerkanals. Mehrfach aufrufbar.
    func bauen() async {
        oberflaeche.sitzungenOffen = true
        fenster.layoutIfNeeded()
        if !geladen {
            geladen = true
            await zustand.laden()
            if !zustand.texte.leer { fenster.title = zustand.texte.t("kopf.titel") }
        }
    }

    /// DER EINZIGE WEG AUF DEN BILDSCHIRM: ⌘N. Kopflos ohne Wirkung.
    func zeigen() {
        Task { @MainActor in
            await bauen()
            guard !kopflos else { return }
            fenster.vorZeigen(ohneFokus: optionen.ohneFokus)
        }
    }

    var sichtbar: Bool { fenster.isVisible }

    func windowWillClose(_ notification: Notification) {
        oberflaeche.sitzungenOffen = false
    }

    /// Die Rueckfrage vor dem Beenden: kopflos die Attrappe `AWB_RUECKFRAGE`
    /// ('ja'/'nein', sonst nein) -- dieselbe Variable, die der Kern liest --,
    /// sichtbar ein Sheet an diesem Fenster, Abbrechen ist die Vorgabe.
    func rueckfrage(_ titel: String, _ text: String, knopf: String) async -> Bool {
        oberflaeche.letzteRueckfrage = titel
        if kopflos {
            let antwort = ProcessInfo.processInfo.environment["AWB_RUECKFRAGE"] == "ja"
            oberflaeche.letzteRueckfrageAntwort = antwort ? "ja" : "nein"
            return antwort
        }
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = titel
        alert.informativeText = text
        alert.addButton(withTitle: zustand.texte.t("knopf.abbrechen"))
        let tun = alert.addButton(withTitle: knopf)
        tun.hasDestructiveAction = true
        tun.keyEquivalent = ""
        let antwort = await alert.beginSheetModal(for: fenster)
        let ja = antwort == .alertSecondButtonReturn
        oberflaeche.letzteRueckfrageAntwort = ja ? "ja" : "nein"
        return ja
    }

    /// Der Ordner fuer eine neue Sitzung -- der Dialog des Systems, als Sheet
    /// an diesem Fenster. Nur sichtbar erreichbar (der Haken wird kopflos nicht gesetzt).
    private func ordnerDialog() async -> String {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Ordner für die neue Sitzung"
        panel.prompt = "Sitzung hier starten"
        let r = await panel.beginSheetModal(for: fenster)
        return r == .OK ? (panel.url?.path ?? "") : ""
    }

    /// Ein Belegbild, auch kopflos: der Rahmen in eine Bitmap, darueber das
    /// Blatt aus denselben Views ueber `ImageRenderer` (Einstellungen.swift,
    /// derselbe Grund: Form und Steuerelemente zeichnen ausserhalb des
    /// Bildschirms nichts). `rueckfrage`: die letzte Rueckfrage als Karte
    /// darueber, aus denselben Texten wie das Sheet.
    func schuss(pfad: String, rueckfrage: Bool = false) throws -> (breite: Int, hoehe: Int) {
        guard let rahmen = fenster.contentView?.superview else { throw NSError(domain: "Werkbank", code: 1, userInfo: [NSLocalizedDescriptionKey: "kein Fensterrahmen"]) }
        fenster.layoutIfNeeded()
        rahmen.layoutSubtreeIfNeeded()
        guard let rep = rahmen.bitmapImageRepForCachingDisplay(in: rahmen.bounds) else {
            throw NSError(domain: "Werkbank", code: 2, userInfo: [NSLocalizedDescriptionKey: "keine Bitmap"])
        }
        let dunkel = fenster.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        if let ctx = NSGraphicsContext(bitmapImageRep: rep) {
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = ctx
            fenster.effectiveAppearance.performAsCurrentDrawingAppearance {
                fenster.backgroundColor.setFill()
                NSRect(x: 0, y: 0, width: rep.pixelsWide, height: rep.pixelsHigh).fill()
            }
            NSGraphicsContext.restoreGraphicsState()
        }
        rahmen.cacheDisplay(in: rahmen.bounds, to: rep)
        func legen<V: View>(_ view: V, in ziel: NSRect, grund: NSColor?) {
            guard let ctx = NSGraphicsContext(bitmapImageRep: rep) else { return }
            let renderer = ImageRenderer(content: view.frame(width: ziel.width, height: ziel.height, alignment: .topLeading).environment(\.colorScheme, dunkel ? .dark : .light))
            renderer.scale = fenster.backingScaleFactor
            renderer.proposedSize = ProposedViewSize(width: ziel.width, height: ziel.height)
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = ctx
            if let grund {
                fenster.effectiveAppearance.performAsCurrentDrawingAppearance {
                    grund.setFill()
                    ziel.fill()
                }
            }
            renderer.nsImage?.draw(in: ziel, from: .zero, operation: .sourceOver, fraction: 1)
            NSGraphicsContext.restoreGraphicsState()
        }
        if let inhalt = fenster.contentView {
            legen(SitzungsBlattAnsicht(zustand: zustand, beleg: true), in: inhalt.convert(inhalt.bounds, to: nil), grund: fenster.backgroundColor)
            if rueckfrage, let r = zustand.letzteRueckfrage {
                let breite: CGFloat = 420
                let hoehe: CGFloat = 170
                let ziel = NSRect(x: (inhalt.bounds.width - breite) / 2, y: inhalt.bounds.height - hoehe - 8, width: breite, height: hoehe)
                legen(RueckfrageBeleg(titel: r.titel, text: r.text, knopf: r.knopf, abbrechen: zustand.texte.t("knopf.abbrechen")), in: ziel, grund: nil)
            }
        }
        guard let png = rep.representation(using: .png, properties: [:]) else {
            throw NSError(domain: "Werkbank", code: 3, userInfo: [NSLocalizedDescriptionKey: "kein PNG"])
        }
        try FileManager.default.createDirectory(at: URL(fileURLWithPath: pfad).deletingLastPathComponent(), withIntermediateDirectories: true)
        try png.write(to: URL(fileURLWithPath: pfad))
        return (rep.pixelsWide, rep.pixelsHigh)
    }

    /// Die Auskunft fuer `awbmac-ctl` (`ui.sitzung` und `sitzung`), mit den
    /// Feldnamen von `awb-ctl sitzung` (sichtbar, bereit, groesse, status, gruppen, sitzungen).
    func auskunft() -> [String: Any] {
        let z = zustand
        let gruppen: [[String: Any]] = z.gruppen.map { g in
            ["schluessel": g.schluessel, "dir": g.dir, "machine": g.machine,
             "kopf": "\(g.zeilen.first?.ordnerName ?? "") \(g.machine == z.eigeneMaschine ? g.dir : "\(g.machine):\(g.dir)")",
             "sichtbar": g.zeilen.map(\.id), "verborgen": 0, "anzahl": g.zeilen.count]
        }
        let sitzungen: [[String: Any]] = z.sichtbareZeilen.map { s in
            ["id": s.id, "name": s.name, "state": s.state, "fortsetzbar": s.fortsetzbar, "gewaehlt": s.id == z.gewaehlt,
             "text": z.zeilenText(s), "grund": s.grund, "machine": s.machine, "dir": s.dir]
        }
        var r: [String: Any] = [
            "gebaut": oberflaeche.sitzungenOffen,
            "sichtbar": fenster.isVisible,
            "bereit": z.daten != nil && !z.texte.leer,
            "groesse": [Int(fenster.contentView?.frame.width ?? 0), Int(fenster.contentView?.frame.height ?? 0)],
            "sprache": z.texte.sprache,
            "status": z.status,
            "statusArt": z.statusArt,
            "beschaeftigt": z.beschaeftigt,
            "zeichnungen": z.zeichnungen,
            "gruppen": gruppen,
            "gruppenTitel": z.gruppenTitel,
            "sitzungen": sitzungen,
            "bekannt": z.alleZeilen.count,
            "gewaehlt": z.gewaehlt,
            "neu": ["name": z.name, "maschine": z.zielMaschine, "fern": z.fern, "fernPfad": z.fernPfad, "rolle": z.rolle.rawValue,
                    "harness": z.wahl.harness, "modell": z.wahl.model, "effort": z.wahl.effort, "kontext": z.wahl.kontext,
                    "flaggen": z.flaggen, "wahlIstVorgabe": z.wahlIstVorgabe, "deckel": z.deckelText],
            "text": z.blattText(),
        ]
        if let f = z.letzteRueckfrage {
            r["rueckfrage"] = ["gestellt": true, "titel": f.titel, "text": f.text, "knopf": f.knopf, "antwort": f.antwort]
        } else {
            r["rueckfrage"] = ["gestellt": false]
        }
        return r
    }
}

// MARK: Das Blatt

struct SitzungsBlattAnsicht: View {
    let zustand: SitzungsZustand
    var beleg = false

    var body: some View {
        VStack(spacing: 0) {
            if zustand.daten == nil || zustand.texte.leer {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Sitzungen").font(.title2.weight(.semibold))
                    Text(zustand.kern.verbunden ? "Die Sitzungen werden vom Kern gelesen …" : "Kein Kern verbunden – die Sitzungen kommen, sobald er da ist.")
                        .foregroundStyle(.secondary)
                }
                .padding(20)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else if beleg {
                VStack(alignment: .leading, spacing: 12) { inhalt }
                    .padding(20)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            } else {
                Form { inhalt }
                    .formStyle(.grouped)
                    .accessibilityIdentifier("sitzungen-blatt")
            }
            SitzungsFuss(zustand: zustand, beleg: beleg)
        }
        .background(.background)
    }

    private var t: Texte { zustand.texte }

    @ViewBuilder
    private var inhalt: some View {
        // KEINE ZWEITE UEBERSCHRIFT (08.09.2026, Entscheidung des Nutzers). Der
        // Fenstertitel sagt schon „Sitzungen"; darunter stand dieselbe Zeile
        // noch einmal als Karte. Auf dem Mac traegt die Titelleiste den Namen
        // des Fensters, und der Inhalt faengt mit dem Inhalt an. Die
        // Unterzeile bleibt -- sie erklaert, was die Liste zeigt, und das
        // steht sonst nirgends. Die Electron-Fassung bleibt, wie sie ist:
        // dort gibt es keine Titelleiste, die den Titel schon traegt.
        gruppe(nil) {
            Text(t.t("kopf.unterzeile")).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        gruppe(t.t("gruppe.ordner")) { ordnerFelder }
        if !zustand.maschinenOptionen.isEmpty {
            gruppe(t.t("gruppe.maschine")) { maschinenFeld }
        }
        gruppe(t.t("gruppe.rolle")) { rolleFeld }
        if zustand.rolle == .orchestrator {
            gruppe(t.t("gruppe.harness")) { harnessFeld }
            gruppe(t.t("gruppe.modell")) { modellFeld }
            gruppe(t.t("gruppe.effort")) { effortFeld }
            if zustand.aktuellesModell?.lokal ?? false {
                gruppe(t.t("wahl.kontext")) { kontextFeld }
            }
        }
        gruppe(nil) { startzeile }
        gruppe(t.t("gruppe.sitzungen")) { sitzungsListe }
    }

    /// Eine Gruppe: im Formular eine Section, im Beleg ein Kasten mit Titel.
    @ViewBuilder
    private func gruppe<Inhalt: View>(_ titel: String?, @ViewBuilder _ inhalt: () -> Inhalt) -> some View {
        if beleg {
            VStack(alignment: .leading, spacing: 8) {
                if let titel { Text(titel).font(.headline) }
                inhalt()
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(.quaternary.opacity(0.5)))
        } else if let titel {
            Section { inhalt() } header: { Text(titel).font(.headline) }
        } else {
            Section { inhalt() }
        }
    }

    // MARK: Ordner, Maschine, Rolle

    @ViewBuilder
    private var ordnerFelder: some View {
        LabeledContent {
            if beleg {
                Kasten(zustand.name.isEmpty ? t.t("platzhalter.name") : zustand.name, blass: zustand.name.isEmpty)
            } else {
                TextField(t.t("platzhalter.name"), text: Binding(get: { zustand.name }, set: { zustand.name = $0 }))
                    .textFieldStyle(.roundedBorder)
                    .autocorrectionDisabled()
                    .frame(minWidth: 240)
                    .accessibilityLabel("Name")
                    .accessibilityIdentifier("neu-name")
            }
        } label: {
            Text("Name")
        }
        if zustand.fern && zustand.rolle == .orchestrator {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    if beleg {
                        Kasten(zustand.fernPfad.isEmpty ? t.t("platzhalter.fernpfad", ["maschine": zustand.zielMaschine]) : zustand.fernPfad, blass: zustand.fernPfad.isEmpty)
                        Text(t.t("knopf.pruefen")).font(.callout).padding(.horizontal, 10).padding(.vertical, 3).background(Capsule().fill(.quaternary))
                    } else {
                        TextField(t.t("platzhalter.fernpfad", ["maschine": zustand.zielMaschine]), text: Binding(get: { zustand.fernPfad }, set: { zustand.fernPfad = $0 }))
                            .textFieldStyle(.roundedBorder)
                            .font(.body.monospaced())
                            .autocorrectionDisabled()
                            .accessibilityLabel("Pfad auf \(zustand.zielMaschine)")
                            .accessibilityIdentifier("neu-fern-pfad")
                        if !zustand.bekannteFernOrdner.isEmpty {
                            Menu {
                                ForEach(zustand.bekannteFernOrdner, id: \.self) { o in Button(o) { zustand.fernPfad = o } }
                            } label: { Image(systemName: "clock.arrow.circlepath") }
                            .fixedSize()
                            .help("Bekannte Ordner auf \(zustand.zielMaschine)")
                            .accessibilityLabel("Bekannte Ordner")
                        }
                        Button(t.t("knopf.pruefen")) { zustand.fernPruefen() }
                            .disabled(zustand.fernPrueft)
                            .accessibilityIdentifier("neu-fern-pruefen")
                    }
                }
                if !zustand.fernStatus.isEmpty {
                    Label(zustand.fernStatus, systemImage: zustand.fernStatusArt == "gut" ? "checkmark.circle" : (zustand.fernStatusArt == "fehler" ? "xmark.octagon" : "ellipsis.circle"))
                        .font(.callout)
                        .foregroundStyle(zustand.fernStatusArt == "gut" ? AnyShapeStyle(.green) : (zustand.fernStatusArt == "fehler" ? AnyShapeStyle(.red) : AnyShapeStyle(.secondary)))
                        .accessibilityIdentifier("neu-fern-status")
                }
            }
        } else {
            Text(t.t("satz.ordnerImDialog")).font(.callout).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var maschinenFeld: some View {
        let optionen = zustand.maschinenOptionen
        if beleg {
            Kasten(zustand.zielMaschine == zustand.eigeneMaschine ? t.t("satz.dieseMaschine", ["maschine": zustand.zielMaschine]) : zustand.zielMaschine, pfeil: true)
        } else {
            Picker(selection: Binding(get: { zustand.zielMaschine }, set: { _ = zustand.eingabe("neu-maschine", $0) })) {
                ForEach(optionen, id: \.self) { m in
                    Text(m == zustand.eigeneMaschine ? t.t("satz.dieseMaschine", ["maschine": m]) : m).tag(m)
                }
            } label: { Text(t.t("gruppe.maschine")) }
            .pickerStyle(.menu)
            .fixedSize()
            .accessibilityIdentifier("neu-maschine")
        }
    }

    @ViewBuilder
    private var rolleFeld: some View {
        if beleg {
            Segmente(optionen: SitzungsRolle.allCases.map { ($0.rawValue, t.t("rolle.\($0.rawValue)")) }, wert: zustand.rolle.rawValue)
        } else {
            Picker(selection: Binding(get: { zustand.rolle }, set: { zustand.rolle = $0 })) {
                ForEach(SitzungsRolle.allCases, id: \.self) { r in Text(t.t("rolle.\(r.rawValue)")).tag(r) }
            } label: { EmptyView() }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            .accessibilityLabel(t.t("gruppe.rolle"))
            .accessibilityIdentifier("neu-rolle")
        }
        if zustand.rolle == .chat {
            Text(t.t("rolle.chatHinweis")).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Programm, Modell, Denkstufe, Kontext

    @ViewBuilder
    private var harnessFeld: some View {
        if let d = zustand.wahlDaten {
            if beleg {
                Kasten(d.harnesses.first { $0.id == zustand.wahl.harness }.map { zustand.harnessText($0) } ?? "–", pfeil: true)
            } else {
                Picker(selection: Binding(get: { zustand.wahl.harness }, set: { zustand.harnessWaehlen($0) })) {
                    ForEach(d.harnesses) { h in Text(zustand.harnessText(h)).tag(h.id) }
                } label: { Text(t.t("wahl.harness")) }
                .pickerStyle(.menu)
                .fixedSize()
                .accessibilityIdentifier("neu-harness")
            }
        } else {
            Text(zustand.wahlFehler.isEmpty ? t.t("wahl.laedt") : t.t("wahl.ladefehler", ["grund": zustand.wahlFehler]))
                .font(.callout).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var modellFeld: some View {
        if let d = zustand.wahlDaten {
            let eigene = d.modelle(fuer: zustand.wahl.harness)
            if eigene.isEmpty {
                Text(t.t("wahl.keinModell")).font(.callout).foregroundStyle(.secondary)
            } else if beleg {
                let m = zustand.aktuellesModell
                Kasten(m.map { "\($0.label)  \($0.id)" } ?? "–", pfeil: true)
            } else {
                Picker(selection: Binding(get: { zustand.wahl.model }, set: { zustand.modellWaehlen($0) })) {
                    if zustand.aktuellesModell == nil { Text("–").tag("") }
                    ForEach(eigene) { m in
                        Text(m.startbar ? "\(m.label)  \(m.id)" : "\(m.label)  \(m.id) · \(t.t("wahl.nichtStartbar"))").tag(m.id)
                    }
                } label: { Text(t.t("wahl.modell")) }
                .pickerStyle(.menu)
                .accessibilityIdentifier("neu-modell")
            }
            if let m = zustand.aktuellesModell {
                Text(m.harnessLabel + (m.lokal ? " · lokal" : "")).font(.callout).foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var effortFeld: some View {
        let stufen = zustand.stufen
        if stufen.isEmpty {
            Text(t.t("wahl.keineStufen")).font(.callout).foregroundStyle(.secondary)
        } else if beleg {
            Segmente(optionen: stufen.map { ($0, $0) }, wert: zustand.wahl.effort)
        } else {
            Picker(selection: Binding(get: { stufen.contains(zustand.wahl.effort) ? zustand.wahl.effort : "" }, set: { if !$0.isEmpty { zustand.wahl.effort = $0 } })) {
                if !stufen.contains(zustand.wahl.effort) { Text("–").tag("") }
                ForEach(stufen, id: \.self) { s in Text(s).tag(s) }
            } label: { EmptyView() }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            .accessibilityLabel(t.t("wahl.effort"))
            .accessibilityIdentifier("neu-effort")
        }
        if !zustand.deckelText.isEmpty {
            VStack(alignment: .leading, spacing: 2) {
                Label(zustand.deckelText, systemImage: "lock.shield").font(.callout).foregroundStyle(.secondary)
                Text(t.t("wahl.deckelHinweis")).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityIdentifier("neu-deckel")
        }
    }

    @ViewBuilder
    private var kontextFeld: some View {
        let modellId = zustand.wahl.model
        switch zustand.kontextStand[modellId] {
        case nil:
            Text(t.t("wahl.kontextWirdErmittelt")).font(.callout).foregroundStyle(.secondary)
                .onAppear { zustand.kontextHolen(modellId) }
        case .fehler(let grund)?:
            Text(t.t("wahl.kontextNichtErmittelt", ["grund": grund])).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        case .sicht(let s)?:
            VStack(alignment: .leading, spacing: 6) {
                ForEach(s.stufen) { stufe in
                    let ist = stufe.tokens == (zustand.wahl.kontext == 0 ? s.vorgabe : zustand.wahl.kontext)
                    let zeile = HStack(alignment: .top, spacing: 8) {
                        Image(systemName: ist ? "largecircle.fill.circle" : "circle").foregroundStyle(ist ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Text(stufe.label)
                                if stufe.tokens == s.empfehlung { Text(t.t("wahl.kontextEmpfohlen")).font(.caption).padding(.horizontal, 5).background(Capsule().fill(.tint.opacity(0.15))) }
                                Text(t.t("wahl.kontextToken", ["tokens": String(stufe.tokens)])).font(.callout.monospaced()).foregroundStyle(.secondary)
                            }
                            Text(!stufe.passt && !stufe.hinweis.isEmpty ? stufe.hinweis : t.t("wahl.kontextBedarf", ["bedarf": String(format: "%.1f", stufe.bedarfGib)]))
                                .font(.callout).foregroundStyle(!stufe.passt && !stufe.hinweis.isEmpty ? AnyShapeStyle(.orange) : AnyShapeStyle(.secondary))
                        }
                        Spacer(minLength: 0)
                    }
                    if beleg {
                        zeile
                    } else {
                        Button { zustand.wahl.kontext = stufe.tokens } label: { zeile }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("kontext:\(stufe.tokens)")
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var startzeile: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                if zustand.rolle == .orchestrator {
                    Text(zustand.flaggen.isEmpty ? t.t("wahl.flaggenLeer") : zustand.flaggen.joined(separator: " "))
                        .font(zustand.flaggen.isEmpty ? .callout : .callout.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .accessibilityIdentifier("neu-wahl-flaggen")
                }
            }
            Spacer()
            let titel = zustand.rolle == .chat ? t.t("knopf.neuChat") : t.t("knopf.start")
            if beleg {
                Text(titel).font(.callout).padding(.horizontal, 10).padding(.vertical, 3)
                    .background(Capsule().fill(.tint)).foregroundStyle(.white)
            } else {
                Button(titel) { zustand.neu(echt: !zustand.kopflos) }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(zustand.startGesperrt)
                    .accessibilityIdentifier("neu-start")
            }
        }
    }

    // MARK: Die bekannten Sitzungen

    @ViewBuilder
    private var sitzungsListe: some View {
        HStack(spacing: 8) {
            if beleg {
                Kasten(zustand.suche.isEmpty ? t.t("platzhalter.suche") : zustand.suche, blass: zustand.suche.isEmpty)
            } else {
                TextField(t.t("platzhalter.suche"), text: Binding(get: { zustand.suche }, set: { zustand.suche = $0 }))
                    .textFieldStyle(.roundedBorder)
                    .autocorrectionDisabled()
                    .accessibilityLabel("Suche")
                    .accessibilityIdentifier("such-feld")
            }
            let chips = zustand.zustandChips
            if !chips.isEmpty {
                if beleg {
                    Segmente(optionen: chips.map { ($0.wert, $0.label) }, wert: zustand.zustandFilter)
                } else {
                    Picker(selection: Binding(get: { zustand.zustandFilter }, set: { zustand.zustandFilter = $0 })) {
                        ForEach(chips, id: \.wert) { c in Text(c.label).tag(c.wert) }
                    } label: { EmptyView() }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                    .accessibilityLabel("Zustand")
                    .accessibilityIdentifier("zustand-chips")
                }
            }
        }
        let gruppen = zustand.gruppen
        if gruppen.isEmpty {
            Text(t.t("satz.keineSitzungBekannt")).font(.callout).foregroundStyle(.secondary)
        }
        ForEach(gruppen) { g in
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(g.zeilen.first?.ordnerName ?? "").fontWeight(.semibold)
                    Text(g.machine == zustand.eigeneMaschine ? g.dir : "\(g.machine):\(g.dir)")
                        .font(.callout.monospaced()).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                    Spacer(minLength: 0)
                    if g.zeilen.count > 1 {
                        Text(t.t("wort.sitzungenAnzahl", ["n": String(g.zeilen.count)])).font(.caption).foregroundStyle(.secondary)
                    }
                }
                ForEach(g.zeilen) { z in zeile(z) }
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("gruppe:\(g.schluessel)")
        }
    }

    @ViewBuilder
    private func zeile(_ z: SitzungsZeileDaten) -> some View {
        let ist = z.id == zustand.gewaehlt
        let womit = z.model.isEmpty ? (z.harness.isEmpty ? "claude" : z.harness) : "\(z.harness) · \(z.model)"
        let inhalt = HStack(alignment: .top, spacing: 8) {
            Zustandspunkt(art: Self.punkt(z))
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(z.name)
                    Text(zustand.zustandWort(z.state, startet: z.startet, startFehler: z.startFehler))
                        .font(.caption).foregroundStyle(.secondary)
                        .padding(.horizontal, 5).background(Capsule().fill(.quaternary))
                }
                Text("\(womit) — \(zustand.wann(z.lastActive))").font(.callout).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(ist ? AnyShapeStyle(.tint.opacity(0.12)) : AnyShapeStyle(.clear)))
        .opacity(z.fortsetzbar || z.laeuftGerade ? 1 : 0.7)
        if beleg {
            inhalt
        } else {
            Button { zustand.gewaehlt = z.id } label: { inhalt }
                .buttonStyle(.plain)
                .help(z.grund)
                .accessibilityLabel("\(z.name), \(zustand.zustandWort(z.state, startet: z.startet, startFehler: z.startFehler)), \(womit)")
                .accessibilityAddTraits(ist ? .isSelected : [])
                .accessibilityIdentifier("zeile:\(z.id)")
        }
    }

    /// Zustand als Punkt UND Farbe UND Wort -- derselbe wie in der Seitenleiste
    /// (abnahme.md, Merkmal 5; Punktart.sitzung).
    static func punkt(_ z: SitzungsZeileDaten) -> Punktart {
        if z.startet && !z.startFehler { return .will }
        switch z.state {
        case "running": return .laeuft
        case "attention": return .will
        case "unreachable": return .fern
        default: return .aus
        }
    }
}

/// Die Fusszeile: der Satz zur gewaehlten Sitzung, Fortsetzen und Beenden, darunter die letzte Meldung.
private struct SitzungsFuss: View {
    let zustand: SitzungsZustand
    let beleg: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Divider()
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(zustand.grundText)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("fort-grund")
                Spacer(minLength: 8)
                if beleg {
                    Text(zustand.texte.t("knopf.beenden")).font(.callout).padding(.horizontal, 10).padding(.vertical, 3).background(Capsule().fill(.quaternary))
                    Text(zustand.texte.t("knopf.fortsetzen")).font(.callout).padding(.horizontal, 10).padding(.vertical, 3)
                        .background(Capsule().fill(zustand.fortsetzenGesperrt ? AnyShapeStyle(.quaternary) : AnyShapeStyle(.tint)))
                        .foregroundStyle(zustand.fortsetzenGesperrt ? Color.primary : Color.white)
                } else {
                    Button(zustand.texte.t("knopf.beenden"), role: .destructive) { zustand.beenden(echt: !zustand.kopflos) }
                        .buttonStyle(.bordered)
                        .disabled(zustand.beendenGesperrt)
                        .accessibilityIdentifier("beenden-start")
                    Button(zustand.texte.t("knopf.fortsetzen")) { zustand.fortsetzen(echt: !zustand.kopflos) }
                        .buttonStyle(.borderedProminent)
                        .disabled(zustand.fortsetzenGesperrt)
                        .accessibilityIdentifier("fort-start")
                }
            }
            HStack(spacing: 6) {
                if zustand.statusArt == "fehler" {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.red)
                } else if zustand.statusArt == "gut" {
                    Image(systemName: "checkmark.circle").foregroundStyle(.secondary)
                }
                Text(zustand.status.isEmpty ? " " : zustand.status)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .textSelection(.enabled)
                Spacer(minLength: 0)
            }
            .accessibilityIdentifier("statuszeile")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
}

/// Der Beleg einer Segmentleiste, ohne AppKit.
private struct Segmente: View {
    let optionen: [(String, String)]
    let wert: String

    var body: some View {
        HStack(spacing: 0) {
            ForEach(optionen, id: \.0) { o in
                Text(o.1).font(.callout)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(o.0 == wert ? AnyShapeStyle(.selection) : AnyShapeStyle(.clear))
                    .foregroundStyle(o.0 == wert ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
            }
        }
        .background(RoundedRectangle(cornerRadius: 6).fill(.quaternary.opacity(0.6)))
    }
}

/// Der Beleg eines Eingabefelds oder Aufklappmenues: der Wert in einem Kasten.
private struct Kasten: View {
    let text: String
    var blass = false
    var pfeil = false

    init(_ text: String, blass: Bool = false, pfeil: Bool = false) {
        self.text = text; self.blass = blass; self.pfeil = pfeil
    }

    var body: some View {
        HStack(spacing: 4) {
            Text(text).font(.callout).foregroundStyle(blass ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary)).lineLimit(1)
            if pfeil { Image(systemName: "chevron.up.chevron.down").font(.caption2).foregroundStyle(.secondary) }
        }
        .padding(.horizontal, 8).padding(.vertical, 3)
        .frame(minWidth: 60, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 5).fill(.background))
        .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(.quaternary))
    }
}

/// Die Rueckfrage als Karte im Belegbild -- dieselben Texte wie das NSAlert-Sheet,
/// das ausserhalb des Bildschirms nichts zeichnet.
struct RueckfrageBeleg: View {
    let titel: String
    let text: String
    let knopf: String
    let abbrechen: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill").font(.title).foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 6) {
                    Text(titel).font(.headline)
                    Text(text).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
            HStack {
                Spacer()
                Text(abbrechen).font(.callout).padding(.horizontal, 12).padding(.vertical, 4)
                    .background(Capsule().fill(.tint)).foregroundStyle(.white)
                Text(knopf).font(.callout).padding(.horizontal, 12).padding(.vertical, 4)
                    .background(Capsule().fill(.quaternary)).foregroundStyle(.red)
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.background))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(.quaternary))
        .shadow(radius: 8)
    }
}
