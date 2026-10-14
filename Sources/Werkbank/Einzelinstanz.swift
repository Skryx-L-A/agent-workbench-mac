// EINE WERKBANK JE LAUFVERZEICHNIS (11.10.2026, Auftrag einzelinstanz).
//
// Ein zweiter Start ohne Mantel-Umgebung (Doppelklick nach `open -n`, der saubere Neustart aus
// einer Agenten-Umgebung in main.swift, ein direkter Aufruf des Programms) lief bisher ganz durch
// `Kernstart.starten`: kern.log geleert, kern.pid und mantel.token neu geschrieben, und
// `UnixSocket.lauschen` raeumte awbmac.sock ab und band ihn neu -- die erste App war danach ueber
// ihren Steuerkanal nicht mehr zu erreichen (gemessen in app-absturz-peek und kern-steuerkanal).
// Beim Beenden loeschte die zweite dann auch noch mantel.sock, kern.pid und mantel.token der ersten.
//
// Deshalb haelt jede Werkbank fuer ihr Laufverzeichnis eine Sperre (`instanz.lock`, flock). Wer
// sie nicht bekommt, ist der zweite Start: er bittet die erste ueber ihren Steuerkanal, nach vorn
// zu kommen (`vorholen`), und endet mit Exit 0, bevor er irgendetwas anlegt.
//
// WARUM DIE SPERRE AM LAUFVERZEICHNIS HAENGT und nicht an der Bundle-ID: eine Pruefung mit eigenem
// HOME hat ihr eigenes Laufverzeichnis, findet also nur sich selbst und nie App des Nutzers.
//
// TOTE VORGAENGERIN: flock gehoert dem offenen Dateideskriptor; stirbt der Prozess (auch per
// SIGKILL), gibt der Kernel die Sperre frei. Liegen Sperrdatei und awbmac.sock noch da, bekommt
// der naechste Start die Sperre trotzdem und uebernimmt wie bisher (der alte Kern geht ueber seine
// Elternwache, der neue wartet auf den Mantel-Socket -- app/src/main/main.ts).
import AppKit

@MainActor
enum Einzelinstanz {
    /// Wer die Sperre haelt, wie sie in `instanz.lock` steht.
    struct Inhaber: Equatable, Sendable {
        var pid: pid_t
        var steuerSocket: String
        var pruefung: Bool
    }

    enum Ergebnis: Equatable, Sendable {
        /// Diese App haelt die Sperre (bis zum Prozessende).
        case eigen
        /// Eine andere Werkbank haelt sie.
        case belegt(Inhaber)
        /// Sperre nicht pruefbar (Laufverzeichnis nicht anlegbar o. ae.); die App startet wie bisher.
        case unbekannt(String)
    }

    /// Bleibt offen, solange die App laeuft. O_CLOEXEC: weder Kern noch tmux erben die Sperre --
    /// sonst hielte ein verwaister Kern sie ueber den Tod seiner App hinaus.
    private static var sperrFd: Int32 = -1

    /// Wie oft die erste Werkbank von einem zweiten Start nach vorn gebeten wurde (`ui.fenster.vorgeholt`).
    static var vorgeholt = 0

    /// Derselbe Ordner, den `Kernstart.starten` und `mac/bin/starten` waehlen.
    static func laufdir(env: [String: String] = ProcessInfo.processInfo.environment) -> String {
        if let l = env["AWBMAC_LAUFDIR"], !l.isEmpty { return l }
        return "\(env["HOME"] ?? NSHomeDirectory())/.config/agent-workbench/mac-lauf"
    }

    /// Der Steuerkanal, den diese App binden wird (Kernstart: AWBMAC_CONTROL_SOCKET, sonst im Laufverzeichnis).
    static func steuerSocket(_ optionen: Laufoptionen, laufdir: String) -> String {
        optionen.steuerSocket.isEmpty ? "\(laufdir)/awbmac.sock" : optionen.steuerSocket
    }

    /**
     Die Sperre nehmen. Nur die Sperrdatei wird angelegt (und das Laufverzeichnis, das `Kernstart`
     ohnehin anlegt); bei `.belegt` wird nichts geschrieben.
     */
    static func sperren(laufdir: String, steuerSocket: String, pruefung: Bool) -> Ergebnis {
        do {
            try FileManager.default.createDirectory(atPath: laufdir, withIntermediateDirectories: true)
        } catch {
            return .unbekannt("Laufverzeichnis \(laufdir) nicht anlegbar: \(error.localizedDescription)")
        }
        let pfad = "\(laufdir)/instanz.lock"
        let fd = open(pfad, O_RDWR | O_CREAT | O_CLOEXEC, 0o600)
        guard fd >= 0 else { return .unbekannt("\(pfad): \(String(cString: strerror(errno)))") }
        if flock(fd, LOCK_EX | LOCK_NB) == 0 {
            let inhalt = "\(getpid())\n\(steuerSocket)\n\(pruefung ? "pruefung" : "mensch")\n"
            ftruncate(fd, 0)
            _ = inhalt.withCString { pwrite(fd, $0, strlen($0), 0) }
            sperrFd = fd
            return .eigen
        }
        let e = errno
        guard e == EWOULDBLOCK else {
            close(fd)
            return .unbekannt("flock \(pfad): \(String(cString: strerror(e)))")
        }
        // Die Inhaberin schreibt ihre Zeilen direkt nach dem flock; kommt dieser Start genau
        // dazwischen, steht noch nichts darin. Zwei Sekunden reichen dafuer lange.
        let bis = Date().addingTimeInterval(2)
        repeat {
            if let i = lesen(fd) { close(fd); return .belegt(i) }
            usleep(50_000)
        } while Date() < bis
        close(fd)
        return .unbekannt("\(pfad) ist gesperrt, nennt aber keine Inhaberin")
    }

