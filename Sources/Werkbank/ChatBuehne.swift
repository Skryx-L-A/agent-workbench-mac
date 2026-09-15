// Die Chat-Buehne (Auftrag 3.2, mac/PLAN.md): die Chat-Sitzung als eigene
// Ansicht im Inhaltsbereich, an der Stelle der Kacheln -- wie in der
// Electron-Fassung (chatbuehne/ansicht.ts, renderer/chatbuehne-view.ts), nach
// dem Foto vom 12.08.: Punktspalte links, Werkzeugaufrufe mit Titelzeile und je
// einer Zeile EIN/AUS, gedimmte Denk-Zeile, unten ein umrandetes Eingabefeld
// mit Modus-Marke, darunter die Statusleiste.
//
// WAS WO LIEGT. Der Zustand (`ChatZustand`) haelt den Verlauf, was aufgeklappt
// ist, das Eingabefeld und die Vervollstaendigung; die reinen Rechnungen
// (Teilstaende zusammenfuehren, Ausloeser, Filter, Markdown) stehen in
// WerkbankProtokoll/Chat.swift und laufen unter `swift test`. Die Bloecke
// zeichnet ChatBloecke.swift, das Eingabefeld ChatEingabe.swift.
//
// WER ENTSCHEIDET, WAS LIEGT: das Modell des Kerns (`chatGezeigt`), nie der
// Klick. Das Fenster ruft `nachModell` in seinem Takt; bei einer anderen
// Kennung wird der Zustand frisch gebaut, der volle Stand geholt (`seit: 0`)
// und die Bereitschaft gemeldet (`awb:chat-bereit`) -- darauf wartet
// `zeigeAufBuehne` im Kern. Danach kommt von sich aus nur noch das Geaenderte
// (`awb:chat-stand-neu`, Befund B1).
//
// GEMESSEN WIRD JEDES ZEICHNEN (`zeiten`, wie `chat-zeiten` der Electron-
// Suite): die Zeit vom Eintreffen eines Standes bis zum fertigen Zustand,
// samt Markdown-Lesen der geaenderten Bloecke -- das Gegenstueck zu
// `Chatansicht.zeichne` im DOM. Was SwiftUI danach auf den Bildschirm bringt,
// haengt an seinem eigenen Takt und wird hier nicht mitgezaehlt.
//
// FREMDER TEXT BLEIBT TEXT (freigabenmarkup, 05.09.): Nachrichten und
// Werkzeugausgaben stehen in `Text(String)` oder gehen durch den eigenen
// Markdown-Leser, der nur Praesentationsabsichten setzt -- nie als
// LocalizedStringKey. Textstile, Systemfarben, SF Symbols, keine Emojis.
import AppKit
import SwiftUI
import WerkbankProtokoll

/// Die Texte der Buehne, DE und EN, dieselben Schluessel wie chatbuehne/texte.ts.
enum ChatTexte {
    static let de: [String: String] = [
        "eingabe.platzhalter": "Claude fragen …",
        "eingabe.senden": "Senden",
        "eingabe.hinweis": "Eingabe sendet, Umschalt+Eingabe macht einen Zeilenumbruch. „/“ zeigt die Befehle, „@“ die Dateien.",
        "eingabe.haengtNach": "Du hast hochgerollt — die Ansicht folgt neuen Zeilen nicht mehr. Nach unten rollen holt sie zurück.",
        "knopf.neustart": "Frisch starten",
        "knopf.halt": "Den laufenden Zug unterbrechen (Escape)",
        "modus.wechseln": "Freigabemodus: {modus} — Klick schaltet zum nächsten weiter.",
        "modus.abgelehnt": "Der Harness hat die Umschaltung abgelehnt: {grund}",
        "worker.titel": "Worker",
        "worker.wechseln": "Zu „{name}“ wechseln — das Gespräch bleibt im Hintergrund und läuft weiter.",
        "worker.beendet": "„{name}“ läuft nicht mehr. Der Pane steht noch; ein Klick zeigt, was zuletzt darin stand.",
        "vervoll.befehle": "Befehle",
        "vervoll.dateien": "Dateien im Projektordner",
        "vervoll.dateien.ohneGit": "Dateien im Projektordner — ohne git gelesen, nur die .gitignore der Wurzel gilt",
        "status.modell": "Das Modell, mit dem diese Sitzung läuft.",
        "status.kontext": "Kontextfenster zu {prozent} % belegt — belegte Tokens des letzten Zuges gegen die Fenstergröße aus der Modell-Registry.",
        "status.kontext.ohneFenster": "Belegte Tokens des letzten Zuges. Die Fenstergröße dieses Modells steht nicht in der Registry, deshalb kein Balken.",
        "status.5h": "Anteil des 5-Stunden-Kontingents des Anthropic-Kontos{reset}. Dieselbe Quelle wie die Statuszeile im Terminal.",
        "status.7d": "Anteil des 7-Tage-Kontingents des Anthropic-Kontos. Dieselbe Quelle wie die Statuszeile im Terminal.",
        "status.kosten": "Aufgelaufene Kosten, so wie der Harness sie nennt.",
        "kopf.ordner": "Ordner: {ordner}",
        "kopf.tokens": "{tokens} Token",
        "kopf.kosten": "{kosten} $",
        "zustand.arbeitet": "arbeitet",
        "zustand.wartet": "wartet",
        "zustand.freigabe": "wartet auf Freigabe",
        "zustand.beendet": "beendet",
        "zustand.fehler": "Fehler",
        "wort.denken": "Denken",
        "wort.ein": "EIN",
        "wort.aus": "AUS",
        "wort.laeuft": "läuft",
        "freigabe.frage": "{name} darf ausgeführt werden?",
        "freigabe.erlauben": "Erlauben",
        "freigabe.ablehnen": "Ablehnen",
        "freigabe.erlaubt": "Erlaubt",
        "freigabe.abgelehnt": "Abgelehnt",
        "freigabe.zurueckgezogen": "Zurückgezogen",
        "freigabe.defekt": "Ohne Kennung — diese Frage lässt sich nicht beantworten.",
        "leer.titel": "Noch kein Gespräch",
        "leer.satz": "Schreib unten etwas, und die Sitzung beginnt.",
    ]

