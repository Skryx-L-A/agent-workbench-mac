// DAS ANLEGE-MENUE DER WELTEN (14.09.2026, Plan Fassung 28, Abschnitt 9 und
// Bauschritt 5; Auftrag agentsui Nr. 3).
//
// Das Plus neben dem Welt-Dropdown oeffnet es in der gewaehlten Welt: leer, aus
// einer Vorlage der Bibliothek (`agents/bibliothek/`) oder als Vorschlag, den
// ein Modell aus einer Beschreibung in Alltagssprache schreibt. Der Entwurf
// steht in der Mitte als Formular und bleibt bis „Anlegen" nur ein Entwurf;
// der Inspektor zeigt daneben die Figur und die Anweisungsdatei. Geprueft und
// geschrieben wird ausschliesslich im Kern und in der Datenbibliothek
// (`welt:entwurf`, `welt:anlegen`); diese Datei rechnet nichts nach, was die
// Bibliothek entscheidet.
//
// DIE FIGUR ist eine Auswahl aus dem Katalog von Agentenfigur.swift: Art
// (Roboter, Tier, Linse) und Farbe eines Teams. Die Variante ergibt sich wie
// ueberall aus dem Namen; gezeichnet wird mit demselben Zeichner.
//
// DAS GESPRAECH (15.09.2026, Auftrag agentschat) ist der zweite Weg zum selben
// Entwurf: oben schaltet „Gespräch | Formular" um, jederzeit. Jede Nachricht geht
// als `welt:gespraech` an den Kern; er fuehrt den Verlauf, fragt das Modell und
// gibt den gemischten Entwurf zurueck (agentengespraech.ts). Was der Mensch im
// Formular selbst gesetzt hat, gilt vor dem Modell, auch waehrend ein Zug laeuft.
// „Abbrechen" verwirft den Verlauf im Kern.
//
// DIE RECHTE (16.09.2026, Auftrag agentsform; der Nutzer: „Der Hauptagent darf entscheiden, wer welche
// Berechtigung bekommt, und ich beim Erstellen."). Was ein Agent darf, steht in Formular, Gespraech und
// Vorschau an einer Stelle: Werkzeuge (Bash fest als Dienstweg), Web nur mit einem Zugang der Art web,
// eigene Bash-Muster ueber den festen Mustern des Dienstwegs, Skills der Welt und der Bibliothek. Modell
// und Fallback bieten nur die Modelle an, die der Traeger der Welt fahren kann; die Maschine steht auf
// seiner Maschine.
import AppKit
import SwiftUI

extension WeltenZustand {
    enum AnlegenAnsicht: String, CaseIterable {
        case gespraech, formular
        var titel: String { self == .gespraech ? "Gespräch" : "Formular" }
    }

    /// Eine Nachricht im Gespraech, wie der Kern sie fuehrt (`verlauf`).
    struct GespraechZug: Equatable, Identifiable {
        let id: Int
        let rolle: String
        let text: String
        let felder: [String]
    }

    /// Der offene Entwurf: Formularinhalt, Beschreibung fuer den Vorschlag und was der Mensch selbst gesetzt hat.
    struct AnlegenEntwurf: Equatable {
        /// Kennt eine Antwort ihr Menue wieder: ein zwischendurch neu geoeffnetes Menue bekommt sie nicht.
        var sitzung = UUID()
        var entwurf = AgentEntwurf()
        var beschreibung = ""
        var vorschlagModell = "sonnet5:high"
        var neuesTeam = false
        /// Felder, die der Mensch selbst gesetzt hat: sie gehen als Vorgaben in Vorschlag und Gespraech.
        var gesetzt: Set<String> = []
        var pruefung = ""
        var vorschlagInfo = ""
        var vorlagen: [WeltVorlage] = []
        var modelle: [ModellZeile] = []
        var entwurfModelle: [String] = []
        var ansicht: AnlegenAnsicht = .formular
        var verlauf: [GespraechZug] = []
        var gespraechEingabe = ""
        /// Was der letzte Zug im Entwurf gesetzt hat (Feldnamen des Entwurfs), seine offenen Fragen, ob er fertig ist.
        var gespraechFelder: [String] = []
        var gespraechFragen: [String] = []
        var gespraechFertig = false
        var gespraechInfo = ""
        /// Auftrag agentsform: die Dienstwegmuster je Stufe, die Maschinen zur Wahl und ob die Rechte im Gespraech aufgeklappt sind.
        var bashVorgabe: [String: [String]] = [:]
        var maschinen: [String] = []
        var rechteOffen = false

        func dienstweg(_ stufe: String) -> [String] { bashVorgabe[stufe] ?? bashVorgabe["mitglied"] ?? [] }
    }

    /// Die Feldnamen des Entwurfs in den Worten des Formulars.
    nonisolated static func feldWort(_ feld: String) -> String {
        let worte = ["id": "Name", "stage": "Stufe", "team": "Team", "specialty": "Spezialgebiet", "model": "Modell", "effort": "Denkstufe",
                     "fallback_model": "Fallback", "fallback_effort": "Fallback-Denkstufe", "machine": "Maschine", "tools": "Werkzeuge",
                     "bash": "Bash-Muster", "skills": "Skills", "context_limit": "Kontextgrenze", "figure": "Figur",
                     "instructions": "Anweisungsdatei", "template": "Vorlage"]
        return worte[feld] ?? feld
    }

    static let figurArten: [(String, String)] = [("roboter", "Roboter"), ("tier", "Tier"), ("linse", "Linse")]
    static let figurFarben: [(String, String)] = [("entwicklung", "Entwicklung"), ("recherche", "Recherche"), ("pruefung", "Prüfung"), ("gestaltung", "Gestaltung")]
    // WebFetch und WebSearch sind je Agent wählbar (Rechercheagenten, 2026-09-15); die Vorgabe bleibt ohne Web.
    // Auftrag agentsform: Bash gehoert zum Dienstweg und ist immer dabei; Web nur mit einem Zugang der Art web.
    static let werkzeuge = ["Read", "Write", "Edit", "Glob", "Grep"]
    static let webWerkzeuge = ["WebFetch", "WebSearch"]

    func anlegenOeffnen(_ n: WeltenNutzlast, _ w: Welt, vorlage: String? = nil) {
        var a = AnlegenEntwurf()
        a.vorlagen = n.vorlagen
        a.modelle = n.modelle
        a.entwurfModelle = n.entwurfModelle.isEmpty ? ["sonnet5:high"] : n.entwurfModelle
        a.vorschlagModell = a.entwurfModelle[0]
        a.entwurf.team = w.teams.first?.name ?? ""
        a.neuesTeam = w.teams.isEmpty
        if w.hauptagent == nil { a.entwurf.stufe = "hauptagent"; a.entwurf.team = "" }
        // Auftrag fernwelten: ein Agent laeuft, wo seine Welt liegt; seit agentsform auf der Traegermaschine der Welt.
        if !w.agentMaschine.isEmpty { a.entwurf.maschine = w.agentMaschine }
        a.bashVorgabe = n.bashVorgabe
        a.maschinen = n.maschinen.map(\.name)
        // Auftrag agentsform: mit einer Modellliste der Welt gehen die Kennungen woertlich hinaus; die Vorgabe ist die erste verfuegbare.
        if let ms = w.modelle {
            a.entwurf.modellGenau = true
            let voll = AgentEntwurf.mitStufe(a.entwurf.modell, a.entwurf.denkstufe)
            if let m = ms.first(where: { $0.verfuegbar && $0.id == voll }) ?? ms.first(where: { $0.verfuegbar }) {
                a.entwurf.modell = m.id
                let teile = AgentEntwurf.teilen(m.id, "")
                if !teile.1.isEmpty { a.entwurf.denkstufe = teile.1 }
            }
        }
        anlegen = a
        meldung = nil
        inspektorOffen = true
        if let vorlage, let v = n.vorlagen.first(where: { $0.name == vorlage }) { vorlageAnwenden(v, w) }
    }