    private static func lesen(_ fd: Int32) -> Inhaber? {
        var puffer = [UInt8](repeating: 0, count: 1024)
        let n = pread(fd, &puffer, puffer.count, 0)
        guard n > 0 else { return nil }
        let zeilen = String(decoding: puffer[0..<n], as: UTF8.self).split(separator: "\n").map(String.init)
        guard zeilen.count >= 3, let pid = pid_t(zeilen[0]), pid > 0 else { return nil }
        return Inhaber(pid: pid, steuerSocket: zeilen[1], pruefung: zeilen[2] == "pruefung")
    }

    /**
     Die erste Werkbank nach vorn bitten. Ueber ihren Steuerkanal (`vorholen`): sie kennt ihre
     eigene Lage und entscheidet selbst, ob sie den Fokus nehmen darf. Ist keine von beiden eine
     Pruefung, gibt dieser Start die Aktivierung zusaetzlich an sie ab -- macOS 14 und spaeter
     aktiviert eine App im Hintergrund nur, wenn die aktive sie ihr ueberlaesst. Gibt die Antwort
     des Steuerkanals zurueck (leer, wenn keine kam).
     */
    static func vorholen(_ i: Inhaber, pruefung: Bool) -> String {
        if !pruefung, !i.pruefung, let andere = NSRunningApplication(processIdentifier: i.pid) {
            NSApplication.shared.yieldActivation(to: andere)
            andere.activate(from: NSRunningApplication.current, options: [.activateAllWindows])
        }
        guard let fd = try? UnixSocket.verbinden(i.steuerSocket) else { return "" }
        defer { close(fd) }
        var tv = timeval(tv_sec: 3, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
        guard UnixSocket.schreiben(fd, Data("{\"cmd\":\"vorholen\"}\n".utf8)) else { return "" }
        var puffer = [UInt8](repeating: 0, count: 4096)
        var antwort = Data()
        while !antwort.contains(UInt8(ascii: "\n")) {
            let n = read(fd, &puffer, puffer.count)
            guard n > 0 else { break }
            antwort.append(contentsOf: puffer[0..<n])
        }
        return String(decoding: antwort, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /**
     Eine Werkbank ohne Sperre am Steuerkanal: eine aeltere Fassung, die `instanz.lock` noch nicht
     kennt (der Weg einer Aktualisierung, solange die alte App laeuft). Gibt ihre PID zurueck, wenn
     dort binnen zwei Sekunden eine ANDERE App auf `ping` antwortet; eine liegengebliebene
     Socketdatei ohne Zuhoerer ergibt nil.
     */
    static func aeltereAmSteuerkanal(_ pfad: String) -> pid_t? {
        guard FileManager.default.fileExists(atPath: pfad), let fd = try? UnixSocket.verbinden(pfad) else { return nil }
        defer { close(fd) }
        var tv = timeval(tv_sec: 2, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
        guard UnixSocket.schreiben(fd, Data("{\"cmd\":\"ping\"}\n".utf8)) else { return nil }
        var puffer = [UInt8](repeating: 0, count: 4096)
        var antwort = Data()
        while !antwort.contains(UInt8(ascii: "\n")) {
            let n = read(fd, &puffer, puffer.count)
            guard n > 0 else { return nil }
            antwort.append(contentsOf: puffer[0..<n])
        }
        let zeile = antwort.prefix(while: { $0 != UInt8(ascii: "\n") })
        guard let d = try? JSONSerialization.jsonObject(with: zeile) as? [String: Any], let pid = d["pid"] as? Int,
              pid != Int(getpid()) else { return nil }
        return pid_t(pid)
    }

    /// Die Seite der ersten Werkbank: ein zweiter Start bittet sie nach vorn. Eine Pruefung zaehlt
    /// nur mit und laesst ihre Fenster, wo sie sind -- nie in den Fokus des Menschen.
    static func vorgeholtWerden(_ fenster: NSWindow, optionen: Laufoptionen) -> [String: Any] {
        vorgeholt += 1
        if !optionen.pruefmodus {
            if fenster.isMiniaturized { fenster.deminiaturize(nil) }
            fenster.vorZeigen(ohneFokus: false)
        }
        return ["vorgeholt": vorgeholt, "pruefung": optionen.pruefmodus, "pid": Int(getpid())]
    }
}
