# Client Stratum pour M1Miner

Ce module fournit une implémentation d'un client Stratum en Swift, conçu pour communiquer avec les pools de minage. Le code a été organisé en plusieurs dossiers et fichiers pour une meilleure maintenabilité et évolutivité.

## Structure du projet

```
StratumClientNIO/
├── Core/
│   ├── StratumClientCore.swift     # Logique principale du client
│   └── StratumClient+Handlers.swift  # Gestionnaires d'événements
├── Network/
│   └── NetworkManager.swift        # Gestion des connexions réseau
├── Models/
│   ├── StratumModels.swift         # Modèles de données
│   └── StratumError.swift          # Erreurs personnalisées
├── Protocols/
│   └── StratumProtocols.swift      # Protocoles et interfaces
└── Extensions/
    └── StratumClient+Extensions.swift  # Extensions utilitaires
```

### Core/
Contient la logique principale du client et les gestionnaires d'événements.

### Network/
Gère les connexions réseau et la communication avec le serveur.

### Models/
Définit les modèles de données et les erreurs personnalisées.

### Protocols/
Définit les protocoles et interfaces utilisés par le client.

### Extensions/
Contient des extensions utilitaires pour le client.

## Utilisation

### Initialisation

```swift
import M1MinerCore

// Créer une instance du client
let client = StratumClientNIO(
    host: "stratum.example.com",
    port: 3333,
    useTLS: false,
    workerName: "votre_worker",
    password: "x"
)
```

### Connexion

```swift
// Se connecter au serveur
client.connect { result in
    switch result {
    case .success:
        print("Connecté avec succès")
    case .failure(let error):
        print("Échec de la connexion: \(error)")
    }
}
```

### Configuration des callbacks

```swift
// Appelé lors de la réception d'un nouveau travail
client.onNewWork = { job in
    print("Nouveau travail reçu: \(job.jobId)")
    // Traiter le travail de minage ici
}

// Appelé en cas d'erreur
client.onError = { error in
    print("Erreur: \(error)")
}
```

### Soumission d'une solution

```swift
// Soumettre une solution
client.submitWork(
    jobId: "123",
    nonce: "a1b2c3d4",
    result: "00000000000000000000000000000000"
) { result in
    switch result {
    case .success(let accepted):
        print(accepted ? "Solution acceptée" : "Solution rejetée")
    case .failure(let error):
        print("Erreur lors de la soumission: \(error)")
    }
}
```

## Dépendances

- SwiftNIO : Pour les opérations réseau asynchrones
- Logging : Pour la journalisation

## Licence

Ce projet est sous licence MIT. Voir le fichier `LICENSE` pour plus de détails.
