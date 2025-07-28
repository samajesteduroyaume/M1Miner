#include <metal_stdlib>
using namespace metal;

// Constantes optimisées pour l'algorithme KawPow
constant constexpr uint KECCAK_ROUNDS = 24;
constant constexpr uint FNV_PRIME = 0x01000193;
constant constexpr uint FNV_OFFSET_BASIS = 0x811c9dc5;
constant constexpr uint4 VEC_FNV_PRIME = uint4(FNV_PRIME);
constant constexpr uint4 VEC_16 = uint4(16);

// Fonction de hachage FNV-1 optimisée avec vectorisation
inline uint4 fnv1a_vec4(uint4 x, uint4 y) {
    return (x ^ y) * VEC_FNV_PRIME;
}

// Fonction de mélange optimisée avec décalages vectoriels
inline uint4 shuffle_optimized(uint4 v) {
    // Décalage de 16 bits à gauche et à droite avec OR pour le mélange
    return (v >> 16) | (v << 16);
}

// Structure pour regrouper les variables d'état
struct MiningState {
    uint4 mix[4];
    
    // Constructeur pour initialiser l'état
    MiningState(constant const uint* header, uint nonce_val) {
        // Initialisation vectorisée
        mix[0] = uint4(header[0], header[1], 0, 0);
        mix[1] = uint4(header[2], header[3], 0, 0);
        mix[2] = uint4(header[4], header[5], 0, 0);
        mix[3] = uint4(header[6], header[7], 0, 0);
        
        // Ajout du nonce au début du mélange
        mix[0].x += nonce_val;
    }
    
    // Fonction de mélange optimisée
    void mix_round(uint round) {
        // Déroulage partiel de la boucle pour le pipeline GPU
        #pragma unroll 4
        for (int i = 0; i < 4; i++) {
            // Accès aux éléments de manière séquentielle pour améliorer la localité
            uint4 a = mix[i];
            uint4 b = mix[(i + 1) & 0x3];
            
            // Opérations de mélange optimisées
            a += b;
            b = shuffle_optimized(b) ^ a;
            a = shuffle_optimized(a);
            
            // Stockage des résultats
            mix[i] = a;
            mix[(i + 1) & 0x3] = b;
            
            // Sauter une itération sur deux pour le motif de mélange
            i++;
        }
    }
    
    // Fonction pour extraire le résultat final
    void get_result(device uint* output) {
        // Écriture séquentielle pour optimiser l'accès mémoire
        output[0] = mix[0].x;
        output[1] = mix[1].x;
        output[2] = mix[2].x;
        output[3] = mix[3].x;
    }
};

// Fonction de hachage principale optimisée pour KawPoW
kernel void kawpow_hash_optimized(
    constant const uint* header [[buffer(0)]],  // En-tête du bloc (lecture seule)
    constant const uint* nonce [[buffer(1)]],   // Valeur de nonce (lecture seule)
    device uint* output [[buffer(2)]],          // Sortie du hachage (écriture seule)
    uint tid [[thread_position_in_grid]],
    uint tcount [[threads_per_grid]]
) {
    // Optimisation: Utilisation de la mémoire locale pour les threads du même groupe
    threadgroup uint local_cache[64];
    
    // Initialisation de l'état avec vectorisation
    MiningState state(header, *nonce + tid);
    
    // Déroulage partiel de la boucle principale
    #pragma unroll 6
    for (uint i = 0; i < KECCAK_ROUNDS; i++) {
        state.mix_round(i);
    }
    
    // Stockage du résultat final
    if (tid < tcount) {
        state.get_result(output + (tid * 4));
    }
}

// Version alternative avec traitement par lots pour les petits lots
kernel void kawpow_hash_batch(
    constant const uint* headers [[buffer(0)]],  // Tableau d'en-têtes
    constant const uint* nonces [[buffer(1)]],   // Tableau de nonces
    device uint* output [[buffer(2)]],           // Sortie des hachages
    uint tid [[thread_position_in_grid]],
    uint batch_size [[threads_per_grid]]
) {
    // Traitement par lots de 4 nonces par thread
    const uint base_idx = tid * 4;
    
    // Vérification des limites
    if (base_idx >= batch_size) return;
    
    // Traitement de 4 nonces en parallèle
    for (uint i = 0; i < 4 && (base_idx + i) < batch_size; i++) {
        MiningState state(headers + (base_idx + i) * 8, nonces[base_idx + i]);
        
        #pragma unroll 6
        for (uint j = 0; j < KECCAK_ROUNDS; j++) {
            state.mix_round(j);
        }
        
        state.get_result(output + (base_idx + i) * 4);
    }
}