    static let en: [String: String] = [
        "eingabe.platzhalter": "Ask Claude …",
        "eingabe.senden": "Send",
        "eingabe.hinweis": "Enter sends, Shift+Enter starts a new line. \"/\" lists the commands, \"@\" the files.",
        "eingabe.haengtNach": "You scrolled up — the view no longer follows new lines. Scroll to the bottom to bring it back.",
        "knopf.neustart": "Start fresh",
        "knopf.halt": "Interrupt the running turn (Escape)",
        "modus.wechseln": "Permission mode: {modus} — click switches to the next one.",
        "modus.abgelehnt": "The harness refused the switch: {grund}",
        "worker.titel": "Workers",
        "worker.wechseln": "Switch to \"{name}\" — the conversation stays in the background and keeps running.",
        "worker.beendet": "\"{name}\" is no longer running. Its pane is still there; a click shows what was last in it.",
        "vervoll.befehle": "Commands",
        "vervoll.dateien": "Files in the project folder",
        "vervoll.dateien.ohneGit": "Files in the project folder — read without git, only the root .gitignore applies",
        "status.modell": "The model this session runs on.",
        "status.kontext": "Context window {prozent} % used — tokens of the last turn against the window size from the model registry.",
        "status.kontext.ohneFenster": "Tokens of the last turn. The registry has no window size for this model, so there is no bar.",
        "status.5h": "Share of the Anthropic account's 5-hour quota{reset}. Same source as the status line in the terminal.",
        "status.7d": "Share of the Anthropic account's 7-day quota. Same source as the status line in the terminal.",
        "status.kosten": "Accrued cost, exactly as the harness reports it.",
        "kopf.ordner": "Folder: {ordner}",
        "kopf.tokens": "{tokens} tokens",
        "kopf.kosten": "${kosten}",
        "zustand.arbeitet": "working",
        "zustand.wartet": "idle",
        "zustand.freigabe": "waiting for approval",
        "zustand.beendet": "ended",
        "zustand.fehler": "error",
        "wort.denken": "Thinking",
        "wort.ein": "IN",
        "wort.aus": "OUT",
        "wort.laeuft": "running",
        "freigabe.frage": "Allow {name} to run?",
        "freigabe.erlauben": "Allow",
        "freigabe.ablehnen": "Deny",
        "freigabe.erlaubt": "Allowed",
        "freigabe.abgelehnt": "Denied",
        "freigabe.zurueckgezogen": "Withdrawn",
        "freigabe.defekt": "No request id — this question cannot be answered.",
        "leer.titel": "No conversation yet",
        "leer.satz": "Write something below and the session starts.",
    ]

    /// Ein Text in der Sprache des Standes; Platzhalter `{name}` bleiben stehen, wenn der Wert fehlt.
    static func t(_ sprache: String, _ schluessel: String, _ werte: [String: String] = [:]) -> String {
        let tabelle = sprache == "en" ? en : de
        var roh = tabelle[schluessel] ?? de[schluessel] ?? schluessel
        for (k, v) in werte { roh = roh.replacingOccurrences(of: "{\(k)}", with: v) }
        return roh
    }
}

