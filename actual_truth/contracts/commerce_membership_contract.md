# COMMERCE MEMBERSHIP CONTRACT

## STATUS

ACTIVE

This contract defines the canonical commerce truth for launch purchase authority and membership purchase/app-entry state.
This contract operates under `SYSTEM_LAWS.md`.

## 1. CONTRACT LAW

- Purchase authority is owned only by `app.orders` and `app.payments`.
- Membership app-entry state is owned only by `app.memberships`.
- Membership purchase is a purchase flow and therefore MUST create an order.
- Membership MUST NOT exist as a separate purchase authority.
- Course purchase and membership purchase use separate canonical initiation entrypoints.
- Stripe webhook completion is the only canonical payment-confirmation path.

## 2. AUTHORITY MODEL

- `app.orders` owns purchase identity and lifecycle for all paid launch commerce flows.
- `app.payments` owns payment-provider settlement records tied to orders.
- `app.memberships` owns app-entry state only.
- `app.memberships` does not own purchase truth.
- A membership row is not proof of purchase without an order/payment trail.

Protected course-access state is outside this contract and is owned only by `course_access_contract.md`.

## 3. CANONICAL LAUNCH ENTRYPOINTS

- Course purchase initiation: `POST /api/checkout/create`
- Membership purchase initiation: `POST /api/billing/create-subscription`
- Stripe webhook completion: `POST /api/stripe/webhook`

Entrypoint responsibilities:

- `POST /api/checkout/create` initiates paid course purchase only.
- `POST /api/billing/create-subscription` initiates membership purchase only.
- `POST /api/stripe/webhook` confirms payment and applies post-payment mutations.

## 4. COURSE PURCHASE FLOW

1. Client calls `POST /api/checkout/create`.
2. Backend validates the course purchase request.
3. Backend resolves the course and Stripe price.
4. Backend creates a pending order in `app.orders`.
5. Backend creates a Stripe checkout session.
6. Backend stores Stripe checkout references on the order.
7. Backend returns checkout session data to the client.
8. Stripe sends the completion event to `POST /api/stripe/webhook`.
9. Webhook marks the order as paid.
10. Webhook records payment in `app.payments`.
11. Webhook creates canonical course-access state under `course_access_contract.md`.
12. Membership is not changed by the course purchase flow.

## 5. MEMBERSHIP PURCHASE FLOW

1. Client calls `POST /api/billing/create-subscription`.
2. Backend validates the membership purchase request.
3. Backend resolves the membership Stripe price.
4. Backend creates a pending order in `app.orders`.
5. Backend creates a Stripe subscription checkout session.
6. Backend stores order linkage in Stripe metadata.
7. Backend writes or upserts `app.memberships` as `incomplete`.
8. Backend returns checkout session data to the client.
9. Stripe sends subscription and invoice events to `POST /api/stripe/webhook`.
10. Webhook resolves the event back to the membership purchase order.
11. Webhook marks the order as paid.
12. Webhook records payment in `app.payments`.
13. Webhook updates `app.memberships` to the canonical membership state.

## 6. MEMBERSHIP ALIGNMENT DECISION

- Membership MUST create order.
- Membership MUST NOT be a separate non-order purchase authority.
- The canonical purchase trail for membership is:
  - `app.orders` for purchase identity and state
  - `app.payments` for payment settlement
  - `app.memberships` for resulting app-entry state
- Any membership flow that creates or updates membership without an order-backed purchase trail is non-canonical.

## 7. MEMBERSHIP SOURCE LAW

Membership must always have an explicit source.

Allowed sources:

- purchase
- coupon
- invite

Rules:

- purchase MUST create an order
- purchase MAY include a trial period
- trial via Stripe is still a purchase and MUST have an order
- non-purchase sources MUST NOT create an order
- all memberships MUST include explicit source metadata
- implicit membership creation is forbidden

## 8. FORBIDDEN PATTERNS

- A single checkout endpoint serving both course and membership via a `type` switch.
- Service checkout logic inside canonical launch commerce entrypoints.
- Membership purchase without order creation.
- Membership as standalone purchase authority.
- Webhook flows that update membership without resolving purchase authority through orders/payments.
- Webhook flows that create fallback purchase authority outside the canonical order path.
- Duplicate membership initiation entrypoints that express the same purchase meaning.
- Treating `subscription` as the canonical runtime authority term.
- Treating session-status, portal, or cancellation surfaces as launch purchase entrypoints.

## 9. FRONTEND ALIGNMENT TARGET

- Frontend must use `POST /api/checkout/create` only for paid course purchase.
- Frontend must use `POST /api/billing/create-subscription` only for membership purchase.
- Frontend must never use `POST /api/checkout/create` for membership purchase.
- Frontend must never use `POST /api/checkout/create` for service purchase in launch scope.
- Frontend must treat `POST /api/stripe/webhook` as backend-only.
- Frontend must not depend on polymorphic request bodies.
- Frontend course purchase request shape:
  - `{ "slug": string }`
- Frontend membership purchase request shape:
  - `{ "interval": "month" | "year" }`
- Frontend course purchase response shape:
  - `{ "url": string, "session_id": string, "order_id": string }`
- Frontend membership purchase response shape:
  - `{ "url": string, "session_id": string, "order_id": string }`
- All checkout responses MUST follow the same response shape regardless of purchase type.

## 10. IMPLEMENTATION DRIFT OUTSIDE CONTRACT

- The canonical launch commerce routes are not currently mounted in `backend/app/main.py`.
- `POST /api/checkout/create` is still polymorphic in the current repo schema and service layer.
- `POST /api/billing/create-subscription` currently creates membership without creating an order.
- `POST /api/billing/create-checkout-session` still exists as a duplicate membership initiation path.
- `POST /api/stripe/webhook` currently handles broader non-launch branches beyond the locked launch contract.
- Current membership webhook processing updates `app.memberships` but does not yet settle membership purchase orders.

## 11. FINAL ASSERTION

- This contract is the canonical launch commerce and membership purchase truth.
- It is lockable as a contract artifact.
- Contract truth and implementation drift are intentionally separated.