    /// Eine Vorlage fuellt den Entwurf; Name und Team werden an die Welt angepasst, die Beschreibung bleibt.
    func vorlageAnwenden(_ v: WeltVorlage, _ w: Welt) {
        guard var a = anlegen else { return }
        var e = v.entwurf
        e.id = Self.freieKennung(e.id, w)
        if !w.agentMaschine.isEmpty { e.maschine = w.agentMaschine }
        if w.modelle != nil {
            e.modell = AgentEntwurf.mitStufe(e.modell, e.denkstufe)
            if !e.fallback.isEmpty { e.fallback = AgentEntwurf.mitStufe(e.fallback, e.fallbackDenkstufe) }
            e.modellGenau = true
        }
        e.bash = AgentEntwurf.eigeneMuster(e.bashMuster, a.dienstweg(e.stufe)).joined(separator: "\n")
        e.vorlage = v.name
        a.neuesTeam = !w.teams.contains { $0.name == e.team }
        a.entwurf = e
        a.gesetzt = []
        a.pruefung = ""
        a.vorschlagInfo = "Aus der Vorlage „\(v.titel)“."
        anlegen = a
    }

    static func freieKennung(_ id: String, _ w: Welt) -> String {
        guard w.agent(id) != nil else { return id }
        var n = 2
        while w.agent("\(id)-\(n)") != nil { n += 1 }
        return "\(id)-\(n)"
    }

    /// Ein Feld des Formulars aendern (auch ueber den Steuerkanal); es zaehlt ab dann als Vorgabe des Menschen.
    func anlegenFeld(_ feld: String, _ wert: String) -> Bool {
        guard var a = anlegen else { return false }
        switch feld {
        case "name": a.entwurf.id = wert
        case "stufe": a.entwurf.stufe = wert
        case "team": a.entwurf.team = wert; a.neuesTeam = false
        case "neues-team": a.entwurf.team = wert; a.neuesTeam = true
        case "spezialgebiet": a.entwurf.spezialgebiet = wert
        case "modell": a.entwurf.modell = wert
        case "denkstufe": a.entwurf.denkstufe = wert
        case "fallback": a.entwurf.fallback = wert
        case "fallback-denkstufe": a.entwurf.fallbackDenkstufe = wert
        case "maschine": a.entwurf.maschine = wert
        case "bash": a.entwurf.bash = wert.replacingOccurrences(of: "\\n", with: "\n")
        case "skills": a.entwurf.skills = wert
        case "kontextgrenze": a.entwurf.kontextgrenze = wert
        case "figur": a.entwurf.figurArt = wert
        case "farbe": a.entwurf.figurFarbe = wert
        case "anweisungen": a.entwurf.anweisungen = wert.replacingOccurrences(of: "\\n", with: "\n")
        case "beschreibung": a.beschreibung = wert; anlegen = a; return true
        case "vorschlagmodell": a.vorschlagModell = wert; anlegen = a; return true
        case "gespraech": a.gespraechEingabe = wert; anlegen = a; return true
        default: return false
        }
        a.gesetzt.insert(feld)
        anlegen = a
        return true
    }

    /// Die Vorgaben fuer einen Vorschlag: nur, was der Mensch gesetzt hat.
    func vorschlagVorgaben() -> [String: Any] {
        guard let a = anlegen else { return [:] }
        let j = a.entwurf.json()
        let schluessel: [String: [String]] = [
            "name": ["id"], "stufe": ["stage"], "team": ["team"], "neues-team": ["team"], "spezialgebiet": ["specialty"],
            "modell": ["model", "effort"], "denkstufe": ["model", "effort"], "fallback": ["fallback_model", "fallback_effort"],
            "fallback-denkstufe": ["fallback_model", "fallback_effort"], "maschine": ["machine"], "werkzeuge": ["tools", "bash"],
            "bash": ["bash"], "skills": ["skills"], "kontextgrenze": ["context_limit"], "figur": ["figure"], "farbe": ["figure"],
            "anweisungen": ["instructions"],
        ]
        var raus: [String: Any] = [:]
        for feld in a.gesetzt { for k in schluessel[feld] ?? [] { if let v = j[k] { raus[k] = v } } }
        return raus
    }

    /// Ein Werkzeug an oder aus; nil, wenn es ging, sonst der Grund. Bash bleibt, Web nur mit Zugang der Art web.
    @discardableResult
    func werkzeugSetzen(_ name: String, _ an: Bool, webZugang: Bool, befehl: String = "") -> String? {
        guard var a = anlegen else { return "Kein Anlege-Menü offen." }
        if name == "Bash" { return an ? nil : "Bash gehört zum Dienstweg und bleibt dabei." }
        if Self.webWerkzeuge.contains(name), an, !webZugang { return Self.webOhneZugang(befehl) }
        if an, !a.entwurf.werkzeuge.contains(name) { a.entwurf.werkzeuge.append(name) }
        if !an { a.entwurf.werkzeuge.removeAll { $0 == name } }
        if !a.entwurf.werkzeuge.contains("Bash") { a.entwurf.werkzeuge.insert("Bash", at: 0) }
        a.gesetzt.insert("werkzeuge")
        anlegen = a
        return nil
    }

    /// Der Satz, wie eine Welt Web bekommt.
    nonisolated static func webOhneZugang(_ befehl: String) -> String {
        "WebFetch und WebSearch gibt es erst, wenn die Welt einen Zugang der Art web hat. Einrichten: \(befehl)"
    }

    /// Ein Skill der Welt oder der Bibliothek an oder aus.
    func skillSetzen(_ name: String, _ an: Bool) {
        guard var a = anlegen else { return }
        var liste = a.entwurf.skillListe
        if an, !liste.contains(name) { liste.append(name) }
        if !an { liste.removeAll { $0 == name } }
        a.entwurf.skills = liste.joined(separator: ", ")
        a.gesetzt.insert("skills")
        anlegen = a
    }

    /// Modell oder Fallback: nur ein Modell, das der Traeger der Welt fahren kann; nil, wenn es ging.
    @discardableResult
    func anlegenModell(_ feld: String, _ wert: String, _ w: Welt) -> String? {
        if !wert.isEmpty, let m = w.modelle?.first(where: { $0.id == wert || AgentEntwurf.teilen($0.id, "").0 == wert }), !m.verfuegbar {
            return "\(wert) ist in \(w.name) nicht verfügbar: \(WeltenWorte.modellGrund(m.grund))"
        }
        guard anlegenFeld(feld, wert) else { return "Kein Anlege-Menü offen." }
        // Eine Kennung der Welt mit Suffix bringt ihre Denkstufe mit.
        let stufe = AgentEntwurf.teilen(wert, "").1
        if anlegen?.entwurf.modellGenau == true, !stufe.isEmpty, WeltenWorte.denkstufen.contains(stufe) {
            _ = anlegenFeld(feld == "modell" ? "denkstufe" : "fallback-denkstufe", stufe)
        }
        return nil
    }

    func anlegenRechteOffen(_ offen: Bool) {
        guard var a = anlegen else { return }
        a.rechteOffen = offen
        anlegen = a
    }

