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


;; Tournament System Constants
(define-constant err-tournament-full (err u400))
(define-constant err-tournament-not-active (err u401))
(define-constant err-not-participant (err u402))
(define-constant err-match-not-ready (err u403))
(define-constant err-invalid-winner (err u404))

;; Tournament Data Variables
(define-data-var next-tournament-id uint u0)
(define-data-var next-match-id uint u0)

;; Tournament Structure
(define-map tournaments
    { tournament-id: uint }
    { name: (string-ascii 50),
      creator: principal,
      entry-fee: uint,
      prize-pool: uint,
      max-participants: uint,
      current-participants: uint,
      status: (string-ascii 20),
      start-block: uint,
      winner: (optional principal) }
)

;; Tournament Participants
(define-map tournament-participants
    { tournament-id: uint, participant: principal }
    { joined-block: uint,
      eliminated: bool,
      current-round: uint }
)

;; Tournament Matches
(define-map tournament-matches
    { match-id: uint }
    { tournament-id: uint,
      round: uint,
      player1: principal,
      player2: principal,
      winner: (optional principal),
      completed: bool }
)

;; Tournament Rounds Tracking
(define-map tournament-rounds
    { tournament-id: uint, round: uint }
    { matches-total: uint,
      matches-completed: uint,
      active: bool }
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



(define-map lending-contracts
    { loan-id: uint }
    { lender: principal,
      borrower: (optional principal),
      asset-id: uint,
      duration: uint,
      fee: uint,
      start-block: uint,
      active: bool }
)

(define-data-var next-loan-id uint u0)

(define-public (create-loan-offer (asset-id uint) (duration uint) (fee uint))
    (let ((loan-id (var-get next-loan-id)))
    (begin
        (var-set next-loan-id (+ loan-id u1))
        (ok (map-set lending-contracts
            {loan-id: loan-id}
            {lender: tx-sender,
             borrower: none,
             asset-id: asset-id,
             duration: duration,
             fee: fee,
             start-block: u0,
             active: true}))))
)

(define-public (accept-loan (loan-id uint))
    (let ((loan (unwrap! (map-get? lending-contracts {loan-id: loan-id}) err-not-found)))
    (begin
        (asserts! (get active loan) err-not-found)
        (try! (ft-transfer? game-coins (get fee loan) tx-sender (get lender loan)))
        (ok (map-set lending-contracts
            {loan-id: loan-id}
            (merge loan 
                {borrower: (some tx-sender),
                 start-block: stacks-block-height,
                 active: true})))))
)


(define-map fusion-recipes
    { recipe-id: uint }
    { input-assets: (list 3 uint),
      output-asset: uint,
      fusion-cost: uint }
)

(define-constant err-fusion-failed (err u300))

(define-public (register-fusion-recipe (recipe-id uint) (inputs (list 3 uint)) (output uint) (cost uint))
    (begin
        (asserts! (is-eq tx-sender contract-owner) err-owner-only)
        (ok (map-set fusion-recipes
            {recipe-id: recipe-id}
            {input-assets: inputs,
             output-asset: output,
             fusion-cost: cost})))
)

(define-public (fuse-assets (recipe-id uint))
    (let ((recipe (unwrap! (map-get? fusion-recipes {recipe-id: recipe-id}) err-not-found))
          (player-data (unwrap! (map-get? player-assets {player: tx-sender}) err-not-found)))
        (begin
            (try! (ft-transfer? game-coins (get fusion-cost recipe) tx-sender contract-owner))
            (ok (map-set player-assets
                {player: tx-sender}
                (merge player-data
                    {inventory: (unwrap! (as-max-len? 
                        (append (get inventory player-data) (get output-asset recipe)) u10) 
                        err-fusion-failed)}))))))



;; Create Tournament
(define-public (create-tournament (name (string-ascii 50)) (entry-fee uint) (max-participants uint))
    (let ((tournament-id (var-get next-tournament-id)))
        (begin
            (var-set next-tournament-id (+ tournament-id u1))
            (ok (map-set tournaments
                { tournament-id: tournament-id }
                { name: name,
                  creator: tx-sender,
                  entry-fee: entry-fee,
                  prize-pool: u0,
                  max-participants: max-participants,
                  current-participants: u0,
                  status: "registration",
                  start-block: u0,
                  winner: none }))))
)

;; Join Tournament
(define-public (join-tournament (tournament-id uint))
    (let ((tournament (unwrap! (map-get? tournaments { tournament-id: tournament-id }) err-not-found)))
        (begin
            (asserts! (is-eq (get status tournament) "registration") err-tournament-not-active)
            (asserts! (< (get current-participants tournament) (get max-participants tournament)) err-tournament-full)
            (asserts! (is-none (map-get? tournament-participants { tournament-id: tournament-id, participant: tx-sender })) err-already-exists)
            (try! (ft-transfer? game-coins (get entry-fee tournament) tx-sender contract-owner))
            (map-set tournament-participants
                { tournament-id: tournament-id, participant: tx-sender }
                { joined-block: stacks-block-height,
                  eliminated: false,
                  current-round: u1 })
            (ok (map-set tournaments
                { tournament-id: tournament-id }
                (merge tournament 
                    { current-participants: (+ (get current-participants tournament) u1),
                      prize-pool: (+ (get prize-pool tournament) (get entry-fee tournament)) })))))
)

;; Start Tournament
(define-public (start-tournament (tournament-id uint))
    (let ((tournament (unwrap! (map-get? tournaments { tournament-id: tournament-id }) err-not-found)))
        (begin
            (asserts! (is-eq tx-sender (get creator tournament)) err-owner-only)
            (asserts! (is-eq (get status tournament) "registration") err-tournament-not-active)
            (asserts! (>= (get current-participants tournament) u2) (err u405))
            (try! (generate-first-round-matches tournament-id))
            (ok (map-set tournaments
                { tournament-id: tournament-id }
                (merge tournament 
                    { status: "active",
                      start-block: stacks-block-height })))))
)

;; Generate First Round Matches
(define-private (generate-first-round-matches (tournament-id uint))
    (let ((tournament (unwrap! (map-get? tournaments { tournament-id: tournament-id }) err-not-found))
          (participant-count (get current-participants tournament)))
        (begin
            (map-set tournament-rounds
                { tournament-id: tournament-id, round: u1 }
                { matches-total: (/ participant-count u2),
                  matches-completed: u0,
                  active: true })
            (ok true)))
)

;; Create Match
(define-public (create-match (tournament-id uint) (round uint) (player1 principal) (player2 principal))
    (let ((match-id (var-get next-match-id)))
        (begin
            (asserts! (is-eq tx-sender contract-owner) err-owner-only)
            (var-set next-match-id (+ match-id u1))
            (ok (map-set tournament-matches
                { match-id: match-id }
                { tournament-id: tournament-id,
                  round: round,
                  player1: player1,
                  player2: player2,
                  winner: none,
                  completed: false }))))
)

;; Report Match Result
(define-public (report-match-result (match-id uint) (winner principal))
    (let ((match (unwrap! (map-get? tournament-matches { match-id: match-id }) err-not-found))
          (tournament (unwrap! (map-get? tournaments { tournament-id: (get tournament-id match) }) err-not-found)))
        (begin
            (asserts! (is-eq tx-sender (get creator tournament)) err-owner-only)
            (asserts! (not (get completed match)) err-already-exists)
            (asserts! (or (is-eq winner (get player1 match)) (is-eq winner (get player2 match))) err-invalid-winner)
            (map-set tournament-matches
                { match-id: match-id }
                (merge match { winner: (some winner), completed: true }))
            (try! (update-round-progress (get tournament-id match) (get round match)))
            (ok true)))
)

;; Update Round Progress
(define-private (update-round-progress (tournament-id uint) (round uint))
    (let ((round-data (unwrap! (map-get? tournament-rounds { tournament-id: tournament-id, round: round }) err-not-found)))
        (begin
            (map-set tournament-rounds
                { tournament-id: tournament-id, round: round }
                (merge round-data { matches-completed: (+ (get matches-completed round-data) u1) }))
            (if (is-eq (+ (get matches-completed round-data) u1) (get matches-total round-data))
                (advance-tournament-round tournament-id round)
                (ok true))))
)

;; Advance Tournament Round
(define-private (advance-tournament-round (tournament-id uint) (current-round uint))
    (let ((remaining-players (get-round-winners tournament-id current-round)))
        (if (is-eq (len remaining-players) u1)
            (complete-tournament tournament-id (unwrap-panic (element-at remaining-players u0)))
            (begin
                (map-set tournament-rounds
                    { tournament-id: tournament-id, round: (+ current-round u1) }
                    { matches-total: (/ (len remaining-players) u2),
                      matches-completed: u0,
                      active: true })
                (ok true))))
)

;; Get Round Winners (simplified - would need proper implementation)
(define-private (get-round-winners (tournament-id uint) (round uint))
    (list tx-sender)
)

;; Complete Tournament
(define-private (complete-tournament (tournament-id uint) (winner principal))
    (let ((tournament (unwrap! (map-get? tournaments { tournament-id: tournament-id }) err-not-found)))
        (begin
            (try! (ft-mint? game-coins (get prize-pool tournament) winner))
            (ok (map-set tournaments
                { tournament-id: tournament-id }
                (merge tournament 
                    { status: "completed",
                      winner: (some winner) })))))
)

;; Read-only Functions
(define-read-only (get-tournament-info (tournament-id uint))
    (ok (map-get? tournaments { tournament-id: tournament-id }))
)

(define-read-only (get-tournament-participant (tournament-id uint) (participant principal))
    (ok (map-get? tournament-participants { tournament-id: tournament-id, participant: participant }))
)

(define-read-only (get-match-info (match-id uint))
    (ok (map-get? tournament-matches { match-id: match-id }))
)

(define-read-only (get-round-info (tournament-id uint) (round uint))
    (ok (map-get? tournament-rounds { tournament-id: tournament-id, round: round }))
)

(define-read-only (is-tournament-participant (tournament-id uint) (player principal))
    (is-some (map-get? tournament-participants { tournament-id: tournament-id, participant: player }))
)