// Die Bloecke des Gespraechs (Auftrag 3.2), nach chatbuehne/ansicht.ts und
// dem Foto vom 12.08.: die Nachricht des Menschen im umrandeten Kasten, der
// Text des Programms fliesst (Markdown), Denken als gedimmte, aufklappbare
// Zeile, ein Werkzeugaufruf mit Titelzeile „Bash — <description>“ und je einer
// Zeile EIN und AUS (Klick klappt die volle Ein- und Ausgabe auf), die
// Freigabefrage als Kasten mit Erlauben und Ablehnen.
//
// MARKDOWN NUR FUER MENSCH UND AGENT, und nur ueber den eigenen Leser
// (WerkbankProtokoll/Chat.swift `ChatMarkdown`): er setzt Praesentations-
// absichten (fett, kursiv, Code) und macht Links zu Text -- nie Markup, nie
// einen Anker. Werkzeugausgaben und Denken stehen als `Text(String)`, wortgleich.
// Ein Pfad im Text ist anklickbar (Auftrag 3.6): die Fundstelle bekommt das
// Link-Merkmal, siehe `ChatPfadmarken` am Ende dieser Datei. Der Text bleibt
// dabei selektierbar, und ein Block bleibt ein Block.
//
// Textstile statt Punktgroessen, Systemfarben, SF Symbols; Codebloecke
// monospaced, Inline-Code hinterlegt.
import SwiftUI
import WerkbankProtokoll

enum ChatBloecke {
    /// Die erste Zeile einer Ausgabe -- mehr passt nicht in eine Zeile.
    static func eineZeile(_ s: String) -> String {
        let zeilen = s.components(separatedBy: "\n").filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        guard let erste = zeilen.first?.trimmingCharacters(in: .whitespaces) else { return "" }
        return zeilen.count > 1 ? erste + " …" : erste
    }
}

/// Ein Block, je nach Sorte.
struct ChatBlockAnsicht: View {
    let block: ChatBlock
    let zustand: ChatZustand
    var beleg = false

    var body: some View {
        switch block {
        case .text(let t):
            switch t.art {
            case "mensch": MenschBlock(block: t, bloecke: zustand.gelesen[t.id]?.bloecke ?? ChatMarkdown.bloecke(t.text),
                                       treffer: zustand.pfade[t.id] ?? [])
            case "denken": DenkenBlock(block: t, zustand: zustand, beleg: beleg)
            case "system": SystemBlock(block: t)
            default: AgentBlock(block: t, bloecke: zustand.gelesen[t.id]?.bloecke ?? ChatMarkdown.bloecke(t.text),
                                treffer: zustand.pfade[t.id] ?? [])
            }
        case .werkzeug(let w):
            WerkzeugBlockAnsicht(block: w, zustand: zustand, beleg: beleg)
        case .freigabe(let f):
            FreigabeBlockAnsicht(block: f, zustand: zustand, beleg: beleg)
        }
    }
}

/// Der Punkt in der Spalte links (das Foto: eine Punktspalte).
private struct Punkt: View {
    var farbe: Color = .secondary
    var body: some View {
        Circle()
            .fill(farbe)
            .frame(width: 6, height: 6)
            .padding(.top, 7)
            .accessibilityHidden(true)
    }
}

/// Die Nachricht des Menschen: im umrandeten Kasten, rechts buendig wie ein Chat.
struct MenschBlock: View {
    let block: ChatTextBlock
    let bloecke: [MarkdownBlock]
    /// Die Pfade, die der Kern in diesem Block gefunden hat (Auftrag 3.6).
    var treffer: [PfadTreffer] = []

    var body: some View {
        HStack {
            Spacer(minLength: 40)
            MarkdownAnsicht(bloecke: bloecke, treffer: treffer)
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color(nsColor: .controlBackgroundColor)))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Color(nsColor: .separatorColor)))
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Du: \(block.text)")
        .accessibilityIdentifier("chat-mensch")
    }
}

/// Der Text des Programms fliesst; waehrend er einlaeuft, pulsiert der Punkt nicht -- er ist im Akzent.
struct AgentBlock: View {
    let block: ChatTextBlock
    let bloecke: [MarkdownBlock]
    var treffer: [PfadTreffer] = []

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Punkt(farbe: block.offen ? .accentColor : .secondary)
            MarkdownAnsicht(bloecke: bloecke, treffer: treffer)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Claude: \(block.text)")
        .accessibilityIdentifier("chat-agent")
    }
}