    /// Die Rechte in einer Zeile: fuer den zugeklappten Stand im Gespraech und die Auskunft.
    nonisolated static func rechteKurz(werkzeuge: [String], eigeneBash: Int, dienstweg: Int, skills: [String]) -> String {
        let wz = ["Bash"] + werkzeuge.filter { $0 != "Bash" }
        return "Darf: \(wz.joined(separator: ", ")) · Bash \(eigeneBash) eigene + \(dienstweg) Dienstweg · Skills: \(skills.isEmpty ? "–" : skills.joined(separator: ", "))"
    }

    /// Eine Handlung, deren Antwort Daten traegt (Vorschlag, Pruefung).
    private func ausfuehrenMitDaten(_ handlung: String, _ daten: [String: Any], echt: Bool) async -> (ok: Bool, j: [String: Any]) {
        let json = (try? JSONSerialization.data(withJSONObject: daten, options: [.sortedKeys])).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
        guard let kern else {
            meldung = Meldung(text: "Keine Verbindung zum Kern.", ok: false)
            return (false, [:])
        }
        laufendSetzen(handlung, true)
        defer { laufendSetzen(handlung, false) }
        let a = await kern.invoke("awb:aufgabe", ["welt:\(handlung) \(json)", ["echt": echt, "bestaetigt": false]])
        let r = HandlungsAntwort(a)
        meldung = Meldung(text: r.meldung, ok: r.ok)
        let j = a.wertJSON.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] } ?? [:]
        return (r.ok, j)
    }

    /// „Vorschlag erzeugen": das Modell schreibt Profil und Anweisungsdatei; der Entwurf ersetzt das Formular.
    func vorschlagErzeugen(_ w: Welt, trocken: Bool = false, echt: Bool) async {
        guard let a = anlegen else { return }
        let text = a.beschreibung.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            meldung = Meldung(text: "Beschreibe zuerst in eigenen Worten, was der Agent tun soll.", ok: false)
            return
        }
        var daten: [String: Any] = ["welt": w.pfad, "beschreibung": text, "modell": a.vorschlagModell, "vorgaben": vorschlagVorgaben()]
        if trocken { daten["trocken"] = true }
        let (ok, j) = await ausfuehrenMitDaten("vorschlag", daten, echt: echt)
        guard ok, var neu = anlegen else { return }
        if trocken {
            neu.vorschlagInfo = (j["meldung"] as? String) ?? ""
            anlegen = neu
            return
        }
        if let e = j["entwurf"] as? [String: Any] {
            let gesetzt = neu.gesetzt
            neu.entwurf = AgentEntwurf(e, genau: neu.entwurf.modellGenau)
            neu.entwurf.bash = AgentEntwurf.eigeneMuster(neu.entwurf.bashMuster, neu.dienstweg(neu.entwurf.stufe)).joined(separator: "\n")
            neu.gesetzt = gesetzt
            if let text = j["anweisungen"] as? String, !text.isEmpty { neu.entwurf.anweisungen = text }
            neu.neuesTeam = !neu.entwurf.team.isEmpty && !w.teams.contains { $0.name == neu.entwurf.team }
        }
        neu.pruefung = (j["pruefung"] as? String) ?? ""
        let aufruf = j["aufruf"] as? [String: Any] ?? [:]
        let kosten = (j["kosten"] as? NSNumber).map { String(format: " · %.3f $", $0.doubleValue) } ?? ""
        neu.vorschlagInfo = "Vorschlag von \((aufruf["kennung"] as? String) ?? a.vorschlagModell), Denkstufe \((aufruf["stufe"] as? String) ?? "")\(kosten)."
        anlegen = neu
    }

    /// Prueft den Entwurf in der Bibliothek; ohne eigene Anweisungsdatei kommt die aus der Hausvorlage zurueck.
    func entwurfPruefen(_ w: Welt, anweisungenAusVorlage: Bool = false, echt: Bool) async {
        guard let a = anlegen else { return }
        var e = a.entwurf.json()
        if anweisungenAusVorlage { e.removeValue(forKey: "instructions") }
        let (ok, j) = await ausfuehrenMitDaten("entwurf", ["welt": w.pfad, "entwurf": e], echt: echt)
        guard var neu = anlegen else { return }
        neu.pruefung = ok ? "" : ((j["pruefung"] as? String) ?? (j["meldung"] as? String) ?? "")
        if ok, anweisungenAusVorlage, let text = j["anweisungen"] as? String { neu.entwurf.anweisungen = text; neu.gesetzt.insert("anweisungen") }
        anlegen = neu
    }

    func anlegenSichern(_ w: Welt, echt: Bool) async {
        guard let a = anlegen else { return }
        let id = a.entwurf.id.trimmingCharacters(in: .whitespaces)
        if await ausfuehren("anlegen", ["welt": w.pfad, "entwurf": a.entwurf.json()], echt: echt) {
            anlegen = nil
            auswahl = "agent:\(id)"
            gespraech = Self.einzel
            blatt = .profil
        } else if var neu = anlegen {
            neu.pruefung = meldung?.text ?? ""
            anlegen = neu
        }
    }

    // --- Das Gespraech ----------------------------------------------------------------

    func anlegenAnsicht(_ ansicht: AnlegenAnsicht) {
        guard var a = anlegen else { return }
        a.ansicht = ansicht
        anlegen = a
    }

    /// Ein Zug: die Nachricht (aus dem Eingabefeld oder dem Steuerkanal) geht mit Entwurf und Vorgaben an den Kern.
    func gespraechSenden(_ w: Welt, text: String? = nil, trocken: Bool = false, echt: Bool) async {
        guard let a = anlegen else { return }
        let nachricht = (text ?? a.gespraechEingabe).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !nachricht.isEmpty else {
            meldung = Meldung(text: "Schreib zuerst, was der Agent tun soll.", ok: false)
            return
        }
        var daten: [String: Any] = ["welt": w.pfad, "text": nachricht, "modell": a.vorschlagModell, "entwurf": a.entwurf.json(),
                                    "vorgaben": vorschlagVorgaben(), "neu": a.verlauf.isEmpty]
        if trocken { daten["trocken"] = true }
        let (ok, j) = await ausfuehrenMitDaten("gespraech", daten, echt: echt)
        guard ok, var neu = anlegen, neu.sitzung == a.sitzung else { return }
        let info = (j["meldung"] as? String) ?? ""
        if trocken {
            neu.gespraechInfo = info
            anlegen = neu
            return
        }
        meldung = nil
        if var e = j["entwurf"] as? [String: Any] {
            // Was der Mensch waehrend des Zuges im Formular gesetzt hat, bleibt stehen.
            for (k, v) in vorschlagVorgaben() { e[k] = v }
            neu.entwurf = AgentEntwurf(e, genau: neu.entwurf.modellGenau)
            neu.entwurf.bash = AgentEntwurf.eigeneMuster(neu.entwurf.bashMuster, neu.dienstweg(neu.entwurf.stufe)).joined(separator: "\n")
            neu.neuesTeam = !neu.entwurf.team.isEmpty && !w.teams.contains { $0.name == neu.entwurf.team }
        }
        let verlauf = (j["verlauf"] as? [[String: Any]]) ?? []
        neu.verlauf = verlauf.enumerated().map { i, z in
            GespraechZug(id: i, rolle: (z["rolle"] as? String) ?? "", text: (z["text"] as? String) ?? "", felder: (z["felder"] as? [String]) ?? [])
        }
        neu.gespraechFelder = (j["felder"] as? [String]) ?? []
        neu.gespraechFragen = (j["fragen"] as? [String]) ?? []
        neu.gespraechFertig = (j["fertig"] as? Bool) ?? false
        neu.pruefung = (j["pruefung"] as? String) ?? ""
        let kosten = (j["kosten"] as? NSNumber).map { String(format: " · %.3f $", $0.doubleValue) } ?? ""
        neu.gespraechInfo = info + kosten
        if text == nil { neu.gespraechEingabe = "" }
        anlegen = neu
    }

    /// „Abbrechen": das Menue schliesst sofort; ein Gespraech wird danach im Kern verworfen.
    func anlegenAbbrechen(_ w: Welt, echt: Bool) async {
        let mitGespraech = !(anlegen?.verlauf.isEmpty ?? true)
        anlegen = nil
        meldung = nil
        guard mitGespraech, let kern else { return }
        let json = (try? JSONSerialization.data(withJSONObject: ["welt": w.pfad, "verwerfen": true], options: [.sortedKeys])).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
        _ = await kern.invoke("awb:aufgabe", ["welt:gespraech \(json)", ["echt": echt, "bestaetigt": false]])
    }

    /// Was die Auskunft ueber das offene Menue traegt (`ui.agents.anlegen`, `welten.anlegen`).
    func anlegenAuskunft(_ w: Welt? = nil) -> [String: Any] {
        guard let a = anlegen else { return [:] }
        let e = a.entwurf
        let dienstweg = a.dienstweg(e.stufe)
        var rechte: [String: Any] = ["werkzeuge": e.werkzeuge, "eigeneBash": e.bashMuster, "dienstweg": dienstweg, "skills": e.skillListe, "offen": a.rechteOffen,
                                     "kurz": Self.rechteKurz(werkzeuge: e.werkzeuge, eigeneBash: e.bashMuster.count, dienstweg: dienstweg.count, skills: e.skillListe)]
        if let w {
            rechte["webZugang"] = w.webZugang
            rechte["webSatz"] = w.webZugang ? "" : Self.webOhneZugang(w.webZugangBefehl)
            rechte["skillKatalog"] = w.skillKatalog.map { "\($0.name) (\($0.ebene))" }
            rechte["modellOptionen"] = WeltenNutzlast.modellOptionen(w, registry: a.modelle, eigene: [e.modell, e.fallback])
                .map { ["wert": $0.wert, "titel": $0.titel, "verfuegbar": $0.verfuegbar] as [String: Any] }
            rechte["maschinen"] = Self.maschinenWahl(a, w).map(\.wert)
            rechte["maschineVorgabe"] = w.agentMaschine
        }
        return ["rechte": rechte,"entwurf": a.entwurf.json(), "beschreibung": a.beschreibung, "vorschlagModell": a.vorschlagModell, "neuesTeam": a.neuesTeam,
                "gesetzt": a.gesetzt.sorted(), "vorgaben": vorschlagVorgaben(), "pruefung": a.pruefung, "vorschlagInfo": a.vorschlagInfo,
                "modelle": a.modelle.count, "entwurfModelle": a.entwurfModelle, "ansicht": a.ansicht.rawValue,
                "vorschau": { let k = WeltenAnlegenVorschau.kopf(a.entwurf)
                    return ["name": k.name, "stufe": k.stufe, "modell": k.modell, "spezialgebiet": a.entwurf.spezialgebiet,
                            "werkzeuge": a.entwurf.werkzeuge.joined(separator: ", ")] as [String: Any] }(),
                "gespraech": ["verlauf": a.verlauf.map { ["rolle": $0.rolle, "text": $0.text, "felder": $0.felder] as [String: Any] },
                              "eingabe": a.gespraechEingabe, "felder": a.gespraechFelder, "fragen": a.gespraechFragen,
                              "fertig": a.gespraechFertig, "info": a.gespraechInfo, "laeuft": laufend.contains("gespraech"),
                              "hinweis": Self.gespraechHinweis(a)] as [String: Any]]
    }

    /// Die Maschinen zur Wahl: die Traegermaschine der Welt zuerst, dann der Wert des Entwurfs und die bekannten Maschinen.
    nonisolated static func maschinenWahl(_ a: AnlegenEntwurf, _ w: Welt) -> [(wert: String, titel: String)] {
        var gesehen = Set<String>()
        return ([w.agentMaschine, a.entwurf.maschine] + a.maschinen).filter { !$0.isEmpty && gesehen.insert($0).inserted }
            .map { ($0, $0 == w.agentMaschine ? "\(WeltenWorte.maschine($0)) (\(w.traegerEingerichtet ? "Träger der Welt" : "Vorgabe der Welt"))" : WeltenWorte.maschine($0)) }
    }

    /// Der Hinweis unter dem Verlauf: was der letzte Zug gesetzt hat.
    nonisolated static func gespraechHinweis(_ a: AnlegenEntwurf) -> String {
        a.gespraechFelder.isEmpty ? "" : "Zuletzt gesetzt: " + a.gespraechFelder.map(feldWort).joined(separator: ", ")
    }
}

