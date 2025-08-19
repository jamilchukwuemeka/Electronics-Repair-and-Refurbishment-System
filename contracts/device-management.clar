;; Electronics Repair System - Device Management Contract
;; Manages device registration, tracking, and diagnostics

;; Constants
(define-constant CONTRACT-OWNER tx-sender)
(define-constant ERR-NOT-AUTHORIZED (err u100))
(define-constant ERR-DEVICE-NOT-FOUND (err u101))
(define-constant ERR-DEVICE-ALREADY-EXISTS (err u102))
(define-constant ERR-INVALID-INPUT (err u103))
(define-constant ERR-INVALID-STATUS (err u104))

;; Device Types
(define-constant DEVICE-TYPE-SMARTPHONE u1)
(define-constant DEVICE-TYPE-LAPTOP u2)
(define-constant DEVICE-TYPE-TABLET u3)
(define-constant DEVICE-TYPE-DESKTOP u4)
(define-constant DEVICE-TYPE-GAMING-CONSOLE u5)
(define-constant DEVICE-TYPE-SMARTWATCH u6)
(define-constant DEVICE-TYPE-OTHER u7)

;; Device Status
(define-constant STATUS-REGISTERED u1)
(define-constant STATUS-DIAGNOSTIC u2)
(define-constant STATUS-REPAIR-NEEDED u3)
(define-constant STATUS-IN-REPAIR u4)
(define-constant STATUS-COMPLETED u5)
(define-constant STATUS-RECYCLING u6)

;; Data Structures
(define-map devices
  { device-id: uint }
  {
    owner: principal,
    device-type: uint,
    brand: (string-ascii 50),
    model: (string-ascii 50),
    serial-number: (string-ascii 100),
    manufacture-year: uint,
    condition-rating: uint,
    status: uint,
    registration-date: uint,
    last-updated: uint,
    estimated-value: uint
  }
)

(define-map device-diagnostics
  { device-id: uint }
  {
    technician: principal,
    diagnostic-date: uint,
    issues-found: (list 10 (string-ascii 100)),
    severity-level: uint,
    repair-estimate: uint,
    time-estimate-hours: uint,
    parts-needed: (list 20 uint),
    diagnostic-notes: (string-ascii 500)
  }
)

(define-map device-history
  { device-id: uint, entry-id: uint }
  {
    timestamp: uint,
    action: (string-ascii 50),
    technician: principal,
    notes: (string-ascii 200),
    status-change: uint
  }
)

;; Data Variables
(define-data-var next-device-id uint u1)
(define-data-var next-entry-id uint u1)
(define-data-var total-devices uint u0)

;; Authorization
(define-map authorized-technicians principal bool)
(define-map authorized-admins principal bool)

;; Initialize contract owner as admin
(map-set authorized-admins CONTRACT-OWNER true)

;; Private Functions
(define-private (is-authorized-admin (user principal))
  (default-to false (map-get? authorized-admins user))
)

(define-private (is-authorized-technician (user principal))
  (default-to false (map-get? authorized-technicians user))
)

(define-private (is-valid-device-type (device-type uint))
  (and (>= device-type u1) (<= device-type u7))
)

(define-private (is-valid-status (status uint))
  (and (>= status u1) (<= status u6))
)

(define-private (is-valid-condition-rating (rating uint))
  (and (>= rating u1) (<= rating u10))
)

(define-private (add-history-entry (device-id uint) (action (string-ascii 50)) (notes (string-ascii 200)) (status-change uint))
  (let ((entry-id (var-get next-entry-id)))
    (map-set device-history
      { device-id: device-id, entry-id: entry-id }
      {
        timestamp: block-height,
        action: action,
        technician: tx-sender,
        notes: notes,
        status-change: status-change
      }
    )
    (var-set next-entry-id (+ entry-id u1))
    (ok entry-id)
  )
)

;; Public Functions

;; Admin Functions
(define-public (add-authorized-technician (technician principal))
  (begin
    (asserts! (is-authorized-admin tx-sender) ERR-NOT-AUTHORIZED)
    (ok (map-set authorized-technicians technician true))
  )
)

(define-public (remove-authorized-technician (technician principal))
  (begin
    (asserts! (is-authorized-admin tx-sender) ERR-NOT-AUTHORIZED)
    (ok (map-delete authorized-technicians technician))
  )
)

(define-public (add-authorized-admin (admin principal))
  (begin
    (asserts! (is-authorized-admin tx-sender) ERR-NOT-AUTHORIZED)
    (ok (map-set authorized-admins admin true))
  )
)

