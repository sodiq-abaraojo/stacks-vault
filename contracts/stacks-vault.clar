;; Title: StacksVault Protocol
;; Summary: Decentralized BTC-collateralized stablecoin lending protocol on Stacks Layer 2
;; Description: StacksVault enables users to mint USD-pegged stablecoins by depositing Bitcoin as collateral.
;;              The protocol maintains a 150% minimum collateralization ratio with automatic liquidation 
;;              mechanisms to ensure stability. Features include dynamic interest rates, oracle-based pricing,
;;              and governance controls for a secure DeFi lending experience on Stacks blockchain.
;;

;; ERROR CODES

(define-constant ERR-NOT-AUTHORIZED (err u1000))
(define-constant ERR-INSUFFICIENT-COLLATERAL (err u1001))
(define-constant ERR-POSITION-NOT-FOUND (err u1002))
(define-constant ERR-UNDERCOLLATERALIZED (err u1003))
(define-constant ERR-MINIMUM-LOAN-REQUIRED (err u1004))
(define-constant ERR-INSUFFICIENT-DEBT (err u1005))
(define-constant ERR-PRICE-EXPIRED (err u1006))
(define-constant ERR-PROTOCOL-PAUSED (err u1007))
(define-constant ERR-INVALID-AMOUNT (err u1008))
(define-constant ERR-NO-PRICE-DATA (err u1009))

;; PROTOCOL PARAMETERS

;; Collateralization and liquidation parameters
(define-constant COLLATERAL-RATIO u150)           ;; 150% minimum collateral ratio (1.5x)
(define-constant LIQUIDATION-THRESHOLD u120)      ;; 120% liquidation threshold
(define-constant LIQUIDATION-PENALTY u10)         ;; 10% liquidation penalty

;; Loan and pricing parameters
(define-constant MINIMUM_LOAN_AMOUNT u100000000)  ;; 100 stablecoins (with 8 decimals)
(define-constant PRICE_EXPIRY u86400)             ;; Price feed valid for 24 hours (in seconds)

;; Interest rate parameters
(define-constant INTEREST_RATE_PER_BLOCK u5)      ;; 0.0005% interest per block (~10% APR)
(define-constant INTEREST_RATE_DENOMINATOR u1000000) ;; Interest rate precision

;; PROTOCOL STATE VARIABLES

;; Administrative state
(define-data-var protocol-owner principal tx-sender)
(define-data-var protocol-paused bool false)

;; Financial state tracking
(define-data-var total-debt uint u0)              ;; Total debt in the system
(define-data-var total-collateral uint u0)        ;; Total BTC collateral in the system
(define-data-var stability-fee uint u0)           ;; Accumulated protocol fees
(define-data-var last-accrual-block uint stacks-block-height) ;; Last interest accrual block

;; Oracle price data
(define-data-var btc-price-in-usd 
  (optional {price: uint, timestamp: uint}) none) ;; BTC/USD price from oracle

;; Testing utilities
(define-data-var current-time uint u0)            ;; Mock time for testing

;; DATA STRUCTURES

;; User position tracking
(define-map positions principal {
  collateral: uint,        ;; Amount of BTC collateral (in satoshis)
  debt: uint,             ;; Amount of stablecoin debt
  last-update-block: uint ;; Last block when position was updated (for interest calculation)
})

;; Stablecoin fungible token
(define-fungible-token stable-usd)

;; ADMINISTRATIVE FUNCTIONS

;; Transfer protocol ownership
(define-public (set-protocol-owner (new-owner principal))
  (begin
    (asserts! (is-eq tx-sender (var-get protocol-owner)) ERR-NOT-AUTHORIZED)
    (ok (var-set protocol-owner new-owner))
  )
)

;; Emergency pause/unpause protocol
(define-public (pause-protocol (paused bool))
  (begin
    (asserts! (is-eq tx-sender (var-get protocol-owner)) ERR-NOT-AUTHORIZED)
    (ok (var-set protocol-paused paused))
  )
)

;; Update BTC price from oracle
(define-public (update-btc-price (price uint) (timestamp uint))
  (begin
    (asserts! (is-eq tx-sender (var-get protocol-owner)) ERR-NOT-AUTHORIZED)
    (asserts! (> price u0) ERR-INVALID-AMOUNT)
    (var-set btc-price-in-usd (some {price: price, timestamp: timestamp}))
    (ok true)
  )
)

;; Set current time for testing
(define-public (set-current-time (time uint))
  (begin
    (asserts! (is-eq tx-sender (var-get protocol-owner)) ERR-NOT-AUTHORIZED)
    (ok (var-set current-time time))
  )
)

;;   UTILITY FUNCTIONS

;; Calculate USD value of BTC collateral
(define-private (collateral-value (collateral-amount uint) (price uint))
  (* collateral-amount price)
)

