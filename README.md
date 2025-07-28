# M1Miner

M1Miner est un logiciel de minage multi-algorithmes optimisé pour les plateformes Apple Silicon (M1/M2), écrit en Swift. Il supporte le protocole Stratum, la gestion avancée des pools, et plusieurs stratégies de minage.

## Fonctionnalités principales
- Connexion à des pools Stratum (ex : 2miners, zpool, etc.)
- Support natif Metal (GPU Apple M1/M2)
- Gestion multi-thread CPU
- Configuration avancée via `config.json`
- Adapté à de nombreux algorithmes (Equihash 144,5, etc.)
- Gestion dynamique de la difficulté et des jobs
- Logs détaillés et gestion des erreurs
- Extensible pour d’autres stratégies de minage

## Structure du projet
```
M1Miner/
├── Package.swift           # Dépendances SwiftPM
├── config.json            # Configuration utilisateur
├── Sources/
│   ├── M1Miner/           # Point d’entrée CLI
│   ├── M1MinerCore/       # Logique principale du mineur
│   ├── StratumClientNIO/  # Client Stratum NIO (réseau, jobs, parsing)
│   ├── Shared/            # Types partagés
│   └── Resources/         # Shaders Metal, assets
├── Tests/                 # Tests unitaires et d’intégration
```

## Configuration
Copiez `config.example.json` en `config.json` et adaptez les paramètres :
```json
{
  "poolUrl": "stratum+tcp://equihash144.eu.mine.zpool.ca:2144",
  "walletAddress": "VotreWallet.m1miner",
  "workerName": "m1miner",
  "password": "c=BTG,zap=BTG",
  "algorithm": "btg",
  "threads": 8,
  "retryPause": 5,
  "intensity": 20,
  "donateLevel": 1,
  "autoStart": true,
  "logLevel": "info",
  "advanced": {
    "maxTemp": 80,
    "fanSpeed": "auto",
    "powerLimit": 85,
    "threads": 0,
    "worksize": 8,
    "affinity": 0,
    "noStrictSSL": false,
    "retryPause": 5,
    "donateLevel": 1
  }
}
```
- **poolUrl** : Adresse du pool Stratum
- **walletAddress** : Adresse de paiement (format `<wallet>.<worker>` pour zpool)
- **password** : Paramètres pool (ex : `c=BTG,zap=BTG`)
- **algorithm** : Algorithme à miner

## Lancement
Dans le dossier du projet :
```sh
swift run
```

## Architecture logicielle
- **MiningManager.swift** : Orchestration du minage, gestion du client Stratum (propriété privée `__stratumClient: StratumClientNIO?`)
- **StratumClientNIO** : Gestion du protocole Stratum, parsing multi-messages, notifications, jobs, soumission de shares
- **Shaders Metal** : Calculs GPU pour les algorithmes compatibles
- **Tests** : Vérification de la compatibilité multi-pool, parsing, calculs

## Compatibilité pools
- 2miners (Equihash, etc.)
- zpool (Equihash, jobs multi-paramètres)
- Toute pool Stratum standard (adaptation automatique du parsing)

## Personnalisation et extensions
- Ajoutez vos propres stratégies dans `M1MinerCore`
- Ajoutez de nouveaux algorithmes GPU dans `Resources/Shaders`
- Adaptez la gestion des jobs dans `StratumClientNIO/Core/StratumClient+Handlers.swift`

## Dépendances
- Swift NIO
- Logging
- MetalKit
- Foundation

## Licence
MIT

---

**Pour toute question ou contribution, ouvrez une issue ou une pull request sur le dépôt GitHub du projet.**
