// Das Eingabefeld der Chat-Buehne (Auftrag 3.2): ein umrandeter Kasten mit
// dem Feld, darueber die Vervollstaendigungsliste (sie haengt UEBER dem Feld,
// weil unter ihm der Rand des Fensters kommt), rechts unten Modus-Marke,
// Halt und Senden; darunter der Hinweis.
//
// DAS FELD IST EIN NSTextView (NSViewRepresentable), nicht TextField/TextEditor:
// nur so gehoeren Eingabe, Umschalt+Eingabe, Pfeiltasten, Tabulator und Escape
// dem Feld, in DER Reihenfolge, die der Renderer hat (ansicht.ts, keydown):
// erst die Liste (Umschalt+Eingabe gehoert bei offener Liste dem FELD, Befund
// 9), dann Escape (unterbricht nur, wenn etwas laeuft), dann Eingabe sendet.
// Die Entscheidung faellt in `ChatZustand.taste` -- dieselbe Funktion, die der
// Steuerkanal kopflos ruft (`awbmac-ctl chat-taste`); das Feld reicht nur
// durch, was AppKit ihm als Befehl meldet (`doCommandBy`).
//
// Das Feld waechst mit dem Text bis zu einer Grenze, danach rollt es -- wie
// `hoeheAnpassen` im Renderer (220 px). Kopflos ist das Feld nie erster
// Responder; der Zustand traegt Text und Marke, die Steuerbefehle setzen sie.
import AppKit
import SwiftUI
import WerkbankProtokoll

struct ChatEingabe: View {
    let zustand: ChatZustand
    var beleg = false

    var body: some View {
        let v = zustand.verlauf
        VStack(alignment: .leading, spacing: 4) {
            VStack(spacing: 0) {
                if let liste = zustand.vervoll {
                    Vervollliste(liste: liste, beleg: beleg) { zustand.einsetzen($0) }
                    Divider()
                }
                HStack(alignment: .bottom, spacing: 6) {
                    if beleg {
                        Text(zustand.eingabe.isEmpty ? zustand.t("eingabe.platzhalter") : zustand.eingabe)
                            .foregroundStyle(zustand.eingabe.isEmpty ? Color.secondary : Color.primary)
                            .frame(maxWidth: .infinity, minHeight: 22, alignment: .leading)
                            .padding(.vertical, 4)
                    } else {
                        Eingabefeld(zustand: zustand)
                            .frame(height: max(22, min(220, zustand.feldHoehe)))
                            .accessibilityIdentifier("chat-feld")
                    }
                    Modusmarke(zustand: zustand, beleg: beleg)
                    if v.haltMoeglich {
                        if beleg {
                            Image(systemName: "stop.fill").foregroundStyle(.red)
                        } else {
                            Button { zustand.halt() } label: { Image(systemName: "stop.fill") }
                                .buttonStyle(.borderless)
                                .foregroundStyle(.red)
                                .help(zustand.t("knopf.halt"))
                                .accessibilityLabel(zustand.t("knopf.halt"))
                                .accessibilityIdentifier("chat-halt")
                        }
                    }
                    if beleg {
                        Image(systemName: "arrow.up.circle.fill").foregroundStyle(.tint)
                    } else {
                        Button { zustand.abschicken() } label: { Image(systemName: "arrow.up.circle.fill").font(.title3) }
                            .buttonStyle(.borderless)
                            .disabled(!v.laeuft)
                            .help(zustand.t("eingabe.senden"))
                            .accessibilityLabel(zustand.t("eingabe.senden"))
                            .accessibilityIdentifier("chat-senden")
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
            }
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color(nsColor: .controlBackgroundColor)))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Color(nsColor: .separatorColor)))
            Text(zustand.amEnde ? zustand.t("eingabe.hinweis") : zustand.t("eingabe.haengtNach"))
                .font(.caption)
                .foregroundStyle(zustand.amEnde ? Color.secondary : Color.orange)
                .lineLimit(1)
                .accessibilityIdentifier("chat-hinweis")
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }
}

/// Die Modus-Marke ist ein KNOPF: ein Klick, ein Schritt in der Modusliste des
/// Harness; was danach dasteht, kommt von ihm, nicht vom Wunsch.
struct Modusmarke: View {
    let zustand: ChatZustand
    var beleg = false

    var body: some View {
        let v = zustand.verlauf
        let modus = v.kopf.modus.isEmpty ? "—" : v.kopf.modus
        let fehler = !v.kopf.modusFehler.isEmpty
        let hilfe = fehler ? zustand.t("modus.abgelehnt", ["grund": v.kopf.modusFehler]) : zustand.t("modus.wechseln", ["modus": modus])
        let inhalt = Text(modus)
            .font(.caption)
            .monospaced()
            .foregroundStyle(fehler ? Color.red : Color.secondary)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(Capsule().fill(.quaternary.opacity(0.5)))
        if beleg {
            inhalt
        } else {
            Button { zustand.modusWeiter() } label: { inhalt }
                .buttonStyle(.plain)
                .disabled(!v.laeuft || v.kopf.modi.isEmpty)
                .help(hilfe)
                .accessibilityLabel("Freigabemodus \(modus)")
                .accessibilityHint(hilfe)
                .accessibilityIdentifier("chat-modus")
        }
    }
}

