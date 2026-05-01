# API Mapping — n8n v1.6.1 → Make

Source of truth: https://github.com/paytm/n8n-nodes-paytm

---

## Module List

### Payment Link

| # | n8n Operation | Make Module | Make Type | Paytm Endpoint | Auth | Annotation | Status |
|---|---------------|-------------|-----------|----------------|------|------------|--------|
| 1 | Create Payment Link | `createPaymentLink` | **Action** | `POST /link/create` | Checksum | destructiveHint | 🔲 Pending |
| 2 | Fetch Payment Links | `fetchPaymentLinks` | **Search** | `POST /link/fetch` | Checksum | readOnlyHint | 🔲 Pending |
| 3 | Fetch Transactions for Link | `fetchTransactionsForLink` | **Search** | `POST /link/fetchTransaction` | Checksum | readOnlyHint | 🔲 Pending |

### Order

| # | n8n Operation | Make Module | Make Type | Paytm Endpoint | Auth | Annotation | Status |
|---|---------------|-------------|-----------|----------------|------|------------|--------|
| 4 | Fetch Order List | `fetchOrderList` | **Search** | `POST /merchant-passbook/search/list/order/v2` | Checksum | readOnlyHint | ⚠️ Scaffolded — needs proxy + auth envelope fix |
| 5 | Order Detail | `orderDetail` | **Action** | `POST /merchant-adapter/internal/ORDER_DETAIL?mid={mid}` | Settlement | readOnlyHint | 🔲 Pending |

### Refund

| # | n8n Operation | Make Module | Make Type | Paytm Endpoint | Auth | Annotation | Status |
|---|---------------|-------------|-----------|----------------|------|------------|--------|
| 6 | Initiate Refund | `initiateRefund` | **Action** | `POST /refund/apply` | Checksum | destructiveHint | 🔲 Pending |
| 7 | Check Refund Status | `checkRefundStatus` | **Action** | `POST /v2/refund/status` | Checksum | readOnlyHint | 🔲 Pending |
| 8 | Fetch Refund List | `fetchRefundList` | **Search** | `POST /merchant-passbook/api/v1/refundList` | Checksum | readOnlyHint | 🔲 Pending |

### Settlement

| # | n8n Operation | Make Module | Make Type | Paytm Endpoint | Auth | Annotation | Status |
|---|---------------|-------------|-----------|----------------|------|------------|--------|
| 9 | Settlement Bill List | `settlementBillList` | **Search** | `POST /merchant-adapter/internal/BILL_LIST?mid={mid}` | Settlement | readOnlyHint | 🔲 Pending |
| 10 | Settlement Txn List by Date | `settlementTxnListByDate` | **Search** | `POST /merchant-adapter/internal/TxnListByDate?mid={mid}` | Settlement | readOnlyHint | 🔲 Pending |

### Subscription

| # | n8n Operation | Make Module | Make Type | Paytm Endpoint | Auth | Annotation | Status |
|---|---------------|-------------|-----------|----------------|------|------------|--------|
| 11 | Fetch Subscription Status | `fetchSubscriptionStatus` | **Action** | `POST /subscription/subscription/checkStatus` | Checksum | readOnlyHint | 🔲 Pending |
| 12 | Pause / Resume Subscription | `pauseResumeSubscription` | **Action** | `POST /subscription/subscription/status/modify` | Checksum | destructiveHint | 🔲 Pending |
| 13 | Cancel Subscription | `cancelSubscription` | **Action** | `POST /subscription/subscription/cancel` | Checksum | destructiveHint | 🔲 Pending |

### Universal (required by Make platform)

| # | Module | Make Type | Purpose | Status |
|---|--------|-----------|---------|--------|
| 14 | `makeApiCall` | **Universal** | Custom Paytm API call for endpoints not covered by modules 1–13. Must use a relative path routed through the signing proxy. | 🔲 Pending |

---

## Make Module Type Reference

| Type | When to use | JSONC `"type"` value |
|------|-------------|----------------------|
| Action | Single-item response — create, read one, write, delete | `"action"` |
| Search | Multi-item / list response | `"search"` |
| Universal | Custom API call — one per app, required by Make | `"universal"` |

