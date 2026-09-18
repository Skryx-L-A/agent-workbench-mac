// DIE AGENTS-ANSICHT NACH FASSUNG 28 (14.09.2026, docs/AGENTS-PLAN.md
// Abschnitt 6 und 13; Auftrag agentsui). Zuerst als Vorab-Blatt im eigenen
// Fenster gebaut; seit Abnahme des Nutzers vom 14.09., 20:40 (Plan Abschnitt 12,
// Schritt 4) steht sie im Tab „Agents" des Hauptfensters (Fenster.swift), und
// das Fenster „Agents-Welten …" bleibt als zweiter Zugang zu derselben Ansicht.
//
// Links die Leiste der Welt: Dropdown der Welten mit Plus, der Kanal mit
// Ungelesen-Zahl, der Hauptagent immer oben, die Teams einklappbar bis zum
// Teamleiter (mit der Zahl der Mitglieder, die arbeiten oder ein Ergebnis
// haben), Mitglieder ohne Team darunter; Baum oder Liste. In der Mitte der
// Einzelchat des gewaehlten Agenten, ein Direktchat zwischen Agenten zum
// Lesen, oder der Kanal mit Adressfeld; darueber die Reiter Chat und Tickets
// und die Kopfzeile. Rechts der Inspektor mit Profil, Protokoll und
// Gedaechtnis. Oben rechts Zaehler und Pausenschalter der Welt. Offene Fragen
// stehen im Einzelchat des Hauptagenten und als Leiste ueber jedem anderen
// Gespraech, bis sie beantwortet oder zurueckgenommen sind.
//
// JEDE HANDLUNG geht als `welt:<handlung> <JSON>` an den Kern (`awb:aufgabe`),
// der sie ueber die Datenbibliothek ausfuehrt. Diese Seite schreibt keine
// Weltdatei selbst. Ein Klick hier traegt `echt: true` (Absender `mensch`),
// der Steuerkanal `echt: false` (Absender `cli-operator`); beides bleibt ein
// unbestaetigter Entwicklungsabsender.
//
// Gestaltung nach apple-native-design: NavigationSplitView mit Inspektor,
// Systemfarben und Textstile, Karten statt Gitternetz, neben jedem Punkt das
// Wort, keine Emojis. Die Figuren kommen unveraendert aus Agentenfigur.swift.
import AppKit
import SwiftUI

// MARK: Der Zustand

@MainActor
@Observable
final class WeltenZustand {
    enum Darstellung: String, CaseIterable, Sendable {
        case baum, liste
        var titel: String { self == .baum ? "Baum" : "Liste" }
    }
    enum Reiter: String, CaseIterable, Sendable {
        case chat, tickets
        var titel: String { self == .chat ? "Chat" : "Tickets" }
    }
    enum Blatt: String, CaseIterable, Sendable {
        case profil, protokoll, gedaechtnis, skills
        var titel: String {
            switch self {
            case .profil: "Profil"
            case .protokoll: "Protokoll"
            case .gedaechtnis: "Gedächtnis"
            case .skills: "Skills"
            }
        }
    }
    struct Meldung: Equatable { let text: String; let ok: Bool }
    struct Rueckfrage: Equatable, Identifiable {
        let handlung: String; let daten: [String: String]; let text: String; let warnungen: [String]; let echt: Bool
        var id: String { handlung + (daten["agent"] ?? "") + (daten["frage"] ?? "") }
    }
    /// Das Formular für ein neues Ticket (Auftrag tickets4 C): Auftrag, Art, Priorität,
    /// Adressat, Eltern, Abhängigkeiten und Grenzen. Leere Felder heissen „Vorgabe des Kerns".
    struct TicketEntwurf: Identifiable, Equatable {
        var titel = "", ziel = "", fertig = "", an = ""
        var kind = "auftrag"
        var prioritaet = 2
        var fertigPunkte: [String] = []
        var eltern = ""
        var abhaengig: [String] = []
        var frist = "", runden = ""
        let id = UUID()
    }
    /// Die Handlung, die im Ticketdetail gerade offen steht; nur eine zur Zeit.
    enum TicketHandlung: String, CaseIterable, Equatable, Sendable {
        case rueckgabe, verwerfen, annehmen, umadressieren, grenzen, pruefer
    }
    /// Die Felder aller Detail-Handlungen an einem Ticket; sie leeren sich mit dem Schliessen.
    struct TicketHandlungEntwurf: Equatable {
        var ticket = ""
        var handlung: TicketHandlung = .rueckgabe
        var grund = "", bemerkung = "", duplikat = ""
        var an = "", pruefer = ""
        var kind = "auftrag"
        var prioritaet = 2
        var fertigPunkte: [String] = []
        var frist = "", runden = ""
    }
    /// Zyklus, Definition of Done und WIP-Grenze der Welt im Inspektor (Auftrag tickets4 D).
    struct WeltRegelEntwurf: Equatable {
        var welt = ""
        var zyklusTage = "", zyklusZiel = ""
        var dod: [String] = []
        var wip = ""
    }

    static let kanal = "kanal"
    /// Die Uebersicht der Welt (Auftrag agentsux Nr. 1): Karten je Agent, was dich braucht, offene Tickets.
    static let uebersicht = "uebersicht"
    static let einzel = "einzel"
    static let merkerDatei = "agents-welten.txt"
    static let merkerSchluessel = "agentsWelten"

    var weltPfad: String?
    /// `uebersicht`, `kanal` oder `agent:<id>`. Eine Welt geht mit ihrer Uebersicht auf.
    var auswahl: String = WeltenZustand.uebersicht
    var darstellung: Darstellung = .baum { didSet { if darstellung != oldValue { merken() } } }
    /// Chat oder Tickets. Die Uebersicht hat keine Reiter: wer dort Tickets will, meint die der Welt,
    /// und die stehen am Kanal.
    var reiter: Reiter = .chat {
        didSet { if reiter != oldValue, auswahl == Self.uebersicht { auswahl = Self.kanal } }
    }
    var blatt: Blatt = .profil
    /// `einzel` oder die Kennung eines Direktchats zwischen Agenten.
    var gespraech: String = WeltenZustand.einzel
    var zugeklappt: Set<String> = []
    /// Ein Ticket oeffnet sich im Reiter Tickets; aus der Uebersicht heraus am Kanal, der alle Tickets der Welt fuehrt.
    var ticketAuswahl: String? {
        didSet {
            guard ticketAuswahl != nil, auswahl == Self.uebersicht else { return }
            auswahl = Self.kanal
            reiter = .tickets
        }
    }
    /// `offen` (alles ausser abgenommen und verworfen), `alle`, `triage` oder ein Stand.
    var ticketFilter = "offen"
    /// Liste oder Board (Plan Satz 47). Das Board zeigt die Stände als Spalten, je Vorhaben eine Swimlane.
    enum TicketAnsicht: String, CaseIterable, Sendable {
        case liste, board
        var titel: String { self == .liste ? "Liste" : "Board" }
    }
    var ticketAnsicht: TicketAnsicht = .liste
    /// Die offene Handlung im Ticketdetail (Verwerfen, Annehmen, Umadressieren, Grenzen, Prüfer, Abnehmen).
    var ticketHandlung: TicketHandlungEntwurf?
    /// Die Regeln der Welt in Bearbeitung (Zyklus, Definition of Done, WIP-Grenze).
    var weltRegeln: WeltRegelEntwurf?
    /// Das Ticket, das gerade in der Triage gezogen wird (Backlog-Reihenfolge, Satz 44).
    var backlogZieht: String?
    var entwuerfe: [String: String] = [:]
    var adressfeld = ""
    var antwortEntwuerfe: [String: String] = [:]
    var meldung: Meldung?
    var rueckfrage: Rueckfrage?
    var neuesTicket: TicketEntwurf?
    var inspektorOffen = true
    var gelesen = WeltenGelesen()
    /// Das Ticket, dessen Rueckgabe gerade im Detail offen steht, und die Bemerkung dazu.
    var rueckgabeOffen: String?
    var rueckgabeText = ""
    var profilEntwurf: ProfilEntwurf?
    var gedaechtnisEntwurf: GedaechtnisEntwurf?
    /// Auftrag agentsform: die Rechte eines bestehenden Agenten in Bearbeitung (nur, wenn die Bibliothek `wb-agent rechte` kennt).
    var rechteEntwurf: RechteEntwurf?
    /// Das offene Anlege-Menue (WeltenAnlegen.swift); solange es steht, zeigt die Mitte das Formular.
    var anlegen: AnlegenEntwurf?
    /// Auftrag fernwelten: die Frage, auf welcher Maschine die globale Welt entsteht; nil = keine offen.
    var weltNeuFrage: WeltNeuFrage?
    struct WeltNeuFrage: Equatable, Identifiable {
        let name: String
        /// (Maschine, Knopftitel), die Vorgabe zuerst.
        let wege: [String]
        let vorgabe: String
        let text: String
        var id: String { name }
    }
    /// Auftrag Nr. 4: aufgeklappte SKILL.md, der offene Ablehnungsgrund eines Skill-Vorschlags.
    var skillOffen: Set<String> = []
    var skillAblehnenOffen: String?
    var skillGrund = ""
    /// WER DIE RUECKFRAGE ZEIGT (Auftrag agentsui Nr. 6). Tab und Fenster teilen den Zustand;
    /// ohne diese Wahl stuende dieselbe Rueckfrage als zwei Hinweise in zwei Fenstern, auch in
    /// einem, das gerade verborgen ist. Der Tab zeigt sie, solange er steht und das Fenster
    /// „Agents-Welten …" nicht vorn ist; sonst zeigt sie das Fenster.
    var tabSichtbar = false
    var fensterVorn = false
    var rueckfrageImTab: Bool { tabSichtbar && !fensterVorn }
    private(set) var laufend: Set<String> = []

    func laufendSetzen(_ handlung: String, _ an: Bool) {
        if an { laufend.insert(handlung) } else { laufend.remove(handlung) }
    }

    struct ProfilEntwurf: Equatable {
        let agent: String
        var modell, denkstufe, fallback, fallbackDenkstufe, maschine, spezialgebiet: String
        init(_ a: WeltAgent) {
            agent = a.id; modell = a.modell; denkstufe = a.denkstufe; fallback = a.fallback
            fallbackDenkstufe = a.fallbackDenkstufe; maschine = a.maschine; spezialgebiet = a.spezialgebiet
        }
    }
    struct GedaechtnisEntwurf: Equatable {
        let agent: String
        var text: String
        let sha: String
    }
    /// Werkzeuge ohne Bash (das bleibt), nur die eigenen Bash-Muster (eins je Zeile), Skills.
    struct RechteEntwurf: Equatable {
        let agent: String
        var werkzeuge: [String]
        var bash: String
        var skills: [String]
        init(_ a: WeltAgent, dienstweg: [String]) {
            agent = a.id
            werkzeuge = a.werkzeuge.filter { $0 != "Bash" }
            bash = AgentEntwurf.eigeneMuster(a.bash, dienstweg).joined(separator: "\n")
            skills = a.skills
        }
    }

    @ObservationIgnored weak var kern: KernVerbindung?
    var darstellungMerken: (String) -> Void = { _ in }

    private func merken() { darstellungMerken(darstellung.rawValue) }

    // --- Welt und Auswahl ---------------------------------------------------------

    func welt(_ n: WeltenNutzlast?) -> Welt? {
        guard let n else { return nil }
        return n.welten.first { $0.pfad == weltPfad } ?? n.welten.first { $0.fehler.isEmpty } ?? n.welten.first
    }

    var agentId: String? { auswahl.hasPrefix("agent:") ? String(auswahl.dropFirst(6)) : nil }

    func weltWaehlen(_ pfad: String, _ n: WeltenNutzlast?, echt: Bool = true) {
        guard weltPfad != pfad else { return }
        weltPfad = pfad
        auswahl = Self.uebersicht
        // Eine Meldung gehoert zu der Welt, in der gehandelt wurde.
        meldung = nil
        gespraech = Self.einzel
        ticketAuswahl = nil
        adressfeld = ""
        profilEntwurf = nil
        gedaechtnisEntwurf = nil
        rechteEntwurf = nil
        anlegen = nil
        if let w = welt(n) { gesehen(w, echt: echt) }
    }

    func waehlen(_ ziel: String, _ welt: Welt, echt: Bool = true) {
        auswahl = ziel
        anlegen = nil
        gespraech = Self.einzel
        ticketAuswahl = nil
        rueckgabeOffen = nil
        if profilEntwurf?.agent != agentId { profilEntwurf = nil }
        if gedaechtnisEntwurf?.agent != agentId { gedaechtnisEntwurf = nil }
        if rechteEntwurf?.agent != agentId { rechteEntwurf = nil }
        gesehen(welt, echt: echt)
    }

    /// Das Adressfeld zeigt den Hauptagenten, bis jemand etwas anderes eintraegt.
    func adressen(_ w: Welt) -> String { adressfeld.isEmpty ? WeltenAdressen.vorgabe(w) : adressfeld }

    // --- Gespraeche und Ungelesen -------------------------------------------------

    /// Der Schluessel des Gespraechs, das gerade in der Mitte steht.
    func gespraechSchluessel() -> String {
        guard let id = agentId else { return Self.kanal }
        return gespraech == Self.einzel ? "einzel:\(id)" : "direkt:\(gespraech)"
    }

    static func nachrichten(einzelchat a: WeltAgent) -> [WeltNachricht] { a.einzelchat.compactMap(\.nachricht) }

    /// Die Nachrichten eines Gespraechs, fuer Ungelesen und Gesehen.
    func nachrichten(_ w: Welt, schluessel: String) -> [WeltNachricht] {
        if schluessel == Self.kanal { return w.kanal }
        if schluessel.hasPrefix("einzel:") { return w.agent(String(schluessel.dropFirst(7))).map(Self.nachrichten(einzelchat:)) ?? [] }
        if schluessel.hasPrefix("direkt:") { return w.direktchats.first { $0.id == String(schluessel.dropFirst(7)) }?.nachrichten ?? [] }
        return []
    }

    /// Ungelesen nach der juengeren Marke: der Lesestand der Welt oder das, was diese Oberflaeche gerade gesehen hat.
    func ungelesen(_ w: Welt, schluessel: String) -> Int {
        let marke = WeltMarke.neuer(w.gelesenMarken[schluessel], gelesen.marke(welt: w.id, gespraech: schluessel))
        return WeltenGelesen.zaehlen(nachrichten(w, schluessel: schluessel), marke: marke)
    }

    /// Ungelesen an einem Agenten der Leiste: sein Einzelchat.
    func ungelesen(_ w: Welt, agent: String) -> Int { ungelesen(w, schluessel: "einzel:\(agent)") }

    /// Was in der Mitte steht, gilt als gesehen. Liegt die juengste Nachricht hinter dem
    /// Lesestand der Welt, geht die neue Marke ueber den Kern in die Welt (`wb-welt gelesen`).
    func gesehen(_ w: Welt, echt: Bool = true) {
        // Die Uebersicht zeigt aus dem Kanal nur die letzten Zeilen; gelesen ist er damit nicht.
        guard auswahl != Self.uebersicht else { return }
        let k = gespraechSchluessel()
        guard reiter == .chat || k == Self.kanal else { return }
        let liste = nachrichten(w, schluessel: k)
        _ = gelesen.gesehen(liste, welt: w.id, gespraech: k)
        guard let letzte = liste.max(by: { ($0.zeit, $0.id) < ($1.zeit, $1.id) }) else { return }
        if let welt = w.gelesenMarken[k], (welt.zeit, welt.id) >= (letzte.zeit, letzte.id) { return }
        let daten: [String: Any] = ["welt": w.pfad, "gespraech": k, "zeit": letzte.zeit, "id": letzte.id]
        Task { _ = await self.ausfuehren("gelesen", daten, echt: echt, still: true) }
    }

    // --- Leiste ---------------------------------------------------------------------

    enum Zeile: Equatable, Identifiable {
        case uebersicht
        case kanal
        case agent(id: String, ebene: Int, teamZusatz: Bool)
        case team(name: String, offen: Bool, aktiv: Int, mitLeiter: Bool)
        case kopf(String)
        /// Eine Zeile ohne Auswahl, die sagt, warum ein Abschnitt leer ist.
        case hinweis(String)
        var id: String {
            switch self {
            case .uebersicht: "uebersicht"
            case .kanal: "kanal"
            case .agent(let id, _, _): "agent:\(id)"
            case .team(let name, _, _, _): "team:\(name)"
            case .kopf(let t): "kopf:\(t)"
            case .hinweis(let t): "hinweis:\(t)"
            }
        }
    }

    /// Die Zeilen der Leiste als flache Folge -- fuer Bildschirm und Auskunft dieselbe.
    /// Oben die Welt selbst (Uebersicht, Kanal), darunter unter eigenen Koepfen der
    /// Hauptagent und die Teams; eine Welt ohne Hauptagenten sagt das an seiner Stelle.
    func zeilen(_ w: Welt) -> [Zeile] {
        var raus: [Zeile] = [.uebersicht, .kanal, .kopf("Hauptagent")]
        if let h = w.hauptagent {
            raus.append(.agent(id: h, ebene: 0, teamZusatz: false))
        } else {
            raus.append(.hinweis("Noch kein Hauptagent"))
        }
        switch darstellung {
        case .liste:
            let rest = w.liste.filter { $0 != w.hauptagent }
            if !rest.isEmpty { raus.append(.kopf("Agenten")) }
            raus += rest.map { .agent(id: $0, ebene: 0, teamZusatz: true) }
        case .baum:
            if !w.teams.isEmpty { raus.append(.kopf("Teams")) }
            for t in w.teams {
                let offen = !zugeklappt.contains(t.name)
                if let l = t.leiter {
                    raus.append(.team(name: t.name, offen: offen, aktiv: t.aktiv, mitLeiter: true))
                    raus.append(.agent(id: l, ebene: 0, teamZusatz: false))
                } else {
                    raus.append(.team(name: t.name, offen: offen, aktiv: t.aktiv, mitLeiter: false))
                }
                if offen { raus += t.mitglieder.map { .agent(id: $0, ebene: 1, teamZusatz: false) } }
            }
            if !w.ohneTeam.isEmpty {
                raus.append(.kopf("Ohne Team"))
                raus += w.ohneTeam.map { .agent(id: $0, ebene: 0, teamZusatz: false) }
            }
        }
        return raus
    }

    func umklappen(_ team: String) {
        if zugeklappt.contains(team) { zugeklappt.remove(team) } else { zugeklappt.insert(team) }
    }

    // --- Tickets -------------------------------------------------------------------

    func tickets(_ w: Welt) -> [WeltTicket] {
        let basis: [WeltTicket]
        if let id = agentId, let a = w.agent(id) {
            basis = w.tickets.filter { a.tickets.contains($0.id) }
        } else {
            basis = w.tickets
        }
        let gefiltert: [WeltTicket]
        switch ticketFilter {
        case "alle": gefiltert = basis
        case "offen": gefiltert = basis.filter { !["abgenommen", "verworfen"].contains($0.stand) }
        default: gefiltert = basis.filter { $0.stand == ticketFilter }
        }
        // Die Triage ist das geordnete Backlog (Plan Satz 44): sie steht in ihrer Reihenfolge,
        // nicht nach Aenderung. Alles andere: juengste Aenderung zuerst; bei gleicher Sekunde
        // entscheidet die Kennung, damit nichts springt.
        if ticketFilter == "triage" { return Self.backlogFolge(gefiltert) }
        return gefiltert.sorted { $0.geaendert != $1.geaendert ? $0.geaendert > $1.geaendert : $0.id < $1.id }
    }

    /// Die Triage in Backlog-Reihenfolge: `order` aufsteigend, ohne Feld ans Ende, dann Anlagezeit.
    nonisolated static func backlogFolge(_ tickets: [WeltTicket]) -> [WeltTicket] {
        tickets.sorted { a, b in
            let x = a.ordnung ?? Int.max, y = b.ordnung ?? Int.max
            if x != y { return x < y }
            if a.angelegt != b.angelegt { return a.angelegt < b.angelegt }
            return a.id < b.id
        }
    }

    /// Die Tickets der Welt in der Triage, in Backlog-Reihenfolge (fuer den Reiter und die Uebersicht).
    nonisolated static func backlog(_ w: Welt) -> [WeltTicket] {
        backlogFolge(w.tickets.filter { $0.stand == "triage" })
    }

    // --- Das Board (Plan Satz 47) ----------------------------------------------------

    /// Eine Swimlane des Boards: ein Vorhaben mit seinen Tickets, zuletzt „Ohne Vorhaben".
    struct BoardSpur: Identifiable, Equatable {
        let id: String
        let titel: String
        /// Je Spalte des Boards die Tickets dieser Spur, in derselben Reihenfolge wie `boardSpalten`.
        let spalten: [[WeltTicket]]
    }

