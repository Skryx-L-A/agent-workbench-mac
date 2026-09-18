// DIE WELTEN DER AGENTS, WIE DER KERN SIE SCHICKT (14.09.2026, Plan Fassung 28,
// Abschnitt 6; Auftrag agentsui). Das Feld `welten` der Nutzlast `awb:aufgaben`
// (app/src/main/welten.ts), nachsichtig gelesen: ein fehlendes Feld heisst
// „leer", nicht „kaputt" -- der Kern darf Felder dazulegen, ohne dass diese
// Seite bricht.
//
// Hier stehen nur Daten und reine Ableitungen (Worte, Punkte, Ungelesen,
// Adressen). Gezeichnet wird in WeltenBlatt.swift. Die Zustaende und die
// Reihenfolge der Leiste rechnet der Kern -- dieselben fuer beide Oberflaechen.
import Foundation

private func text(_ j: [String: Any], _ k: String) -> String { j[k] as? String ?? "" }
private func optText(_ j: [String: Any], _ k: String) -> String? { j[k] as? String }
private func objekt(_ j: [String: Any], _ k: String) -> [String: Any] { j[k] as? [String: Any] ?? [:] }
private func liste(_ j: [String: Any], _ k: String) -> [[String: Any]] { j[k] as? [[String: Any]] ?? [] }
private func texte(_ j: [String: Any], _ k: String) -> [String] { j[k] as? [String] ?? [] }
/// Eine Zahl, aber kein Wahrheitswert (siehe AgentsBlatt.swift, `zahl`).
private func ganz(_ j: [String: Any], _ k: String) -> Int {
    guard let n = j[k] as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID() else { return 0 }
    return n.intValue
}

struct WeltNachricht: Equatable, Identifiable, Sendable {
    let id, art, von, text, zeit, betreff: String
    let an: [String]
    let ticket: String?
    let vonMensch: Bool
    /// `frage` oder `ergebnis` an den Menschen (Auftrag Nr. 2), sonst nil.
    let markierung: String?
    /// An den Menschen zugestellt und noch nicht quittiert.
    let offenFuerMensch: Bool

    init(_ j: [String: Any]) {
        id = Werkbank.text(j, "id"); art = Werkbank.text(j, "art"); von = Werkbank.text(j, "von")
        text = Werkbank.text(j, "text"); zeit = Werkbank.text(j, "zeit"); betreff = Werkbank.text(j, "betreff")
        an = texte(j, "an"); ticket = optText(j, "ticket"); vonMensch = j["von_mensch"] as? Bool ?? false
        markierung = optText(j, "markierung"); offenFuerMensch = j["offen_fuer_mensch"] as? Bool ?? false
    }
}

/// Eine Zeile aus dem Verlauf eines Agenten (history.json): Profil- und Gedaechtnisaenderungen.
struct WeltVerlaufseintrag: Equatable, Sendable {
    let zeit, ereignis, notiz, aenderungen: String

    init(_ j: [String: Any]) {
        zeit = Werkbank.text(j, "time"); ereignis = Werkbank.text(j, "event"); notiz = Werkbank.text(j, "note")
        let c = j["changes"] as? [String: Any] ?? [:]
        aenderungen = c.keys.sorted().map { k in
            let paar = c[k] as? [Any] ?? []
            let alt = paar.first.map { "\($0)" } ?? "", neu = paar.count > 1 ? "\(paar[1])" : ""
            return "\(WeltenWorte.profilfeld(k)): \(alt == "<null>" ? "–" : alt) → \(neu == "<null>" ? "–" : neu)"
        }.joined(separator: "; ")
    }
}

struct WeltMarke: Equatable, Sendable {
    let zeit, id: String
    static func neuer(_ a: WeltMarke?, _ b: WeltMarke?) -> WeltMarke? {
        guard let a else { return b }
        guard let b else { return a }
        return (a.zeit, a.id) >= (b.zeit, b.id) ? a : b
    }
}

struct WeltChatEintrag: Equatable, Identifiable, Sendable {
    let art, id, zeit: String
    let nachricht: WeltNachricht?
    let frage: String?

    init(_ j: [String: Any]) {
        art = text(j, "art"); id = text(j, "id"); zeit = text(j, "zeit")
        nachricht = (j["nachricht"] as? [String: Any]).map(WeltNachricht.init)
        frage = optText(j, "frage")
    }
}

struct WeltTicketEreignis: Equatable, Sendable {
    let zeit, ereignis, von, text: String
}

/// Ein Punkt der Fertig-Liste (`done_items`, Plan Satz 2); abgehakt wird nur vom Bearbeiter.
struct WeltFertigPunkt: Equatable, Identifiable, Sendable {
    let text: String
    let erledigt: Bool
    let von, zeit: String?
    let nr: Int
    var id: Int { nr }
}

struct WeltTicket: Equatable, Identifiable, Sendable {
    let id, titel, ziel, fertig, stand, absender, angelegt, geaendert: String
    let adressaten, abhaengig, wartetAuf: [String]
    let team, bearbeiter: String?
    let ergebnis: (text: String, commit: String?, von: String, zeit: String)?
    let abnahme: (von: String, zeit: String, bemerkung: String?, grund: String?)?
    let verlauf: [WeltTicketEreignis]
    let grenzen: [String: String]
    /// `limits.art`, etwa `skill-vorschlag` (Auftrag Nr. 4), und der Vorschlag mit Diff.
    let art: String
    let skillVorschlag: WeltSkillVorschlag?
    // --- tickets1 bis tickets3, gezeigt seit tickets4 (Plan Saetze 35 bis 41, 44, 46, 50) ---
    /// Art des Tickets (`vorhaben`, `story`, `task`, `subtask`, `auftrag`, `fehler`, `recherche`, `pruefung`, `skill-vorschlag`).
    let kind: String
    /// 0 sofort, 1 hoch, 2 normal, 3 später; `prioritaetText` ist der Bedeutungstext des Kerns.
    let prioritaet: Int
    let prioritaetText: String
    /// `grau`, `gelb`, `rot` aus `deadline_state`; leer ohne Frist.
    let ampel: String
    let eltern, herkunft, duplikatVon, zyklus: String?
    /// Backlog-Reihenfolge in der Triage (Satz 44); nil ausserhalb der Triage.
    let ordnung: Int?
    let fertigPunkte: [WeltFertigPunkt]
    let kinderGesamt, kinderAbgenommen: Int
    /// Messung je Ticket (Satz 50): Durchlaufzeit, Alter (Sekunden) und Züge.
    let durchlaufzeit, alterSekunden, zuege: Int
    let geparkt: (grund: String, bis: String?, auf: String?)?
    let flagge: (grund: String, frage: String?, vorher: String?)?
    let verworfen: (code: String, bemerkung: String?, duplikatVon: String?)?
    let pruefung: (pruefer: String, revision: Int, angefordertVon: String, notiz: String?, urteil: String?)?

    static func == (a: WeltTicket, b: WeltTicket) -> Bool {
        a.id == b.id && a.stand == b.stand && a.geaendert == b.geaendert && a.verlauf == b.verlauf
            && a.titel == b.titel && a.adressaten == b.adressaten && a.bearbeiter == b.bearbeiter && a.wartetAuf == b.wartetAuf
            && a.art == b.art && a.skillVorschlag == b.skillVorschlag
            && a.kind == b.kind && a.prioritaet == b.prioritaet && a.ampel == b.ampel && a.ordnung == b.ordnung
            && a.fertigPunkte == b.fertigPunkte && a.kinderGesamt == b.kinderGesamt && a.kinderAbgenommen == b.kinderAbgenommen
            && a.pruefung?.pruefer == b.pruefung?.pruefer && a.pruefung?.urteil == b.pruefung?.urteil
            && a.geparkt?.grund == b.geparkt?.grund && a.flagge?.grund == b.flagge?.grund && a.verworfen?.code == b.verworfen?.code
    }

    init(_ j: [String: Any]) {
        id = text(j, "id"); titel = text(j, "titel"); ziel = text(j, "ziel"); fertig = text(j, "fertig")
        stand = text(j, "stand"); absender = text(j, "absender"); angelegt = text(j, "angelegt"); geaendert = text(j, "geaendert")
        adressaten = texte(j, "adressaten"); abhaengig = texte(j, "abhaengig"); wartetAuf = texte(j, "wartet_auf")
        team = optText(j, "team"); bearbeiter = optText(j, "bearbeiter")
        if let e = j["ergebnis"] as? [String: Any] {
            ergebnis = (text(e, "text"), optText(e, "commit"), text(e, "von"), text(e, "zeit"))
        } else { ergebnis = nil }
        if let a = j["abnahme"] as? [String: Any] {
            abnahme = (text(a, "von"), text(a, "zeit"), optText(a, "bemerkung"), optText(a, "grund"))
        } else { abnahme = nil }
        verlauf = liste(j, "verlauf").map { WeltTicketEreignis(zeit: text($0, "zeit"), ereignis: text($0, "ereignis"), von: text($0, "von"), text: text($0, "text")) }
        grenzen = objekt(j, "grenzen").reduce(into: [:]) { $0[$1.key] = "\($1.value)" }
        art = text(j, "art")
        skillVorschlag = (j["skill_vorschlag"] as? [String: Any]).map(WeltSkillVorschlag.init)
        kind = text(j, "kind").isEmpty ? "auftrag" : text(j, "kind")
        prioritaet = (j["prioritaet"] as? NSNumber).map(\.intValue) ?? 2
        prioritaetText = text(j, "prioritaet_text")
        ampel = text(j, "ampel")
        eltern = optText(j, "eltern"); herkunft = optText(j, "herkunft"); duplikatVon = optText(j, "duplikat_von")
        zyklus = optText(j, "zyklus")
        ordnung = (j["ordnung"] as? NSNumber).flatMap { CFGetTypeID($0) == CFBooleanGetTypeID() ? nil : $0.intValue }
        fertigPunkte = liste(j, "fertig_punkte").enumerated().map { nr, p in
            WeltFertigPunkt(text: text(p, "text"), erledigt: p["erledigt"] as? Bool ?? false,
                            von: optText(p, "von"), zeit: optText(p, "zeit"), nr: nr + 1)
        }
        kinderGesamt = ganz(j, "kinder_gesamt"); kinderAbgenommen = ganz(j, "kinder_abgenommen")
        durchlaufzeit = ganz(j, "durchlaufzeit_s"); alterSekunden = ganz(j, "alter_s"); zuege = ganz(j, "zuege")
        if let p = j["geparkt"] as? [String: Any] { geparkt = (text(p, "grund"), optText(p, "bis"), optText(p, "auf")) } else { geparkt = nil }
        if let f = j["flagge"] as? [String: Any] { flagge = (text(f, "grund"), optText(f, "frage"), optText(f, "vorher")) } else { flagge = nil }
        if let v = j["verworfen"] as? [String: Any] { verworfen = (text(v, "code"), optText(v, "bemerkung"), optText(v, "duplikat_von")) } else { verworfen = nil }
        if let r = j["pruefung"] as? [String: Any] {
            pruefung = (text(r, "pruefer"), ganz(r, "revision"), text(r, "angefordert_von"), optText(r, "notiz"), optText(r, "urteil"))
        } else { pruefung = nil }
    }