/// Was die Vervollstaendigungsliste gerade zeigt.
struct VervollStand: Equatable {
    let art: Vervollart
    let eintraege: [Vorschlag]
    let kopfzeile: String
    var wahl = 0
}

/// Der Zustand der Buehne -- die Sitzung, die gerade liegt.
@MainActor
@Observable
final class ChatZustand {
    /// Welche Sitzung liegt; leer = keine.
    private(set) var chatId = ""
    private(set) var verlauf = ChatVerlauf()
    /// Die gelesenen Markdown-Bloecke je Block-Kennung, mit der Fassung, fuer die sie gelten.
    private(set) var gelesen: [String: (rev: Int, bloecke: [MarkdownBlock])] = [:]
    /// Welche Bloecke der Mensch aufgeklappt hat -- ueberlebt jeden Stand.
    var offen: Set<String> = []
    var worker: [ChatEintrag.Worker] = []
    /// Das Eingabefeld: Text und Schreibmarke (UTF-16-Offset).
    var eingabe = ""
    var marke = 0
    var feldHoehe: CGFloat = 0
    var vervoll: VervollStand?
    private(set) var dateiliste: [Dateivorschlag] = []
    private(set) var dateiquelle = "git"
    private var dateienUnterwegs = false
    /// Klebt die Ansicht unten? Dann folgt sie neuen Zeilen.
    var amEnde = true
    /// Die gemessenen Zeichenzeiten in Millisekunden (siehe Dateikopf).
    private(set) var zeiten: [Double] = []
    /// Ob die Bereitschaft fuer die liegende Sitzung gemeldet ist.
    private(set) var bereit = false
    /// Der letzte Fehler eines Kanals, fuer die Auskunft.
    private(set) var letzteMeldung = ""
    /// Das Feld soll den Fokus bekommen (nach dem Wechsel, nach dem Einsetzen).
    var fokusWunsch = 0
    /// ANKLICKBARE PFADE IM GESPRAECH (Auftrag 3.6, Vorbild chat/pfadlinks.ts):
    /// je Textblock die Pfade, die der Kern wirklich gefunden hat. Was hier
    /// nicht steht, bleibt Text -- die Ansicht erfindet keinen Treffer.
    private(set) var pfade: [String: [PfadTreffer]] = [:]
    /// Fuer welche Fassung eines Blocks schon gefragt wurde (Blockkennung -> rev):
    /// ein Ruf je Nachricht, nicht einer je Pfad und keiner zweimal.
    @ObservationIgnored private var pfadeGefragt: [String: Int] = [:]
    /// Der Klick auf eine Fundstelle -- das Fenster haengt den Pfadoeffner ein.
    @ObservationIgnored var aufPfad: ((PfadTreffer) -> Void)?

    @ObservationIgnored private let kern: KernVerbindung
    @ObservationIgnored private var wechselNr = 0

    init(kern: KernVerbindung) {
        self.kern = kern
        kern.aufChatStand = { [weak self] n in self?.standAngekommen(n) }
    }

    var sprache: String { verlauf.sprache }
    func t(_ schluessel: String, _ werte: [String: String] = [:]) -> String { ChatTexte.t(sprache, schluessel, werte) }

    // MARK: Das Modell entscheidet, was liegt

    /// Aufgerufen im Takt des Fensters mit `chatGezeigt` und den Workern aus dem Modell.
    func nachModell(gezeigt: String, worker: [ChatEintrag.Worker]) {
        if gezeigt == chatId {
            if worker != self.worker { self.worker = worker }
            return
        }
        wechselNr += 1
        let nr = wechselNr
        chatId = gezeigt
        verlauf = ChatVerlauf()
        gelesen = [:]
        pfade = [:]
        pfadeGefragt = [:]
        offen = []
        eingabe = ""
        marke = 0
        vervoll = nil
        dateiliste = []
        dateiquelle = "git"
        dateienUnterwegs = false
        amEnde = true
        bereit = false
        self.worker = worker
        guard !gezeigt.isEmpty else { return }
        Task { @MainActor in
            // `seit: 0` heisst „alles“ -- danach schickt der Kern nur das Geaenderte.
            let stand = await kern.chatDaten(seit: 0)
            // In der Zwischenzeit weitergewechselt: dieser Stand gehoert nicht mehr hierher.
            guard nr == wechselNr, chatId == gezeigt else { return }
            if let s = stand, s.id == gezeigt { anwenden(s) }
            bereit = true
            fokusWunsch += 1
            kern.chatBereit(gezeigt)
        }
    }

    private func standAngekommen(_ n: ChatStandNachricht) {
        // Ein Stand einer Sitzung, die nicht liegt, wird verworfen -- eingemischt
        // saehe er aus wie ein Teil dieses Gespraechs.
        guard n.id == chatId else { return }
        let start = DispatchTime.now().uptimeNanoseconds
        anwenden(n)
        zeiten.append(Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000)
    }

