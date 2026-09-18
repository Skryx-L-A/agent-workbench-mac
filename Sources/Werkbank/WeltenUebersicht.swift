// DIE GESTALTUNGSRUNDE DES TABS „AGENTS" (14.09.2026, Auftrag agentsux Nr. 1).
//
// der Nutzer nach der ausgerollten Fassung: „Ich sehe nicht, wie ich neue Agents oder
// Workplaces für mehrere Agents erstelle", und vom Vorab-Fenster: „Die Ansicht wirkt
// noch zu leer und unübersichtlich; Erstellung und Verwaltung sind noch nicht
// benutzerfreundlich." Diese Datei traegt die Antworten darauf:
//
//   - WeltenEinladung: der Leerzustand ohne jede Welt. Er erklaert, was eine Welt ist
//     (Projektordner oder Global, Plan Abschnitt 11), legt eine an und sagt, was danach kommt.
//   - WeltenWahlMenue und WeltenNeuEintraege: das Menue der Welten oben links mit den
//     Eintraegen zum Anlegen („im Dropdown oben links, Plus zum Anlegen").
//   - WeltenAgentAnlegenKnopf: „Agent anlegen" beschriftet statt eines Plus von 13 Punkt.
//   - WeltenUebersicht: die Mitte, mit der eine Welt aufgeht -- was dich braucht, Karten je
//     Agent mit Stand, letzter Meldung und offenen Tickets, die offenen Tickets der Welt und
//     die letzten Zeilen im Kanal. Eine Welt ohne Hauptagenten laedt dort zu ihm ein.
//
// Gestaltung nach apple-native-design: Systemtextstile und -farben, Karten mit Flaeche,
// Abstand und Rundung statt Gitternetz, neben jedem Punkt ein Wort, keine Emojis, keine
// neuen Figuren (die Neugestaltung der Figuren ist gesperrt). Jede Handlung geht wie
// ueberall ueber WeltenZustand an den Kern.
import AppKit
import SwiftUI

// MARK: Worte und Ableitungen

enum WeltenUebersichtWorte {
    static let endstaende: Set<String> = ["abgenommen", "verworfen"]

    /// Die zweite Zeile unter „Übersicht" in der Leiste.
    static func leistenzeile(_ w: Welt) -> String {
        guard !w.agenten.isEmpty else { return "Noch keine Agenten" }
        let a = w.agenten.count == 1 ? "1 Agent" : "\(w.agenten.count) Agenten"
        return "\(a) · \(w.ticketsOffen == 1 ? "1 Ticket" : "\(w.ticketsOffen) Tickets") offen"
    }

    /// Auftrag fernwelten: mit der Maschine der Ablage („myproject · peer").
    static func menuname(_ w: Welt) -> String { [w.art == "global" ? "Global" : w.name, WeltenWorte.maschine(w.maschine)].filter { !$0.isEmpty }.joined(separator: " · ") }
    static func symbol(_ w: Welt) -> String { w.art == "global" ? "globe" : "folder" }

    /// Die juengste Nachricht, die dieser Agent geschrieben hat: Kanal, Einzelchat oder Direktchat.
    static func letzteMeldung(_ w: Welt, _ id: String) -> WeltNachricht? {
        var alle = w.kanal.filter { $0.von == id }
        if let a = w.agent(id) { alle += a.einzelchat.compactMap(\.nachricht).filter { $0.von == id } }
        alle += w.direktchats.flatMap(\.nachrichten).filter { $0.von == id }
        return alle.max { ($0.zeit, $0.id) < ($1.zeit, $1.id) }
    }

    /// Die Tickets eines Agenten, die noch nicht abgenommen oder verworfen sind.
    static func offeneTickets(_ w: Welt, _ id: String) -> [WeltTicket] {
        guard let a = w.agent(id) else { return [] }
        return w.tickets.filter { a.tickets.contains($0.id) && !endstaende.contains($0.stand) }
    }

    /// Die offenen Tickets der Welt, juengste Aenderung zuerst.
    static func offeneTickets(_ w: Welt) -> [WeltTicket] {
        w.tickets.filter { !endstaende.contains($0.stand) }
            .sorted { $0.geaendert != $1.geaendert ? $0.geaendert > $1.geaendert : $0.id < $1.id }
    }

    /// Die Karten der Mitte: Hauptagent zuerst, dann in der Reihenfolge des Kerns (Handlungsbedarf).
    static func kartenFolge(_ w: Welt) -> [String] {
        var raus: [String] = w.hauptagent.map { [$0] } ?? []
        for id in w.liste where !raus.contains(id) { raus.append(id) }
        for a in w.agenten where !raus.contains(a.id) { raus.append(a.id) }
        return raus
    }