// MARK: Das Formular in der Mitte

struct WeltenAnlegen: View {
    let welt: Welt
    @Bindable var zustand: WeltenZustand

    private var a: WeltenZustand.AnlegenEntwurf { zustand.anlegen ?? WeltenZustand.AnlegenEntwurf() }

    private func feld(_ name: String, _ weg: WritableKeyPath<AgentEntwurf, String>) -> Binding<String> {
        Binding(get: { a.entwurf[keyPath: weg] }, set: { _ = zustand.anlegenFeld(name, $0) })
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "person.badge.plus").font(.title2).foregroundStyle(.secondary).frame(width: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text(a.entwurf.stufe == "hauptagent" ? "Hauptagent anlegen" : "Agent anlegen").font(.title3.weight(.semibold))
                    Text("in \(welt.name) · gültig erst mit „Anlegen“, gestartet wird dabei nichts").font(.callout).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
                Picker("Ansicht", selection: Binding(get: { a.ansicht }, set: { zustand.anlegenAnsicht($0) })) {
                    ForEach(WeltenZustand.AnlegenAnsicht.allCases, id: \.self) { Text($0.titel).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                .help("Den Entwurf im Gespräch mit einem Modell ausmachen oder im Formular selbst setzen; beide zeigen denselben Entwurf.")
                .accessibilityIdentifier("welten-anlegen-ansicht")
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            Divider()
            if let m = zustand.meldung {
                Label(m.text, systemImage: m.ok ? "checkmark.circle" : "exclamationmark.triangle")
                    .font(.callout).foregroundStyle(m.ok ? Color.secondary : Color.orange)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14).padding(.vertical, 6)
                    .accessibilityIdentifier("welten-anlegen-meldung")
                Divider()
            }
            if a.ansicht == .gespraech {
                WeltenAnlegenGespraech(welt: welt, zustand: zustand)
            } else {
                Form {
                    vorschlag
                    agent
                    rechte
                    modell
                    figur
                    anweisungen
                }
                .formStyle(.grouped)
            }
            Divider()
            fuss
        }
        .background(Color(nsColor: .textBackgroundColor))
        .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
        .accessibilityIdentifier("welten-anlegen")
    }