    /// Den Stand aufnehmen und die geaenderten Textbloecke lesen (Markdown).
    private func anwenden(_ n: ChatStandNachricht) {
        let geaendert = verlauf.anwenden(n)
        for id in geaendert {
            guard let b = verlauf.bloecke.first(where: { $0.id == id }) else { continue }
            if case .text(let t) = b, t.art == "mensch" || t.art == "agent" {
                gelesen[id] = (t.rev, ChatMarkdown.bloecke(t.text))
                pfadeSuchen(id, t)
            }
        }
        let bekannt = Set(verlauf.bloecke.map(\.id))
        for id in gelesen.keys where !bekannt.contains(id) { gelesen[id] = nil }
        for id in pfade.keys where !bekannt.contains(id) { pfade[id] = nil }
        for id in pfadeGefragt.keys where !bekannt.contains(id) { pfadeGefragt[id] = nil }
    }

    /// Die Kandidaten dieses Blocks EINMAL je Fassung pruefen lassen. Der Kern
    /// sieht mit `fs.stat` nach (main/chatpfade.ts) und merkt sich, was er
    /// gefunden hat; nur das laesst sich danach oeffnen.
    private func pfadeSuchen(_ id: String, _ t: ChatTextBlock) {
        guard pfadeGefragt[id] != t.rev else { return }
        let kandidaten = Pfadlinks.kandidaten(t.text)
        guard !kandidaten.isEmpty else {
            pfadeGefragt[id] = t.rev
            pfade[id] = nil
            return
        }
        pfadeGefragt[id] = t.rev
        let nr = wechselNr
        Task { @MainActor in
            let treffer = await kern.pfadePruefen(pane: "", kandidaten: kandidaten)
            guard nr == wechselNr else { return }
            pfade[id] = treffer.isEmpty ? nil : treffer
        }
    }

    /// Alle Fundstellen des Verlaufs in der Reihenfolge der Bloecke -- fuer
    /// `awbmac-ctl` und den Klick ueber den Steuerkanal.
    var alleTreffer: [PfadTreffer] {
        verlauf.bloecke.compactMap { pfade[$0.id] }.flatMap { $0 }
    }

    func zeitenLeeren() { zeiten = [] }

    // MARK: Handlungen des Menschen

    /// Das Feld leert sich SOFORT, nicht erst nach der Bestaetigung: ein Feld,
    /// das nach dem Absenden noch den alten Text zeigt, laedt zum zweiten Absenden ein.
    @discardableResult
    func abschicken() -> Bool {
        let text = eingabe.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, verlauf.laeuft else { return false }
        eingabe = ""
        marke = 0
        vervoll = nil
        amEnde = true
        Task { @MainActor in
            if !(await kern.chatSenden(text)) { letzteMeldung = "Senden abgelehnt" }
        }
        return true
    }

    func freigabe(_ anfrageId: String, erlauben: Bool) {
        Task { @MainActor in _ = await kern.chatFreigabe(anfrageId, erlauben: erlauben) }
    }

    func neustart() {
        Task { @MainActor in _ = await kern.chatNeustart() }
    }

    /// Einen Schritt weiter in der Modusliste; was WIRKLICH gilt, sagt danach der Harness.
    func modusWeiter() {
        guard let neu = verlauf.naechsterModus else { return }
        Task { @MainActor in _ = await kern.chatModus(neu) }
    }

    func halt() {
        guard verlauf.haltMoeglich else { return }
        Task { @MainActor in _ = await kern.chatHalt() }
    }

    func klappen(_ id: String) {
        if offen.contains(id) { offen.remove(id) } else { offen.insert(id) }
    }

    func workerZeigen(_ pane: String) {
        guard !chatId.isEmpty else { return }
        kern.chatWorkerZeigen(chat: chatId, pane: pane)
    }

    // MARK: Vervollstaendigung

    /// Nachsehen, was an der Schreibmarke steht, und die Liste danach richten.
    func vervollstaendigen() {
        guard let a = ChatVervollstaendigung.ausloeser(eingabe, marke: marke) else { vervoll = nil; return }
        if a.art == .befehl {
            let treffer = ChatVervollstaendigung.filtereBefehle(verlauf.befehle, a.muster)
            zeige(.befehl, treffer.map { Vorschlag(wert: $0.name, satz: [$0.argumente, $0.beschreibung].filter { !$0.isEmpty }.joined(separator: " — ")) }, t("vervoll.befehle"))
            return
        }
        if dateiliste.isEmpty, !dateienUnterwegs {
            dateienUnterwegs = true
            let nr = wechselNr
            Task { @MainActor in
                let antwort = await kern.chatDateien()
                dateienUnterwegs = false
                guard nr == wechselNr else { return }
                dateiliste = antwort.dateien
                dateiquelle = antwort.quelle
                vervollstaendigen()
            }
        }
        zeige(.datei, ChatVervollstaendigung.filtereDateien(dateiliste, a.muster).map { Vorschlag(wert: $0.pfad, ordner: $0.ordner) },
              dateiquelle == "git" ? t("vervoll.dateien") : t("vervoll.dateien.ohneGit"))
    }

