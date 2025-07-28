//
//  StratumClientNIO.swift
//  M1Miner
//
//  NOTE: Ce fichier est un point d'entrée pour le module StratumClientNIO.
//  Toutes les fonctionnalités sont organisées dans des fichiers séparés.

// Réexporter les dépendances principales
@_exported import Foundation
@_exported import NIO
@_exported import NIOConcurrencyHelpers
@_exported import Logging
@_exported import M1MinerShared

// La classe principale StratumClientNIO est définie dans Core/StratumClientCore.swift
// Pour garantir la visibilité dans tout le module, on importe explicitement la déclaration :