> Make will reject the app submission if the Universal module is missing, or if it uses an absolute URL
> (a user could redirect requests to their own server to harvest auth tokens). The Universal module
> must accept a **relative path** and the proxy prepends the base URL.

---

## Base URLs (from n8n constants)

| Environment | Paytm Base URL | Proxy Base URL |
|-------------|---------------|----------------|
| Production | `https://secure.paytmpayments.com` | `https://paytm-make-proxy.paytmpayments.com` |
| Staging | `https://securestage.paytmpayments.com` | `https://paytm-make-proxy-staging.paytmpayments.com` |

Make modules call the **proxy**, not Paytm directly. The proxy calls the Paytm base URL.

---

## Auth Mechanisms

### 1. Checksum — Head Envelope (10 modules: 1–3, 4, 6–8, 11–13)

```json
{
  "body": { "mid": "...", "...": "request params" },
  "head": { "tokenType": "AES", "signature": "<checksum>", "channelId": "WEB" }
}
```

Checksum = AES-128-CBC(SHA256(sorted_values + "|" + salt) + salt, keySecret, IV="@@@@&&&&####$$").
Cannot be computed in Make IML — handled entirely by the signing proxy.

### 2. Settlement Envelope (3 modules: 5, 9, 10)

```json
{
  "ipRoleId": "...",
  "...": "request params",
  "signature": "<checksum>",
  "X-PGP-Unique-ID": "<uuid>"
}
```

Built by `settlementUtil.ts` in n8n. Also handled by the signing proxy.

---

## Parameter Mapping (verified against n8n source)

### 1. createPaymentLink — Action

| n8n Param | Make Param | Type | Required | Default |
|-----------|-----------|------|----------|---------|
| `linkName` | `linkName` | text | yes | — |
| `linkDescription` | `linkDescription` | text | yes | — |
| `linkType` | `linkType` | select (FIXED / GENERIC) | yes | — |
| `amount` | `amount` | number | no (required if FIXED) | — |
| `customerName` | `customerName` | text | no | — |
| `customerEmail` | `customerEmail` | text | no | — |
| `customerMobile` | `customerMobile` | text | no | — |
| `expiryDate` | `expiryDate` | date | no | — |
| `sendSms` | `sendSms` | boolean | no | — |
| `sendEmail` | `sendEmail` | boolean | no | — |

### 2. fetchPaymentLinks — Search

| n8n Param | Make Param | Type | Required | Default |
|-----------|-----------|------|----------|---------|
| `fromDate` | `fromDate` | date | no | — |
| `toDate` | `toDate` | date | no | — |
| `linkId` | `linkId` | text | no | — |
| `merchantRequestId` | `merchantRequestId` | text | no | — |
| `linkType` | `linkType` | select (FIXED / GENERIC) | no | — |
| `paymentStatus` | `paymentStatus` | select | no | — |
| `isActive` | `isActive` | boolean | no | — |

### 3. fetchTransactionsForLink — Search

| n8n Param | Make Param | Type | Required | Default |
|-----------|-----------|------|----------|---------|
| `linkId` | `linkId` | text | yes | — |
| `searchStartDate` | `searchStartDate` | date | no | — |
| `searchEndDate` | `searchEndDate` | date | no | — |
| `fetchAllTxns` | `fetchAllTxns` | boolean | no | — |

### 4. fetchOrderList — Search

| n8n Param | Make Param | Type | Required | Default |
|-----------|-----------|------|----------|---------|
| `startDate` | `startDate` | date | yes | — |
| `endDate` | `endDate` | date | yes | — |
| `orderSearchStatus` | `orderSearchStatus` | select | no | `ALL` |
| `orderSearchType` | `orderSearchType` | select | no | `TRANSACTION` |
| `pageNumber` | `pageNumber` | integer | no | `1` |
| `pageSize` | `pageSize` | integer | no | `20` |
| `merchantOrderId` | `merchantOrderId` | text | no | — |
| `payMode` | `payMode` | text | no | — |

### 5. orderDetail — Action (Settlement envelope)