    /// Eine LEERE Liste schliesst sie: die Auskunft ist die Abwesenheit der Liste.
    private func zeige(_ art: Vervollart, _ eintraege: [Vorschlag], _ kopfzeile: String) {
        guard !eintraege.isEmpty else { vervoll = nil; return }
        let wahl = (vervoll?.art == art && vervoll?.eintraege == eintraege) ? (vervoll?.wahl ?? 0) : 0
        vervoll = VervollStand(art: art, eintraege: eintraege, kopfzeile: kopfzeile, wahl: min(wahl, eintraege.count - 1))
    }

    func einsetzen(_ v: Vorschlag) {
        guard let a = ChatVervollstaendigung.ausloeser(eingabe, marke: marke) else { vervoll = nil; return }
        let neu = ChatVervollstaendigung.einsetzen(eingabe, a, wahl: v.wert, ordner: v.ordner)
        eingabe = neu.text
        marke = neu.marke
        vervoll = nil
        fokusWunsch += 1
        // Ein Ordner geht gleich eine Ebene tiefer weiter.
        if v.ordner { vervollstaendigen() }
    }

    /// Eine Taste anbieten -- dieselbe Reihenfolge wie im Renderer: erst die
    /// Liste (Umschalt+Eingabe gehoert dem Feld, Befund 9), dann Escape (nur,
    /// wenn etwas laeuft), dann Eingabe. Gibt zurueck, ob die Taste VERBRAUCHT ist.
    func taste(_ name: String, umschalt: Bool = false) -> Bool {
        if var v = vervoll {
            if name == "Enter" && umschalt { return false }
            switch name {
            case "Escape":
                vervoll = nil
                return true
            case "ArrowDown", "ArrowUp":
                let n = v.eintraege.count
                v.wahl = ((v.wahl + (name == "ArrowDown" ? 1 : -1)) % n + n) % n
                vervoll = v
                return true
            case "Enter", "Tab":
                einsetzen(v.eintraege[v.wahl])
                return true
            default:
                return false
            }
        }
        if name == "Escape" {
            if verlauf.haltMoeglich { halt() }
            return true
        }
        if name == "Enter" && !umschalt {
            abschicken()
            return true
        }
        return false
    }

    // MARK: Auskunft (awbmac-ctl)

    /// Der Verlauf als Text, so wie er zu lesen ist (`chat-text` der Electron-Fassung: innerText).
    func text() -> String {
        var zeilen: [String] = []
        zeilen.append(t("zustand." + verlauf.zustand))
        if !verlauf.kopf.fehler.isEmpty { zeilen.append(t("zustand.fehler") + ": " + verlauf.kopf.fehler) }
        if verlauf.neustartMoeglich && !verlauf.laeuft { zeilen.append(t("knopf.neustart")) }
        if !worker.isEmpty { zeilen.append(t("worker.titel") + " " + worker.map(\.name).joined(separator: " ")) }
        if verlauf.bloecke.isEmpty { zeilen.append(t("leer.titel")); zeilen.append(t("leer.satz")) }
        for b in verlauf.bloecke {
            switch b {
            case .text(let x):
                if x.art == "denken" {
                    zeilen.append(t("wort.denken"))
                    if offen.contains(x.id) { zeilen.append(x.text) }
                } else if let g = gelesen[x.id] {
                    zeilen.append(ChatMarkdown.klartext(g.bloecke))
                } else {
                    zeilen.append(x.text)
                }
            case .werkzeug(let w):
                zeilen.append([w.name, w.beschreibung, w.laeuft ? t("wort.laeuft") : ""].filter { !$0.isEmpty }.joined(separator: " "))
                zeilen.append(t("wort.ein") + " " + w.ein)
                if !w.laeuft { zeilen.append(t("wort.aus") + " " + ChatBloecke.eineZeile(w.aus)) }
                if offen.contains(w.id) {
                    zeilen.append(t("wort.ein") + "\n" + w.einVoll)
                    if !w.aus.isEmpty { zeilen.append(t("wort.aus") + "\n" + w.aus) }
                }
            case .freigabe(let f):
                zeilen.append(t("freigabe.frage", ["name": f.name]))
                if !f.beschreibung.isEmpty { zeilen.append(f.beschreibung) }
                zeilen.append(f.einVoll)
                if f.defekt { zeilen.append(t("freigabe.defekt")) }
                else if f.offen { zeilen.append(t("freigabe.erlauben") + " " + t("freigabe.ablehnen")) }
                else { zeilen.append(t("freigabe." + (f.entschieden.isEmpty ? "abgelehnt" : f.entschieden))) }
            }
        }
        zeilen.append(verlauf.kopf.modus.isEmpty ? "—" : verlauf.kopf.modus)
        zeilen.append(amEnde ? t("eingabe.hinweis") : t("eingabe.haengtNach"))
        zeilen.append(ChatStatusleiste.felder(verlauf.status, sprache: sprache).map(\.wert).joined(separator: " "))
        return zeilen.joined(separator: "\n")
    }