    private var vorschlag: some View {
        Section {
            TextField("Beschreibung", text: Binding(get: { a.beschreibung }, set: { _ = zustand.anlegenFeld("beschreibung", $0) }),
                      prompt: Text("Was soll der Agent tun? In eigenen Worten"), axis: .vertical)
                .labelsHidden()
                .lineLimit(2...5)
                .accessibilityIdentifier("welten-anlegen-beschreibung")
            HStack {
                Picker("Modell für den Vorschlag", selection: Binding(get: { a.vorschlagModell }, set: { _ = zustand.anlegenFeld("vorschlagmodell", $0) })) {
                    ForEach(a.entwurfModelle, id: \.self) { Text($0).tag($0) }
                }
                .fixedSize()
                Spacer()
                if zustand.laufend.contains("vorschlag") { ProgressView().controlSize(.small) }
                Button("Vorschlag erzeugen") { Task { await zustand.vorschlagErzeugen(welt, echt: true) } }
                    .disabled(zustand.laufend.contains("vorschlag") || a.beschreibung.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityIdentifier("welten-anlegen-vorschlag")
            }
            if !a.vorlagen.isEmpty {
                Picker("Vorlage", selection: Binding(get: { a.entwurf.vorlage }, set: { name in
                    if let v = a.vorlagen.first(where: { $0.name == name }) { zustand.vorlageAnwenden(v, welt) }
                })) {
                    Text("keine").tag("")
                    ForEach(a.vorlagen) { v in Text(v.titel).tag(v.name) }
                }
                .help(a.vorlagen.first { $0.name == a.entwurf.vorlage }?.zusammenfassung ?? "Ein Klick füllt das Formular aus der Bibliothek.")
            }
        } header: {
            Text("Beschreibung")
        } footer: {
            Text(a.vorschlagInfo.isEmpty ? "Nur die Beschreibung genügt: das Modell entwirft den Rest, kopflos, ohne Werkzeuge und ohne Zugriff auf die Welt. Was du selbst gesetzt hast, bleibt." : a.vorschlagInfo)
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    /// Ein Satz, der umbrechen darf: dieselbe Zeile wie „Beschreibung" und „Name" (Beschriftung
    /// links, Feld rechts). Die fruehere Fassung stellte das Feld ohne Beschriftung unter einen
    /// eigenen Text in einem VStack; dort blieb der Entwurf beim Tippen leer (15.09.2026, der Nutzer
    /// beim ersten Agenten fuer Myproject, Steuerkanal: alle anderen Felder gesetzt, `specialty`
    /// fehlte), waehrend die direkt in der Section stehenden Felder ihre Eingabe trugen. Die
    /// Ursache im Rahmenwerk ist nicht gemessen; diese Zeile nutzt das belegte Muster.
    private func mehrzeilig(_ titel: String, _ hinweis: String, _ text: Binding<String>, kennung: String) -> some View {
        TextField(titel, text: text, prompt: Text(hinweis), axis: .vertical)
            .lineLimit(1...3)
            .accessibilityIdentifier(kennung)
    }

    private var agent: some View {
        Section("Agent") {
            TextField("Name", text: feld("name", \.id)).accessibilityIdentifier("welten-anlegen-name")
            Picker("Stufe", selection: feld("stufe", \.stufe)) {
                Text("Mitglied").tag("mitglied")
                Text("Teamleiter").tag("teamleiter")
                if welt.hauptagent == nil { Text("Hauptagent").tag("hauptagent") }
            }
            if a.entwurf.stufe != "hauptagent" {
                Picker("Team", selection: Binding(get: { a.neuesTeam ? "\u{1f}neu" : a.entwurf.team }, set: { wert in
                    if wert == "\u{1f}neu" { _ = zustand.anlegenFeld("neues-team", "") } else { _ = zustand.anlegenFeld("team", wert) }
                })) {
                    if a.entwurf.stufe == "mitglied" { Text("ohne Team").tag("") }
                    ForEach(welt.teams) { t in Text(WeltenWorte.team(t.name)).tag(t.name) }
                    Text("Neues Team …").tag("\u{1f}neu")
                }
                if a.neuesTeam {
                    TextField("Name des neuen Teams", text: feld("neues-team", \.team))
                }
            }
            mehrzeilig("Spezialgebiet", "In einem Satz, der mit einem Verb beginnt", feld("spezialgebiet", \.spezialgebiet), kennung: "welten-anlegen-spezialgebiet")
        }
    }

    /// Ein Modell setzen; ein nicht verfuegbares lehnt der Zustand mit Grund ab.
    private func modellFeld(_ name: String, _ weg: WritableKeyPath<AgentEntwurf, String>) -> Binding<String> {
        Binding(get: { a.entwurf[keyPath: weg] }, set: { wert in
            if let f = zustand.anlegenModell(name, wert, welt) { zustand.meldung = WeltenZustand.Meldung(text: f, ok: false) }
        })
    }

    private var modell: some View {
        let optionen = WeltenNutzlast.modellOptionen(welt, registry: a.modelle, eigene: [a.entwurf.modell, a.entwurf.fallback])
        return Section {
            Picker("Modell", selection: modellFeld("modell", \.modell)) {
                ForEach(optionen, id: \.wert) { Text($0.titel).tag($0.wert).disabled(!$0.verfuegbar) }
            }
            .accessibilityIdentifier("welten-anlegen-modell")
            Picker("Denkstufe", selection: feld("denkstufe", \.denkstufe)) {
                ForEach(WeltenWorte.denkstufen, id: \.self) { Text($0).tag($0) }
            }
            Picker("Fallback", selection: modellFeld("fallback", \.fallback)) {
                Text("keiner").tag("")
                ForEach(optionen, id: \.wert) { Text($0.titel).tag($0.wert).disabled(!$0.verfuegbar) }
            }
            .accessibilityIdentifier("welten-anlegen-fallback")
            if !a.entwurf.fallback.isEmpty {
                Picker("Fallback-Denkstufe", selection: feld("fallback-denkstufe", \.fallbackDenkstufe)) {
                    ForEach(WeltenWorte.denkstufen, id: \.self) { Text($0).tag($0) }
                }
            }
            Picker("Maschine", selection: feld("maschine", \.maschine)) {
                ForEach(WeltenZustand.maschinenWahl(a, welt), id: \.wert) { Text($0.titel).tag($0.wert) }
            }
            .accessibilityIdentifier("welten-anlegen-maschine")
        } header: {
            Text("Modell und Maschine")
        } footer: {
            Text(welt.modelle == nil
                 ? "Aus wb-state models table, Fable nie. Die Maschine steht auf der Maschine der Welt."
                 : "Nur die Modelle, die der Träger dieser Welt fahren kann; nicht verfügbare stehen mit Grund da. Fable nie.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    /// Auftrag agentsform: was der Agent darf, in einem Blick -- gleich nach Name, Stufe und Team.
    private var rechte: some View {
        Section {
            WeltenRechteAuswahl(
                welt: welt, werkzeuge: a.entwurf.werkzeuge, skills: a.entwurf.skillListe, dienstweg: a.dienstweg(a.entwurf.stufe),
                bash: feld("bash", \.bash),
                werkzeug: { name, an in
                    if let f = zustand.werkzeugSetzen(name, an, webZugang: welt.webZugang, befehl: welt.webZugangBefehl) {
                        zustand.meldung = WeltenZustand.Meldung(text: f, ok: false)
                    }
                },
                skill: { zustand.skillSetzen($0, $1) })
            mehrzeilig("Kontextgrenze", "Was der Agent nicht erfährt", feld("kontextgrenze", \.kontextgrenze), kennung: "welten-anlegen-kontextgrenze")
        } header: {
            Text("Was der Agent darf")
        } footer: {
            Text("Gesperrt bleibt, was die Hausliste sperrt: Push, rm -rf, kill, Mail-Versand, Erlaubnisstufen.").font(.caption).foregroundStyle(.secondary)
        }
        .accessibilityIdentifier("welten-anlegen-rechte")
    }

    private var figur: some View {
        Section("Figur") {
            if a.entwurf.stufe == "hauptagent" {
                Text("Der Hauptagent trägt den Kern.").foregroundStyle(.secondary)
            } else {
                Picker("Art", selection: feld("figur", \.figurArt)) {
                    ForEach(WeltenZustand.figurArten, id: \.0) { Text($0.1).tag($0.0) }
                }
                .pickerStyle(.segmented)
                Picker("Farbe", selection: feld("farbe", \.figurFarbe)) {
                    ForEach(WeltenZustand.figurFarben, id: \.0) { Text($0.1).tag($0.0) }
                }
                .pickerStyle(.segmented)
            }
        }
    }

    private var anweisungen: some View {
        Section {
            TextEditor(text: feld("anweisungen", \.anweisungen))
                .font(.callout.monospaced())
                .frame(minHeight: 150)
                .scrollContentBackground(.hidden)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color(nsColor: .controlBackgroundColor)))
                .accessibilityIdentifier("welten-anlegen-anweisungen")
            HStack {
                Spacer()
                Button("Aus der Hausvorlage erzeugen") { Task { await zustand.entwurfPruefen(welt, anweisungenAusVorlage: true, echt: true) } }
                    .controlSize(.small)
            }
        } header: {
            Text("Anweisungsdatei (AGENTS.md)")
        } footer: {
            Text("Leer lassen: die Datei entsteht beim Anlegen aus der Hausvorlage mit Rolle, Spezialgebiet, Grenzen und Meldewegen.").font(.caption).foregroundStyle(.secondary)
        }
    }

    private var fuss: some View {
        HStack(spacing: 10) {
            if !a.pruefung.isEmpty {
                Label(a.pruefung, systemImage: "exclamationmark.triangle").font(.callout).foregroundStyle(.orange).lineLimit(2)
                    .accessibilityIdentifier("welten-anlegen-pruefung")
            }
            Spacer()
            Button("Abbrechen") { Task { await zustand.anlegenAbbrechen(welt, echt: true) } }
            Button("Prüfen") { Task { await zustand.entwurfPruefen(welt, echt: true) } }
            Button("Anlegen") { Task { await zustand.anlegenSichern(welt, echt: true) } }
                .buttonStyle(.borderedProminent)
                // Im Gespraech gehoert Return dem Eingabefeld; angelegt wird dort nur mit einem Klick.
                .keyboardShortcut(a.ansicht == .formular ? .defaultAction : nil)
                .disabled(zustand.laufend.contains("anlegen") || a.entwurf.id.trimmingCharacters(in: .whitespaces).isEmpty
                          || a.entwurf.spezialgebiet.trimmingCharacters(in: .whitespaces).isEmpty)
                .accessibilityIdentifier("welten-anlegen-sichern")
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
    }
}

// MARK: Das Gespraech in der Mitte

struct WeltenAnlegenGespraech: View {
    let welt: Welt
    @Bindable var zustand: WeltenZustand

    private var a: WeltenZustand.AnlegenEntwurf { zustand.anlegen ?? WeltenZustand.AnlegenEntwurf() }
    private var laeuft: Bool { zustand.laufend.contains("gespraech") }
    private var leer: Bool { a.gespraechEingabe.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { leser in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        if a.verlauf.isEmpty { einladung }
                        ForEach(a.verlauf) { WeltenGespraechBlase(zug: $0).id($0.id) }
                        if laeuft {
                            HStack(spacing: 8) {
                                ProgressView().controlSize(.small)
                                Text("\(a.vorschlagModell) antwortet …").font(.callout).foregroundStyle(.secondary)
                            }
                            .padding(.leading, 4)
                            .id("laeuft")
                            .accessibilityIdentifier("welten-anlegen-gespraech-laeuft")
                        }
                    }
                    .padding(14)
                }
                .onChange(of: a.verlauf.count) { _, _ in if let z = a.verlauf.last { leser.scrollTo(z.id, anchor: .bottom) } }
                .onChange(of: laeuft) { _, an in if an { leser.scrollTo("laeuft", anchor: .bottom) } }
            }
            .accessibilityIdentifier("welten-anlegen-gespraech")
            Divider()
            rechteKarte
            hinweise
            eingabe
        }
        .frame(maxHeight: .infinity)
    }

    private var einladung: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Im Gespräch entwerfen", systemImage: "bubble.left.and.text.bubble.right").font(.headline)
            Text(welt.hauptagent == nil
                 ? "Beschreibe in eigenen Worten, wofür \(welt.name) da ist und was der Hauptagent verantworten soll: Zweck, Ton, Aufgaben, Grenzen."
                 : "Beschreibe in eigenen Worten, was der neue Agent in \(welt.name) tun soll: Zweck, Ton, Aufgaben, Grenzen.")
                .fixedSize(horizontal: false, vertical: true)
            Text("Das Modell fragt nach, schlägt Werte vor und trägt sie in den Entwurf ein; die Vorschau rechts zeigt den Stand. Im Formular lässt sich jederzeit alles ändern, und was du dort selbst setzt, bleibt. Das Modell arbeitet kopflos, ohne Werkzeuge und ohne Zugriff auf die Welt.")
                .font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color(nsColor: .controlBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Color(nsColor: .separatorColor)))
    }

