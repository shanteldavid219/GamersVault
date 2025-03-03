;; GamersVault - Gaming Assets & Achievements Contract

;; Constants
(define-constant contract-owner tx-sender)
(define-constant err-owner-only (err u100))
(define-constant err-not-found (err u101))
(define-constant err-already-exists (err u102))

;; Data Variables
(define-data-var next-trade-id uint u0)
(define-data-var next-guild-id uint u0)
(define-data-var next-event-id uint u0)

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
      tradeable: bool,
      rarity: (string-ascii 20) }
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
             tradeable: true,
             rarity: "common"}))
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



;; Add to Data Variables
(define-map player-xp 
    { player: principal }
    { level: uint,
      current-xp: uint,
      xp-to-next-level: uint }
)

;; Add Public Function
(define-public (add-player-xp (player principal) (xp-amount uint))
    (begin
        (asserts! (is-eq tx-sender contract-owner) err-owner-only)
        (match (map-get? player-xp {player: player})
            profile (ok (map-set player-xp
                {player: player}
                {level: (+ (get level profile) u1),
                 current-xp: (+ (get current-xp profile) xp-amount),
                 xp-to-next-level: u1000}))
            err-not-found))
)



;; Add to Data Variables
(define-map trade-offers
    { trade-id: uint }
    { from: principal,
      to: principal,
      asset-offered: uint,
      asset-requested: uint,
      status: (string-ascii 20) }
)

;; Add Public Function
(define-public (create-trade-offer (to principal) (asset-offered uint) (asset-requested uint))
    (ok (map-set trade-offers
        {trade-id: (+ (var-get next-trade-id) u1)}
        {from: tx-sender,
         to: to,
         asset-offered: asset-offered,
         asset-requested: asset-requested,
         status: "pending"}))
)



;; Add to Data Variables
(define-fungible-token game-coins)

;; Add Public Function
(define-public (mint-coins (amount uint) (recipient principal))
    (begin
        (asserts! (is-eq tx-sender contract-owner) err-owner-only)
        (ft-mint? game-coins amount recipient))
)


;; Add to Data Variables
(define-map guilds
    { guild-id: uint }
    { name: (string-ascii 50),
      leader: principal,
      members: (list 50 principal) }
)

;; Add Public Function
(define-public (create-guild (guild-name (string-ascii 50)))
    (ok (map-set guilds
        {guild-id: (+ (var-get next-guild-id) u1)}
        {name: guild-name,
         leader: tx-sender,
         members: (list tx-sender)}))
)




;; Add Public Function
(define-public (set-asset-rarity (asset-id uint) (rarity (string-ascii 20)))
    (begin
        (asserts! (is-eq tx-sender contract-owner) err-owner-only)
        (ok (map-set asset-details
            {asset-id: asset-id}
            (merge (unwrap! (map-get? asset-details {asset-id: asset-id}) err-not-found)
                  {rarity: rarity})))
))




;; Add to Data Variables
(define-map events
    { event-id: uint }
    { name: (string-ascii 50),
      start-block: uint,
      end-block: uint,
      rewards: (list 10 uint) }
)

;; Add Public Function
(define-public (create-event (name (string-ascii 50)) (duration uint) (rewards (list 10 uint)))
    (begin
        (asserts! (is-eq tx-sender contract-owner) err-owner-only)
        (ok (map-set events
            {event-id: (+ (var-get next-event-id) u1)}
            {name: name,
             start-block: stacks-block-height,
             end-block: (+ stacks-block-height duration),
             rewards: rewards})))
)



;; Add to Data Variables
(define-map achievement-rewards
    { achievement-id: uint }
    { xp-reward: uint,
      coin-reward: uint,
      asset-reward: (optional uint) }
)

;; Add Public Function
(define-public (claim-achievement-reward (achievement-id uint))
    (begin
        (asserts! (is-some (map-get? achievement-rewards {achievement-id: achievement-id})) err-not-found)
        (let ((reward (unwrap! (map-get? achievement-rewards {achievement-id: achievement-id}) err-not-found)))
            (ok (mint-coins (get coin-reward reward) tx-sender))))
)



;; Add to Data Variables
(define-map player-stats
    { player: principal }
    { games-played: uint,
      tournaments-won: uint,
      trades-completed: uint,
      achievements-earned: uint }
)

;; Add Public Function
(define-public (update-player-stats (stat-type (string-ascii 20)))
    (let ((current-stats (default-to 
            {games-played: u0, tournaments-won: u0, trades-completed: u0, achievements-earned: u0}
            (map-get? player-stats {player: tx-sender}))))
        (ok (map-set player-stats
            {player: tx-sender}
            (merge current-stats
                  {games-played: (+ (get games-played current-stats) u1)}))))
)
