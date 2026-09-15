// DER SKILL-REITER DER WELTEN (14.09.2026, Plan Abschnitt 14; Auftrag agentsui Nr. 4).
//
// Je Agent die aufgeloesten Skills aus `skills.json` (Ebene, Version, vorgeladen,
// verdeckt, fehlend, ungueltig), lesbar mit `SKILL.md`, dazu der Skill-Verlauf und die
// Tokenmessung je Ticketart als Zahlenzeile: Mittel ueber alle Zuege, Mittel und Werte
// der letzten fuenf, Veraenderung gegenueber den Zuegen davor. Kein Diagramm.
//
// Ein Ticket „Skill-Vorschlag" zeigt im Detail Skill, Ziel, Begruendung und den Diff;
// Uebernehmen und Ablehnen gehen ueber den Kern an `wb-skill abnehmen|ablehnen`. Die
// Daten kommen nur lesend aus `agents_skills_ansicht.py` (welten.ts, `skill_ansicht`).
import SwiftUI

enum WeltenSkillWorte {
    static func ebene(_ e: String) -> String {
        switch e {
        case "agent": "eigen"
        case "welt": "Welt"
        case "bibliothek": "Bibliothek"
        default: e
        }
    }

    /// Tokens kurz: 43200 -> „43,2 k", 1 250 000 -> „1,3 M".
    static func token(_ n: Double) -> String {
        let f = NumberFormatter()
        f.locale = Locale(identifier: "de_DE")
        f.minimumFractionDigits = 1
        f.maximumFractionDigits = 1
        f.roundingMode = .halfUp
        if n >= 1_000_000 { return "\(f.string(from: NSNumber(value: n / 1_000_000)) ?? "") M" }
        if n >= 1000 { return "\(f.string(from: NSNumber(value: n / 1000)) ?? "") k" }
        return String(Int(n.rounded()))
    }

    /// Die Zahlenzeile einer Ticketart: „7 Züge · Mittel 50,3 k · letzte 5: 43,2 k (47,0 · 45,5 · 42,0 · 41,2 · 40,3) · −37 %".
    static func messung(_ m: WeltSkillMessung) -> String {
        var teile = ["\(m.anzahl) \(m.anzahl == 1 ? "Zug" : "Züge")", "Mittel \(token(m.mittel))"]
        if !m.letzte.isEmpty {
            let werte = m.letzte.map { token($0).replacingOccurrences(of: " k", with: "") }.joined(separator: " · ")
            teile.append("letzte \(m.letzte.count): \(token(m.mittelLetzte)) (\(werte))")
        }
        // Kaufmaennisch gerundet wie in der Electron-Fassung (Math.round): -0,365 ist −37 %.
        if let v = m.veraenderung { teile.append("\(v < 0 ? "−" : "+")\(Int((abs(v) * 100).rounded())) %") }
        return teile.joined(separator: " · ")
    }

    static func aktion(_ a: String) -> String {
        switch a {
        case "neu": "angelegt"
        case "vorschlag": "vorgeschlagen"
        case "abgenommen": "übernommen"
        case "abgelehnt": "abgelehnt"
        default: a
        }
    }
}

extension WeltenZustand {
    func skillAbnehmen(_ w: Welt, ticket: String, echt: Bool) async {
        _ = await ausfuehren("skill_abnehmen", ["welt": w.pfad, "ticket": ticket], echt: echt)
    }

    func skillAblehnen(_ w: Welt, ticket: String, echt: Bool) async {
        let grund = skillGrund.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !grund.isEmpty else {
            meldung = Meldung(text: "Die Ablehnung braucht einen Grund.", ok: false)
            return
        }
        if await ausfuehren("skill_ablehnen", ["welt": w.pfad, "ticket": ticket, "grund": grund], echt: echt) {
            skillAblehnenOffen = nil
            skillGrund = ""
        }
    }
}

// MARK: Das Blatt im Inspektor

struct WeltenSkillBlatt: View {
    let agent: WeltAgent
    @Bindable var zustand: WeltenZustand

