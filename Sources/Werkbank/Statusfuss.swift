// Der Statusfuss (Auftrag 2.5, mac/PLAN.md): die Fusszeile der LINKEN
// Seitenleiste -- nicht unten ueber die volle Breite (Entscheidung des Nutzers
// vom 05.09., „Statusleiste nicht unten“, „Maschinen prominenter“). Darin,
// von oben nach unten, wie in der Electron-Fassung (fuss-status.ts, Bild
// results/entwurf2/bilder/nachher-leiste.png):
//
//   die Maschinenkarten (Maschinenkarte.swift), dauerhaft sichtbar
//   der Hinweis des Kerns (`awb:meldung`, auch der Absturzhinweis aus
//     absturz.ts): eine Zeile, solange sie gilt (30 s beim Absturz) oder bis
//     zum Klick
//   Verbrauch heute (`budget`), die Woche mit Balken und erlaubtem Anteil
//   „N Worker laufen“ und das Zahnrad
//
// Apple raet von Bedienelementen am unteren Fensterrand ab (plattformen.md,
// macOS): Fenster stehen oft so, dass die Unterkante unter dem Bildschirm
// liegt. Deshalb ist hier alles Anzeige; die Karten oeffnen ein Popover, und
// das Zahnrad ist nur eine ZWEITE Tuer zu den Einstellungen -- die erste
// sitzt in der Symbolleiste, wo sie immer erreichbar bleibt.
//
// Hier entsteht keine zweite Bewertung: Ampel, Budget und Erreichbarkeit hat
// der Kern schon ausgewertet (ampel.ts, budget.ts, remote.ts). Was er nicht
// liefert, steht nicht da.
import SwiftUI
import WerkbankProtokoll

struct Statusfuss: View {
    let kern: KernVerbindung
    let oberflaeche: Oberflaeche
    unowned let handlungen: Fusshandlungen
    var kopflos = false
    /// Fuer kopflose Bilder (Fenster.schuss): keine Buttons, offenes Feld unter der Karte.
    var beleg = false

