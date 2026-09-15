// Die typisierten Nutzlasten der Ereignisse, die das Skelett zeichnet. Jede
// Struktur nimmt nur die Felder, die die Oberflaeche braucht, und ignoriert den
// Rest (Codable laesst unbekannte Schluessel durch). Die Feldnamen sind die des
// Kerns (app/src/main/sessions.ts, main.ts `modellSenden`, preload.ts
// `SessionPayload`), unveraendert -- wer hier umbenennt, verliert die
// Vergleichbarkeit mit der Electron-Fassung.
import Foundation

/// Ein Subagent (V19): eigener Pane, zaehlt nicht als Worker.
public struct SubagentEintrag: Codable, Sendable, Equatable, Identifiable {
    public var id: String { paneId.isEmpty ? (agentId.isEmpty ? name : agentId) : paneId }
    public let paneId: String
    public let agentId: String
    public let name: String
    public let type: String

    public init(paneId: String = "", agentId: String = "", name: String = "", type: String = "") {
        self.paneId = paneId; self.agentId = agentId; self.name = name; self.type = type
    }

    enum CodingKeys: String, CodingKey { case paneId, agentId, name, type }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        paneId = try c.decodeIfPresent(String.self, forKey: .paneId) ?? ""
        agentId = try c.decodeIfPresent(String.self, forKey: .agentId) ?? ""
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        type = try c.decodeIfPresent(String.self, forKey: .type) ?? ""
    }

    /// Wie die Zeile heisst: der Name, sonst die Agentenkennung.
    public var anzeigename: String { name.isEmpty ? agentId : name }
}

/// Ein Worker, wie `awb:model` ihn unter `sessions[].workers` traegt
/// (app/src/main/sessions.ts, `WorkerInfo`). Die Felder, die die Seitenleiste
/// und die Uebersicht lesen; der Rest bleibt in der Zeile liegen.
public struct WorkerEintrag: Codable, Sendable, Equatable, Identifiable {
    public var id: String { paneId.isEmpty ? name : paneId }
    public let name: String
    public let kind: String
    public let model: String
    /// Der Ordner, in dem der Worker arbeitet (sein Worktree). Das Agents-Blatt
    /// nennt ihn und klappt ihn im Ordner-Blatt auf; leer, wenn ihn niemand
    /// eingetragen hat (ein Worker, der nur als Pane bekannt ist).
    public let dir: String
    public let paneId: String
    /// running | blocked | stalled | done | unknown
    public let state: String
    public let alive: Bool
    /// Kontextauslastung in Prozent, -1 = unbekannt.
    public let contextPercent: Int
    /// Belegte Tokens, 0 = unbekannt.
    public let contextTokens: Int
    /// Sekunden ohne Bewegung im Transcript, -1 = unbekannt.
    public let idleSeconds: Int
    public let resultPath: String
    /// Der Worker, auf dessen Antrag dieser entstanden ist -- leer, wenn keiner.
    public let requestedBy: String
    /// '' | request | guard
    public let blockedReason: String
    public let subagents: [SubagentEintrag]
    /// Beschriftung eines Workers, der aus einem Pane statt der Zustandsdatei stammt.
    public let titel: String

    public init(name: String, kind: String = "", model: String = "", dir: String = "", paneId: String = "", state: String = "", alive: Bool = false,
                contextPercent: Int = -1, contextTokens: Int = 0, idleSeconds: Int = -1, resultPath: String = "",
                requestedBy: String = "", blockedReason: String = "", subagents: [SubagentEintrag] = [], titel: String = "") {
        self.name = name; self.kind = kind; self.model = model; self.dir = dir; self.paneId = paneId; self.state = state; self.alive = alive
        self.contextPercent = contextPercent; self.contextTokens = contextTokens; self.idleSeconds = idleSeconds
        self.resultPath = resultPath; self.requestedBy = requestedBy; self.blockedReason = blockedReason
        self.subagents = subagents; self.titel = titel
    }

    enum CodingKeys: String, CodingKey {
        case name, kind, model, dir, paneId, state, alive, contextPercent, contextTokens, idleSeconds, resultPath, requestedBy, blockedReason, subagents, titel
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        kind = try c.decodeIfPresent(String.self, forKey: .kind) ?? ""
        model = try c.decodeIfPresent(String.self, forKey: .model) ?? ""
        dir = try c.decodeIfPresent(String.self, forKey: .dir) ?? ""
        paneId = try c.decodeIfPresent(String.self, forKey: .paneId) ?? ""
        state = try c.decodeIfPresent(String.self, forKey: .state) ?? ""
        alive = try c.decodeIfPresent(Bool.self, forKey: .alive) ?? false
        contextPercent = try c.decodeIfPresent(Int.self, forKey: .contextPercent) ?? -1
        contextTokens = try c.decodeIfPresent(Int.self, forKey: .contextTokens) ?? 0
        idleSeconds = try c.decodeIfPresent(Int.self, forKey: .idleSeconds) ?? -1
        resultPath = try c.decodeIfPresent(String.self, forKey: .resultPath) ?? ""
        requestedBy = try c.decodeIfPresent(String.self, forKey: .requestedBy) ?? ""
        blockedReason = try c.decodeIfPresent(String.self, forKey: .blockedReason) ?? ""
        subagents = try c.decodeIfPresent([SubagentEintrag].self, forKey: .subagents) ?? []
        titel = try c.decodeIfPresent(String.self, forKey: .titel) ?? ""
    }

    /// Tokenstand, kompakt -- leer, solange keiner bekannt ist (renderer.ts `tokenKurz`).
    public var tokensKurz: String {
        if contextTokens <= 0 { return "" }
        if contextTokens >= 1_000_000 { return String(format: "%.1fM", Double(contextTokens) / 1_000_000) }
        if contextTokens >= 1000 { return "\(Int((Double(contextTokens) / 1000).rounded()))k" }
        return String(contextTokens)
    }

    /// Was der Worker gerade tut, in Worten (renderer.ts `zustandText`).
    public var zustandText: String {
        switch state {
        case "blocked": return blockedReason == "guard" ? "wartet auf Freigabe eines Befehls" : "wartet auf Entscheidung"
        case "stalled": return "hängt seit \(dauerKurz(idleSeconds))"
        case "unknown": return "nicht einsehbar"
        case "done": return resultPath.isEmpty ? "fertig, kein Ergebnis" : "fertig, Ergebnis da"
        default:
            if contextPercent >= 0 { return "Kontext \(contextPercent) %" }
            return "läuft"
        }
    }
}

func dauerKurz(_ sekunden: Int) -> String {
    if sekunden < 0 { return "?" }
    if sekunden < 60 { return "\(sekunden) s" }
    if sekunden < 3600 { return "\(sekunden / 60) min" }
    return "\(sekunden / 3600) h \((sekunden % 3600) / 60) min"
}