struct SystemBlock: View {
    let block: ChatTextBlock
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Punkt()
            Text(block.text).font(.callout).foregroundStyle(.secondary).textSelection(.enabled)
        }
        .accessibilityIdentifier("chat-system")
    }
}

/// Das Denken: gedimmt, zugeklappt, ein Klick zeigt es.
struct DenkenBlock: View {
    let block: ChatTextBlock
    let zustand: ChatZustand
    var beleg = false

    var body: some View {
        let auf = zustand.offen.contains(block.id)
        HStack(alignment: .top, spacing: 10) {
            Punkt(farbe: Color.secondary.opacity(0.5))
            VStack(alignment: .leading, spacing: 4) {
                Klappkopf(auf: auf, beleg: beleg) { zustand.klappen(block.id) } label: {
                    Text(zustand.t("wort.denken")).font(.callout).italic().foregroundStyle(.secondary)
                }
                if auf {
                    Text(block.text).font(.callout).foregroundStyle(.secondary).textSelection(.enabled)
                }
            }
        }
        .accessibilityIdentifier("chat-denken")
    }
}

/// Ein Kopf, der auf- und zuklappt: das Dreieck als Zeichen, der Klick auf der ganzen Zeile.
struct Klappkopf<Label: View>: View {
    let auf: Bool
    var beleg = false
    let handlung: () -> Void
    @ViewBuilder let label: Label

    var body: some View {
        let inhalt = HStack(spacing: 5) {
            Image(systemName: auf ? "chevron.down" : "chevron.right")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .frame(width: 10)
            label
        }
        if beleg {
            inhalt
        } else {
            Button(action: handlung) { inhalt }
                .buttonStyle(.plain)
                .accessibilityAddTraits(.isButton)
                .accessibilityValue(auf ? "aufgeklappt" : "zugeklappt")
        }
    }
}

/// Der Werkzeugaufruf, wie im Foto: „Bash — <description>“, darunter EIN und AUS.
struct WerkzeugBlockAnsicht: View {
    let block: ChatWerkzeugBlock
    let zustand: ChatZustand
    var beleg = false

    var body: some View {
        let auf = zustand.offen.contains(block.id)
        HStack(alignment: .top, spacing: 10) {
            Punkt(farbe: block.fehler ? .red : (block.laeuft ? .accentColor : .secondary))
            VStack(alignment: .leading, spacing: 4) {
                Klappkopf(auf: auf, beleg: beleg) { zustand.klappen(block.id) } label: {
                    HStack(spacing: 6) {
                        Text(block.name).fontWeight(.semibold)
                        if !block.beschreibung.isEmpty {
                            Text("—").foregroundStyle(.tertiary)
                            Text(block.beschreibung).foregroundStyle(.secondary).lineLimit(1)
                        }
                        if block.laeuft {
                            Text(zustand.t("wort.laeuft")).font(.caption).foregroundStyle(.tint)
                        }
                    }
                }
                .accessibilityIdentifier("chat-werkzeugkopf")
                Paar(marke: zustand.t("wort.ein"), wert: block.ein)
                if !block.laeuft {
                    Paar(marke: zustand.t("wort.aus"), wert: ChatBloecke.eineZeile(block.aus), fehler: block.fehler)
                }
                if auf {
                    VollFeld(marke: zustand.t("wort.ein"), wert: block.einVoll)
                    if !block.aus.isEmpty { VollFeld(marke: zustand.t("wort.aus"), wert: block.aus) }
                }
            }
        }
        .accessibilityIdentifier("chat-werkzeug")
    }
}

/// EIN <wert> in einer Zeile, monospaced, rechts beschnitten.
private struct Paar: View {
    let marke: String
    let wert: String
    var fehler = false
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(marke).font(.caption2).fontWeight(.bold).foregroundStyle(.tertiary).frame(width: 28, alignment: .trailing)
            Text(wert).font(.body.monospaced()).foregroundStyle(fehler ? Color.red : Color.primary).lineLimit(1).truncationMode(.tail)
        }
    }
}

/// Die volle Ein- oder Ausgabe, als Codeblock.
private struct VollFeld: View {
    let marke: String
    let wert: String
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(marke).font(.caption2).fontWeight(.bold).foregroundStyle(.tertiary)
            Codeblock(text: wert)
        }
    }
}

/// Ein Codeblock: monospaced auf hinterlegter Flaeche, waagerecht rollbar.
struct Codeblock: View {
    let text: String
    var body: some View {
        ScrollView(.horizontal) {
            Text(text)
                .font(.body.monospaced())
                .textSelection(.enabled)
                .padding(8)
        }
        .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color(nsColor: .quaternarySystemFill)))
    }
}