;; Calculate required collateral for a given debt amount
(define-private (required-collateral (debt-amount uint) (price uint))
  (/ (* debt-amount COLLATERAL-RATIO) (/ price u100))
)

;; Check if a position meets collateralization requirements
(define-private (is-position-safe (user principal) (btc-price uint))
  (let (
    (position (unwrap! (map-get? positions user) false))
    (debt (get debt position))
    (collateral (get collateral position))
    (collateral-value-usd (collateral-value collateral btc-price))
    (min-collateral-value-usd (/ (* debt COLLATERAL-RATIO) u100))
  )
    (>= collateral-value-usd min-collateral-value-usd)
  )
)

;; Calculate interest accrued over time
(define-private (calculate-interest (debt uint) (blocks-passed uint))
  (/ (* debt (* blocks-passed INTEREST_RATE_PER_BLOCK)) INTEREST_RATE_DENOMINATOR)
)

;; INTEREST ACCRUAL FUNCTIONS

;; Accrue interest globally across all positions
(define-private (accrue-global-interest)
  (let (
    (current-block stacks-block-height)
    (last-block (var-get last-accrual-block))
    (blocks-passed (- current-block last-block))
    (total-system-debt (var-get total-debt))
    (interest-accrued (calculate-interest total-system-debt blocks-passed))
  )
    (begin
      (if (> blocks-passed u0)
        (begin
          (var-set stability-fee (+ (var-get stability-fee) interest-accrued))
          (var-set total-debt (+ total-system-debt interest-accrued))
          (var-set last-accrual-block current-block)
        )
        false
      )
      true
    )
  )
)

;; Accrue interest for a specific user position
(define-private (accrue-position-interest (user principal))
  (let (
    (position (unwrap! (map-get? positions user) 
                      {debt: u0, collateral: u0, last-update-block: stacks-block-height}))
    (debt (get debt position))
    (collateral (get collateral position))
    (last-update (get last-update-block position))
    (blocks-passed (- stacks-block-height last-update))
    (interest-accrued (calculate-interest debt blocks-passed))
    (new-debt (+ debt interest-accrued))
    (updated-position {
      collateral: collateral,
      debt: new-debt,
      last-update-block: stacks-block-height
    })
  )
    (begin
      (if (> blocks-passed u0)
        (map-set positions user updated-position)
        false
      )
      updated-position
    )
  )
)

;;   PRICE ORACLE FUNCTIONS

;; Get current BTC price with expiry validation
(define-read-only (get-current-price)
  (match (var-get btc-price-in-usd)
    price-data (let (
      (price (get price price-data))
      (timestamp (get timestamp price-data))
      (current-timestamp (var-get current-time))
    )
      (if (>= (- current-timestamp timestamp) PRICE_EXPIRY)
        ERR-PRICE-EXPIRED
        (if (<= price u0)
          ERR-PRICE-EXPIRED
          (ok price)
        )
      ))
    ERR-NO-PRICE-DATA)
)

;; CORE PROTOCOL FUNCTIONS

;; Create or expand a collateralized debt position
(define-public (create-position (btc-amount uint) (stable-amount uint))
  (begin
    (asserts! (not (var-get protocol-paused)) ERR-PROTOCOL-PAUSED)
    (asserts! (>= btc-amount u0) ERR-INVALID-AMOUNT)
    (asserts! (>= stable-amount MINIMUM_LOAN_AMOUNT) ERR-MINIMUM-LOAN-REQUIRED)
    
    ;; Get current BTC price with error handling
    (let (
      (btc-price (try! (get-current-price)))
      (user tx-sender)
      (existing-position (map-get? positions user))
    )
      (begin
        ;; Update global interest accrual
        (accrue-global-interest)
        
        ;; Handle existing position or create new one
        (let (
          (current-position 
            (if (is-some existing-position)
              (accrue-position-interest user)
              {collateral: u0, debt: u0, last-update-block: stacks-block-height}
            )
          )
        )
          ;; Calculate new position totals
          (let (
            (old-collateral (get collateral current-position))
            (old-debt (get debt current-position))
            (new-collateral (+ old-collateral btc-amount))
            (new-debt (+ old-debt stable-amount))
            (min-required-collateral (required-collateral new-debt btc-price))
          )
            (begin
              ;; Validate collateralization ratio
              (asserts! (>= (collateral-value new-collateral btc-price) min-required-collateral) 
                       ERR-INSUFFICIENT-COLLATERAL)
              
              ;; Update user position
              (map-set positions user {
                collateral: new-collateral,
                debt: new-debt,
                last-update-block: stacks-block-height
              })
              
              ;; Update protocol totals
              (var-set total-collateral (+ (var-get total-collateral) btc-amount))
              (var-set total-debt (+ (var-get total-debt) stable-amount))
              
              ;; Mint stablecoins to user
              (ft-mint? stable-usd stable-amount user)
            )
          )
        )
      )
    )
  )
)