# API Mapping — n8n v1.6.1 → Make

Source of truth: https://github.com/paytm/n8n-nodes-paytm

---

## Module List

### Order Resource

| n8n Operation | Make Module | Paytm Endpoint | Auth Type | Status |
|---------------|-------------|----------------|-----------|--------|
| Fetch Order List | `fetchOrderList` | `POST /merchant-passbook/search/list/order/v2` | Checksum (head envelope) | ✅ Built (needs auth format fix — see note) |
| Order Detail | `orderDetail` | `POST /merchant-adapter/internal/ORDER_DETAIL?mid={mid}` | Settlement envelope | 🔲 Pending |

### Payment Link Resource

| n8n Operation | Make Module | Paytm Endpoint | Auth Type | Status |
|---------------|-------------|----------------|-----------|--------|
| Fetch Payment Links | `fetchPaymentLinks` | `POST /link/fetch` | Checksum (head envelope) | 🔲 Pending |
| Fetch Transactions for Link | `fetchTransactionsForLink` | `POST /link/fetchTransaction` | Checksum (head envelope) | 🔲 Pending |
| Create Payment Link | `createPaymentLink` | `POST /link/create` | Checksum (head envelope) | 🔲 Pending |

### Refund Resource

| n8n Operation | Make Module | Paytm Endpoint | Auth Type | Status |
|---------------|-------------|----------------|-----------|--------|
| Fetch Refund List | `fetchRefundList` | `POST /merchant-passbook/api/v1/refundList` | Checksum (head envelope) | 🔲 Pending |
| Check Refund Status | `checkRefundStatus` | `POST /v2/refund/status` | Checksum (head envelope) | 🔲 Pending |
| Initiate Refund | `initiateRefund` | `POST /refund/apply` | Checksum (head envelope) | 🔲 Pending |

### Settlement Resource

| n8n Operation | Make Module | Paytm Endpoint | Auth Type | Status |
|---------------|-------------|----------------|-----------|--------|
| Settlement Txn List by Date | `settlementTxnListByDate` | `POST /merchant-adapter/internal/TxnListByDate?mid={mid}` | Settlement envelope | 🔲 Pending |
| Settlement Bill List | `settlementBillList` | `POST /merchant-adapter/internal/BILL_LIST?mid={mid}` | Settlement envelope | 🔲 Pending |

### Subscription Resource

| n8n Operation | Make Module | Paytm Endpoint | Auth Type | Status |
|---------------|-------------|----------------|-----------|--------|
| Fetch Subscription Status | `fetchSubscriptionStatus` | `POST /subscription/subscription/checkStatus` | Checksum (head envelope) | 🔲 Pending |
| Pause / Resume Subscription | `pauseResumeSubscription` | `POST /subscription/subscription/status/modify` | Checksum (head envelope) | 🔲 Pending |
| Cancel Subscription | `cancelSubscription` | `POST /subscription/subscription/cancel` | Checksum (head envelope) | 🔲 Pending |

---

## Base URLs (from n8n constants)

| Environment | Base URL |
|-------------|----------|
| Production | `https://secure.paytmpayments.com` |
| Staging | `https://securestage.paytmpayments.com` |

> **Action required:** Our `listOrders` module was built with `https://securegw.paytm.in` as base URL. Verify which is correct for `/merchant-passbook/search/list/order/v2` before testing with Stage credentials.

---

## Auth Mechanisms

### 1. Checksum — Head Envelope (10 of 13 modules)

Used by: Order List, all Payment Link, all Refund, all Subscription modules.

```json
{
  "body": {
    "mid": "...",
    "...": "request params"
  },
  "head": {
    "tokenType": "AES",
    "signature": "<SHA-256 Base64 checksum>",
    "channelId": "WEB"
  }
}
```

Checksum is computed from `body` fields (keys sorted alphabetically, values pipe-delimited) + keySecret.

> **Action required:** Our `listOrders` module currently puts `paytmChecksum` flat inside the body, not in `head.signature`. This needs to be corrected once confirmed against Paytm API docs or a staging test.

### 2. Settlement Envelope (3 modules)

Used by: Order Detail, Settlement Txn List, Settlement Bill List.

```json
{
  "ipRoleId": "...",
  "...": "request params",
  "signature": "<checksum>",
  "X-PGP-Unique-ID": "<uuid>"
}
```

Different request shape — implement these last after confirming the exact envelope format.

---

## Parameter Mapping

### fetchOrderList

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

### fetchPaymentLinks

| n8n Param | Make Param | Type | Required | Default |
|-----------|-----------|------|----------|---------|
| `fromDate` | `fromDate` | date | no | — |
| `toDate` | `toDate` | date | no | — |
| `linkId` | `linkId` | text | no | — |
| `merchantRequestId` | `merchantRequestId` | text | no | — |
| `linkType` | `linkType` | select (FIXED / GENERIC) | no | — |
| `paymentStatus` | `paymentStatus` | select | no | — |
| `isActive` | `isActive` | boolean | no | — |

### fetchTransactionsForLink

| n8n Param | Make Param | Type | Required | Default |
|-----------|-----------|------|----------|---------|
| `linkId` | `linkId` | text | yes | — |
| `searchStartDate` | `searchStartDate` | date | no | — |
| `searchEndDate` | `searchEndDate` | date | no | — |
| `fetchAllTxns` | `fetchAllTxns` | boolean | no | — |

### createPaymentLink

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

### fetchRefundList

| n8n Param | Make Param | Type | Required | Default |
|-----------|-----------|------|----------|---------|
| `startDate` | `startDate` | date | yes | — |
| `endDate` | `endDate` | date | yes | — |
| `pageNum` | `pageNum` | integer | no | `1` |
| `pageSize` | `pageSize` | integer | no | `20` |
| `isSort` | `isSort` | boolean | no | `true` |

### checkRefundStatus

| n8n Param | Make Param | Type | Required | Default |
|-----------|-----------|------|----------|---------|
| `orderId` | `orderId` | text | yes | — |
| `refId` | `refId` | text | yes | — |

### initiateRefund

| n8n Param | Make Param | Type | Required | Default |
|-----------|-----------|------|----------|---------|
| `orderId` | `orderId` | text | yes | — |
| `txnId` | `txnId` | text | yes | — |
| `refId` | `refId` | text | yes | — |
| `refundAmount` | `refundAmount` | number | yes | — |
| `comments` | `comments` | text | no | — |

### fetchSubscriptionStatus

| n8n Param | Make Param | Type | Required | Default |
|-----------|-----------|------|----------|---------|
| `subsId` | `subsId` | text | no | — |
| `orderId` | `orderId` | text | no | — |
| `linkId` | `linkId` | text | no | — |
| `custId` | `custId` | text | no | — |

### pauseResumeSubscription

| n8n Param | Make Param | Type | Required | Default |
|-----------|-----------|------|----------|---------|
| `subsId` | `subsId` | text | yes | — |
| `status` | `status` | select (SUSPENDED / ACTIVE) | yes | — |

### cancelSubscription

| n8n Param | Make Param | Type | Required | Default |
|-----------|-----------|------|----------|---------|
| `subsId` | `subsId` | text | yes | — |
