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
    static let werkzeuge = ["Read", "Grep", "Glob", "Bash", "Write", "Edit"]

    func anlegenOeffnen(_ n: WeltenNutzlast, _ w: Welt, vorlage: String? = nil) {
        var a = AnlegenEntwurf()
        a.vorlagen = n.vorlagen
        a.modelle = n.modelle
        a.entwurfModelle = n.entwurfModelle.isEmpty ? ["sonnet5:high"] : n.entwurfModelle
        a.vorschlagModell = a.entwurfModelle[0]
        a.entwurf.team = w.teams.first?.name ?? ""
        a.neuesTeam = w.teams.isEmpty
        if w.hauptagent == nil { a.entwurf.stufe = "hauptagent"; a.entwurf.team = "" }
        // Auftrag fernwelten: ein Agent laeuft, wo seine Welt liegt; die Maschine der Welt ist die Vorgabe.
        if !w.maschine.isEmpty { a.entwurf.maschine = w.maschine }
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
        if !w.maschine.isEmpty { e.maschine = w.maschine }
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

    func werkzeugSetzen(_ name: String, _ an: Bool) {
        guard var a = anlegen else { return }
        if an, !a.entwurf.werkzeuge.contains(name) { a.entwurf.werkzeuge.append(name) }
        if !an { a.entwurf.werkzeuge.removeAll { $0 == name } }
        a.gesetzt.insert("werkzeuge")
        anlegen = a
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
            neu.entwurf = AgentEntwurf(e)
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
            neu.entwurf = AgentEntwurf(e)
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
    func anlegenAuskunft() -> [String: Any] {
        guard let a = anlegen else { return [:] }
        return ["entwurf": a.entwurf.json(), "beschreibung": a.beschreibung, "vorschlagModell": a.vorschlagModell, "neuesTeam": a.neuesTeam,
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
                    modell
                    werkzeuge
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

    private var modellBasen: [(String, String)] {
        var gesehen = Set<String>()
        var raus: [(String, String)] = []
        for m in a.modelle {
            let basis = AgentEntwurf.teilen(m.kennung, "").0
            if gesehen.insert(basis).inserted { raus.append((basis, "\(basis) · \(m.harness)")) }
        }
        for eigen in [a.entwurf.modell, a.entwurf.fallback] where !eigen.isEmpty && gesehen.insert(eigen).inserted { raus.append((eigen, eigen)) }
        return raus
    }

    private var modell: some View {
        Section {
            Picker("Modell", selection: feld("modell", \.modell)) {
                ForEach(modellBasen, id: \.0) { Text($0.1).tag($0.0) }
            }
            Picker("Denkstufe", selection: feld("denkstufe", \.denkstufe)) {
                ForEach(WeltenWorte.denkstufen, id: \.self) { Text($0).tag($0) }
            }
            Picker("Fallback", selection: feld("fallback", \.fallback)) {
                Text("keiner").tag("")
                ForEach(modellBasen, id: \.0) { Text($0.1).tag($0.0) }
            }
            if !a.entwurf.fallback.isEmpty {
                Picker("Fallback-Denkstufe", selection: feld("fallback-denkstufe", \.fallbackDenkstufe)) {
                    ForEach(WeltenWorte.denkstufen, id: \.self) { Text($0).tag($0) }
                }
            }
            TextField("Maschine", text: feld("maschine", \.maschine), prompt: Text("peer"))
        } header: {
            Text("Modell und Maschine")
        } footer: {
            Text("Aus wb-state models table, Fable nie. Lokal, wo es reicht; der Mac nur, wenn die Arbeit dort sein muss.").font(.caption).foregroundStyle(.secondary)
        }
    }

    private var werkzeuge: some View {
        Section {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 90), alignment: .leading)], alignment: .leading, spacing: 6) {
                ForEach(WeltenZustand.werkzeuge, id: \.self) { w in
                    Toggle(w, isOn: Binding(get: { a.entwurf.werkzeuge.contains(w) }, set: { zustand.werkzeugSetzen(w, $0) }))
                        .toggleStyle(.checkbox)
                }
            }
            if a.entwurf.werkzeuge.contains("Bash") {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Bash-Muster, eins je Zeile").font(.callout)
                    TextEditor(text: feld("bash", \.bash))
                        .font(.callout.monospaced())
                        .frame(minHeight: 54)
                        .scrollContentBackground(.hidden)
                        .background(RoundedRectangle(cornerRadius: 6).fill(Color(nsColor: .controlBackgroundColor)))
                }
            }
            TextField("Skills, durch Komma getrennt", text: feld("skills", \.skills))
            mehrzeilig("Kontextgrenze", "Was der Agent nicht erfährt", feld("kontextgrenze", \.kontextgrenze), kennung: "welten-anlegen-kontextgrenze")
        } header: {
            Text("Werkzeuge und Grenzen")
        } footer: {
            Text("Gesperrt bleiben, was die Hausliste sperrt: Push, rm -rf, kill, Mail-Versand, Erlaubnisstufen.").font(.caption).foregroundStyle(.secondary)
        }
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
                    VStack(alignment: .leading, spacing: 6) {
                        zeile("Spezialgebiet", e.spezialgebiet)
                        zeile("Werkzeuge", e.werkzeuge.joined(separator: ", "))
                        if e.werkzeuge.contains("Bash") { zeile("Bash", e.bash.split(separator: "\n").joined(separator: " · ")) }
                        zeile("Maschine", WeltenWorte.maschine(e.maschine))
                        if !e.kontextgrenze.isEmpty { zeile("Kontextgrenze", e.kontextgrenze) }
                    }
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
         AgentEntwurf.mitStufe(e.modell, e.denkstufe))
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