/// Die Freigabefrage: eine Frage, die niemand sieht, haelt die Sitzung an, ohne zu sagen warum.
struct FreigabeBlockAnsicht: View {
    let block: ChatFreigabeBlock
    let zustand: ChatZustand
    var beleg = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(zustand.t("freigabe.frage", ["name": block.name]), systemImage: "hand.raised.circle.fill")
                .font(.headline)
                .foregroundStyle(block.offen ? Color.orange : Color.secondary)
            if !block.beschreibung.isEmpty { Text(block.beschreibung).foregroundStyle(.secondary) }
            Codeblock(text: block.einVoll)
            if block.defekt {
                Text(zustand.t("freigabe.defekt")).font(.callout).foregroundStyle(.red)
            } else if block.offen {
                HStack(spacing: 8) {
                    if beleg {
                        Text(zustand.t("freigabe.erlauben")).fontWeight(.semibold).foregroundStyle(.tint)
                        Text(zustand.t("freigabe.ablehnen"))
                    } else {
                        Button(zustand.t("freigabe.erlauben")) { zustand.freigabe(block.anfrageId, erlauben: true) }
                            .keyboardShortcut(.defaultAction)
                            .accessibilityIdentifier("chat-freigabe-ja")
                        Button(zustand.t("freigabe.ablehnen")) { zustand.freigabe(block.anfrageId, erlauben: false) }
                            .accessibilityIdentifier("chat-freigabe-nein")
                    }
                }
            } else {
                let wort = zustand.t("freigabe." + (block.entschieden.isEmpty ? "abgelehnt" : block.entschieden))
                Label(wort, systemImage: block.entschieden == "erlaubt" ? "checkmark.circle" : "xmark.circle")
                    .font(.callout)
                    .foregroundStyle(block.entschieden == "erlaubt" ? Color.green : Color.secondary)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color(nsColor: .controlBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(block.offen ? Color.orange : Color(nsColor: .separatorColor)))
        .accessibilityIdentifier("chat-freigabe")
    }
}

// MARK: - Markdown

/// Die gelesenen Bloecke als SwiftUI: Absaetze, Ueberschriften, Code, Listen, Zitate, Tabellen.
struct MarkdownAnsicht: View {
    let bloecke: [MarkdownBlock]
    /// Die im Text gefundenen Pfade -- jede Fundstelle wird ein Link (Auftrag 3.6).
    var treffer: [PfadTreffer] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(bloecke.enumerated()), id: \.offset) { _, b in
                switch b {
                case .absatz(let a):
                    Text(Self.ausgezeichnet(a, treffer: treffer)).textSelection(.enabled)
                case .ueberschrift(let ebene, let a):
                    Text(Self.ausgezeichnet(a, treffer: treffer)).font(ebene <= 1 ? .title2 : (ebene == 2 ? .title3 : .headline)).textSelection(.enabled)
                case .code(let c):
                    Codeblock(text: c)
                case .liste(let geordnet, let punkte):
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(Array(punkte.enumerated()), id: \.offset) { i, p in
                            HStack(alignment: .firstTextBaseline, spacing: 6) {
                                Text(geordnet ? "\(i + 1)." : "•").foregroundStyle(.secondary).frame(minWidth: 16, alignment: .trailing)
                                Text(Self.ausgezeichnet(p, treffer: treffer)).textSelection(.enabled)
                            }
                        }
                    }
                case .zitat(let a):
                    HStack(alignment: .top, spacing: 8) {
                        RoundedRectangle(cornerRadius: 1).fill(.quaternary).frame(width: 3)
                        Text(Self.ausgezeichnet(a, treffer: treffer)).foregroundStyle(.secondary).textSelection(.enabled)
                    }
                case .tabelle(let kopf, let zeilen):
                    VStack(alignment: .leading, spacing: 0) {
                        Tabellenzeile(zellen: kopf, kopf: true)
                        Divider()
                        ForEach(Array(zeilen.enumerated()), id: \.offset) { _, z in
                            Tabellenzeile(zellen: z, kopf: false)
                        }
                    }
                    .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color(nsColor: .quaternarySystemFill)))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Inline-Code bekommt seine Hinterlegung -- die Praesentationsabsicht allein
    /// macht ihn nur monospaced. Danach werden die gefundenen Pfade zu Links.
    static func ausgezeichnet(_ a: AttributedString, treffer: [PfadTreffer] = []) -> AttributedString {
        var s = a
        for r in s.runs where r.inlinePresentationIntent == .code {
            s[r.range].backgroundColor = Color(nsColor: .quaternarySystemFill)
        }
        return ChatPfadmarken.markieren(s, treffer: treffer)
    }
}

