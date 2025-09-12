;; Player Mentorship & Coaching System
;; Enables experienced players to offer coaching services and mentorship

(define-constant contract-owner tx-sender)
(define-constant err-owner-only (err u800))
(define-constant err-not-found (err u801))
(define-constant err-already-exists (err u802))
(define-constant err-unauthorized (err u803))
(define-constant err-session-active (err u804))
(define-constant err-insufficient-funds (err u805))
(define-constant err-invalid-rating (err u806))
(define-constant err-session-not-completed (err u807))

;; Data variables
(define-data-var next-mentor-id uint u0)
(define-data-var next-session-id uint u0)
(define-data-var platform-fee-rate uint u5) ;; 5% platform fee

;; Mentor profiles with specialties and rates
(define-map mentor-profiles
    { mentor-id: uint }
    { mentor: principal,
      specialties: (list 3 (string-ascii 30)),
      hourly-rate: uint,
      total-sessions: uint,
      average-rating: uint,
      verified: bool,
      available: bool,
      bio: (string-ascii 200),
      created-block: uint }
)

;; Mentor by principal lookup
(define-map mentor-by-principal
    { mentor: principal }
    { mentor-id: uint }
)

;; Mentorship sessions
(define-map mentorship-sessions
    { session-id: uint }
    { mentor-id: uint,
      student: principal,
      game-type: (string-ascii 30),
      session-duration: uint,
      total-cost: uint,
      status: (string-ascii 20),
      scheduled-block: uint,
      completed-block: (optional uint),
      student-notes: (optional (string-ascii 200)),
      mentor-notes: (optional (string-ascii 200)) }
)

;; Session ratings and feedback
(define-map session-ratings
    { session-id: uint }
    { student-rating: (optional uint),
      mentor-rating: (optional uint),
      student-feedback: (optional (string-ascii 200)),
      mentor-feedback: (optional (string-ascii 200)),
      rating-block: (optional uint) }
)

;; Student progress tracking
(define-map student-progress
    { student: principal, mentor-id: uint }
    { total-sessions: uint,
      skill-improvement: uint,
      last-session-block: uint,
      progress-notes: (string-ascii 200) }
)

;; Register as mentor
(define-public (register-as-mentor (specialties (list 3 (string-ascii 30))) (hourly-rate uint) (bio (string-ascii 200)))
    (let ((mentor-id (var-get next-mentor-id)))
        (begin
            (asserts! (is-none (map-get? mentor-by-principal { mentor: tx-sender })) err-already-exists)
            (asserts! (> hourly-rate u0) err-invalid-rating)
            (var-set next-mentor-id (+ mentor-id u1))
            (map-set mentor-profiles
                { mentor-id: mentor-id }
                { mentor: tx-sender,
                  specialties: specialties,
                  hourly-rate: hourly-rate,
                  total-sessions: u0,
                  average-rating: u0,
                  verified: false,
                  available: true,
                  bio: bio,
                  created-block: stacks-block-height })
            (ok (map-set mentor-by-principal
                { mentor: tx-sender }
                { mentor-id: mentor-id }))))
)

;; Update mentor profile
(define-public (update-mentor-profile (hourly-rate uint) (available bool) (bio (string-ascii 200)))
    (let ((mentor-lookup (unwrap! (map-get? mentor-by-principal { mentor: tx-sender }) err-not-found))
          (mentor-profile (unwrap! (map-get? mentor-profiles { mentor-id: (get mentor-id mentor-lookup) }) err-not-found)))
        (begin
            (asserts! (> hourly-rate u0) err-invalid-rating)
            (ok (map-set mentor-profiles
                { mentor-id: (get mentor-id mentor-lookup) }
                (merge mentor-profile 
                    { hourly-rate: hourly-rate,
                      available: available,
                      bio: bio })))))
)

;; Book mentorship session
(define-public (book-session (mentor-id uint) (game-type (string-ascii 30)) (duration uint))
    (let ((mentor-profile (unwrap! (map-get? mentor-profiles { mentor-id: mentor-id }) err-not-found))
          (session-id (var-get next-session-id))
          (total-cost (* (get hourly-rate mentor-profile) duration)))
        (begin
            (asserts! (get available mentor-profile) err-not-found)
            (asserts! (not (is-eq tx-sender (get mentor mentor-profile))) err-unauthorized)
            (var-set next-session-id (+ session-id u1))
            (ok (map-set mentorship-sessions
                { session-id: session-id }
                { mentor-id: mentor-id,
                  student: tx-sender,
                  game-type: game-type,
                  session-duration: duration,
                  total-cost: total-cost,
                  status: "pending",
                  scheduled-block: (+ stacks-block-height u144),
                  completed-block: none,
                  student-notes: none,
                  mentor-notes: none }))))
)

;; Confirm session (by mentor)
(define-public (confirm-session (session-id uint))
    (let ((session (unwrap! (map-get? mentorship-sessions { session-id: session-id }) err-not-found))
          (mentor-lookup (unwrap! (map-get? mentor-by-principal { mentor: tx-sender }) err-not-found)))
        (begin
            (asserts! (is-eq (get mentor-id session) (get mentor-id mentor-lookup)) err-unauthorized)
            (asserts! (is-eq (get status session) "pending") err-session-active)
            (ok (map-set mentorship-sessions
                { session-id: session-id }
                (merge session { status: "confirmed" })))))
)