    /// Wie viele Punkte der Fertig-Liste abgehakt sind; (0, 0) ohne Liste.
    var fertigStand: (erledigt: Int, gesamt: Int) { (fertigPunkte.filter(\.erledigt).count, fertigPunkte.count) }
}

struct WeltFrage: Equatable, Identifiable, Sendable {
    let id, text, stand, von, gestellt: String
    let optionen: [String]
    let empfehlung, ticket: String?
    let antwort: (text: String, von: String, zeit: String)?
    let ruecknahme: (grund: String?, von: String, zeit: String)?

    var offen: Bool { stand == "offen" }

    static func == (a: WeltFrage, b: WeltFrage) -> Bool {
        a.id == b.id && a.stand == b.stand && a.text == b.text && a.optionen == b.optionen && a.antwort?.text == b.antwort?.text
    }

    init(_ j: [String: Any]) {
        id = Werkbank.text(j, "id"); text = Werkbank.text(j, "text"); stand = Werkbank.text(j, "stand")
        von = Werkbank.text(j, "von"); gestellt = Werkbank.text(j, "gestellt")
        optionen = texte(j, "optionen"); empfehlung = optText(j, "empfehlung"); ticket = optText(j, "ticket")
        if let a = j["antwort"] as? [String: Any] { antwort = (Werkbank.text(a, "text"), Werkbank.text(a, "von"), Werkbank.text(a, "zeit")) } else { antwort = nil }
        if let r = j["ruecknahme"] as? [String: Any] { ruecknahme = (optText(r, "grund"), Werkbank.text(r, "von"), Werkbank.text(r, "zeit")) } else { ruecknahme = nil }
    }

    /// Die Empfehlung zuerst, freie Antwort bleibt moeglich (wie im Agents-Blatt aus Fassung 26).
    var optionenGeordnet: [String] {
        guard let e = empfehlung, optionen.contains(e) else { return optionen }
        return [e] + optionen.filter { $0 != e }
    }
}

/// DAS LEBENSZEICHEN (Auftrag agentaktiv, 15.09.2026): je Agent, was der Traeger ueber seinen Zug sagt
/// (`agents_traeger.py status --nur-zug`, ueber welten.ts). Ohne Traeger fehlt alles davon.
struct WeltZug: Equatable, Sendable {
    let laeuft, zustellungOffen: Bool
    let seit, art, wartetSeit, grund, naechsterWecker: String?
    /// Der letzte beendete Zug: Ende, Urteil, Art.
    let letzterEnde, letzterErgebnis: String?

    init?(_ j: [String: Any]?) {
        guard let j, let l = j["laeuft"] as? Bool else { return nil }
        laeuft = l; zustellungOffen = j["zustellung_offen"] as? Bool ?? false
        seit = optText(j, "seit"); art = optText(j, "art"); wartetSeit = optText(j, "wartet_seit"); grund = optText(j, "grund")
        naechsterWecker = optText(j, "naechster_wecker")
        let letzter = j["letzter"] as? [String: Any]
        letzterEnde = letzter.flatMap { optText($0, "ende") }; letzterErgebnis = letzter.flatMap { optText($0, "ergebnis") }
    }
}

/// `arbeitet` (ein Zug laeuft), `wartet` (eine Zustellung ohne Zug), `schlaeft`, `nicht_erreichbar`.
struct WeltLeben: Equatable, Sendable {
    let stand: String
    let seit, grund, wecker: String?

    init?(_ j: [String: Any]?) {
        guard let j, let st = j["stand"] as? String, !st.isEmpty else { return nil }
        stand = st; seit = optText(j, "seit"); grund = optText(j, "grund"); wecker = optText(j, "wecker")
    }
}

/// Der Stand unter der eigenen, noch unbeantworteten Nachricht im Einzelchat.
struct WeltAntwortStand: Equatable, Sendable {
    let nachricht, zeit, stand, wecken: String
    let grund: String?

    init?(_ j: [String: Any]?) {
        guard let j, let n = j["nachricht"] as? String, !n.isEmpty else { return nil }
        nachricht = n; zeit = text(j, "zeit"); stand = text(j, "stand"); wecken = text(j, "wecken"); grund = optText(j, "grund")
    }
}

struct WeltAgent: Equatable, Identifiable, Sendable {
    let id, name, stufe, spezialgebiet, modell, fallback, maschine, stand, standSeit, angelegt: String
    let team, standGrund, ticket: String?
    let figurArt, figurRolle: String
    let zustand, zustandText, figurZustand: String
    let werkzeuge, skills, tickets, direktchats: [String]
    let postfachOffen, postfachGesamt: Int
    let gedaechtnis: String
    let gedaechtnisGekuerzt: Bool
    let gedaechtnisGeaendert: String?
    let verlaufAnzahl: Int
    let verlauf: [WeltVerlaufseintrag]
    let denkstufe, fallbackDenkstufe, gedaechtnisSha: String
    let einzelchat: [WeltChatEintrag]
    /// Auftrag Nr. 3: Bash-Muster, Kontextgrenze, Figurfarbe (Farbschluessel des Teams), Vorlage, wer anlegte.
    let bash: [String]
    let kontextgrenze, figurFarbe: String
    let vorlage, angelegtVon: String?
    /// Auftrag Nr. 4: der Skill-Reiter.
    let skillAnsicht: WeltSkills
    /// Auftrag agentaktiv: Zug, Lebenszeichen und der Stand unter der eigenen Nachricht; nil ohne Traeger.
    let zug: WeltZug?
    let leben: WeltLeben?
    let antwort: WeltAntwortStand?

    init(_ j: [String: Any]) {
        id = text(j, "id"); name = text(j, "name"); stufe = text(j, "stufe"); spezialgebiet = text(j, "spezialgebiet")
        modell = text(j, "modell"); fallback = text(j, "fallback"); maschine = text(j, "maschine"); stand = text(j, "stand")
        standSeit = text(j, "stand_seit"); angelegt = text(j, "angelegt")
        team = optText(j, "team"); standGrund = optText(j, "stand_grund"); ticket = optText(j, "ticket")
        let f = objekt(j, "figur"); figurArt = text(f, "art"); figurRolle = text(f, "rolle")
        zustand = text(j, "zustand"); zustandText = text(j, "zustand_text"); figurZustand = text(j, "figur_zustand")
        werkzeuge = texte(j, "werkzeuge"); skills = texte(j, "skills"); tickets = texte(j, "tickets"); direktchats = texte(j, "direktchats")
        postfachOffen = ganz(j, "postfach_offen"); postfachGesamt = ganz(j, "postfach_gesamt")
        let g = objekt(j, "gedaechtnis"); gedaechtnis = text(g, "text"); gedaechtnisGekuerzt = g["gekuerzt"] as? Bool ?? false
        gedaechtnisGeaendert = optText(g, "geaendert")
        verlaufAnzahl = (j["verlauf"] as? [Any])?.count ?? 0
        verlauf = liste(j, "verlauf").map(WeltVerlaufseintrag.init)
        denkstufe = text(j, "denkstufe"); fallbackDenkstufe = text(j, "fallback_denkstufe"); gedaechtnisSha = text(g, "sha256")
        einzelchat = liste(j, "einzelchat").map(WeltChatEintrag.init)
        bash = texte(j, "bash"); kontextgrenze = text(j, "kontextgrenze"); figurFarbe = text(f, "farbe")
        vorlage = optText(j, "vorlage"); angelegtVon = optText(j, "angelegt_von")
        skillAnsicht = WeltSkills(objekt(j, "skill_ansicht"))
        zug = WeltZug(j["zug"] as? [String: Any]); leben = WeltLeben(j["leben"] as? [String: Any])
        antwort = WeltAntwortStand(j["antwort"] as? [String: Any])
    }