/// Eine Sitzung, wie `awb:model` sie in `sessions` traegt.
public struct SitzungsEintrag: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let name: String
    public let dir: String
    public let machine: String
    public let tmuxSession: String
    /// claude | codex | … -- die Zustandsdatei fuehrt `harness` und `model`, mehr nicht.
    public let harness: String
    /// Die Modellkennung der Sitzung.
    public let model: String
    public let alive: Bool
    /// running | attention | stopped | unreachable
    public let state: String
    public let orchestratorPane: String
    public let workers: [WorkerEintrag]
    public let pendingApprovals: Int
    /// Subagenten ohne zuordenbaren Worker -- sichtbar bleiben sie (V19).
    public let orphanSubagents: [SubagentEintrag]
    /// Merkmale neben `stopped` (sessions.ts): das Ende hat niemand gesehen,
    /// ein Start laeuft gerade, der letzte Start ist gescheitert.
    public let verloren: Bool
    public let startet: Bool
    public let startFehler: Bool
    public let lastActive: String

    public init(id: String, name: String, dir: String, machine: String = "", tmuxSession: String = "", harness: String = "", model: String = "", alive: Bool = true, state: String = "running",
                orchestratorPane: String = "", workers: [WorkerEintrag] = [], pendingApprovals: Int = 0, orphanSubagents: [SubagentEintrag] = [],
                verloren: Bool = false, startet: Bool = false, startFehler: Bool = false, lastActive: String = "") {
        self.id = id; self.name = name; self.dir = dir; self.machine = machine; self.tmuxSession = tmuxSession; self.harness = harness; self.model = model
        self.alive = alive; self.state = state; self.orchestratorPane = orchestratorPane; self.workers = workers
        self.pendingApprovals = pendingApprovals; self.orphanSubagents = orphanSubagents
        self.verloren = verloren; self.startet = startet; self.startFehler = startFehler; self.lastActive = lastActive
    }

    enum CodingKeys: String, CodingKey {
        case id, name, dir, machine, tmuxSession, harness, model, alive, state, orchestratorPane, workers, pendingApprovals, orphanSubagents, verloren, startet, startFehler, lastActive
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        dir = try c.decodeIfPresent(String.self, forKey: .dir) ?? ""
        machine = try c.decodeIfPresent(String.self, forKey: .machine) ?? ""
        tmuxSession = try c.decodeIfPresent(String.self, forKey: .tmuxSession) ?? ""
        harness = try c.decodeIfPresent(String.self, forKey: .harness) ?? ""
        model = try c.decodeIfPresent(String.self, forKey: .model) ?? ""
        alive = try c.decodeIfPresent(Bool.self, forKey: .alive) ?? false
        state = try c.decodeIfPresent(String.self, forKey: .state) ?? ""
        orchestratorPane = try c.decodeIfPresent(String.self, forKey: .orchestratorPane) ?? ""
        workers = try c.decodeIfPresent([WorkerEintrag].self, forKey: .workers) ?? []
        pendingApprovals = try c.decodeIfPresent(Int.self, forKey: .pendingApprovals) ?? 0
        orphanSubagents = try c.decodeIfPresent([SubagentEintrag].self, forKey: .orphanSubagents) ?? []
        verloren = try c.decodeIfPresent(Bool.self, forKey: .verloren) ?? false
        startet = try c.decodeIfPresent(Bool.self, forKey: .startet) ?? false
        startFehler = try c.decodeIfPresent(Bool.self, forKey: .startFehler) ?? false
        lastActive = try c.decodeIfPresent(String.self, forKey: .lastActive) ?? ""
    }

    /// Der Projektname: der letzte Pfadteil des Ordners.
    public var projekt: String {
        let teil = (dir as NSString).lastPathComponent
        return teil.isEmpty ? dir : teil
    }

    /// Lebende Worker -- die Zahl, die die Zusatzzeile nennt (renderer.ts `zusatzzeile`).
    public var lebendeWorker: Int { workers.filter { $0.alive }.count }

    /// Liegt die Sitzung auf einer anderen Maschine als der, die zeichnet?
    public func fern(eigene: String) -> Bool { !machine.isEmpty && machine != eigene }

    /// Die Zusatzzeile unter dem Namen -- wortgleich zur Electron-Fassung
    /// (renderer.ts `zusatzzeile`): die Worker-Zahl zuerst, die Maschine nur,
    /// wenn sie eine andere ist; verloren, startet, gescheitert vor allem.
    public func zusatzzeile(eigene: String) -> String {
        let f = fern(eigene: eigene)
        // Wortlaut und Reihenfolge sind die von texte.ts (`sitzung.verlorenKurz`,
        // `sitzung.startFehlerKurz[Fremd]`, `sitzung.startetKurz[Fremd]`): die
        // Maschine steht hinten, angehaengt mit demselben Trenner wie die
        // Worker-Zahl. Bis zum 06.09. stand hier „verloren, Ende nicht gesehen“
        // und „Start auf X gescheitert“ -- zwei eigene Saetze fuer dieselbe Sache.
        if verloren { return "verloren · lief noch beim letzten Blick" }
        if startFehler { return f ? "Start gescheitert · \(machine)" : "Start gescheitert" }
        if startet { return f ? "startet … · \(machine)" : "startet …" }
        let n = lebendeWorker
        // OHNE WORKER KEIN „0 Worker" (08.09.2026, Entscheidung des Nutzers): die
        // Null sagt nichts und nimmt dem Zustandswort den Platz.
        let w = n == 1 ? "1 Worker" : (n == 0 ? "" : "\(n) Worker")
        // Der Zustand steht auch als Wort da (abnahme.md, Merkmal 5: nie Farbe
        // allein), und die Maschine zuletzt: was zuerst weicht, weiss man am ehesten.
        var teile = [w, zustandText]
        if f { teile.append(machine) }
        return teile.filter { !$0.isEmpty }.joined(separator: " · ")
    }

    /// DER ZUSATZ IN ZWEI TEILEN (08.09.2026, Entscheidung des Nutzers „der Zusatz
    /// bekommt Mindestplatz fuer das Zustandswort").
    ///
    /// Gezeichnet wird die Zeile aus zwei Stuecken: `vorne` darf weichen und
    /// wird VORN gekuerzt („… · pruefmaschine"), `zustand` bleibt immer ganz
    /// stehen. Deshalb steht das Zustandswort im Bild HINTEN, waehrend
    /// `zusatzzeile` oben die gewohnte Reihenfolge behaelt -- sie ist der Satz
    /// fuer das Hilfeschildchen, den Barrierefreiheitsbaum und `awbmac-ctl ui`,
    /// wo nichts gekuerzt wird und die Maschine zuletzt gehoert.
    public func zusatzteile(eigene: String) -> (vorne: String, zustand: String) {
        let f = fern(eigene: eigene)
        if verloren { return ("lief noch beim letzten Blick", "verloren") }
        if startFehler { return (f ? machine : "", "Start gescheitert") }
        if startet { return (f ? machine : "", "startet …") }
        let n = lebendeWorker
        var teile: [String] = []
        if n > 0 { teile.append(n == 1 ? "1 Worker" : "\(n) Worker") }
        if f { teile.append(machine) }
        return (teile.joined(separator: " · "), zustandText)
    }

    /// Der Zustand in Worten -- fuer VoiceOver und das Hilfeschildchen.
    public var zustandText: String {
        switch state {
        case "running": return "läuft"
        case "attention": return "wartet auf Dich"
        case "unreachable": return "Maschine nicht erreichbar"
        default:
            if startFehler { return "Start gescheitert" }
            if startet { return "startet" }
            if verloren { return "verloren" }
            return "beendet"
        }
    }

    /// Worker, die gerade arbeiten oder warten -- die Zahl der Pille „N laufen“
    /// (renderer.ts `laufendeWorker`): lebend und running, blocked oder stalled.
    public var laufendeWorker: Int {
        workers.filter { $0.alive && ["running", "blocked", "stalled"].contains($0.state) }.count
    }

    /// Die lebenden Worker in Listenreihenfolge (renderer.ts `flacheWorker`):
    /// jeder Obere gefolgt von denen, die auf seinen Antrag entstanden sind.
    public var flacheWorker: [WorkerEintrag] {
        let lebende = workers.filter { $0.alive }
        let namen = Set(lebende.map(\.name))
        let obere = lebende.filter { $0.requestedBy.isEmpty || !namen.contains($0.requestedBy) }
        return obere.flatMap { o in [o] + lebende.filter { $0.requestedBy == o.name && namen.contains($0.requestedBy) } }
    }

    /// Ist dieser Worker auf Antrag eines LEBENDEN Workers entstanden (eine Stufe tiefer)?
    public func istKind(_ w: WorkerEintrag) -> Bool {
        !w.requestedBy.isEmpty && workers.contains { $0.alive && $0.name == w.requestedBy }
    }

    /// Die Panes der Worker -- das, was der Umschalter „Worker“ auf die Buehne legt
    /// (renderer.ts `tabZeigen`: die Worker des Tabs, ohne Subagenten).
    public var workerPanes: [String] {
        flacheWorker.map(\.paneId).filter { !$0.isEmpty }
    }

    /// Die Worker des Tabs `i`, nach `capacity.perTab` geschnitten (renderer.ts
    /// `workerImTab`): ein Kind-Worker hat einen eigenen Pane und zaehlt mit.
    public func workerImTab(_ i: Int, perTab: Int) -> [WorkerEintrag] {
        let flach = flacheWorker
        let n = max(1, perTab)
        let von = max(0, i) * n
        guard von < flach.count else { return [] }
        return Array(flach[von..<min(flach.count, von + n)])
    }

    /// Die Panes des Tabs `i` -- der Weg des Umschalters „Worker“ und des Tab-Streifens.
    public func panesImTab(_ i: Int, perTab: Int) -> [String] {
        workerImTab(i, perTab: perTab).map(\.paneId).filter { !$0.isEmpty }
    }

    /// Wieviele Tabs die Worker fuellen (capacity.ts `tabsFor`).
    public func tabs(perTab: Int) -> Int {
        let n = flacheWorker.count
        return n <= 0 ? 0 : Int((Double(n) / Double(max(1, perTab))).rounded(.up))
    }

    /// Alle Panes, die zu Workern gehoeren, samt Subagenten (renderer.ts
    /// `workerAufDerBuehne`): liegt einer davon auf der Buehne, zeigt sie Worker.
    public var workerPanesMitSubagenten: Set<String> {
        var p = Set<String>()
        for w in flacheWorker {
            if !w.paneId.isEmpty { p.insert(w.paneId) }
            for s in w.subagents where !s.paneId.isEmpty { p.insert(s.paneId) }
        }
        for s in orphanSubagents where !s.paneId.isEmpty { p.insert(s.paneId) }
        return p
    }

    /// Die Herkunft unter dem Namen (renderer.ts `zeichneInhaltskopf`): Harness,
    /// Modell, Ordnerkurzpfad -- und die Maschine, wenn es eine andere ist. Was
    /// leer ist, faellt weg statt als Luecke stehenzubleiben.
    public func herkunft(eigene: String) -> String {
        var teile = [harness, model, ModellNutzlast.Projekt.kurz(dir)].filter { !$0.isEmpty }
        if fern(eigene: eigene) { teile.append(machine) }
        return teile.joined(separator: " · ")
    }
}

