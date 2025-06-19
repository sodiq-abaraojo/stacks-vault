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