    var istHauptagent: Bool { stufe == "hauptagent" }
    /// Der Ring um die Figur (Agentenfigur.swift, `FigurRing`).
    var ring: FigurRing { leben?.stand == "arbeitet" ? .arbeitet : leben?.stand == "wartet" ? .wartet : .keiner }
    var figur: FigurZustand { FigurZustand(vertrag: figurZustand) }
    /// Die Art je Team fuer `Agentenfigur`: das Profil entscheidet, nicht die Vorgabe des Teams.
    var arten: [String: String] { [figurTeam: figurArt == "tier" ? "tier" : "roboter"] }
    /// Das Team der Figur: die gewaehlte Farbe, sonst das Team des Agenten.
    var figurTeam: String { istHauptagent ? "hauptagent" : (figurFarbe.isEmpty ? (team ?? "ohne-team") : figurFarbe) }
}

// MARK: Skills (Auftrag Nr. 4, agents_skills_ansicht.py ueber welten.ts)

struct WeltSkill: Equatable, Identifiable, Sendable {
    let name, ebene, version, beschreibung, skillMd: String
    let vorgeladen, gekuerzt, veraltet: Bool
    let verdeckt: [(ebene: String, version: String, gleich: Bool)]
    let befunde: [String]
    let dateien: [String]
    var id: String { name }

    static func == (a: WeltSkill, b: WeltSkill) -> Bool {
        a.name == b.name && a.ebene == b.ebene && a.version == b.version && a.vorgeladen == b.vorgeladen
            && a.veraltet == b.veraltet && a.verdeckt.map { "\($0.ebene)\($0.version)\($0.gleich)" } == b.verdeckt.map { "\($0.ebene)\($0.version)\($0.gleich)" }
    }

    init(_ j: [String: Any]) {
        name = text(j, "name"); ebene = text(j, "ebene"); version = text(j, "version"); beschreibung = text(j, "beschreibung")
        skillMd = text(j, "skill_md"); vorgeladen = j["vorgeladen"] as? Bool ?? false; gekuerzt = j["gekuerzt"] as? Bool ?? false
        veraltet = j["veraltet"] as? Bool ?? false
        verdeckt = liste(j, "verdeckt").map { (text($0, "ebene"), text($0, "version"), $0["gleich"] as? Bool ?? false) }
        befunde = liste(j, "befunde").map { text($0, "text") }.filter { !$0.isEmpty }
        dateien = texte(j, "dateien")
    }
}

struct WeltSkillMessung: Equatable, Identifiable, Sendable {
    let art: String
    let anzahl: Int
    let mittel, mittelLetzte: Double
    let letzte: [Double]
    let veraenderung: Double?
    var id: String { art }

    init(_ j: [String: Any]) {
        art = text(j, "art"); anzahl = ganz(j, "anzahl")
        mittel = (j["mittel"] as? NSNumber)?.doubleValue ?? 0
        mittelLetzte = (j["mittel_letzte"] as? NSNumber)?.doubleValue ?? 0
        letzte = (j["letzte"] as? [Any] ?? []).compactMap { ($0 as? NSNumber)?.doubleValue }
        veraenderung = (j["veraenderung"] as? NSNumber)?.doubleValue
    }
}

struct WeltSkills: Equatable, Sendable {
    let quelle, stand: String?
    let liste: [WeltSkill]
    let fehlend: [String]
    let ungueltig: [String]
    let verlauf: [(zeit: String, aktion: String, skill: String, ziel: String, text: String)]
    let messungen: [WeltSkillMessung]
    let fehler: [String]

    static func == (a: WeltSkills, b: WeltSkills) -> Bool {
        a.quelle == b.quelle && a.stand == b.stand && a.liste == b.liste && a.fehlend == b.fehlend && a.ungueltig == b.ungueltig
            && a.messungen == b.messungen && a.fehler == b.fehler && a.verlauf.count == b.verlauf.count
    }

    init(_ j: [String: Any]) {
        quelle = optText(j, "quelle"); stand = optText(j, "stand")
        liste = Werkbank.liste(j, "liste").map(WeltSkill.init)
        fehlend = texte(j, "fehlend")
        ungueltig = Werkbank.liste(j, "ungueltig").map { "\(text($0, "name")) (\(text($0, "ebene"))): \(text($0, "text"))" }
        verlauf = Werkbank.liste(j, "verlauf").map { (text($0, "zeit"), text($0, "aktion"), text($0, "skill"), text($0, "ziel"), text($0, "text")) }
        messungen = Werkbank.liste(j, "messungen").map(WeltSkillMessung.init)
        fehler = texte(j, "fehler")
    }
}

struct WeltSkillVorschlag: Equatable, Sendable {
    let skill, agent, ziel, stand, version, beschreibung, begruendung, pruefer, diff: String
    let basisVersion, entschiedenVon, bemerkung, grund: String?
    let diffGekuerzt: Bool

    init(_ j: [String: Any]) {
        skill = text(j, "skill"); agent = text(j, "agent"); ziel = text(j, "ziel"); stand = text(j, "stand")
        version = text(j, "version"); beschreibung = text(j, "beschreibung"); begruendung = text(j, "begruendung")
        pruefer = text(j, "pruefer"); diff = text(j, "diff"); diffGekuerzt = j["diff_gekuerzt"] as? Bool ?? false
        basisVersion = optText(j, "basis_version"); entschiedenVon = optText(j, "entschieden_von")
        bemerkung = optText(j, "bemerkung"); grund = optText(j, "grund")
    }

    var offen: Bool { stand == "offen" }
}

/// Ein Antrag eines Teamleiters auf einen neuen Agenten (Frage an den Hauptagenten).
struct WeltAntrag: Equatable, Identifiable, Sendable {
    let id, von, an, agent, spezialgebiet, stand, zeit: String
    let team, entscheidung, bemerkung: String?

    init(_ j: [String: Any]) {
        id = text(j, "id"); von = text(j, "von"); an = text(j, "an"); agent = text(j, "agent")
        spezialgebiet = text(j, "spezialgebiet"); stand = text(j, "stand"); zeit = text(j, "zeit")
        team = optText(j, "team"); entscheidung = optText(j, "entscheidung"); bemerkung = optText(j, "bemerkung")
    }
}

/// Ein Entwurf fuer einen neuen Agenten, in den Feldern der Datenbibliothek (`validate_agent_draft`).
struct AgentEntwurf: Equatable, Sendable {
    var id = "", stufe = "mitglied", team = "", spezialgebiet = "", modell = "sonnet5", denkstufe = "high"
    var fallback = "", fallbackDenkstufe = "", maschine = "peer"
    // Jede Stufe schreibt (15.09.2026); Web-Werkzeuge kommen nur auf Wahl dazu.
    var werkzeuge: [String] = ["Read", "Grep", "Glob", "Bash", "Write", "Edit"]
    var bash = "", skills = "", kontextgrenze = ""
    var figurArt = "roboter", figurFarbe = "entwicklung"
    var anweisungen = "", vorlage = ""
    /// Auftrag agentsform: Modell und Fallback sind Kennungen aus der Modellliste der Welt und gehen woertlich
    /// hinaus (`sonnet5:high`, `haiku`); der Traeger sucht genau diesen Namen. Sonst Basis plus Denkstufe als Suffix.
    var modellGenau = false

    init() {}

    init(_ j: [String: Any], genau: Bool = false) {
        id = text(j, "id"); stufe = text(j, "stage").isEmpty ? "mitglied" : text(j, "stage"); team = text(j, "team")
        spezialgebiet = text(j, "specialty"); maschine = text(j, "machine")
        (modell, denkstufe) = Self.teilen(text(j, "model"), text(j, "effort"))
        (fallback, fallbackDenkstufe) = Self.teilen(text(j, "fallback_model"), text(j, "fallback_effort"))
        if genau {
            modellGenau = true
            if !text(j, "model").isEmpty { modell = text(j, "model") }
            fallback = text(j, "fallback_model")
        }
        werkzeuge = texte(j, "tools"); bash = texte(j, "bash").joined(separator: "\n"); skills = texte(j, "skills").joined(separator: ", ")
        kontextgrenze = text(j, "context_limit")
        let f = objekt(j, "figure"); figurArt = text(f, "family").isEmpty ? "roboter" : text(f, "family")
        figurFarbe = text(f, "color").isEmpty ? "entwicklung" : text(f, "color")
        anweisungen = text(j, "instructions"); vorlage = text(j, "template")
    }

