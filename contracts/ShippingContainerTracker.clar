;; Shipping Container Tracker Smart Contract
;; Real-time container location and condition monitoring with automated payments

;; Constants
(define-constant contract-owner tx-sender)
(define-constant err-owner-only (err u100))
(define-constant err-not-authorized (err u101))
(define-constant err-container-not-found (err u102))
(define-constant err-invalid-data (err u103))
(define-constant err-payment-failed (err u104))
(define-constant err-container-exists (err u105))

;; Container status constants
(define-constant status-in-transit u1)
(define-constant status-delivered u2)
(define-constant status-delayed u3)
(define-constant status-damaged u4)

;; Data structures
(define-map containers
  { container-id: (string-ascii 20) }
  {
    owner: principal,
    current-location: (string-ascii 50),
    destination: (string-ascii 50),
    status: uint,
    temperature: int,
    humidity: uint,
    last-update: uint,
    payment-amount: uint,
    is-delivered: bool
  }
)

(define-map authorized-updaters principal bool)

;; Contract variables
(define-data-var total-containers uint u0)

;; Initialize authorized updaters (IoT devices, logistics partners)
(define-public (add-authorized-updater (updater principal))
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (map-set authorized-updaters updater true)
    (ok true)
  )
)

;; Function 1: Update Container Status and Location
;; This function allows authorized IoT devices or logistics partners to update container information
(define-public (update-container-status 
    (container-id (string-ascii 20))
    (new-location (string-ascii 50))
    (new-status uint)
    (temperature int)
    (humidity uint))
  (let (
    (container (unwrap! (map-get? containers {container-id: container-id}) err-container-not-found))
    (is-authorized (default-to false (map-get? authorized-updaters tx-sender)))
  )
    ;; Check authorization
    (asserts! (or (is-eq tx-sender contract-owner) is-authorized) err-not-authorized)
    
    ;; Validate status
    (asserts! (and (>= new-status u1) (<= new-status u4)) err-invalid-data)
    
    ;; Update container information
    (map-set containers {container-id: container-id}
      (merge container {
        current-location: new-location,
        status: new-status,
        temperature: temperature,
        humidity: humidity,
        last-update: stacks-block-height,
        is-delivered: (is-eq new-status status-delivered)
      })
    )
    
 
    
    (print {
      event: "container-updated",
      container-id: container-id,
      location: new-location,
      status: new-status,
      timestamp: stacks-block-height
    })
    
    (ok true)
  )
)

;; Function 2: Process Automated Payment on Delivery
;; This function handles automated payments when a container reaches its destination
(define-public (process-delivery-payment (container-id (string-ascii 20)))
  (let (
    (container (unwrap! (map-get? containers {container-id: container-id}) err-container-not-found))
    (payment-amount (get payment-amount container))
    (container-owner (get owner container))
  )
    ;; Check if container is delivered and payment hasn't been processed
    (asserts! (get is-delivered container) err-invalid-data)
    
    ;; Transfer payment to container owner
    (if (> payment-amount u0)
      (begin
        (try! (stx-transfer? payment-amount (as-contract tx-sender) container-owner))
        (print {
          event: "payment-processed",
          container-id: container-id,
          amount: payment-amount,
          recipient: container-owner,
          timestamp: stacks-block-height,
        })
        (ok true)
      )
      (ok true)
    )
  )
)

;; Register a new container
(define-public (register-container
    (container-id (string-ascii 20))
    (destination (string-ascii 50))
    (payment-amount uint))
  (begin
    ;; Check if container already exists
    (asserts! (is-none (map-get? containers {container-id: container-id})) err-container-exists)
    
    ;; Register new container
    (map-set containers {container-id: container-id}
      {
        owner: tx-sender,
        current-location: "Origin Port",
        destination: destination,
        status: status-in-transit,
        temperature: 20,
        humidity: u50,
        last-update: stacks-block-height,
        payment-amount: payment-amount,
        is-delivered: false
      }
    )
    
    (var-set total-containers (+ (var-get total-containers) u1))
    
    (print {
      event: "container-registered",
      container-id: container-id,
      owner: tx-sender,
      destination: destination
    })
    
    (ok true)
  )
)

;; Read-only functions
(define-read-only (get-container-info (container-id (string-ascii 20)))
  (ok (map-get? containers {container-id: container-id}))
)

(define-read-only (get-total-containers)
  (ok (var-get total-containers))
)

(define-read-only (is-authorized-updater (updater principal))
  (ok (default-to false (map-get? authorized-updaters updater)))
)