    /// Auftrag agentsform: auch im Gespraech steht, was der Agent darf; aufgeklappt laesst es sich hier setzen.
    private var rechteKarte: some View {
        let e = a.entwurf
        let dienstweg = a.dienstweg(e.stufe)
        let kurz = WeltenZustand.rechteKurz(werkzeuge: e.werkzeuge, eigeneBash: e.bashMuster.count, dienstweg: dienstweg.count, skills: e.skillListe)
        let modell = [e.modellText, e.fallback.isEmpty ? "" : "Fallback \(e.fallbackText)", WeltenWorte.maschine(e.maschine)]
            .filter { !$0.isEmpty }.joined(separator: " · ")
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("Was der Agent darf").font(.callout.weight(.semibold))
                Text("\(kurz) · \(modell)").font(.callout).foregroundStyle(.secondary).lineLimit(1).truncationMode(.tail)
                    .help("\(kurz)\n\(modell)")
                Spacer(minLength: 6)
                Button(a.rechteOffen ? "Zuklappen" : "Ändern") { zustand.anlegenRechteOffen(!a.rechteOffen) }
                    .buttonStyle(.borderless).controlSize(.small)
                    .accessibilityIdentifier("welten-anlegen-gespraech-rechte-knopf")
            }
            if a.rechteOffen {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        WeltenRechteAuswahl(
                            welt: welt, werkzeuge: e.werkzeuge, skills: e.skillListe, dienstweg: dienstweg,
                            bash: Binding(get: { a.entwurf.bash }, set: { _ = zustand.anlegenFeld("bash", $0) }),
                            werkzeug: { name, an in
                                if let f = zustand.werkzeugSetzen(name, an, webZugang: welt.webZugang, befehl: welt.webZugangBefehl) {
                                    zustand.meldung = WeltenZustand.Meldung(text: f, ok: false)
                                }
                            },
                            skill: { zustand.skillSetzen($0, $1) })
                        WeltenAnlegenModellWahl(welt: welt, zustand: zustand)
                    }
                    .padding(.vertical, 4)
                }
                .frame(maxHeight: 320)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color(nsColor: .controlBackgroundColor)))
        .padding(.horizontal, 14).padding(.top, 8)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("welten-anlegen-gespraech-rechte")
    }

    @ViewBuilder private var hinweise: some View {
        let hinweis = WeltenZustand.gespraechHinweis(a)
        if !hinweis.isEmpty || a.gespraechFertig || !a.gespraechInfo.isEmpty {
            VStack(alignment: .leading, spacing: 3) {
                if a.gespraechFertig {
                    Label("Aus Sicht des Modells vollständig. Prüfen, dann anlegen.", systemImage: "checkmark.circle")
                        .font(.callout).foregroundStyle(.secondary)
                        .accessibilityIdentifier("welten-anlegen-gespraech-fertig")
                }
                if !hinweis.isEmpty {
                    HStack(spacing: 6) {
                        Label(hinweis, systemImage: "square.and.pencil").font(.callout).foregroundStyle(.secondary).lineLimit(2)
                        Button("Im Formular ansehen") { zustand.anlegenAnsicht(.formular) }
                            .buttonStyle(.borderless).controlSize(.small)
                    }
                    .accessibilityIdentifier("welten-anlegen-gespraech-hinweis")
                }
                if !a.gespraechInfo.isEmpty {
                    Text(a.gespraechInfo).font(.caption).foregroundStyle(.tertiary).lineLimit(2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14).padding(.top, 8)
        }
    }

    private var eingabe: some View {
        HStack(alignment: .bottom, spacing: 8) {
            Picker("Modell für das Gespräch", selection: Binding(get: { a.vorschlagModell }, set: { _ = zustand.anlegenFeld("vorschlagmodell", $0) })) {
                ForEach(a.entwurfModelle, id: \.self) { Text($0).tag($0) }
            }
            .labelsHidden()
            .fixedSize()
            .help("Modell für das Gespräch")
            TextField("Nachricht", text: Binding(get: { a.gespraechEingabe }, set: { _ = zustand.anlegenFeld("gespraech", $0) }),
                      prompt: Text(a.verlauf.isEmpty ? "Was soll der Agent tun?" : "Antwort an das Modell"), axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(1...6)
                .accessibilityIdentifier("welten-anlegen-gespraech-eingabe")
            Button("Senden") { Task { await zustand.gespraechSenden(welt, echt: true) } }
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(laeuft || leer)
                .help("Senden (⌘↩)")
                .accessibilityIdentifier("welten-anlegen-gespraech-senden")
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
    }
}

/// Eine Nachricht: der Mensch rechts im Akzent, das Modell links auf der Kartenflaeche; darunter, was der Zug gesetzt hat.
struct WeltenGespraechBlase: View {
    let zug: WeltenZustand.GespraechZug

    var body: some View {
        let mensch = zug.rolle == "mensch"
        HStack(alignment: .top, spacing: 8) {
            if mensch { Spacer(minLength: 60) }
            VStack(alignment: .leading, spacing: 5) {
                Text(zug.text).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                if !mensch, !zug.felder.isEmpty {
                    Label("Gesetzt: " + zug.felder.map(WeltenZustand.feldWort).joined(separator: ", "), systemImage: "square.and.pencil")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 9)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(mensch ? Color.accentColor.opacity(0.14) : Color(nsColor: .controlBackgroundColor)))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Color(nsColor: .separatorColor).opacity(mensch ? 0 : 1)))
            if !mensch { Spacer(minLength: 60) }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(mensch ? "Du: \(zug.text)" : "Modell: \(zug.text)")
    }
}

// MARK: Die Vorschau im Inspektor

struct WeltenAnlegenVorschau: View {
    let welt: Welt
    let anlegen: WeltenZustand.AnlegenEntwurf

    private var e: AgentEntwurf { anlegen.entwurf }

    var body: some View {
        VStack(spacing: 0) {
            Text("Vorschau").font(.headline)
                .frame(maxWidth: .infinity, minHeight: 24, alignment: .leading)
                .padding(10)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 12) {
                        figur.frame(width: 96, height: 96)
                        let k = Self.kopf(e)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(k.name).font(.title3.weight(.semibold)).foregroundStyle(e.id.isEmpty ? .secondary : .primary)
                            Text(k.stufe).foregroundStyle(.secondary)
                            Text(k.modell).font(.callout.monospaced()).foregroundStyle(.secondary)
                        }
                    }
                    zeile("Spezialgebiet", e.spezialgebiet)
                    // Auftrag agentsform: was der Agent darf, auf einer Karte.
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Darf").font(.callout.weight(.semibold)).foregroundStyle(.secondary)
                        zeile("Werkzeuge", (["Bash"] + e.werkzeuge.filter { $0 != "Bash" }).joined(separator: ", "))
                        zeile("Bash-Muster", (e.bashMuster.isEmpty ? "keine eigenen" : e.bashMuster.joined(separator: " · ")) + " + \(anlegen.dienstweg(e.stufe).count) Dienstweg")
                        zeile("Skills", e.skillListe.joined(separator: ", "))
                        zeile("Modell", [e.modellText + (e.modellGenau ? " · \(e.denkstufe)" : ""), e.fallback.isEmpty ? "" : "Fallback \(e.fallbackText)"].filter { !$0.isEmpty }.joined(separator: " · "))
                        zeile("Maschine", WeltenWorte.maschine(e.maschine))
                        if !e.kontextgrenze.isEmpty { zeile("Kontextgrenze", e.kontextgrenze) }
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color(nsColor: .controlBackgroundColor)))
                    .accessibilityIdentifier("welten-anlegen-vorschau-darf")
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Anweisungsdatei").font(.callout.weight(.semibold)).foregroundStyle(.secondary)
                        Text(e.anweisungen.isEmpty ? "Entsteht beim Anlegen aus der Hausvorlage." : e.anweisungen)
                            .font(.caption.monospaced()).foregroundStyle(e.anweisungen.isEmpty ? .secondary : .primary)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .accessibilityIdentifier("welten-anlegen-vorschau")
    }

    /// Die Kopfzeilen der Vorschau; die Auskunft liest dieselben (`anlegen.vorschau`).
    nonisolated static func kopf(_ e: AgentEntwurf) -> (name: String, stufe: String, modell: String) {
        (e.id.isEmpty ? "ohne Namen" : e.id,
         WeltenWorte.stufe(e.stufe) + (e.team.isEmpty || e.stufe == "hauptagent" ? "" : " · Team \(WeltenWorte.team(e.team))"),
         e.modellText)
    }

    @ViewBuilder private var figur: some View {
        if e.stufe == "hauptagent" {
            Agentenfigur(rolle: "hauptagent", stufe: "hauptagent", name: e.id.isEmpty ? "neu" : e.id, team: "hauptagent", groesse: 96)
        } else {
            Agentenfigur(rolle: e.figurArt == "linse" ? "reviewer" : (e.id.isEmpty ? "neu" : e.id), stufe: e.stufe, name: e.id.isEmpty ? "neu" : e.id,
                         team: e.figurFarbe, groesse: 96, arten: [e.figurFarbe: e.figurArt == "tier" ? "tier" : "roboter"])
        }
    }

    private func zeile(_ name: String, _ wert: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(name).font(.caption).foregroundStyle(.secondary)
            Text(wert.isEmpty ? "–" : wert).font(.callout).fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: Was ein Agent darf (Auftrag agentsform)

/// Die Rechte eines Agenten zum Setzen: im Formular, im Gespraech und im Profil dieselben Teile.
/// Werkzeuge mit Bash fest als Dienstweg, Web nur mit einem Zugang der Art web (sonst der Befehl dazu),
/// eigene Bash-Muster ueber den festen Mustern des Dienstwegs, Skills der Welt und der Bibliothek.
struct WeltenRechteAuswahl: View {
    let welt: Welt
    let werkzeuge: [String]
    let skills: [String]
    let dienstweg: [String]
    @Binding var bash: String
    let werkzeug: (String, Bool) -> Void
    let skill: (String, Bool) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            teil("Werkzeuge") {
                FlussLayout(abstand: 12) {
                    Toggle("Bash (Dienstweg)", isOn: .constant(true))
                        .disabled(true)
                        .help("Ohne Bash kann der Agent weder antworten noch Ergebnisse abgeben; es ist immer dabei.")
                    ForEach(WeltenZustand.werkzeuge, id: \.self) { w in
                        Toggle(w, isOn: Binding(get: { werkzeuge.contains(w) }, set: { werkzeug(w, $0) }))
                    }
                }
                .toggleStyle(.checkbox)
            }
            teil("Web") {
                if welt.webZugang {
                    FlussLayout(abstand: 12) {
                        ForEach(WeltenZustand.webWerkzeuge, id: \.self) { w in
                            Toggle(w, isOn: Binding(get: { werkzeuge.contains(w) }, set: { werkzeug(w, $0) }))
                        }
                    }
                    .toggleStyle(.checkbox)
                } else {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("WebFetch und WebSearch gibt es erst, wenn die Welt einen Zugang der Art web hat. Einrichten:")
                            .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text(welt.webZugangBefehl).font(.caption.monospaced()).textSelection(.enabled)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(.horizontal, 7).padding(.vertical, 4)
                                .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color(nsColor: .textBackgroundColor)))
                            Button("Kopieren") {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(welt.webZugangBefehl, forType: .string)
                            }
                            .buttonStyle(.borderless).controlSize(.small)
                        }
                    }
                    .accessibilityIdentifier("welten-rechte-web-satz")
                }
            }
            teil("Bash-Muster") {
                VStack(alignment: .leading, spacing: 6) {
                    TextEditor(text: $bash)
                        .font(.callout.monospaced())
                        .frame(minHeight: 44)
                        .scrollContentBackground(.hidden)
                        .padding(4)
                        .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color(nsColor: .textBackgroundColor)))
                        .accessibilityLabel("Eigene Bash-Muster, eins je Zeile")
                        .accessibilityIdentifier("welten-rechte-bash")
                    if dienstweg.isEmpty {
                        Text("Eigene Muster, eins je Zeile. Die Muster des Dienstwegs ergänzt die Bibliothek beim Anlegen.").font(.caption).foregroundStyle(.secondary)
                    } else {
                        DisclosureGroup {
                            VStack(alignment: .leading, spacing: 2) {
                                ForEach(dienstweg, id: \.self) { m in
                                    Label(m, systemImage: "lock").font(.caption.monospaced()).foregroundStyle(.secondary).textSelection(.enabled)
                                }
                            }
                            .padding(.top, 2)
                        } label: {
                            Text("Eigene Muster, eins je Zeile. Immer dabei: \(dienstweg.count) Muster des Dienstwegs").font(.caption).foregroundStyle(.secondary)
                        }
                        .accessibilityIdentifier("welten-rechte-dienstweg")
                    }
                }
            }
            teil("Skills") {
                let fremd = skills.filter { s in !welt.skillKatalog.contains { $0.name == s } }
                if welt.skillKatalog.isEmpty, fremd.isEmpty {
                    Text("Die Welt und die Bibliothek haben noch keine Skills.").font(.callout).foregroundStyle(.secondary)
                } else {
                    FlussLayout(abstand: 12) {
                        ForEach(welt.skillKatalog) { k in
                            Toggle(isOn: Binding(get: { skills.contains(k.name) }, set: { skill(k.name, $0) })) {
                                Text(k.name) + Text(k.ebene == "welt" ? " · Welt" : " · Bibliothek").foregroundStyle(.secondary)
                            }
                            .help(k.beschreibung)
                        }
                        ForEach(fremd, id: \.self) { name in
                            Toggle(isOn: Binding(get: { true }, set: { skill(name, $0) })) {
                                Text(name) + Text(" · nicht gefunden").foregroundStyle(.orange)
                            }
                        }
                    }
                    .toggleStyle(.checkbox)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func teil<Inhalt: View>(_ titel: String, @ViewBuilder _ inhalt: () -> Inhalt) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(titel).font(.callout.weight(.medium)).foregroundStyle(.secondary).accessibilityAddTraits(.isHeader)
            inhalt()
        }
    }
}