    /// Auftrag agentsform: die eigenen Bash-Muster ohne die Dienstwegmuster, die die Bibliothek ohnehin dazugibt.
    static func eigeneMuster(_ muster: [String], _ dienstweg: [String]) -> [String] {
        muster.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty && !dienstweg.contains($0) }
    }

    /// Was als `model` und `fallback_model` hinausgeht.
    var modellText: String { modellGenau ? modell : Self.mitStufe(modell, denkstufe) }
    var fallbackText: String { fallback.isEmpty ? "" : (modellGenau ? fallback : Self.mitStufe(fallback, fallbackDenkstufe)) }

    var bashMuster: [String] { bash.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty } }
    var skillListe: [String] { skills.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty } }

    /// `sonnet5:high` -> (`sonnet5`, `high`); eine ausdrueckliche Stufe gilt vor dem Suffix.
    static func teilen(_ modell: String, _ stufe: String) -> (String, String) {
        let teile = modell.split(separator: ":", maxSplits: 1).map(String.init)
        let basis = teile.first ?? ""
        return (basis, stufe.isEmpty ? (teile.count > 1 ? teile[1] : "") : stufe)
    }

    /// Modell mit Denkstufe als Suffix, wie die Registry spawnt (`sonnet5:high`).
    static func mitStufe(_ modell: String, _ stufe: String) -> String {
        let basis = modell.split(separator: ":").first.map(String.init) ?? modell
        return basis.isEmpty ? "" : (stufe.isEmpty ? basis : "\(basis):\(stufe)")
    }

    /// Das JSON fuer `welt:entwurf`, `welt:anlegen` und die Vorgaben eines Vorschlags; leere Felder fehlen.
    func json(nurGesetzt: Bool = false) -> [String: Any] {
        var j: [String: Any] = [:]
        func setze(_ k: String, _ v: String) { let t = v.trimmingCharacters(in: .whitespacesAndNewlines); if !t.isEmpty { j[k] = t } }
        setze("id", id); setze("team", stufe == "hauptagent" ? "" : team); setze("specialty", spezialgebiet)
        setze("machine", maschine); setze("context_limit", kontextgrenze); setze("template", vorlage)
        if !nurGesetzt {
            setze("stage", stufe)
            setze("model", modellText); setze("effort", denkstufe)
            setze("fallback_model", fallbackText); if !fallback.isEmpty { setze("fallback_effort", fallbackDenkstufe) }
            j["tools"] = werkzeuge
            j["figure"] = ["family": figurArt, "color": figurFarbe]
        }
        let muster = bash.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        if !muster.isEmpty || !nurGesetzt { j["bash"] = werkzeuge.contains("Bash") ? muster : [String]() }
        let s = skills.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        if !s.isEmpty || !nurGesetzt { j["skills"] = s }
        if !anweisungen.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { j["instructions"] = anweisungen }
        return j
    }
}

struct WeltVorlage: Equatable, Identifiable, Sendable {
    let name, titel, zusammenfassung: String
    let entwurf: AgentEntwurf
    var id: String { name }
}

struct ModellZeile: Equatable, Identifiable, Sendable {
    let kennung, harness, aufgabe: String
    var id: String { kennung }
}

/// Auftrag agentsform: ein Modell, das der Traeger einer Welt fahren kann (`wb-welt ansicht`, Feld `modelle`).
struct WeltModell: Equatable, Identifiable, Sendable {
    let id, harness, grund: String
    let verfuegbar: Bool
}

/// Ein Skill der Welt oder der Bibliothek zur Auswahl beim Anlegen (`agents_skills_ansicht.py`, `katalog`).
struct WeltSkillAuswahl: Equatable, Identifiable, Sendable {
    let name, beschreibung, ebene: String
    var id: String { "\(ebene):\(name)" }
}

struct WeltTeam: Equatable, Identifiable, Sendable {
    let name: String
    let leiter: String?
    let mitglieder: [String]
    let aktiv: Int
    var id: String { name }
}

/// Ein abgeschlossener Zyklus mit seinen Zahlen (`zyklen.jsonl`, Plan Satz 46).
struct WeltZyklus: Equatable, Identifiable, Sendable {
    let id, start, ende, ziel, abgeschlossen: String
    let angelegt, abgenommen, uebertragen, verworfen: Int
}

/// Der Zyklus einer Welt: eingeschaltet, Länge, der laufende und die Historie.
struct WeltZyklusStand: Equatable, Sendable {
    let an: Bool
    let tage: Int
    let jetzt: (id: String, start: String, ende: String, ziel: String)?
    let historie: [WeltZyklus]

    static func == (a: WeltZyklusStand, b: WeltZyklusStand) -> Bool {
        a.an == b.an && a.tage == b.tage && a.jetzt?.id == b.jetzt?.id && a.jetzt?.ziel == b.jetzt?.ziel
            && a.historie == b.historie
    }

    init(_ j: [String: Any]) {
        an = j["an"] as? Bool ?? false
        tage = ganz(j, "tage")
        if let n = j["jetzt"] as? [String: Any], !text(n, "id").isEmpty {
            jetzt = (text(n, "id"), text(n, "start"), text(n, "ende"), text(n, "ziel"))
        } else { jetzt = nil }
        historie = liste(j, "historie").map {
            WeltZyklus(id: text($0, "id"), start: text($0, "start"), ende: text($0, "ende"), ziel: text($0, "ziel"),
                       abgeschlossen: text($0, "abgeschlossen"), angelegt: ganz($0, "angelegt"),
                       abgenommen: ganz($0, "abgenommen"), uebertragen: ganz($0, "uebertragen"), verworfen: ganz($0, "verworfen"))
        }
    }
}

struct WeltDirektchat: Equatable, Identifiable, Sendable {
    let id: String
    let teilnehmer: [String]
    let nachrichten: [WeltNachricht]
    let gesamt: Int
}

struct Welt: Equatable, Identifiable, Sendable {
    let pfad, art, name, stand, standSeit, gelesen: String
    let id: String
    let projekt, standGrund, hauptagent: String?
    let konsistent: Bool
    let fehler: [String]
    let brauchenDich, laufen, ticketsOffen: Int
    /// tickets4: die Triage getrennt (Satz 35), die weiche WIP-Grenze (Satz 48), Zyklus (46) und DoD (49).
    let triage: Int
    let wip: (laufend: Int, grenze: Int)
    let zyklus: WeltZyklusStand
    let dod: [String]
    let teams: [WeltTeam]
    let ohneTeam, liste: [String]
    let agenten: [WeltAgent]
    let tickets: [WeltTicket]
    let kanal: [WeltNachricht]
    let kanalGesamt: Int
    let direktchats: [WeltDirektchat]
    let fragen: [WeltFrage]
    let antraege: [WeltAntrag]
    let skillVerlauf: [(zeit: String, ereignis: String, skill: String, agent: String)]
    let skillsFehler: String
    /// Ungelesen je Gespraech nach dem Lesestand der Welt (menschen/mensch/gelesen.json).
    let ungelesen: [String: Int]
    let gelesenMarken: [String: WeltMarke]
    /// Markierte Nachrichten an den Menschen, noch nicht quittiert: (Zustellung, Absender, Markierung).
    let markiertOffen: [(zustellung: String, von: String, markierung: String)]
    /// Auftrag fernwelten: die Maschine der Ablage (`peer`, die eigene `mac`), ob sie fern liegt, ihr Pfad dort.
    let maschine, ablage: String
    let fern: Bool
    /// Die Verbindung zur Maschine der Welt; `seit`: seit wann sie nicht antwortet.
    let verbindungOk: Bool
    let verbindungSeit: String?
    let verbindungText: String
    /// `traeger.json` in der Ablage; `traegerLaeuft` nil, wo es sich nicht feststellen laesst; `traegerMoeglich`: dort kann einer laufen.
    let traegerEingerichtet: Bool
    let traegerLaeuft: Bool?
    let traegerMoeglich: Bool
    /// Zugaenge nach draussen (`zugaenge.json`), nur Name und Art, etwa `myproject-server (ssh)`.
    let zugaenge: [String]
    /// Auftrag agentaktiv: warum das Lebenszeichen nicht lesbar war; leer, wenn es lesbar war oder kein Traeger da ist.
    let traegerZugFehler: String
    /// Auftrag agentsform: die Modelle des Traegers dieser Welt; nil, solange der Kern das Feld nicht liefert (dann gilt die Registry).
    let modelle: [WeltModell]?
    /// Die Maschine eines neuen Agenten (Traegermaschine der Welt); leer, solange die Ansicht sie nicht nennt.
    let maschineVorgabe: String
    /// Die Skills der Welt und der Bibliothek zur Auswahl beim Anlegen.
    let skillKatalog: [WeltSkillAuswahl]
    /// Ob die Welt einen Zugang der Art `web` hat: nur dann gibt es WebFetch und WebSearch.
    let webZugang: Bool
    /// Ob die Bibliothek auf der Maschine der Welt `wb-agent rechte` kennt; sonst stehen die Rechte im Profil nur zum Lesen.
    let rechteAenderbar: Bool

    static func == (a: Welt, b: Welt) -> Bool {
        a.pfad == b.pfad && a.name == b.name && a.stand == b.stand && a.gelesen == b.gelesen && a.agenten == b.agenten
            && a.tickets == b.tickets && a.kanal == b.kanal && a.direktchats == b.direktchats && a.fragen == b.fragen
            && a.ungelesen == b.ungelesen && a.gelesenMarken == b.gelesenMarken && a.fehler == b.fehler && a.teams == b.teams
            && a.liste == b.liste && a.brauchenDich == b.brauchenDich && a.laufen == b.laufen && a.ticketsOffen == b.ticketsOffen
            && a.markiertOffen.map(\.zustellung) == b.markiertOffen.map(\.zustellung) && a.konsistent == b.konsistent
            && a.antraege == b.antraege && a.skillsFehler == b.skillsFehler && a.skillVerlauf.count == b.skillVerlauf.count
            && a.maschine == b.maschine && a.fern == b.fern && a.verbindungOk == b.verbindungOk && a.verbindungSeit == b.verbindungSeit
            && a.traegerEingerichtet == b.traegerEingerichtet && a.traegerLaeuft == b.traegerLaeuft && a.traegerMoeglich == b.traegerMoeglich
            && a.zugaenge == b.zugaenge
            && a.traegerZugFehler == b.traegerZugFehler
            && a.modelle == b.modelle && a.maschineVorgabe == b.maschineVorgabe && a.skillKatalog == b.skillKatalog
            && a.webZugang == b.webZugang && a.rechteAenderbar == b.rechteAenderbar
            && a.triage == b.triage && a.wip == b.wip && a.zyklus == b.zyklus && a.dod == b.dod
    }