/// Die Liste ueber dem Feld: Kopfzeile, Eintraege, der gewaehlte hervorgehoben.
struct Vervollliste: View {
    let liste: VervollStand
    var beleg = false
    let wahl: (Vorschlag) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(liste.kopfzeile).font(.caption).foregroundStyle(.secondary).padding(.horizontal, 10).padding(.vertical, 4)
            ForEach(Array(liste.eintraege.enumerated()), id: \.offset) { i, e in
                let zeile = HStack(spacing: 8) {
                    Text(e.ordner ? e.wert + "/" : e.wert).font(.body.monospaced()).lineLimit(1)
                    if !e.satz.isEmpty { Text(e.satz).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
                    Spacer()
                }
                .padding(.horizontal, 10).padding(.vertical, 3)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(i == liste.wahl ? Color.accentColor.opacity(0.2) : Color.clear)
                if beleg {
                    zeile
                } else {
                    Button { wahl(e) } label: { zeile }
                        .buttonStyle(.plain)
                        .accessibilityLabel(e.wert)
                        .accessibilityAddTraits(i == liste.wahl ? .isSelected : [])
                }
            }
        }
        .padding(.vertical, 2)
        .accessibilityIdentifier("chat-vervoll")
    }
}

/// Das Feld selbst: NSTextView, Text und Marke im Zustand, Tasten ueber `ChatZustand.taste`.
struct Eingabefeld: NSViewRepresentable {
    let zustand: ChatZustand

    @MainActor
    final class Koordinator: NSObject, NSTextViewDelegate {
        let zustand: ChatZustand
        weak var textView: NSTextView?
        var imUpdate = false
        var gesehenerFokusWunsch = 0
        init(zustand: ChatZustand) { self.zustand = zustand }

        func textDidChange(_ notification: Notification) {
            guard !imUpdate, let tv = textView else { return }
            zustand.eingabe = tv.string
            zustand.marke = tv.selectedRange().location
            hoeheMessen(tv)
            zustand.vervollstaendigen()
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard !imUpdate, let tv = textView else { return }
            let m = tv.selectedRange().location
            if m != zustand.marke {
                zustand.marke = m
                // Die Marke wandert mit dem Schreibstrich: ein Klick mitten in
                // den Text beendet einen Vorschlag, der zu einer anderen Stelle gehoerte.
                if zustand.vervoll != nil { zustand.vervollstaendigen() }
            }
        }

        func textView(_ textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            let umschalt = NSApp.currentEvent?.modifierFlags.contains(.shift) ?? false
            switch selector {
            case #selector(NSResponder.insertNewline(_:)):
                if zustand.taste("Enter", umschalt: umschalt) { return true }
                // Umschalt+Eingabe: eine neue Zeile, wie im Renderer.
                textView.insertNewlineIgnoringFieldEditor(nil)
                return true
            case #selector(NSResponder.moveDown(_:)):
                return zustand.taste("ArrowDown")
            case #selector(NSResponder.moveUp(_:)):
                return zustand.taste("ArrowUp")
            case #selector(NSResponder.insertTab(_:)):
                return zustand.taste("Tab")
            case #selector(NSResponder.cancelOperation(_:)):
                return zustand.taste("Escape")
            default:
                return false
            }
        }

        func hoeheMessen(_ tv: NSTextView) {
            guard let lm = tv.layoutManager, let tc = tv.textContainer else { return }
            lm.ensureLayout(for: tc)
            let h = lm.usedRect(for: tc).height + tv.textContainerInset.height * 2
            let neu = max(22, min(220, h.rounded(.up)))
            if zustand.feldHoehe != neu { zustand.feldHoehe = neu }
        }
    }

    func makeCoordinator() -> Koordinator { Koordinator(zustand: zustand) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.drawsBackground = false
        scroll.borderType = .noBorder
        let tv = NSTextView()
        tv.delegate = context.coordinator
        tv.isRichText = false
        tv.allowsUndo = true
        tv.isAutomaticQuoteSubstitutionEnabled = false
        tv.isAutomaticDashSubstitutionEnabled = false
        tv.isAutomaticTextReplacementEnabled = false
        tv.isContinuousSpellCheckingEnabled = false
        tv.drawsBackground = false
        tv.font = NSFont.preferredFont(forTextStyle: .body)
        tv.textContainerInset = NSSize(width: 0, height: 4)
        tv.isVerticallyResizable = true
        tv.isHorizontallyResizable = false
        tv.autoresizingMask = [.width]
        tv.textContainer?.widthTracksTextView = true
        tv.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        tv.setAccessibilityLabel("Nachricht an Claude")
        scroll.documentView = tv
        context.coordinator.textView = tv
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let tv = scroll.documentView as? NSTextView else { return }
        let k = context.coordinator
        if tv.string != zustand.eingabe {
            k.imUpdate = true
            tv.string = zustand.eingabe
            let m = min(zustand.marke, (zustand.eingabe as NSString).length)
            tv.setSelectedRange(NSRange(location: m, length: 0))
            k.imUpdate = false
            k.hoeheMessen(tv)
        } else if tv.selectedRange().location != zustand.marke, tv.window?.firstResponder !== tv {
            k.imUpdate = true
            tv.setSelectedRange(NSRange(location: min(zustand.marke, (zustand.eingabe as NSString).length), length: 0))
            k.imUpdate = false
        }
        tv.isEditable = zustand.verlauf.laeuft
        tv.textColor = zustand.verlauf.laeuft ? .labelColor : .secondaryLabelColor
        if zustand.fokusWunsch != k.gesehenerFokusWunsch {
            k.gesehenerFokusWunsch = zustand.fokusWunsch
            // Nur in einem Fenster auf dem Bildschirm: kopflos gibt es keine Tastatur.
            if let w = tv.window, w.isVisible { w.makeFirstResponder(tv) }
        }
    }
}