    /// Das Board einer Welt: Spalten in Bearbeitungsrichtung, je Vorhaben eine Swimlane.
    /// Ein Ticket gehoert zu dem Vorhaben an der Wurzel seiner Elternkette; Tickets ohne
    /// Vorhaben liegen in „Ohne Vorhaben" (AGIL Abschnitt 5).
    nonisolated static func board(_ w: Welt, tickets: [WeltTicket]) -> [BoardSpur] {
        let nachId = Dictionary(w.tickets.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        func vorhaben(_ t: WeltTicket) -> WeltTicket? {
            if t.kind == "vorhaben" { return t }
            var jetzt = t
            var tiefe = 0
            while let eltern = jetzt.eltern, let naechst = nachId[eltern], tiefe < 5 {
                if naechst.kind == "vorhaben" { return naechst }
                jetzt = naechst
                tiefe += 1
            }
            return nil
        }
        var folge: [String] = []
        var gruppen: [String: [WeltTicket]] = [:]
        for t in tickets {
            let schluessel = vorhaben(t)?.id ?? ""
            if gruppen[schluessel] == nil { folge.append(schluessel) }
            gruppen[schluessel, default: []].append(t)
        }
        // Vorhaben zuerst in der Reihenfolge ihres Auftretens, „Ohne Vorhaben" zuletzt.
        folge = folge.filter { !$0.isEmpty } + (gruppen[""] != nil ? [""] : [])
        return folge.map { schluessel in
            let inhalt = gruppen[schluessel] ?? []
            let spalten = WeltenWorte.boardSpalten.map { spalte -> [WeltTicket] in
                let staende = WeltenWorte.boardStaende(spalte)
                let drin = inhalt.filter { staende.contains($0.stand) }
                return spalte == "triage" ? backlogFolge(drin)
                    : drin.sorted { $0.prioritaet != $1.prioritaet ? $0.prioritaet < $1.prioritaet : $0.id < $1.id }
            }
            let titel = schluessel.isEmpty ? "Ohne Vorhaben" : (nachId[schluessel]?.titel ?? schluessel)
            return BoardSpur(id: schluessel.isEmpty ? "ohne-vorhaben" : schluessel, titel: titel, spalten: spalten)
        }
    }

    /// Was am Kopf der Spalte „läuft" steht (Satz 48): „3 von 4", rot bei Überschreitung.
    nonisolated static func wipText(_ w: Welt) -> (text: String, rot: Bool) {
        ("\(w.wip.laufend) von \(w.wip.grenze)", w.wip.grenze > 0 && w.wip.laufend > w.wip.grenze)
    }

    /// WELCHE HANDLUNGEN DER KERN DEM MENSCHEN AN DIESEM TICKET ERLAUBT (docs/AGENTS-DATEN.md,
    /// Plan Sätze 22, 23, 25, 27, 31, 39). Was er nicht erlaubt, bietet die Ansicht nicht an:
    /// Parken, Zwischenstand, Haken und Prüfnotiz gehören dem Bearbeiter beziehungsweise dem
    /// Prüfer, „braucht dich" setzt nur der Hauptagent über seinen Zug.
    nonisolated static func moeglicheHandlungen(_ t: WeltTicket) -> [TicketHandlung] {
        var raus: [TicketHandlung] = []
        if t.stand == "triage" { raus.append(.annehmen) }
        if t.stand != "abgenommen" { raus.append(.verwerfen) }
        raus.append(.umadressieren)
        if !["abgenommen", "verworfen"].contains(t.stand) { raus.append(.grenzen) }
        // Abnehmen steht dem Menschen NICHT offen (Hausregel vom 11.09.2026, Plan Satz 27:
        // „der Nutzer nimmt nicht ab“). Abgenommen wird vom Hauptagenten oder vom Teamleiter des
        // Teams; der Mensch kann ein abgenommenes Ticket zurueckgeben.
        if t.stand == "zur Abnahme" { raus.append(.pruefer) }
        return raus
    }

    // --- Handlungen ----------------------------------------------------------------

    private static func befehl(_ handlung: String, _ daten: [String: Any]) -> String {
        let json = (try? JSONSerialization.data(withJSONObject: daten, options: [.sortedKeys])).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
        return "welt:\(handlung) \(json)"
    }

    /// `still`: ein Erfolg setzt keine Meldung (der Lesestand laeuft bei jedem Blick mit).
    func ausfuehren(_ handlung: String, _ daten: [String: Any], echt: Bool, bestaetigt: Bool = false, still: Bool = false) async -> Bool {
        await handlungAntwort(handlung, daten, echt: echt, bestaetigt: bestaetigt, still: still).ok
    }

    /// Wie `ausfuehren`, mit der ganzen Antwort des Kerns (neuer Pfad nach einem Umzug, Maschinen nach der Probe).
    func handlungAntwort(_ handlung: String, _ daten: [String: Any], echt: Bool, bestaetigt: Bool = false, still: Bool = false) async -> HandlungsAntwort {
        let befehl = Self.befehl(handlung, daten)
        laufend.insert(handlung)
        defer { laufend.remove(handlung) }
        guard let kern else {
            meldung = Meldung(text: "Keine Verbindung zum Kern.", ok: false)
            return HandlungsAntwort(ok: false, meldung: "Keine Verbindung zum Kern.")
        }
        let r = HandlungsAntwort(await kern.invoke("awb:aufgabe", [befehl, ["echt": echt, "bestaetigt": bestaetigt]]))
        if let f = r.rueckfrage, !bestaetigt {
            let texte = daten.reduce(into: [String: String]()) { $0[$1.key] = "\($1.value)" }
            rueckfrage = Rueckfrage(handlung: handlung, daten: texte, text: f, warnungen: r.warnungen, echt: echt)
            return HandlungsAntwort(ok: false, meldung: r.meldung)
        }
        if !(still && r.ok) { meldung = Meldung(text: r.meldung, ok: r.ok) }
        return r
    }

    /// Eine markierte Nachricht an den Menschen zur Kenntnis nehmen (Quittung der Zustellung).
    func quittieren(_ w: Welt, zustellung: String, echt: Bool) async {
        _ = await ausfuehren("quittieren", ["welt": w.pfad, "zustellung": zustellung], echt: echt)
    }

    /// Ein abgenommenes Ticket mit Bemerkung an den Bearbeiter zurueckgeben.
    func zurueckgeben(_ w: Welt, ticket: String, echt: Bool) async {
        let text = rueckgabeText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            meldung = Meldung(text: "Die Rückgabe braucht eine Bemerkung, was fehlt.", ok: false)
            return
        }
        if await ausfuehren("zurueckgeben", ["welt": w.pfad, "ticket": ticket, "bemerkung": text], echt: echt) {
            rueckgabeOffen = nil
            rueckgabeText = ""
        }
    }

    /// Nur geaenderte Felder gehen hinaus; ohne Aenderung passiert nichts.
    func profilSichern(_ w: Welt, echt: Bool) async {
        guard let e = profilEntwurf, let a = w.agent(e.agent) else { return }
        var d: [String: Any] = ["welt": w.pfad, "agent": a.id]
        if e.modell != a.modell { d["modell"] = e.modell }
        if e.denkstufe != a.denkstufe { d["denkstufe"] = e.denkstufe }
        if e.fallback != a.fallback { d["fallback"] = e.fallback }
        if e.fallbackDenkstufe != a.fallbackDenkstufe { d["fallback_denkstufe"] = e.fallbackDenkstufe }
        if e.maschine != a.maschine { d["maschine"] = e.maschine }
        if e.spezialgebiet != a.spezialgebiet { d["spezialgebiet"] = e.spezialgebiet }
        guard d.count > 2 else {
            profilEntwurf = nil
            meldung = Meldung(text: "Am Profil von \(a.name) hat sich nichts geändert.", ok: true)
            return
        }
        if await ausfuehren("profil", d, echt: echt) { profilEntwurf = nil }
    }

    /// Auftrag agentsform: die Rechte eines bestehenden Agenten sichern (`welt:rechte`, `wb-agent rechte`).
    func rechteSichern(_ w: Welt, echt: Bool) async {
        guard let e = rechteEntwurf else { return }
        let muster = e.bash.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        if await ausfuehren("rechte", ["welt": w.pfad, "agent": e.agent, "werkzeuge": ["Bash"] + e.werkzeuge, "bash": muster, "skills": e.skills], echt: echt) {
            rechteEntwurf = nil
        }
    }

    /// Ein Werkzeug der Rechte in Bearbeitung; nil, wenn es ging, sonst der Grund.
    @discardableResult
    func rechteWerkzeug(_ name: String, _ an: Bool, _ w: Welt) -> String? {
        guard var e = rechteEntwurf else { return "Keine Rechte in Bearbeitung." }
        if name == "Bash" { return an ? nil : "Bash gehört zum Dienstweg und bleibt dabei." }
        if Self.webWerkzeuge.contains(name), an, !w.webZugang { return Self.webOhneZugang(w.webZugangBefehl) }
        if an, !e.werkzeuge.contains(name) { e.werkzeuge.append(name) }
        if !an { e.werkzeuge.removeAll { $0 == name } }
        rechteEntwurf = e
        return nil
    }

    func rechteSkill(_ name: String, _ an: Bool) {
        guard var e = rechteEntwurf else { return }
        if an, !e.skills.contains(name) { e.skills.append(name) }
        if !an { e.skills.removeAll { $0 == name } }
        rechteEntwurf = e
    }

    /// Auftrag agentsform: einen gemerkten Projektordner aus der Liste nehmen; der Kern fragt zurueck, der Ordner bleibt.
    func vergessen(_ ordner: String, echt: Bool) async {
        _ = await ausfuehren("vergessen", ["ordner": ordner], echt: echt)
    }

    /// Mit dem Stand, den der Editor geladen hat: hat der Agent inzwischen geschrieben, lehnt die Bibliothek ab.
    func gedaechtnisSichern(_ w: Welt, echt: Bool) async {
        guard let e = gedaechtnisEntwurf else { return }
        if await ausfuehren("gedaechtnis", ["welt": w.pfad, "agent": e.agent, "text": e.text, "erwartet": e.sha], echt: echt) {
            gedaechtnisEntwurf = nil
        }
    }

    func bestaetigen() async {
        guard let rf = rueckfrage else { return }
        rueckfrage = nil
        let r = await handlungAntwort(rf.handlung, rf.daten, echt: rf.echt, bestaetigt: true)
        // Eine bestaetigte Ticket-Handlung schliesst ihr Formular im Detail.
        if r.ok, rf.handlung.hasPrefix("ticket_") { handlungSchliessen() }
        // Nach einem Umzug heisst die Welt `<maschine>:<ablage>`; die Ansicht bleibt bei ihr.
        if rf.handlung == "umziehen", r.ok, !r.pfad.isEmpty { weltGewechselt(r.pfad) }
    }

    private func weltGewechselt(_ pfad: String) {
        weltPfad = pfad
        auswahl = Self.uebersicht
        gespraech = Self.einzel
        ticketAuswahl = nil
        anlegen = nil
    }

    // --- Maschinen (Auftrag fernwelten) -----------------------------------------------

    /// Eine Welt dieser Maschine auf eine Agent-Maschine: der Kern prueft trocken und fragt zurueck.
    func umziehen(_ w: Welt, nach maschine: String, trocken: Bool = false, echt: Bool) async {
        var d: [String: Any] = ["welt": w.pfad, "maschine": maschine]
        if trocken { d["trocken"] = true }
        _ = await ausfuehren("umziehen", d, echt: echt)
    }

    /// Jede Agent-Maschine einmal fragen; die Antwort traegt ihren Stand.
    @discardableResult
    func maschinenPruefen(echt: Bool) async -> [WeltMaschine] {
        await handlungAntwort("maschinen", ["pruefen": true], echt: echt, still: true).maschinen
    }

    /// Die gezeigte Fernwelt liest der Kern oefter; eine lokale braucht das nicht (fs.watch).
    func gewaehltMelden(_ w: Welt) async {
        guard w.fern else { return }
        _ = await ausfuehren("gewaehlt", ["welt": w.pfad], echt: false, still: true)
    }

    /// Die Vorgabe beim Anlegen: die Standardmaschine, sobald sie als erreichbar belegt ist, sonst diese.
    /// Gefragt wird nur auf einen echten Klick (Ordnerdialog, globale Welt); die Wahl folgt der Probe.
    nonisolated static func maschineVorgabe(_ maschinen: [WeltMaschine], vorgabe: String) -> String {
        let eigene = maschinen.first { $0.eigene }?.name ?? ""
        guard let m = maschinen.first(where: { $0.name == vorgabe && !$0.eigene && $0.traeger }), m.erreichbar == true else { return eigene }
        return m.name
    }

    /// Was unter der Wahl der Maschine steht: wohin die Welt kommt und ob dort Agenten antworten.
    nonisolated static func maschinenWahlText(_ maschinen: [WeltMaschine], auswahl: String) -> String {
        guard let m = maschinen.first(where: { $0.name == auswahl }) else { return "" }
        let name = WeltenWorte.maschine(m.name)
        if m.eigene {
            return m.traeger ? "Die Welt entsteht hier und bekommt ihren Träger." : "Die Welt entsteht \(WeltenWorte.aufMaschine(m.name)). Hier läuft kein Träger, Agenten antworten hier nicht."
        }
        switch m.erreichbar {
        case false?: return "\(name) ist nicht erreichbar\(m.text.isEmpty ? "" : " (\(m.text))"). Angelegt wird erst, wenn \(name) antwortet."
        case nil: return "\(name) wird gefragt …"
        case true?: return "Die Welt entsteht auf \(name) unter demselben Pfad relativ zum Benutzerordner und bekommt dort ihren Träger."
        }
    }

    /// Senden aus dem Eingabefeld: Einzelchat an den gewaehlten Agenten, sonst Kanal mit Adressfeld.
    @discardableResult
    func senden(_ w: Welt, echt: Bool) async -> Bool {
        guard auswahl != Self.uebersicht else {
            meldung = Meldung(text: "Die Übersicht hat kein Eingabefeld; wähle den Kanal oder einen Agenten.", ok: false)
            return false
        }
        let k = gespraechSchluessel()
        let text = (entwuerfe[k] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return false }
        var daten: [String: Any] = ["welt": w.pfad, "text": text]
        if let id = agentId {
            guard gespraech == Self.einzel else {
                meldung = Meldung(text: "Ein Direktchat zwischen Agenten ist nur zum Lesen da.", ok: false)
                return false
            }
            daten["an"] = [id]
            daten["direkt"] = true
        } else {
            let r = WeltenAdressen.lesen(adressen(w), welt: w)
            if let f = r.fehler {
                meldung = Meldung(text: f, ok: false)
                return false
            }
            daten["an"] = r.adressen
        }
        let ok = await ausfuehren("senden", daten, echt: echt)
        if ok { entwuerfe[k] = "" }
        return ok
    }

    func antworten(_ w: Welt, frage: String, text: String, echt: Bool) async {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        if await ausfuehren("antworten", ["welt": w.pfad, "frage": frage, "text": t], echt: echt) { antwortEntwuerfe[frage] = "" }
    }

    func zuruecknehmen(_ w: Welt, frage: String, echt: Bool) async {
        _ = await ausfuehren("zuruecknehmen", ["welt": w.pfad, "frage": frage], echt: echt)
    }

    /// Der Pausenschalter: `laeuft` true setzt fort, false pausiert -- fuer die Welt oder einen Agenten.
    func schalten(_ w: Welt, agent: String?, laeuft: Bool, echt: Bool) async {
        var d: [String: Any] = ["welt": w.pfad]
        if let agent { d["agent"] = agent }
        _ = await ausfuehren(laeuft ? "fortsetzen" : "pausieren", d, echt: echt)
    }

    func stoppen(_ w: Welt, agent: String?, echt: Bool) async {
        var d: [String: Any] = ["welt": w.pfad]
        if let agent { d["agent"] = agent }
        _ = await ausfuehren("stoppen", d, echt: echt)
    }

    func ticketAnlegen(_ w: Welt, _ e: TicketEntwurf, echt: Bool) async -> Bool {
        var d: [String: Any] = ["welt": w.pfad, "titel": e.titel, "ziel": e.ziel, "fertig": e.fertig,
                                "art": e.kind, "prioritaet": e.prioritaet]
        if !e.an.isEmpty { d["an"] = [e.an] }
        let punkte = e.fertigPunkte.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        if !punkte.isEmpty { d["fertig_punkte"] = punkte }
        if !e.eltern.isEmpty { d["eltern"] = e.eltern }
        if !e.abhaengig.isEmpty { d["abhaengig"] = e.abhaengig }
        if !e.frist.isEmpty { d["frist"] = e.frist }
        if !e.runden.isEmpty { d["runden"] = e.runden }
        return await ausfuehren("ticket", d, echt: echt)
    }

    // --- tickets4: die Handlungen des Menschen am Ticket -------------------------------

    /// Eine Handlung im Detail öffnen; die Felder stehen mit den Vorgaben des Tickets da.
    func handlungOeffnen(_ handlung: TicketHandlung, _ t: WeltTicket, welt w: Welt) {
        var e = TicketHandlungEntwurf(ticket: t.id, handlung: handlung)
        switch handlung {
        case .rueckgabe:
            rueckgabeOffen = t.id
            rueckgabeText = ""
            ticketHandlung = nil
            return
        case .verwerfen: e.grund = "nicht-mehr-noetig"
        case .annehmen:
            e.kind = t.kind
            e.prioritaet = t.prioritaet
            e.an = w.hauptagent ?? ""
        case .umadressieren: e.an = t.bearbeiter ?? t.adressaten.first ?? (w.hauptagent ?? "")
        case .grenzen:
            e.frist = t.grenzen["frist"] ?? ""
            e.runden = t.grenzen["runden"] ?? ""
        case .pruefer: e.pruefer = w.agenten.first { $0.id != t.bearbeiter && $0.stand == "aktiv" }?.id ?? ""
        }
        rueckgabeOffen = nil
        ticketHandlung = e
    }

    func handlungSchliessen() {
        ticketHandlung = nil
        rueckgabeOffen = nil
        rueckgabeText = ""
    }

    /// Ein Ticket verwerfen (Satz 22 und 40): Grundcode Pflicht, bei `duplikat` der Verweis.
    func verwerfen(_ w: Welt, echt: Bool) async {
        guard let e = ticketHandlung, e.handlung == .verwerfen else { return }
        var d: [String: Any] = ["welt": w.pfad, "ticket": e.ticket, "grund": e.grund]
        let bemerkung = e.bemerkung.trimmingCharacters(in: .whitespacesAndNewlines)
        if !bemerkung.isEmpty { d["bemerkung"] = bemerkung }
        if !e.duplikat.isEmpty { d["duplikat_von"] = e.duplikat }
        if await ausfuehren("ticket_verwerfen", d, echt: echt) { handlungSchliessen() }
    }

    /// Ein Triage-Ticket annehmen (Satz 39): Adressat, Priorität, Art, Fertig-Punkte.
    func annehmen(_ w: Welt, echt: Bool) async {
        guard let e = ticketHandlung, e.handlung == .annehmen else { return }
        var d: [String: Any] = ["welt": w.pfad, "ticket": e.ticket, "an": [e.an],
                                "prioritaet": e.prioritaet, "art": e.kind]
        let punkte = e.fertigPunkte.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        if !punkte.isEmpty { d["fertig_punkte"] = punkte }
        if await ausfuehren("ticket_annehmen", d, echt: echt) { handlungSchliessen() }
    }

    /// Ein Ticket umadressieren (Satz 23): neue Adressaten mit Grund.
    func umadressieren(_ w: Welt, echt: Bool) async {
        guard let e = ticketHandlung, e.handlung == .umadressieren else { return }
        let grund = e.grund.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !grund.isEmpty else {
            meldung = Meldung(text: "Umadressieren braucht einen Grund.", ok: false)
            return
        }
        if await ausfuehren("ticket_umadressieren", ["welt": w.pfad, "ticket": e.ticket, "an": [e.an], "grund": grund], echt: echt) {
            handlungSchliessen()
        }
    }

    /// Frist und Rundenzahl eines Tickets setzen (Sätze 6 und 31).
    func grenzenSetzen(_ w: Welt, echt: Bool) async {
        guard let e = ticketHandlung, e.handlung == .grenzen else { return }
        var d: [String: Any] = ["welt": w.pfad, "ticket": e.ticket]
        if !e.frist.isEmpty { d["frist"] = e.frist }
        if !e.runden.isEmpty { d["runden"] = e.runden }
        if await ausfuehren("ticket_grenzen", d, echt: echt) { handlungSchliessen() }
    }

    /// Den Prüfer eines Ergebnisses setzen (Sätze 25 und 26).
    func prueferSetzen(_ w: Welt, echt: Bool) async {
        guard let e = ticketHandlung, e.handlung == .pruefer else { return }
        if await ausfuehren("ticket_pruefen", ["welt": w.pfad, "ticket": e.ticket, "pruefer": e.pruefer], echt: echt) {
            handlungSchliessen()
        }
    }

    /// Die Backlog-Reihenfolge der Triage setzen (Satz 44); `reihe` ist die ganze Liste, oben zuerst.
    @discardableResult
    func backlogOrdnen(_ w: Welt, reihe: [String], echt: Bool) async -> Bool {
        guard !reihe.isEmpty else { return false }
        return await ausfuehren("backlog", ["welt": w.pfad, "ordnen": reihe], echt: echt)
    }

    /// Ein Triage-Ticket um `schritte` verschieben (Pfeiltasten und der Steuerkanal).
    @discardableResult
    func backlogSchieben(_ w: Welt, ticket: String, schritte: Int, echt: Bool) async -> Bool {
        var reihe = Self.backlog(w).map(\.id)
        guard let jetzt = reihe.firstIndex(of: ticket) else {
            meldung = Meldung(text: "„\(ticket)“ steht nicht in der Triage.", ok: false)
            return false
        }
        let ziel = max(0, min(reihe.count - 1, jetzt + schritte))
        guard ziel != jetzt else { return false }
        reihe.remove(at: jetzt)
        reihe.insert(ticket, at: ziel)
        return await backlogOrdnen(w, reihe: reihe, echt: echt)
    }

    // --- tickets4: Zyklus, Definition of Done und WIP-Grenze der Welt ------------------

    func regelnOeffnen(_ w: Welt) {
        weltRegeln = WeltRegelEntwurf(welt: w.pfad, zyklusTage: w.zyklus.tage > 0 ? "\(w.zyklus.tage)" : "7",
                                      zyklusZiel: w.zyklus.jetzt?.ziel ?? "", dod: w.dod,
                                      wip: w.wip.grenze > 0 ? "\(w.wip.grenze)" : "")
    }

    func zyklusSetzen(_ w: Welt, an: Bool, echt: Bool) async {
        var d: [String: Any] = ["welt": w.pfad, "aktion": an ? "einschalten" : "ausschalten"]
        if an, let e = weltRegeln {
            if !e.zyklusTage.isEmpty { d["tage"] = e.zyklusTage }
            let ziel = e.zyklusZiel.trimmingCharacters(in: .whitespacesAndNewlines)
            if !ziel.isEmpty { d["ziel"] = ziel }
        }
        _ = await ausfuehren("zyklus", d, echt: echt)
    }

    func dodSichern(_ w: Welt, echt: Bool) async {
        guard let e = weltRegeln else { return }
        let punkte = e.dod.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        if await ausfuehren("dod", ["welt": w.pfad, "punkte": punkte], echt: echt) {
            weltRegeln?.dod = punkte
        }
    }

    func wipSetzen(_ w: Welt, echt: Bool) async {
        guard let e = weltRegeln else { return }
        _ = await ausfuehren("wip", ["welt": w.pfad, "limit": e.wip], echt: echt)
    }

    // --- Welt und Agent anlegen (Auftrag agentsux Nr. 1) ------------------------------

    /// Ob und wie der Knopf „Agent anlegen" geht: der Titel nennt den Hauptagenten, solange
    /// die Welt keinen hat; ein Grund steht als Text da, wenn er nicht geht.
    struct AnlegenLage: Equatable {
        let titel: String
        let aktiv: Bool
        let grund: String
    }

    nonisolated static func anlegenLage(_ w: Welt) -> AnlegenLage {
        let titel = w.hauptagent == nil ? "Hauptagent anlegen" : "Agent anlegen"
        if !w.fehler.isEmpty { return AnlegenLage(titel: titel, aktiv: false, grund: "Die Welt ist nicht vollständig lesbar; angelegt wird erst, wenn sie es wieder ist.") }
        switch w.stand {
        case "läuft": return AnlegenLage(titel: titel, aktiv: true, grund: "")
        case "pausiert": return AnlegenLage(titel: titel, aktiv: false, grund: "Die Welt ist pausiert. Setze sie oben rechts fort, dann lässt sich wieder anlegen.")
        case "gestoppt": return AnlegenLage(titel: titel, aktiv: false, grund: "Die Welt ist gestoppt. Setze sie oben rechts fort, dann lässt sich wieder anlegen.")
        default: return AnlegenLage(titel: titel, aktiv: false, grund: "Die Welt ist \(w.stand); angelegt wird nur in einer Welt, die läuft.")
        }
    }