/// `ui` aus `awb:model` (uistate.ts): was der Mensch an der Leiste eingestellt hat.
public struct AnsichtsZustand: Codable, Sendable, Equatable {
    public let showStopped: Bool
    /// recent | folder | name
    public let sort: String
    public let order: [String]
    /// Die von Hand gezogene Reihenfolge der PROJEKTE (uistate.ts
    /// `projektReihenfolge`, `projekt-order`): ein Ordner je Eintrag. Leer
    /// heisst „niemand hat gezogen"; dann stehen die Projekte so, wie `sort`
    /// und `order` sie ergeben.
    public let projektReihenfolge: [String]
    public let selected: String
    /// Je Sitzung die gemerkte Wahl des Umschalters (`orchestrator` | `worker`,
    /// uistate.ts `flaecheSitzung`): womit die Sitzung AUFGEHEN soll.
    public let flaecheSitzung: [String: String]
    /// Welcher Worker-Tab gewaehlt ist (uistate.ts `workerTab`, `worker-tab`).
    public let workerTab: Int
    /// Die Breite der Seitenleiste in Punkten (uistate.ts `sidebarWidth`,
    /// `sidebar-width`; Vorgabe 232) -- der Mantel stellt sie beim Start her
    /// und meldet, was der Mensch zieht (Auftrag 2.8).
    public let sidebarWidth: Int
    /// Die Breite des Inspektors (uistate.ts `blattBreite`, `blatt-breite`; Vorgabe 360).
    public let blattBreite: Int
    /// Steht das Editor-Blatt eingeklappt (uistate.ts `editorEingeklappt`,
    /// `editor-eingeklappt`)? Dieselbe Ablage wie in der Electron-Fassung.
    public let editorEingeklappt: Bool

    enum CodingKeys: String, CodingKey { case showStopped, sort, order, projektReihenfolge, selected, flaecheSitzung, workerTab, sidebarWidth, blattBreite, editorEingeklappt }

    public init(showStopped: Bool = false, sort: String = "recent", order: [String] = [], projektReihenfolge: [String] = [], selected: String = "", flaecheSitzung: [String: String] = [:], workerTab: Int = 0,
                sidebarWidth: Int = 232, blattBreite: Int = 360, editorEingeklappt: Bool = false) {
        self.showStopped = showStopped; self.sort = sort; self.order = order; self.projektReihenfolge = projektReihenfolge
        self.selected = selected; self.flaecheSitzung = flaecheSitzung
        self.workerTab = workerTab; self.sidebarWidth = sidebarWidth; self.blattBreite = blattBreite
        self.editorEingeklappt = editorEingeklappt
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        showStopped = try c.decodeIfPresent(Bool.self, forKey: .showStopped) ?? false
        sort = try c.decodeIfPresent(String.self, forKey: .sort) ?? "recent"
        order = try c.decodeIfPresent([String].self, forKey: .order) ?? []
        projektReihenfolge = try c.decodeIfPresent([String].self, forKey: .projektReihenfolge) ?? []
        selected = try c.decodeIfPresent(String.self, forKey: .selected) ?? ""
        flaecheSitzung = try c.decodeIfPresent([String: String].self, forKey: .flaecheSitzung) ?? [:]
        workerTab = max(0, try c.decodeIfPresent(Int.self, forKey: .workerTab) ?? 0)
        sidebarWidth = try c.decodeIfPresent(Int.self, forKey: .sidebarWidth) ?? 232
        blattBreite = try c.decodeIfPresent(Int.self, forKey: .blattBreite) ?? 360
        editorEingeklappt = try c.decodeIfPresent(Bool.self, forKey: .editorEingeklappt) ?? false
    }
}

/// `capacity` aus `awb:model` (main.ts `kapazitaet`, capacity.ts): wieviele
/// Panes in einen Tab passen und wieviele Tabs die gewaehlte Sitzung hat. Die
/// Rechnung liegt im Kern und nur dort -- der Mantel schneidet die Worker nach
/// `perTab` in Tabs, genau wie renderer.ts `workerImTab`.
public struct KapazitaetNutzlast: Codable, Sendable, Equatable {
    public let perRow: Int
    public let perColumn: Int
    public let perTab: Int
    public let tabs: Int
    public let workerCount: Int
    public let spalten: Int
    public let zeilen: Int

    enum CodingKeys: String, CodingKey { case perRow, perColumn, perTab, tabs, workerCount, spalten, zeilen }

    public init(perRow: Int = 1, perColumn: Int = 1, perTab: Int = 1, tabs: Int = 0, workerCount: Int = 0, spalten: Int = 1, zeilen: Int = 1) {
        self.perRow = perRow; self.perColumn = perColumn; self.perTab = perTab; self.tabs = tabs
        self.workerCount = workerCount; self.spalten = spalten; self.zeilen = zeilen
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        perRow = max(1, try c.decodeIfPresent(Int.self, forKey: .perRow) ?? 1)
        perColumn = max(1, try c.decodeIfPresent(Int.self, forKey: .perColumn) ?? 1)
        perTab = max(1, try c.decodeIfPresent(Int.self, forKey: .perTab) ?? 1)
        tabs = max(0, try c.decodeIfPresent(Int.self, forKey: .tabs) ?? 0)
        workerCount = max(0, try c.decodeIfPresent(Int.self, forKey: .workerCount) ?? 0)
        spalten = max(1, try c.decodeIfPresent(Int.self, forKey: .spalten) ?? 1)
        zeilen = max(1, try c.decodeIfPresent(Int.self, forKey: .zeilen) ?? 1)
    }
}

// MARK: Statusfuss (`maschinen`, `ampel`, `budget` aus `awb:model`; Auftrag 2.5)

/// Eine Maschine, wie der Kern sie kennt (main.ts `maschinenStand`,
/// fuss-status.ts `MaschinenStand`). `erreichbar == nil` heisst NICHT „nicht
/// erreichbar", sondern „noch nicht nachgesehen"; `pausiert` ist gewollt
/// abgestellt, etwas anderes als ein Ausfall. Beides gleich zu zeichnen
/// versteckt den Ausfall.
public struct MaschinenStand: Codable, Sendable, Equatable, Identifiable {
    public var id: String { name }
    public let name: String
    public let eigen: Bool
    public let erreichbar: Bool?
    /// Alter der letzten Antwort in Sekunden, -1 = nie geantwortet.
    public let alter: Int
    public let fehler: String
    public let sitzungen: Int
    public let worker: Int
    public let pausiert: Bool