| n8n Param | Make Param | Type | Required | Default | Notes |
|-----------|-----------|------|----------|---------|-------|
| `bizOrderId` | `bizOrderId` | text | yes | — | Transaction-level ID — PRD: "against a transaction ID" |
| `isSettlementInfo` | `isSettlementInfo` | boolean | no | `false` | Include settlement breakdown |
| `excludePaymentsData` | `excludePaymentsData` | boolean | no | `false` | Omit payment details |

> **Correction from earlier mapping:** field is `bizOrderId`, not `orderId`. Verified from n8n source.

### 6. initiateRefund — Action

| n8n Param | Make Param | Type | Required | Default |
|-----------|-----------|------|----------|---------|
| `orderId` | `orderId` | text | yes | — |
| `txnId` | `txnId` | text | yes | — |
| `refId` | `refId` | text | yes | — |
| `refundAmount` | `refundAmount` | number | yes | — |
| `comments` | `comments` | text | no | — |

### 7. checkRefundStatus — Action

| n8n Param | Make Param | Type | Required | Default |
|-----------|-----------|------|----------|---------|
| `orderId` | `orderId` | text | yes | — |
| `refId` | `refId` | text | yes | — |

### 8. fetchRefundList — Search

| n8n Param | Make Param | Type | Required | Default |
|-----------|-----------|------|----------|---------|
| `startDate` | `startDate` | date | yes | — |
| `endDate` | `endDate` | date | yes | — |
| `pageNum` | `pageNum` | integer | no | `1` |
| `pageSize` | `pageSize` | integer | no | `20` |
| `isSort` | `isSort` | boolean | no | `true` |

### 9. settlementBillList — Search (Settlement envelope)

| n8n Param | Make Param | Type | Required | Default | Notes |
|-----------|-----------|------|----------|---------|-------|
| `settlementStartTime` | `settlementStartTime` | datetime | yes | — | Settlement date range start |
| `settlementEndTime` | `settlementEndTime` | datetime | yes | — | Settlement date range end |
| `pageNum` | `pageNum` | integer | no | `1` | — |
| `pageSize` | `pageSize` | integer | no | `20` | Max 50 |
| `settlementBillId` | `settlementBillId` | text | no | — | Payout ID filter |
| `settleStatus` | `settleStatus` | select | no | — | BANK_INITIATED / PAYOUT_SETTLED / PAYOUT_UNSETTLED / WAIT_FOR_SETTLE |
| `utrNo` | `utrNo` | text | no | — | UTR number filter |

> **Correction from earlier mapping:** date fields are `settlementStartTime`/`settlementEndTime`, not generic `startDate`/`endDate`. Verified from n8n source.

### 10. settlementTxnListByDate — Search (Settlement envelope)

| n8n Param | Make Param | Type | Required | Default |
|-----------|-----------|------|----------|---------|
| `startDate` | `startDate` | datetime | yes | — |
| `endDate` | `endDate` | datetime | yes | — |
| `pageNum` | `pageNum` | integer | no | `1` |
| `pageSize` | `pageSize` | integer | no | `20` |
| `settlementOrderId` | `settlementOrderId` | text | no | — |

### 11. fetchSubscriptionStatus — Action

| n8n Param | Make Param | Type | Required | Default |
|-----------|-----------|------|----------|---------|
| `subsId` | `subsId` | text | no | — |
| `orderId` | `orderId` | text | no | — |
| `linkId` | `linkId` | text | no | — |
| `custId` | `custId` | text | no | — |

### 12. pauseResumeSubscription — Action

| n8n Param | Make Param | Type | Required | Default |
|-----------|-----------|------|----------|---------|
| `subsId` | `subsId` | text | yes | — |
| `status` | `status` | select (SUSPENDED / ACTIVE) | yes | — |

### 13. cancelSubscription — Action

| n8n Param | Make Param | Type | Required | Default |
|-----------|-----------|------|----------|---------|
| `subsId` | `subsId` | text | yes | — |

### 14. makeApiCall — Universal

| Param | Type | Required | Notes |
|-------|------|----------|-------|
| `method` | select | yes | GET / POST / PUT / PATCH / DELETE |
| `url` | text | yes | Relative path only — e.g. `/v2/some/endpoint`. Proxy prepends base URL. Absolute URLs rejected by Make. |
| `headers` | collection | no | Additional headers |
| `body` | any | no | Raw JSON body |