    /// Eine Welt anlegen: `art` ist `projekt` (mit Ordner) oder `global`. Die neue Welt ist danach
    /// gewaehlt und steht mit ihrer Uebersicht da, die zum Hauptagenten einlaedt.
    ///
    /// Auftrag fernwelten: `maschine` nennt, wo sie entsteht (`peer`, die eigene); ohne Angabe fragt ein echter
    /// Klick nach der globalen Welt, sobald es eine Agent-Maschine gibt, und der Steuerkanal legt hier an.
    @discardableResult
    func weltAnlegen(art: String, ordner: String = "", name: String = "", maschine: String? = nil, echt: Bool) async -> Bool {
        guard let kern else {
            meldung = Meldung(text: "Keine Verbindung zum Kern.", ok: false)
            return false
        }
        if art == "global", maschine == nil, echt, let n = kern.welten, !n.agentMaschinen.isEmpty {
            laufend.insert("neu")
            let stand = await maschinenPruefen(echt: echt)
            laufend.remove("neu")
            let ms = stand.isEmpty ? n.maschinen : stand
            let vorgabe = Self.maschineVorgabe(ms, vorgabe: n.maschineVorgabe)
            let wege = [vorgabe] + ms.filter { $0.name != vorgabe && ($0.eigene || $0.traeger) }.map(\.name)
            weltNeuFrage = WeltNeuFrage(name: "Global", wege: wege, vorgabe: vorgabe,
                                        text: wege.map { Self.maschinenWahlText(ms, auswahl: $0) }.joined(separator: "\n"))
            return false
        }
        var daten: [String: Any] = ["art": art == "global" ? "global" : "projekt"]
        if art != "global" { daten["ordner"] = ordner }
        if !name.isEmpty { daten["name"] = name }
        if let maschine, !maschine.isEmpty { daten["maschine"] = maschine }
        let json = (try? JSONSerialization.data(withJSONObject: daten, options: [.sortedKeys])).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
        laufend.insert("neu")
        defer { laufend.remove("neu") }
        let r = HandlungsAntwort(await kern.invoke("awb:aufgabe", ["welt:neu \(json)", ["echt": echt, "bestaetigt": false]]))
        meldung = Meldung(text: r.meldung, ok: r.ok)
        guard r.ok, !r.pfad.isEmpty else { return r.ok }
        weltGewechselt(r.pfad)
        return true
    }

    /// „Neue Welt in einem Projektordner …": der Ordnerdialog des Systems als Sheet am Fenster,
    /// in dem geklickt wurde -- derselbe Dialog wie beim Plus der Sitzungen (Fenster.swift).
    /// Ohne echten Klick oeffnet sich kein Dialog; der Steuerkanal nennt den Ordner als Text.
    func ordnerWaehlenUndAnlegen(echt: Bool) async {
        guard echt, let fenster = NSApp.keyWindow ?? NSApp.mainWindow, fenster.isVisible else {
            meldung = Meldung(text: "Ohne echten Klick wird kein Ordner-Dialog geöffnet.", ok: false)
            return
        }
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Projektordner für die neue Welt. Sie liegt danach dort unter .werkbank/agents."
        panel.prompt = "Welt hier anlegen"
        // Laeuft die Werkbank mit umgelenktem HOME (Abnahme, mac/bin/abnahme-welten), beginnt der
        // Dialog dort und nicht im echten Benutzerordner; sonst merkt sich das System den letzten Ordner.
        if let home = ProcessInfo.processInfo.environment["HOME"], home != NSHomeDirectory() {
            panel.directoryURL = URL(fileURLWithPath: home, isDirectory: true)
        }
        // Auftrag fernwelten: unter dem Dialog die Maschine, Vorgabe peer, sobald peer als erreichbar belegt ist.
        // Die Probe laeuft neben dem offenen Dialog; die Wahl folgt ihr, bis der Mensch selbst waehlt.
        var wahl: WeltNeuMaschinenWahl?
        if let n = kern?.welten, !n.agentMaschinen.isEmpty {
            let w = WeltNeuMaschinenWahl(maschinen: n.maschinen, vorgabe: n.maschineVorgabe)
            let zubehoer = NSHostingView(rootView: WeltenMaschinenZubehoer(wahl: w))
            zubehoer.frame = NSRect(origin: .zero, size: NSSize(width: 480, height: max(64, zubehoer.fittingSize.height)))
            panel.accessoryView = zubehoer
            panel.isAccessoryViewDisclosed = true
            wahl = w
            Task { @MainActor in
                let stand = await self.maschinenPruefen(echt: echt)
                if !stand.isEmpty { w.aktualisieren(stand) }
            }
        }
        let r = await panel.beginSheetModal(for: fenster)
        guard r == .OK, let pfad = panel.url?.path, !pfad.isEmpty else { return }
        await weltAnlegen(art: "projekt", ordner: pfad, maschine: wahl?.auswahl, echt: true)
    }

    /// Das Anlege-Menue aus einem Knopf der Oberflaeche: leer, aus einer Vorlage oder mit dem
    /// Hinweis, dass eine Beschreibung genuegt (`vorschlagen`). In einer Welt ohne Hauptagenten
    /// steht die Stufe dabei schon auf Hauptagent (`anlegenOeffnen`).
    func anlegenStarten(_ n: WeltenNutzlast, _ w: Welt, vorschlagen: Bool = false, vorlage: String? = nil) {
        anlegenOeffnen(n, w, vorlage: vorlage)
        guard vorschlagen, var a = anlegen else { return }
        let wer = w.hauptagent == nil ? "der Hauptagent" : "der neue Agent"
        a.vorschlagInfo = "Beschreibe in ein, zwei Sätzen, was \(wer) in \(w.name) verantworten soll. „Vorschlag erzeugen“ füllt den Rest; angelegt wird erst mit „Anlegen“."
        // Auftrag agentschat: wer sich vorschlagen laesst, landet im Gespraech; das Formular bleibt einen Klick entfernt.
        a.ansicht = .gespraech
        anlegen = a
    }

    // --- Lage -----------------------------------------------------------------------

    enum Lage: Equatable { case offline(String), ladend, fehler([String]), leer([String]), inhalt }

    static func lage(_ kern: KernVerbindung) -> Lage {
        guard kern.verbunden else { return .offline(kern.kanalFehler ?? "Die Verbindung zum Kern steht nicht.") }
        guard let n = kern.welten else { return .ladend }
        if !n.geladen { return n.fehler.isEmpty ? .ladend : .fehler(n.fehler.map { "\($0.quelle): \($0.text)" }) }
        if n.welten.isEmpty { return .leer(n.fehler.map { "\($0.quelle): \($0.text)" }) }
        return .inhalt
    }
}

// MARK: Das Blatt

/// DAS FENSTER „AGENTS-WELTEN …" (WeltenFenster.swift): Leiste, Mitte und Inspektor
/// in einer NavigationSplitView, Zaehler und Pausenschalter in seiner Symbolleiste.
/// Der Tab „Agents" des Hauptfensters (Fenster.swift) zeigt DIESELBEN Teile an Ort
/// und Stelle: die Leiste statt der Seitenleiste, die Mitte auf der Buehne, den
/// Inspektor rechts, Zaehler und Pausenschalter in seiner Symbolleiste. Beide
/// teilen einen `WeltenZustand`.
struct WeltenBlatt: View {
    let kern: KernVerbindung
    @Bindable var zustand: WeltenZustand

    var body: some View {
        VStack(spacing: 0) {
            if WeltenZustand.lage(kern) == .inhalt, let n = kern.welten, let w = zustand.welt(n) {
                inhalt(n, w)
            } else {
                WeltenLageAnsicht(kern: kern, zustand: zustand)
            }
            Divider()
            AgentsFusszeile(nutzlast: kern.aufgaben)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .weltenRueckfrage(zustand, aktiv: !zustand.rueckfrageImTab)
    }

    private func inhalt(_ n: WeltenNutzlast, _ w: Welt) -> some View {
        NavigationSplitView {
            WeltenLeiste(nutzlast: n, welt: w, zustand: zustand)
                .navigationSplitViewColumnWidth(min: 250, ideal: 290, max: 380)
        } detail: {
            WeltenMitte(nutzlast: n, welt: w, zustand: zustand)
                .inspector(isPresented: $zustand.inspektorOffen) {
                    WeltenInspektor(welt: w, zustand: zustand)
                        .inspectorColumnWidth(min: 270, ideal: 320, max: 460)
                }
        }
        .navigationTitle(w.name)
        .navigationSubtitle(WeltenWorte.herkunft(w))
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                WeltenZaehler(kern: kern, zustand: zustand)
            }
            ToolbarItem(placement: .primaryAction) {
                WeltenPausenschalter(welt: w, agent: nil, zustand: zustand)
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    zustand.inspektorOffen.toggle()
                } label: {
                    Label("Inspektor", systemImage: "sidebar.right")
                }
                .help(zustand.inspektorOffen ? "Inspektor ausblenden" : "Inspektor einblenden")
            }
        }
    }
}

/// Die Rueckfrage vor Stoppen und Zuruecknehmen -- am Fenster wie am Tab dieselbe.
extension View {
    func weltenRueckfrage(_ zustand: WeltenZustand, aktiv: Bool) -> some View {
        alert(zustand.rueckfrage?.text ?? "", isPresented: Binding(get: { aktiv && zustand.rueckfrage != nil }, set: { if !$0, aktiv { zustand.rueckfrage = nil } }), presenting: zustand.rueckfrage) { rf in
            // Ein Umzug loescht nichts (die alte Ablage bleibt umbenannt liegen): kein destruktiver Knopf.
            if rf.handlung == "umziehen" {
                Button("Umziehen") { Task { await zustand.bestaetigen() } }.keyboardShortcut(.defaultAction)
            } else if rf.handlung == "vergessen" {
                // Auftrag agentsform: nur der Eintrag der Liste geht; Ordner und Welt bleiben.
                Button("Entfernen") { Task { await zustand.bestaetigen() } }.keyboardShortcut(.defaultAction)
            } else {
                Button(rf.handlung == "stoppen" ? "Stoppen" : "Zurücknehmen", role: .destructive) { Task { await zustand.bestaetigen() } }
            }
            Button("Abbrechen", role: .cancel) { zustand.rueckfrage = nil }
        } message: { rf in
            Text(rf.warnungen.isEmpty ? "Das geschieht über die Datenbibliothek der Welt und steht danach in ihren Dateien." : rf.warnungen.joined(separator: "\n"))
        }
        .alert("Wo soll die globale Welt liegen?", isPresented: Binding(get: { aktiv && zustand.weltNeuFrage != nil }, set: { if !$0, aktiv { zustand.weltNeuFrage = nil } }), presenting: zustand.weltNeuFrage) { f in
            ForEach(f.wege, id: \.self) { m in
                if m == f.vorgabe {
                    Button("\(WeltenWorte.aufMaschine(m, satzanfang: true)) anlegen") { zustand.weltNeuFrage = nil; Task { await zustand.weltAnlegen(art: "global", maschine: m, echt: true) } }
                        .keyboardShortcut(.defaultAction)
                } else {
                    Button("\(WeltenWorte.aufMaschine(m, satzanfang: true)) anlegen") { zustand.weltNeuFrage = nil; Task { await zustand.weltAnlegen(art: "global", maschine: m, echt: true) } }
                }
            }
            Button("Abbrechen", role: .cancel) { zustand.weltNeuFrage = nil }
        } message: { f in
            Text(f.text)
        }
    }
}

/// Was an der Stelle der Welten steht, solange es keine zu zeigen gibt: ohne Kern,
/// beim ersten Lesen, bei unlesbaren Welten und ohne jede Welt -- mit dem naechsten Schritt.
struct WeltenLageAnsicht: View {
    let kern: KernVerbindung
    @Bindable var zustand: WeltenZustand

    var body: some View {
        switch WeltenZustand.lage(kern) {
        case .offline(let grund):
            leer("Kern nicht erreichbar", "bolt.horizontal.circle", "Ohne Kern keine Welten. \(grund) Die Werkbank verbindet sich von selbst neu.", id: "welten-offline")
        case .ladend:
            WeltenLadend()
        case .fehler(let f):
            leer("Welten nicht lesbar", "exclamationmark.triangle", f.joined(separator: "\n"), id: "welten-fehler")
        case .leer(let f):
            // Keine Welt: die Einladung erklaert, was eine Welt ist, und legt eine an (WeltenUebersicht.swift).
            WeltenEinladung(kern: kern, zustand: zustand, fehler: f)
        case .inhalt:
            Color.clear
        }
    }

    private func leer(_ titel: String, _ symbol: String, _ text: String, id: String) -> some View {
        ContentUnavailableView {
            Label(titel, systemImage: symbol)
        } description: {
            Text(text)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityIdentifier(id)
    }
}

// MARK: Maschinen (Auftrag fernwelten)

/// Die Wahl der Maschine unter dem Ordnerdialog „Neue Welt": die Vorgabe folgt der Probe, bis der Mensch waehlt.
@MainActor
@Observable
final class WeltNeuMaschinenWahl {
    var maschinen: [WeltMaschine]
    var auswahl: String
    let vorgabe: String
    private(set) var beruehrt = false

    init(maschinen: [WeltMaschine], vorgabe: String) {
        self.maschinen = maschinen
        self.vorgabe = vorgabe
        auswahl = WeltenZustand.maschineVorgabe(maschinen, vorgabe: vorgabe)
    }

    func waehlen(_ name: String) {
        auswahl = name
        beruehrt = true
    }

    func aktualisieren(_ neu: [WeltMaschine]) {
        maschinen = neu
        if !beruehrt { auswahl = WeltenZustand.maschineVorgabe(neu, vorgabe: vorgabe) }
    }

    /// Die eigene Maschine und die Agent-Maschinen mit Traeger, die Vorgabe zuerst.
    var wege: [WeltMaschine] {
        let passend = maschinen.filter { $0.eigene || $0.traeger }
        return passend.filter { $0.standard } + passend.filter { !$0.standard }
    }
}

/// Unter dem Ordnerdialog: „Maschine  [peer | Mac]" und ein Satz, was die Wahl bedeutet.
struct WeltenMaschinenZubehoer: View {
    @Bindable var wahl: WeltNeuMaschinenWahl

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            LabeledContent("Maschine") {
                Picker("Maschine", selection: Binding(get: { wahl.auswahl }, set: { wahl.waehlen($0) })) {
                    ForEach(wahl.wege) { m in Text(WeltenWorte.maschine(m.name)).tag(m.name) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                .accessibilityIdentifier("welten-neu-maschine")
            }
            Text(WeltenZustand.maschinenWahlText(wahl.maschinen, auswahl: wahl.auswahl))
                .font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .frame(width: 480, alignment: .leading)
    }
}

/// Ueber der Mitte, solange der Welt etwas fehlt, damit Agenten antworten: Maschine nicht erreichbar oder kein Traeger.
struct WeltenMaschinenBand: View {
    let nutzlast: WeltenNutzlast
    let welt: Welt
    @Bindable var zustand: WeltenZustand

    var body: some View {
        if let hinweis = WeltenWorte.maschinenHinweis(welt) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Zustandspunkt(art: welt.verbindungOk ? .ruhig : .will)
                Text(hinweis).font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                if !welt.fern, !welt.traegerMoeglich, let ziel = nutzlast.agentMaschinen.first(where: { $0.name == nutzlast.maschineVorgabe }) ?? nutzlast.agentMaschinen.first {
                    Button("Nach \(WeltenWorte.maschine(ziel.name)) umziehen …") { Task { await zustand.umziehen(welt, nach: ziel.name, echt: true) } }
                        .controlSize(.small)
                        .disabled(zustand.laufend.contains("umziehen"))
                        .help("Die Ablage zieht auf \(ziel.name); dort bekommt die Welt ihren Träger. Vorher fragt die Werkbank zurück.")
                        .accessibilityIdentifier("welten-band-umziehen")
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 7)
            .background(welt.verbindungOk ? AnyShapeStyle(.quaternary.opacity(0.5)) : AnyShapeStyle(Color.orange.opacity(0.10)))
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("welten-maschinen-band")
            Divider()
        }
    }
}

// MARK: Die Teile fuer den Tab „Agents" (Fenster.swift)

/// Links statt der Seitenleiste: die Leiste der gewaehlten Welt. Ohne Welt bleibt die
/// Spalte leer bis auf den Hinweis; was fehlt, sagt die Mitte.
struct WeltenLeisteSpalte: View {
    let kern: KernVerbindung
    @Bindable var zustand: WeltenZustand

    var body: some View {
        if WeltenZustand.lage(kern) == .inhalt, let n = kern.welten, let w = zustand.welt(n) {
            WeltenLeiste(nutzlast: n, welt: w, zustand: zustand)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Text("Agents").font(.headline)
                switch WeltenZustand.lage(kern) {
                case .ladend:
                    Text("Die Welten werden gelesen.").font(.callout).foregroundStyle(.secondary)
                case .leer:
                    Text("Noch keine Welt. Eine Welt gehört zu einem Projektordner oder gilt global; ihre Agenten stehen dann hier.")
                        .font(.callout).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    WeltenNeuMenue(kern: kern, zustand: zustand, titel: "Neue Welt …")
                default:
                    Text("Keine Welt zu zeigen; die Mitte sagt, warum.").font(.callout).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .accessibilityIdentifier("welten-leiste-leer")
        }
    }
}

/// Die Buehne: Gespraech, Tickets oder Anlege-Menue der Welt, darunter die Fusszeile wie bisher.
struct WeltenMitteSpalte: View {
    let kern: KernVerbindung
    @Bindable var zustand: WeltenZustand

    var body: some View {
        VStack(spacing: 0) {
            if WeltenZustand.lage(kern) == .inhalt, let n = kern.welten, let w = zustand.welt(n) {
                WeltenMitte(nutzlast: n, welt: w, zustand: zustand)
            } else {
                WeltenLageAnsicht(kern: kern, zustand: zustand)
            }
            Divider()
            AgentsFusszeile(nutzlast: kern.aufgaben)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .weltenRueckfrage(zustand, aktiv: zustand.rueckfrageImTab)
    }
}

/// Rechts: Profil, Protokoll, Gedaechtnis und Skills des gewaehlten Agenten, sonst die Welt.
struct WeltenInspektorSpalte: View {
    let kern: KernVerbindung
    @Bindable var zustand: WeltenZustand

    var body: some View {
        if WeltenZustand.lage(kern) == .inhalt, let n = kern.welten, let w = zustand.welt(n) {
            WeltenInspektor(welt: w, zustand: zustand)
        } else {
            // Keine leere Spalte ohne Erklaerung: was hier spaeter steht.
            VStack(alignment: .leading, spacing: 0) {
                Text("Inspektor").font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 24, alignment: .leading)
                    .padding(10)
                Divider()
                Text("Hier stehen Profil, Protokoll, Gedächtnis und Skills des Agenten, den du links wählst, bei Übersicht und Kanal die Angaben zur Welt.")
                    .font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(14)
                Spacer(minLength: 0)
            }
            .accessibilityIdentifier("welten-inspektor-leer")
        }
    }
}

/// Der Zaehler der Welt („3 brauchen dich · 1 läuft · 6 Tickets offen") fuer eine Symbolleiste.
struct WeltenZaehler: View {
    let kern: KernVerbindung
    @Bindable var zustand: WeltenZustand

    var body: some View {
        // Plan Satz 35: „braucht dich", Triage, laufende und offene Tickets getrennt.
        let w = kern.welten.flatMap { zustand.welt($0) }
        Text(w.map(WeltenWorte.zaehlerGetrennt) ?? "")
            .font(.callout).monospacedDigit().foregroundStyle(.secondary)
            .fixedSize()
            .accessibilityLabel(w.map { "Welt \($0.name): \(WeltenWorte.zaehlerGetrennt($0))" } ?? "Keine Welt")
            .accessibilityIdentifier("welten-zaehler")
    }
}

/// Der Pausenschalter der gewaehlten Welt fuer die Symbolleiste des Hauptfensters.
struct WeltenWeltPause: View {
    let kern: KernVerbindung
    @Bindable var zustand: WeltenZustand

    var body: some View {
        if let n = kern.welten, let w = zustand.welt(n) {
            WeltenPausenschalter(welt: w, agent: nil, zustand: zustand)
        } else {
            Color.clear.frame(width: 1, height: 1)
        }
    }
}

/// Platzhalter in der Form des kommenden Inhalts, statt eines Rades ueber allem.
struct WeltenLadend: View {
    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            VStack(alignment: .leading, spacing: 14) {
                ForEach(0..<6, id: \.self) { i in
                    HStack(spacing: 10) {
                        Circle().fill(.quaternary).frame(width: 28, height: 28)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Agentenname").font(.body)
                            Text("Zustand und Spezialgebiet").font(.callout)
                        }
                    }
                    .padding(.leading, i > 2 ? 18 : 0)
                }
                Spacer()
            }
            .frame(width: 280, alignment: .leading)
            .padding(16)
            Divider()
            VStack(alignment: .leading, spacing: 12) {
                Text("Kanal der Welt").font(.title3)
                ForEach(0..<4, id: \.self) { _ in Text("Eine Nachricht im Kanal, adressiert an einen Agenten").padding(10) }
                Spacer()
            }
            .padding(16)
        }
        .redacted(reason: .placeholder)
        .accessibilityLabel("Die Welten werden gelesen")
        .accessibilityIdentifier("welten-ladend")
    }
}

// MARK: Pausenschalter

struct WeltenPausenschalter: View {
    let welt: Welt
    let agent: WeltAgent?
    @Bindable var zustand: WeltenZustand

    private var stand: String { agent?.stand ?? welt.stand }
    private var gestoppt: Bool { stand == "gestoppt" }

    var body: some View {
        Group {
            if gestoppt || stand == "archiviert" {
                HStack(spacing: 6) {
                    Zustandspunkt(art: .aus)
                    Text(stand == "archiviert" ? "archiviert" : "gestoppt").foregroundStyle(.secondary)
                    if gestoppt {
                        Button("Fortsetzen") { Task { await zustand.schalten(welt, agent: agent?.id, laeuft: true, echt: true) } }
                    }
                }
            } else {
                Picker(agent == nil ? "Welt" : "Agent", selection: Binding(
                    get: { stand == "pausiert" ? "pausiert" : "laeuft" },
                    set: { neu in Task { await zustand.schalten(welt, agent: agent?.id, laeuft: neu == "laeuft", echt: true) } })) {
                    Text("läuft").tag("laeuft")
                    Text("pausiert").tag("pausiert")
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                .disabled(zustand.laufend.contains("pausieren") || zustand.laufend.contains("fortsetzen"))
                .help(agent == nil ? "Pause hält jeden Agenten der Welt am nächsten Checkpoint an; nichts Neues startet." : "Pause hält \(agent!.name) am nächsten Checkpoint an.")
            }
        }
        .accessibilityLabel(agent == nil ? "Welt \(welt.name): \(stand)" : "\(agent!.name): \(stand)")
        .accessibilityIdentifier(agent == nil ? "welten-pause" : "welten-agent-pause")
    }
}

// MARK: Die Leiste

struct WeltenLeiste: View {
    let nutzlast: WeltenNutzlast
    let welt: Welt
    @Bindable var zustand: WeltenZustand