    public init(name: String, eigen: Bool = false, erreichbar: Bool? = nil, alter: Int = -1, fehler: String = "",
                sitzungen: Int = 0, worker: Int = 0, pausiert: Bool = false) {
        self.name = name; self.eigen = eigen; self.erreichbar = erreichbar; self.alter = alter; self.fehler = fehler
        self.sitzungen = sitzungen; self.worker = worker; self.pausiert = pausiert
    }

    enum CodingKeys: String, CodingKey { case name, eigen, erreichbar, alter, fehler, sitzungen, worker, pausiert }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        eigen = try c.decodeIfPresent(Bool.self, forKey: .eigen) ?? false
        // `null` im JSON bleibt nil: decodeIfPresent liefert fuer null nil.
        erreichbar = try c.decodeIfPresent(Bool.self, forKey: .erreichbar)
        alter = try c.decodeIfPresent(Int.self, forKey: .alter) ?? -1
        fehler = try c.decodeIfPresent(String.self, forKey: .fehler) ?? ""
        sitzungen = try c.decodeIfPresent(Int.self, forKey: .sitzungen) ?? 0
        worker = try c.decodeIfPresent(Int.self, forKey: .worker) ?? 0
        pausiert = try c.decodeIfPresent(Bool.self, forKey: .pausiert) ?? false
    }

    /// Die Form des Punkts, wortgleich zu den CSS-Klassen der Electron-Karte
    /// (`laeuft` gefuellt, `ruhig` Ring = noch nicht nachgesehen, `aus` hohl
    /// rot = hat nicht geantwortet, `pausiert` gedaempft gefuellt).
    public var punktFarbe: String {
        if pausiert { return "pausiert" }
        if eigen || erreichbar == true { return "laeuft" }
        return erreichbar == nil ? "ruhig" : "aus"
    }

    /// Die Lage im Wort, fuer die Kurzzeile (fuss-status.ts, `lage`).
    public var lageWort: String {
        if eigen { return "hier" }
        if pausiert { return "pausiert" }
        guard let e = erreichbar else { return "nicht nachgesehen" }
        return e ? "erreichbar" : "nicht erreichbar"
    }

    /// Die Kurzzeile der Karte: Lage, Sitzungen, laufende Worker.
    public var kurzzeile: String {
        "\(lageWort) · \(sitzungen)\u{a0}Sitzungen · \(worker)\u{a0}Worker"
    }

    /// Das Alter der letzten Antwort in Worten (fuss-status.ts `alterKurz`).
    public var alterText: String {
        if alter < 0 { return "noch nie geantwortet" }
        if alter < 60 { return "gerade eben" }
        let min = Int((Double(alter) / 60).rounded())
        if min < 60 { return "seit \(min) Min." }
        return "seit \(min / 60) Std. \(min % 60) Min."
    }
}

/// Ein Befund des Pruefstands (ampel.ts `AmpelBefund`): Testsuite oder Hygiene.
public struct AmpelBefund: Codable, Sendable, Equatable {
    public let quelle: String
    public let vorhanden: Bool
    public let rot: Bool
    public let ueberfaellig: Bool
    public let ueberholt: Bool
    public let ageDays: Int
    public let text: String

    public init(quelle: String = "", vorhanden: Bool = false, rot: Bool = false, ueberfaellig: Bool = false, ueberholt: Bool = false, ageDays: Int = -1, text: String = "") {
        self.quelle = quelle; self.vorhanden = vorhanden; self.rot = rot; self.ueberfaellig = ueberfaellig; self.ueberholt = ueberholt
        self.ageDays = ageDays; self.text = text
    }

    enum CodingKeys: String, CodingKey { case quelle, vorhanden, rot, ueberfaellig, ueberholt, ageDays, text }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        quelle = try c.decodeIfPresent(String.self, forKey: .quelle) ?? ""
        vorhanden = try c.decodeIfPresent(Bool.self, forKey: .vorhanden) ?? false
        rot = try c.decodeIfPresent(Bool.self, forKey: .rot) ?? false
        ueberfaellig = try c.decodeIfPresent(Bool.self, forKey: .ueberfaellig) ?? false
        ueberholt = try c.decodeIfPresent(Bool.self, forKey: .ueberholt) ?? false
        ageDays = (try? c.decodeIfPresent(Int.self, forKey: .ageDays)) ?? Int((try? c.decodeIfPresent(Double.self, forKey: .ageDays)) ?? -1)
        text = try c.decodeIfPresent(String.self, forKey: .text) ?? ""
    }
}

/// Der Pruefstand einer Maschine (ampel.ts `AmpelStand`): rot | gelb | gruen | unbekannt.
public struct AmpelStand: Codable, Sendable, Equatable, Identifiable {
    public var id: String { machine }
    public let machine: String
    public let befunde: [AmpelBefund]
    public let farbe: String

    public init(machine: String, befunde: [AmpelBefund] = [], farbe: String = "unbekannt") {
        self.machine = machine; self.befunde = befunde; self.farbe = farbe
    }

    enum CodingKeys: String, CodingKey { case machine, befunde, farbe }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        machine = try c.decodeIfPresent(String.self, forKey: .machine) ?? ""
        befunde = try c.decodeIfPresent([AmpelBefund].self, forKey: .befunde) ?? []
        farbe = try c.decodeIfPresent(String.self, forKey: .farbe) ?? "unbekannt"
    }

    /// Die Befunde in einer Zeile, wie die Electron-Karte sie nennt.
    public var befundText: String {
        let t = befunde.map(\.text).joined(separator: " · ")
        return t.isEmpty ? "nicht nachgesehen" : t
    }
}

/// Der Kontingentstand (budget.ts `BudgetStand`), gelesen aus `wb-budget --json`.
/// Wochenwerte -1, wenn der Ruecksetzpunkt fehlt: dann steht keine Zahl da,
/// statt einer geratenen.
public struct BudgetStand: Codable, Sendable, Equatable {
    public let ok: Bool
    public let error: String
    public let heuteTokens: Int
    public let heuteStunden: Double
    public let hochrechnung24h: Int
    public let text: String
    public let fiveHourPct: Int
    public let sevenDayPct: Int
    public let resetText: String
    public let wocheVerbraucht: Double
    public let wocheErlaubt: Double

    public init(ok: Bool = false, error: String = "", heuteTokens: Int = 0, heuteStunden: Double = 0, hochrechnung24h: Int = 0, text: String = "",
                fiveHourPct: Int = -1, sevenDayPct: Int = -1, resetText: String = "", wocheVerbraucht: Double = -1, wocheErlaubt: Double = -1) {
        self.ok = ok; self.error = error; self.heuteTokens = heuteTokens; self.heuteStunden = heuteStunden; self.hochrechnung24h = hochrechnung24h
        self.text = text; self.fiveHourPct = fiveHourPct; self.sevenDayPct = sevenDayPct; self.resetText = resetText
        self.wocheVerbraucht = wocheVerbraucht; self.wocheErlaubt = wocheErlaubt
    }

    enum CodingKeys: String, CodingKey {
        case ok, error, heuteTokens, heuteStunden, hochrechnung24h, text, fiveHourPct, sevenDayPct, resetText, wocheVerbraucht, wocheErlaubt
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func zahl(_ k: CodingKeys, _ vorgabe: Double) -> Double {
            (try? c.decodeIfPresent(Double.self, forKey: k)) ?? vorgabe
        }
        ok = try c.decodeIfPresent(Bool.self, forKey: .ok) ?? false
        error = try c.decodeIfPresent(String.self, forKey: .error) ?? ""
        heuteTokens = Int(zahl(.heuteTokens, 0))
        heuteStunden = zahl(.heuteStunden, 0)
        hochrechnung24h = Int(zahl(.hochrechnung24h, 0))
        text = try c.decodeIfPresent(String.self, forKey: .text) ?? ""
        fiveHourPct = Int(zahl(.fiveHourPct, -1))
        sevenDayPct = Int(zahl(.sevenDayPct, -1))
        resetText = try c.decodeIfPresent(String.self, forKey: .resetText) ?? ""
        wocheVerbraucht = zahl(.wocheVerbraucht, -1)
        wocheErlaubt = zahl(.wocheErlaubt, -1)
    }