    init(_ j: [String: Any]) {
        pfad = text(j, "pfad"); art = text(j, "art"); name = text(j, "name"); stand = text(j, "stand")
        standSeit = text(j, "stand_seit"); gelesen = text(j, "gelesen"); id = text(j, "id")
        projekt = optText(j, "projekt"); standGrund = optText(j, "stand_grund"); hauptagent = optText(j, "hauptagent")
        konsistent = j["konsistent"] as? Bool ?? true
        fehler = texte(j, "fehler")
        let z = objekt(j, "zaehler")
        brauchenDich = ganz(z, "brauchen_dich"); laufen = ganz(z, "laufen"); ticketsOffen = ganz(z, "tickets_offen")
        triage = ganz(z, "triage")
        let wp = objekt(j, "wip")
        wip = (ganz(wp, "laufend"), ganz(wp, "grenze"))
        zyklus = WeltZyklusStand(objekt(j, "zyklus"))
        dod = texte(j, "dod")
        teams = Werkbank.liste(j, "teams").map { WeltTeam(name: text($0, "name"), leiter: optText($0, "leiter"), mitglieder: texte($0, "mitglieder"), aktiv: ganz($0, "aktiv")) }
        ohneTeam = texte(j, "ohne_team"); liste = texte(j, "liste")
        agenten = Werkbank.liste(j, "agenten").map(WeltAgent.init)
        tickets = Werkbank.liste(j, "tickets").map(WeltTicket.init)
        kanal = Werkbank.liste(j, "kanal").map(WeltNachricht.init)
        kanalGesamt = ganz(j, "kanal_gesamt")
        direktchats = Werkbank.liste(j, "direktchats").map { WeltDirektchat(id: text($0, "id"), teilnehmer: texte($0, "teilnehmer"), nachrichten: Werkbank.liste($0, "nachrichten").map(WeltNachricht.init), gesamt: ganz($0, "gesamt")) }
        fragen = Werkbank.liste(j, "fragen").map(WeltFrage.init)
        antraege = Werkbank.liste(j, "antraege").map(WeltAntrag.init)
        skillVerlauf = Werkbank.liste(j, "skill_verlauf").map { (text($0, "zeit"), text($0, "ereignis"), text($0, "skill"), text($0, "agent")) }
        skillsFehler = text(j, "skills_fehler")
        ungelesen = (j["ungelesen"] as? [String: Any] ?? [:]).reduce(into: [:]) { r, e in
            if let n = e.value as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID() { r[e.key] = n.intValue }
        }
        let m = objekt(j, "mensch")
        gelesenMarken = objekt(m, "gelesen").reduce(into: [:]) { r, e in
            if let v = e.value as? [String: Any] { r[e.key] = WeltMarke(zeit: text(v, "zeit"), id: text(v, "id")) }
        }
        markiertOffen = Werkbank.liste(m, "markiert_offen").map { (text($0, "zustellung"), text($0, "von"), text($0, "markierung")) }
        maschine = text(j, "maschine"); fern = j["fern"] as? Bool ?? false
        ablage = text(j, "ablage").isEmpty ? pfad : text(j, "ablage")
        let v = objekt(j, "verbindung")
        verbindungOk = v["ok"] as? Bool ?? true; verbindungSeit = optText(v, "seit"); verbindungText = text(v, "text")
        let t = objekt(j, "traeger")
        traegerEingerichtet = t["eingerichtet"] as? Bool ?? false; traegerLaeuft = t["laeuft"] as? Bool
        traegerMoeglich = t["moeglich"] as? Bool ?? false
        zugaenge = Werkbank.liste(j, "zugaenge").compactMap { z in text(z, "name").isEmpty ? nil : "\(text(z, "name")) (\(text(z, "art").isEmpty ? "ssh" : text(z, "art")))" }
        traegerZugFehler = text(t, "zug_fehler")
        modelle = (j["modelle"] as? [[String: Any]]).map { liste in
            liste.map { WeltModell(id: Werkbank.text($0, "id"), harness: Werkbank.text($0, "harness"), grund: Werkbank.text($0, "grund"),
                                   verfuegbar: $0["verfuegbar"] as? Bool ?? false) }
                .filter { !$0.id.isEmpty && !$0.id.lowercased().contains("fable") }
        }
        maschineVorgabe = text(j, "maschine_vorgabe")
        let k = objekt(j, "skill_katalog")
        skillKatalog = ["welt", "bibliothek"].flatMap { ebene in
            Werkbank.liste(k, ebene).map { WeltSkillAuswahl(name: Werkbank.text($0, "name"), beschreibung: Werkbank.text($0, "beschreibung"), ebene: ebene) }
        }.filter { !$0.name.isEmpty }
        webZugang = j["web_zugang"] as? Bool ?? false
        rechteAenderbar = j["rechte_aenderbar"] as? Bool ?? false
    }

    /// Die Maschine eines neuen Agenten: die Traegermaschine, sonst die Maschine der Ablage.
    var agentMaschine: String { maschineVorgabe.isEmpty ? maschine : maschineVorgabe }

    /// Der Befehl, mit dem der Mensch der Welt einen Zugang der Art web gibt.
    var webZugangBefehl: String { "wb-welt zugang \(ablage.isEmpty ? pfad : ablage) hinzufuegen --art web --name netz --bestaetigt" }

    func agent(_ id: String?) -> WeltAgent? { id.flatMap { i in agenten.first { $0.id == i } } }
    func ticket(_ id: String?) -> WeltTicket? { id.flatMap { i in tickets.first { $0.id == i } } }
    func frage(_ id: String?) -> WeltFrage? { id.flatMap { i in fragen.first { $0.id == i } } }
    var offeneFragen: [WeltFrage] { fragen.filter(\.offen) }
    /// Ein Name statt einer Kennung, wo es einen gibt: Agent, Team oder Mensch.
    func anzeigename(_ id: String) -> String {
        if id == "alle" { return "alle" }
        if let a = agent(id) { return a.name }
        switch id {
        case "mensch", "person-1": return "Du"
        case "cli-operator": return "Steuerkanal"
        case "companion": return "Companion"
        case "orchestrator": return "Orchestrator"
        default: return id
        }
    }
}

/// Eine Maschine fuer Anlegen, Umzug und Fusszeile (`WeltMaschine` in app/src/main/welten.ts).
struct WeltMaschine: Equatable, Identifiable, Sendable {
    let name, ssh, text: String
    let eigene, standard, traeger: Bool
    /// nil: noch nie gefragt (nur Fernmaschinen).
    let erreichbar: Bool?
    let seit: String?
    let welten, traegerEingerichtet: Int
    var id: String { name }

    init(_ j: [String: Any]) {
        name = Werkbank.text(j, "name"); ssh = Werkbank.text(j, "ssh"); text = Werkbank.text(j, "text")
        eigene = j["eigene"] as? Bool ?? false; standard = j["standard"] as? Bool ?? false; traeger = j["traeger"] as? Bool ?? false
        erreichbar = j["erreichbar"] as? Bool; seit = optText(j, "seit")
        welten = ganz(j, "welten"); traegerEingerichtet = ganz(j, "traeger_eingerichtet")
    }
}

struct WeltenNutzlast: Equatable, Sendable {
    let geladen: Bool
    let fehler: [(quelle: String, text: String)]
    let welten: [Welt]
    let datenbibliothek: String
    /// Auftrag Nr. 3: Vorlagen und Modelle fuer das Anlege-Menue, Modelle fuer Vorschlaege.
    var vorlagen: [WeltVorlage] = []
    var modelle: [ModellZeile] = []
    var entwurfModelle: [String] = []
    /// Auftrag agentsux Nr. 1: wo die globale Welt liegt oder angelegt wird (`AWB_WELTEN_GLOBAL` des Kerns).
    var globalPfad = ""
    /// Auftrag fernwelten: die eigene Maschine zuerst, dann die Agent-Maschinen; die Vorgabe beim Anlegen.
    var maschinen: [WeltMaschine] = []
    var maschineVorgabe = ""
    /// Auftrag agentsform: die gemerkten Projektordner (`welten-projekte.json`) und die Bash-Muster des Dienstwegs je Stufe.
    var gemerkteProjekte: [String] = []
    var bashVorgabe: [String: [String]] = [:]

    var eigeneMaschine: WeltMaschine? { maschinen.first { $0.eigene } }
    /// Maschinen, auf die eine Welt ziehen oder auf denen sie entstehen kann: fern und mit Traeger.
    var agentMaschinen: [WeltMaschine] { maschinen.filter { !$0.eigene && $0.traeger } }

    /// Ob es die globale Welt schon gibt -- dann bietet das Menue sie nicht noch einmal zum Anlegen an.
    var globalDa: Bool { welten.contains { $0.art == "global" } }

    static func == (a: WeltenNutzlast, b: WeltenNutzlast) -> Bool {
        a.geladen == b.geladen && a.welten == b.welten && a.datenbibliothek == b.datenbibliothek && a.globalPfad == b.globalPfad
            && a.vorlagen == b.vorlagen && a.modelle == b.modelle && a.entwurfModelle == b.entwurfModelle
            && a.maschinen == b.maschinen && a.maschineVorgabe == b.maschineVorgabe
            && a.gemerkteProjekte == b.gemerkteProjekte && a.bashVorgabe == b.bashVorgabe
            && a.fehler.map { "\($0.quelle)\u{1f}\($0.text)" } == b.fehler.map { "\($0.quelle)\u{1f}\($0.text)" }
    }