    var body: some View {
        VStack(spacing: 0) {
            kopf
            List(selection: Binding(get: { zustand.auswahl }, set: { neu in
                if let neu, !neu.hasPrefix("team:"), !neu.hasPrefix("kopf:"), !neu.hasPrefix("hinweis:") { zustand.waehlen(neu, welt) }
            })) {
                ForEach(zustand.zeilen(welt)) { z in zeile(z) }
            }
            .listStyle(.sidebar)
            .accessibilityIdentifier("welten-leiste")
        }
    }

    /// DER KOPF DER LEISTE (Auftrag agentsux Nr. 1, Befund des Nutzers: „Ich sehe nicht, wie ich
    /// neue Agents oder Workplaces für mehrere Agents erstelle"). Oben die Welt als Menue mit den
    /// Eintraegen zum Anlegen einer neuen, darunter ein beschrifteter Knopf „Agent anlegen" statt
    /// eines Plus von 13 Punkt. Geht er nicht, steht der Grund als Satz darunter.
    private var kopf: some View {
        let lage = WeltenZustand.anlegenLage(welt)
        return VStack(alignment: .leading, spacing: 8) {
            WeltenWahlMenue(nutzlast: nutzlast, welt: welt, zustand: zustand)
            WeltenAgentAnlegenKnopf(nutzlast: nutzlast, welt: welt, zustand: zustand)
            if !lage.aktiv {
                Text(lage.grund)
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("welten-anlegen-grund")
            }
            Picker("Darstellung", selection: $zustand.darstellung) {
                ForEach(WeltenZustand.Darstellung.allCases, id: \.self) { Text($0.titel).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .help("Baum: Teams mit ihren Leitern. Liste: nach Handlungsbedarf.")
            .accessibilityLabel("Darstellung: Baum oder Liste")
            .accessibilityIdentifier("welten-darstellung")
            if !welt.fehler.isEmpty || !welt.konsistent {
                Label(welt.fehler.isEmpty ? "Stand während eines Schreibvorgangs gelesen" : welt.fehler.joined(separator: "\n"), systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(.secondary).lineLimit(4)
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 6)
    }

    @ViewBuilder
    private func zeile(_ z: WeltenZustand.Zeile) -> some View {
        switch z {
        case .uebersicht:
            HStack(spacing: 9) {
                Image(systemName: "square.grid.2x2")
                    .font(.body).foregroundStyle(.secondary)
                    .frame(width: 32, height: 28)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Übersicht").fontWeight(.semibold)
                    Text(WeltenUebersichtWorte.leistenzeile(welt)).font(.callout).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 4)
            }
            .padding(.vertical, 2)
            .tag(WeltenZustand.uebersicht)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("welten-zeile-uebersicht")
        case .hinweis(let t):
            Text(t).font(.callout).foregroundStyle(.secondary)
                .padding(.leading, 4)
                .selectionDisabled()
        case .kanal:
            let n = zustand.ungelesen(welt, schluessel: WeltenZustand.kanal)
            HStack(spacing: 9) {
                Image(systemName: "bubble.left.and.bubble.right")
                    .font(.body).foregroundStyle(.secondary)
                    .frame(width: 32, height: 28)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Kanal").fontWeight(.semibold)
                    Text(welt.kanalGesamt == 1 ? "1 Nachricht" : "\(welt.kanalGesamt) Nachrichten").font(.callout).foregroundStyle(.secondary)
                }
                Spacer(minLength: 4)
                WeltenZahl(n: n)
            }
            .padding(.vertical, 2)
            .tag(WeltenZustand.kanal)
            .accessibilityLabel("Kanal, \(n) ungelesen")
        case .kopf(let t):
            Text(t).font(.callout.weight(.semibold)).foregroundStyle(.secondary)
                .padding(.top, 6)
                .selectionDisabled()
                .accessibilityAddTraits(.isHeader)
        case .team(let name, let offen, let aktiv, let mitLeiter):
            HStack(spacing: 6) {
                Button { zustand.umklappen(name) } label: {
                    Image(systemName: "chevron.right")
                        .rotationEffect(.degrees(offen ? 90 : 0))
                        .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        .frame(width: 14)
                }
                .buttonStyle(.plain)
                .disabled(zustand.darstellung != .baum)
                .accessibilityLabel(offen ? "Team \(name) einklappen" : "Team \(name) aufklappen")
                Text("Team \(WeltenWorte.team(name))").font(.callout.weight(.medium)).foregroundStyle(.secondary)
                Spacer(minLength: 4)
                if !offen || !mitLeiter {
                    Text(aktiv == 1 ? "1 arbeitet" : "\(aktiv) arbeiten").font(.caption).monospacedDigit().foregroundStyle(.secondary)
                        .help("Mitglieder, die gerade arbeiten oder ein Ergebnis haben")
                }
            }
            .selectionDisabled()
        case .agent(let id, let ebene, let teamZusatz):
            if let a = welt.agent(id) {
                WeltenAgentZeile(agent: a, welt: welt, teamZusatz: teamZusatz, ungelesen: zustand.ungelesen(welt, agent: id))
                    .padding(.leading, CGFloat(ebene) * 20)
                    .tag("agent:\(id)")
            }
        }
    }
}

struct WeltenAgentZeile: View {
    let agent: WeltAgent
    let welt: Welt
    let teamZusatz: Bool
    let ungelesen: Int

    var body: some View {
        HStack(spacing: 9) {
            WeltenFigur(agent: agent, groesse: 32)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 5) {
                    Text(agent.name).fontWeight(.semibold).lineLimit(1)
                    if agent.istHauptagent {
                        Text("Hauptagent").font(.caption).foregroundStyle(.secondary)
                    } else if agent.stufe == "teamleiter" {
                        Text("Leiter").font(.caption).foregroundStyle(.secondary)
                    }
                    if teamZusatz, let t = agent.team {
                        Text(WeltenWorte.team(t)).font(.caption).foregroundStyle(.tertiary).lineLimit(1)
                    }
                }
                HStack(spacing: 4) {
                    Zustandspunkt(art: WeltenWorte.punkt(agent: agent), basis: 7)
                    WeltenLebenWort(agent: agent)
                    if !agent.spezialgebiet.isEmpty {
                        Text("· \(agent.spezialgebiet)").foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                .font(.callout)
            }
            Spacer(minLength: 4)
            WeltenZahl(n: ungelesen)
        }
        .padding(.vertical, 2)
        .help(WeltenWorte.leben(agent) ?? agent.zustandText)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(agent.name), \(WeltenWorte.stufe(agent.stufe)), \(WeltenWorte.leben(agent) ?? agent.zustandText), \(agent.spezialgebiet)\(ungelesen > 0 ? ", \(ungelesen) ungelesen" : "")")
    }
}

/// Die Ungelesen-Zahl an einer Zeile der Leiste -- nur, wenn es etwas zu lesen gibt.
struct WeltenZahl: View {
    let n: Int
    var body: some View {
        if n > 0 {
            Text("\(n)")
                .font(.caption.weight(.semibold)).monospacedDigit()
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6).padding(.vertical, 1)
                .background(Capsule().fill(Color.secondary.opacity(0.18)))
                .accessibilityLabel("\(n) ungelesen")
        }
    }
}

/// Die Figur eines Agenten aus Agentenfigur.swift -- Art und Team aus dem Profil, Zustand vom Kern,
/// darum der Ring des Lebenszeichens (Auftrag agentaktiv), wo die Welt einen Traeger hat.
struct WeltenFigur: View {
    let agent: WeltAgent
    var groesse: CGFloat = 32
    var body: some View {
        Agentenfigur(rolle: agent.figurRolle.isEmpty ? agent.id : agent.figurRolle, stufe: agent.stufe, name: agent.id,
                     team: agent.figurTeam, zustand: agent.figur, groesse: groesse, arten: agent.arten)
            .overlay { FigurRingAnsicht(ring: agent.ring, groesse: groesse) }
    }
}

/// Das Wort des Lebenszeichens neben dem Punkt. Solange ein Zug laeuft oder eine Nachricht auf den Stand
/// „nicht gestartet" zulaeuft, stellt eine Uhr es jede Sekunde neu; sonst steht es still.
struct WeltenLebenWort: View {
    let agent: WeltAgent
    /// Ohne Lebenszeichen: statt des Zustandsworts der Zustandstext des Kerns („arbeitet an …").
    var ohneLeben: String? = nil

    var body: some View {
        if agent.leben?.stand == "arbeitet" {
            TimelineView(.periodic(from: .now, by: 1)) { tl in Text(WeltenWorte.agentWort(agent, jetzt: tl.date)) }
        } else if WeltenWorte.leben(agent) == nil, let ohneLeben {
            Text(ohneLeben)
        } else {
            Text(WeltenWorte.agentWort(agent))
        }
    }
}

/// Der Stand direkt unter der eigenen Nachricht (Auftrag agentaktiv): zugestellt, arbeitet, nicht gestartet.
struct WeltenAntwortStandZeile: View {
    let agent: WeltAgent

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { tl in
            if let st = WeltenWorte.antwort(agent, jetzt: tl.date) {
                HStack(spacing: 5) {
                    Spacer(minLength: 60)
                    Zustandspunkt(art: st.art == "arbeitet" ? .laeuft : st.art == "zugestellt" ? .ruhig : .will, basis: 6)
                    Text(st.text)
                        .font(.caption)
                        .foregroundStyle(st.art == "zugestellt" || st.art == "arbeitet" ? AnyShapeStyle(.secondary) : AnyShapeStyle(Color.orange))
                }
                .padding(.top, -6)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("welten-antwortstand")
            }
        }
    }
}

// MARK: Die Mitte

struct WeltenMitte: View {
    let nutzlast: WeltenNutzlast
    let welt: Welt
    @Bindable var zustand: WeltenZustand

    private var agent: WeltAgent? { welt.agent(zustand.agentId) }
    private var direktchat: WeltDirektchat? {
        zustand.gespraech == WeltenZustand.einzel ? nil : welt.direktchats.first { $0.id == zustand.gespraech }
    }

    var body: some View {
        VStack(spacing: 0) {
            WeltenMaschinenBand(nutzlast: nutzlast, welt: welt, zustand: zustand)
            if zustand.anlegen != nil {
                WeltenAnlegen(welt: welt, zustand: zustand)
            } else if zustand.auswahl == WeltenZustand.uebersicht {
                WeltenUebersicht(nutzlast: nutzlast, welt: welt, zustand: zustand)
            } else {
                gespraeche
            }
        }
        // Eine Fernwelt, die hier steht, liest der Kern oefter (Auftrag fernwelten).
        .task(id: welt.pfad) { await zustand.gewaehltMelden(welt) }
    }

    private var gespraeche: some View {
        VStack(spacing: 0) {
            kopf
            Divider()
            if let m = zustand.meldung { meldung(m) }
            fragenLeiste
            switch zustand.reiter {
            case .chat:
                chat
            case .tickets:
                WeltenTickets(welt: welt, zustand: zustand)
            }
        }
        .background(Color(nsColor: .textBackgroundColor))
        // DIE MITTE GIBT NACH (gemessen 14.09. am Belegbild): ohne Mindestbreite 0
        // meldete eine lange Kopfzeile ihre volle Breite als Minimum, und die
        // Aufteilung schob Leiste und Inspektor aus dem Fenster.
        .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
        .onChange(of: zustand.gespraechSchluessel()) { zustand.gesehen(welt) }
        .onChange(of: zustand.nachrichten(welt, schluessel: zustand.gespraechSchluessel()).count) { zustand.gesehen(welt) }
        .onAppear { zustand.gesehen(welt) }
    }

    // --- Kopfzeile ------------------------------------------------------------------

    private var kopf: some View {
        HStack(alignment: .center, spacing: 12) {
            if let a = agent {
                WeltenFigur(agent: a, groesse: 44)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Text(a.name).font(.title3.weight(.semibold))
                        Text(WeltenWorte.stufe(a.stufe) + (a.team.map { " · Team \(WeltenWorte.team($0))" } ?? "")).foregroundStyle(.secondary)
                    }
                    HStack(spacing: 6) {
                        Text(a.modell).font(.callout.monospaced()).lineLimit(1).truncationMode(.middle)
                        Text("·")
                        Text(WeltenWorte.maschine(a.maschine))
                        Text("·")
                        Zustandspunkt(art: WeltenWorte.punkt(agent: a), basis: 7)
                        WeltenLebenWort(agent: a, ohneLeben: a.zustandText).lineLimit(1)
                        if WeltenWorte.leben(a) != nil, a.zustand == "arbeitet", a.zustandText != "arbeitet" {
                            Text("· \(a.zustandText)").lineLimit(1)
                        }
                    }
                    .font(.callout).foregroundStyle(.secondary)
                }
            } else {
                Image(systemName: "bubble.left.and.bubble.right").font(.title2).foregroundStyle(.secondary).frame(width: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Kanal").font(.title3.weight(.semibold))
                    Text("Alle Agenten von \(welt.name) · \(welt.kanalGesamt == 1 ? "1 Nachricht" : "\(welt.kanalGesamt) Nachrichten") · adressiert, nur Adressierte werden geweckt")
                        .font(.callout).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer(minLength: 12)
            if let a = agent, !a.direktchats.isEmpty, zustand.reiter == .chat {
                Picker("Gespräch", selection: $zustand.gespraech) {
                    Text("Mit dir").tag(WeltenZustand.einzel)
                    ForEach(welt.direktchats.filter { a.direktchats.contains($0.id) }) { c in
                        Text("Direkt mit " + c.teilnehmer.filter { $0 != a.id }.map { welt.anzeigename($0) }.joined(separator: ", ")).tag(c.id)
                    }
                }
                .labelsHidden()
                .fixedSize()
                .help("Gespräch mit dir oder ein Direktchat zwischen Agenten")
                .accessibilityIdentifier("welten-gespraech")
            }
            Picker("Reiter", selection: $zustand.reiter) {
                ForEach(WeltenZustand.Reiter.allCases, id: \.self) { Text($0.titel).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            .accessibilityLabel("Chat oder Tickets")
            .accessibilityIdentifier("welten-reiter")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private func meldung(_ m: WeltenZustand.Meldung) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: m.ok ? "checkmark.circle" : "exclamationmark.triangle")
                .foregroundStyle(m.ok ? Color.green : Color.orange)
                .accessibilityHidden(true)
            Text(m.ok ? m.text : "Nicht ausgeführt: \(m.text)").font(.callout)
            Spacer(minLength: 8)
            Button("Ausblenden") { zustand.meldung = nil }.buttonStyle(.borderless).controlSize(.small)
        }
        .padding(.horizontal, 16).padding(.vertical, 6)
        .background(.quaternary.opacity(0.5))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("welten-meldung")
    }

    /// Offene Fragen bleiben sichtbar, auch wenn gerade ein anderes Gespraech steht (Plan Abschnitt 13).
    @ViewBuilder
    private var fragenLeiste: some View {
        let offen = welt.offeneFragen
        let imHauptchat = zustand.agentId == welt.hauptagent && zustand.gespraech == WeltenZustand.einzel && zustand.reiter == .chat
        if !offen.isEmpty, !imHauptchat {
            HStack(spacing: 8) {
                Zustandspunkt(art: .will)
                Text(offen.count == 1 ? "Eine offene Frage von \(welt.anzeigename(offen[0].von)): „\(offen[0].text)“" : "\(offen.count) offene Fragen von \(welt.anzeigename(offen[0].von))")
                    .font(.callout).lineLimit(1)
                Spacer(minLength: 8)
                if let h = welt.hauptagent {
                    Button("Ansehen") {
                        zustand.waehlen("agent:\(h)", welt)
                        zustand.reiter = .chat
                    }
                    .controlSize(.small)
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 7)
            .background(Color.orange.opacity(0.10))
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("welten-fragenleiste")
        }
    }

    // --- Chat ---------------------------------------------------------------------

    @ViewBuilder
    private var chat: some View {
        let eintraege = chatEintraege()
        ScrollViewReader { leser in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    if eintraege.isEmpty {
                        ContentUnavailableView {
                            Label(leerTitel, systemImage: "bubble.left")
                        } description: {
                            Text(leerText)
                        }
                        .padding(.top, 40)
                    }
                    ForEach(eintraege, id: \.id) { e in
                        switch e {
                        case .nachricht(let n):
                            WeltenNachrichtKarte(nachricht: n, welt: welt, imKanal: agent == nil, zustand: zustand)
                            // Auftrag agentaktiv: unter der eigenen, noch unbeantworteten Nachricht, bis die Antwort da ist.
                            if let a = agent, direktchat == nil, a.antwort?.nachricht == n.id { WeltenAntwortStandZeile(agent: a) }
                        case .frage(let f): WeltenFrageKarte(frage: f, welt: welt, zustand: zustand)
                        }
                    }
                    Color.clear.frame(height: 1).id("ende")
                }
                .padding(16)
                .frame(maxWidth: 820)
                .frame(maxWidth: .infinity)
            }
            .onAppear { leser.scrollTo("ende", anchor: .bottom) }
            .onChange(of: eintraege.count) { leser.scrollTo("ende", anchor: .bottom) }
        }
        Divider()
        eingabe
    }

    enum Eintrag { case nachricht(WeltNachricht), frage(WeltFrage)
        var id: String {
            switch self {
            case .nachricht(let n): "n:\(n.id)"
            case .frage(let f): "f:\(f.id)"
            }
        }
    }

    private func chatEintraege() -> [Eintrag] {
        if let c = direktchat { return c.nachrichten.map { .nachricht($0) } }
        if let a = agent {
            return a.einzelchat.compactMap { e in
                if let n = e.nachricht { return .nachricht(n) }
                return welt.frage(e.frage).map { .frage($0) }
            }
        }
        return welt.kanal.map { .nachricht($0) }
    }

    private var leerTitel: String { agent == nil ? "Noch still im Kanal" : "Noch kein Gespräch" }
    private var leerText: String {
        if let a = agent {
            return a.istHauptagent
                ? "Schreib \(a.name) einen Auftrag; daraus wird ein Ticket oder eine Antwort."
                : "Du kannst \(a.name) schreiben. Antworten und Berichte erscheinen hier; Fragen gehen den Dienstweg über Teamleiter und Hauptagent."
        }
        if welt.agenten.isEmpty {
            return "Hier reden die Agenten der Welt miteinander, sobald es welche gibt. Lege zuerst den Hauptagenten an: links über „Hauptagent anlegen“ oder in der Übersicht."
        }
        return "Hier reden die Agenten der Welt miteinander. Jede Nachricht ist adressiert; du kannst mitschreiben."
    }

    @ViewBuilder
    private var eingabe: some View {
        if let c = direktchat {
            Label("Direktchat zwischen \(c.teilnehmer.map { welt.anzeigename($0) }.joined(separator: " und ")) -- nur zum Lesen.", systemImage: "eye")
                .font(.callout).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16).padding(.vertical, 10)
        } else {
            let k = zustand.gespraechSchluessel()
            HStack(alignment: .bottom, spacing: 8) {
                if agent == nil {
                    HStack(spacing: 4) {
                        Text("An").foregroundStyle(.secondary).fixedSize()
                        TextField("@name, @team, @alle", text: Binding(get: { zustand.adressen(welt) }, set: { zustand.adressfeld = $0 }))
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 170)
                            .accessibilityLabel("Adressaten")
                            .accessibilityIdentifier("welten-adressfeld")
                        Menu {
                            ForEach(WeltenAdressen.auswahl(welt), id: \.adresse) { a in
                                Button(a.titel) { zustand.adressfeld = a.adresse }
                            }
                        } label: {
                            Image(systemName: "at")
                        }
                        .menuStyle(.borderlessButton)
                        .fixedSize()
                        .help("Adressat wählen")
                    }
                }
                TextField(platzhalter, text: Binding(get: { zustand.entwuerfe[k] ?? "" }, set: { zustand.entwuerfe[k] = $0 }), axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(1...6)
                    .onSubmit { Task { await zustand.senden(welt, echt: true) } }
                    .accessibilityIdentifier("welten-eingabe")
                Button("Senden") { Task { await zustand.senden(welt, echt: true) } }
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled((zustand.entwuerfe[k] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || zustand.laufend.contains("senden"))
            }
            .padding(.horizontal, 16).padding(.vertical, 10)
        }
    }

    private var platzhalter: String {
        if let a = agent { return a.istHauptagent ? "Auftrag oder Nachricht an \(a.name)" : "Nachricht an \(a.name)" }
        return "Nachricht in den Kanal"
    }
}

struct WeltenNachrichtKarte: View {
    let nachricht: WeltNachricht
    let welt: Welt
    let imKanal: Bool
    @Bindable var zustand: WeltenZustand

    var body: some View {
        let mensch = nachricht.vonMensch
        HStack(alignment: .top, spacing: 8) {
            if mensch { Spacer(minLength: 60) }
            if !mensch, let a = welt.agent(nachricht.von) {
                WeltenFigur(agent: a, groesse: 28)
            }
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Text(welt.anzeigename(nachricht.von)).font(.callout.weight(.semibold))
                    if imKanal || nachricht.art == "ticket-ergebnis" {
                        Text("an \(nachricht.an.map { welt.anzeigename($0) }.joined(separator: ", "))").font(.callout).foregroundStyle(.secondary)
                    }
                    Text(WeltenWorte.alter(nachricht.zeit)).font(.caption).foregroundStyle(.tertiary).help(AgentsWorte.uhrzeit(nachricht.zeit))
                }
                if nachricht.art == "ticket-ergebnis" {
                    Label("Ergebnis", systemImage: "checkmark.seal").font(.caption.weight(.medium)).foregroundStyle(.secondary)
                }
                if let m = nachricht.markierung {
                    Label(m == "frage" ? "Frage an dich" : "Ergebnis für dich", systemImage: m == "frage" ? "questionmark.bubble" : "checkmark.seal")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(nachricht.offenFuerMensch ? Color.orange : Color.secondary)
                }
                Text(nachricht.text).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                if let t = welt.ticket(nachricht.ticket) {
                    Button {
                        zustand.reiter = .tickets
                        zustand.ticketFilter = "alle"
                        zustand.ticketAuswahl = t.id
                    } label: {
                        Label("Ticket „\(t.titel)“", systemImage: "ticket").font(.caption)
                    }
                    .buttonStyle(.borderless)
                    .help("Ticket öffnen")
                }
                if nachricht.markierung != nil {
                    if nachricht.offenFuerMensch {
                        Button("Zur Kenntnis genommen") { Task { await zustand.quittieren(welt, zustellung: nachricht.id, echt: true) } }
                            .controlSize(.small)
                            .disabled(zustand.laufend.contains("quittieren"))
                            .accessibilityIdentifier("welten-quittieren-\(nachricht.id)")
                    } else {
                        Label("zur Kenntnis genommen", systemImage: "checkmark").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 9)
            .background(RoundedRectangle(cornerRadius: 12).fill(mensch ? Color.accentColor.opacity(0.14) : Color(nsColor: .controlBackgroundColor)))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(nachricht.markierung != nil && nachricht.offenFuerMensch ? Color.orange.opacity(0.6)
                : Color(nsColor: .separatorColor).opacity(mensch ? 0 : 1), lineWidth: nachricht.markierung != nil && nachricht.offenFuerMensch ? 1.5 : 1))
            if !mensch { Spacer(minLength: 60) }
        }
        .accessibilityElement(children: .combine)
    }
}