/// Modell, Denkstufe, Fallback und Maschine ausserhalb des Formulars (Gespraech): dieselben Regeln wie dort.
struct WeltenAnlegenModellWahl: View {
    let welt: Welt
    @Bindable var zustand: WeltenZustand

    private var a: WeltenZustand.AnlegenEntwurf { zustand.anlegen ?? WeltenZustand.AnlegenEntwurf() }

    private func modell(_ name: String, _ weg: WritableKeyPath<AgentEntwurf, String>) -> Binding<String> {
        Binding(get: { a.entwurf[keyPath: weg] }, set: { wert in
            if let f = zustand.anlegenModell(name, wert, welt) { zustand.meldung = WeltenZustand.Meldung(text: f, ok: false) }
        })
    }

    private func feld(_ name: String, _ weg: WritableKeyPath<AgentEntwurf, String>) -> Binding<String> {
        Binding(get: { a.entwurf[keyPath: weg] }, set: { _ = zustand.anlegenFeld(name, $0) })
    }

    var body: some View {
        let optionen = WeltenNutzlast.modellOptionen(welt, registry: a.modelle, eigene: [a.entwurf.modell, a.entwurf.fallback])
        Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 10, verticalSpacing: 6) {
            GridRow {
                Text("Modell").foregroundStyle(.secondary)
                HStack {
                    Picker("Modell", selection: modell("modell", \.modell)) {
                        ForEach(optionen, id: \.wert) { Text($0.titel).tag($0.wert).disabled(!$0.verfuegbar) }
                    }
                    .labelsHidden().fixedSize()
                    Picker("Denkstufe", selection: feld("denkstufe", \.denkstufe)) {
                        ForEach(WeltenWorte.denkstufen, id: \.self) { Text($0).tag($0) }
                    }
                    .labelsHidden().fixedSize()
                }
            }
            GridRow {
                Text("Fallback").foregroundStyle(.secondary)
                HStack {
                    Picker("Fallback", selection: modell("fallback", \.fallback)) {
                        Text("keiner").tag("")
                        ForEach(optionen, id: \.wert) { Text($0.titel).tag($0.wert).disabled(!$0.verfuegbar) }
                    }
                    .labelsHidden().fixedSize()
                    if !a.entwurf.fallback.isEmpty {
                        Picker("Fallback-Denkstufe", selection: feld("fallback-denkstufe", \.fallbackDenkstufe)) {
                            ForEach(WeltenWorte.denkstufen, id: \.self) { Text($0).tag($0) }
                        }
                        .labelsHidden().fixedSize()
                    }
                }
            }
            GridRow {
                Text("Maschine").foregroundStyle(.secondary)
                Picker("Maschine", selection: feld("maschine", \.maschine)) {
                    ForEach(WeltenZustand.maschinenWahl(a, welt), id: \.wert) { Text($0.titel).tag($0.wert) }
                }
                .labelsHidden().fixedSize()
            }
        }
        .font(.callout)
        .controlSize(.small)
    }
}