    /// Die Bloecke, wie sie gezeichnet sind, fuer `ui.chat.bloecke`.
    func bloeckeAuskunft() -> [[String: Any]] {
        verlauf.bloecke.map { b -> [String: Any] in
            switch b {
            case .text(let x):
                return ["art": x.art, "id": x.id, "rev": x.rev, "text": x.text, "offen": x.offen, "aufgeklappt": offen.contains(x.id)]
            case .werkzeug(let w):
                return ["art": "werkzeug", "id": w.id, "rev": w.rev, "name": w.name, "beschreibung": w.beschreibung, "ein": w.ein, "einVoll": w.einVoll,
                        "aus": w.aus, "ausKurz": ChatBloecke.eineZeile(w.aus), "fehler": w.fehler, "laeuft": w.laeuft, "aufgeklappt": offen.contains(w.id)]
            case .freigabe(let f):
                return ["art": "freigabe", "id": f.id, "rev": f.rev, "anfrageId": f.anfrageId, "name": f.name, "beschreibung": f.beschreibung,
                        "offen": f.offen, "entschieden": f.entschieden, "defekt": f.defekt,
                        "knoepfe": (f.offen && !f.defekt) ? [t("freigabe.erlauben"), t("freigabe.ablehnen")] : []]
            }
        }
    }

    func auskunft() -> [String: Any] {
        let k = verlauf.kopf
        var v: [String: Any] = ["offen": false]
        if let s = vervoll {
            v = ["offen": true, "art": s.art.rawValue, "kopfzeile": s.kopfzeile, "wahl": s.wahl,
                 "eintraege": s.eintraege.map { $0.ordner ? $0.wert + "/" : $0.wert }]
        }
        return [
            "gezeigt": chatId, "da": !chatId.isEmpty, "bereit": bereit, "staende": verlauf.staende,
            "zustand": verlauf.zustand, "zustandText": t("zustand." + verlauf.zustand), "laeuft": verlauf.laeuft, "neustartMoeglich": verlauf.neustartMoeglich,
            "kopf": ["sessionId": k.sessionId, "modell": k.modell, "ordner": k.ordner, "modus": k.modus, "arbeitet": k.arbeitet,
                     "wartetAufFreigabe": k.wartetAufFreigabe, "tokens": k.tokens, "kontext": k.kontext, "kosten": k.kosten,
                     "fehler": k.fehler, "initGesehen": k.initGesehen, "takt": k.takt, "modi": k.modi, "modusFehler": k.modusFehler],
            "bloecke": bloeckeAuskunft(),
            "befehle": verlauf.befehle.map(\.name),
            "worker": worker.map { ["name": $0.name, "pane": $0.paneId, "laeuft": $0.laeuft] },
            "eingabe": ["text": eingabe, "marke": marke, "platzhalter": t("eingabe.platzhalter"), "aktiv": verlauf.laeuft,
                        "hinweis": amEnde ? t("eingabe.hinweis") : t("eingabe.haengtNach"),
                        "modus": k.modus.isEmpty ? "—" : k.modus, "modusAktiv": verlauf.laeuft && !k.modi.isEmpty,
                        "halt": verlauf.haltMoeglich],
            "vervoll": v,
            "status": ChatStatusleiste.felder(verlauf.status, sprache: sprache).map { ["klasse": $0.klasse, "wert": $0.wert, "titel": $0.titel] },
            "zeiten": zeiten,
            "amEnde": amEnde,
            "meldung": letzteMeldung,
        ]
    }
}

// MARK: - Die Ansicht

struct ChatBuehne: View {
    let zustand: ChatZustand
    /// Fuer kopflose Bilder (Fenster.schuss): ohne ScrollView, Knoepfe und
    /// Textfeld, die AppKit-gestuetzt sind und im ImageRenderer nichts zeichnen
    /// (gemessen 06.09.) -- an ihrer Stelle stehen ihre Beschriftungen.
    var beleg = false

