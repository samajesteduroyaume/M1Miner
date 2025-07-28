# M1MinerCore

Un client Stratum haute performance pour le minage de cryptomonnaies, implémenté en Swift avec SwiftNIO.

## Aperçu

M1MinerCore est une bibliothèque complète pour se connecter aux pools de minage utilisant le protocole Stratum. Elle est conçue pour être performante, fiable et facile à utiliser, avec une attention particulière portée à la sécurité et à la robustesse.

## Fonctionnalités clés

- **Connexion sécurisée** : Support de TLS pour des communications chiffrées
- **Haute performance** : Utilisation de SwiftNIO pour une gestion efficace des E/S asynchrones
- **Gestion des erreurs** : Système complet de gestion et de récupération des erreurs
- **Sécurité renforcée** : Protection contre les attaques par rejeu et validation stricte des entrées
- **Gestion de session** : Reconnexion automatique et gestion de l'état de la connexion
- **Métriques** : Suivi des performances et de l'utilisation du réseau

## Architecture

Le module est organisé en plusieurs composants principaux :

1. **StratumClientNIO** : Le point d'entrée principal pour interagir avec un pool de minage
2. **NetworkManager** : Gère les connexions réseau et la communication bas niveau
3. **Sécurité** : Composants pour la protection des données sensibles et la prévention des attaques
4. **Validation** : Outils pour valider et assainir les entrées utilisateur

## Prérequis

- iOS 13.0+ / macOS 10.15+ / tvOS 13.0+ / watchOS 6.0+
- Xcode 13.0+
- Swift 5.5+

## Installation

### Swift Package Manager

Ajoutez M1MinerCore comme dépendance dans votre `Package.swift` :

```swift
dependencies: [
    .package(url: "https://github.com/votre-utilisateur/M1MinerCore.git", from: "1.0.0")
]
```

### CocoaPods

Ajoutez la ligne suivante à votre Podfile :

```ruby
pod 'M1MinerCore', '~> 1.0.0'
```

## Utilisation de base

```swift
import M1MinerCore

// Configuration du client
let config = StratumClientConfiguration(
    connectionTimeout: 10.0,
    requestTimeout: 30.0,
    reconnectDelay: 5.0,
    maxReconnectAttempts: 5,
    keepAliveInterval: 60.0,
    jobValidityDuration: 300.0,
    enableAutoReconnect: true
)

// Création d'une instance du client
let client = StratumClientNIO(
    host: "stratum.example.com",
    port: 3333,
    useTLS: true,
    workerName: "votre.worker",
    password: "x",
    configuration: config
)

// Connexion au pool
Task {
    do {
        try await client.connect()
        print("Connecté au pool de minage")
    } catch {
        print("Échec de la connexion : \(error)")
    }
}

// Gestion des nouveaux travaux de minage
client.delegate = YourDelegate()

// Soumission d'une solution
Task {
    do {
        let result = try await client.submit(
            jobId: "job123",
            extranonce2: "12345678",
            ntime: "5a0e1b2c",
            nonce: "deadbeef"
        )
        
        if result.accepted {
            print("Solution acceptée !")
        } else {
            print("Solution rejetée : \(result.message ?? "Raison inconnue")")
        }
    } catch {
        print("Erreur lors de la soumission : \(error)")
    }
}
```

## Gestion des erreurs

Le module définit plusieurs types d'erreurs personnalisées dans `StratumClientError` et `NetworkError`. Toutes les méthodes qui peuvent échouer lancent des erreurs qui doivent être attrapées et gérées de manière appropriée.

## Journalisation

Le module utilise le système de journalisation unifié d'Apple (`os.log`). Vous pouvez contrôler le niveau de journalisation en configurant le `Logger` avant d'initialiser le client.

```swift
import Logging

// Configurer le niveau de journalisation
LoggingSystem.bootstrap { _ in
    var handler = StreamLogHandler.standardOutput(label: $0)
    handler.logLevel = .debug
    return handler
}
```

## Sécurité

### Stockage sécurisé

Les informations d'identification sensibles sont stockées dans le trousseau de l'appareil à l'aide de `SecureStorage` :

```swift
do {
    // Stocker les identifiants de manière sécurisée
    try SecureStorage.storeCredentials(workerName: "votre.worker", password: "votre-mot-de-passe")
    
    // Récupérer les identifiants
    if let credentials = try SecureStorage.retrieveCredentials() {
        print("Worker: \(credentials.workerName)")
    }
    
    // Supprimer les identifiants
    try SecureStorage.deleteCredentials()
} catch {
    print("Erreur de stockage sécurisé : \(error)")
}
```

### Protection contre les attaques par rejeu

Le module inclut une protection intégrée contre les attaques par rejeu via la classe `ReplayProtection`. Cette fonctionnalité est activée par défaut dans `StratumClientNIO`.

## Bonnes pratiques

1. **Gestion du cycle de vie** : Assurez-vous de libérer correctement les ressources en appelant `disconnect()` lorsque vous avez terminé avec le client.
2. **Gestion des erreurs** : Toujours implémenter une gestion des erreurs appropriée pour les opérations réseau.
3. **Mises à jour de l'interface utilisateur** : Effectuez les mises à jour de l'interface utilisateur sur le thread principal.
4. **Tests** : Testez votre implémentation avec différents scénarios de réseau et d'erreur.

## Licence

M1MinerCore est disponible sous la licence MIT. Voir le fichier LICENSE pour plus d'informations.

## Contribution

Les contributions sont les bienvenues ! N'hésitez pas à soumettre des problèmes et des demandes d'extraction.

---

*Documentation générée automatiquement le 26/07/2025*