struct WeltenFrageKarte: View {
    let frage: WeltFrage
    let welt: Welt
    @Bindable var zustand: WeltenZustand

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Zustandspunkt(art: frage.offen ? .will : .ruhig)
                Text(frage.offen ? "Frage von \(welt.anzeigename(frage.von))" : frage.stand == "beantwortet" ? "Beantwortete Frage" : "Zurückgenommene Frage")
                    .font(.callout.weight(.semibold))
                Text(WeltenWorte.alter(frage.gestellt)).font(.caption).foregroundStyle(.tertiary)
                if let t = welt.ticket(frage.ticket) {
                    Text("zu „\(t.titel)“").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Text(frage.text).font(.body).fixedSize(horizontal: false, vertical: true)
            if frage.offen {
                FlussLayout(abstand: 6) {
                    ForEach(frage.optionenGeordnet, id: \.self) { o in
                        if o == frage.empfehlung {
                            Button("\(o) (Empfehlung)") { Task { await zustand.antworten(welt, frage: frage.id, text: o, echt: true) } }
                                .buttonStyle(.borderedProminent)
                        } else {
                            Button(o) { Task { await zustand.antworten(welt, frage: frage.id, text: o, echt: true) } }
                        }
                    }
                }
                HStack(spacing: 8) {
                    TextField("Eigene Antwort", text: Binding(get: { zustand.antwortEntwuerfe[frage.id] ?? "" }, set: { zustand.antwortEntwuerfe[frage.id] = $0 }))
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { Task { await zustand.antworten(welt, frage: frage.id, text: zustand.antwortEntwuerfe[frage.id] ?? "", echt: true) } }
                    Button("Antworten") { Task { await zustand.antworten(welt, frage: frage.id, text: zustand.antwortEntwuerfe[frage.id] ?? "", echt: true) } }
                        .disabled((zustand.antwortEntwuerfe[frage.id] ?? "").trimmingCharacters(in: .whitespaces).isEmpty)
                    Button("Zurücknehmen …", role: .destructive) { Task { await zustand.zuruecknehmen(welt, frage: frage.id, echt: true) } }
                }
                .disabled(zustand.laufend.contains("antworten"))
            } else if let a = frage.antwort {
                Label("\(welt.anzeigename(a.von)): \(a.text)", systemImage: "checkmark.circle").font(.callout)
            } else if let r = frage.ruecknahme {
                Label("Zurückgenommen\(r.grund.map { ": \($0)" } ?? "")", systemImage: "arrow.uturn.backward.circle").font(.callout).foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(nsColor: .controlBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(frage.offen ? Color.orange.opacity(0.6) : Color(nsColor: .separatorColor), lineWidth: frage.offen ? 1.5 : 1))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(frage.offen ? "Offene Frage: \(frage.text)" : "Frage: \(frage.text), \(frage.stand)")
        .accessibilityIdentifier("welten-frage-\(frage.id)")
    }
}

/// Knoepfe, die umbrechen, wenn die Breite nicht reicht.
struct FlussLayout: Layout {
    var abstand: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let breite = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, zeile: CGFloat = 0, weiteste: CGFloat = 0
        for s in subviews {
            let g = s.sizeThatFits(.unspecified)
            if x > 0, x + g.width > breite { y += zeile + abstand; x = 0; zeile = 0 }
            x += g.width + abstand
            zeile = max(zeile, g.height)
            weiteste = max(weiteste, x - abstand)
        }
        return CGSize(width: min(weiteste, breite), height: y + zeile)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, zeile: CGFloat = 0
        for s in subviews {
            let g = s.sizeThatFits(.unspecified)
            if x > bounds.minX, x + g.width > bounds.maxX { y += zeile + abstand; x = bounds.minX; zeile = 0 }
            s.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(g))
            x += g.width + abstand
            zeile = max(zeile, g.height)
        }
    }
}

// MARK: Tickets

/// EIN ABZEICHEN an der Ticketkarte: Art, Priorität, Frist-Ampel. Neben jeder Farbe steht
/// ein Wort (Hausregel), und die Fläche kommt aus der Systemfarbe, nicht aus eigenen Tokens.
struct WeltenAbzeichen: View {
    let text: String
    var hervorgehoben = false
    var hilfe: String = ""

    var body: some View {
        Text(text)
            .font(.caption.weight(hervorgehoben ? .semibold : .regular))
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(RoundedRectangle(cornerRadius: 5).fill(hervorgehoben ? Color.accentColor.opacity(0.16) : Color.secondary.opacity(0.12)))
            .foregroundStyle(hervorgehoben ? Color.accentColor : Color.secondary)
            .help(hilfe.isEmpty ? text : hilfe)
            .accessibilityLabel(hilfe.isEmpty ? text : "\(text), \(hilfe)")
    }
}

/// Die Frist-Ampel (Plan Satz 31): Punkt und Wort, grau, gelb ab einem Tag vorher, rot ab Ablauf.
struct WeltenAmpel: View {
    let stand: String
    let frist: String

    var body: some View {
        if !stand.isEmpty {
            HStack(spacing: 4) {
                Zustandspunkt(art: WeltenWorte.ampelPunkt(stand), basis: 7)
                Text(WeltenWorte.ampel(stand)).font(.caption)
            }
            .foregroundStyle(stand == "rot" ? Color.orange : Color.secondary)
            .help(frist.isEmpty ? WeltenWorte.ampel(stand) : "\(WeltenWorte.ampel(stand)): \(AgentsWorte.uhrzeit(frist))")
            .accessibilityElement(children: .combine)
            .accessibilityLabel(WeltenWorte.ampel(stand))
        }
    }
}

struct WeltenTickets: View {
    let welt: Welt
    @Bindable var zustand: WeltenZustand

    var body: some View {
        // Ein offenes Formular hat Vorrang vor dem Detail: „Neues Ticket" fuehrt immer in die
        // Liste mit dem Formular darueber, gleich woher der Klick kam.
        if let t = welt.ticket(zustand.ticketAuswahl), zustand.neuesTicket == nil {
            WeltenTicketDetail(ticket: t, welt: welt, zustand: zustand)
        } else {
            liste
        }
    }

    private var liste: some View {
        let tickets = zustand.tickets(welt)
        return VStack(spacing: 0) {
            kopf(tickets.count)
            // Das Formular steht IM Blatt, nicht in einem Sheet: so bleibt die Liste daneben
            // lesbar, und ein Belegbild des Fensters zeigt es mit (Auftrag tickets4 F).
            if let e = zustand.neuesTicket {
                WeltenTicketFormular(welt: welt, entwurf: e, zustand: zustand)
                    .frame(maxWidth: 900)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 16)
                Divider()
            }
            if zustand.ticketAnsicht == .board {
                WeltenTicketBoard(welt: welt, tickets: tickets, zustand: zustand)
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        if tickets.isEmpty { leer }
                        ForEach(tickets) { t in
                            zeile(t, alle: tickets)
                        }
                    }
                    .padding(.horizontal, 16).padding(.bottom, 16)
                    .frame(maxWidth: 900)
                    .frame(maxWidth: .infinity)
                }
            }
        }
    }

    private func kopf(_ anzahl: Int) -> some View {
        HStack(spacing: 10) {
            Picker("Stand", selection: $zustand.ticketFilter) {
                Text("Offen").tag("offen")
                Text("Alle").tag("alle")
                Text("Triage").tag("triage")
                Divider()
                ForEach(WeltenWorte.ticketStaende, id: \.self) { Text($0).tag($0) }
            }
            .fixedSize()
            .accessibilityIdentifier("welten-ticketfilter")
            Picker("Ansicht", selection: $zustand.ticketAnsicht) {
                ForEach(WeltenZustand.TicketAnsicht.allCases, id: \.self) { Text($0.titel).tag($0) }
            }
            .pickerStyle(.segmented)
            .fixedSize()
            .accessibilityIdentifier("welten-ticketansicht")
            Text(anzahl == 1 ? "1 Ticket" : "\(anzahl) Tickets").font(.callout).foregroundStyle(.secondary)
            Spacer()
            Button {
                zustand.neuesTicket = WeltenZustand.TicketEntwurf(an: zustand.agentId ?? "")
            } label: {
                Label("Neues Ticket", systemImage: "plus")
            }
            .accessibilityIdentifier("welten-neues-ticket")
        }
        .padding(.horizontal, 16).padding(.vertical, 8)
    }

    private var leer: some View {
        ContentUnavailableView {
            Label("Keine Tickets", systemImage: "ticket")
        } description: {
            switch zustand.ticketFilter {
            case "offen": Text("Nichts offen. „Alle“ zeigt auch abgenommene Tickets.")
            case "triage": Text("Das Backlog ist leer. Ein Ticket ohne Adressat landet hier, bis der Hauptagent es annimmt.")
            default: Text("Kein Ticket in diesem Stand.")
            }
        }
        .padding(.top, 30)
    }

    /// In der Triage lässt sich die Reihenfolge ziehen (Plan Satz 44); sonst ist die Zeile nur ein Knopf.
    @ViewBuilder
    private func zeile(_ t: WeltTicket, alle: [WeltTicket]) -> some View {
        let karte = Button { zustand.ticketAuswahl = t.id } label: {
            WeltenTicketKarte(ticket: t, welt: welt, ziehbar: zustand.ticketFilter == "triage")
        }
        .buttonStyle(.plain)
        if zustand.ticketFilter == "triage" {
            karte
                .draggable(t.id) { WeltenTicketKarte(ticket: t, welt: welt, ziehbar: true).frame(width: 420) }
                .dropDestination(for: String.self) { kennungen, _ in
                    guard let gezogen = kennungen.first, gezogen != t.id else { return false }
                    var reihe = alle.map(\.id)
                    guard let von = reihe.firstIndex(of: gezogen), let nach = reihe.firstIndex(of: t.id) else { return false }
                    reihe.remove(at: von)
                    reihe.insert(gezogen, at: nach)
                    Task { await zustand.backlogOrdnen(welt, reihe: reihe, echt: true) }
                    return true
                }
        } else {
            karte
        }
    }
}

/// EINE TICKETKARTE (Auftrag tickets4 A, Plan Sätze 35, 36, 39, 44, 48): Art, Priorität,
/// Frist-Ampel, Stand, Alter, Adressat mit Figur, Absender und -- je nach Stand -- die
/// Weckbedingung, der Grund, der Grundcode, der Verweis oder der Prüfer.
struct WeltenTicketKarte: View {
    let ticket: WeltTicket
    let welt: Welt
    var ziehbar = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            if ziehbar {
                Image(systemName: "line.3.horizontal").font(.callout).foregroundStyle(.tertiary).frame(width: 14)
                    .accessibilityHidden(true)
            }
            if let a = welt.agent(ticket.bearbeiter ?? ticket.adressaten.first) {
                WeltenFigur(agent: a, groesse: 32)
            } else {
                Image(systemName: "person.3").frame(width: 32).foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(ticket.titel).fontWeight(.semibold).lineLimit(1)
                    WeltenAbzeichen(text: WeltenWorte.kind(ticket.kind), hilfe: WeltenWorte.kindErklaerung(ticket.kind))
                    WeltenAbzeichen(text: WeltenWorte.prioritaet(ticket.prioritaet),
                                    hervorgehoben: WeltenWorte.prioritaetHervor(ticket.prioritaet),
                                    hilfe: ticket.prioritaetText.isEmpty ? WeltenWorte.prioritaetText(ticket.prioritaet) : ticket.prioritaetText)
                    WeltenAmpel(stand: ticket.ampel, frist: ticket.grenzen["frist"] ?? "")
                }
                Text(WeltenTicketWorte.zeile(ticket, welt: welt)).font(.callout).foregroundStyle(.secondary).lineLimit(1)
                if let zusatz = WeltenTicketWorte.standzeile(ticket, welt: welt) {
                    Text(zusatz).font(.callout).foregroundStyle(.secondary).lineLimit(2).fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 4) {
                HStack(spacing: 5) {
                    Zustandspunkt(art: WeltenWorte.punkt(ticket: ticket.stand))
                    Text(ticket.stand)
                }
                .font(.callout)
                if !ticket.wartetAuf.isEmpty {
                    Label("wartet auf \(ticket.wartetAuf.count)", systemImage: "link").font(.caption).foregroundStyle(.secondary)
                }
            }
            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary).padding(.top, 2)
        }
        .padding(12)
        .contentShape(Rectangle())
        .background(RoundedRectangle(cornerRadius: 10).fill(Color(nsColor: .controlBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color(nsColor: .separatorColor)))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(WeltenTicketWorte.vorlesen(ticket, welt: welt))
        .accessibilityIdentifier("welten-ticket-\(ticket.id)")
    }
}

/// Die Sätze der Ticketkarte -- für Bildschirm und Auskunft dieselben.
enum WeltenTicketWorte {
    /// Zeile zwei: an wen, von wem, wie alt, und bei Eltern der Kinderzähler.
    static func zeile(_ t: WeltTicket, welt w: Welt) -> String {
        var teile: [String] = []
        let an = t.adressaten.map { w.anzeigename($0) } + (t.team.map { ["Team \(WeltenWorte.team($0))"] } ?? [])
        if !an.isEmpty { teile.append("an \(an.joined(separator: ", "))") }
        if let b = t.bearbeiter, !t.adressaten.contains(b) || t.adressaten.count > 1 { teile.append("bearbeitet von \(w.anzeigename(b))") }
        teile.append("von \(w.anzeigename(t.absender))")
        teile.append(WeltenWorte.alter(t.angelegt))
        if t.kinderGesamt > 0 { teile.append("\(t.kinderAbgenommen) von \(t.kinderGesamt) abgenommen") }
        return teile.joined(separator: " · ")
    }

    /// Zeile drei: was der Stand erklären muss (Auftrag tickets4 A). nil, wenn nichts zu sagen ist.
    static func standzeile(_ t: WeltTicket, welt w: Welt) -> String? {
        var teile: [String] = []
        if t.stand == "wartet", let p = t.geparkt {
            let weck = p.bis.map { "bis \(AgentsWorte.uhrzeit($0))" } ?? p.auf.map { id in "auf „\(w.ticket(id)?.titel ?? id)“" } ?? "ohne Weckbedingung"
            teile.append("wartet \(weck)\(p.grund.isEmpty ? "" : ": \(p.grund)")")
        }
        if t.stand == "braucht dich", let f = t.flagge {
            teile.append("braucht dich: \(f.grund.isEmpty ? "ohne Grund" : f.grund)")
        }
        if t.stand == "verworfen", let v = t.verworfen {
            let dup = v.duplikatVon.map { id in " von „\(w.ticket(id)?.titel ?? id)“" } ?? ""
            teile.append("verworfen: \(WeltenWorte.verwerfGrund(v.code))\(dup)")
        } else if let d = t.duplikatVon {
            teile.append("Duplikat von „\(w.ticket(d)?.titel ?? d)“")
        }
        if t.stand == "in Prüfung", let r = t.pruefung {
            teile.append("prüft: \(w.anzeigename(r.pruefer))")
        }
        if let e = t.eltern {
            teile.append("gehört zu „\(w.ticket(e)?.titel ?? e)“ (\(e))")
        }
        return teile.isEmpty ? nil : teile.joined(separator: " · ")
    }

    /// Was VoiceOver von der Karte liest.
    static func vorlesen(_ t: WeltTicket, welt w: Welt) -> String {
        var teile = ["Ticket \(t.titel)", WeltenWorte.kind(t.kind), WeltenWorte.prioritaet(t.prioritaet), t.stand]
        if !t.ampel.isEmpty { teile.append(WeltenWorte.ampel(t.ampel)) }
        if let z = standzeile(t, welt: w) { teile.append(z) }
        return teile.joined(separator: ", ")
    }

    /// Die Messung im Detail (Plan Satz 50): Durchlaufzeit, Züge, Alter.
    static func messung(_ t: WeltTicket) -> String {
        ["Durchlaufzeit \(WeltenWorte.dauerWort(t.durchlaufzeit))",
         t.zuege == 1 ? "1 Zug" : "\(t.zuege) Züge",
         "Alter \(WeltenWorte.dauerWort(t.alterSekunden))"].joined(separator: " · ")
    }
}

/// DAS BOARD (Plan Satz 47): Spalten in Bearbeitungsrichtung, je Vorhaben eine Swimlane,
/// Zähler am Spaltenkopf und die WIP-Grenze der Welt über „läuft".
struct WeltenTicketBoard: View {
    let welt: Welt
    let tickets: [WeltTicket]
    @Bindable var zustand: WeltenZustand

    private let spaltenbreite: CGFloat = 220

    var body: some View {
        let spuren = WeltenZustand.board(welt, tickets: tickets)
        ScrollView([.horizontal, .vertical]) {
            VStack(alignment: .leading, spacing: 16) {
                kopfzeile
                if spuren.isEmpty {
                    Text("Kein Ticket in dieser Auswahl.").font(.callout).foregroundStyle(.secondary).padding(.leading, 4)
                }
                ForEach(spuren) { spur in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(spur.titel).font(.headline).accessibilityAddTraits(.isHeader)
                        HStack(alignment: .top, spacing: 12) {
                            ForEach(Array(WeltenWorte.boardSpalten.enumerated()), id: \.offset) { i, spalte in
                                spaltenInhalt(spur.spalten[i], spalte: spalte)
                            }
                        }
                    }
                    .accessibilityIdentifier("welten-board-spur-\(spur.id)")
                }
            }
            .padding(16)
        }
        .accessibilityIdentifier("welten-board")
    }

    private var kopfzeile: some View {
        HStack(alignment: .bottom, spacing: 12) {
            ForEach(WeltenWorte.boardSpalten, id: \.self) { spalte in
                let anzahl = tickets.filter { WeltenWorte.boardStaende(spalte).contains($0.stand) }.count
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 5) {
                        Zustandspunkt(art: WeltenWorte.punkt(ticket: spalte), basis: 7)
                        Text(spalte).font(.callout.weight(.semibold)).lineLimit(1)
                        Text("\(anzahl)").font(.callout).monospacedDigit().foregroundStyle(.secondary)
                    }
                    if spalte == "läuft" {
                        let w = WeltenZustand.wipText(welt)
                        Text(w.text)
                            .font(.caption).monospacedDigit()
                            .foregroundStyle(w.rot ? Color.orange : Color.secondary)
                            .help("Weiche WIP-Grenze der Welt: laufende und geparkte Tickets gegen die Grenze")
                            .accessibilityLabel("WIP-Grenze \(w.text)\(w.rot ? ", überschritten" : "")")
                            .accessibilityIdentifier("welten-board-wip")
                    }
                }
                .frame(width: spaltenbreite, alignment: .leading)
            }
        }
    }

    private func spaltenInhalt(_ inhalt: [WeltTicket], spalte: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(inhalt) { t in
                Button { zustand.ticketAuswahl = t.id } label: { kachel(t) }
                    .buttonStyle(.plain)
            }
            if inhalt.isEmpty {
                Text("–").font(.caption).foregroundStyle(.tertiary).frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(width: spaltenbreite, alignment: .topLeading)
    }

    private func kachel(_ t: WeltTicket) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(t.titel).font(.callout.weight(.medium)).lineLimit(2).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 5) {
                WeltenAbzeichen(text: WeltenWorte.kind(t.kind), hilfe: WeltenWorte.kindErklaerung(t.kind))
                WeltenAbzeichen(text: WeltenWorte.prioritaet(t.prioritaet), hervorgehoben: WeltenWorte.prioritaetHervor(t.prioritaet),
                                hilfe: t.prioritaetText.isEmpty ? WeltenWorte.prioritaetText(t.prioritaet) : t.prioritaetText)
                WeltenAmpel(stand: t.ampel, frist: t.grenzen["frist"] ?? "")
            }
            Text(t.bearbeiter.map { welt.anzeigename($0) } ?? t.adressaten.first.map { welt.anzeigename($0) } ?? "ohne Adressat")
                .font(.caption).foregroundStyle(.secondary).lineLimit(1)
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .controlBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(nsColor: .separatorColor)))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(WeltenTicketWorte.vorlesen(t, welt: welt))
        .accessibilityIdentifier("welten-board-ticket-\(t.id)")
    }
}