    struct BrauchtDich: Identifiable, Equatable {
        let id: String
        let titel: String
        let text: String
        let knopf: String
        /// Wohin der Knopf fuehrt: `agent:<id>`.
        let ziel: String
        /// Auftrag agentsform: die offene Frage, die hier gleich beantwortet werden kann; nil bei einer Nachricht.
        var frage: String? = nil
    }

    /// Was den Menschen braucht: offene Fragen (Plan Abschnitt 13), markierte, noch nicht
    /// quittierte Nachrichten und -- seit tickets4 -- Tickets im Stand `braucht dich` mit ihrem
    /// Grund (Plan Sätze 21, 31, 35).
    static func brauchtDich(_ w: Welt) -> [BrauchtDich] {
        var raus = w.offeneFragen.map { f in
            BrauchtDich(id: "frage:\(f.id)", titel: "Frage von \(w.anzeigename(f.von))", text: f.text, knopf: "Im Chat ansehen",
                        ziel: "agent:\(w.hauptagent ?? f.von)", frage: f.id)
        }
        for m in w.markiertOffen {
            let nachricht = (w.agent(m.von)?.einzelchat.compactMap(\.nachricht) ?? []).first { $0.id == m.zustellung }
                ?? w.kanal.first { $0.id == m.zustellung }
            raus.append(BrauchtDich(id: "zustellung:\(m.zustellung)",
                                    titel: m.markierung == "frage" ? "Frage von \(w.anzeigename(m.von))" : "Ergebnis von \(w.anzeigename(m.von))",
                                    text: nachricht?.text ?? "Im Chat mit \(w.anzeigename(m.von)).", knopf: "Ansehen", ziel: "agent:\(m.von)"))
        }
        for t in w.tickets where t.stand == "braucht dich" {
            let grund = t.flagge?.grund ?? ""
            raus.append(BrauchtDich(id: "ticket:\(t.id)", titel: "Ticket „\(t.titel)“",
                                    text: grund.isEmpty ? "Das Ticket hängt an dir." : grund,
                                    knopf: "Ticket öffnen", ziel: "ticket:\(t.id)"))
        }
        return raus
    }

    /// Die ersten Tickets des Backlogs für die Übersicht (Plan Satz 44).
    static func triage(_ w: Welt) -> [WeltTicket] { WeltenZustand.backlog(w) }

    /// Ein Vorhaben mit seinem Fortschritt (Plan Sätze 42, 51): „3 von 5 Stories abgenommen".
    struct VorhabenStand: Identifiable, Equatable {
        let id: String
        let titel: String
        let stand: String
        let abgenommen: Int
        let gesamt: Int
        var fertig: Bool { stand == "abgenommen" }
        var text: String {
            gesamt == 0 ? "noch keine Stories" : "\(abgenommen) von \(gesamt) \(gesamt == 1 ? "Story" : "Stories") abgenommen"
        }
    }

    /// Die Vorhaben der Welt mit dem Fortschritt ihrer Stories; abgeschlossene zuletzt.
    static func vorhaben(_ w: Welt) -> [VorhabenStand] {
        w.tickets.filter { $0.kind == "vorhaben" }.map { v in
            let stories = w.tickets.filter { $0.eltern == v.id && $0.stand != "verworfen" }
            return VorhabenStand(id: v.id, titel: v.titel, stand: v.stand,
                                 abgenommen: stories.filter { $0.stand == "abgenommen" }.count, gesamt: stories.count)
        }
        .sorted { a, b in a.fertig != b.fertig ? !a.fertig : a.id < b.id }
    }

    /// Die Auskunft fuer `awbmac-ctl agents`, solange die Uebersicht steht.
    @MainActor
    static func auskunft(_ w: Welt, zustand: WeltenZustand) -> [String: Any] {
        [
            "hauptagentEinladung": w.hauptagent == nil,
            "teamAufbauen": w.hauptagent != nil && w.agenten.count == 1,
            "brauchtDich": brauchtDich(w).map(\.titel),
            "brauchtDichFragen": brauchtDich(w).compactMap { e in e.frage.flatMap { w.frage($0) }.map { ["id": $0.id, "optionen": $0.optionenGeordnet, "empfehlung": $0.empfehlung ?? ""] as [String: Any] } },
            "karten": kartenFolge(w).compactMap { id -> [String: Any]? in
                guard let a = w.agent(id) else { return nil }
                return ["id": a.id, "zustand": WeltenWorte.zustand(a.zustand), "text": a.zustandText,
                        "wort": WeltenWorte.leben(a) ?? "", "ring": a.ring.rawValue, "zug": WeltenZustand.zugAuskunft(a),
                        "letzteMeldung": letzteMeldung(w, a.id)?.text ?? "", "ticketsOffen": offeneTickets(w, a.id).count,
                        "ungelesen": zustand.ungelesen(w, agent: a.id)]
            },
            "ticketsOffen": offeneTickets(w).prefix(5).map(\.titel),
            "kanal": w.kanal.suffix(3).map(\.id),
            // tickets4: Triage, Vorhaben und die Ticketgruende unter „Braucht dich".
            "triage": triage(w).prefix(5).map(\.id),
            "brauchtDichTickets": brauchtDich(w).filter { $0.ziel.hasPrefix("ticket:") }.map { ["id": String($0.ziel.dropFirst(7)), "text": $0.text] },
            "vorhaben": vorhaben(w).map { ["id": $0.id, "titel": $0.titel, "text": $0.text, "stand": $0.stand, "fertig": $0.fertig] },
        ]
    }
}