;; Complete session and add notes
(define-public (complete-session (session-id uint) (mentor-notes (string-ascii 200)))
    (let ((session (unwrap! (map-get? mentorship-sessions { session-id: session-id }) err-not-found))
          (mentor-lookup (unwrap! (map-get? mentor-by-principal { mentor: tx-sender }) err-not-found))
          (mentor-profile (unwrap! (map-get? mentor-profiles { mentor-id: (get mentor-id session) }) err-not-found)))
        (begin
            (asserts! (is-eq (get mentor-id session) (get mentor-id mentor-lookup)) err-unauthorized)
            (asserts! (is-eq (get status session) "confirmed") err-session-not-completed)
            (map-set mentorship-sessions
                { session-id: session-id }
                (merge session 
                    { status: "completed",
                      completed-block: (some stacks-block-height),
                      mentor-notes: (some mentor-notes) }))
            (map-set mentor-profiles
                { mentor-id: (get mentor-id session) }
                (merge mentor-profile 
                    { total-sessions: (+ (get total-sessions mentor-profile) u1) }))
            (let ((current-progress (default-to 
                    { total-sessions: u0, skill-improvement: u0, last-session-block: u0, progress-notes: "" }
                    (map-get? student-progress { student: (get student session), mentor-id: (get mentor-id session) }))))
                (ok (map-set student-progress
                    { student: (get student session), mentor-id: (get mentor-id session) }
                    (merge current-progress 
                        { total-sessions: (+ (get total-sessions current-progress) u1),
                          last-session-block: stacks-block-height }))))))
)

;; Rate completed session
(define-public (rate-session (session-id uint) (rating uint) (feedback (string-ascii 200)))
    (let ((session (unwrap! (map-get? mentorship-sessions { session-id: session-id }) err-not-found))
          (current-rating (default-to 
            { student-rating: none, mentor-rating: none, student-feedback: none, mentor-feedback: none, rating-block: none }
            (map-get? session-ratings { session-id: session-id })))
          (mentor-profile (unwrap! (map-get? mentor-profiles { mentor-id: (get mentor-id session) }) err-not-found)))
        (begin
            (asserts! (is-eq (get status session) "completed") err-session-not-completed)
            (asserts! (and (>= rating u1) (<= rating u5)) err-invalid-rating)
            (if (is-eq tx-sender (get student session))
                ;; Student rating mentor
                (begin
                    (map-set session-ratings
                        { session-id: session-id }
                        (merge current-rating 
                            { student-rating: (some rating),
                              student-feedback: (some feedback),
                              rating-block: (some stacks-block-height) }))
                    (ok true))
                ;; Mentor rating student (simplified for brevity)
                (if (is-eq tx-sender (get mentor mentor-profile))
                    (ok (map-set session-ratings
                        { session-id: session-id }
                        (merge current-rating 
                            { mentor-rating: (some rating),
                              mentor-feedback: (some feedback) })))
                    err-unauthorized))))
)

;; Verify mentor (admin only)
(define-public (verify-mentor (mentor-id uint))
    (let ((mentor-profile (unwrap! (map-get? mentor-profiles { mentor-id: mentor-id }) err-not-found)))
        (begin
            (asserts! (is-eq tx-sender contract-owner) err-owner-only)
            (ok (map-set mentor-profiles
                { mentor-id: mentor-id }
                (merge mentor-profile { verified: true })))))
)

;; Read-only functions
(define-read-only (get-mentor-profile (mentor-id uint))
    (ok (map-get? mentor-profiles { mentor-id: mentor-id }))
)

(define-read-only (get-mentor-by-principal (mentor principal))
    (ok (map-get? mentor-by-principal { mentor: mentor }))
)

(define-read-only (get-session-info (session-id uint))
    (ok (map-get? mentorship-sessions { session-id: session-id }))
)

(define-read-only (get-session-rating (session-id uint))
    (ok (map-get? session-ratings { session-id: session-id }))
)

(define-read-only (get-student-progress (student principal) (mentor-id uint))
    (ok (map-get? student-progress { student: student, mentor-id: mentor-id }))
)

(define-read-only (get-platform-fee-rate)
    (ok (var-get platform-fee-rate))
)

(define-read-only (calculate-session-cost (mentor-id uint) (duration uint))
    (match (map-get? mentor-profiles { mentor-id: mentor-id })
        profile (let ((base-cost (* (get hourly-rate profile) duration))
                     (platform-fee (/ (* base-cost (var-get platform-fee-rate)) u100)))
                   (ok { base-cost: base-cost, 
                         platform-fee: platform-fee, 
                         total-cost: (+ base-cost platform-fee) }))
        err-not-found)
)

(define-read-only (is-mentor-available (mentor-id uint))
    (match (map-get? mentor-profiles { mentor-id: mentor-id })
        profile (ok (get available profile))
        (ok false))
)