    var body: some View {
        let m = kern.modell
        VStack(alignment: .leading, spacing: 8) {
            ForEach(m.maschinenKarten) { k in
                Maschinenkarte(maschine: k, ampel: m.ampel(fuer: k.name), oberflaeche: oberflaeche,
                               handlungen: handlungen, kopflos: kopflos, beleg: beleg)
            }
            if hinweisSichtbar {
                Hinweiszeile(text: kern.meldung, handlungen: handlungen, beleg: beleg)
            }
            // Die fertige Ergebnisdatei (`awb:ergebnis`, Auftrag 3.5). Sie steht
            // hier, wo der Hinweis des Kerns schon steht, und geht nach 30 s von
            // selbst -- keine Dauerflaeche (A14). „Öffnen“ legt sie in den Editor.
            if let e = oberflaeche.ergebnis, oberflaeche.ergebnisBis > Date() {
                Ergebniszeile(ergebnis: e, handlungen: handlungen, beleg: beleg)
            }
            VStack(alignment: .leading, spacing: 4) {
                // Der Weg zur Verbrauchsseite (Auftrag 3.8). Bis dahin stand
                // hier nur Text; der Platzhalter aus 2.5 ist damit weg.
                if beleg {
                    Text(m.budget?.heuteText ?? "Budget: n. v.")
                        .help(budgetHilfe(m.budget))
                        .accessibilityIdentifier("verbrauch")
                } else {
                    Button { handlungen.verbrauchZeigen() } label: {
                        Text(m.budget?.heuteText ?? "Budget: n. v.")
                    }
                    .buttonStyle(.plain)
                    .help(budgetHilfe(m.budget) + " — anklicken für die Verbrauchsseite (⌥⌘V)")
                    .accessibilityLabel("Verbrauch: \(m.budget?.heuteText ?? "nicht verfügbar"), Verbrauchsseite öffnen")
                    .accessibilityIdentifier("verbrauch")
                }
                if let b = m.budget, b.wocheDa {
                    Wochenzeile(budget: b)
                }
                HStack {
                    Text("\(m.laufendeWorkerGesamt)").fontWeight(.semibold).monospacedDigit()
                    + Text(" Worker laufen")
                    Spacer()
                    if beleg {
                        Image(systemName: "gearshape").foregroundStyle(.secondary)
                    } else {
                        Button { handlungen.einstellungenZeigen() } label: {
                            Image(systemName: "gearshape")
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                        .help("Einstellungen (⌘,)")
                        .accessibilityLabel("Einstellungen")
                        .accessibilityIdentifier("zahnrad-fuss")
                    }
                }
                .accessibilityElement(children: .combine)
            }
            .font(.callout)
            .padding(.horizontal, 4)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityIdentifier("statusfuss")
    }

    var hinweisSichtbar: Bool { !kern.meldung.isEmpty && kern.meldungBis > Date() }

    private func budgetHilfe(_ b: BudgetStand?) -> String {
        guard let b, b.ok else { return "Budget: wb-budget nicht verfügbar" }
        return "Budget — \(b.text)"
    }
}

/// Der Wochenstand: Prozent, ein schmaler Balken, der erlaubte Anteil daneben.
/// Ueber der Grenze faerbt der Balken in die Wartefarbe (fuss-status.ts `wochenStueck`).
struct Wochenzeile: View {
    let budget: BudgetStand

    var body: some View {
        // Eine Zeile, wo sie passt; in einer schmalen Leiste (Mindestbreite
        // 200 pt) der erlaubte Anteil darunter, statt abgeschnitten (gemessen 06.09.).
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                Text(budget.wocheText).monospacedDigit().fixedSize()
                balken.frame(minWidth: 40)
                Text(budget.erlaubtText).monospacedDigit().foregroundStyle(.secondary).fixedSize()
            }
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(budget.wocheText).monospacedDigit().fixedSize()
                    balken.frame(minWidth: 24)
                }
                Text(budget.erlaubtText).monospacedDigit().foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .help("\(Int(budget.wocheVerbraucht.rounded())) % des Wochenkontingents verbraucht; an einem gleichmäßig aufgeteilten Fenster wären bis heute Abend \(Int(budget.wocheErlaubt.rounded())) % erlaubt.")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(budget.wocheText), \(budget.erlaubtText)\(budget.drueber ? ", über der Grenze" : "")")
        .accessibilityIdentifier("woche")
    }

    /// Der Balken als Form, nicht als ProgressView: die ist AppKit-gestuetzt
    /// und zeichnet im ImageRenderer ein Sperrsymbol (gemessen 06.09.).
    private var balken: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(.quaternary)
                Capsule().fill(budget.drueber ? AnyShapeStyle(.orange) : AnyShapeStyle(.tint))
                    .frame(width: g.size.width * min(100, max(0, budget.wocheVerbraucht)) / 100)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 6)
    }
}

/// Der Hinweis des Kerns im Fuss: eine Zeile, ein Klick raeumt sie weg.
struct Hinweiszeile: View {
    let text: String
    unowned let handlungen: Fusshandlungen
    var beleg = false

    /// Ein Knopf, damit der Hinweis auch per Tab und Leertaste weggeht (dazu
    /// Darstellung, Hinweis ausblenden ⌘⇧H); im Beleg nur seine Flaeche.
    var body: some View {
        Group {
            if beleg {
                zeile
            } else {
                Button { handlungen.hinweisWeg() } label: { zeile }
                    .buttonStyle(.plain)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Hinweis: \(text), ausblenden")
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("hinweis")
    }

    private var zeile: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: "info.circle").foregroundStyle(.secondary).accessibilityHidden(true)
            Text(text).font(.callout).lineLimit(4).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(.quaternary.opacity(0.5)))
        .contentShape(Rectangle())
    }
}