    /// Aus der ganzen Zeile `awb:aufgaben`; nil, wenn der Kern (noch) keine Welten schickt.
    static func lesen(_ daten: Data) -> WeltenNutzlast? {
        guard let j = try? JSONSerialization.jsonObject(with: daten) as? [String: Any],
              let w = j["welten"] as? [String: Any] else { return nil }
        return WeltenNutzlast(
            geladen: w["geladen"] as? Bool ?? false,
            fehler: liste(w, "fehler").map { (text($0, "quelle"), text($0, "text")) },
            welten: liste(w, "welten").map(Welt.init),
            datenbibliothek: text(w, "datenbibliothek"),
            vorlagen: liste(w, "vorlagen").map { WeltVorlage(name: text($0, "name"), titel: text($0, "title"), zusammenfassung: text($0, "summary"), entwurf: AgentEntwurf(objekt($0, "draft"))) },
            modelle: liste(w, "modelle").map { ModellZeile(kennung: text($0, "kennung"), harness: text($0, "harness"), aufgabe: text($0, "aufgabe")) },
            entwurfModelle: texte(w, "entwurf_modelle"),
            globalPfad: text(w, "global_pfad"),
            maschinen: liste(w, "maschinen").map(WeltMaschine.init),
            maschineVorgabe: text(w, "maschine_vorgabe"),
            gemerkteProjekte: texte(w, "gemerkte_projekte"),
            bashVorgabe: objekt(w, "bash_vorgabe").reduce(into: [:]) { r, e in if let v = e.value as? [String] { r[e.key] = v } })
    }

    /// Die Dienstwegmuster einer Stufe; ohne Angabe die eines Mitglieds, ohne beide keine.
    func dienstweg(_ stufe: String) -> [String] { bashVorgabe[stufe] ?? bashVorgabe["mitglied"] ?? [] }

    /// Die Modelle fuer Modell und Fallback: die der Welt (nicht verfuegbare mit Grund), sonst die Registry; eigene Werte bleiben waehlbar.
    static func modellOptionen(_ w: Welt, registry modelle: [ModellZeile], eigene: [String]) -> [(wert: String, titel: String, verfuegbar: Bool)] {
        var gesehen = Set<String>()
        var raus: [(wert: String, titel: String, verfuegbar: Bool)] = []
        if let ms = w.modelle {
            // Die Kennung der Welt woertlich: der Traeger sucht genau diesen Namen.
            for m in ms where gesehen.insert(m.id).inserted {
                raus.append((m.id, m.verfuegbar ? "\(m.id) · \(m.harness)" : "\(m.id) · nicht verfügbar: \(WeltenWorte.modellGrund(m.grund))", m.verfuegbar))
            }
        } else {
            for m in modelle {
                let b = AgentEntwurf.teilen(m.kennung, "").0
                if gesehen.insert(b).inserted { raus.append((b, "\(b) · \(m.harness)", true)) }
            }
        }
        for e in eigene where !e.isEmpty && gesehen.insert(e).inserted { raus.append((e, e, true)) }
        return raus
    }
}

// MARK: Worte und Punkte

enum WeltenWorte {
    /// Der Untertitel unter dem Namen der Welt: die globale Welt oder ihr Projekt, dazu ihre Maschine („~/AI/myproject · peer").
    static func herkunft(_ w: Welt) -> String {
        let ort = w.art == "global" ? "Globale Welt" : (w.projekt.map { w.fern ? kurzpfad($0) : kurzerPfad($0) } ?? "")
        return [ort, maschine(w.maschine)].filter { !$0.isEmpty }.joined(separator: " · ")
    }

    /// Ein Pfad auf einer anderen Maschine: ihr Home heisst dort anders, `/home/<name>/…` und `/Users/<name>/…` werden `~/…`.
    static func kurzpfad(_ p: String) -> String {
        let teile = p.split(separator: "/", omittingEmptySubsequences: true)
        guard teile.count >= 2, teile[0] == "home" || teile[0] == "Users" else { return p }
        return (["~"] + teile.dropFirst(2).map(String.init)).joined(separator: "/")
    }

    /// Wie die Maschine einer Welt im Satz heisst: „auf dem Mac", „auf peer".
    static func aufMaschine(_ m: String, satzanfang: Bool = false) -> String {
        m == "mac" ? (satzanfang ? "Auf dem Mac" : "auf dem Mac") : (satzanfang ? "Auf \(m)" : "auf \(m)")
    }

    /// WAS AN DER WELT FEHLT, damit ihre Agenten antworten (Auftrag fernwelten): eine Maschine, die nicht
    /// antwortet, eine Maschine ohne Traeger, eine Welt ohne eingerichteten Traeger. nil, wenn nichts fehlt.
    static func maschinenHinweis(_ w: Welt) -> String? {
        guard !w.maschine.isEmpty else { return nil }
        let m = maschine(w.maschine)
        if !w.verbindungOk {
            let seit = w.verbindungSeit.map { " seit \(AgentsWorte.uhrzeit($0))" } ?? ""
            return "\(m) nicht erreichbar\(seit). Zu sehen ist der letzte Stand; Handlungen gehen wieder, sobald \(m) antwortet."
        }
        if !w.traegerMoeglich { return "\(aufMaschine(w.maschine, satzanfang: true)) läuft kein Träger, Agenten antworten hier nicht." }
        if !w.traegerEingerichtet { return "\(aufMaschine(w.maschine, satzanfang: true)) ist für diese Welt kein Träger eingerichtet; Agenten antworten erst, wenn er eingerichtet ist." }
        return nil
    }

    /// Der Traeger der Welt in einem Wort fuer den Inspektor.
    static func traeger(_ w: Welt) -> String {
        guard w.traegerEingerichtet else { return w.traegerMoeglich ? "nicht eingerichtet" : "\(aufMaschine(w.maschine)) nicht möglich" }
        switch w.traegerLaeuft {
        case true?: return "eingerichtet, läuft"
        case false?: return "eingerichtet, schläft"
        case nil: return "eingerichtet"
        }
    }

    /// Die Agent-Maschinen in der Fusszeile, sobald der Kern sie gefragt hat: erreichbar mit Traegern oder nicht erreichbar seit.
    static func maschinenFuss(_ ms: [WeltMaschine]) -> [(art: Punktart?, text: String)] {
        ms.compactMap { m in
            guard !m.eigene, let erreichbar = m.erreichbar else { return nil }
            let name = maschine(m.name)
            guard erreichbar else { return (.will, "\(name) nicht erreichbar\(m.seit.map { " seit \(AgentsWorte.uhrzeit($0))" } ?? "")") }
            return (.laeuft, "\(name) erreichbar, \(m.traegerEingerichtet == 1 ? "1 Träger" : "\(m.traegerEingerichtet) Träger")")
        }
    }

    // --- Das Lebenszeichen (Auftrag agentaktiv) ------------------------------------------

    /// Nach so vielen Sekunden ohne Zugbeginn heisst eine zugestellte Nachricht „nicht gestartet".
    static let nichtGestartetNach: TimeInterval = 30

