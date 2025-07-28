// swift-tools-version:5.5
import PackageDescription

let package = Package(
    name: "M1Miner",
    platforms: [
        .macOS(.v12)
    ],
    products: [
        .executable(
            name: "M1Miner",
            targets: ["M1Miner"]
        ),
        .library(
            name: "M1MinerCore",
            targets: ["M1MinerCore"]
        ),
        .library(
            name: "M1MinerShared",
            targets: ["M1MinerShared"]
        ),
        .library(
            name: "StratumClientNIO",
            targets: ["StratumClientNIO"]
        )
    ],
    dependencies: [
        // Dependencies pour le client Stratum avec SwiftNIO
        .package(url: "https://github.com/apple/swift-nio.git", from: "2.0.0"),
        .package(url: "https://github.com/apple/swift-nio-ssl.git", from: "2.0.0"),
        .package(url: "https://github.com/apple/swift-nio-http2.git", from: "1.0.0"),
        .package(url: "https://github.com/apple/swift-nio-extras.git", from: "1.0.0"),
        .package(url: "https://github.com/apple/swift-log.git", from: "1.0.0"),
        .package(url: "https://github.com/apple/swift-atomics.git", from: "1.0.0")
    ],
    targets: [
        // Cible pour les types partagés
        .target(
            name: "M1MinerShared",
            dependencies: [
                .product(name: "NIO", package: "swift-nio"),
                .product(name: "NIOConcurrencyHelpers", package: "swift-nio"),
                .product(name: "NIOSSL", package: "swift-nio-ssl"),
                .product(name: "Logging", package: "swift-log")
            ],
            path: "Sources/Shared"
        ),
        
        // Cible pour le client Stratum (dépréciée, utiliser StratumClientNIO à la place)
        .target(
            name: "StratumClient",
            dependencies: [
                "M1MinerShared",
                "M1MinerCore",
                .product(name: "NIO", package: "swift-nio"),
                .product(name: "NIOConcurrencyHelpers", package: "swift-nio"),
                .product(name: "NIOSSL", package: "swift-nio-ssl"),
                .product(name: "Logging", package: "swift-log")
            ],
            path: "Sources/StratumClient",
            exclude: ["StratumClientNIO.swift"]  // Exclure le fichier en double
        ),
        
        // Cible principale exécutable
        .executableTarget(
            name: "M1Miner",
            dependencies: [
                "M1MinerCore",
                "M1MinerShared",
                "StratumClient",
                .product(name: "NIO", package: "swift-nio"),
                .product(name: "NIOSSL", package: "swift-nio-ssl"),
                .product(name: "NIOExtras", package: "swift-nio-extras")
            ],
            path: "Sources/M1Miner"
        ),
        
        // Cible pour le client Stratum NIO avec gestion réseau intégrée
        .target(
            name: "StratumClientNIO",
            dependencies: [
                "M1MinerShared",
                "NetworkManager",
                .product(name: "NIO", package: "swift-nio"),
                .product(name: "NIOConcurrencyHelpers", package: "swift-nio"),
                .product(name: "NIOSSL", package: "swift-nio-ssl"),
                .product(name: "NIOExtras", package: "swift-nio-extras"),
                .product(name: "Logging", package: "swift-log"),
                .product(name: "Atomics", package: "swift-atomics")
            ],
            path: "Sources/StratumClientNIO"
        ),
        
        // Cible pour la gestion réseau partagée
        .target(
            name: "NetworkManager",
            dependencies: [
                "M1MinerShared",
                .product(name: "NIO", package: "swift-nio"),
                .product(name: "NIOSSL", package: "swift-nio-ssl"),
                .product(name: "NIOConcurrencyHelpers", package: "swift-nio"),
                .product(name: "Logging", package: "swift-log"),
                .product(name: "Atomics", package: "swift-atomics")
            ],
            path: "Sources/M1MinerCore/Network"
        ),
        
        // Cible principale de la bibliothèque
        .target(
            name: "M1MinerCore",
            dependencies: [
                "M1MinerShared",
                "StratumClientNIO",
                // StratumClientNIO a été retiré pour éviter la dépendance cyclique
                // "StratumClientNIO",
                "NetworkManager",
                .product(name: "NIO", package: "swift-nio"),
                .product(name: "NIOConcurrencyHelpers", package: "swift-nio"),
                .product(name: "NIOSSL", package: "swift-nio-ssl"),
                .product(name: "NIOHTTP2", package: "swift-nio-http2"),
                .product(name: "NIOExtras", package: "swift-nio-extras"),
                .product(name: "Logging", package: "swift-log"),
                .product(name: "Atomics", package: "swift-atomics")
            ],
            path: "Sources/M1MinerCore",
            exclude: [
                "Documentation.docc",
                "Stratum",       // Exclure tout le dossier Stratum (géré par la cible StratumClientNIO)
                "Network"        // Exclure tout le dossier Network (géré par la cible NetworkManager)
            ],
            resources: [
                .process("../Resources/Shaders")
            ]
        ),
        
        // Cible de test
        .testTarget(
            name: "M1MinerTests",
            dependencies: [
                "M1MinerCore",
                "M1MinerShared",
                .product(name: "NIO", package: "swift-nio"),
                .product(name: "NIOSSL", package: "swift-nio-ssl"),
                .product(name: "NIOExtras", package: "swift-nio-extras")
            ],
            path: "Tests/M1MinerTests"
        )
    ]
)