    /// Tokens kompakt (fuss-status.ts `kompakt`): 1,2M, 340k, 512.
    public static func kompakt(_ n: Int) -> String {
        if n >= 1_000_000 { return String(format: "%.1fM", Double(n) / 1_000_000).replacingOccurrences(of: ".", with: ",") }
        if n >= 1000 { return "\(Int((Double(n) / 1000).rounded()))k" }
        return String(n)
    }

    /// „106,3M heute“ -- oder der Kurzhinweis, wenn wb-budget nichts lieferte.
    public var heuteText: String { ok ? "\(Self.kompakt(heuteTokens)) heute" : "Budget: n. v." }
    /// Der Wochenstand ist nur da, wenn der Kern einen Ruecksetzpunkt kennt.
    public var wocheDa: Bool { wocheVerbraucht >= 0 && wocheErlaubt >= 0 }
    public var wocheText: String { "Woche \(Int(wocheVerbraucht.rounded())) %" }
    public var erlaubtText: String { "erlaubt \(Int(wocheErlaubt.rounded())) %" }
    public var drueber: Bool { wocheDa && wocheVerbraucht > wocheErlaubt }
}

/// `awb:model` -- die Sitzungsliste samt Auswahl.
public struct ModellNutzlast: Codable, Sendable, Equatable {
    /// Die SICHTBAREN Sitzungen, vom Kern gefiltert (`showStopped`) und
    /// sortiert (`sort`, `order`) -- die Leiste zeichnet sie in dieser Reihenfolge.
    public let sessions: [SitzungsEintrag]
    /// Wie viele Sitzungen es insgesamt gibt, auch die ausgeblendeten.
    public let all: Int
    public let ui: AnsichtsZustand
    public let selected: String
    public let machine: String
    public let schriftgroesse: Int
    /// Der Statusfuss (Auftrag 2.5): Maschinen, Pruefstand je Maschine, Kontingent.
    public let maschinen: [MaschinenStand]
    public let ampel: [AmpelStand]
    public let budget: BudgetStand?
    /// Kapazitaet der gewaehlten Sitzung (Tabs, Panes je Tab).
    public let capacity: KapazitaetNutzlast
    /// Die Chat-Sitzungen (Auftrag 3.2): eigene Liste NEBEN `sessions`, wie im
    /// Kern (main.ts `chats`) -- eine Chat-Sitzung hat keinen Pane und keinen tmux-Zustand.
    public let chats: [ChatEintrag]
    /// Welche Chat-Sitzung auf der Buehne liegt (`chatGezeigt`); leer = die Kacheln.
    public let chatGezeigt: String
    /// Liegt statt des Gespraechs ein WORKER dieser Chat-Sitzung auf der Buehne?
    public let chatWerkstattGezeigt: String
    /// Die Reihenfolge der Leiste ueber beide Sorten (`leiste`, main.ts): EINE
    /// Sortierung fuer Terminal- und Chat-Sitzungen (der Nutzer, 12.08.).
    public let leiste: [LeistenEintrag]
    // `agentsBlattVorschau` (08.09. bis 14.09.2026) schaltete das Aufgaben-Blatt
    // aus Fassung 26 frei. Seit der Tab „Agents" die Welten zeigt (Auftrag
    // agentsui Nr. 6), gibt es nichts mehr freizuschalten: ein Kern oder eine
    // Einstellungsdatei, die das Feld noch fuehrt, wird beim Lesen ignoriert.

    enum CodingKeys: String, CodingKey { case sessions, all, ui, selected, machine, schriftgroesse, maschinen, ampel, budget, capacity, chats, chatGezeigt, chatWerkstattGezeigt, leiste }

    public init(sessions: [SitzungsEintrag], selected: String, machine: String = "", schriftgroesse: Int = 13, all: Int = -1, ui: AnsichtsZustand = AnsichtsZustand(),
                maschinen: [MaschinenStand] = [], ampel: [AmpelStand] = [], budget: BudgetStand? = nil, capacity: KapazitaetNutzlast = KapazitaetNutzlast(),
                chats: [ChatEintrag] = [], chatGezeigt: String = "", chatWerkstattGezeigt: String = "", leiste: [LeistenEintrag] = []) {
        self.sessions = sessions; self.selected = selected; self.machine = machine; self.schriftgroesse = schriftgroesse
        self.all = all < 0 ? sessions.count : all; self.ui = ui
        self.maschinen = maschinen; self.ampel = ampel; self.budget = budget; self.capacity = capacity
        self.chats = chats; self.chatGezeigt = chatGezeigt; self.chatWerkstattGezeigt = chatWerkstattGezeigt; self.leiste = leiste
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        sessions = try c.decodeIfPresent([SitzungsEintrag].self, forKey: .sessions) ?? []
        all = try c.decodeIfPresent(Int.self, forKey: .all) ?? sessions.count
        ui = try c.decodeIfPresent(AnsichtsZustand.self, forKey: .ui) ?? AnsichtsZustand()
        selected = try c.decodeIfPresent(String.self, forKey: .selected) ?? ""
        machine = try c.decodeIfPresent(String.self, forKey: .machine) ?? ""
        schriftgroesse = try c.decodeIfPresent(Int.self, forKey: .schriftgroesse) ?? 13
        maschinen = try c.decodeIfPresent([MaschinenStand].self, forKey: .maschinen) ?? []
        ampel = try c.decodeIfPresent([AmpelStand].self, forKey: .ampel) ?? []
        budget = try c.decodeIfPresent(BudgetStand.self, forKey: .budget)
        capacity = (try? c.decodeIfPresent(KapazitaetNutzlast.self, forKey: .capacity)) ?? KapazitaetNutzlast()
        chats = (try? c.decodeIfPresent([ChatEintrag].self, forKey: .chats)) ?? []
        chatGezeigt = try c.decodeIfPresent(String.self, forKey: .chatGezeigt) ?? ""
        chatWerkstattGezeigt = try c.decodeIfPresent(String.self, forKey: .chatWerkstattGezeigt) ?? ""
        leiste = (try? c.decodeIfPresent([LeistenEintrag].self, forKey: .leiste)) ?? []
    }

    /// Die gezeigte Chat-Sitzung, wenn eine auf der Buehne liegt (oder ihr Worker).
    public var gezeigterChat: ChatEintrag? {
        let id = chatGezeigt.isEmpty ? chatWerkstattGezeigt : chatGezeigt
        guard !id.isEmpty else { return nil }
        return chats.first { $0.id == id }
    }

    /// Worker, die ueber alle sichtbaren Sitzungen arbeiten oder warten -- die
    /// Zahl der Fusszeile „N Worker laufen“ (renderer.ts `zeichneStatus`).
    public var laufendeWorkerGesamt: Int { sessions.reduce(0) { $0 + $1.laufendeWorker } }

    /// Der Pruefstand einer Maschine, wenn der Kern einen kennt.
    public func ampel(fuer maschine: String) -> AmpelStand? { ampel.first { $0.machine == maschine } }

    /// Die Karten: die Maschinen des Kerns, oder -- kennt er keine (aelterer
    /// Kern) -- eine Karte je Pruefstand (fuss-status.ts `gezeigt`).
    public var maschinenKarten: [MaschinenStand] {
        if !maschinen.isEmpty { return maschinen }
        return ampel.map { MaschinenStand(name: $0.machine, eigen: $0.machine == machine, erreichbar: $0.machine == machine ? true : nil) }
    }