    /// m:ss, ab einer Stunde h:mm:ss, seit einer ISO-Zeit.
    static func dauer(seit iso: String?, jetzt: Date = Date()) -> String {
        guard let iso, let d = datum(iso) else { return "" }
        let s = max(0, Int(jetzt.timeIntervalSince(d)))
        let h = s / 3600, m = (s % 3600) / 60, sek = s % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, sek) : String(format: "%d:%02d", m, sek)
    }

    /// Das Wort neben dem Avatar, wenn der Traeger etwas zu sagen hat; nil heisst: es gilt das Zustandswort.
    /// Dieselbe Regel wie `lebenWort` in welten-view.ts.
    static func leben(_ a: WeltAgent, jetzt: Date = Date()) -> String? {
        guard let l = a.leben else { return nil }
        if l.stand == "arbeitet" { return l.seit.map { "arbeitet seit \(dauer(seit: $0, jetzt: jetzt))" } ?? "arbeitet" }
        if ["braucht_dich", "pausiert", "gestoppt", "archiviert"].contains(a.zustand) { return nil }
        switch l.stand {
        case "wartet": return "wartet auf den Träger"
        case "nicht_erreichbar": return "Träger nicht erreichbar"
        default: return nil
        }
    }

    /// Der Punkt zum Wort: steht das Lebenszeichen da, zeigt auch der Punkt es (arbeitet gefuellt, wartet hohl, weg aus).
    static func punkt(agent a: WeltAgent) -> Punktart {
        guard leben(a) != nil else { return punkt(zustand: a.zustand) }
        switch a.leben?.stand {
        case "arbeitet": return .laeuft
        case "wartet": return .ruhig
        default: return .aus
        }
    }

    /// Das Wort neben dem Punkt: das Lebenszeichen, sonst das Zustandswort.
    static func agentWort(_ a: WeltAgent, jetzt: Date = Date()) -> String { leben(a, jetzt: jetzt) ?? zustand(a.zustand) }

    /// Die Gruende des Traegers als Wort (`zug_stand` in shell/agents_traeger.py); ein unbekannter bleibt roh.
    static func grund(_ g: String?) -> String {
        switch g ?? "" {
        case "kontingent": "Kontingent erschöpft"
        case "anmeldung": "Anmeldung fehlt"
        case "recovery_limit": "Wiederholungsgrenze erreicht"
        case "pausiert": "pausiert"
        case "gestoppt": "gestoppt"
        case "ungeklaert": "ungeklärter Lauf"
        case "traeger_aus": "Träger läuft nicht"
        case "startfehler": "Startfehler"
        case "chain_limit": "Kettengrenze erreicht"
        case "cycle": "Weckkreis erkannt"
        case "nicht_erreichbar": "nicht erreichbar"
        default: g ?? ""
        }
    }

    static func zugArt(_ art: String?) -> String {
        switch art ?? "" {
        case "nachricht": "Nachricht"
        case "ticket": "Ticket"
        case "frage": "Antwort auf eine Frage"
        case "recovery": "Wiederaufnahme"
        default: art ?? ""
        }
    }

    /// Der Stand unter der eigenen Nachricht als (Wort, Art); nil, wenn keiner gilt. Wie `antwortText` in welten-view.ts.
    static func antwort(_ a: WeltAgent, jetzt: Date = Date()) -> (text: String, art: String)? {
        guard let st = a.antwort else { return nil }
        switch st.stand {
        case "arbeitet": return ("\(a.name) arbeitet …", "arbeitet")
        case "beendet": return ("Zug endete ohne Antwort: \(grund(st.grund))", "beendet")
        case "nicht_erreichbar": return ("zugestellt · Träger nicht erreichbar", "weg")
        default: break
        }
        if let d = datum(st.zeit), jetzt.timeIntervalSince(d) >= nichtGestartetNach {
            return (st.grund.map { "Träger hat den Zug nicht gestartet: \(grund($0))" } ?? "Träger hat den Zug nicht gestartet", "nicht_gestartet")
        }
        switch st.wecken {
        case "gestartet": return ("zugestellt · Träger geweckt", "zugestellt")
        case "laeuft": return ("zugestellt · Träger lief schon", "zugestellt")
        case "fehler": return ("zugestellt · Träger nicht geweckt", "zugestellt")
        default: return ("zugestellt", "zugestellt")
        }
    }

    /// Das Wort neben dem Punkt -- nie Farbe allein.
    static func zustand(_ z: String) -> String {
        switch z {
        case "braucht_dich": "braucht dich"
        case "arbeitet": "arbeitet"
        case "hat_ergebnis": "hat Ergebnis"
        case "wartet": "wartet"
        case "schlaeft": "schläft"
        case "pausiert": "pausiert"
        case "gestoppt": "gestoppt"
        case "archiviert": "archiviert"
        default: z
        }
    }

    static func punkt(zustand z: String) -> Punktart {
        switch z {
        case "braucht_dich": .will
        case "arbeitet": .laeuft
        case "hat_ergebnis": .fertig
        case "pausiert": .pausiert
        case "gestoppt", "archiviert": .aus
        default: .ruhig
        }
    }

    static func punkt(ticket stand: String) -> Punktart {
        switch stand {
        case "läuft": .laeuft
        case "braucht dich": .will
        case "zur Abnahme", "in Prüfung": .fertig
        case "zurückgegeben", "unterbrochen", "verworfen": .aus
        case "wartet": .pausiert
        default: .ruhig
        }
    }

    static func stufe(_ s: String) -> String {
        switch s {
        case "hauptagent": "Hauptagent"
        case "teamleiter": "Teamleiter"
        case "mitglied": "Mitglied"
        default: s
        }
    }

    /// Teamnamen stehen klein in den Daten; die Ansicht schreibt sie gross.
    static func team(_ t: String) -> String { t.prefix(1).uppercased() + t.dropFirst() }

    static func maschine(_ m: String) -> String { m == "mac" ? "Mac" : m }

    /// Auftrag agentsform: warum ein Modell der Welt nicht verfuegbar ist (agents_modellwahl.py), in Worten; unbekannt bleibt roh.
    static func modellGrund(_ g: String) -> String {
        switch g {
        case "": return "ohne Grund"
        case "nicht_in_registry": return "nicht in der Registry"
        case "in_registry_abgeschaltet": return "in der Registry abgeschaltet"
        case "nicht_fuer_diese_maschine": return "nicht für diese Maschine"
        case "codex_nur_trockenlauf": return "Codex nur als Trockenlauf"
        default: return g
        }
    }

    static let ticketStaende = ["triage", "offen", "läuft", "wartet", "braucht dich", "zur Abnahme", "in Prüfung", "abgenommen", "zurückgegeben", "unterbrochen", "verworfen"]

    // --- tickets4: die Worte des Ticketsystems (Plan Saetze 3, 5, 31, 40, 43, 47, 50) ---------

    /// Die Spalten des Boards in Bearbeitungsrichtung (AGIL Abschnitt 5); `zurückgegeben` liegt
    /// in `offen` und steht dort als Abzeichen, `verworfen` und `unterbrochen` stehen nicht im Board.
    static let boardSpalten = ["triage", "offen", "läuft", "wartet", "braucht dich", "zur Abnahme", "in Prüfung", "abgenommen"]

    /// Welche Stände eine Board-Spalte fasst.
    static func boardStaende(_ spalte: String) -> [String] {
        spalte == "offen" ? ["offen", "zurückgegeben"] : [spalte]
    }

    /// Die Ticketarten im Formular, mit Erklärung je Art (Satz 3 und AGIL Abschnitt 2).
    static let ticketArten = ["vorhaben", "story", "task", "subtask", "auftrag", "fehler", "recherche", "pruefung"]

    static func kind(_ k: String) -> String {
        switch k {
        case "vorhaben": "Vorhaben"
        case "story": "Story"
        case "task": "Task"
        case "subtask": "Subtask"
        case "auftrag": "Auftrag"
        case "fehler": "Fehler"
        case "recherche": "Recherche"
        case "pruefung": "Prüfung"
        case "skill-vorschlag": "Skill-Vorschlag"
        default: k
        }
    }

    static func kindErklaerung(_ k: String) -> String {
        switch k {
        case "vorhaben": "Das Ganze: Ziel, Nutzen und Fertig-Kriterium. Wird in Stories zerlegt."
        case "story": "Ein Stück Nutzen, das für sich abnehmbar ist. Wird erst zerlegt, wenn sie läuft."
        case "task": "Ein Arbeitsschritt einer Story, in einem oder wenigen Zügen zu schaffen."
        case "subtask": "Der kleinste Schritt unter einem Task; hat selbst keine Kinder."
        case "auftrag": "Ein Auftrag ohne Hierarchie -- die Vorgabe, wenn nichts anderes passt."
        case "fehler": "Etwas geht nicht. Das Fertig-Kriterium nennt, woran man es misst."
        case "recherche": "Etwas herausfinden; das Ergebnis ist die Antwort, nicht der Code."
        case "pruefung": "Ein zweiter Blick mit frischem Kontext, ohne Schreibwerkzeuge."
        case "skill-vorschlag": "Ein Skill, den ein Agent vorschlägt; die Abnahme entscheidet."
        default: ""
        }
    }

    /// Die vier Stufen mit Bedeutungstext (Satz 5). Der Kern schickt den Text mit; fehlt er, gilt dieser.
    static func prioritaet(_ p: Int) -> String {
        switch p {
        case 0: "P0 sofort"
        case 1: "P1 hoch"
        case 3: "P3 später"
        default: "P2 normal"
        }
    }

    static func prioritaetText(_ p: Int) -> String {
        switch p {
        case 0: "sofort: der Betrieb steht oder Daten sind in Gefahr"
        case 1: "hoch"
        case 3: "später"
        default: "normal (Vorgabe)"
        }
    }

    /// Ob die Stufe in der Liste hervorgehoben steht (0 und 1, Auftrag tickets4 A).
    static func prioritaetHervor(_ p: Int) -> Bool { p <= 1 }

    /// Die Frist-Ampel (Satz 31): grau, gelb ab einem Tag vorher, rot ab Ablauf.
    static func ampel(_ a: String) -> String {
        switch a {
        case "rot": "Frist abgelaufen"
        case "gelb": "Frist heute"
        case "grau": "Frist gesetzt"
        default: ""
        }
    }

    static func ampelPunkt(_ a: String) -> Punktart {
        switch a {
        case "rot": .will
        case "gelb": .fertig
        default: .ruhig
        }
    }

    /// Die Grundcodes des Verwerfens (Satz 40).
    static let verwerfGruende = ["duplikat", "anderswo-erledigt", "nicht-mehr-noetig", "nicht-reproduzierbar", "abgelehnt"]

    static func verwerfGrund(_ g: String) -> String {
        switch g {
        case "duplikat": "Duplikat"
        case "anderswo-erledigt": "anderswo erledigt"
        case "nicht-mehr-noetig": "nicht mehr nötig"
        case "nicht-reproduzierbar": "nicht reproduzierbar"
        case "abgelehnt": "abgelehnt"
        default: g
        }
    }

    static func abnahmeGrund(_ g: String) -> String {
        switch g {
        case "erledigt": "erledigt"
        case "teilweise": "teilweise (Rest als neues Ticket)"
        default: g
        }
    }

    static func urteil(_ u: String) -> String {
        switch u {
        case "bestanden": "bestanden"
        case "maengel": "Mängel"
        default: u
        }
    }

    /// Eine Dauer in Sekunden als Wort für die Messung (Satz 50).
    static func dauerWort(_ s: Int) -> String {
        if s < 60 { return "\(s) s" }
        if s < 3600 { return "\(s / 60) min" }
        if s < 86_400 { return "\(s / 3600) h" }
        let tage = s / 86_400
        return tage == 1 ? "1 Tag" : "\(tage) Tage"
    }

    /// Die getrennten Weltzähler in der Symbolleiste (Satz 35).
    static func zaehlerGetrennt(_ w: Welt) -> String {
        ["\(w.brauchenDich) \(w.brauchenDich == 1 ? "braucht" : "brauchen") dich",
         "\(w.triage) Triage",
         "\(w.laufen) \(w.laufen == 1 ? "läuft" : "laufen")",
         "\(w.ticketsOffen) offen"].joined(separator: " · ")
    }

    /// DIE DEFINITION OF READY ALS VORSCHAU (Satz 45, Auftrag tickets4 C). Dieselbe Reihenfolge
    /// wie `_definition_of_ready_grund` in shell/agents_data.py; sie warnt, sie blockt nicht.
    /// nil heisst: das Ticket wird zugestellt.
    static func bereitschaft(kind: String, punkte: Int, frist: String, runden: String,
                             adressaten: Bool, titel: String, ziel: String, fertig: String) -> String? {
        let leer = { (s: String) in s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        if leer(titel) || leer(ziel) || leer(fertig) { return "Titel, Ziel oder Fertig-Kriterium fehlt" }
        if kind == "vorhaben" { return nil }
        if ["story", "task", "subtask"].contains(kind), punkte == 0 { return "die Fertig-Liste fehlt" }
        if leer(frist), leer(runden) { return "die Grenzen fehlen (keine Frist, keine Rundenzahl)" }
        if !adressaten { return "der Adressat fehlt -- das Ticket bleibt in der Triage" }
        return nil
    }

    static func profilfeld(_ f: String) -> String {
        switch f {
        case "model": "Modell"
        case "effort": "Denkstufe"
        case "fallback_model": "Fallback"
        case "fallback_effort": "Fallback-Denkstufe"
        case "machine": "Maschine"
        case "specialty": "Spezialgebiet"
        default: f
        }
    }

    static let denkstufen = ["low", "medium", "high", "xhigh"]

    static func ereignis(_ e: String) -> String {
        switch e {
        case "erstellt": "angelegt"
        case "uebernommen": "übernommen"
        case "ergebnis": "Ergebnis geschrieben"
        case "abgenommen": "abgenommen"
        case "zurueckgegeben": "zurückgegeben"
        case "unterbrochen": "unterbrochen"
        case "fortgesetzt": "fortgesetzt"
        case "profil": "Profil geändert"
        case "gedaechtnis": "Gedächtnis bearbeitet"
        // tickets1 bis tickets3: die neuen Übergänge und Vermerke im Ticketverlauf
        case "geparkt": "geparkt"
        case "geweckt": "geweckt"
        case "braucht-dich": "braucht dich"
        case "beantwortet": "Frage beantwortet"
        case "verworfen": "verworfen"
        case "umadressiert": "umadressiert"
        case "zwischenstand": "Zwischenstand"
        case "fertig-gehaekt": "Fertig-Punkt abgehakt"
        case "fertig-zurueck": "Fertig-Punkt zurückgenommen"
        case "pruefung-angefordert": "Prüfung angefordert"
        case "pruefnotiz": "Prüfnotiz"
        case "frei": "frei geworden"
        case "duplikat-gemeldet": "Duplikat gemeldet"
        case "abhaengigkeit-verworfen": "Abhängigkeit verworfen"
        case "kinder-fertig": "alle Kinder abgenommen"
        case "folgeticket": "Folgeticket entdeckt"
        case "geordnet": "Backlog geordnet"
        case "uebertragen": "in den nächsten Zyklus übertragen"
        case "grenzen-geaendert": "Grenzen geändert"
        case "angenommen": "aus der Triage angenommen"
        case "zug": "Zug"
        default: e
        }
    }

    /// Wie lange her, in Worten: „gerade", „vor 5 min", „vor 3 h", sonst das Datum.
    static func alter(_ iso: String, jetzt: Date = Date()) -> String {
        guard let d = datum(iso) else { return "" }
        let s = jetzt.timeIntervalSince(d)
        if s < 60 { return "gerade" }
        if s < 3600 { return "vor \(Int(s / 60)) min" }
        if s < 86_400 { return "vor \(Int(s / 3600)) h" }
        return AgentsWorte.uhrzeit(iso)
    }

    static func datum(_ iso: String) -> Date? {
        let f = ISO8601DateFormatter()
        if let d = f.date(from: iso) { return d }
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.date(from: iso)
    }

}

