# API Mapping — Paytm Modules for Make

For **paste-ready mappable-parameter lists** and **communication JSON** per module (Make UI), see **[make-ui-paste-by-module.md](./make-ui-paste-by-module.md)** — aligned with `app/modules/*.jsonc`.

---

## Architecture

All 14 modules call the **merchant-adapter signing proxy**, not Paytm directly.
The proxy handles Paytm's AES-128-CBC checksum — IML cannot compute it.

```
Make module  →  proxy /make/{functionName}?mid=XXX  →  Paytm API
              [HMAC-SHA256 inbound auth]           [AES checksum outbound]
```

**Connection fields:**

- `merchantId` — Paytm MID, passed as `?mid=` query param
- `keySecret` — HMAC signing key (password, never logged)
- `baseUrl` — proxy base URL (select: Production / Staging)

**Make UI:** [make-connection-paytm.md](./make-connection-paytm.md) — build the connection from [`app/connections/paytm.jsonc`](../app/connections/paytm.jsonc).

**Proxy base URLs:**


| Environment | Proxy URL                                            |
| ----------- | ---------------------------------------------------- |
| Production  | `https://paytm-make-proxy.paytmpayments.com`         |
| Staging     | `https://paytm-make-proxy-staging.paytmpayments.com` |


**Module request pattern (all modules follow this):**

```jsonc
{
    "url": "{{connection.baseUrl}}/make/{functionName}?mid={{connection.merchantId}}",
    "method": "POST",
    "headers": {
        "Content-Type": "application/json",
        "X-Signature": "{{sha256(createJSON(body); connection.keySecret)}}"
    },
    "body": {
        "requestId": "{{uuid()}}",
        "timestamp": "{{toTimestamp(now)}}",
        "params": { ...module-specific params... }
    }
}
```

---

## Module List

### Payment Link


| #   | Operation                   | Make Module                | Make Type  | Paytm Endpoint                | Auth     | Annotation      | Status     |
| --- | --------------------------- | -------------------------- | ---------- | ----------------------------- | -------- | --------------- | ---------- |
| 1   | Create Payment Link         | `createPaymentLink`        | **Action** | `POST /link/create`           | Checksum | destructiveHint | 🔲 Pending |
| 2   | Fetch Payment Links         | `fetchPaymentLinks`        | **Search** | `POST /link/fetch`            | Checksum | readOnlyHint    | 🔲 Pending |
| 3   | Fetch Transactions for Link | `fetchTransactionsForLink` | **Search** | `POST /link/fetchTransaction` | Checksum | readOnlyHint    | 🔲 Pending |


### Order


| #   | Operation        | Make Module      | Make Type  | Paytm Endpoint                                 | Auth       | Annotation   | Status     |
| --- | ---------------- | ---------------- | ---------- | ---------------------------------------------- | ---------- | ------------ | ---------- |
| 4   | Fetch Order List | `fetchOrderList` | **Search** | `POST /merchant-passbook/search/list/order/v2` | Checksum   | readOnlyHint | 🔲 Pending |
| 5   | Order Detail     | `orderDetail`    | **Action** | RTDD via proxy                                 | Settlement | readOnlyHint | 🔲 Pending |


### Refund


| #   | Operation           | Make Module         | Make Type  | Paytm Endpoint                              | Auth     | Annotation      | Status     |
| --- | ------------------- | ------------------- | ---------- | ------------------------------------------- | -------- | --------------- | ---------- |
| 6   | Initiate Refund     | `initiateRefund`    | **Action** | `POST /refund/apply`                        | Checksum | destructiveHint | 🔲 Pending |
| 7   | Check Refund Status | `checkRefundStatus` | **Action** | `POST /v2/refund/status`                    | Checksum | readOnlyHint    | 🔲 Pending |
| 8   | Fetch Refund List   | `fetchRefundList`   | **Search** | `POST /merchant-passbook/api/v1/refundList` | Checksum | readOnlyHint    | 🔲 Pending |


### Settlement


| #   | Operation                   | Make Module               | Make Type  | Paytm Endpoint | Auth       | Annotation   | Status     |
| --- | --------------------------- | ------------------------- | ---------- | -------------- | ---------- | ------------ | ---------- |
| 9   | Settlement Bill List        | `settlementBillList`      | **Search** | RTDD via proxy | Settlement | readOnlyHint | 🔲 Pending |
| 10  | Settlement Txn List by Date | `settlementTxnListByDate` | **Search** | RTDD via proxy | Settlement | readOnlyHint | 🔲 Pending |