    var body: some View {
        VStack(spacing: 0) {
            ChatKopfzeile(zustand: zustand, beleg: beleg)
            if !zustand.worker.isEmpty {
                ChatWorkerleiste(zustand: zustand, beleg: beleg)
            }
            Divider()
            if beleg {
                // Der Beleg zeigt das ENDE des Verlaufs (wie die Ansicht, die
                // unten klebt): was nicht passt, faellt oben weg, nicht unten.
                // Als Overlay auf einer leeren Flaeche: so bringt der Verlauf seine
                // Eigenhoehe NICHT ins Layout (gemessen: sonst drueckte er Kopf
                // und Statusleiste aus dem Bild).
                Color.clear
                    .overlay(alignment: .bottomLeading) { verlauf.fixedSize(horizontal: false, vertical: true) }
                    .clipped()
            } else {
                ScrollViewReader { leser in
                    ScrollView {
                        verlauf
                        Color.clear.frame(height: 1).id("ende")
                    }
                    .onScrollGeometryChange(for: Bool.self) { g in
                        g.contentOffset.y + g.containerSize.height >= g.contentSize.height - 40
                    } action: { _, unten in
                        zustand.amEnde = unten
                    }
                    .onChange(of: zustand.verlauf.staende) { _, _ in
                        if zustand.amEnde { leser.scrollTo("ende", anchor: .bottom) }
                    }
                }
            }
            Divider()
            ChatEingabe(zustand: zustand, beleg: beleg)
            ChatStatusleiste(status: zustand.verlauf.status, sprache: zustand.sprache)
        }
        .background(.background)
        // DER KLICK AUF EINEN PFAD (Auftrag 3.6). Die Fundstellen tragen einen
        // Link mit eigenem Schema (`awbpfad:`, ChatPfadmarken); er wird hier
        // abgefangen und geht nie an das System. Jeder andere Link bleibt ein
        // Link -- Markdown macht ohnehin keinen daraus (ChatMarkdown), also
        // kommt hier nichts an, was nicht von uns stammt.
        .environment(\.openURL, OpenURLAction { url in
            guard let t = ChatPfadmarken.treffer(aus: url) else { return .systemAction }
            zustand.aufPfad?(t)
            return .handled
        })
        .accessibilityIdentifier("chatbuehne")
    }

