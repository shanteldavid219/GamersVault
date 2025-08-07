;; Dynamic Skill Rating System with ELO mechanics
;; Tracks player skill across game types with seasonal progression

(define-constant contract-owner tx-sender)
(define-constant err-owner-only (err u700))
(define-constant err-not-found (err u701))
(define-constant err-invalid-rating (err u702))
(define-constant err-same-player (err u703))
(define-constant err-season-ended (err u704))
(define-constant err-insufficient-games (err u705))

;; Rating system constants
(define-constant base-rating u1200)
(define-constant max-rating u3000)
(define-constant min-rating u600)
(define-constant k-factor-base u32)
(define-constant k-factor-new u50)
(define-constant provisional-games u10)
(define-constant decay-threshold u2016) ;; blocks for 2 weeks
(define-constant decay-rate u5)

;; Season and rating tracking
(define-data-var current-season uint u1)
(define-data-var season-start-block uint u0)
(define-data-var season-duration uint u100800) ;; ~10 weeks

;; Player skill ratings per game type and season
(define-map player-ratings
    { player: principal, game-type: (string-ascii 30), season: uint }
    { current-rating: uint,
      peak-rating: uint,
      games-played: uint,
      wins: uint,
      losses: uint,
      last-game-block: uint,
      provisional: bool,
      decay-applied: uint }
)

;; Game type configurations
(define-map game-type-config
    { game-type: (string-ascii 30) }
    { enabled: bool,
      rating-floor: uint,
      rating-ceiling: uint,
      k-factor-modifier: uint,
      min-rating-diff: uint }
)

;; Match results for rating calculations
(define-map match-results
    { match-id: uint }
    { player1: principal,
      player2: principal,
      winner: principal,
      game-type: (string-ascii 30),
      season: uint,
      rating-change-p1: int,
      rating-change-p2: int,
      processed-block: uint }
)

;; Seasonal leaderboards
(define-map seasonal-rankings
    { game-type: (string-ascii 30), season: uint, rank: uint }
    { player: principal,
      final-rating: uint,
      games-played: uint,
      win-rate: uint }
)

(define-data-var next-match-id uint u0)

;; Initialize a new game type
(define-public (register-game-type (game-type (string-ascii 30)) (rating-floor uint) (rating-ceiling uint))
    (begin
        (asserts! (is-eq tx-sender contract-owner) err-owner-only)
        (asserts! (< rating-floor rating-ceiling) err-invalid-rating)
        (ok (map-set game-type-config
            { game-type: game-type }
            { enabled: true,
              rating-floor: rating-floor,
              rating-ceiling: rating-ceiling,
              k-factor-modifier: u100,
              min-rating-diff: u50 })))
)

;; Get or initialize player rating
(define-private (get-or-init-rating (player principal) (game-type (string-ascii 30)))
    (let ((season (var-get current-season)))
        (match (map-get? player-ratings { player: player, game-type: game-type, season: season })
            existing-rating existing-rating
            { current-rating: base-rating,
              peak-rating: base-rating,
              games-played: u0,
              wins: u0,
              losses: u0,
              last-game-block: stacks-block-height,
              provisional: true,
              decay-applied: u0 }))
)

;; Calculate expected score using ELO formula
(define-private (calculate-expected-score (rating-a uint) (rating-b uint))
    (let ((rating-diff (if (> rating-a rating-b) 
                          (- rating-a rating-b) 
                          (- rating-b rating-a)))
          (expected-raw (if (> rating-a rating-b) u750 u250)))
        (if (> rating-diff u400)
            (if (> rating-a rating-b) u950 u50)
            (+ expected-raw (/ (* rating-diff u200) u400))))
)

;; Calculate K-factor based on player stats
(define-private (calculate-k-factor (rating-data { current-rating: uint, peak-rating: uint, games-played: uint, wins: uint, losses: uint, last-game-block: uint, provisional: bool, decay-applied: uint }))
    (if (get provisional rating-data)
        k-factor-new
        (if (< (get current-rating rating-data) u2100)
            k-factor-base
            (/ (* k-factor-base u80) u100)))
)

