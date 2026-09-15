// Die Nachrichten des Mantel-Sockets (app/src/main/mantel.ts), aus Sicht des
// Mantels. Wortlaut und Richtung stehen in mac/PROTOKOLL.md.
//
//   Kern -> Mantel   {"ev":"awb:model", ...}            ein Ereignis (= webContents.send)
//   Kern -> Mantel   {"id":7,"ok":true,"value":...}     die Antwort auf ein invoke
//   Mantel -> Kern   {"cmd":"hallo","token":"..."}      der Handschlag, erste Zeile
//   Mantel -> Kern   {"cmd":"send","kanal":"awb:input","args":[...]}
//   Mantel -> Kern   {"id":7,"cmd":"invoke","kanal":"awb:ein-daten","args":[...]}
//
// Die Nutzlast eines Ereignisses bleibt als rohe JSON-Zeile erhalten und wird
// erst dort typisiert, wo sie gebraucht wird (Modell.swift): der Kern schickt
// 54 verschiedene Formen, und ein Mantel, der jede sofort in einen Typ
// zwingt, bricht beim ersten Feld, das er nicht kennt.
import Foundation

public enum KernNachricht: Sendable, Equatable {
    /// Ein Ereignis des Kerns: der Kanalname (`awb:...`) und die ganze Zeile.
    case ereignis(kanal: String, zeile: Data)
    /// Die Antwort auf ein `invoke` mit dieser Kennung.
    case antwort(id: Int, ok: Bool, zeile: Data)
    /// Der Handschlag wurde angenommen; `pid` ist der Kernprozess.
    case hallo(pid: Int)
    /// Eine Zeile, die keinem der drei entspricht (z. B. eine Fehlermeldung ohne Kennung).
    case unbekannt(zeile: Data)

    public static func lesen(_ zeile: Data) -> KernNachricht {
        guard let obj = try? JSONSerialization.jsonObject(with: zeile) as? [String: Any] else {
            return .unbekannt(zeile: zeile)
        }
        if let ev = obj["ev"] as? String {
            if ev == "hallo" {
                return .hallo(pid: obj["pid"] as? Int ?? 0)
            }
            return .ereignis(kanal: ev, zeile: zeile)
        }
        if let id = obj["id"] as? Int {
            return .antwort(id: id, ok: obj["ok"] as? Bool ?? false, zeile: zeile)
        }
        return .unbekannt(zeile: zeile)
    }
}

/// Eine Antwortzeile aufgeschluesselt: Wert oder Fehlertext.
public struct KernAntwort: Sendable {
    public let ok: Bool
    public let wertJSON: Data?
    public let fehler: String?

    public init(zeile: Data) {
        let obj = (try? JSONSerialization.jsonObject(with: zeile) as? [String: Any]) ?? [:]
        ok = obj["ok"] as? Bool ?? false
        fehler = obj["error"] as? String
        if let wert = obj["value"], JSONSerialization.isValidJSONObject([wert]) {
            wertJSON = try? JSONSerialization.data(withJSONObject: wert, options: [.fragmentsAllowed])
        } else {
            wertJSON = nil
        }
    }
}

/// Baut die Zeilen, die der Mantel an den Kern schickt -- mit Zeilenende.
public enum KernAnfrage {
    public static func hallo(token: String) -> Data {
        zeile(["cmd": "hallo", "token": token])
    }

    /// `ipcRenderer.send`: feuern und vergessen.
    public static func send(kanal: String, args: [Any]) -> Data {
        zeile(["cmd": "send", "kanal": kanal, "args": args])
    }

    /// `ipcRenderer.invoke`: eine Antwort mit derselben Kennung kommt zurueck.
    public static func invoke(id: Int, kanal: String, args: [Any]) -> Data {
        zeile(["id": id, "cmd": "invoke", "kanal": kanal, "args": args])
    }

    public static func ping(id: Int) -> Data {
        zeile(["id": id, "cmd": "ping"])
    }

    private static func zeile(_ obj: [String: Any]) -> Data {
        var d = (try? JSONSerialization.data(withJSONObject: obj)) ?? Data("{}".utf8)
        d.append(0x0A)
        return d
    }
}
