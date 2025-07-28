# ``StratumClientNIO``

Un client haute performance pour le protocole Stratum, utilisé pour le minage de cryptomonnaies.

## Vue d'ensemble

Le `StratumClientNIO` est le point d'entrée principal pour interagir avec un pool de minage utilisant le protocole Stratum. Il gère la connexion au pool, l'authentification, la réception des travaux de minage et la soumission des solutions.

## Sujets

### Initialisation

- ``init(host:port:useTLS:workerName:password:configuration:)``
- ``StratumClientConfiguration``

### Connexion

- ``connect()``
- ``disconnect()``
- ``reconnect()``

### Soumission de solutions

- ``submit(jobId:extranonce2:ntime:nonce:)``
- ``SubmitResult``

### Gestion des travaux

- ``currentJob``
- ``difficulty``
- ``poolInfo``

### Délégation

- ``StratumClientDelegate``
- ``setDelegate(_:)``

### Statistiques

- ``getStats()``
- ``StratumClientStats``

## Voir aussi

- ``NetworkManager``
- ``SecureStorage``
- ``ReplayProtection``
