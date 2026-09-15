// Das Freigabenblatt: der Inspektor rechts (NSSplitViewItem(inspectorWith…)),
// Auftrag 2.4. Drei Rubriken wie in der Electron-Fassung
// (app/src/renderer/freigaben-view.ts): Antraege mit Annehmen/Ablehnen
// (`freigaben-entscheiden`, ruft `wb-decide`), angehaltene Worker -- die
// Rueckfrage-Stufe mit Freigeben/Ablehnen (`muster-entscheiden`), die harte
// Ablehnung als Befund --, und der Guard-Verlauf. Die Begruendung ist
// freiwillig (19.08.).
//
// Fremder Text (Worker-Name, Befehl, Aufgabe, Grund) steht als String in
// `Text(...)` -- nie als LocalizedStringKey, das Markdown deuten wuerde
// (freigabenmarkup, 05.09.). Textstile, Systemfarben, SF Symbols; keine
// festen Punktgroessen.
import SwiftUI
import WerkbankProtokoll

struct FreigabenBlatt: View {
    let kern: KernVerbindung
    let zustand: FreigabenZustand
    unowned let handlungen: Freigabehandlungen
    /// Als Beleg fuer kopflose Bilder (Fenster.schuss): ohne ScrollView, Knoepfe
    /// und Textfelder, die AppKit-gestuetzt sind und im ImageRenderer nichts
    /// zeichnen (gemessen 06.09.) -- an ihrer Stelle stehen ihre Beschriftungen.
    var beleg = false

    var body: some View {
        if beleg {
            inhalt.background(Color(nsColor: .windowBackgroundColor))
        } else {
            ScrollView { inhalt }
                .background(.background)
                .accessibilityIdentifier("freigabenblatt")
        }
    }

    private var inhalt: some View {
        let f = kern.freigaben
        return Group {
            VStack(alignment: .leading, spacing: 14) {
                if !zustand.meldung.isEmpty && zustand.meldungBis > Date() {
                    Label(zustand.meldung, systemImage: "info.circle")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Rubrik("Anträge", anzahl: f.requests.count, leer: "Kein offener Antrag.") {
                    ForEach(f.requests) { r in
                        AntragKarte(antrag: r, zustand: zustand, handlungen: handlungen, beleg: beleg)
                    }
                }
                Rubrik("Angehaltene Worker", anzahl: f.guardBlocks.count, leer: "Kein Worker wartet gerade auf eine Guard-Entscheidung.") {
                    ForEach(f.guardBlocks) { b in
                        BlockKarte(block: b, zustand: zustand, handlungen: handlungen, beleg: beleg)
                    }
                }
                Rubrik("Guard-Verlauf", anzahl: f.guardLog.count, leer: "Noch keine Ablehnung aufgezeichnet.") {
                    ForEach(f.guardLog) { g in
                        VerlaufZeile(gruppe: g)
                    }
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }
}

/// Eine Karte des Blatts: abgesetzte Flaeche in Systemfarbe, kein Material.
private struct Karte<Inhalt: View>: View {
    @ViewBuilder let inhalt: Inhalt
    var body: some View {
        VStack(alignment: .leading, spacing: 6) { inhalt }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(.quaternary.opacity(0.5)))
    }
}

/// Knoepfe -- im Beleg nur ihre Beschriftung, sonst echte Buttons.
private struct Knoepfe: View {
    let beleg: Bool
    let paare: [(String, Bool, () -> Void)]   // Titel, hervorgehoben, Handlung

    var body: some View {
        HStack {
            ForEach(Array(paare.enumerated()), id: \.offset) { _, p in
                if beleg {
                    Text(p.0).font(.callout)
                        .padding(.horizontal, 10).padding(.vertical, 3)
                        .background(Capsule().fill(p.1 ? AnyShapeStyle(.tint) : AnyShapeStyle(.quaternary)))
                        .foregroundStyle(p.1 ? Color.white : Color.primary)
                } else if p.1 {
                    Button(p.0, action: p.2).buttonStyle(.borderedProminent)
                } else {
                    Button(p.0, action: p.2).buttonStyle(.bordered)
                }
            }
        }
        .controlSize(.small)
    }
}

/// Eine Rubrik des Blatts: Ueberschrift mit Zahl, dann die Karten oder der Leerzustand.
private struct Rubrik<Inhalt: View>: View {
    let titel: String
    let anzahl: Int
    let leer: String
    @ViewBuilder let inhalt: Inhalt

    init(_ titel: String, anzahl: Int, leer: String, @ViewBuilder inhalt: () -> Inhalt) {
        self.titel = titel; self.anzahl = anzahl; self.leer = leer; self.inhalt = inhalt()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(titel).font(.headline)
                Text("\(anzahl)").font(.headline).foregroundStyle(.secondary).monospacedDigit()
            }
            .accessibilityElement(children: .combine)
            if anzahl == 0 {
                Text(leer).font(.callout).foregroundStyle(.secondary)
            } else {
                inhalt
            }
        }
    }
}

/// Ein Antrag: wer bittet um wen, die fuenf Felder, Begruendung, zwei Knoepfe.
private struct AntragKarte: View {
    let antrag: AntragEintrag
    let zustand: FreigabenZustand
    unowned let handlungen: Freigabehandlungen
    var beleg = false