    /// Sitzungen UND Chat-Sitzungen nach Projektordner gruppiert (renderer.ts
    /// `projektKnoten`): die Reihenfolge innerhalb eines Projekts kommt aus
    /// `leiste` (eine Sortierung fuer beide Sorten); Projekte in der Reihenfolge
    /// der ersten Nennung. Ohne `leiste` (aelterer Kern): erst Sitzungen, dann Chats.
    public var projekte: [Projekt] {
        var reihenfolge: [String] = []
        var gruppen: [String: [Projekt.Zeile]] = [:]
        let sitzungen = Dictionary(sessions.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let chatsNachId = Dictionary(chats.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        var zeilen: [Projekt.Zeile] = []
        if leiste.isEmpty {
            zeilen = sessions.map { .sitzung($0) } + chats.map { .chat($0) }
        } else {
            for e in leiste {
                if e.art == "chat", let c = chatsNachId[e.id] { zeilen.append(.chat(c)) }
                else if let s = sitzungen[e.id] { zeilen.append(.sitzung(s)) }
            }
            // Was der Kern in `leiste` nicht nennt (Uebergang), haengt hinten an.
            let genannt = Set(leiste.map(\.id))
            zeilen += sessions.filter { !genannt.contains($0.id) }.map { .sitzung($0) }
            zeilen += chats.filter { !genannt.contains($0.id) }.map { .chat($0) }
        }
        for z in zeilen {
            if gruppen[z.dir] == nil { reihenfolge.append(z.dir) }
            gruppen[z.dir, default: []].append(z)
        }
        return reihenfolge.map { Projekt(dir: $0, zeilen: gruppen[$0]!) }
    }

    /// Ein Projekt der Leiste: der Ordner und seine Zeilen in Leistenreihenfolge.
    public struct Projekt: Sendable, Equatable, Identifiable {
        /// Eine Zeile der Leiste: Terminal-Sitzung oder Chat-Sitzung.
        public enum Zeile: Sendable, Equatable, Identifiable {
            case sitzung(SitzungsEintrag)
            case chat(ChatEintrag)
            public var id: String {
                switch self {
                case .sitzung(let s): return s.id
                case .chat(let c): return "chat:" + c.id
                }
            }
            public var dir: String {
                switch self {
                case .sitzung(let s): return s.dir
                case .chat(let c): return c.ordner
                }
            }
            /// Die Kennung, wie der KERN sie fuehrt (`leiste`, `order`): ohne
            /// das `chat:`-Praefix, das nur die Liste dieser Fassung braucht,
            /// um zwei Sorten in einer Auswahl auseinanderzuhalten.
            public var kennung: String {
                switch self {
                case .sitzung(let s): return s.id
                case .chat(let c): return c.id
                }
            }
        }
        public var id: String { dir }
        public let projekt: String
        public let dir: String
        public let zeilen: [Zeile]
        /// Nur die Terminal-Sitzungen (fuer alles, was Panes braucht).
        public let sitzungen: [SitzungsEintrag]
        /// Nur die Chat-Sitzungen.
        public let chats: [ChatEintrag]

        public init(dir: String, zeilen: [Zeile]) {
            self.dir = dir
            self.zeilen = zeilen
            let teil = (dir as NSString).lastPathComponent
            self.projekt = teil.isEmpty ? dir : teil
            self.sitzungen = zeilen.compactMap { if case .sitzung(let s) = $0 { return s } else { return nil } }
            self.chats = zeilen.compactMap { if case .chat(let c) = $0 { return c } else { return nil } }
        }
        /// Wie viele Sitzungen im Projekt auf den Menschen warten (`attention`).
        public var wartet: Int { sitzungen.filter { $0.state == "attention" }.count }
        /// Der Ordner, kurz: `~` fuer das Home, sonst der ganze Pfad.
        public var kurzpfad: String { Self.kurz(dir) }

        /// Ein Ordner, kurz: `~` fuer das Home, sonst der ganze Pfad.
        public static func kurz(_ dir: String) -> String {
            // HOME aus der Umgebung zuerst: NSHomeDirectory nennt das echte Home,
            // auch wenn eine Pruefung mit eigenem HOME laeuft (gemessen 06.09.).
            let home = ProcessInfo.processInfo.environment["HOME"].flatMap { $0.isEmpty ? nil : $0 } ?? NSHomeDirectory()
            if dir == home { return "~" }
            if dir.hasPrefix(home + "/") { return "~" + dir.dropFirst(home.count) }
            return dir
        }
    }
}

/// Eine Chat-Sitzung in `awb:model` (`chats`, main.ts): Buchfuehrung plus
/// gemessenes `laeuft` und die Worker ihrer Werkstatt (nur fuer die gezeigte
/// frisch, chatbuehne.ts `workerVon`).
public struct ChatEintrag: Codable, Sendable, Equatable, Identifiable {
    public struct Worker: Codable, Sendable, Equatable, Identifiable {
        public var id: String { paneId }
        public let name: String
        public let paneId: String
        public let laeuft: Bool
        public init(name: String, paneId: String, laeuft: Bool) { self.name = name; self.paneId = paneId; self.laeuft = laeuft }
        enum CodingKeys: String, CodingKey { case name, paneId, laeuft }
        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
            paneId = try c.decodeIfPresent(String.self, forKey: .paneId) ?? ""
            laeuft = try c.decodeIfPresent(Bool.self, forKey: .laeuft) ?? false
        }
    }
    public let id: String
    public let name: String
    public let ordner: String
    public let zuletzt: String
    public let laeuft: Bool
    /// Die tmux-Werkstatt dieser Sitzung (leer = keine).
    public let tmuxSession: String
    public let worker: [Worker]

    public init(id: String, name: String, ordner: String, zuletzt: String = "", laeuft: Bool = false, tmuxSession: String = "", worker: [Worker] = []) {
        self.id = id; self.name = name; self.ordner = ordner; self.zuletzt = zuletzt; self.laeuft = laeuft; self.tmuxSession = tmuxSession; self.worker = worker
    }

    enum CodingKeys: String, CodingKey { case id, name, ordner, zuletzt, laeuft, tmuxSession, worker }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        ordner = try c.decodeIfPresent(String.self, forKey: .ordner) ?? ""
        zuletzt = try c.decodeIfPresent(String.self, forKey: .zuletzt) ?? ""
        laeuft = try c.decodeIfPresent(Bool.self, forKey: .laeuft) ?? false
        tmuxSession = try c.decodeIfPresent(String.self, forKey: .tmuxSession) ?? ""
        worker = (try? c.decodeIfPresent([Worker].self, forKey: .worker)) ?? []
    }

    /// Der Projektname: der letzte Pfadteil des Ordners.
    public var projekt: String {
        let teil = (ordner as NSString).lastPathComponent
        return teil.isEmpty ? ordner : teil
    }

    /// Lebende Worker in der Werkstatt.
    public var lebendeWorker: Int { worker.filter { $0.laeuft }.count }

    /// Die Zusatzzeile unter dem Namen (renderer.ts `chatZeile`): nur die Worker-Zahl,
    /// keine Maschine -- ein Gespraech laeuft immer hier.
    public var zusatzzeile: String {
        let n = lebendeWorker
        return n == 1 ? "1 Worker" : "\(n) Worker"
    }
}

/// Ein Eintrag der gemeinsamen Leistenreihenfolge (`leiste`, main.ts).
public struct LeistenEintrag: Codable, Sendable, Equatable {
    /// terminal | chat
    public let art: String
    public let id: String
    public init(art: String, id: String) { self.art = art; self.id = id }
}

/// `awb:umbenennen` -- der Kern bittet die Oberflaeche um einen neuen Namen.
public struct UmbenennenNutzlast: Codable, Sendable, Equatable {
    public let id: String
    public let name: String
    public let dir: String

    enum CodingKeys: String, CodingKey { case id, name, dir }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? ""
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        dir = try c.decodeIfPresent(String.self, forKey: .dir) ?? ""
    }
}

/// `awb:meldung` -- eine Zeile fuer den Menschen.
public struct MeldungNutzlast: Codable, Sendable, Equatable {
    public let text: String
    public let dauerMs: Int

    enum CodingKeys: String, CodingKey { case text, dauerMs }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        text = try c.decodeIfPresent(String.self, forKey: .text) ?? ""
        dauerMs = try c.decodeIfPresent(Int.self, forKey: .dauerMs) ?? 4000
    }
}

/// `awb:session` -- die angehaengte tmux-Sitzung.
public struct SitzungsNutzlast: Codable, Sendable, Equatable {
    public struct Pane: Codable, Sendable, Equatable {
        public let paneId: String
        public let windowId: String
        public let width: Int
        public let height: Int
        public let active: Bool
    }
    public let session: String
    public let cols: Int
    public let rows: Int
    public let activePane: String
    public let panes: [Pane]