    private var verlauf: some View {
        LazyVStack(alignment: .leading, spacing: 10) {
            if zustand.verlauf.bloecke.isEmpty {
                VStack(spacing: 4) {
                    Text(zustand.t("leer.titel")).font(.headline)
                    Text(zustand.t("leer.satz")).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 40)
            }
            ForEach(zustand.verlauf.bloecke) { b in
                ChatBlockAnsicht(block: b, zustand: zustand, beleg: beleg)
                    .id(b.id)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Der Kopf sagt, woran die Sitzung ist: Zustand, ein Fehler, das Angebot eines frischen Starts.
struct ChatKopfzeile: View {
    let zustand: ChatZustand
    var beleg = false

    var body: some View {
        let v = zustand.verlauf
        HStack(spacing: 10) {
            HStack(spacing: 5) {
                Zustandspunkt(art: punkt(v.zustand))
                Text(zustand.t("zustand." + v.zustand))
            }
            .font(.callout)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("chat-zustand")
            if !v.kopf.fehler.isEmpty {
                Label(zustand.t("zustand.fehler"), systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .font(.callout)
                    .help(v.kopf.fehler)
            }
            if v.neustartMoeglich && !v.laeuft {
                if beleg {
                    Text(zustand.t("knopf.neustart")).font(.callout).foregroundStyle(.tint)
                } else {
                    Button(zustand.t("knopf.neustart")) { zustand.neustart() }
                        .controlSize(.small)
                        .accessibilityIdentifier("chat-neustart")
                }
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
    }

    private func punkt(_ z: String) -> Punktart {
        switch z {
        case "arbeitet": return .laeuft
        case "freigabe": return .will
        case "beendet": return .aus
        default: return .ruhig
        }
    }
}

/// Die Worker der Werkstatt dieser Sitzung -- eine Leiste unter dem Kopf; ohne Worker ist sie WEG.
struct ChatWorkerleiste: View {
    let zustand: ChatZustand
    var beleg = false

    var body: some View {
        HStack(spacing: 8) {
            Text(zustand.t("worker.titel")).font(.caption).foregroundStyle(.secondary)
            ForEach(zustand.worker) { w in
                let inhalt = HStack(spacing: 5) {
                    Zustandspunkt(art: w.laeuft ? .laeuft : .ruhig)
                    Text(w.name).font(.callout)
                }
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(Capsule().fill(.quaternary.opacity(0.5)))
                if beleg {
                    inhalt
                } else {
                    Button { zustand.workerZeigen(w.paneId) } label: { inhalt }
                        .buttonStyle(.plain)
                        .help(zustand.t(w.laeuft ? "worker.wechseln" : "worker.beendet", ["name": w.name]))
                        .accessibilityLabel("Worker \(w.name), \(w.laeuft ? "läuft" : "beendet")")
                }
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 6)
    }
}

/// Die Statusleiste unter dem Gespraech: Modell, Ordner (und Zweig), Kontext, 5h, 7d, Kosten.
struct ChatStatusleiste: View {
    let status: ChatStatus
    let sprache: String

    struct Feld: Equatable {
        let klasse: String
        let wert: String
        let titel: String
        /// ruhig | will | aus -- die Farbstufe (statusline-command.sh).
        var stufe = "ruhig"
    }

    /// Die Felder, in der Reihenfolge der Zeile unter einer Terminal-Sitzung. Was
    /// unbekannt ist, steht nicht da.
    static func felder(_ s: ChatStatus, sprache: String) -> [Feld] {
        var f: [Feld] = []
        let t = { (k: String, w: [String: String]) in ChatTexte.t(sprache, k, w) }
        if !s.modell.isEmpty { f.append(Feld(klasse: "modell", wert: s.modell, titel: t("status.modell", [:]))) }
        if !s.ordner.isEmpty {
            var kurz = ModellNutzlast.Projekt.kurz(s.ordner)
            if !s.zweig.isEmpty { kurz += " " + s.zweig }
            f.append(Feld(klasse: "ordner", wert: kurz, titel: t("kopf.ordner", ["ordner": s.ordner])))
        }
        if let anteil = s.kontextAnteil {
            let prozent = (anteil * 100).rounded()
            f.append(Feld(klasse: "kontext", wert: "\(ChatStatus.kompakt(s.tokens))/\(ChatStatus.kompakt(s.fenster))",
                          titel: t("status.kontext", ["prozent": String(Int(prozent))]), stufe: ChatStatus.stufe(prozent)))
        } else if s.tokens > 0 {
            f.append(Feld(klasse: "kontext", wert: t("kopf.tokens", ["tokens": s.tokens.formatted()]), titel: t("status.kontext.ohneFenster", [:])))
        }
        if s.fuenfStunden >= 0 {
            f.append(Feld(klasse: "limit", wert: "5h \(Int(s.fuenfStunden.rounded()))%", titel: t("status.5h", ["reset": s.zurueck.isEmpty ? "" : " → " + s.zurueck]), stufe: ChatStatus.stufe(s.fuenfStunden)))
        }
        if s.siebenTage >= 0 {
            f.append(Feld(klasse: "limit", wert: "7d \(Int(s.siebenTage.rounded()))%", titel: t("status.7d", [:]), stufe: ChatStatus.stufe(s.siebenTage)))
        }
        if s.kosten >= 0 {
            f.append(Feld(klasse: "kosten", wert: t("kopf.kosten", ["kosten": String(format: "%.4f", s.kosten)]), titel: t("status.kosten", [:])))
        }
        return f
    }

    var body: some View {
        let felder = Self.felder(status, sprache: sprache)
        HStack(spacing: 6) {
            ForEach(Array(felder.enumerated()), id: \.offset) { i, f in
                if i > 0 { Text("·").foregroundStyle(.quaternary) }
                if f.klasse == "kontext", let anteil = status.kontextAnteil {
                    HStack(spacing: 4) {
                        Kontextbalken(anteil: anteil, stufe: f.stufe)
                        Text(f.wert)
                    }
                    .help(f.titel)
                } else {
                    Text(f.wert)
                        .foregroundStyle(farbe(f.stufe))
                        .help(f.titel)
                }
            }
            Spacer()
        }
        .font(.caption)
        .monospacedDigit()
        .lineLimit(1)
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
        .accessibilityIdentifier("chat-status")
        .accessibilityLabel(felder.map(\.wert).joined(separator: ", "))
    }

    private func farbe(_ stufe: String) -> Color {
        switch stufe {
        case "aus": return .red
        case "will": return .orange
        default: return .secondary
        }
    }
}

/// Der Balken der Kontextauslastung: eine Capsule-Form (kein ProgressView --
/// die zeichnet im ImageRenderer ein Sperrsymbol, gemessen 06.09., Statusfuss).
struct Kontextbalken: View {
    let anteil: Double
    let stufe: String

    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(.quaternary)
                Capsule().fill(farbe).frame(width: max(2, g.size.width * min(1, max(0, anteil))))
            }
        }
        .frame(width: 48, height: 6)
        .accessibilityHidden(true)
    }

    private var farbe: Color {
        switch stufe {
        case "aus": return .red
        case "will": return .orange
        default: return .accentColor
        }
    }
}