    var body: some View {
        Karte {
                HStack(alignment: .firstTextBaseline) {
                    Text("\(antrag.parent) → \(antrag.childName)").font(.body.weight(.semibold)).lineLimit(2)
                    Spacer()
                    Text(seitHer(antrag.ts)).font(.caption).foregroundStyle(.secondary)
                }
                Text("\(antrag.modellText) · \(antrag.projekt)").font(.caption).foregroundStyle(.secondary)
                    .help(antrag.dir)
                Feld("Aufgabe", antrag.task)
                Feld("Warum abtrennbar", antrag.whySeparable)
                Feld("Fertig-Kriterium", antrag.doneCriterion)
                Feld("Dateien", antrag.files.joined(separator: ", "))
                Feld("Umfang", antrag.est)
                Text("Annehmen startet den Worker nicht von selbst: der Orchestrator bekommt den fertigen Startbefehl.")
                    .font(.caption).foregroundStyle(.secondary)
                GrundFeld(zustand: zustand, id: antrag.id, beleg: beleg)
                Knoepfe(beleg: beleg, paare: [("Annehmen", true, { entscheiden(true) }), ("Ablehnen", false, { entscheiden(false) })])
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Antrag von \(antrag.parent) auf \(antrag.childName)")
    }

    private func entscheiden(_ annehmen: Bool) {
        let o = OffeneFreigabe(art: .antrag, wer: antrag.parent, wo: antrag.projekt, worum: antrag.task,
                               sessionId: "", pane: "", schluessel: "", pfad: antrag.path)
        handlungen.entscheiden(o, annehmen: annehmen, grund: (zustand.blattGruende[antrag.id] ?? "").trimmingCharacters(in: .whitespacesAndNewlines))
        zustand.blattGruende[antrag.id] = nil
    }
}

/// Ein angehaltener Worker: wartend (Muster, Freigeben/Ablehnen) oder als Befund.
private struct BlockKarte: View {
    let block: GuardBlockEintrag
    let zustand: FreigabenZustand
    unowned let handlungen: Freigabehandlungen
    var beleg = false