    enum CodingKeys: String, CodingKey { case session, cols, rows, activePane, panes }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        session = try c.decodeIfPresent(String.self, forKey: .session) ?? ""
        cols = try c.decodeIfPresent(Int.self, forKey: .cols) ?? 80
        rows = try c.decodeIfPresent(Int.self, forKey: .rows) ?? 24
        activePane = try c.decodeIfPresent(String.self, forKey: .activePane) ?? ""
        panes = try c.decodeIfPresent([Pane].self, forKey: .panes) ?? []
    }
}

/// `awb:layout` -- was gerade gezeichnet wird: eine Lage aus Panes mit
/// Momentaufnahme (`inhalt`) und Rueckblick (`historie`).
public struct LageNutzlast: Codable, Sendable, Equatable {
    public struct Kachel: Codable, Sendable, Equatable {
        public let paneId: String
        public let x: Int
        public let y: Int
        public let cols: Int
        public let rows: Int
        public init(paneId: String, x: Int = 0, y: Int = 0, cols: Int, rows: Int) {
            self.paneId = paneId; self.x = x; self.y = y; self.cols = cols; self.rows = rows
        }
    }
    /// Die Fenstergroesse, in der die Kaesten stehen (paneflaeche.ts `raster`).
    public struct Raster: Codable, Sendable, Equatable {
        public let cols: Int
        public let rows: Int
        public init(cols: Int, rows: Int) { self.cols = cols; self.rows = rows }
    }
    /// Ein angeforderter Pane, den es nicht (mehr) gibt -- mit dem Grund.
    public struct Fehlend: Codable, Sendable, Equatable {
        public let pane: String
        public let grund: String
        enum CodingKeys: String, CodingKey { case pane, grund }
        public init(pane: String, grund: String) { self.pane = pane; self.grund = grund }
        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            pane = try c.decodeIfPresent(String.self, forKey: .pane) ?? ""
            grund = try c.decodeIfPresent(String.self, forKey: .grund) ?? ""
        }
    }
    public let art: String
    public let cols: Int
    public let rows: Int
    public let aktiv: String
    public let panes: [Kachel]
    public let inhalt: [String: String]
    public let historie: [String: String]
    /// Nur `tab`: Spalten des Gitters aus der Kapazitaetsrechnung.
    public let spalten: Int
    /// Ob die Buehne frei kacheln darf (jeder Pane in eigenem tmux-Fenster).
    public let frei: Bool
    /// Alle gezeigten Panes liegen in EINEM Fenster, das genau sie traegt.
    public let raster: Raster?
    /// Wie `raster`, aber das Fenster traegt mehr Panes als gezeigt (Layout `split`).
    public let rasterTeil: Raster?
    public let fehlend: [Fehlend]

    enum CodingKeys: String, CodingKey { case art, cols, rows, aktiv, panes, inhalt, historie, spalten, frei, raster, rasterTeil, fehlend }

    public init(art: String = "pane", cols: Int = 80, rows: Int = 24, aktiv: String = "", panes: [Kachel] = [], inhalt: [String: String] = [:],
                historie: [String: String] = [:], spalten: Int = 1, frei: Bool = false, raster: Raster? = nil, rasterTeil: Raster? = nil, fehlend: [Fehlend] = []) {
        self.art = art; self.cols = cols; self.rows = rows; self.aktiv = aktiv; self.panes = panes; self.inhalt = inhalt; self.historie = historie
        self.spalten = spalten; self.frei = frei; self.raster = raster; self.rasterTeil = rasterTeil; self.fehlend = fehlend
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        art = try c.decodeIfPresent(String.self, forKey: .art) ?? "pane"
        cols = try c.decodeIfPresent(Int.self, forKey: .cols) ?? 80
        rows = try c.decodeIfPresent(Int.self, forKey: .rows) ?? 24
        aktiv = try c.decodeIfPresent(String.self, forKey: .aktiv) ?? ""
        panes = try c.decodeIfPresent([Kachel].self, forKey: .panes) ?? []
        inhalt = try c.decodeIfPresent([String: String].self, forKey: .inhalt) ?? [:]
        historie = try c.decodeIfPresent([String: String].self, forKey: .historie) ?? [:]
        spalten = max(1, try c.decodeIfPresent(Int.self, forKey: .spalten) ?? 1)
        frei = try c.decodeIfPresent(Bool.self, forKey: .frei) ?? false
        raster = try? c.decodeIfPresent(Raster.self, forKey: .raster)
        rasterTeil = try? c.decodeIfPresent(Raster.self, forKey: .rasterTeil)
        fehlend = try c.decodeIfPresent([Fehlend].self, forKey: .fehlend) ?? []
    }
}

/// `awb:output` -- Bytes eines Panes, Base64.
public struct AusgabeNutzlast: Codable, Sendable, Equatable {
    public let paneId: String
    public let data: String

    public var bytes: Data { Data(base64Encoded: data) ?? Data() }
}

public enum Nutzlast {
    public static func lesen<T: Decodable>(_ typ: T.Type, aus zeile: Data) throws -> T {
        try JSONDecoder().decode(typ, from: zeile)
    }
}

// MARK: Freigaben (`awb:freigaben`, app/src/main/freigaben.ts)

/// Ein Antrag eines Workers auf einen guenstigeren Worker (`RequestEntry`).
/// Jedes Feld stammt aus einer JSON-Datei, die ein WORKER schreibt -- die
/// Oberflaeche setzt es als Text, nie als Markup.
public struct AntragEintrag: Codable, Sendable, Equatable, Identifiable {
    public var id: String { path }
    public let path: String
    public let ts: String
    public let parent: String
    public let parentModel: String
    public let childName: String
    public let childModel: String
    public let childEffort: String
    public let dir: String
    public let files: [String]
    public let task: String
    public let doneCriterion: String
    public let whySeparable: String
    public let est: String

    public init(path: String, ts: String = "", parent: String = "", parentModel: String = "", childName: String = "",
                childModel: String = "", childEffort: String = "", dir: String = "", files: [String] = [], task: String = "",
                doneCriterion: String = "", whySeparable: String = "", est: String = "") {
        self.path = path; self.ts = ts; self.parent = parent; self.parentModel = parentModel; self.childName = childName
        self.childModel = childModel; self.childEffort = childEffort; self.dir = dir; self.files = files; self.task = task
        self.doneCriterion = doneCriterion; self.whySeparable = whySeparable; self.est = est
    }

    enum CodingKeys: String, CodingKey {
        case path, ts, parent, parentModel, childName, childModel, childEffort, dir, files, task, doneCriterion, whySeparable, est
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        path = try c.decodeIfPresent(String.self, forKey: .path) ?? ""
        ts = try c.decodeIfPresent(String.self, forKey: .ts) ?? ""
        parent = try c.decodeIfPresent(String.self, forKey: .parent) ?? ""
        parentModel = try c.decodeIfPresent(String.self, forKey: .parentModel) ?? ""
        childName = try c.decodeIfPresent(String.self, forKey: .childName) ?? ""
        childModel = try c.decodeIfPresent(String.self, forKey: .childModel) ?? ""
        childEffort = try c.decodeIfPresent(String.self, forKey: .childEffort) ?? ""
        dir = try c.decodeIfPresent(String.self, forKey: .dir) ?? ""
        files = try c.decodeIfPresent([String].self, forKey: .files) ?? []
        task = try c.decodeIfPresent(String.self, forKey: .task) ?? ""
        doneCriterion = try c.decodeIfPresent(String.self, forKey: .doneCriterion) ?? ""
        whySeparable = try c.decodeIfPresent(String.self, forKey: .whySeparable) ?? ""
        est = try c.decodeIfPresent(String.self, forKey: .est) ?? ""
    }

    /// Modell samt Denkstufe, wie das Blatt es nennt (`modell:effort`).
    public var modellText: String { childEffort.isEmpty ? childModel : "\(childModel):\(childEffort)" }
    /// Der Projektname statt des Vollpfads (Electron-Befund 2 vom 05.09.).
    public var projekt: String {
        let teil = (dir as NSString).lastPathComponent
        return teil.isEmpty ? dir : teil
    }
}