// MARK: Karten

/// Eine Karte in Fensterflaeche mit feiner Kante -- dieselbe Form wie die Karten im Ticketdetail.
private struct Karte: ViewModifier {
    var hervorgehoben = false
    var gestrichelt = false
    func body(content: Content) -> some View {
        content
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .background(RoundedRectangle(cornerRadius: 12).fill(hervorgehoben ? Color.accentColor.opacity(0.08) : Color(nsColor: .controlBackgroundColor)))
            .overlay {
                if gestrichelt {
                    RoundedRectangle(cornerRadius: 12).strokeBorder(Color(nsColor: .separatorColor), style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
                } else {
                    RoundedRectangle(cornerRadius: 12).strokeBorder(hervorgehoben ? Color.accentColor.opacity(0.35) : Color(nsColor: .separatorColor))
                }
            }
    }
}

private extension View {
    func weltenKarte(hervorgehoben: Bool = false, gestrichelt: Bool = false) -> some View {
        modifier(Karte(hervorgehoben: hervorgehoben, gestrichelt: gestrichelt))
    }
}

/// Die Meldung der letzten Handlung, ueber dem Inhalt -- wie in der Mitte der Gespraeche.
struct WeltenMeldungsband: View {
    @Bindable var zustand: WeltenZustand

    var body: some View {
        if let m = zustand.meldung {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: m.ok ? "checkmark.circle" : "exclamationmark.triangle")
                    .foregroundStyle(m.ok ? Color.green : Color.orange)
                    .accessibilityHidden(true)
                Text(m.ok ? m.text : "Nicht ausgeführt: \(m.text)").font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                Button("Ausblenden") { zustand.meldung = nil }.buttonStyle(.borderless).controlSize(.small)
            }
            .padding(.horizontal, 16).padding(.vertical, 6)
            .background(.quaternary.opacity(0.5))
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("welten-meldung")
        }
    }
}

// MARK: Menue der Welten und die Wege zu einer neuen

/// Die Eintraege „Neue Welt" in einem Menue: ein Projektordner ueber den Systemdialog, oder Global ohne Dialog.
struct WeltenNeuEintraege: View {
    let nutzlast: WeltenNutzlast?
    @Bindable var zustand: WeltenZustand

    var body: some View {
        Section("Neue Welt") {
            Button("In einem Projektordner …") { Task { await zustand.ordnerWaehlenUndAnlegen(echt: true) } }
            if !(nutzlast?.globalDa ?? false) {
                Button("Global, für alle Projekte") { Task { await zustand.weltAnlegen(art: "global", echt: true) } }
            }
        }
        // Auftrag agentsform: ein gemerkter Projektordner laesst sich aus der Liste nehmen; der Ordner bleibt, der Kern fragt zurueck.
        if let gemerkt = nutzlast?.gemerkteProjekte, !gemerkt.isEmpty {
            Section("Gemerkte Projektordner") {
                Menu("Aus der Liste entfernen") {
                    ForEach(gemerkt, id: \.self) { ordner in
                        Button(kurzerPfad(ordner)) { Task { await zustand.vergessen(ordner, echt: true) } }
                    }
                }
                .disabled(zustand.laufend.contains("vergessen"))
            }
        }
    }
}

/// Oben links in der Leiste: die gewaehlte Welt, ihre Geschwister zum Wechseln und die Wege zu einer neuen.
struct WeltenWahlMenue: View {
    let nutzlast: WeltenNutzlast
    let welt: Welt
    @Bindable var zustand: WeltenZustand

    /// Was das Menue zum Anlegen anbietet -- fuer Bildschirm und Auskunft dieselbe Liste.
    static func neuEintraege(_ n: WeltenNutzlast?) -> [String] {
        ["In einem Projektordner …"] + ((n?.globalDa ?? false) ? [] : ["Global, für alle Projekte"])
    }