    var body: some View {
        Karte {
                HStack(alignment: .firstTextBaseline) {
                    Image(systemName: block.wartet ? "hand.raised.circle.fill" : "xmark.octagon.fill")
                        .foregroundStyle(block.wartet ? Color.orange : Color.red)
                        .accessibilityHidden(true)
                    Text(block.wer).font(.body.weight(.semibold)).lineLimit(2)
                    Spacer()
                    Text(seitHer(block.ts)).font(.caption).foregroundStyle(.secondary)
                }
                Text([block.sessionName, block.machine, block.guardName.isEmpty ? "" : "Guard: \(block.guardName)"].filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.caption).foregroundStyle(.secondary)
                if block.wartet {
                    Text("Wartet auf Freigabe · Muster: \(block.muster)" + (block.musterGrund.isEmpty ? "" : " — \(block.musterGrund)"))
                        .font(.callout)
                } else {
                    Text(block.reason).font(.callout).foregroundStyle(.secondary)
                }
                Text(block.command)
                    .font(.body.monospaced())
                    .textSelection(.enabled)
                    .lineLimit(6)
                Text(kurzerPfad(block.cwd)).font(.caption).foregroundStyle(.secondary).help(block.cwd)
                if block.wartet {
                    GrundFeld(zustand: zustand, id: block.id, beleg: beleg)
                    Text("Einmalig: die Freigabe gilt genau diesem Befehl in genau diesem Pane.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Knoepfe(beleg: beleg, paare: knoepfe)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(block.wartet ? "Wartender" : "Angehaltener") Worker \(block.wer)")
    }

    private var knoepfe: [(String, Bool, () -> Void)] {
        var k: [(String, Bool, () -> Void)] = []
        if !block.unbekannterPane { k.append(("Pane zeigen", false, { handlungen.workerZeigen(sitzung: block.sessionId, pane: block.pane) })) }
        if block.wartet {
            k.append(("Freigeben", true, { entscheiden(true) }))
            k.append(("Ablehnen", false, { entscheiden(false) }))
        }
        return k
    }

    private func entscheiden(_ annehmen: Bool) {
        let o = OffeneFreigabe(art: .rueckfrage, wer: block.wer, wo: block.sessionName, worum: block.command,
                               sessionId: block.sessionId, pane: block.pane, schluessel: block.schluessel, pfad: block.path)
        handlungen.entscheiden(o, annehmen: annehmen, grund: (zustand.blattGruende[block.id] ?? "").trimmingCharacters(in: .whitespacesAndNewlines))
        zustand.blattGruende[block.id] = nil
    }
}

private struct VerlaufZeile: View {
    let gruppe: GuardLogGruppe

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline) {
                Text(gruppe.guardName.isEmpty ? "Guard" : gruppe.guardName).font(.callout.weight(.semibold))
                Text("\(gruppe.anzahl) ×").font(.caption).foregroundStyle(.secondary).monospacedDigit()
                Spacer()
                Text(seitHer(ms: gruppe.letzteMs)).font(.caption).foregroundStyle(.secondary)
            }
            Text(gruppe.reason).font(.caption).foregroundStyle(.secondary).lineLimit(3)
            if !gruppe.letzterBefehl.isEmpty {
                Text(gruppe.letzterBefehl).font(.caption.monospaced()).lineLimit(2).textSelection(.enabled)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

private struct Feld: View {
    let name: String
    let wert: String
    init(_ name: String, _ wert: String) { self.name = name; self.wert = wert }

    var body: some View {
        if !wert.isEmpty {
            (Text("\(name): ").bold() + Text(wert))
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        }
    }
}

private struct GrundFeld: View {
    let zustand: FreigabenZustand
    let id: String
    var beleg = false

    var body: some View {
        if beleg {
            Text((zustand.blattGruende[id] ?? "").isEmpty ? "Begründung (freiwillig)" : zustand.blattGruende[id]!)
                .font(.callout).foregroundStyle(.secondary)
                .padding(.horizontal, 6).padding(.vertical, 3)
                .frame(maxWidth: .infinity, alignment: .leading)
                .overlay(RoundedRectangle(cornerRadius: 5).stroke(.quaternary))
        } else {
            feld
        }
    }

    private var feld: some View {
        TextField("Begründung (freiwillig)", text: Binding(
            get: { zustand.blattGruende[id] ?? "" },
            set: { zustand.blattGruende[id] = $0 }
        ), prompt: Text("optional — ein Satz genügt"))
        .textFieldStyle(.roundedBorder)
        .controlSize(.small)
        .accessibilityLabel("Begründung, freiwillig")
    }
}

/// `~` fuer das Home des Laufs, sonst der Pfad (kurzpfad wie im Modell).
func kurzerPfad(_ pfad: String) -> String {
    let home = ProcessInfo.processInfo.environment["HOME"].flatMap { $0.isEmpty ? nil : $0 } ?? NSHomeDirectory()
    if pfad == home { return "~" }
    if pfad.hasPrefix(home + "/") { return "~" + pfad.dropFirst(home.count) }
    return pfad
}

/// „gerade eben", „vor 3 min", „vor 1 h 20 min" (freigaben-view.ts `seitHer`).
func seitHer(_ iso: String) -> String {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime]
    var d = f.date(from: iso)
    if d == nil {
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        d = f.date(from: iso)
    }
    if d == nil {
        // Die Antragsdateien tragen den kompakten Stempel 20260906T025122Z (wb-request).
        let kompakt = DateFormatter()
        kompakt.locale = Locale(identifier: "en_US_POSIX")
        kompakt.timeZone = TimeZone(identifier: "UTC")
        kompakt.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        d = kompakt.date(from: String(iso.prefix(16)))
    }
    guard let datum = d else { return iso }
    return seitHer(ms: datum.timeIntervalSince1970 * 1000)
}

func seitHer(ms: Double) -> String {
    guard ms > 0 else { return "" }
    let min = Int((Date().timeIntervalSince1970 * 1000 - ms) / 60000)
    if min < 1 { return "gerade eben" }
    if min < 60 { return "vor \(min) min" }
    return "vor \(min / 60) h \(min % 60) min"
}