/// ANKLICKBARE PFADE IN EINER GEZEICHNETEN NACHRICHT (Auftrag 3.6).
///
/// Die Electron-Fassung zerschneidet dafuer Textknoten im DOM und setzt
/// `<span>`-Elemente ein -- damit ein Dateiname mit `<img onerror>` darin nie
/// durch `innerHTML` laeuft (chat/pfadlinks.ts, „nach dem Zeichnen"). Hier
/// stellt sich die Frage gar nicht: der Text steht in einem `AttributedString`
/// und wird nie als Markup gedeutet. Die Fundstelle bekommt schlicht das
/// Link-Merkmal, und `Text` zeichnet sie als Link; der Klick landet ueber
/// `OpenURLAction` in der Buehne (ChatBuehne.swift) und von dort im
/// `Pfadoeffner`.
///
/// Ein Codeblock (`.code`) bleibt aussen vor -- darin stehen Befehle, und ein
/// Pfad in einem Befehl ist ein Argument, kein Link. Inline-Code (Backticks)
/// wird mitgenommen, wie dort.
enum ChatPfadmarken {
    /// Das eigene Schema. Es steht nur in dieser Datei und in der Buehne, und
    /// keine App ausser dieser sieht es je: ein Link darin verlaesst das
    /// Fenster nicht.
    static let schema = "awbpfad"

    static func url(_ t: PfadTreffer) -> URL? {
        var teile = URLComponents()
        teile.scheme = schema
        teile.host = "oeffnen"
        teile.queryItems = [
            URLQueryItem(name: "p", value: t.abs),
            URLQueryItem(name: "z", value: String(t.zeile)),
            URLQueryItem(name: "s", value: String(t.spalte)),
            URLQueryItem(name: "a", value: t.art),
        ]
        return teile.url
    }

    /// Der Treffer hinter einer angeklickten Stelle.
    static func treffer(aus url: URL) -> PfadTreffer? {
        guard url.scheme == schema,
              let teile = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        let werte = Dictionary(uniqueKeysWithValues: (teile.queryItems ?? []).map { ($0.name, $0.value ?? "") })
        guard let pfad = werte["p"], !pfad.isEmpty else { return nil }
        return PfadTreffer(kandidat: pfad, abs: pfad, art: werte["a"] ?? "datei",
                           zeile: Int(werte["z"] ?? "") ?? 0, spalte: Int(werte["s"] ?? "") ?? 0)
    }

    /// Jede Fundstelle eines Treffers im Text bekommt das Link-Merkmal.
    static func markieren(_ a: AttributedString, treffer: [PfadTreffer]) -> AttributedString {
        guard !treffer.isEmpty else { return a }
        let nachWortlaut = Dictionary(treffer.map { ($0.kandidat, $0) }, uniquingKeysWith: { erster, _ in erster })
        let text = String(a.characters)
        let stellen = Pfadlinks.stellen(text).filter { nachWortlaut[$0.wortlaut] != nil }
        guard !stellen.isEmpty else { return a }
        var s = a
        for stelle in stellen {
            guard let t = nachWortlaut[stelle.wortlaut],
                  let ziel = url(t),
                  let von = s.index(s.startIndex, offsetByCharacters: stelle.von),
                  let bis = s.index(s.startIndex, offsetByCharacters: stelle.bis) else { continue }
            s[von..<bis].link = ziel
        }
        return s
    }
}

private extension AttributedString {
    /// Ein Index um `n` Zeichen weiter -- `nil`, wenn er hinter dem Ende laege.
    func index(_ i: AttributedString.Index, offsetByCharacters n: Int) -> AttributedString.Index? {
        guard n >= 0, let ziel = characters.index(i, offsetBy: n, limitedBy: characters.endIndex) else { return nil }
        return ziel
    }
}

private struct Tabellenzeile: View {
    let zellen: [AttributedString]
    let kopf: Bool
    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            ForEach(Array(zellen.enumerated()), id: \.offset) { _, z in
                Text(MarkdownAnsicht.ausgezeichnet(z))
                    .fontWeight(kopf ? .semibold : .regular)
                    .textSelection(.enabled)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}
