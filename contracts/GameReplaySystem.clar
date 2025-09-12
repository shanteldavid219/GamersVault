(define-constant contract-owner tx-sender)
(define-constant err-owner-only (err u600))
(define-constant err-not-found (err u601))
(define-constant err-session-ended (err u602))
(define-constant err-unauthorized (err u603))
(define-constant err-session-active (err u604))

(define-data-var next-session-id uint u0)
(define-data-var next-move-id uint u0)

(define-map gaming-sessions
    { session-id: uint }
    { player: principal,
      game-type: (string-ascii 30),
      start-block: uint,
      end-block: (optional uint),
      total-moves: uint,
      session-status: (string-ascii 20),
      metadata: (string-ascii 100) }
)

(define-map session-moves
    { session-id: uint, move-id: uint }
    { timestamp: uint,
      move-data: (string-ascii 200),
      move-type: (string-ascii 20),
      sequence-number: uint }
)

(define-map session-stats
    { session-id: uint }
    { duration: uint,
      total-actions: uint,
      peak-performance: uint,
      average-response-time: uint }
)

(define-map replay-permissions
    { session-id: uint, viewer: principal }
    { can-view: bool,
      granted-block: uint,
      granted-by: principal }
)

(define-public (start-gaming-session (game-type (string-ascii 30)) (metadata (string-ascii 100)))
    (let ((session-id (var-get next-session-id)))
        (begin
            (var-set next-session-id (+ session-id u1))
            (map-set gaming-sessions
                { session-id: session-id }
                { player: tx-sender,
                  game-type: game-type,
                  start-block: stacks-block-height,
                  end-block: none,
                  total-moves: u0,
                  session-status: "active",
                  metadata: metadata })
            (ok session-id)))
)

(define-public (record-move (session-id uint) (move-data (string-ascii 200)) (move-type (string-ascii 20)))
    (let ((session (unwrap! (map-get? gaming-sessions { session-id: session-id }) err-not-found))
          (move-id (var-get next-move-id)))
        (begin
            (asserts! (is-eq tx-sender (get player session)) err-unauthorized)
            (asserts! (is-eq (get session-status session) "active") err-session-ended)
            (var-set next-move-id (+ move-id u1))
            (map-set session-moves
                { session-id: session-id, move-id: move-id }
                { timestamp: stacks-block-height,
                  move-data: move-data,
                  move-type: move-type,
                  sequence-number: (+ (get total-moves session) u1) })
            (ok (map-set gaming-sessions
                { session-id: session-id }
                (merge session { total-moves: (+ (get total-moves session) u1) })))))
)

(define-public (end-gaming-session (session-id uint))
    (let ((session (unwrap! (map-get? gaming-sessions { session-id: session-id }) err-not-found)))
        (begin
            (asserts! (is-eq tx-sender (get player session)) err-unauthorized)
            (asserts! (is-eq (get session-status session) "active") err-session-ended)
            (map-set session-stats
                { session-id: session-id }
                { duration: (- stacks-block-height (get start-block session)),
                  total-actions: (get total-moves session),
                  peak-performance: u100,
                  average-response-time: u5 })
            (ok (map-set gaming-sessions
                { session-id: session-id }
                (merge session 
                    { end-block: (some stacks-block-height),
                      session-status: "completed" })))))
)

(define-public (grant-replay-access (session-id uint) (viewer principal))
    (let ((session (unwrap! (map-get? gaming-sessions { session-id: session-id }) err-not-found)))
        (begin
            (asserts! (is-eq tx-sender (get player session)) err-unauthorized)
            (ok (map-set replay-permissions
                { session-id: session-id, viewer: viewer }
                { can-view: true,
                  granted-block: stacks-block-height,
                  granted-by: tx-sender }))))
)

(define-public (revoke-replay-access (session-id uint) (viewer principal))
    (let ((session (unwrap! (map-get? gaming-sessions { session-id: session-id }) err-not-found)))
        (begin
            (asserts! (is-eq tx-sender (get player session)) err-unauthorized)
            (ok (map-set replay-permissions
                { session-id: session-id, viewer: viewer }
                { can-view: false,
                  granted-block: stacks-block-height,
                  granted-by: tx-sender }))))
)

(define-public (create-session-snapshot (session-id uint) (snapshot-data (string-ascii 200)))
    (let ((session (unwrap! (map-get? gaming-sessions { session-id: session-id }) err-not-found)))
        (begin
            (asserts! (is-eq tx-sender (get player session)) err-unauthorized)
            (asserts! (is-eq (get session-status session) "active") err-session-ended)
            (record-move session-id snapshot-data "snapshot")))
)

(define-read-only (get-session-info (session-id uint))
    (ok (map-get? gaming-sessions { session-id: session-id }))
)

(define-read-only (get-session-move (session-id uint) (move-id uint))
    (ok (map-get? session-moves { session-id: session-id, move-id: move-id }))
)

(define-read-only (get-session-stats (session-id uint))
    (ok (map-get? session-stats { session-id: session-id }))
)

(define-read-only (can-view-replay (session-id uint) (viewer principal))
    (let ((session (map-get? gaming-sessions { session-id: session-id }))
          (permission (map-get? replay-permissions { session-id: session-id, viewer: viewer })))
        (match session
            session-data (if (is-eq (get player session-data) viewer)
                             (ok true)
                             (match permission
                                 perm-data (ok (get can-view perm-data))
                                 (ok false)))
            (ok false)))
)

(define-read-only (get-player-sessions (player principal))
    (ok (list))
)

(define-read-only (get-session-replay-data (session-id uint))
    (let ((session (unwrap! (map-get? gaming-sessions { session-id: session-id }) err-not-found)))
        (begin
            (asserts! (or (is-eq tx-sender (get player session))
                         (unwrap-panic (can-view-replay session-id tx-sender))) err-unauthorized)
            (ok session)))
)

(define-public (validate-session-integrity (session-id uint))
    (let ((session (unwrap! (map-get? gaming-sessions { session-id: session-id }) err-not-found))
          (stats (map-get? session-stats { session-id: session-id })))
        (match stats
            stat-data (ok (is-eq (get total-moves session) (get total-actions stat-data)))
            (ok false)))
)

(define-public (export-session-summary (session-id uint))
    (let ((session (unwrap! (map-get? gaming-sessions { session-id: session-id }) err-not-found))
          (stats (map-get? session-stats { session-id: session-id })))
        (begin
            (asserts! (or (is-eq tx-sender (get player session))
                         (unwrap-panic (can-view-replay session-id tx-sender))) err-unauthorized)
            (ok { session-id: session-id,
                  player: (get player session),
                  game-type: (get game-type session),
                  total-moves: (get total-moves session),
                  duration: (match stats s (some (get duration s)) none) })))
)