struct WeltenTicketDetail: View {
    let ticket: WeltTicket
    let welt: Welt
    @Bindable var zustand: WeltenZustand

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Button { zustand.ticketAuswahl = nil } label: { Label("Alle Tickets", systemImage: "chevron.left") }
                    .buttonStyle(.borderless)
                titelzeile
                if let v = ticket.skillVorschlag {
                    WeltenSkillVorschlagKarte(ticket: ticket, vorschlag: v, welt: welt, zustand: zustand)
                }
                auftrag
                if !ticket.fertigPunkte.isEmpty { fertigListe }
                if !zwischenstaende.isEmpty { zwischenstandKarte }
                if let e = ticket.ergebnis { ergebnisKarte(e) }
                if let r = ticket.pruefung, r.notiz != nil || ticket.stand == "in Prüfung" { pruefKarte(r) }
                if let a = ticket.abnahme { abnahmeKarte(a) }
                if let v = ticket.verworfen { verwurfKarte(v) }
                handlungen
                messungKarte
                verlaufKarte
                let nachrichten = welt.kanal.filter { $0.ticket == ticket.id }
                if !nachrichten.isEmpty {
                    karte("Im Kanal") {
                        ForEach(nachrichten) { n in
                            Text("\(n.id) · \(welt.anzeigename(n.von)) an \(n.an.map { welt.anzeigename($0) }.joined(separator: ", ")): \(n.text)")
                                .font(.callout).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
            .padding(16)
            .frame(maxWidth: 820, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityIdentifier("welten-ticket-detail")
    }

    // --- Kopf und Auftrag -----------------------------------------------------------

    private var titelzeile: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(ticket.titel).font(.title2.weight(.semibold))
                HStack(spacing: 5) { Zustandspunkt(art: WeltenWorte.punkt(ticket: ticket.stand)); Text(ticket.stand) }.font(.callout)
            }
            HStack(spacing: 6) {
                WeltenAbzeichen(text: WeltenWorte.kind(ticket.kind), hilfe: WeltenWorte.kindErklaerung(ticket.kind))
                WeltenAbzeichen(text: WeltenWorte.prioritaet(ticket.prioritaet), hervorgehoben: WeltenWorte.prioritaetHervor(ticket.prioritaet),
                                hilfe: ticket.prioritaetText.isEmpty ? WeltenWorte.prioritaetText(ticket.prioritaet) : ticket.prioritaetText)
                WeltenAmpel(stand: ticket.ampel, frist: ticket.grenzen["frist"] ?? "")
                if let z = ticket.zyklus { WeltenAbzeichen(text: z, hilfe: "Zyklus, in dem das Ticket geplant ist") }
                Text(ticket.id).font(.caption).monospaced().foregroundStyle(.tertiary).textSelection(.enabled)
            }
            if let zusatz = WeltenTicketWorte.standzeile(ticket, welt: welt) {
                Text(zusatz).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var auftrag: some View {
        karte("Auftrag") {
            // Ein Skill-Vorschlag traegt den Diff auch im Ziel; der steht schon in der Karte darueber.
            feld("Ziel", ticket.skillVorschlag == nil ? ticket.ziel : (ticket.ziel.components(separatedBy: "\n\n").first ?? ticket.ziel))
            feld("Fertig heißt", ticket.fertig)
            feld("Adressiert an", (ticket.adressaten.map { welt.anzeigename($0) } + (ticket.team.map { ["Team \(WeltenWorte.team($0))"] } ?? [])).joined(separator: ", "))
            if let b = ticket.bearbeiter { feld("Bearbeiter", welt.anzeigename(b)) }
            feld("Absender", welt.anzeigename(ticket.absender))
            feld("Angelegt", AgentsWorte.uhrzeit(ticket.angelegt))
            if !ticket.abhaengig.isEmpty {
                feld("Hängt ab von", ticket.abhaengig.map { id in
                    let t = welt.ticket(id)
                    return "„\(t?.titel ?? id)“ (\(t?.stand ?? "unbekannt"))"
                }.joined(separator: ", "))
            }
            if !ticket.grenzen.isEmpty { feld("Grenzen", ticket.grenzen.sorted { $0.key < $1.key }.map { "\($0.key): \($0.value)" }.joined(separator: ", ")) }
            if let e = ticket.eltern { verweis("Eltern", e) }
            if let o = ticket.herkunft { verweis("Entdeckt bei", o) }
            if !kinder.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text("Kinder").foregroundStyle(.secondary).frame(width: 110, alignment: .leading)
                        Text("\(ticket.kinderAbgenommen) von \(ticket.kinderGesamt) abgenommen")
                    }
                    .font(.callout)
                    ForEach(kinder) { k in
                        Button { zustand.ticketAuswahl = k.id } label: {
                            HStack(spacing: 6) {
                                Zustandspunkt(art: WeltenWorte.punkt(ticket: k.stand), basis: 7)
                                Text("„\(k.titel)“ (\(k.stand))").font(.callout)
                            }
                        }
                        .buttonStyle(.link)
                        .padding(.leading, 120)
                    }
                }
            }
        }
    }

    private var kinder: [WeltTicket] {
        welt.tickets.filter { $0.eltern == ticket.id }.sorted { $0.angelegt != $1.angelegt ? $0.angelegt < $1.angelegt : $0.id < $1.id }
    }