    var body: some View {
        Menu {
            Section("Welten") {
                Picker("Welt", selection: Binding(get: { welt.pfad }, set: { zustand.weltWaehlen($0, nutzlast) })) {
                    ForEach(nutzlast.welten) { w in
                        Label(WeltenUebersichtWorte.menuname(w), systemImage: WeltenUebersichtWorte.symbol(w)).tag(w.pfad)
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            }
            WeltenNeuEintraege(nutzlast: nutzlast, zustand: zustand)
        } label: {
            Label(WeltenUebersichtWorte.menuname(welt), systemImage: WeltenUebersichtWorte.symbol(welt))
        }
        .controlSize(.large)
        .fixedSize()
        .frame(maxWidth: .infinity, alignment: .leading)
        .disabled(zustand.laufend.contains("neu"))
        .help("Welt wechseln oder eine neue anlegen: für einen Projektordner oder global")
        .accessibilityLabel("Welt \(WeltenUebersichtWorte.menuname(welt)), wechseln oder neu anlegen")
        .accessibilityIdentifier("welten-dropdown")
    }
}

/// Die Leiste ohne Welt: derselbe Weg als eigener Knopf.
struct WeltenNeuMenue: View {
    let kern: KernVerbindung
    @Bindable var zustand: WeltenZustand
    let titel: String

    var body: some View {
        Menu {
            WeltenNeuEintraege(nutzlast: kern.welten, zustand: zustand)
        } label: {
            Label(titel, systemImage: "plus.rectangle.on.folder")
        }
        .fixedSize()
        .disabled(zustand.laufend.contains("neu"))
        .accessibilityIdentifier("welten-neu-menue")
    }
}

/// „Agent anlegen" mit Beschriftung: der Knopf oeffnet das Anlege-Menue, der Pfeil daneben
/// bietet den Vorschlag aus einer Beschreibung und die Vorlagen der Bibliothek an.
struct WeltenAgentAnlegenKnopf: View {
    let nutzlast: WeltenNutzlast
    let welt: Welt
    @Bindable var zustand: WeltenZustand
    var prominent = false

    var body: some View {
        let lage = WeltenZustand.anlegenLage(welt)
        Menu {
            Button(welt.hauptagent == nil ? "Hauptagent selbst anlegen …" : "Selbst anlegen …") { zustand.anlegenStarten(nutzlast, welt) }
            Button("Aus einer Beschreibung vorschlagen lassen …") { zustand.anlegenStarten(nutzlast, welt, vorschlagen: true) }
            if welt.hauptagent != nil, !nutzlast.vorlagen.isEmpty {
                Section("Aus der Bibliothek") {
                    ForEach(nutzlast.vorlagen) { v in
                        Button(v.titel) { zustand.anlegenStarten(nutzlast, welt, vorlage: v.name) }
                    }
                }
            }
        } label: {
            Label(lage.titel, systemImage: "person.badge.plus")
        } primaryAction: {
            zustand.anlegenStarten(nutzlast, welt)
        }
        .fixedSize()
        .disabled(!lage.aktiv)
        .help(lage.aktiv ? "\(lage.titel) in \(welt.name): selbst, als Vorschlag oder aus der Bibliothek" : lage.grund)
        .accessibilityLabel(lage.titel)
        .accessibilityIdentifier(prominent ? "welten-agent-anlegen-mitte" : "welten-agent-anlegen")
    }
}

// MARK: Der Leerzustand ohne Welt

struct WeltenEinladung: View {
    let kern: KernVerbindung
    @Bindable var zustand: WeltenZustand
    let fehler: [String]

    /// Die Knoepfe der Einladung -- fuer Bildschirm und Auskunft dieselben.
    static func knoepfe(_ n: WeltenNutzlast?) -> [String] {
        ["Projektordner wählen …"] + ((n?.globalDa ?? false) ? [] : ["Globale Welt anlegen"])
    }

    private var globalPfad: String {
        let p = kern.welten?.globalPfad ?? ""
        return p.isEmpty ? "~/.claude/workbench/agents" : kurzerPfad(p)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                VStack(spacing: 10) {
                    Image(systemName: "person.3.sequence")
                        .font(.largeTitle).foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                    Text("Agents arbeiten in Welten").font(.title.weight(.semibold))
                    Text("Eine Welt ist der Arbeitsplatz einer Gruppe von Agenten: ein Hauptagent nimmt deine Aufträge an, Teams verteilen sie unter sich. Jede Welt hat ihren eigenen Kanal, ihre Tickets und ihr Gedächtnis und ist von deinen Code-Sitzungen getrennt.")
                        .multilineTextAlignment(.center).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: 560)
                }
                // Nebeneinander, solange die Mitte breit genug ist; sonst untereinander. Die feste
                // Mindestbreite gibt ViewThatFits das Mass, an dem es entscheidet (Text allein
                // meldete seine ganze Zeile als Wunschbreite und fiel immer auf den Stapel).
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 14) {
                        projektKarte.frame(maxHeight: .infinity, alignment: .top)
                        globalKarte.frame(maxHeight: .infinity, alignment: .top)
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(minWidth: 580, maxWidth: 700)
                    VStack(spacing: 14) { projektKarte; globalKarte }
                        .frame(maxWidth: 700)
                }
                WeltenMeldungsband(zustand: zustand)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .frame(maxWidth: 700)
                WeltenSchritte(titel: "Danach").frame(maxWidth: 700)
                if !fehler.isEmpty {
                    Label(fehler.joined(separator: "\n"), systemImage: "exclamationmark.triangle")
                        .font(.caption).foregroundStyle(.secondary).frame(maxWidth: 700, alignment: .leading)
                }
                Text("Auf der Kommandozeile geht dasselbe mit „wb-welt neu <projekt>/.werkbank/agents“.")
                    .font(.caption).foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 32).padding(.vertical, 36)
            .frame(maxWidth: .infinity)
        }
        .accessibilityIdentifier("welten-leer")
    }

    private var projektKarte: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Projektwelt", systemImage: "folder").font(.headline)
            Text("Die Agenten arbeiten in einem Projektordner. Die Welt liegt dort unter .werkbank/agents und reist mit dem Projekt.")
                .font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 4)
            Button("Projektordner wählen …") { Task { await zustand.ordnerWaehlenUndAnlegen(echt: true) } }
                .buttonStyle(.borderedProminent)
                .disabled(zustand.laufend.contains("neu"))
                .accessibilityIdentifier("welten-leer-projekt")
        }
        .weltenKarte()
    }

    private var globalKarte: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Globale Welt", systemImage: "globe").font(.headline)
            Text("Für Aufgaben über alle Projekte hinweg, ohne Dialog. Sie liegt unter \(globalPfad) und bleibt von den Projektwelten getrennt.")
                .font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 4)
            if kern.welten?.globalDa ?? false {
                Text("Die globale Welt gibt es schon.").font(.callout).foregroundStyle(.secondary)
            } else {
                Button("Globale Welt anlegen") { Task { await zustand.weltAnlegen(art: "global", echt: true) } }
                    .disabled(zustand.laufend.contains("neu"))
                    .accessibilityIdentifier("welten-leer-global")
            }
        }
        .weltenKarte()
    }
}