### Subscription


| #   | Operation                   | Make Module               | Make Type  | Paytm Endpoint                                  | Auth     | Annotation      | Status     |
| --- | --------------------------- | ------------------------- | ---------- | ----------------------------------------------- | -------- | --------------- | ---------- |
| 11  | Fetch Subscription Status   | `fetchSubscriptionStatus` | **Action** | `POST /subscription/subscription/checkStatus`   | Checksum | readOnlyHint    | 🔲 Pending |
| 12  | Pause / Resume Subscription | `pauseResumeSubscription` | **Action** | `POST /subscription/subscription/status/modify` | Checksum | destructiveHint | 🔲 Pending |
| 13  | Cancel Subscription         | `cancelSubscription`      | **Action** | `POST /subscription/subscription/cancel`        | Checksum | destructiveHint | 🔲 Pending |


### Universal (required by Make platform)


| #   | Module        | Make Type     | Purpose                                                                                                                                                       | Status     |
| --- | ------------- | ------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------- | ---------- |
| 14  | `makeApiCall` | **Universal** | Custom Paytm API call for endpoints not covered by modules 1–13. Accepts a relative path — proxy prepends the Paytm base URL. Absolute URLs rejected by Make. | 🔲 Pending |


---

## Auth Mechanisms

### 1. Checksum — standard Paytm APIs (modules 1–4, 6–8, 11–13)

Paytm expects:

```json
{
  "body": { "mid": "...", ...params },
  "head": { "tokenType": "AES", "signature": "<checksum>", "channelId": "WEB" }
}
```

Checksum = `AES-128-CBC(SHA256(sorted_values + salt) + salt, keySecret, IV="@@@@&&&&####$$")`.
**Cannot be computed in Make IML.** Handled entirely by the proxy.

### 2. Settlement / RTDD Envelope (modules 5, 9, 10)

```json
{ "request": { "body": {...}, "head": {...} }, "signature": "<checksum>" }
```

Built by the proxy (`buildRtddSignedDownstreamBody`). Also cannot be done in IML.

### 3. Inbound — Make → Proxy (all modules)

```
X-Signature: HMAC-SHA256(createJSON(body), keySecret)
```

This IS computable in IML via `{{sha256(createJSON(body); connection.keySecret)}}`.
The proxy verifies this before forwarding any request.

---

## Make Module Type Reference


| Type      | When to use                                            | JSONC `"type"` value |
| --------- | ------------------------------------------------------ | -------------------- |
| Action    | Single-item response — create, read one, write, delete | `"action"`           |
| Search    | Multi-item / list response                             | `"search"`           |
| Universal | Custom API call — one per app, required by Make        | `"universal"`        |


> Make will reject the app submission if the Universal module is missing, or if it uses an absolute URL.
> The Universal module must accept a **relative path** — the proxy prepends the base URL.

---

## Parameter Mapping

### 1. createPaymentLink — Action


| Param             | Type                     | Required               | Default |
| ----------------- | ------------------------ | ---------------------- | ------- |
| `linkName`        | text                     | yes                    | —       |
| `linkDescription` | text                     | yes                    | —       |
| `linkType`        | select (FIXED / GENERIC) | yes                    | —       |
| `amount`          | number                   | no (required if FIXED) | —       |
| `customerName`    | text                     | no                     | —       |
| `customerEmail`   | text                     | no                     | —       |
| `customerMobile`  | text                     | no                     | —       |
| `expiryDate`      | date                     | no                     | —       |
| `sendSms`         | boolean                  | no                     | —       |
| `sendEmail`       | boolean                  | no                     | —       |


### 2. fetchPaymentLinks — Search


| Param               | Type                     | Required | Default |
| ------------------- | ------------------------ | -------- | ------- |
| `fromDate`          | date                     | no       | —       |
| `toDate`            | date                     | no       | —       |
| `linkId`            | text                     | no       | —       |
| `merchantRequestId` | text                     | no       | —       |
| `linkType`          | select (FIXED / GENERIC) | no       | —       |
| `paymentStatus`     | select                   | no       | —       |
| `isActive`          | boolean                  | no       | —       |


### 3. fetchTransactionsForLink — Search


| Param             | Type    | Required | Default |
| ----------------- | ------- | -------- | ------- |
| `linkId`          | text    | yes      | —       |
| `searchStartDate` | date    | no       | —       |
| `searchEndDate`   | date    | no       | —       |
| `fetchAllTxns`    | boolean | no       | —       |


### 4. fetchOrderList — Search