;; Apply skill decay for inactive players
(define-private (apply-skill-decay (rating-data { current-rating: uint, peak-rating: uint, games-played: uint, wins: uint, losses: uint, last-game-block: uint, provisional: bool, decay-applied: uint }))
    (let ((blocks-since-game (- stacks-block-height (get last-game-block rating-data))))
        (if (and (> blocks-since-game decay-threshold) (not (get provisional rating-data)))
            (let ((decay-periods (/ blocks-since-game decay-threshold))
                  (total-decay (* decay-periods decay-rate))
                  (new-rating (if (> (get current-rating rating-data) total-decay)
                                 (- (get current-rating rating-data) total-decay)
                                 min-rating)))
                (merge rating-data 
                    { current-rating: new-rating,
                      decay-applied: (+ (get decay-applied rating-data) total-decay) }))
            rating-data))
)

;; Process match result and update ratings
(define-public (process-match-result (player1 principal) (player2 principal) (winner principal) (game-type (string-ascii 30)))
    (begin
        (asserts! (not (is-eq player1 player2)) err-same-player)
        (asserts! (or (is-eq winner player1) (is-eq winner player2)) err-invalid-rating)
        (asserts! (is-some (map-get? game-type-config { game-type: game-type })) err-not-found)
        
        (let ((season (var-get current-season))
              (match-id (var-get next-match-id))
              (rating1-raw (get-or-init-rating player1 game-type))
              (rating2-raw (get-or-init-rating player2 game-type))
              (rating1 (apply-skill-decay rating1-raw))
              (rating2 (apply-skill-decay rating2-raw))
              (expected1 (calculate-expected-score (get current-rating rating1) (get current-rating rating2)))
              (expected2 (- u1000 expected1))
              (actual1 (if (is-eq winner player1) u1000 u0))
              (actual2 (if (is-eq winner player2) u1000 u0))
              (k1 (calculate-k-factor rating1))
              (k2 (calculate-k-factor rating2))
              (rating-change1 (/ (* k1 (if (>= actual1 expected1) (- actual1 expected1) (- expected1 actual1))) u1000))
              (rating-change2 (/ (* k2 (if (>= actual2 expected2) (- actual2 expected2) (- expected2 actual2))) u1000))
              (new-rating1 (if (is-eq winner player1)
                              (if (< (+ (get current-rating rating1) rating-change1) max-rating)
                                  (+ (get current-rating rating1) rating-change1)
                                  max-rating)
                              (if (> (- (get current-rating rating1) rating-change1) min-rating)
                                  (- (get current-rating rating1) rating-change1)
                                  min-rating)))
              (new-rating2 (if (is-eq winner player2)
                              (if (< (+ (get current-rating rating2) rating-change2) max-rating)
                                  (+ (get current-rating rating2) rating-change2)
                                  max-rating)
                              (if (> (- (get current-rating rating2) rating-change2) min-rating)
                                  (- (get current-rating rating2) rating-change2)
                                  min-rating))))
            
            ;; Update player 1 rating
            (map-set player-ratings
                { player: player1, game-type: game-type, season: season }
                { current-rating: new-rating1,
                  peak-rating: (if (> new-rating1 (get peak-rating rating1)) new-rating1 (get peak-rating rating1)),
                  games-played: (+ (get games-played rating1) u1),
                  wins: (if (is-eq winner player1) (+ (get wins rating1) u1) (get wins rating1)),
                  losses: (if (is-eq winner player2) (+ (get losses rating1) u1) (get losses rating1)),
                  last-game-block: stacks-block-height,
                  provisional: (< (+ (get games-played rating1) u1) provisional-games),
                  decay-applied: (get decay-applied rating1) })
            
            ;; Update player 2 rating
            (map-set player-ratings
                { player: player2, game-type: game-type, season: season }
                { current-rating: new-rating2,
                  peak-rating: (if (> new-rating2 (get peak-rating rating2)) new-rating2 (get peak-rating rating2)),
                  games-played: (+ (get games-played rating2) u1),
                  wins: (if (is-eq winner player2) (+ (get wins rating2) u1) (get wins rating2)),
                  losses: (if (is-eq winner player1) (+ (get losses rating2) u1) (get losses rating2)),
                  last-game-block: stacks-block-height,
                  provisional: (< (+ (get games-played rating2) u1) provisional-games),
                  decay-applied: (get decay-applied rating2) })
            
            ;; Record match result
            (var-set next-match-id (+ match-id u1))
            (ok (map-set match-results
                { match-id: match-id }
                { player1: player1,
                  player2: player2,
                  winner: winner,
                  game-type: game-type,
                  season: season,
                  rating-change-p1: (if (is-eq winner player1) (to-int rating-change1) (- 0 (to-int rating-change1))),
                  rating-change-p2: (if (is-eq winner player2) (to-int rating-change2) (- 0 (to-int rating-change2))),
                  processed-block: stacks-block-height }))))
)