    private var s: WeltSkills { agent.skillAnsicht }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !s.fehler.isEmpty {
                Label(s.fehler.joined(separator: "\n"), systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange)
            }
            gruppe("Skills") {
                if s.liste.isEmpty {
                    Text("Noch keine Skills. Wiederkehrende Arbeit wird beim zweiten Mal Skript, beim dritten Mal Skill.")
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                ForEach(s.liste) { skill in zeile(skill) }
                if !s.fehlend.isEmpty {
                    Text("Fehlt: \(s.fehlend.joined(separator: ", ")) (im Profil vorgeladen, auf keiner Ebene vorhanden)")
                        .font(.caption).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
                }
                if !s.ungueltig.isEmpty {
                    Text("Ungültig: \(s.ungueltig.joined(separator: "; "))")
                        .font(.caption).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
                }
                Text(s.quelle == "skills.json" ? "Aus skills.json\(s.stand.map { ", Stand \(AgentsWorte.uhrzeit($0))" } ?? "")." : "Ohne skills.json aus den Skillordnern aufgelöst.")
                    .font(.caption2).foregroundStyle(.tertiary)
            }
            gruppe("Token je Ticketart") {
                if s.messungen.isEmpty {
                    Text("Noch keine Messung. Der Träger schreibt je Zug eine Zeile nach messungen.jsonl.")
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                ForEach(s.messungen) { m in
                    VStack(alignment: .leading, spacing: 1) {
                        Text(m.art).font(.callout.weight(.medium))
                        Text(WeltenSkillWorte.messung(m)).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            gruppe("Skill-Verlauf") {
                if s.verlauf.isEmpty { Text("Noch nichts.").font(.caption).foregroundStyle(.secondary) }
                ForEach(Array(s.verlauf.reversed().enumerated()), id: \.offset) { _, e in
                    VStack(alignment: .leading, spacing: 1) {
                        Text("\(AgentsWorte.uhrzeit(e.zeit)) · \(WeltenSkillWorte.aktion(e.aktion))\(e.skill.isEmpty ? "" : " · \(e.skill)")\(e.ziel.isEmpty ? "" : " → \(WeltenSkillWorte.ebene(e.ziel))")")
                            .font(.callout)
                        if !e.text.isEmpty { Text(e.text).font(.caption).foregroundStyle(.secondary) }
                    }
                }
            }
        }
        .accessibilityIdentifier("welten-skills")
    }

    private func zeile(_ skill: WeltSkill) -> some View {
        let offen = zustand.skillOffen.contains(skill.name)
        return VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Button {
                    if offen { zustand.skillOffen.remove(skill.name) } else { zustand.skillOffen.insert(skill.name) }
                } label: {
                    Image(systemName: offen ? "chevron.down" : "chevron.right").font(.caption).frame(width: 12)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(offen ? "SKILL.md zuklappen" : "SKILL.md zeigen")
                Text(skill.name).font(.callout.weight(.semibold).monospaced())
                Text(WeltenSkillWorte.ebene(skill.ebene)).font(.caption)
                    .padding(.horizontal, 5).padding(.vertical, 1)
                    .background(Capsule().fill(Color.secondary.opacity(0.15)))
                if skill.vorgeladen { Text("vorgeladen").font(.caption).foregroundStyle(.secondary) }
                Spacer(minLength: 0)
                Text(String(skill.version.prefix(8))).font(.caption2.monospaced()).foregroundStyle(.tertiary)
            }
            Text(skill.beschreibung).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if !skill.verdeckt.isEmpty {
                Text("verdeckt: " + skill.verdeckt.map { "\(WeltenSkillWorte.ebene($0.ebene))\($0.gleich ? " (gleicher Stand)" : "")" }.joined(separator: ", "))
                    .font(.caption).foregroundStyle(.secondary)
            }
            if skill.veraltet { Text("skills.json ist älter als der Ordner.").font(.caption).foregroundStyle(.orange) }
            if offen {
                Text(skill.skillMd + (skill.gekuerzt ? "\n[… gekürzt]" : ""))
                    .font(.caption.monospaced()).textSelection(.enabled)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Color(nsColor: .textBackgroundColor)))
                    .fixedSize(horizontal: false, vertical: true)
                if !skill.dateien.isEmpty {
                    Text("Dateien: \(skill.dateien.joined(separator: ", "))").font(.caption2.monospaced()).foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 3)
    }

    private func gruppe<Inhalt: View>(_ titel: String, @ViewBuilder _ inhalt: () -> Inhalt) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(titel).font(.callout.weight(.semibold)).foregroundStyle(.secondary)
            inhalt()
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color(nsColor: .controlBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color(nsColor: .separatorColor)))
    }
}