/// Was nach dem Anlegen kommt, in drei Schritten -- in der Einladung ohne Welt und in einer Welt ohne Hauptagenten.
struct WeltenSchritte: View {
    /// „Danach" in der Einladung, „So geht es weiter" in der Uebersicht einer leeren Welt.
    let titel: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(titel).font(.headline)
            schritt(1, "Hauptagent anlegen", "Selbst oder als Vorschlag aus ein, zwei Sätzen Beschreibung. Er nimmt deine Aufträge an und fragt dich nur, wenn es nicht anders geht.")
            schritt(2, "Team aufbauen", "Teamleiter und Mitglieder, auch aus den Vorlagen der Bibliothek. Gestartet wird dabei nichts.")
            schritt(3, "Aufträge geben", "Im Chat des Hauptagenten oder als Ticket. Die Übersicht zeigt dann, wer arbeitet und was dich braucht.")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .weltenKarte(gestrichelt: true)
    }

    private func schritt(_ nr: Int, _ titel: String, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text("\(nr)")
                .font(.callout.weight(.semibold)).monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(minWidth: 18)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(titel).font(.callout.weight(.semibold))
                Text(text).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: Die Uebersicht einer Welt

struct WeltenUebersicht: View {
    let nutzlast: WeltenNutzlast
    let welt: Welt
    @Bindable var zustand: WeltenZustand

    var body: some View {
        VStack(spacing: 0) {
            kopf
            Divider()
            WeltenMeldungsband(zustand: zustand)
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    if welt.hauptagent == nil { hauptagentEinladung }
                    if welt.agenten.isEmpty { WeltenSchritte(titel: "So geht es weiter") }
                    let brauchen = WeltenUebersichtWorte.brauchtDich(welt)
                    if !brauchen.isEmpty { brauchtDich(brauchen) }
                    if !welt.agenten.isEmpty { agenten }
                    let vorhaben = WeltenUebersichtWorte.vorhaben(welt)
                    if !vorhaben.isEmpty { vorhabenKarte(vorhaben) }
                    let backlog = WeltenUebersichtWorte.triage(welt)
                    if !backlog.isEmpty { triageKarte(backlog) }
                    tickets
                    if !welt.kanal.isEmpty { kanal }
                }
                .padding(20)
                .frame(maxWidth: 980, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
        }
        .background(Color(nsColor: .textBackgroundColor))
        .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
        .accessibilityIdentifier("welten-uebersicht")
    }

    // --- Kopf ---------------------------------------------------------------------

    private var kopf: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: "square.grid.2x2").font(.title2).foregroundStyle(.secondary).frame(width: 44)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(welt.name).font(.title3.weight(.semibold))
                Text(["Übersicht", WeltenWorte.herkunft(welt), welt.stand].filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.callout).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
            }
            Spacer(minLength: 12)
            Button {
                // Das Formular steht im Reiter Tickets (tickets4); die Uebersicht fuehrt dorthin.
                zustand.waehlen(WeltenZustand.kanal, welt)
                zustand.reiter = .tickets
                zustand.neuesTicket = WeltenZustand.TicketEntwurf()
            } label: {
                Label("Neues Ticket", systemImage: "ticket")
            }
            .fixedSize()
            .disabled(welt.agenten.isEmpty)
            .help(welt.agenten.isEmpty ? "Ein Ticket braucht einen Adressaten; lege zuerst den Hauptagenten an." : "Ein Ticket an den Hauptagenten, ein Team oder einen Agenten")
            WeltenAgentAnlegenKnopf(nutzlast: nutzlast, welt: welt, zustand: zustand, prominent: true)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private func abschnitt<Inhalt: View>(_ titel: String, zahl: Int? = nil, @ViewBuilder _ inhalt: () -> Inhalt) -> some View {
        abschnitt(titel, zahl: zahl, rechts: { EmptyView() }, inhalt)
    }

    private func abschnitt<Rechts: View, Inhalt: View>(_ titel: String, zahl: Int? = nil, @ViewBuilder rechts: () -> Rechts,
                                                       @ViewBuilder _ inhalt: () -> Inhalt) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(titel).font(.title3.weight(.semibold)).accessibilityAddTraits(.isHeader)
                if let zahl { Text("\(zahl)").font(.callout).monospacedDigit().foregroundStyle(.secondary) }
                Spacer(minLength: 8)
                rechts()
            }
            inhalt()
        }
    }

    // --- Ohne Hauptagent -----------------------------------------------------------

    private var hauptagentEinladung: some View {
        let lage = WeltenZustand.anlegenLage(welt)
        return HStack(alignment: .top, spacing: 16) {
            Image(systemName: "person.crop.circle.badge.plus")
                .font(.largeTitle).foregroundStyle(.tint)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 8) {
                Text("Diese Welt hat noch keinen Hauptagenten.").font(.title3.weight(.semibold))
                Text("Lege ihn an oder lass ihn vorschlagen. Er nimmt deine Aufträge an, verteilt sie als Tickets an die Teams und fragt dich nur, wenn es nicht anders geht. Danach baust du mit ihm das Team auf.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 10) {
                    Button("Hauptagent anlegen …") { zustand.anlegenStarten(nutzlast, welt) }
                        .buttonStyle(.borderedProminent)
                        .accessibilityIdentifier("welten-hauptagent-anlegen")
                    Button("Vorschlagen lassen …") { zustand.anlegenStarten(nutzlast, welt, vorschlagen: true) }
                        .accessibilityIdentifier("welten-hauptagent-vorschlag")
                }
                .disabled(!lage.aktiv)
                .padding(.top, 2)
                if !lage.aktiv {
                    Text(lage.grund).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .weltenKarte(hervorgehoben: true)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("welten-einladung-hauptagent")
    }

    // --- Braucht dich ----------------------------------------------------------------

    private func brauchtDich(_ eintraege: [WeltenUebersichtWorte.BrauchtDich]) -> some View {
        abschnitt("Braucht dich", zahl: eintraege.count) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(eintraege.enumerated()), id: \.element.id) { i, e in
                    if i > 0 { Divider().padding(.vertical, 8) }
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Zustandspunkt(art: .will, basis: 8)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(e.titel).font(.callout.weight(.semibold))
                                Text(e.text).font(.callout).foregroundStyle(.secondary).lineLimit(e.frage == nil ? 2 : 4)
                            }
                            Spacer(minLength: 8)
                            Button(e.knopf) {
                                if e.ziel.hasPrefix("ticket:") {
                                    zustand.ticketAuswahl = String(e.ziel.dropFirst(7))
                                } else {
                                    zustand.waehlen(e.ziel, welt)
                                    zustand.reiter = .chat
                                }
                            }
                        }
                        .accessibilityElement(children: .combine)
                        // Auftrag agentsform: eine gespeicherte Frage gleich hier beantworten -- Option oder eigener Text.
                        if let id = e.frage, let f = welt.frage(id), f.offen {
                            frageAntwort(f).padding(.leading, 18)
                        }
                    }
                }
            }
            .weltenKarte()
        }
    }

    private func frageAntwort(_ f: WeltFrage) -> some View {
        let entwurf = Binding(get: { zustand.antwortEntwuerfe[f.id] ?? "" }, set: { zustand.antwortEntwuerfe[f.id] = $0 })
        return VStack(alignment: .leading, spacing: 6) {
            if !f.optionen.isEmpty {
                FlussLayout(abstand: 6) {
                    ForEach(f.optionenGeordnet, id: \.self) { o in
                        if o == f.empfehlung {
                            Button("\(o) (Empfehlung)") { Task { await zustand.antworten(welt, frage: f.id, text: o, echt: true) } }
                                .buttonStyle(.borderedProminent)
                        } else {
                            Button(o) { Task { await zustand.antworten(welt, frage: f.id, text: o, echt: true) } }
                        }
                    }
                }
            }
            HStack(spacing: 8) {
                TextField("Eigene Antwort", text: entwurf)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { Task { await zustand.antworten(welt, frage: f.id, text: entwurf.wrappedValue, echt: true) } }
                    .accessibilityIdentifier("welten-uebersicht-antwort-\(f.id)")
                Button("Antworten") { Task { await zustand.antworten(welt, frage: f.id, text: entwurf.wrappedValue, echt: true) } }
                    .disabled(entwurf.wrappedValue.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .controlSize(.small)
        .disabled(zustand.laufend.contains("antworten"))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Antwort auf: \(f.text)")
    }

    // --- Agenten -----------------------------------------------------------------------

    private var agenten: some View {
        let folge = WeltenUebersichtWorte.kartenFolge(welt)
        return abschnitt("Agenten", zahl: folge.count) {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 250, maximum: 460), spacing: 12, alignment: .top)], alignment: .leading, spacing: 12) {
                ForEach(folge, id: \.self) { id in
                    if let a = welt.agent(id) { agentKarte(a) }
                }
                if welt.hauptagent != nil, welt.agenten.count == 1 { teamAufbauen }
            }
        }
    }

    private func agentKarte(_ a: WeltAgent) -> some View {
        let letzte = WeltenUebersichtWorte.letzteMeldung(welt, a.id)
        let offen = WeltenUebersichtWorte.offeneTickets(welt, a.id).count
        let ungelesen = zustand.ungelesen(welt, agent: a.id)
        return Button {
            zustand.waehlen("agent:\(a.id)", welt)
            zustand.reiter = .chat
        } label: {
            HStack(alignment: .top, spacing: 12) {
                WeltenFigur(agent: a, groesse: 40)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(a.name).font(.headline).lineLimit(1)
                        Spacer(minLength: 4)
                        WeltenZahl(n: ungelesen)
                    }
                    Text(WeltenWorte.stufe(a.stufe) + (a.team.map { " · Team \(WeltenWorte.team($0))" } ?? ""))
                        .font(.callout).foregroundStyle(.secondary).lineLimit(1)
                    HStack(alignment: .firstTextBaseline, spacing: 5) {
                        Zustandspunkt(art: WeltenWorte.punkt(agent: a), basis: 7)
                        WeltenLebenWort(agent: a, ohneLeben: a.zustandText.isEmpty ? WeltenWorte.zustand(a.zustand) : a.zustandText).lineLimit(1)
                    }
                    .font(.callout)
                    Group {
                        if let m = letzte {
                            Text("„\(m.text)“ · \(WeltenWorte.alter(m.zeit))")
                        } else {
                            Text("Noch keine Meldung")
                        }
                    }
                    .font(.callout).foregroundStyle(.secondary).lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    Text(offen == 0 ? "Keine offenen Tickets" : (offen == 1 ? "1 Ticket offen" : "\(offen) Tickets offen"))
                        .font(.caption).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .contentShape(Rectangle())
            .weltenKarte()
        }
        .buttonStyle(.plain)
        .help("Chat mit \(a.name) öffnen")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(a.name), \(WeltenWorte.stufe(a.stufe)), \(WeltenWorte.leben(a) ?? a.zustandText), \(offen) Tickets offen\(ungelesen > 0 ? ", \(ungelesen) ungelesen" : "")")
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("welten-karte-\(a.id)")
    }

    private var teamAufbauen: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Team aufbauen", systemImage: "person.badge.plus").font(.headline)
            Text("\(welt.agent(welt.hauptagent)?.name ?? "Der Hauptagent") arbeitet noch allein. Lege Teamleiter und Mitglieder an: selbst, als Vorschlag oder aus der Bibliothek.")
                .font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if !nutzlast.vorlagen.isEmpty {
                FlussLayout(abstand: 6) {
                    ForEach(nutzlast.vorlagen) { v in
                        Button(v.titel) { zustand.anlegenStarten(nutzlast, welt, vorlage: v.name) }
                            .controlSize(.small)
                            .help(v.zusammenfassung)
                    }
                }
                .disabled(!WeltenZustand.anlegenLage(welt).aktiv)
            }
        }
        .weltenKarte(gestrichelt: true)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("welten-team-aufbauen")
    }

    // --- Tickets und Kanal ---------------------------------------------------------------

    private var tickets: some View {
        let offen = WeltenUebersichtWorte.offeneTickets(welt)
        return abschnitt("Offene Tickets", zahl: offen.count, rechts: {
            Button("Alle Tickets") {
                zustand.waehlen(WeltenZustand.kanal, welt)
                zustand.reiter = .tickets
            }
            .buttonStyle(.borderless)
        }) {
            VStack(alignment: .leading, spacing: 0) {
                if offen.isEmpty {
                    Text(welt.agenten.isEmpty ? "Noch keine Tickets. Sie entstehen, sobald ein Agent da ist: aus einem Auftrag im Chat oder über „Neues Ticket“."
                         : "Nichts offen. Ein Auftrag im Chat des Hauptagenten wird zum Ticket, oder du legst eines über „Neues Ticket“ an.")
                        .font(.callout).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                ForEach(Array(offen.prefix(5).enumerated()), id: \.element.id) { i, t in
                    if i > 0 { Divider().padding(.vertical, 6) }
                    Button { zustand.ticketAuswahl = t.id } label: {
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Zustandspunkt(art: WeltenWorte.punkt(ticket: t.stand), basis: 7)
                            Text(t.titel).lineLimit(1)
                            Spacer(minLength: 8)
                            Text(([t.bearbeiter ?? t.adressaten.first].compactMap { $0 }.map { welt.anzeigename($0) } + [t.stand]).joined(separator: " · "))
                                .font(.callout).foregroundStyle(.secondary).lineLimit(1)
                            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Ticket \(t.titel), \(t.stand)")
                }
                if offen.count > 5 {
                    Text("und \(offen.count - 5) weitere unter „Alle Tickets“").font(.caption).foregroundStyle(.secondary).padding(.top, 8)
                }
            }
            .weltenKarte()
        }
    }

    /// Die Vorhaben mit Fortschritt (Plan Sätze 42 und 51); ein abgeschlossenes steht markiert da.
    private func vorhabenKarte(_ liste: [WeltenUebersichtWorte.VorhabenStand]) -> some View {
        abschnitt("Vorhaben", zahl: liste.count) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(liste.enumerated()), id: \.element.id) { i, v in
                    if i > 0 { Divider().padding(.vertical, 6) }
                    Button { zustand.ticketAuswahl = v.id } label: {
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Zustandspunkt(art: WeltenWorte.punkt(ticket: v.stand), basis: 7)
                            Text(v.titel).lineLimit(1)
                            if v.fertig { WeltenAbzeichen(text: "abgeschlossen", hervorgehoben: true, hilfe: "Alle Stories abgenommen und das Vorhaben abgenommen") }
                            Spacer(minLength: 8)
                            Text(v.text).font(.callout).foregroundStyle(.secondary).lineLimit(1)
                            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Vorhaben \(v.titel), \(v.text), \(v.stand)")
                    .accessibilityIdentifier("welten-uebersicht-vorhaben-\(v.id)")
                }
            }
            .weltenKarte()
        }
    }

    /// Die ersten fünf Tickets des Backlogs in ihrer Reihenfolge (Plan Sätze 39 und 44).
    private func triageKarte(_ liste: [WeltTicket]) -> some View {
        abschnitt("Triage", zahl: liste.count, rechts: {
            Button("Backlog öffnen") {
                zustand.waehlen(WeltenZustand.kanal, welt)
                zustand.reiter = .tickets
                zustand.ticketFilter = "triage"
            }
            .buttonStyle(.borderless)
        }) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(liste.prefix(5).enumerated()), id: \.element.id) { i, t in
                    if i > 0 { Divider().padding(.vertical, 6) }
                    Button { zustand.ticketAuswahl = t.id } label: {
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Text("\(i + 1)").font(.callout.monospacedDigit()).foregroundStyle(.secondary).frame(width: 18, alignment: .trailing)
                            Text(t.titel).lineLimit(1)
                            WeltenAbzeichen(text: WeltenWorte.kind(t.kind), hilfe: WeltenWorte.kindErklaerung(t.kind))
                            Spacer(minLength: 8)
                            Text("von \(welt.anzeigename(t.absender)) · \(WeltenWorte.alter(t.angelegt))")
                                .font(.callout).foregroundStyle(.secondary).lineLimit(1)
                            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Triage \(i + 1): \(t.titel)")
                    .accessibilityIdentifier("welten-uebersicht-triage-\(t.id)")
                }
                if liste.count > 5 {
                    Text("und \(liste.count - 5) weitere im Backlog").font(.caption).foregroundStyle(.secondary).padding(.top, 8)
                }
            }
            .weltenKarte()
        }
    }

    private var kanal: some View {
        abschnitt("Zuletzt im Kanal", rechts: {
            Button("Kanal öffnen") { zustand.waehlen(WeltenZustand.kanal, welt); zustand.reiter = .chat }
                .buttonStyle(.borderless)
        }) {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(welt.kanal.suffix(3)) { m in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(welt.anzeigename(m.von)).font(.callout.weight(.semibold))
                        Text("an \(m.an.map { welt.anzeigename($0) }.joined(separator: ", "))").font(.callout).foregroundStyle(.secondary).lineLimit(1)
                        Text(m.text).font(.callout).lineLimit(1).truncationMode(.tail)
                        Spacer(minLength: 8)
                        Text(WeltenWorte.alter(m.zeit)).font(.caption).foregroundStyle(.tertiary)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            .weltenKarte()
        }
    }
}