;; Device Registration
(define-public (register-device
  (device-type uint)
  (brand (string-ascii 50))
  (model (string-ascii 50))
  (serial-number (string-ascii 100))
  (manufacture-year uint)
  (condition-rating uint)
  (estimated-value uint))
  (let ((device-id (var-get next-device-id)))
    (asserts! (is-valid-device-type device-type) ERR-INVALID-INPUT)
    (asserts! (is-valid-condition-rating condition-rating) ERR-INVALID-INPUT)
    (asserts! (> manufacture-year u1990) ERR-INVALID-INPUT)
    (asserts! (<= manufacture-year u2030) ERR-INVALID-INPUT)
    (asserts! (> (len brand) u0) ERR-INVALID-INPUT)
    (asserts! (> (len model) u0) ERR-INVALID-INPUT)
    (asserts! (> (len serial-number) u0) ERR-INVALID-INPUT)

    (map-set devices
      { device-id: device-id }
      {
        owner: tx-sender,
        device-type: device-type,
        brand: brand,
        model: model,
        serial-number: serial-number,
        manufacture-year: manufacture-year,
        condition-rating: condition-rating,
        status: STATUS-REGISTERED,
        registration-date: block-height,
        last-updated: block-height,
        estimated-value: estimated-value
      }
    )

    (unwrap! (add-history-entry device-id "REGISTERED" "Device registered in system" STATUS-REGISTERED) ERR-INVALID-INPUT)

    (var-set next-device-id (+ device-id u1))
    (var-set total-devices (+ (var-get total-devices) u1))

    (print { event: "device-registered", device-id: device-id, owner: tx-sender })
    (ok device-id)
  )
)

;; Device Status Updates
(define-public (update-device-status (device-id uint) (new-status uint) (notes (string-ascii 200)))
  (let ((device (unwrap! (map-get? devices { device-id: device-id }) ERR-DEVICE-NOT-FOUND)))
    (asserts! (or (is-authorized-technician tx-sender) (is-eq tx-sender (get owner device))) ERR-NOT-AUTHORIZED)
    (asserts! (is-valid-status new-status) ERR-INVALID-STATUS)

    (map-set devices
      { device-id: device-id }
      (merge device { status: new-status, last-updated: block-height })
    )

    (unwrap! (add-history-entry device-id "STATUS_UPDATE" notes new-status) ERR-INVALID-INPUT)

    (print { event: "status-updated", device-id: device-id, new-status: new-status })
    (ok true)
  )
)

;; Diagnostic Functions
(define-public (record-diagnostic
  (device-id uint)
  (issues-found (list 10 (string-ascii 100)))
  (severity-level uint)
  (repair-estimate uint)
  (time-estimate-hours uint)
  (parts-needed (list 20 uint))
  (diagnostic-notes (string-ascii 500)))
  (let ((device (unwrap! (map-get? devices { device-id: device-id }) ERR-DEVICE-NOT-FOUND)))
    (asserts! (is-authorized-technician tx-sender) ERR-NOT-AUTHORIZED)
    (asserts! (>= severity-level u1) ERR-INVALID-INPUT)
    (asserts! (<= severity-level u5) ERR-INVALID-INPUT)

    (map-set device-diagnostics
      { device-id: device-id }
      {
        technician: tx-sender,
        diagnostic-date: block-height,
        issues-found: issues-found,
        severity-level: severity-level,
        repair-estimate: repair-estimate,
        time-estimate-hours: time-estimate-hours,
        parts-needed: parts-needed,
        diagnostic-notes: diagnostic-notes
      }
    )

    (unwrap! (update-device-status device-id STATUS-DIAGNOSTIC "Diagnostic completed") ERR-INVALID-INPUT)
    (unwrap! (add-history-entry device-id "DIAGNOSTIC" "Diagnostic assessment completed" STATUS-DIAGNOSTIC) ERR-INVALID-INPUT)

    (print { event: "diagnostic-recorded", device-id: device-id, technician: tx-sender, severity: severity-level })
    (ok true)
  )
)

;; Read-only Functions
(define-read-only (get-device (device-id uint))
  (map-get? devices { device-id: device-id })
)

(define-read-only (get-device-diagnostic (device-id uint))
  (map-get? device-diagnostics { device-id: device-id })
)

(define-read-only (get-device-history-entry (device-id uint) (entry-id uint))
  (map-get? device-history { device-id: device-id, entry-id: entry-id })
)

(define-read-only (get-total-devices)
  (var-get total-devices)
)

(define-read-only (get-next-device-id)
  (var-get next-device-id)
)

(define-read-only (is-technician-authorized (technician principal))
  (is-authorized-technician technician)
)

(define-read-only (is-admin-authorized (admin principal))
  (is-authorized-admin admin)
)

(define-read-only (get-devices-by-owner (owner principal))
  ;; This would require iteration in a real implementation
  ;; For now, returns a placeholder response
  (ok "Use off-chain indexing for owner queries")
)

(define-read-only (get-devices-by-status (status uint))
  ;; This would require iteration in a real implementation
  ;; For now, returns a placeholder response
  (ok "Use off-chain indexing for status queries")
)