// MARK: Der Vorschlag im Ticketdetail

struct WeltenSkillVorschlagKarte: View {
    let ticket: WeltTicket
    let vorschlag: WeltSkillVorschlag
    let welt: Welt
    @Bindable var zustand: WeltenZustand

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Skill-Vorschlag").font(.headline)
            Text("„\(vorschlag.skill)“ von \(welt.anzeigename(vorschlag.agent)) für \(WeltenSkillWorte.ebene(vorschlag.ziel)) · prüft \(welt.anzeigename(vorschlag.pruefer)) · \(vorschlag.stand)")
                .font(.callout)
            if !vorschlag.beschreibung.isEmpty { Text(vorschlag.beschreibung).font(.callout).foregroundStyle(.secondary) }
            if !vorschlag.begruendung.isEmpty { Text("Begründung: \(vorschlag.begruendung)").font(.callout).foregroundStyle(.secondary) }
            Text("Stand \(vorschlag.version.prefix(12)), Zielebene bisher \(vorschlag.basisVersion.map { String($0.prefix(12)) } ?? "neu")")
                .font(.caption.monospaced()).foregroundStyle(.secondary)
            ScrollView([.vertical, .horizontal]) {
                Text(vorschlag.diff + (vorschlag.diffGekuerzt ? "\n[… gekürzt; vollständig in diff.txt]" : ""))
                    .font(.caption.monospaced())
                    .textSelection(.enabled)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(minHeight: 120, maxHeight: 320)
            .background(RoundedRectangle(cornerRadius: 6).fill(Color(nsColor: .textBackgroundColor)))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color(nsColor: .separatorColor)))
            .accessibilityIdentifier("welten-skill-diff")
            if let von = vorschlag.entschiedenVon {
                Text("\(vorschlag.stand == "übernommen" ? "Übernommen" : "Abgelehnt") von \(welt.anzeigename(von))\((vorschlag.bemerkung ?? vorschlag.grund).map { ": \($0)" } ?? "")")
                    .font(.callout)
            }
            if vorschlag.offen && !["abgenommen", "verworfen"].contains(ticket.stand) { knoepfe }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(nsColor: .controlBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(nsColor: .separatorColor)))
    }

    @ViewBuilder private var knoepfe: some View {
        if zustand.skillAblehnenOffen == ticket.id {
            VStack(alignment: .leading, spacing: 6) {
                TextField("Warum nicht, in einem Satz", text: $zustand.skillGrund, axis: .vertical)
                    .lineLimit(1...3)
                    .accessibilityIdentifier("welten-skill-grund")
                HStack {
                    Spacer()
                    Button("Abbrechen") { zustand.skillAblehnenOffen = nil; zustand.skillGrund = "" }
                    Button("Ablehnen", role: .destructive) { Task { await zustand.skillAblehnen(welt, ticket: ticket.id, echt: true) } }
                        .disabled(zustand.skillGrund.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || zustand.laufend.contains("skill_ablehnen"))
                }
            }
        } else {
            HStack {
                Text("Prüfen: keine Agentenregel gelockert, keine Freigabe umgangen, kein doppelter Zweck.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Spacer()
                Button("Ablehnen …") { zustand.skillAblehnenOffen = ticket.id; zustand.skillGrund = "" }
                Button("Übernehmen") { Task { await zustand.skillAbnehmen(welt, ticket: ticket.id, echt: true) } }
                    .disabled(zustand.laufend.contains("skill_abnehmen"))
                    .accessibilityIdentifier("welten-skill-uebernehmen")
            }
        }
    }
}