    private func verweis(_ name: String, _ id: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(name).foregroundStyle(.secondary).frame(width: 110, alignment: .leading)
            Button("„\(welt.ticket(id)?.titel ?? id)“") { zustand.ticketAuswahl = id }
                .buttonStyle(.link)
        }
        .font(.callout)
    }

    // --- Fertig-Liste, Zwischenstände, Ergebnis, Prüfung, Abnahme ---------------------

    private var fertigListe: some View {
        let stand = ticket.fertigStand
        return karte("Fertig-Liste (\(stand.erledigt) von \(stand.gesamt))") {
            ForEach(ticket.fertigPunkte) { p in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Image(systemName: p.erledigt ? "checkmark.square" : "square")
                        .foregroundStyle(p.erledigt ? Color.accentColor : Color.secondary)
                        .accessibilityHidden(true)
                    Text(p.text).font(.callout).strikethrough(p.erledigt, color: .secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if let von = p.von, p.erledigt {
                        Text("· \(welt.anzeigename(von))").font(.caption).foregroundStyle(.secondary)
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(p.text), \(p.erledigt ? "abgehakt" : "offen")")
            }
            Text("Abgehakt wird vom Bearbeiter; das Ergebnis geht erst, wenn alles steht.")
                .font(.caption).foregroundStyle(.tertiary)
        }
    }

    private var zwischenstaende: [WeltTicketEreignis] { ticket.verlauf.filter { $0.ereignis == "zwischenstand" } }

    private var zwischenstandKarte: some View {
        karte("Zwischenstände") {
            ForEach(Array(zwischenstaende.enumerated()), id: \.offset) { _, e in
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(welt.anzeigename(e.von)) · \(AgentsWorte.uhrzeit(e.zeit))").font(.caption).foregroundStyle(.secondary)
                    Text(e.text).font(.callout).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func ergebnisKarte(_ e: (text: String, commit: String?, von: String, zeit: String)) -> some View {
        karte("Ergebnis") {
            Text(e.text).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
            Text("\(welt.anzeigename(e.von)) · \(AgentsWorte.uhrzeit(e.zeit))\(e.commit.map { " · Commit \($0)" } ?? "")").font(.callout).foregroundStyle(.secondary)
        }
    }

    private func pruefKarte(_ r: (pruefer: String, revision: Int, angefordertVon: String, notiz: String?, urteil: String?)) -> some View {
        karte("Prüfung") {
            feld("Prüfer", welt.anzeigename(r.pruefer))
            feld("Angefordert von", welt.anzeigename(r.angefordertVon))
            if let u = r.urteil { feld("Urteil", WeltenWorte.urteil(u)) }
            if let n = r.notiz {
                Text(n).font(.callout).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
            } else {
                Text("Die Prüfnotiz steht noch aus.").font(.callout).foregroundStyle(.secondary)
            }
        }
    }

    private func abnahmeKarte(_ a: (von: String, zeit: String, bemerkung: String?, grund: String?)) -> some View {
        karte(ticket.stand == "zurückgegeben" ? "Zurückgegeben" : "Abnahme") {
            Text("\(welt.anzeigename(a.von)) · \(AgentsWorte.uhrzeit(a.zeit))\(a.grund.map { " · \(WeltenWorte.abnahmeGrund($0))" } ?? "")").font(.callout)
            if let b = a.bemerkung { Text(b).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
            if ticket.stand == "abgenommen" { rueckgabe }
        }
    }

    private func verwurfKarte(_ v: (code: String, bemerkung: String?, duplikatVon: String?)) -> some View {
        karte("Verworfen") {
            feld("Grund", WeltenWorte.verwerfGrund(v.code))
            if let b = v.bemerkung { feld("Bemerkung", b) }
            if let d = v.duplikatVon { verweis("Duplikat von", d) }
        }
    }

    private var messungKarte: some View {
        karte("Messung") {
            Text(WeltenTicketWorte.messung(ticket)).font(.callout)
                .accessibilityIdentifier("welten-ticket-messung")
            if let z = ticket.zyklus { feld("Zyklus", z) }
        }
    }

    private var verlaufKarte: some View {
        karte("Verlauf") {
            ForEach(Array(ticket.verlauf.enumerated()), id: \.offset) { _, e in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(AgentsWorte.uhrzeit(e.zeit)).font(.callout).monospacedDigit().foregroundStyle(.secondary).frame(width: 90, alignment: .leading)
                    Text("\(welt.anzeigename(e.von)): \(WeltenWorte.ereignis(e.ereignis))\(e.text.isEmpty ? "" : " -- \(e.text)")").font(.callout)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    // --- Die Handlungen des Menschen (Auftrag tickets4 B) -----------------------------

    /// Welche Handlungen der Kern dem Menschen an diesem Ticket erlaubt (WeltenZustand).
    private var moegliche: [WeltenZustand.TicketHandlung] { WeltenZustand.moeglicheHandlungen(ticket) }

    private func handlungstitel(_ h: WeltenZustand.TicketHandlung) -> String {
        switch h {
        case .rueckgabe: "Zurückgeben …"
        case .verwerfen: "Verwerfen …"
        case .annehmen: "Aus der Triage annehmen …"
        case .umadressieren: "Umadressieren …"
        case .grenzen: "Grenzen ändern …"
        case .pruefer: "Prüfer setzen …"
        }
    }

    @ViewBuilder
    private var handlungen: some View {
        if let e = zustand.ticketHandlung, e.ticket == ticket.id {
            karte(handlungstitel(e.handlung).replacingOccurrences(of: " …", with: "")) {
                handlungsformular(e)
            }
        } else if !moegliche.isEmpty {
            karte("Handlungen") {
                FlussLayout(abstand: 8) {
                    ForEach(moegliche, id: \.rawValue) { h in
                        Button(handlungstitel(h)) { zustand.handlungOeffnen(h, ticket, welt: welt) }
                            .accessibilityIdentifier("welten-handlung-\(h.rawValue)")
                    }
                }
                Text("Jede Handlung geht als Mensch an den Kern; was der Kern dem Menschen nicht erlaubt, steht hier nicht.")
                    .font(.caption).foregroundStyle(.tertiary)
            }
        }
    }

    @ViewBuilder
    private func handlungsformular(_ e: WeltenZustand.TicketHandlungEntwurf) -> some View {
        let bindung = Binding(get: { zustand.ticketHandlung ?? e }, set: { zustand.ticketHandlung = $0 })
        VStack(alignment: .leading, spacing: 10) {
            switch e.handlung {
            case .rueckgabe:
                EmptyView()
            case .verwerfen:
                Picker("Grund", selection: bindung.grund) {
                    ForEach(WeltenWorte.verwerfGruende, id: \.self) { Text(WeltenWorte.verwerfGrund($0)).tag($0) }
                }
                .accessibilityIdentifier("welten-verwerfen-grund")
                TextField("Bemerkung (freiwillig)", text: bindung.bemerkung, axis: .vertical).lineLimit(1...3)
                if e.grund == "duplikat" {
                    Picker("Duplikat von", selection: bindung.duplikat) {
                        Text("bitte wählen").tag("")
                        ForEach(welt.tickets.filter { $0.id != ticket.id }) { t in Text(t.titel).tag(t.id) }
                    }
                    .accessibilityIdentifier("welten-verwerfen-duplikat")
                }
            case .annehmen:
                adressatWahl(bindung)
                artUndPrioritaet(bindung)
                punkteFeld(bindung)
            case .umadressieren:
                adressatWahl(bindung)
                TextField("Grund", text: bindung.grund).accessibilityIdentifier("welten-umadressieren-grund")
            case .grenzen:
                TextField("Frist (ISO, etwa 2026-09-25T17:00:00Z)", text: bindung.frist).accessibilityIdentifier("welten-grenzen-frist")
                TextField("Höchste Rundenzahl", text: bindung.runden).accessibilityIdentifier("welten-grenzen-runden")
            case .pruefer:
                Picker("Prüfer", selection: bindung.pruefer) {
                    Text("bitte wählen").tag("")
                    ForEach(welt.agenten.filter { $0.id != ticket.bearbeiter && $0.stand == "aktiv" }) { a in Text(a.name).tag(a.id) }
                }
                .accessibilityIdentifier("welten-pruefer-wahl")
                Text("Der Prüfer bekommt einen Zug ohne Schreibwerkzeuge mit dem Diff des genannten Commits.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            HStack(spacing: 8) {
                Spacer()
                Button("Abbrechen") { zustand.handlungSchliessen() }
                Button(knopftitel(e.handlung)) { Task { await ausfuehren(e.handlung) } }
                    .buttonStyle(.borderedProminent)
                    .disabled(!bereit(e))
                    .accessibilityIdentifier("welten-handlung-ausfuehren")
            }
        }
        .textFieldStyle(.roundedBorder)
    }

    private func adressatWahl(_ b: Binding<WeltenZustand.TicketHandlungEntwurf>) -> some View {
        Picker("Adressat", selection: b.an) {
            Text("bitte wählen").tag("")
            ForEach(welt.teams) { t in Text("Team \(WeltenWorte.team(t.name))").tag("team:\(t.name)") }
            ForEach(welt.liste, id: \.self) { id in Text(welt.anzeigename(id)).tag(id) }
        }
        .accessibilityIdentifier("welten-handlung-adressat")
    }

    private func artUndPrioritaet(_ b: Binding<WeltenZustand.TicketHandlungEntwurf>) -> some View {
        Group {
            Picker("Art", selection: b.kind) {
                ForEach(WeltenWorte.ticketArten, id: \.self) { Text(WeltenWorte.kind($0)).tag($0) }
            }
            .accessibilityIdentifier("welten-handlung-art")
            Picker("Priorität", selection: b.prioritaet) {
                ForEach(0..<4) { p in Text(WeltenWorte.prioritaet(p)).tag(p) }
            }
            .accessibilityIdentifier("welten-handlung-prioritaet")
        }
    }

    private func punkteFeld(_ b: Binding<WeltenZustand.TicketHandlungEntwurf>) -> some View {
        WeltenPunkteFeld(punkte: b.fertigPunkte, kennung: "welten-handlung-punkt")
    }

    private func knopftitel(_ h: WeltenZustand.TicketHandlung) -> String {
        switch h {
        case .rueckgabe: "Zurückgeben"
        case .verwerfen: "Verwerfen"
        case .annehmen: "Annehmen"
        case .umadressieren: "Umadressieren"
        case .grenzen: "Grenzen setzen"
        case .pruefer: "Prüfung anfordern"
        }
    }

    private func bereit(_ e: WeltenZustand.TicketHandlungEntwurf) -> Bool {
        switch e.handlung {
        case .rueckgabe: return !zustand.rueckgabeText.trimmingCharacters(in: .whitespaces).isEmpty
        case .verwerfen: return e.grund != "duplikat" || !e.duplikat.isEmpty
        case .annehmen: return !e.an.isEmpty
        case .umadressieren: return !e.an.isEmpty && !e.grund.trimmingCharacters(in: .whitespaces).isEmpty
        case .grenzen: return !e.frist.isEmpty || !e.runden.isEmpty
        case .pruefer: return !e.pruefer.isEmpty
        }
    }

    private func ausfuehren(_ h: WeltenZustand.TicketHandlung) async {
        switch h {
        case .rueckgabe: await zustand.zurueckgeben(welt, ticket: ticket.id, echt: true)
        case .verwerfen: await zustand.verwerfen(welt, echt: true)
        case .annehmen: await zustand.annehmen(welt, echt: true)
        case .umadressieren: await zustand.umadressieren(welt, echt: true)
        case .grenzen: await zustand.grenzenSetzen(welt, echt: true)
        case .pruefer: await zustand.prueferSetzen(welt, echt: true)
        }
    }

    /// Ein abgenommenes Ticket zurueckgeben (Plan Abschnitt 5): Bemerkung, dann an den Bearbeiter.
    @ViewBuilder
    private var rueckgabe: some View {
        if zustand.rueckgabeOffen == ticket.id {
            VStack(alignment: .leading, spacing: 8) {
                Divider()
                Text("Zurückgeben an \(ticket.bearbeiter.map { welt.anzeigename($0) } ?? "die Adressaten")").font(.callout.weight(.semibold))
                TextField("Was fehlt, in einem Satz", text: $zustand.rueckgabeText, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(2...4)
                    .accessibilityIdentifier("welten-rueckgabe-text")
                HStack(spacing: 8) {
                    Spacer()
                    Button("Abbrechen") {
                        zustand.rueckgabeOffen = nil
                        zustand.rueckgabeText = ""
                    }
                    Button("Zurückgeben") { Task { await zustand.zurueckgeben(welt, ticket: ticket.id, echt: true) } }
                        .buttonStyle(.borderedProminent)
                        .disabled(zustand.rueckgabeText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || zustand.laufend.contains("zurueckgeben"))
                }
            }
        } else {
            Button("Zurückgeben …") {
                zustand.rueckgabeOffen = ticket.id
                zustand.rueckgabeText = ""
            }
            .help("Das abgenommene Ticket geht mit deiner Bemerkung an den Bearbeiter zurück.")
            .accessibilityIdentifier("welten-zurueckgeben")
        }
    }

    private func karte<Inhalt: View>(_ titel: String, @ViewBuilder _ inhalt: () -> Inhalt) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(titel).font(.headline)
            inhalt()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color(nsColor: .controlBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color(nsColor: .separatorColor)))
    }

    private func feld(_ name: String, _ wert: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(name).foregroundStyle(.secondary).frame(width: 110, alignment: .leading)
            Text(wert.isEmpty ? "–" : wert).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
        }
        .font(.callout)
    }
}

/// Eine Liste freier Punkte mit Hinzufügen und Entfernen (Fertig-Punkte, Definition of Done).
struct WeltenPunkteFeld: View {
    @Binding var punkte: [String]
    let kennung: String
    var titel = "Fertig-Punkte"
    var platzhalter = "Ein abhakbarer Punkt"

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(titel).font(.callout.weight(.semibold))
                Spacer()
                Button {
                    punkte.append("")
                } label: {
                    Label("Punkt hinzufügen", systemImage: "plus")
                }
                .controlSize(.small)
                .accessibilityIdentifier("\(kennung)-plus")
            }
            ForEach(Array(punkte.indices), id: \.self) { i in
                HStack(spacing: 6) {
                    TextField(platzhalter, text: Binding(get: { punkte.indices.contains(i) ? punkte[i] : "" },
                                                         set: { if punkte.indices.contains(i) { punkte[i] = $0 } }))
                        .textFieldStyle(.roundedBorder)
                        .accessibilityIdentifier("\(kennung)-\(i)")
                    Button {
                        if punkte.indices.contains(i) { punkte.remove(at: i) }
                    } label: {
                        Image(systemName: "minus.circle")
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Punkt \(i + 1) entfernen")
                }
            }
            if punkte.isEmpty {
                Text("Keine Punkte. Story, Task und Subtask werden ohne Fertig-Liste nicht zugestellt.")
                    .font(.caption).foregroundStyle(.tertiary)
            }
        }
    }
}

struct WeltenTicketFormular: View {
    let welt: Welt
    @State var entwurf: WeltenZustand.TicketEntwurf
    @Bindable var zustand: WeltenZustand

    init(welt: Welt, entwurf: WeltenZustand.TicketEntwurf, zustand: WeltenZustand) {
        self.welt = welt
        _entwurf = State(initialValue: entwurf)
        self.zustand = zustand
    }

    /// Der Steuerkanal schreibt in `zustand.neuesTicket`; das Formular folgt ihm.
    private func nachziehen() {
        if let e = zustand.neuesTicket, e != entwurf, e.id != entwurf.id || e.titel != entwurf.titel
            || e.ziel != entwurf.ziel || e.fertig != entwurf.fertig || e.an != entwurf.an || e.kind != entwurf.kind
            || e.prioritaet != entwurf.prioritaet || e.fertigPunkte != entwurf.fertigPunkte || e.eltern != entwurf.eltern
            || e.abhaengig != entwurf.abhaengig || e.frist != entwurf.frist || e.runden != entwurf.runden {
            entwurf = e
        }
    }

    /// Die Vorschau der Definition of Ready (Plan Satz 45): sie warnt, sie blockt nicht.
    private var bereitschaft: String? {
        WeltenWorte.bereitschaft(kind: entwurf.kind,
                                 punkte: entwurf.fertigPunkte.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }.count,
                                 frist: entwurf.frist, runden: entwurf.runden,
                                 adressaten: !entwurf.an.isEmpty,
                                 titel: entwurf.titel, ziel: entwurf.ziel, fertig: entwurf.fertig)
    }

    /// Die Tickets, die nach den Hierarchieregeln Eltern sein dürfen (Satz 43).
    private var elternWahl: [WeltTicket] {
        let erlaubt: String
        switch entwurf.kind {
        case "story": erlaubt = "vorhaben"
        case "task": erlaubt = "story"
        case "subtask": erlaubt = "task"
        default: return []
        }
        return welt.tickets.filter { $0.kind == erlaubt && !["verworfen", "abgenommen"].contains($0.stand) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
        Form {
            Section("Neues Ticket in \(welt.name)") {
                TextField("Titel", text: $entwurf.titel)
                TextField("Ziel", text: $entwurf.ziel, axis: .vertical).lineLimit(2...4)
                TextField("Fertig heißt", text: $entwurf.fertig, axis: .vertical).lineLimit(2...4)
            }
            Section("Fertig-Punkte") {
                WeltenPunkteFeld(punkte: $entwurf.fertigPunkte, kennung: "welten-ticket-punkt", titel: "Abhakbare Punkte")
            }
            Section("Einordnung") {
                Picker("Art", selection: $entwurf.kind) {
                    ForEach(WeltenWorte.ticketArten, id: \.self) { Text(WeltenWorte.kind($0)).tag($0) }
                }
                .accessibilityIdentifier("welten-ticket-art")
                Text(WeltenWorte.kindErklaerung(entwurf.kind)).font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Picker("Priorität", selection: $entwurf.prioritaet) {
                    ForEach(0..<4) { p in Text(WeltenWorte.prioritaet(p)).tag(p) }
                }
                .accessibilityIdentifier("welten-ticket-prioritaet")
                Text(WeltenWorte.prioritaetText(entwurf.prioritaet)).font(.caption).foregroundStyle(.secondary)
                Picker("Adressat", selection: $entwurf.an) {
                    Text("Hauptagent entscheidet").tag("")
                    ForEach(welt.teams) { t in Text("Team \(WeltenWorte.team(t.name))").tag("team:\(t.name)") }
                    ForEach(welt.liste, id: \.self) { id in Text(welt.anzeigename(id)).tag(id) }
                }
                .accessibilityIdentifier("welten-ticket-adressat")
                if !elternWahl.isEmpty {
                    Picker("Eltern", selection: $entwurf.eltern) {
                        Text("ohne").tag("")
                        ForEach(elternWahl) { t in Text(t.titel).tag(t.id) }
                    }
                    .accessibilityIdentifier("welten-ticket-eltern")
                }
            }
            Section("Abhängigkeiten und Grenzen") {
                Picker("Hängt ab von", selection: Binding(get: { entwurf.abhaengig.first ?? "" },
                                                          set: { entwurf.abhaengig = $0.isEmpty ? [] : [$0] })) {
                    Text("nichts").tag("")
                    ForEach(welt.tickets.filter { $0.stand != "verworfen" }) { t in Text(t.titel).tag(t.id) }
                }
                .accessibilityIdentifier("welten-ticket-abhaengig")
                TextField("Frist (ISO, etwa 2026-09-25T17:00:00Z)", text: $entwurf.frist)
                    .accessibilityIdentifier("welten-ticket-frist")
                TextField("Höchste Rundenzahl", text: $entwurf.runden)
                    .accessibilityIdentifier("welten-ticket-runden")
                Text("Ohne Frist und ohne Rundenzahl setzt der Kern sechs Runden.").font(.caption).foregroundStyle(.tertiary)
            }
        }
        .formStyle(.grouped)
        .frame(maxHeight: 460)
        .scrollContentBackground(.hidden)
        .onChange(of: zustand.neuesTicket) { _, _ in nachziehen() }
        .onAppear { nachziehen() }
        .accessibilityIdentifier("welten-ticket-formular")
        Divider()
        // Die Vorschau der Definition of Ready steht neben den Knoepfen, damit sie beim
        // Ausfuellen immer sichtbar bleibt; sie warnt, sie blockt nicht (Plan Satz 45).
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Zustandspunkt(art: bereitschaft == nil ? .laeuft : .will, basis: 7)
            VStack(alignment: .leading, spacing: 1) {
                Text(bereitschaft.map { "Wird noch nicht zugestellt: \($0)." } ?? "Wird zugestellt.")
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Die Vorschau hält nichts auf; angelegt wird das Ticket so oder so.")
                    .font(.caption).foregroundStyle(.tertiary)
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("welten-ticket-bereitschaft")
            Spacer(minLength: 12)
            Button("Abbrechen") { zustand.neuesTicket = nil }
            Button("Anlegen") {
                Task {
                    if await zustand.ticketAnlegen(welt, entwurf, echt: true) { zustand.neuesTicket = nil }
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled([entwurf.titel, entwurf.ziel, entwurf.fertig].contains { $0.trimmingCharacters(in: .whitespaces).isEmpty })
            .accessibilityIdentifier("welten-ticket-anlegen")
        }
        .padding(.top, 8)
        }
    }
}

// MARK: Der Inspektor

struct WeltenInspektor: View {
    let welt: Welt
    @Bindable var zustand: WeltenZustand

    var body: some View {
        VStack(spacing: 0) {
            if let anlegen = zustand.anlegen {
                WeltenAnlegenVorschau(welt: welt, anlegen: anlegen)
            } else if let a = welt.agent(zustand.agentId) {
                Picker("Blatt", selection: $zustand.blatt) {
                    ForEach(WeltenZustand.Blatt.allCases, id: \.self) { Text($0.titel).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .padding(10)
                .accessibilityIdentifier("welten-blatt")
                Divider()
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        switch zustand.blatt {
                        case .profil: profil(a)
                        case .protokoll: protokoll(a)
                        case .gedaechtnis: gedaechtnis(a)
                        case .skills: WeltenSkillBlatt(agent: a, zustand: zustand)
                        }
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                // Derselbe Aufbau wie beim Agenten: ein Kopf ueber dem rollenden Inhalt.
                Text("Welt").font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 24, alignment: .leading)
                    .padding(10)
                Divider()
                ScrollView {
                    weltInfo.padding(14).frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .accessibilityIdentifier("welten-inspektor")
    }

    private func gruppe<Inhalt: View>(_ titel: String?, @ViewBuilder _ inhalt: () -> Inhalt) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            if let titel { Text(titel).font(.callout.weight(.semibold)).foregroundStyle(.secondary) }
            inhalt()
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color(nsColor: .controlBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color(nsColor: .separatorColor)))
    }

    private func feld(_ name: String, _ wert: String, mono: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(name).font(.caption).foregroundStyle(.secondary)
            Text(wert.isEmpty ? "–" : wert).font(mono ? .callout.monospaced() : .callout).textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Ein Pfad in einer Zeile, in der Mitte gekuerzt; ganz steht er im Schildchen, der Pfeil zeigt ihn im Finder.
    private func pfadFeld(_ name: String, _ pfad: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(name).font(.caption).foregroundStyle(.secondary)
            HStack(spacing: 4) {
                Text(kurzerPfad(pfad))
                    .font(.callout.monospaced()).lineLimit(1).truncationMode(.middle)
                    .help(pfad)
                Button {
                    NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: pfad)])
                } label: {
                    Image(systemName: "arrow.forward.circle")
                }
                .buttonStyle(.borderless)
                .help("Im Finder zeigen")
                .accessibilityLabel("\(name) im Finder zeigen")
            }
        }
    }

    @ViewBuilder
    private func profil(_ a: WeltAgent) -> some View {
        HStack(spacing: 12) {
            WeltenFigur(agent: a, groesse: 64)
            VStack(alignment: .leading, spacing: 3) {
                Text(a.name).font(.title3.weight(.semibold))
                Text(WeltenWorte.stufe(a.stufe) + (a.team.map { " · Team \(WeltenWorte.team($0))" } ?? "")).foregroundStyle(.secondary)
                HStack(spacing: 4) { Zustandspunkt(art: WeltenWorte.punkt(agent: a), basis: 7); WeltenLebenWort(agent: a) }.font(.callout)
            }
        }
        if a.leben != nil { lebenszeichen(a) }
        gruppe("Betrieb") {
            HStack {
                Text("Schalter").font(.callout)
                Spacer()
                WeltenPausenschalter(welt: welt, agent: a, zustand: zustand)
            }
            if let g = a.standGrund, a.stand != "aktiv" { Text("Grund: \(g)").font(.caption).foregroundStyle(.secondary) }
            if a.stand != "gestoppt" {
                Button("Sofort stoppen …", role: .destructive) { Task { await zustand.stoppen(welt, agent: a.id, echt: true) } }
                    .controlSize(.small)
            }
            Text("Postfach: \(a.postfachOffen) von \(a.postfachGesamt) noch nicht quittiert").font(.caption).foregroundStyle(.secondary)
        }
        if zustand.profilEntwurf?.agent == a.id {
            profilFormular(a)
        } else {
            gruppe("Profil") {
                HStack {
                    Spacer()
                    Button("Bearbeiten") { zustand.profilEntwurf = WeltenZustand.ProfilEntwurf(a) }
                        .controlSize(.small)
                        .accessibilityIdentifier("welten-profil-bearbeiten")
                }
                feld("Spezialgebiet", a.spezialgebiet)
                feld("Modell", a.modell + (a.denkstufe.isEmpty || a.modell.hasSuffix(":\(a.denkstufe)") ? "" : " · \(a.denkstufe)"), mono: true)
                feld("Fallback", a.fallback, mono: true)
                feld("Maschine", WeltenWorte.maschine(a.maschine))
                if !a.kontextgrenze.isEmpty { feld("Kontextgrenze", a.kontextgrenze) }
                feld("Angelegt", AgentsWorte.uhrzeit(a.angelegt) + (a.angelegtVon.map { " von \(welt.anzeigename($0))" } ?? "") + (a.vorlage.map { ", Vorlage \($0)" } ?? ""))
                feld("Kennung", a.id, mono: true)
            }
        }
        rechte(a)
    }

    /// Auftrag agentsform: was der Agent darf. Aendern geht nur, wenn die Bibliothek `wb-agent rechte` kennt; sonst sagt der Knopf, warum nicht.
    @ViewBuilder
    private func rechte(_ a: WeltAgent) -> some View {
        let dienstweg = zustand.kern?.welten?.dienstweg(a.stufe) ?? []
        if let e = zustand.rechteEntwurf, e.agent == a.id, welt.rechteAenderbar {
            gruppe("Rechte ändern") {
                WeltenRechteAuswahl(
                    welt: welt, werkzeuge: ["Bash"] + e.werkzeuge, skills: e.skills, dienstweg: dienstweg,
                    bash: Binding(get: { zustand.rechteEntwurf?.bash ?? "" }, set: { zustand.rechteEntwurf?.bash = $0 }),
                    werkzeug: { name, an in
                        if let f = zustand.rechteWerkzeug(name, an, welt) { zustand.meldung = WeltenZustand.Meldung(text: f, ok: false) }
                    },
                    skill: { zustand.rechteSkill($0, $1) })
                .controlSize(.small)
                Label("Ein laufender Zug behält seine Rechte; der nächste liest die neuen. Der Verlauf nennt die Änderung.", systemImage: "info.circle")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 8) {
                    Spacer()
                    Button("Abbrechen") { zustand.rechteEntwurf = nil }
                    Button("Sichern") { Task { await zustand.rechteSichern(welt, echt: true) } }
                        .buttonStyle(.borderedProminent)
                        .disabled(zustand.laufend.contains("rechte"))
                        .accessibilityIdentifier("welten-rechte-sichern")
                }
                .controlSize(.small)
            }
            .accessibilityIdentifier("welten-profil-rechte")
        } else {
            let eigene = AgentEntwurf.eigeneMuster(a.bash, dienstweg)
            let web = a.werkzeuge.filter { WeltenZustand.webWerkzeuge.contains($0) }
            gruppe("Was der Agent darf") {
                HStack {
                    Spacer()
                    Button("Rechte ändern …") { zustand.rechteEntwurf = WeltenZustand.RechteEntwurf(a, dienstweg: dienstweg) }
                        .controlSize(.small)
                        .disabled(!welt.rechteAenderbar)
                        .help(welt.rechteAenderbar ? "Werkzeuge, Bash-Muster und Skills; gilt ab dem nächsten Zug." : Self.rechteNichtAusgerollt)
                        .accessibilityIdentifier("welten-rechte-bearbeiten")
                }
                feld("Werkzeuge", a.werkzeuge.filter { !WeltenZustand.webWerkzeuge.contains($0) }.joined(separator: ", "), mono: true)
                feld("Web", web.isEmpty ? (welt.webZugang ? "keins (Zugang vorhanden)" : "keins (die Welt hat keinen Zugang der Art web)") : web.joined(separator: ", "))
                feld("Bash-Muster", (eigene.isEmpty ? "keine eigenen" : eigene.joined(separator: " · ")) + (a.bash.count > eigene.count ? " + \(a.bash.count - eigene.count) Dienstweg" : ""), mono: !eigene.isEmpty)
                feld("Skills", a.skills.isEmpty ? "keine eingetragen" : a.skills.joined(separator: ", "))
                if !welt.rechteAenderbar {
                    Text(Self.rechteNichtAusgerollt).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("welten-rechte-grund")
                }
            }
            .accessibilityIdentifier("welten-profil-rechte")
        }
    }

    static let rechteNichtAusgerollt = "Ändern ist noch nicht ausgerollt: Die Datenbibliothek kennt „wb-agent rechte“ noch nicht. Bis dahin stehen die Rechte hier nur zum Lesen."

    /// Auftrag agentaktiv: was der Traeger ueber den Zug sagt -- jetzt, Art, Grund, naechster Wecker, letzter Zug.
    private func lebenszeichen(_ a: WeltAgent) -> some View {
        gruppe("Zug") {
            VStack(alignment: .leading, spacing: 1) {
                Text("Jetzt").font(.caption).foregroundStyle(.secondary)
                WeltenLebenWort(agent: a, ohneLeben: a.leben?.stand == "schlaeft" ? "schläft" : nil).font(.callout)
            }
            if let z = a.zug, z.laeuft, let art = z.art { feld("Art", WeltenWorte.zugArt(art)) }
            if let g = a.leben?.grund { feld("Grund", WeltenWorte.grund(g)) }
            if let w = a.leben?.wecker { feld("Nächster Wecker", AgentsWorte.uhrzeit(w)) }
            if let z = a.zug, let e = z.letzterErgebnis { feld("Letzter Zug", "\(AgentsWorte.uhrzeit(z.letzterEnde)), \(e)") }
            if !welt.traegerZugFehler.isEmpty {
                Text("Lebenszeichen nicht lesbar: \(welt.traegerZugFehler)").font(.caption).foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityIdentifier("welten-lebenszeichen")
    }

    /// Das Profil bearbeiten: Modell, Denkstufe, Fallback, Maschine, Spezialgebiet (Plan Abschnitt 6, Inspektor).
    private func profilFormular(_ a: WeltAgent) -> some View {
        let e = Binding(get: { zustand.profilEntwurf ?? WeltenZustand.ProfilEntwurf(a) }, set: { zustand.profilEntwurf = $0 })
        return gruppe("Profil bearbeiten") {
            VStack(alignment: .leading, spacing: 10) {
                formzeile("Spezialgebiet") {
                    TextField("Spezialgebiet", text: e.spezialgebiet, axis: .vertical).lineLimit(1...3)
                }
                formzeile("Modell") {
                    TextField("z. B. sonnet5:high", text: e.modell).font(.callout.monospaced())
                        .accessibilityIdentifier("welten-profil-modell")
                }
                formzeile("Denkstufe") {
                    Picker("Denkstufe", selection: e.denkstufe) {
                        ForEach(WeltenWorte.denkstufen, id: \.self) { Text($0).tag($0) }
                    }
                    .labelsHidden()
                }
                formzeile("Fallback") {
                    TextField("leer = keiner", text: e.fallback).font(.callout.monospaced())
                }
                formzeile("Fallback-Denkstufe") {
                    Picker("Fallback-Denkstufe", selection: e.fallbackDenkstufe) {
                        Text("–").tag("")
                        ForEach(WeltenWorte.denkstufen, id: \.self) { Text($0).tag($0) }
                    }
                    .labelsHidden()
                    .disabled(e.wrappedValue.fallback.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                formzeile("Maschine") {
                    TextField("peer, ltfserver, mac …", text: e.maschine)
                }
                Label("Ein Modellwechsel gilt ab dem nächsten Start; ein laufender Zug behält sein Modell. Der Verlauf nennt jede Änderung.", systemImage: "info.circle")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 8) {
                    Spacer()
                    Button("Abbrechen") { zustand.profilEntwurf = nil }
                    Button("Sichern") { Task { await zustand.profilSichern(welt, echt: true) } }
                        .buttonStyle(.borderedProminent)
                        .disabled(zustand.laufend.contains("profil"))
                        .accessibilityIdentifier("welten-profil-sichern")
                }
            }
            .textFieldStyle(.roundedBorder)
            .controlSize(.small)
        }
    }

    private func formzeile<Inhalt: View>(_ name: String, @ViewBuilder _ inhalt: () -> Inhalt) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(name).font(.caption).foregroundStyle(.secondary)
            inhalt()
        }
    }

    @ViewBuilder
    private func protokoll(_ a: WeltAgent) -> some View {
        let ausTickets = welt.tickets.flatMap { t in t.verlauf.filter { $0.von == a.id }.map { (zeit: $0.zeit, titel: WeltenWorte.ereignis($0.ereignis), text: "„\(t.titel)“\($0.text.isEmpty ? "" : " -- \($0.text)")") } }
        let ausProfil = a.verlauf.map { (zeit: $0.zeit, titel: WeltenWorte.ereignis($0.ereignis), text: [$0.aenderungen, $0.notiz].filter { !$0.isEmpty }.joined(separator: ". ")) }
        let ereignisse = (ausTickets + ausProfil).sorted { $0.zeit > $1.zeit }
        gruppe(nil) {
            Label("Das Zugprotokoll mit Werkzeugaufrufen liefert erst der Träger. Bis dahin steht hier, was \(a.name) in Tickets eingetragen hat und was am Profil oder Gedächtnis geändert wurde.", systemImage: "info.circle")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        if ereignisse.isEmpty {
            Text("Noch keine Einträge.").font(.callout).foregroundStyle(.secondary)
        }
        ForEach(Array(ereignisse.enumerated()), id: \.offset) { _, e in
            VStack(alignment: .leading, spacing: 2) {
                Text("\(AgentsWorte.uhrzeit(e.zeit)) · \(e.titel)").font(.callout.weight(.medium))
                Text(e.text).font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder
    private func gedaechtnis(_ a: WeltAgent) -> some View {
        if let e = zustand.gedaechtnisEntwurf, e.agent == a.id {
            VStack(alignment: .leading, spacing: 8) {
                Label("Das Gedächtnis pflegt \(a.name) selbst. Deine Fassung ersetzt MEMORY.md; wurde die Datei inzwischen geändert, wird nichts gesichert, und du lädst neu.", systemImage: "exclamationmark.triangle")
                    .font(.caption).fixedSize(horizontal: false, vertical: true)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.orange.opacity(0.12)))
            TextEditor(text: Binding(get: { zustand.gedaechtnisEntwurf?.text ?? "" }, set: { zustand.gedaechtnisEntwurf?.text = $0 }))
                .font(.callout.monospaced())
                .frame(minHeight: 280)
                .scrollContentBackground(.hidden)
                .padding(6)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .textBackgroundColor)))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(nsColor: .separatorColor)))
                .accessibilityIdentifier("welten-gedaechtnis-editor")
            HStack(spacing: 8) {
                Spacer()
                Button("Verwerfen") { zustand.gedaechtnisEntwurf = nil }
                Button("Sichern") { Task { await zustand.gedaechtnisSichern(welt, echt: true) } }
                    .buttonStyle(.borderedProminent)
                    .disabled(e.text == a.gedaechtnis || zustand.laufend.contains("gedaechtnis"))
            }
            .controlSize(.small)
        } else {
            gruppe(nil) {
                HStack(alignment: .firstTextBaseline) {
                    Label("MEMORY.md", systemImage: "doc.text").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("Bearbeiten …") { zustand.gedaechtnisEntwurf = WeltenZustand.GedaechtnisEntwurf(agent: a.id, text: a.gedaechtnis, sha: a.gedaechtnisSha) }
                        .controlSize(.small)
                        .disabled(a.gedaechtnisGekuerzt || a.gedaechtnisSha.isEmpty)
                        .help(a.gedaechtnisGekuerzt ? "Gekürzt geladen; bearbeiten geht nur mit der ganzen Datei." : "Mit Warnung bearbeiten")
                        .accessibilityIdentifier("welten-gedaechtnis-bearbeiten")
                }
                if let g = a.gedaechtnisGeaendert { Text("Zuletzt geändert \(AgentsWorte.uhrzeit(g))").font(.caption).foregroundStyle(.secondary) }
            }
            Text(a.gedaechtnis.isEmpty ? "Kein Gedächtnis gefunden." : a.gedaechtnis)
                .font(.callout.monospaced())
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("welten-gedaechtnis")
            if a.gedaechtnisGekuerzt { Text("Gekürzt angezeigt.").font(.caption).foregroundStyle(.secondary) }
        }
    }

    /// Wo die Welt liegt, ob die Maschine antwortet, ob ihr Traeger eingerichtet ist; fuer eine Welt hier der Umzug.
    private var maschine: some View {
        gruppe("Maschine") {
            feld("Maschine", WeltenWorte.maschine(welt.maschine) + (welt.fern ? "" : ", diese"))
            if welt.fern {
                feld("Verbindung", welt.verbindungOk ? "erreichbar" : "nicht erreichbar\(welt.verbindungSeit.map { " seit \(AgentsWorte.uhrzeit($0))" } ?? ""): \(welt.verbindungText)")
            }
            feld("Träger", WeltenWorte.traeger(welt))
            if !welt.fern, let n = zustand.kern?.welten, !n.agentMaschinen.isEmpty {
                Menu("Umziehen nach …") {
                    ForEach(n.agentMaschinen) { m in
                        Button(WeltenWorte.maschine(m.name) + (m.erreichbar == false ? " (nicht erreichbar)" : "")) {
                            Task { await zustand.umziehen(welt, nach: m.name, echt: true) }
                        }
                    }
                }
                .fixedSize()
                .controlSize(.small)
                .disabled(zustand.laufend.contains("umziehen"))
                .help("Die Ablage zieht auf die Maschine unter demselben Pfad relativ zum Benutzerordner; hier bleibt sie umbenannt liegen. Vorher prüft die Werkbank beide Seiten und fragt zurück.")
                .accessibilityIdentifier("welten-umziehen")
                Text("Hier bleibt die Ablage als …umgezogen-<Datum> liegen; nichts wird gelöscht.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder
    private var weltInfo: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(welt.name).font(.title3.weight(.semibold))
            gruppe("Welt") {
                feld("Art", welt.art == "global" ? "Global, für alle Projekte" : "Projekt")
                if welt.fern {
                    if let p = welt.projekt { feld("Projekt", "\(welt.maschine):\(p)", mono: true) }
                    feld("Ablage", "\(welt.maschine):\(welt.ablage)", mono: true)
                } else {
                    if let p = welt.projekt { pfadFeld("Projekt", p) }
                    pfadFeld("Ablage", welt.pfad)
                }
                feld("Stand", welt.stand + (welt.standGrund.map { ", \($0)" } ?? ""))
                feld("Hauptagent", welt.agent(welt.hauptagent)?.name ?? "keiner")
                feld("Agenten", "\(welt.agenten.count) in \(welt.teams.count) \(welt.teams.count == 1 ? "Team" : "Teams")")
                feld("Tickets", "\(welt.tickets.count), davon \(welt.ticketsOffen) offen, \(welt.triage) in der Triage")
                feld("Fragen", "\(welt.offeneFragen.count) offen von \(welt.fragen.count)")
            }
            zyklusGruppe
            dodGruppe
            wipGruppe
            if !welt.maschine.isEmpty { maschine }
            if !welt.zugaenge.isEmpty {
                gruppe("Zugänge") {
                    Text("\(welt.zugaenge.joined(separator: ", ")) – eingerichtet vom Menschen, gilt für alle Agenten der Welt")
                        .font(.callout).fixedSize(horizontal: false, vertical: true)
                }
            }
            gruppe("Sofortstopp") {
                Text("Sperrt neue Starts und beendet laufende Züge der ganzen Welt. Tickets in Arbeit werden unterbrochen, nie als Erfolg gezählt.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                if welt.stand != "gestoppt" {
                    Button("Welt sofort stoppen …", role: .destructive) { Task { await zustand.stoppen(welt, agent: nil, echt: true) } }
                        .controlSize(.small)
                }
            }
            if !welt.antraege.isEmpty {
                gruppe("Anträge an den Hauptagenten") {
                    ForEach(welt.antraege) { a in
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(a.agent) für Team \(WeltenWorte.team(a.team ?? "")) · \(a.stand == "offen" ? "offen" : (a.entscheidung == "anlegen" ? "angelegt" : "abgelehnt"))")
                                .font(.callout)
                            Text("von \(welt.anzeigename(a.von)): \(a.spezialgebiet)").font(.caption).foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    Text("Entscheiden kann nur \(welt.agent(welt.hauptagent)?.name ?? "der Hauptagent") (wb-agent antrag-entscheiden).")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            if !welt.fehler.isEmpty {
                gruppe("Beim Lesen") { ForEach(welt.fehler, id: \.self) { Text($0).font(.caption) } }
            }
        }
    }

    // --- Zyklus, Definition of Done und WIP-Grenze der Welt (Auftrag tickets4 D) ---------

    /// Die Felder der Welt in Bearbeitung; sie gehen auf, sobald „Bearbeiten" geklickt ist.
    private var regeln: Binding<WeltenZustand.WeltRegelEntwurf>? {
        guard zustand.weltRegeln?.welt == welt.pfad else { return nil }
        return Binding(get: { self.zustand.weltRegeln ?? WeltenZustand.WeltRegelEntwurf() },
                       set: { self.zustand.weltRegeln = $0 })
    }

    @ViewBuilder
    private var zyklusGruppe: some View {
        gruppe("Zyklus") {
            let z = welt.zyklus
            if let jetzt = z.jetzt, z.an {
                feld("Läuft", "\(jetzt.id) · \(AgentsWorte.uhrzeit(jetzt.start)) bis \(AgentsWorte.uhrzeit(jetzt.ende))")
                if !jetzt.ziel.isEmpty { feld("Ziel", jetzt.ziel) }
            } else if let jetzt = z.jetzt {
                feld("Aus", "zuletzt \(jetzt.id)")
            } else {
                Text("Diese Welt arbeitet ohne Zyklus. Eine Bauwelt bekommt einen, eine Betriebswelt braucht keinen.")
                    .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            feld("Länge", "\(z.tage) \(z.tage == 1 ? "Tag" : "Tage")")
            if let r = regeln {
                TextField("Länge in Tagen", text: r.zyklusTage).textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier("welten-zyklus-tage")
                TextField("Ziel dieses Zyklus", text: r.zyklusZiel).textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier("welten-zyklus-ziel")
                HStack(spacing: 8) {
                    Button(z.an ? "Neu starten" : "Einschalten") { Task { await zustand.zyklusSetzen(welt, an: true, echt: true) } }
                        .accessibilityIdentifier("welten-zyklus-ein")
                    if z.an {
                        Button("Ausschalten") { Task { await zustand.zyklusSetzen(welt, an: false, echt: true) } }
                            .accessibilityIdentifier("welten-zyklus-aus")
                    }
                }
                .controlSize(.small)
            } else {
                Button("Bearbeiten") { zustand.regelnOeffnen(welt) }
                    .controlSize(.small)
                    .accessibilityIdentifier("welten-regeln-bearbeiten")
            }
            if !z.historie.isEmpty {
                Text("Abgeschlossen").font(.caption).foregroundStyle(.secondary)
                ForEach(z.historie.reversed()) { h in
                    Text("\(h.id): \(h.angelegt) angelegt · \(h.abgenommen) abgenommen · \(h.uebertragen) übertragen")
                        .font(.caption).foregroundStyle(.secondary)
                        .accessibilityIdentifier("welten-zyklus-\(h.id)")
                }
            }
        }
    }

    @ViewBuilder
    private var dodGruppe: some View {
        gruppe("Definition of Done") {
            if let r = regeln {
                WeltenPunkteFeld(punkte: r.dod, kennung: "welten-dod", titel: "Punkte der Welt", platzhalter: "Was für alles gilt, was diese Welt liefert")
                HStack {
                    Spacer()
                    Button("Sichern") { Task { await zustand.dodSichern(welt, echt: true) } }
                        .controlSize(.small)
                        .accessibilityIdentifier("welten-dod-sichern")
                }
            } else if welt.dod.isEmpty {
                Text("Noch keine. Ohne Definition of Done nimmt der Abnehmende ohne Bestätigung ab.")
                    .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            } else {
                ForEach(Array(welt.dod.enumerated()), id: \.offset) { _, p in
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Image(systemName: "checkmark").font(.caption).foregroundStyle(.secondary).accessibilityHidden(true)
                        Text(p).font(.callout).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var wipGruppe: some View {
        gruppe("WIP-Grenze") {
            let w = WeltenZustand.wipText(welt)
            HStack(spacing: 6) {
                Text(w.text).font(.callout).monospacedDigit().foregroundStyle(w.rot ? Color.orange : Color.primary)
                Text(w.rot ? "überschritten" : "laufende und geparkte Tickets").font(.caption).foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("welten-wip")
            if let r = regeln {
                TextField("Grenze (leer: aktive Agenten plus ein Viertel)", text: r.wip).textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier("welten-wip-feld")
                HStack {
                    Spacer()
                    Button("Setzen") { Task { await zustand.wipSetzen(welt, echt: true) } }
                        .controlSize(.small)
                        .accessibilityIdentifier("welten-wip-setzen")
                }
            }
        }
    }
}

// MARK: Die Auskunft fuer `awbmac-ctl welten`

extension WeltenZustand {
    /// Auftrag agentaktiv: der Zug eines Agenten fuer die Auskunft; ohne Traeger `null`.
    nonisolated static func zugAuskunft(_ a: WeltAgent) -> Any {
        guard let z = a.zug else { return a.leben.map { ["leben": $0.stand] as [String: Any] } ?? NSNull() }
        return ["laeuft": z.laeuft, "seit": z.seit ?? "", "art": z.art ?? "", "zustellung_offen": z.zustellungOffen, "grund": z.grund ?? "",
                "naechster_wecker": z.naechsterWecker ?? "", "letzter": z.letzterErgebnis ?? "", "leben": a.leben?.stand ?? ""] as [String: Any]
    }

    func auskunft(kern: KernVerbindung, sichtbar: Bool) -> [String: Any] {
        var raus: [String: Any] = ["sichtbar": sichtbar, "darstellung": darstellung.rawValue, "reiter": reiter.rawValue,
                                   "blatt": blatt.rawValue, "auswahl": auswahl, "gespraech": gespraech,
                                   "inspektor": inspektorOffen, "ticketFilter": ticketFilter, "ticketAuswahl": ticketAuswahl ?? ""]
        raus["meldung"] = meldung.map { ["text": $0.text, "ok": $0.ok] as [String: Any] } ?? [:]
        raus["rueckfrage"] = rueckfrage.map { ["handlung": $0.handlung, "text": $0.text, "warnungen": $0.warnungen] as [String: Any] } ?? [:]
        switch Self.lage(kern) {
        case .offline(let g): raus["lage"] = "offline"; raus["lageText"] = g
        case .ladend: raus["lage"] = "ladend"
        case .fehler(let f): raus["lage"] = "fehler"; raus["lageText"] = f.joined(separator: "; ")
        case .leer(let f): raus["lage"] = "leer"; raus["lageText"] = f.joined(separator: "; ")
        case .inhalt: raus["lage"] = "inhalt"
        }
        raus["weltNeuLaeuft"] = laufend.contains("neu")
        raus["weltNeuFrage"] = weltNeuFrage.map { ["wege": $0.wege, "vorgabe": $0.vorgabe, "text": $0.text] as [String: Any] } ?? [:]
        // Der Leerzustand ohne Welt (WeltenEinladung): welche Wege er anbietet.
        if case .leer = Self.lage(kern) {
            raus["einladung"] = ["knoepfe": WeltenEinladung.knoepfe(kern.welten), "globalPfad": kern.welten?.globalPfad ?? ""] as [String: Any]
        }
        guard let n = kern.welten, let w = welt(n) else { return raus }
        raus["welten"] = n.welten.map { ["name": $0.name, "pfad": $0.pfad, "art": $0.art, "fehler": $0.fehler, "maschine": $0.maschine,
                                         "menuname": WeltenUebersichtWorte.menuname($0)] as [String: Any] }
        raus["welt"] = ["name": w.name, "pfad": w.pfad, "stand": w.stand, "zaehler": WeltenWorte.zaehlerGetrennt(w), "hauptagent": w.hauptagent ?? "",
                        "maschine": w.maschine, "fern": w.fern, "ablage": w.ablage, "herkunft": WeltenWorte.herkunft(w),
                        "verbindung": ["ok": w.verbindungOk, "seit": w.verbindungSeit ?? "", "text": w.verbindungText] as [String: Any],
                        "traeger": WeltenWorte.traeger(w), "hinweis": WeltenWorte.maschinenHinweis(w) ?? ""] as [String: Any]
        raus["maschinen"] = n.maschinen.map { ["name": $0.name, "eigene": $0.eigene, "traeger": $0.traeger, "erreichbar": $0.erreichbar.map { $0 ? "ja" : "nein" } ?? "unbekannt",
                                               "welten": $0.welten] as [String: Any] }
        raus["maschineVorgabe"] = WeltenZustand.maschineVorgabe(n.maschinen, vorgabe: n.maschineVorgabe)
        raus["umziehenNach"] = w.fern ? [] : n.agentMaschinen.map(\.name)
        raus["globalPfad"] = n.globalPfad
        raus["neueWelt"] = WeltenWahlMenue.neuEintraege(n)
        let al = Self.anlegenLage(w)
        raus["agentAnlegen"] = ["titel": al.titel, "aktiv": al.aktiv, "grund": al.grund, "vorlagen": n.vorlagen.map(\.titel)] as [String: Any]
        raus["mitte"] = anlegen != nil ? "anlegen" : (auswahl == Self.uebersicht ? "uebersicht" : reiter.rawValue)
        if auswahl == Self.uebersicht { raus["uebersicht"] = WeltenUebersichtWorte.auskunft(w, zustand: self) }
        raus["zeilen"] = zeilen(w).map { z -> [String: Any] in
            switch z {
            case .uebersicht: return ["art": "uebersicht", "id": z.id]
            case .hinweis(let t): return ["art": "hinweis", "id": z.id, "text": t]
            case .kanal: return ["art": "kanal", "id": z.id, "ungelesen": ungelesen(w, schluessel: Self.kanal)]
            case .kopf(let t): return ["art": "kopf", "id": z.id, "text": t]
            case .team(let name, let offen, let aktiv, let mitLeiter): return ["art": "team", "id": z.id, "name": name, "offen": offen, "aktiv": aktiv, "leiter": mitLeiter]
            case .agent(let id, let ebene, let teamZusatz):
                let a = w.agent(id)
                return ["art": "agent", "id": z.id, "name": a?.name ?? id, "ebene": ebene, "stufe": a?.stufe ?? "", "team": teamZusatz ? (a?.team ?? "") : "",
                        "zustand": WeltenWorte.zustand(a?.zustand ?? ""), "text": a?.zustandText ?? "", "ungelesen": ungelesen(w, agent: id),
                        "figur": a.map { FigurArt.fuer(rolle: $0.figurRolle, team: $0.figurTeam, arten: $0.arten).rawValue } ?? "",
                        "figurZustand": a?.figur.rawValue ?? "", "wort": a.map { WeltenWorte.agentWort($0) } ?? "", "ring": a?.ring.rawValue ?? "",
                        "zug": a.map { Self.zugAuskunft($0) } ?? NSNull()]
            }
        }
        let a = w.agent(agentId)
        raus["kopf"] = a.map { ["name": $0.name, "stufe": WeltenWorte.stufe($0.stufe), "modell": $0.modell, "maschine": $0.maschine, "zug": $0.zustandText,
                                "leben": WeltenWorte.leben($0) ?? "", "ring": $0.ring.rawValue] as [String: Any] }
            ?? (auswahl == Self.uebersicht ? ["name": "Übersicht", "welt": w.name] : ["name": "Kanal", "nachrichten": w.kanalGesamt]) as [String: Any]
        raus["gespraeche"] = a.map { agent in [Self.einzel] + agent.direktchats } ?? []
        let k = gespraechSchluessel()
        var chat: [[String: Any]] = []
        if k.hasPrefix("einzel:"), let a {
            for e in a.einzelchat {
                if let m = e.nachricht { chat.append(["art": "nachricht", "id": m.id, "von": m.von, "an": m.an, "text": m.text, "markierung": m.markierung ?? "", "offen": m.offenFuerMensch]) }
                else if let f = w.frage(e.frage) { chat.append(["art": "frage", "id": f.id, "stand": f.stand, "text": f.text, "optionen": f.optionenGeordnet, "empfehlung": f.empfehlung ?? ""]) }
            }
        } else {
            for m in nachrichten(w, schluessel: k) { chat.append(["art": "nachricht", "id": m.id, "von": m.von, "an": m.an, "text": m.text, "markierung": m.markierung ?? "", "offen": m.offenFuerMensch]) }
        }
        raus["chat"] = chat
        // Auftrag agentaktiv: der Stand unter der eigenen Nachricht, wie ihn die Mitte gerade zeichnet.
        raus["antwortStand"] = k.hasPrefix("einzel:") ? (a.flatMap { agent in
            WeltenWorte.antwort(agent).map { ["text": $0.text, "art": $0.art, "nachricht": agent.antwort?.nachricht ?? "", "wecken": agent.antwort?.wecken ?? ""] as [String: Any] }
        } ?? [:]) : [:]
        raus["traegerZugFehler"] = w.traegerZugFehler
        raus["eingabe"] = k.hasPrefix("direkt:") ? ["lesend": true] as [String: Any] : ["lesend": false, "adressen": a == nil ? adressen(w) : "", "entwurf": entwuerfe[k] ?? ""] as [String: Any]
        raus["offeneFragen"] = w.offeneFragen.map(\.id)
        raus["ungelesenWelt"] = w.ungelesen
        raus["markiertOffen"] = w.markiertOffen.map { ["zustellung": $0.zustellung, "von": $0.von, "markierung": $0.markierung] }
        raus["ticketDetail"] = w.ticket(ticketAuswahl).map { t -> [String: Any] in
            ["id": t.id, "stand": t.stand, "bemerkung": t.abnahme?.bemerkung ?? "", "rueckgabeOffen": rueckgabeOffen == t.id, "rueckgabeText": rueckgabeText,
             "art": t.art, "skillVorschlag": t.skillVorschlag.map { ["skill": $0.skill, "agent": $0.agent, "ziel": $0.ziel, "stand": $0.stand, "pruefer": $0.pruefer,
                                                                    "diffZeilen": $0.diff.split(separator: "\n").count, "entschiedenVon": $0.entschiedenVon ?? ""] as [String: Any] } ?? [:],
             "skillAblehnenOffen": skillAblehnenOffen == t.id,
             // tickets4: alles, was die Detailansicht nach Plan Satz 37 und 38 zeigt.
             "kind": t.kind, "prioritaet": t.prioritaet, "prioritaetText": t.prioritaetText, "ampel": t.ampel,
             "eltern": t.eltern ?? "", "herkunft": t.herkunft ?? "", "duplikatVon": t.duplikatVon ?? "", "zyklus": t.zyklus ?? "",
             "kinder": ["gesamt": t.kinderGesamt, "abgenommen": t.kinderAbgenommen] as [String: Any],
             "fertigPunkte": t.fertigPunkte.map { ["text": $0.text, "erledigt": $0.erledigt] as [String: Any] },
             "zwischenstaende": t.verlauf.filter { $0.ereignis == "zwischenstand" }.map(\.text),
             "messung": WeltenTicketWorte.messung(t),
             "standzeile": WeltenTicketWorte.standzeile(t, welt: w) ?? "",
             "abnahmeGrund": t.abnahme?.grund ?? "",
             "pruefung": t.pruefung.map { ["pruefer": $0.pruefer, "urteil": $0.urteil ?? "", "notiz": $0.notiz ?? ""] as [String: Any] } ?? [:],
             "verworfen": t.verworfen.map { ["code": $0.code, "bemerkung": $0.bemerkung ?? "", "duplikatVon": $0.duplikatVon ?? ""] as [String: Any] } ?? [:],
             "geparkt": t.geparkt.map { ["grund": $0.grund, "bis": $0.bis ?? "", "auf": $0.auf ?? ""] as [String: Any] } ?? [:],
             "flagge": t.flagge.map { ["grund": $0.grund, "frage": $0.frage ?? ""] as [String: Any] } ?? [:],
             "handlungen": Self.moeglicheHandlungen(t).map(\.rawValue)]
        } ?? [:]
        raus["ticketAnsicht"] = ticketAnsicht.rawValue
        raus["ticketHandlung"] = ticketHandlung.map {
            ["ticket": $0.ticket, "handlung": $0.handlung.rawValue, "grund": $0.grund, "bemerkung": $0.bemerkung,
             "duplikat": $0.duplikat, "an": $0.an, "pruefer": $0.pruefer, "art": $0.kind, "prioritaet": $0.prioritaet,
             "punkte": $0.fertigPunkte, "frist": $0.frist, "runden": $0.runden] as [String: Any]
        } ?? [:]
        raus["ticketFormular"] = neuesTicket.map { e -> [String: Any] in
            let punkte = e.fertigPunkte.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            return ["titel": e.titel, "ziel": e.ziel, "fertig": e.fertig, "an": e.an, "art": e.kind,
                    "prioritaet": e.prioritaet, "punkte": punkte, "eltern": e.eltern, "abhaengig": e.abhaengig,
                    "frist": e.frist, "runden": e.runden,
                    "bereitschaft": WeltenWorte.bereitschaft(kind: e.kind, punkte: punkte.count, frist: e.frist, runden: e.runden,
                                                             adressaten: !e.an.isEmpty, titel: e.titel, ziel: e.ziel, fertig: e.fertig) ?? ""]
        } ?? [:]
        raus["weltRegeln"] = weltRegeln.map { ["welt": $0.welt, "zyklusTage": $0.zyklusTage, "zyklusZiel": $0.zyklusZiel,
                                               "dod": $0.dod, "wip": $0.wip] as [String: Any] } ?? [:]
        raus["weltZyklus"] = ["an": w.zyklus.an, "tage": w.zyklus.tage, "jetzt": w.zyklus.jetzt?.id ?? "",
                              "ziel": w.zyklus.jetzt?.ziel ?? "",
                              "historie": w.zyklus.historie.map { ["id": $0.id, "angelegt": $0.angelegt, "abgenommen": $0.abgenommen, "uebertragen": $0.uebertragen] as [String: Any] }] as [String: Any]
        raus["weltDod"] = w.dod
        raus["weltWip"] = ["laufend": w.wip.laufend, "grenze": w.wip.grenze, "text": Self.wipText(w).text, "rot": Self.wipText(w).rot] as [String: Any]
        raus["backlog"] = Self.backlog(w).map(\.id)
        raus["board"] = Self.board(w, tickets: tickets(w)).map { spur -> [String: Any] in
            ["id": spur.id, "titel": spur.titel,
             "spalten": zip(WeltenWorte.boardSpalten, spur.spalten).map { name, inhalt in
                 ["name": name, "tickets": inhalt.map(\.id)] as [String: Any]
             }]
        }
        raus["profilEntwurf"] = profilEntwurf.map { ["agent": $0.agent, "modell": $0.modell, "denkstufe": $0.denkstufe, "fallback": $0.fallback, "fallbackDenkstufe": $0.fallbackDenkstufe, "maschine": $0.maschine, "spezialgebiet": $0.spezialgebiet] } ?? [:]
        raus["antraege"] = w.antraege.map { ["id": $0.id, "von": $0.von, "agent": $0.agent, "stand": $0.stand] }
        raus["vorlagen"] = n.vorlagen.map(\.name)
        raus["anlegen"] = anlegenAuskunft(w)
        // Auftrag agentsform: gemerkte Projektordner zum Entfernen und die Rechte in Bearbeitung.
        raus["gemerkteProjekte"] = n.gemerkteProjekte
        raus["rechteEntwurf"] = rechteEntwurf.map { ["agent": $0.agent, "werkzeuge": $0.werkzeuge, "bash": $0.bash, "skills": $0.skills] as [String: Any] } ?? [:]
        raus["weltRechte"] = ["modelle": w.modelle.map { $0.map { ["id": $0.id, "verfuegbar": $0.verfuegbar, "grund": $0.grund] as [String: Any] } } as Any? ?? NSNull(),
                              "maschineVorgabe": w.maschineVorgabe, "webZugang": w.webZugang, "rechteAenderbar": w.rechteAenderbar,
                              "skillKatalog": w.skillKatalog.map { "\($0.name) (\($0.ebene))" }] as [String: Any]
        raus["gedaechtnisEntwurf"] = gedaechtnisEntwurf.map { ["agent": $0.agent, "zeichen": $0.text.count, "sha": $0.sha] as [String: Any] } ?? [:]
        raus["tickets"] = tickets(w).map { ["id": $0.id, "titel": $0.titel, "stand": $0.stand, "adressaten": $0.adressaten,
                                            "kind": $0.kind, "prioritaet": $0.prioritaet, "ampel": $0.ampel,
                                            "zeile": WeltenTicketWorte.zeile($0, welt: w),
                                            "standzeile": WeltenTicketWorte.standzeile($0, welt: w) ?? "",
                                            "ordnung": $0.ordnung ?? -1,
                                            "kinder": "\($0.kinderAbgenommen) von \($0.kinderGesamt)"] as [String: Any] }
        raus["inspektorInhalt"] = a.map { agent -> [String: Any] in
            switch blatt {
            case .profil:
                let dienstweg = n.dienstweg(agent.stufe)
                return ["modell": agent.modell, "denkstufe": agent.denkstufe, "fallback": agent.fallback, "maschine": agent.maschine, "spezialgebiet": agent.spezialgebiet, "stand": agent.stand, "postfachOffen": agent.postfachOffen,
                                  "rechte": ["werkzeuge": agent.werkzeuge, "eigeneBash": AgentEntwurf.eigeneMuster(agent.bash, dienstweg), "dienstweg": agent.bash.count - AgentEntwurf.eigeneMuster(agent.bash, dienstweg).count,
                                             "skills": agent.skills, "aenderbar": w.rechteAenderbar, "grund": w.rechteAenderbar ? "" : WeltenInspektor.rechteNichtAusgerollt,
                                             "bearbeiten": rechteEntwurf?.agent == agent.id] as [String: Any],
                                  "lebenszeichen": agent.leben.map { l in ["jetzt": WeltenWorte.leben(agent) ?? (l.stand == "schlaeft" ? "schläft" : WeltenWorte.zustand(agent.zustand)),
                                                                          "art": agent.zug?.laeuft == true ? WeltenWorte.zugArt(agent.zug?.art) : "", "grund": WeltenWorte.grund(l.grund),
                                                                          "wecker": l.wecker ?? "", "ring": agent.ring.rawValue] as [String: Any] } ?? [:]]
            case .protokoll: return ["eintraege": w.tickets.flatMap { $0.verlauf.filter { $0.von == agent.id } }.count + agent.verlauf.count,
                                     "profil": agent.verlauf.map { ["ereignis": $0.ereignis, "notiz": $0.notiz, "aenderungen": $0.aenderungen] }]
            case .gedaechtnis: return ["text": String(agent.gedaechtnis.prefix(200))]
            case .skills:
                let sk = agent.skillAnsicht
                return ["quelle": sk.quelle ?? "", "skills": sk.liste.map { ["name": $0.name, "ebene": $0.ebene, "vorgeladen": $0.vorgeladen, "verdeckt": $0.verdeckt.map(\.ebene), "skillMd": $0.skillMd.count] as [String: Any] },
                        "fehlend": sk.fehlend, "ungueltig": sk.ungueltig, "offen": sk.liste.map(\.name).filter { skillOffen.contains($0) },
                        "messungen": sk.messungen.map { ["art": $0.art, "zeile": WeltenSkillWorte.messung($0)] }, "verlauf": sk.verlauf.map(\.aktion)]
            }
        } ?? ["welt": w.name, "ablage": w.pfad]
        return raus
    }
}