| Param               | Type    | Required | Default       |
| ------------------- | ------- | -------- | ------------- |
| `startDate`         | date    | yes      | —             |
| `endDate`           | date    | yes      | —             |
| `orderSearchStatus` | select  | no       | `ALL`         |
| `orderSearchType`   | select  | no       | `TRANSACTION` |
| `pageNumber`        | integer | no       | `1`           |
| `pageSize`          | integer | no       | `20`          |
| `merchantOrderId`   | text    | no       | —             |
| `payMode`           | text    | no       | —             |


### 5. orderDetail — Action (RTDD / Settlement envelope)


| Param                 | Type    | Required | Default | Notes                                |
| --------------------- | ------- | -------- | ------- | ------------------------------------ |
| `bizOrderId`          | text    | yes      | —       | Transaction-level ID — not `orderId` |
| `isSettlementInfo`    | boolean | no       | `false` | Include settlement breakdown         |
| `excludePaymentsData` | boolean | no       | `false` | Omit payment details                 |


### 6. initiateRefund — Action


| Param          | Type   | Required | Default |
| -------------- | ------ | -------- | ------- |
| `orderId`      | text   | yes      | —       |
| `txnId`        | text   | yes      | —       |
| `refId`        | text   | yes      | —       |
| `refundAmount` | number | yes      | —       |
| `comments`     | text   | no       | —       |


### 7. checkRefundStatus — Action


| Param     | Type | Required | Default |
| --------- | ---- | -------- | ------- |
| `orderId` | text | yes      | —       |
| `refId`   | text | yes      | —       |


### 8. fetchRefundList — Search


| Param       | Type    | Required | Default |
| ----------- | ------- | -------- | ------- |
| `startDate` | date    | yes      | —       |
| `endDate`   | date    | yes      | —       |
| `pageNum`   | integer | no       | `1`     |
| `pageSize`  | integer | no       | `20`    |
| `isSort`    | boolean | no       | `true`  |


### 9. settlementBillList — Search (RTDD / Settlement envelope)


| Param                 | Type     | Required | Default | Notes                                                                |
| --------------------- | -------- | -------- | ------- | -------------------------------------------------------------------- |
| `settlementStartTime` | datetime | yes      | —       | Not `startDate`                                                      |
| `settlementEndTime`   | datetime | yes      | —       | Not `endDate`                                                        |
| `pageNum`             | integer  | no       | `1`     | —                                                                    |
| `pageSize`            | integer  | no       | `20`    | Max 50                                                               |
| `settlementBillId`    | text     | no       | —       | Payout ID filter                                                     |
| `settleStatus`        | select   | no       | —       | BANK_INITIATED / PAYOUT_SETTLED / PAYOUT_UNSETTLED / WAIT_FOR_SETTLE |
| `utrNo`               | text     | no       | —       | UTR number filter                                                    |


### 10. settlementTxnListByDate — Search (RTDD / Settlement envelope)


| Param               | Type     | Required | Default |
| ------------------- | -------- | -------- | ------- |
| `startDate`         | datetime | yes      | —       |
| `endDate`           | datetime | yes      | —       |
| `pageNum`           | integer  | no       | `1`     |
| `pageSize`          | integer  | no       | `20`    |
| `settlementOrderId` | text     | no       | —       |


### 11. fetchSubscriptionStatus — Action


| Param     | Type | Required | Default |
| --------- | ---- | -------- | ------- |
| `subsId`  | text | no       | —       |
| `orderId` | text | no       | —       |
| `linkId`  | text | no       | —       |
| `custId`  | text | no       | —       |


### 12. pauseResumeSubscription — Action


| Param    | Type                        | Required | Default |
| -------- | --------------------------- | -------- | ------- |
| `subsId` | text                        | yes      | —       |
| `status` | select (SUSPENDED / ACTIVE) | yes      | —       |


### 13. cancelSubscription — Action


| Param    | Type | Required | Default |
| -------- | ---- | -------- | ------- |
| `subsId` | text | yes      | —       |


### 14. makeApiCall — Universal


| Param     | Type       | Required | Notes                                                                                                   |
| --------- | ---------- | -------- | ------------------------------------------------------------------------------------------------------- |
| `method`  | select     | yes      | GET / POST / PUT / PATCH / DELETE                                                                       |
| `url`     | text       | yes      | Relative path only — e.g. `/v2/some/endpoint`. Proxy prepends base URL. Absolute URLs rejected by Make. |
| `headers` | collection | no       | Additional headers                                                                                      |
| `body`    | any        | no       | Raw JSON body                                                                                           |


