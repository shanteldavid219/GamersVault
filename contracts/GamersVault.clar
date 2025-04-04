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


;; Add to Data Variables
(define-map daily-rewards
    { player: principal }
    { last-claim: uint,
      consecutive-days: uint }
)

(define-constant daily-reward-amount u100)
(define-constant blocks-per-day u144) ;; Assuming 1 block per 10 minutes

(define-public (claim-daily-reward)
    (let (
        (current-block (unwrap-panic (get-stacks-block-info? time u0)))
        (last-claim-data (default-to {last-claim: u0, consecutive-days: u0} 
                         (map-get? daily-rewards {player: tx-sender})))
    )
    (begin
        (asserts! (> current-block (+ (get last-claim last-claim-data) blocks-per-day)) (err u200))
        (ok (map-set daily-rewards
            {player: tx-sender}
            {last-claim: current-block,
             consecutive-days: (+ (get consecutive-days last-claim-data) u1)}))))
)


;; Add to Data Variables
(define-map crafting-recipes
    { recipe-id: uint }
    { ingredients: (list 3 uint),
      result: uint,
      required-level: uint }
)

(define-constant err-insufficient-level (err u103))
(define-constant err-missing-ingredients (err u104))

(define-public (craft-item (recipe-id uint))
    (let (
        (recipe (unwrap! (map-get? crafting-recipes {recipe-id: recipe-id}) err-not-found))
        (player-inv (unwrap! (map-get? player-assets {player: tx-sender}) err-not-found))
        (player-level (get level (unwrap! (map-get? player-xp {player: tx-sender}) err-not-found)))
    )
    (begin
        (asserts! (>= player-level (get required-level recipe)) err-insufficient-level)
        ;; Check ingredients and craft logic would go here
        (ok true)))
)

;; Add to Data Variables
(define-map marketplace-listings
    { listing-id: uint }
    { seller: principal,
      asset-id: uint,
      price: uint,
      active: bool }
)

(define-data-var next-listing-id uint u0)

(define-public (create-listing (asset-id uint) (price uint))
    (let ((listing-id (var-get next-listing-id)))
    (begin
        (var-set next-listing-id (+ listing-id u1))
        (ok (map-set marketplace-listings
            {listing-id: listing-id}
            {seller: tx-sender,
             asset-id: asset-id,
             price: price,
             active: true}))))
)

(define-public (buy-listing (listing-id uint))
    (let ((listing (unwrap! (map-get? marketplace-listings {listing-id: listing-id}) err-not-found)))
    (begin
        (asserts! (get active listing) err-not-found)
        (try! (ft-transfer? game-coins (get price listing) tx-sender (get seller listing)))
        (ok (map-set marketplace-listings
            {listing-id: listing-id}
            (merge listing {active: false})))))
)


;; Add to Data Variables
(define-map achievements
    { achievement-id: uint }
    { name: (string-ascii 50),
      description: (string-ascii 100),
      tier: uint,
      required-value: uint }
)

(define-map player-achievement-progress
    { player: principal, achievement-id: uint }
    { current-value: uint,
      completed: bool }
)

(define-public (check-achievement (achievement-id uint))
    (let (
        (achievement (unwrap! (map-get? achievements {achievement-id: achievement-id}) err-not-found))
        (progress (default-to {current-value: u0, completed: false} 
                  (map-get? player-achievement-progress {player: tx-sender, achievement-id: achievement-id})))
    )
    (begin
        (asserts! (not (get completed progress)) err-already-exists)
        (ok (map-set player-achievement-progress
            {player: tx-sender, achievement-id: achievement-id}
            {current-value: (+ (get current-value progress) u1),
             completed: (>= (+ (get current-value progress) u1) (get required-value achievement))}))))
)


;; Add to Data Variables
(define-map leaderboard-scores
    { player: principal }
    { score: uint,
      last-updated: uint }
)

(define-public (update-leaderboard-score (new-score uint))
    (let (
        (current-block (unwrap-panic (get-stacks-block-info? time u0)))
        (current-entry (default-to {score: u0, last-updated: u0} 
                       (map-get? leaderboard-scores {player: tx-sender})))
    )
    (ok (map-set leaderboard-scores
        {player: tx-sender}
        {score: (+ (get score current-entry) new-score),
         last-updated: current-block})))
)

(define-read-only (get-player-rank (player principal))
    (ok (map-get? leaderboard-scores {player: player}))
)