/// Ein angehaltener Worker (`GuardBlockEntry`): `wartet` ist die mittlere
/// Stufe mit Freigeben/Ablehnen, sonst eine harte Ablehnung als Befund.
public struct GuardBlockEintrag: Codable, Sendable, Equatable, Identifiable {
    public var id: String { path.isEmpty ? pane : path }
    public let path: String
    public let pane: String
    public let guardName: String
    public let reason: String
    public let command: String
    public let cwd: String
    public let ts: String
    public let sessionId: String
    public let sessionName: String
    public let machine: String
    public let workerName: String
    public let unbekannterPane: Bool
    public let wartet: Bool
    public let muster: String
    public let musterGrund: String
    public let schluessel: String

    public init(path: String = "", pane: String = "", guardName: String = "", reason: String = "", command: String = "", cwd: String = "",
                ts: String = "", sessionId: String = "", sessionName: String = "", machine: String = "", workerName: String = "",
                unbekannterPane: Bool = false, wartet: Bool = false, muster: String = "", musterGrund: String = "", schluessel: String = "") {
        self.path = path; self.pane = pane; self.guardName = guardName; self.reason = reason; self.command = command; self.cwd = cwd
        self.ts = ts; self.sessionId = sessionId; self.sessionName = sessionName; self.machine = machine; self.workerName = workerName
        self.unbekannterPane = unbekannterPane; self.wartet = wartet; self.muster = muster; self.musterGrund = musterGrund
        self.schluessel = schluessel
    }

    enum CodingKeys: String, CodingKey {
        case path, pane, reason, command, cwd, ts, sessionId, sessionName, machine, workerName, unbekannterPane, wartet, muster, musterGrund, schluessel
        case guardName = "guard"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        path = try c.decodeIfPresent(String.self, forKey: .path) ?? ""
        pane = try c.decodeIfPresent(String.self, forKey: .pane) ?? ""
        guardName = try c.decodeIfPresent(String.self, forKey: .guardName) ?? ""
        reason = try c.decodeIfPresent(String.self, forKey: .reason) ?? ""
        command = try c.decodeIfPresent(String.self, forKey: .command) ?? ""
        cwd = try c.decodeIfPresent(String.self, forKey: .cwd) ?? ""
        ts = try c.decodeIfPresent(String.self, forKey: .ts) ?? ""
        sessionId = try c.decodeIfPresent(String.self, forKey: .sessionId) ?? ""
        sessionName = try c.decodeIfPresent(String.self, forKey: .sessionName) ?? ""
        machine = try c.decodeIfPresent(String.self, forKey: .machine) ?? ""
        workerName = try c.decodeIfPresent(String.self, forKey: .workerName) ?? ""
        unbekannterPane = try c.decodeIfPresent(Bool.self, forKey: .unbekannterPane) ?? false
        wartet = try c.decodeIfPresent(Bool.self, forKey: .wartet) ?? false
        muster = try c.decodeIfPresent(String.self, forKey: .muster) ?? ""
        musterGrund = try c.decodeIfPresent(String.self, forKey: .musterGrund) ?? ""
        schluessel = try c.decodeIfPresent(String.self, forKey: .schluessel) ?? ""
    }

    /// Wer da steht: der Worker, sonst der Pane (freigaben-view.ts `zeileBlock`).
    public var wer: String {
        if unbekannterPane { return "Pane \(pane) (keiner bekannten Sitzung zugeordnet)" }
        return workerName.isEmpty ? pane : workerName
    }
}

/// Eine Gruppe des Guard-Verlaufs (`GuardLogGruppe`): welches Muster wie oft anschlug.
public struct GuardLogGruppe: Codable, Sendable, Equatable, Identifiable {
    public var id: String { "\(guardName)\u{0}\(reason)" }
    public let guardName: String
    public let reason: String
    public let anzahl: Int
    public let ersteMs: Double
    public let letzteMs: Double
    public let letzterBefehl: String

    public init(guardName: String = "", reason: String = "", anzahl: Int = 0, ersteMs: Double = 0, letzteMs: Double = 0, letzterBefehl: String = "") {
        self.guardName = guardName; self.reason = reason; self.anzahl = anzahl; self.ersteMs = ersteMs; self.letzteMs = letzteMs
        self.letzterBefehl = letzterBefehl
    }

    enum CodingKeys: String, CodingKey {
        case reason, anzahl, ersteMs, letzteMs, letzterBefehl
        case guardName = "guard"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        guardName = try c.decodeIfPresent(String.self, forKey: .guardName) ?? ""
        reason = try c.decodeIfPresent(String.self, forKey: .reason) ?? ""
        anzahl = try c.decodeIfPresent(Int.self, forKey: .anzahl) ?? 0
        ersteMs = try c.decodeIfPresent(Double.self, forKey: .ersteMs) ?? 0
        letzteMs = try c.decodeIfPresent(Double.self, forKey: .letzteMs) ?? 0
        letzterBefehl = try c.decodeIfPresent(String.self, forKey: .letzterBefehl) ?? ""
    }
}

/// `awb:freigaben` -- Antraege, angehaltene Worker, Verlauf. Kommt im Takt des Kerns (2 s).
public struct FreigabenNutzlast: Codable, Sendable, Equatable {
    public let requests: [AntragEintrag]
    public let guardBlocks: [GuardBlockEintrag]
    public let guardLog: [GuardLogGruppe]

    enum CodingKeys: String, CodingKey { case requests, guardBlocks, guardLog }

    public init(requests: [AntragEintrag] = [], guardBlocks: [GuardBlockEintrag] = [], guardLog: [GuardLogGruppe] = []) {
        self.requests = requests; self.guardBlocks = guardBlocks; self.guardLog = guardLog
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        requests = try c.decodeIfPresent([AntragEintrag].self, forKey: .requests) ?? []
        guardBlocks = try c.decodeIfPresent([GuardBlockEintrag].self, forKey: .guardBlocks) ?? []
        guardLog = try c.decodeIfPresent([GuardLogGruppe].self, forKey: .guardLog) ?? []
    }

    /// Was auf eine Entscheidung wartet, in der Reihenfolge der Electron-Leiste
    /// (renderer.ts `offeneFreigaben`): erst die Rueckfragen der mittleren
    /// Stufe, dann die Antraege. Eine harte Ablehnung ist keine Frage.
    public var offene: [OffeneFreigabe] {
        var raus: [OffeneFreigabe] = []
        for b in guardBlocks where b.wartet {
            raus.append(OffeneFreigabe(art: .rueckfrage, wer: b.workerName.isEmpty ? b.pane : b.workerName,
                                       wo: "\(b.sessionName.isEmpty ? b.sessionId : b.sessionName) · \(b.machine)",
                                       worum: b.command, sessionId: b.sessionId, pane: b.pane, schluessel: b.schluessel, pfad: b.path))
        }
        for r in requests {
            raus.append(OffeneFreigabe(art: .antrag, wer: r.parent, wo: r.projekt,
                                       worum: "Antrag auf einen Worker \(r.childName) mit \(r.modellText)",
                                       sessionId: "", pane: "", schluessel: "", pfad: r.path))
        }
        return raus
    }
}

/// Ein Eintrag der Freigabeleiste (renderer.ts `OffeneFreigabe`).
public struct OffeneFreigabe: Sendable, Equatable, Identifiable {
    public enum Art: String, Sendable { case rueckfrage, antrag }
    public var id: String { "\(art.rawValue):\(pfad.isEmpty ? schluessel : pfad)" }
    public let art: Art
    public let wer: String
    public let wo: String
    public let worum: String
    public let sessionId: String
    public let pane: String
    public let schluessel: String
    public let pfad: String

    public init(art: Art, wer: String, wo: String, worum: String, sessionId: String, pane: String, schluessel: String, pfad: String) {
        self.art = art; self.wer = wer; self.wo = wo; self.worum = worum
        self.sessionId = sessionId; self.pane = pane; self.schluessel = schluessel; self.pfad = pfad
    }
}