;; Start new season
(define-public (start-new-season)
    (begin
        (asserts! (is-eq tx-sender contract-owner) err-owner-only)
        (asserts! (> stacks-block-height (+ (var-get season-start-block) (var-get season-duration))) err-season-ended)
        (var-set current-season (+ (var-get current-season) u1))
        (ok (var-set season-start-block stacks-block-height)))
)

;; Update season duration
(define-public (set-season-duration (new-duration uint))
    (begin
        (asserts! (is-eq tx-sender contract-owner) err-owner-only)
        (ok (var-set season-duration new-duration)))
)

;; Get player's current rating
(define-read-only (get-player-rating (player principal) (game-type (string-ascii 30)))
    (let ((season (var-get current-season)))
        (ok (map-get? player-ratings { player: player, game-type: game-type, season: season })))
)

;; Get match history
(define-read-only (get-match-result (match-id uint))
    (ok (map-get? match-results { match-id: match-id }))
)

;; Calculate win rate
(define-read-only (get-player-win-rate (player principal) (game-type (string-ascii 30)))
    (let ((season (var-get current-season)))
        (match (map-get? player-ratings { player: player, game-type: game-type, season: season })
            rating-data (if (> (get games-played rating-data) u0)
                           (ok (/ (* (get wins rating-data) u100) (get games-played rating-data)))
                           (ok u0))
            (ok u0)))
)

;; Find suitable opponent based on rating
(define-read-only (find-opponent-in-range (player principal) (game-type (string-ascii 30)) (rating-range uint))
    (let ((player-rating (get-or-init-rating player game-type))
          (min-opponent-rating (if (> (get current-rating player-rating) rating-range)
                                  (- (get current-rating player-rating) rating-range)
                                  min-rating))
          (max-opponent-rating (if (< (+ (get current-rating player-rating) rating-range) max-rating)
                                  (+ (get current-rating player-rating) rating-range)
                                  max-rating)))
        (ok { min-rating: min-opponent-rating,
              max-rating: max-opponent-rating,
              player-rating: (get current-rating player-rating) }))
)

;; Get current season info
(define-read-only (get-season-info)
    (ok { current-season: (var-get current-season),
          season-start: (var-get season-start-block),
          season-end: (+ (var-get season-start-block) (var-get season-duration)),
          blocks-remaining: (if (> (+ (var-get season-start-block) (var-get season-duration)) stacks-block-height)
                               (- (+ (var-get season-start-block) (var-get season-duration)) stacks-block-height)
                               u0) })
)

;; Check if player needs rating refresh due to decay
(define-read-only (needs-rating-refresh (player principal) (game-type (string-ascii 30)))
    (let ((rating-data (get-or-init-rating player game-type))
          (blocks-since-game (- stacks-block-height (get last-game-block rating-data))))
        (ok (and (> blocks-since-game decay-threshold) (not (get provisional rating-data)))))
)

;; Get game type configuration
(define-read-only (get-game-type-config (game-type (string-ascii 30)))
    (ok (map-get? game-type-config { game-type: game-type }))
)