/// Die fertige Ergebnisdatei eines Workers (`awb:ergebnis`, V2/Auftrag 3.5).
/// Zwei Wege zum Ergebnis wie in der Electron-Fassung (meldungen.ts): der Name
/// samt Pfad oeffnet die Datei, das Kreuz raeumt die Zeile weg. Sie geht nach
/// 30 Sekunden ohnehin von selbst.
struct Ergebniszeile: View {
    let ergebnis: ErgebnisNutzlast
    unowned let handlungen: Fusshandlungen
    var beleg = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: "checkmark.circle").foregroundStyle(.secondary).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                // Fremder Text (Worker-Name, Pfad) als String, nie als LocalizedStringKey.
                (Text(ergebnis.name).fontWeight(.semibold) + Text(" ist fertig"))
                    .lineLimit(1)
                Text(Pfadlinks.kurzerPfad(ergebnis.path))
                    .font(.caption).foregroundStyle(.secondary)
                    .lineLimit(1).truncationMode(.head)
            }
            Spacer(minLength: 4)
            if beleg {
                Text("Öffnen").font(.callout).foregroundStyle(.secondary)
            } else {
                Button("Öffnen") { handlungen.ergebnisOeffnen() }
                    .buttonStyle(.link)
                    .accessibilityIdentifier("ergebnis-oeffnen")
                Button { handlungen.ergebnisWeg() } label: { Image(systemName: "xmark").font(.caption2) }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .help("Meldung ausblenden")
                    .accessibilityLabel("Meldung ausblenden")
            }
        }
        .font(.callout)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(.quaternary.opacity(0.5)))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("ergebnis")
    }
}

/// Die Auskunft fuer `awbmac-ctl ui` (`ui.status`) -- dieselben Feldnamen wie
/// `rendered.status` der Electron-Fassung (renderer.ts), damit eine Suite
/// beide Fassungen gleich liest.
@MainActor
enum StatusfussAuskunft {
    static func auskunft(kern: KernVerbindung, oberflaeche: Oberflaeche, kopflos: Bool) -> [String: Any] {
        let m = kern.modell
        let karten = m.maschinenKarten
        let hinweis = !kern.meldung.isEmpty && kern.meldungBis > Date()
        return [
            "inLinkerLeiste": true,
            "maschinenKarten": karten.count,
            "maschinen": karten.map { k -> [String: Any] in
                let a = m.ampel(fuer: k.name)
                let offen = oberflaeche.offeneKarte == k.name
                return [
                    "name": k.name,
                    "eigen": k.eigen,
                    "punktFarbe": k.punktFarbe,
                    "punktForm": Maschinenkarte.punkt(k.punktFarbe).form,
                    "feldOffen": offen,
                    "feld": offen ? MaschinenFeld.text(k, a) : "",
                    "kurz": k.kurzzeile,
                    "sichtbar": true,
                    "pausiert": k.pausiert,
                    "wort": k.pausiert ? "pausiert" : "",
                    "schalter": k.eigen ? NSNull() : !k.pausiert,
                    "ampel": a?.farbe ?? "",
                    "ampelText": a?.befundText ?? "",
                ]
            },
            "ampel": m.ampel.map { ["machine": $0.machine, "farbe": $0.farbe, "befunde": $0.befunde.map(\.text)] },
            "worker": "\(m.laufendeWorkerGesamt) Worker laufen",
            "verbrauch": m.budget?.heuteText ?? "Budget: n. v.",
            "budget": m.budget.map { b -> [String: Any] in
                ["ok": b.ok, "heuteTokens": b.heuteTokens, "hochrechnung24h": b.hochrechnung24h, "fiveHourPct": b.fiveHourPct,
                 "sevenDayPct": b.sevenDayPct, "wocheVerbraucht": b.wocheVerbraucht, "wocheErlaubt": b.wocheErlaubt,
                 "wocheSichtbar": b.wocheDa, "woche": b.wocheDa ? b.wocheText : "", "erlaubt": b.wocheDa ? b.erlaubtText : "",
                 "drueber": b.drueber, "text": b.text]
            } ?? NSNull(),
            "zahnrad": true,
            "notiz": hinweis ? kern.meldung : "",
            "notizBisMs": hinweis ? Int(kern.meldungBis.timeIntervalSince1970 * 1000) : 0,
            // Die Ergebnismeldung (Auftrag 3.5): Worker, Datei, Knopf.
            "ergebnis": oberflaeche.ergebnisBis > Date() && oberflaeche.ergebnis != nil
                ? ["name": oberflaeche.ergebnis?.name ?? "", "pfad": oberflaeche.ergebnis?.path ?? "",
                   "knopf": "Öffnen"] as [String: Any]
                : ["name": "", "pfad": "", "knopf": ""] as [String: Any],
            "kopflos": kopflos,
        ]
    }
}
