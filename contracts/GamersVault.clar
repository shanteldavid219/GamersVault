;; GamersVault - Gaming Assets & Achievements Contract

;; Constants
(define-constant contract-owner tx-sender)
(define-constant err-owner-only (err u100))
(define-constant err-not-found (err u101))
(define-constant err-already-exists (err u102))

;; Data Variables
(define-map player-assets 
    { player: principal }
    { inventory: (list 10 uint),
      achievements: (list 10 uint),
      tournament-access: bool }
)

(define-map asset-details
    { asset-id: uint }
    { name: (string-ascii 50),
      game: (string-ascii 50),
      tradeable: bool }
)

;; Public Functions
(define-public (register-player)
    (begin
        (asserts! (is-none (map-get? player-assets {player: tx-sender})) err-already-exists)
        (ok (map-set player-assets
            {player: tx-sender}
            {inventory: (list), 
             achievements: (list),
             tournament-access: false}))
    )
)

(define-public (add-asset (asset-id uint) (name (string-ascii 50)) (game (string-ascii 50)))
    (begin
        (asserts! (is-eq tx-sender contract-owner) err-owner-only)
        (ok (map-set asset-details
            {asset-id: asset-id}
            {name: name,
             game: game,
             tradeable: true}))
    )
)

(define-public (grant-tournament-access (player principal))
    (begin
        (asserts! (is-eq tx-sender contract-owner) err-owner-only)
        (match (map-get? player-assets {player: player})
            profile (ok (map-set player-assets
                {player: player}
                (merge profile {tournament-access: true})))
            err-not-found))
)

;; Read-only Functions
(define-read-only (get-player-profile (player principal))
    (ok (map-get? player-assets {player: player}))
)

(define-read-only (get-asset-info (asset-id uint))
    (ok (map-get? asset-details {asset-id: asset-id}))
)
