// Ein Unix-Socket mit GCD -- Client und Server. Bewusst ohne Network.framework:
// das kennt Unix-Sockets nur ueber Umwege, und die Gegenseite (node:net) ist
// ein schlichter AF_UNIX-Strom.
import Foundation

enum UnixSocketFehler: Error, CustomStringConvertible {
    case anlegen(String)
    case verbinden(String, Int32)
    case lauschen(String, Int32)

    var description: String {
        switch self {
        case .anlegen(let s): return "Socket anlegen: \(s)"
        case .verbinden(let p, let e): return "Verbinden mit \(p): \(String(cString: strerror(e)))"
        case .lauschen(let p, let e): return "Lauschen auf \(p): \(String(cString: strerror(e)))"
        }
    }
}

enum UnixSocket {
    static func adresse(_ pfad: String) -> (sockaddr_un, socklen_t) {
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(pfad.utf8)
        withUnsafeMutableBytes(of: &addr.sun_path) { raw in
            let c = raw.baseAddress!.assumingMemoryBound(to: CChar.self)
            let platz = raw.count - 1
            for (i, b) in bytes.prefix(platz).enumerated() { c[i] = CChar(bitPattern: b) }
            c[min(bytes.count, platz)] = 0
        }
        let laenge = socklen_t(MemoryLayout<sa_family_t>.size + MemoryLayout<UInt8>.size + bytes.count + 1)
        return (addr, laenge)
    }

    /// Ein Unix-Socketpfad darf hoechstens 103 Bytes lang sein (sun_path, macOS).
    static func pfadPruefen(_ pfad: String) throws {
        if pfad.utf8.count > 103 {
            throw UnixSocketFehler.anlegen("Socketpfad laenger als 103 Bytes: \(pfad)")
        }
    }

    static func verbinden(_ pfad: String) throws -> Int32 {
        try pfadPruefen(pfad)
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw UnixSocketFehler.anlegen(String(cString: strerror(errno))) }
        var (addr, laenge) = adresse(pfad)
        let r = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, laenge) }
        }
        if r != 0 {
            let e = errno
            close(fd)
            throw UnixSocketFehler.verbinden(pfad, e)
        }
        var eins: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &eins, socklen_t(MemoryLayout<Int32>.size))
        return fd
    }

    static func lauschen(_ pfad: String) throws -> Int32 {
        try pfadPruefen(pfad)
        unlink(pfad)
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw UnixSocketFehler.anlegen(String(cString: strerror(errno))) }
        var (addr, laenge) = adresse(pfad)
        let r = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, laenge) }
        }
        if r != 0 || listen(fd, 8) != 0 {
            let e = errno
            close(fd)
            throw UnixSocketFehler.lauschen(pfad, e)
        }
        chmod(pfad, 0o600)
        return fd
    }

    /// Schreibt alles, notfalls in mehreren Zuegen. Ein Fehler beendet nur diesen Schreibvorgang.
    @discardableResult
    static func schreiben(_ fd: Int32, _ daten: Data) -> Bool {
        var rest = daten
        while !rest.isEmpty {
            let n = rest.withUnsafeBytes { p in Darwin.send(fd, p.baseAddress, p.count, MSG_NOSIGNAL) }
            if n <= 0 { return false }
            rest.removeFirst(n)
        }
        return true
    }

    /// Nimmt Verbindungen auf einer eigenen Warteschlange an. Steht hier und
    /// nicht in einer @MainActor-Klasse: ein Dispatch-Handler, der in einem
    /// Hauptakteur-Kontext entsteht, gilt als dorthin gebunden und trifft auf der
    /// Warteschlange auf die Isolationspruefung (gemessen 06.09.: SIGTRAP in
    /// dispatch_assert_queue beim ersten Client, auch mit @Sendable am Abschluss).
    static func annehmer(fd: Int32, queue: DispatchQueue,
                         neu: @escaping @Sendable (Int32) -> Void) -> DispatchSourceRead {
        let quelle = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
        quelle.setEventHandler {
            let client = accept(fd, nil, nil)
            if client >= 0 { neu(client) }
        }
        quelle.resume()
        return quelle
    }

    /// Ein Leser auf einer eigenen Warteschlange. `daten` bekommt jeden Block, `ende` das EOF.
    static func leser(fd: Int32, queue: DispatchQueue,
                      daten: @escaping @Sendable (Data) -> Void,
                      ende: @escaping @Sendable () -> Void) -> DispatchSourceRead {
        let quelle = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
        quelle.setEventHandler {
            var puffer = [UInt8](repeating: 0, count: 65536)
            let n = read(fd, &puffer, puffer.count)
            if n > 0 {
                daten(Data(puffer[0..<n]))
            } else {
                quelle.cancel()
            }
        }
        quelle.setCancelHandler {
            close(fd)
            ende()
        }
        quelle.resume()
        return quelle
    }
}
