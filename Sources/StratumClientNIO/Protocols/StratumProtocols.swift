import Foundation
import M1MinerShared

// MARK: - Protocoles Stratum (dépréciés)

/// Protocole pour les méthodes de rappel du client Stratum (déprécié)
/// Utilisez `StratumClientDelegate` du module `M1MinerShared` à la place
@available(*, deprecated, message: "Use StratumClientDelegate from M1MinerShared module instead")
public typealias StratumClientDelegate = M1MinerShared.StratumClientDelegate

/// Protocole pour le client Stratum (déprécié)
/// Utilisez `StratumClientInterface` du module `M1MinerShared` à la place
@available(*, deprecated, message: "Use StratumClientInterface from M1MinerShared module instead")
public typealias StratumClientInterface = M1MinerShared.StratumClientInterface

// MARK: - Protocoles pour la gestion réseau

// NetworkManagerDelegate a été déplacé dans StratumClientDelegate.swift
