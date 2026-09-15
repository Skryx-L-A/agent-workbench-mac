// swift-tools-version:6.2
// Die Mac-native Werkbank: ein Mantel aus SwiftUI und AppKit um den bestehenden
// Kern (app/, kopflos). Terminal-Panes zeichnet SwiftTerm.
import PackageDescription

let package = Package(
    name: "Werkbank",
    platforms: [.macOS(.v26)],
    products: [
        .executable(name: "Werkbank", targets: ["Werkbank"]),
        .executable(name: "awbmac-ctl", targets: ["awbmac-ctl"]),
        .library(name: "WerkbankProtokoll", targets: ["WerkbankProtokoll"]),
    ],
    dependencies: [
        // Festgenagelt: 1.20.0 ist der juengste Tag am 06.09.2026.
        .package(url: "https://github.com/migueldeicaza/SwiftTerm", exact: "1.20.0"),
        // Syntaxfaerbung des NSTextView-Editors (Auftrag 3.3): highlight.js in
        // JavaScriptCore. Festgenagelt: 2.3.0 ist der juengste Tag am 06.09.2026.
        .package(url: "https://github.com/raspu/Highlightr", exact: "2.3.0"),
    ],
    targets: [
        .target(name: "WerkbankProtokoll"),
        .executableTarget(
            name: "Werkbank",
            dependencies: [
                "WerkbankProtokoll",
                .product(name: "SwiftTerm", package: "SwiftTerm"),
                .product(name: "Highlightr", package: "Highlightr"),
            ]
        ),
        .executableTarget(name: "awbmac-ctl", dependencies: ["WerkbankProtokoll"]),
        // Der Figurenzeichner der Ansicht „Agents“ (Agentenfigur.swift) lebt im
        // App-Ziel; seine Bauplaene prueft diese Suite gegen die Werte des Blatts.
    ],
    swiftLanguageModes: [.v6]
)