// MARK: Ungelesen

/// WAS DER MENSCH SCHON GESEHEN HAT. Seit Auftrag Nr. 2 fuehrt die Welt den
/// Lesestand selbst (`menschen/mensch/gelesen.json`, `wb-welt gelesen`), damit
/// Mac und Electron dieselben Zahlen zeigen. Diese Marken hier sind nur der
/// Stand, den diese Oberflaeche gerade gesetzt hat, bis der Kern ihn
/// zurueckmeldet: es gilt die juengere der beiden Marken, damit eine gerade
/// gelesene Zahl nicht fuer einen Takt zurueckspringt.
struct WeltenGelesen: Equatable, Sendable {
    var marken: [String: String] = [:]

    static func schluessel(welt: String, gespraech: String) -> String { "\(welt)|\(gespraech)" }

    private static func marke(_ zeit: String, _ id: String) -> String { "\(zeit)\u{1f}\(id)" }

    func ungelesen(_ nachrichten: [WeltNachricht], welt: String, gespraech: String) -> Int {
        Self.zaehlen(nachrichten, marke: marke(welt: welt, gespraech: gespraech))
    }

    /// Die gemerkte Marke dieser Oberflaeche fuer ein Gespraech.
    func marke(welt: String, gespraech: String) -> WeltMarke? {
        marken[Self.schluessel(welt: welt, gespraech: gespraech)].map { let (z, i) = Self.teile($0); return WeltMarke(zeit: z, id: i) }
    }

    /// Ungelesen nach einer Marke: was nicht von einem Menschen kommt und danach liegt (Zeit, dann Kennung).
    static func zaehlen(_ nachrichten: [WeltNachricht], marke: WeltMarke?) -> Int {
        guard let m = marke else { return nachrichten.filter { !$0.vonMensch }.count }
        return nachrichten.filter { !$0.vonMensch && ($0.zeit > m.zeit || ($0.zeit == m.zeit && $0.id > m.id)) }.count
    }

    mutating func gesehen(_ nachrichten: [WeltNachricht], welt: String, gespraech: String) -> Bool {
        guard let letzte = nachrichten.max(by: { ($0.zeit, $0.id) < ($1.zeit, $1.id) }) else { return false }
        let k = Self.schluessel(welt: welt, gespraech: gespraech)
        let neu = Self.marke(letzte.zeit, letzte.id)
        if let alt = marken[k], alt >= neu { return false }
        marken[k] = neu
        return true
    }

    private static func teile(_ m: String) -> (String, String) {
        let t = m.split(separator: "\u{1f}", maxSplits: 1, omittingEmptySubsequences: false).map(String.init)
        return (t.first ?? "", t.count > 1 ? t[1] : "")
    }

    /// Eine Zeile je Gespraech: `<welt>|<gespraech>\t<zeit>\u{1f}<id>`.
    var text: String { marken.sorted { $0.key < $1.key }.map { "\($0.key)\t\($0.value)" }.joined(separator: "\n") }

    init(text: String = "") {
        for zeile in text.split(separator: "\n") {
            let t = zeile.split(separator: "\t", maxSplits: 1).map(String.init)
            if t.count == 2 { marken[t[0]] = t[1] }
        }
    }
}

// MARK: Adressen im Kanal

enum WeltenAdressen {
    /// Das Adressfeld: `@name`, `@team` (oder `@team:name`), `@alle`, getrennt durch
    /// Leerzeichen oder Komma. Heraus kommen die Adressen des Kerns (`team:<name>`).
    static func lesen(_ feld: String, welt: Welt) -> (adressen: [String], fehler: String?) {
        let teile = feld.split(whereSeparator: { $0 == " " || $0 == "," || $0 == "\n" }).map { String($0).trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        var raus: [String] = []
        for roh in teile {
            let a = roh.hasPrefix("@") ? String(roh.dropFirst()) : roh
            if a.isEmpty { continue }
            let klein = a.lowercased()
            if klein == "alle" {
                raus.append("alle")
            } else if klein.hasPrefix("team:"), welt.teams.contains(where: { $0.name == String(a.dropFirst(5)) }) {
                raus.append(a)
            } else if let agent = welt.agenten.first(where: { $0.id == a || $0.name.lowercased() == klein }) {
                raus.append(agent.id)
            } else if let team = welt.teams.first(where: { $0.name.lowercased() == klein }) {
                raus.append("team:\(team.name)")
            } else {
                return ([], "„\(roh)“ ist weder Agent noch Team in \(welt.name).")
            }
        }
        var eindeutig: [String] = []
        for a in raus where !eindeutig.contains(a) { eindeutig.append(a) }
        if eindeutig.isEmpty { return ([], "Die Nachricht braucht einen Adressaten.") }
        if eindeutig.contains("alle"), eindeutig.count > 1 { return ([], "„@alle“ lässt sich nicht mit anderen Adressen mischen.") }
        return (eindeutig, nil)
    }

    /// Die Vorgabe des Adressfelds: der Hauptagent (Plan Abschnitt 6).
    static func vorgabe(_ welt: Welt) -> String { welt.hauptagent.map { "@\($0)" } ?? "" }

    /// Die Auswahl im Menue neben dem Feld: Hauptagent, Teams, Agenten, alle.
    static func auswahl(_ welt: Welt) -> [(titel: String, adresse: String)] {
        var raus: [(String, String)] = []
        if let h = welt.agent(welt.hauptagent) { raus.append(("\(h.name) (Hauptagent)", "@\(h.id)")) }
        for t in welt.teams { raus.append(("Team \(WeltenWorte.team(t.name))", "@team:\(t.name)")) }
        for id in welt.liste where id != welt.hauptagent { if let a = welt.agent(id) { raus.append((a.name, "@\(a.id)")) } }
        raus.append(("Alle", "@alle"))
        return raus
    }
}
