# Make UI — modules: communication and parameters

Use when wiring modules in **Apps Editor**: define **mappable parameters** first, then **Communication**. Each section mirrors the repo JSONC sources under `app/`.

**Canonical long-form tables:** [`api-mapping.md`](./api-mapping.md) § *Parameter Mapping*.

**Typical paste order**

1. **Base** — [`app/base.jsonc`](../app/base.jsonc) (Content-Type, default error, log sanitize).
2. **Connection** — parameters JSON + Communication from [`app/connections/paytm.jsonc`](../app/connections/paytm.jsonc).
3. **Per module** — mappable parameters + Communication JSON below.

**IML (current repo)**

| Context | `X-Signature` |
|--------|----------------|
| **Connection save** | `{{sha256(parameters.merchantId; 'hex'; parameters.keySecret; 'utf8')}}` |
| **All modules** | `{{sha256(connection.merchantId; 'hex'; connection.keySecret; 'utf8')}}` |

- Use **4-argument** `sha256(message; 'hex'; keySecret; 'utf8')`. Two-arg `sha256(message; key)` is **not** HMAC in Make IML.
- **URL:** `{{connection.baseUrl}}/integration/{functionName}?mid={{connection.merchantId}}`
- **Modules:** `requestId` and `timestamp` = `{{formatDate(now; 'X')}}000`
- **Connection validation body:** `requestId` = `{{formatDate(now; 'X')}}`, `timestamp` = `{{formatDate(now; 'x')}}`, empty `params`
- **Content-Type** only in **Base** — modules omit it
- **Naming:** modules → `connection.*`; connection save → `parameters.*`

**Public Make hosts:** use routable merchant-adapter URLs (e.g. `https://secure.paytmpayments.com/merchant-adapter`). Avoid `secure-int` (private IP). Add `&env=production` or `&env=staging` on module URLs when required.

---

## Table of contents

0. [Base communication](#base-communication)
1. [Connection](#connection-parameters-not-modules)
2. [`createPaymentLink`](#2-createpaymentlink) — Action
3. [`fetchPaymentLinks`](#3-fetchpaymentlinks) — Search
4. [`fetchTransactionsForLink`](#4-fetchtransactionsforlink) — Search
5. [`fetchOrderList`](#5-fetchorderlist) — Search
6. [`orderDetail`](#6-orderdetail) — Action (RTDD / settlement via proxy)
7. [`initiateRefund`](#7-initiaterefund) — Action
8. [`checkRefundStatus`](#8-checkrefundstatus) — Action
9. [`fetchRefundList`](#9-fetchrefundlist) — Search
10. [`settlementBillList`](#10-settlementbilllist) — Search (RTDD)
11. [`settlementTxnListByDate`](#11-settlementtxnlistbydate) — Search (RTDD)
12. [`fetchSubscriptionStatus`](#12-fetchsubscriptionstatus) — Action
13. [`pauseResumeSubscription`](#13-pauseresumesubscription) — Action
14. [`cancelSubscription`](#14-cancelsubscription) — Action
15. [`makeApiCall`](#15-makeapicall) — Universal

---

## Base communication

**Source:** [`app/base.jsonc`](../app/base.jsonc)

### Base — Communication reference (`jsonc`)

```jsonc
/**
 * BASE COMMUNICATION — inherited by every module in this app.
 *
 * Defines:
 *   headers      — Content-Type applied to every outbound request (modules do NOT repeat this).
 *   response.error — Default error message shown in Make when a request fails.
 *   log.sanitize — Prevents X-Signature from appearing in Make's request logs.
 *
 * HOW TO USE IN MAKE
 *   Apps Editor → [App] → Base → Communications → paste the JSON below (strip JSONC comments first).
 */
{
    "headers": {
        "Content-Type": "application/json"
    },
    "response": {
        "error": {
            "message": "[{{statusCode}}] {{body.error}}"
        }
    },
    "log": {
        "sanitize": ["request.headers.X-Signature"]
    }
}
```

### Base — Communication (`JSON`, paste)

```json
{
    "headers": {
        "Content-Type": "application/json"
    },
    "response": {
        "error": {
            "message": "[{{statusCode}}] {{body.error}}"
        }
    },
    "log": {
        "sanitize": [
            "request.headers.X-Signature"
        ]
    }
}
```

---

## Connection parameters (not modules)

**Source:** [`app/connections/paytm.jsonc`](../app/connections/paytm.jsonc)

| Parameter `name` | Make `type` | Required |
|---|---|---|
| `merchantId` | `text` | Yes |
| `keySecret` | `password` | Yes |
| `baseUrl` | `select` | Yes |

### Connection — parameters (`JSON`, paste)

```json
[
  { "name": "merchantId", "label": "Merchant ID (MID)", "type": "text", "required": true },
  { "name": "keySecret", "label": "Key Secret", "type": "password", "required": true },
  {
    "name": "baseUrl",
    "label": "Environment",
    "type": "select",
    "required": true,
    "options": [
      { "label": "Production", "value": "https://securegw.paytm.in" },
      { "label": "Staging", "value": "https://securegw-stage.paytm.in" },
      { "label": "QA", "value": "https://pgp-qa5.paytm.in/merchant-adapter" }
    ]
  }
]
```

### Connection — Communication reference (`jsonc`)

```jsonc
/**
 * CONNECTION: Paytm Merchant
 * TYPE: apikey (API key / credential pair)
 *
 * Stores credentials for all Paytm API calls routed through the
 * merchant-adapter signing proxy. The proxy handles Paytm's AES-128-CBC
 * checksum — this cannot be computed in Make IML.
 *
 * FIELDS
 *   merchantId  – MID assigned by Paytm. Passed as ?mid= on every proxy call.
 *   keySecret   – Used for two things:
 *                   1. HMAC-SHA256 inbound auth to the proxy (X-Signature header).
 *                   2. The proxy uses it to sign the Paytm AES checksum downstream.
 *                 Marked password:true — Make never displays it after save.
 *   baseUrl     – Proxy base URL. Determines the Paytm environment downstream.
 *                 Production : https://securegw.paytm.in
 *                 Staging    : https://securegw-stage.paytm.in
 *                 QA         : https://pgp-qa5.paytm.in/merchant-adapter
 *
 * HOW AUTHENTICATION WORKS
 *   Make IML requires the 4-argument form of sha256 for proper HMAC-SHA256:
 *     sha256(message; 'hex'; key; 'utf8')
 *   The 2-argument form sha256(message; key) treats the second arg as the output
 *   encoding (not the HMAC key), producing plain SHA256 — NOT HMAC.
 *
 *   Connection validation signs merchantId (static, no timing issues since
 *   body cannot be accessed from connection headers in Make IML):
 *     X-Signature = HMAC-SHA256(merchantId, keySecret) — hex output
 *
 *   Every module request signs connection.merchantId (same message as connection save):
 *     X-Signature = HMAC-SHA256(merchantId, keySecret) — hex output
 *
 *   The proxy accepts either form and verifies before forwarding to Paytm.
 *   keySecret never travels to Paytm — only the HMAC header does.
 *
 * HOW TO COPY INTO MAKE
 *   Apps Editor → Connections → [your connection] → Communication tab → paste below.
 *   Parameters go into the separate Parameters tab as form fields.
 *
 * PARAMETERS TAB (define these as form fields)
 *   - name: merchantId  | label: Merchant ID  | type: text     | required: true
 *   - name: keySecret   | label: Key Secret    | type: password | required: true
 *   - name: baseUrl     | label: Environment   | type: select   | required: true
 *       options:
 *         - label: Production  | value: https://securegw.paytm.in
 *         - label: Staging     | value: https://securegw-stage.paytm.in
 *         - label: QA          | value: https://pgp-qa5.paytm.in/merchant-adapter
 */
{
    // Validation call — send a minimal signed request to the proxy.
    // Any HTTP 200 (even a downstream FAILED from Paytm) means the HMAC was
    // accepted and the credentials are valid at the proxy level.
    "url": "{{parameters.baseUrl}}/integration/fetchOrderList?mid={{parameters.merchantId}}",
    "method": "POST",
    "headers": {
        "Content-Type": "application/json",
        "X-Signature": "{{sha256(parameters.merchantId; 'hex'; parameters.keySecret; 'utf8')}}"
    },
    "body": {
        "requestId": "{{formatDate(now; 'X')}}",
        "timestamp": "{{formatDate(now; 'x')}}",
        "params": {}
    },
    "response": {
        // HTTP 200 from proxy = HMAC accepted = credentials valid.
        // HTTP 401 = wrong keySecret. HTTP 404 = proxy not enabled.
        "valid": "{{statusCode == 200}}",
        "error": {
            "message": "[{{statusCode}}] {{body.error}}"
        }
    },
    "log": {
        "sanitize": ["request.headers.X-Signature"]
    }
}
```

### Connection — Communication (`JSON`, paste)

```json
{
    "url": "{{parameters.baseUrl}}/integration/fetchOrderList?mid={{parameters.merchantId}}",
    "method": "POST",
    "headers": {
        "Content-Type": "application/json",
        "X-Signature": "{{sha256(parameters.merchantId; 'hex'; parameters.keySecret; 'utf8')}}"
    },
    "body": {
        "requestId": "{{formatDate(now; 'X')}}",
        "timestamp": "{{formatDate(now; 'x')}}",
        "params": {}
    },
    "response": {
        "valid": "{{statusCode == 200}}",
        "error": {
            "message": "[{{statusCode}}] {{body.error}}"
        }
    },
    "log": {
        "sanitize": [
            "request.headers.X-Signature"
        ]
    }
}
```

---

## 1. `createPaymentLink` (Action)
**Source:** [`app/modules/createPaymentLink.jsonc`](../app/modules/createPaymentLink.jsonc)
### Mappable parameters

| Parameter `name` | Notes |
|---|---|
| `amount` | Used in `params` — add matching Make form field |
| `bindLinkIdMobile` | Used in `params` — add matching Make form field |
| `customerEmail` | Used in `params` — add matching Make form field |
| `customerId` | Used in `params` — add matching Make form field |
| `customerMobile` | Used in `params` — add matching Make form field |
| `customerName` | Used in `params` — add matching Make form field |
| `expiryDate` | Used in `params` — add matching Make form field |
| `linkDescription` | Used in `params` — add matching Make form field |
| `linkName` | Used in `params` — add matching Make form field |
| `linkNotes` | Used in `params` — add matching Make form field |
| `linkType` | Used in `params` — add matching Make form field |
| `maxPaymentsAllowed` | Used in `params` — add matching Make form field |
| `merchantRequestId` | Used in `params` — add matching Make form field |
| `partialPayment` | Used in `params` — add matching Make form field |
| `sendEmail` | Used in `params` — add matching Make form field |
| `sendSms` | Used in `params` — add matching Make form field |
| `statusCallbackUrl` | Used in `params` — add matching Make form field |

### Response mapping

| `output` | `{{body.data}}` |

### Module Communication — reference (`jsonc`)

```jsonc
/**
 * MODULE: createPaymentLink
 * TYPE: Action (single-item response)
 * PAYTM ENDPOINT: POST /link/create (via proxy)
 * PROXY FUNCTION: createPaymentLink
 *
 * amount is required when linkType = FIXED; optional for GENERIC.
 * expiryDate format expected by Paytm: DD/MM/YYYY
 * customerContact is a nested object — customerName/Email/Mobile go inside it.
 *
 * RESPONSE STRUCTURE
 *   Proxy wraps Paytm response: { status, function, requestId, data: <paytm_response> }
 *   data.body.linkId contains the created link ID on success.
 */
{
    "url": "{{connection.baseUrl}}/integration/createPaymentLink?mid={{connection.merchantId}}",
    "method": "POST",
    "headers": {
        "X-Signature": "{{sha256(connection.merchantId; 'hex'; connection.keySecret; 'utf8')}}"
    },
    "body": {
        "requestId": "{{formatDate(now; 'X')}}000",
        "timestamp": "{{formatDate(now; 'X')}}000",
        "params": {
            "mid": "{{connection.merchantId}}",
            "linkName": "{{parameters.linkName}}",
            "linkDescription": "{{parameters.linkDescription}}",
            "linkType": "{{parameters.linkType}}",
            "amount": "{{parameters.amount}}",
            "partialPayment": "{{parameters.partialPayment}}",
            "bindLinkIdMobile": "{{parameters.bindLinkIdMobile}}",
            "maxPaymentsAllowed": "{{parameters.maxPaymentsAllowed}}",
            "customerContact": {
                "customerName": "{{parameters.customerName}}",
                "customerEmail": "{{parameters.customerEmail}}",
                "customerMobile": "{{parameters.customerMobile}}"
            },
            "sendSms": "{{parameters.sendSms}}",
            "sendEmail": "{{parameters.sendEmail}}",
            "expiryDate": "{{formatDate(parameters.expiryDate; 'DD/MM/YYYY')}}",
            "merchantRequestId": "{{parameters.merchantRequestId}}",
            "customerId": "{{parameters.customerId}}",
            "linkNotes": "{{parameters.linkNotes}}",
            "statusCallbackUrl": "{{parameters.statusCallbackUrl}}"
        }
    },
    "response": {
        "output": "{{body.data}}"
    }
}
```

### Module Communication (`JSON`, paste)

```json
{
    "url": "{{connection.baseUrl}}/integration/createPaymentLink?mid={{connection.merchantId}}",
    "method": "POST",
    "headers": {
        "X-Signature": "{{sha256(connection.merchantId; 'hex'; connection.keySecret; 'utf8')}}"
    },
    "body": {
        "requestId": "{{formatDate(now; 'X')}}000",
        "timestamp": "{{formatDate(now; 'X')}}000",
        "params": {
            "mid": "{{connection.merchantId}}",
            "linkName": "{{parameters.linkName}}",
            "linkDescription": "{{parameters.linkDescription}}",
            "linkType": "{{parameters.linkType}}",
            "amount": "{{parameters.amount}}",
            "partialPayment": "{{parameters.partialPayment}}",
            "bindLinkIdMobile": "{{parameters.bindLinkIdMobile}}",
            "maxPaymentsAllowed": "{{parameters.maxPaymentsAllowed}}",
            "customerContact": {
                "customerName": "{{parameters.customerName}}",
                "customerEmail": "{{parameters.customerEmail}}",
                "customerMobile": "{{parameters.customerMobile}}"
            },
            "sendSms": "{{parameters.sendSms}}",
            "sendEmail": "{{parameters.sendEmail}}",
            "expiryDate": "{{formatDate(parameters.expiryDate; 'DD/MM/YYYY')}}",
            "merchantRequestId": "{{parameters.merchantRequestId}}",
            "customerId": "{{parameters.customerId}}",
            "linkNotes": "{{parameters.linkNotes}}",
            "statusCallbackUrl": "{{parameters.statusCallbackUrl}}"
        }
    },
    "response": {
        "output": "{{body.data}}"
    }
}
```

---

## 2. `fetchPaymentLinks` (Search)
**Source:** [`app/modules/fetchPaymentLinks.jsonc`](../app/modules/fetchPaymentLinks.jsonc)
### Mappable parameters

| Parameter `name` | Notes |
|---|---|
| `customerEmail` | Used in `params` — add matching Make form field |
| `customerName` | Used in `params` — add matching Make form field |
| `customerPhone` | Used in `params` — add matching Make form field |
| `filterFromDate` | Used in `params` — add matching Make form field |
| `filterIsActive` | Used in `params` — add matching Make form field |
| `filterToDate` | Used in `params` — add matching Make form field |
| `linkId` | Used in `params` — add matching Make form field |
| `merchantRequestId` | Used in `params` — add matching Make form field |
| `paymentStatus` | Used in `params` — add matching Make form field |

### Response mapping

| `output` | `{{body.data}}` |

### Module Communication — reference (`jsonc`)

```jsonc
/**
 * MODULE: fetchPaymentLinks
 * TYPE: Search (returns payment links bundle)
 * PROXY FUNCTION: fetchPaymentLinks
 * DOWNSTREAM: POST /link/fetch
 *
 * KEY NOTES (Zapier parity):
 *   - All params are optional; mid is always sent
 *   - Dates go inside searchFilterRequestBody as DD/MM/YYYY
 *   - paymentStatus choices: EXPIRED / INIT / PAID / PENDING
 *   - X-Signature = HMAC-SHA256(merchantId, connection.keySecret)
 */
{
    "url": "{{connection.baseUrl}}/integration/fetchPaymentLinks?mid={{connection.merchantId}}",
    "method": "POST",
    "headers": {
        "X-Signature": "{{sha256(connection.merchantId; 'hex'; connection.keySecret; 'utf8')}}"
    },
    "body": {
        "requestId": "{{formatDate(now; 'X')}}000",
        "timestamp": "{{formatDate(now; 'X')}}000",
        "params": {
            "mid": "{{connection.merchantId}}",
            "paymentStatus": "{{parameters.paymentStatus}}",
            "merchantRequestId": "{{parameters.merchantRequestId}}",
            "linkId": "{{parameters.linkId}}",
            "customerName": "{{parameters.customerName}}",
            "customerEmail": "{{parameters.customerEmail}}",
            "customerPhone": "{{parameters.customerPhone}}",
            "searchFilterRequestBody": {
                "fromDate": "{{formatDate(parameters.filterFromDate; 'DD/MM/YYYY')}}",
                "toDate": "{{formatDate(parameters.filterToDate; 'DD/MM/YYYY')}}",
                "isActive": "{{parameters.filterIsActive}}"
            }
        }
    },
    "response": {
        "output": "{{body.data}}"
    }
}
```

### Module Communication (`JSON`, paste)

```json
{
    "url": "{{connection.baseUrl}}/integration/fetchPaymentLinks?mid={{connection.merchantId}}",
    "method": "POST",
    "headers": {
        "X-Signature": "{{sha256(connection.merchantId; 'hex'; connection.keySecret; 'utf8')}}"
    },
    "body": {
        "requestId": "{{formatDate(now; 'X')}}000",
        "timestamp": "{{formatDate(now; 'X')}}000",
        "params": {
            "mid": "{{connection.merchantId}}",
            "paymentStatus": "{{parameters.paymentStatus}}",
            "merchantRequestId": "{{parameters.merchantRequestId}}",
            "linkId": "{{parameters.linkId}}",
            "customerName": "{{parameters.customerName}}",
            "customerEmail": "{{parameters.customerEmail}}",
            "customerPhone": "{{parameters.customerPhone}}",
            "searchFilterRequestBody": {
                "fromDate": "{{formatDate(parameters.filterFromDate; 'DD/MM/YYYY')}}",
                "toDate": "{{formatDate(parameters.filterToDate; 'DD/MM/YYYY')}}",
                "isActive": "{{parameters.filterIsActive}}"
            }
        }
    },
    "response": {
        "output": "{{body.data}}"
    }
}
```

---

## 3. `fetchTransactionsForLink` (Search)
**Source:** [`app/modules/fetchTransactionsForLink.jsonc`](../app/modules/fetchTransactionsForLink.jsonc)
### Mappable parameters

| Parameter `name` | Notes |
|---|---|
| `fetchAllTxns` | Used in `params` — add matching Make form field |
| `limit` | Used in `params` — add matching Make form field |
| `linkId` | Used in `params` — add matching Make form field |
| `searchEndDate` | Used in `params` — add matching Make form field |
| `searchStartDate` | Used in `params` — add matching Make form field |

### Response mapping (Search)

| Field | Expression |
|-------|------------|
| `iterate` | `{{body.data.txnDetailsList}}` |
| `output` | `{{item}}` |

### Module Communication — reference (`jsonc`)

```jsonc
/**
 * MODULE: fetchTransactionsForLink
 * TYPE: Search (returns a list of transactions for a payment link)
 * PAYTM ENDPOINT: POST /link/fetchTransaction (via proxy)
 * PROXY FUNCTION: fetchTransactionsForLink
 *
 * linkId is required. Date range and fetchAllTxns are optional filters.
 *
 * RESPONSE STRUCTURE
 *   Proxy wraps Paytm response: { status, function, requestId, data: <paytm_response> }
 *   Verify body.data.txnDetailsList iterate path during E2E testing.
 */
{
    "url": "{{connection.baseUrl}}/integration/fetchTransactionsForLink?mid={{connection.merchantId}}",
    "method": "POST",
    "headers": {
        "X-Signature": "{{sha256(connection.merchantId; 'hex'; connection.keySecret; 'utf8')}}"
    },
    "body": {
        "requestId": "{{formatDate(now; 'X')}}000",
        "timestamp": "{{formatDate(now; 'X')}}000",
        "params": {
            "linkId": "{{parameters.linkId}}",
            "searchStartDate": "{{formatDate(parameters.searchStartDate; 'YYYY-MM-DD')}}",
            "searchEndDate": "{{formatDate(parameters.searchEndDate; 'YYYY-MM-DD')}}",
            "fetchAllTxns": "{{parameters.fetchAllTxns}}",
            "pageSize": "{{ifempty(parameters.limit; 20)}}"
        }
    },
    "response": {
        // Verify body.data.txnDetailsList is the correct iterate path during E2E testing.
        "iterate": "{{body.data.txnDetailsList}}",
        "output": "{{item}}"
    }
}
```

### Module Communication (`JSON`, paste)

```json
{
    "url": "{{connection.baseUrl}}/integration/fetchTransactionsForLink?mid={{connection.merchantId}}",
    "method": "POST",
    "headers": {
        "X-Signature": "{{sha256(connection.merchantId; 'hex'; connection.keySecret; 'utf8')}}"
    },
    "body": {
        "requestId": "{{formatDate(now; 'X')}}000",
        "timestamp": "{{formatDate(now; 'X')}}000",
        "params": {
            "linkId": "{{parameters.linkId}}",
            "searchStartDate": "{{formatDate(parameters.searchStartDate; 'YYYY-MM-DD')}}",
            "searchEndDate": "{{formatDate(parameters.searchEndDate; 'YYYY-MM-DD')}}",
            "fetchAllTxns": "{{parameters.fetchAllTxns}}",
            "pageSize": "{{ifempty(parameters.limit; 20)}}"
        }
    },
    "response": {
        "iterate": "{{body.data.txnDetailsList}}",
        "output": "{{item}}"
    }
}
```

---

## 4. `fetchOrderList` (Search)
**Source:** [`app/modules/fetchOrderList.jsonc`](../app/modules/fetchOrderList.jsonc)
### Mappable parameters

| Parameter `name` | Notes |
|---|---|
| `endDate` | Used in `params` — add matching Make form field |
| `limit` | Used in `params` — add matching Make form field |
| `orderSearchStatus` | Used in `params` — add matching Make form field |
| `orderSearchType` | Used in `params` — add matching Make form field |
| `pageNumber` | Used in `params` — add matching Make form field |
| `startDate` | Used in `params` — add matching Make form field |

### Response mapping

| `output` | `{{body.data}}` |

### Module Communication — reference (`jsonc`)

```jsonc
/**
 * MODULE: fetchOrderList
 * TYPE: Search (returns order list bundle)
 * PROXY FUNCTION: fetchOrderList
 * DOWNSTREAM: POST /merchant-passbook/search/list/order/v2
 *
 * KEY NOTES (from Zapier parity):
 *   - orderSearchStatus "ALL" is INVALID at Paytm; map to "SUCCESS|FAILURE|PENDING"
 *   - Dates must be IST datetime: "YYYY-MM-DDTHH:mm:ss+05:30"
 *   - isSort must be boolean true
 *   - X-Signature = HMAC-SHA256(merchantId, connection.keySecret)
 */
{
    "url": "{{connection.baseUrl}}/integration/fetchOrderList?mid={{connection.merchantId}}",
    "method": "POST",
    "headers": {
        "X-Signature": "{{sha256(connection.merchantId; 'hex'; connection.keySecret; 'utf8')}}"
    },
    "body": {
        "requestId": "{{formatDate(now; 'X')}}000",
        "timestamp": "{{formatDate(now; 'X')}}000",
        "params": {
            "mid": "{{connection.merchantId}}",
            "fromDate": "{{formatDate(parameters.startDate; 'YYYY-MM-DD')}}T00:00:00+05:30",
            "toDate": "{{formatDate(parameters.endDate; 'YYYY-MM-DD')}}T23:59:59+05:30",
            "orderSearchStatus": "{{if(parameters.orderSearchStatus == 'ALL'; 'SUCCESS|FAILURE|PENDING'; ifempty(parameters.orderSearchStatus; 'SUCCESS'))}}",
            "orderSearchType": "{{ifempty(parameters.orderSearchType; 'ALL')}}",
            "pageNumber": "{{ifempty(parameters.pageNumber; 1)}}",
            "pageSize": "{{ifempty(parameters.limit; 20)}}",
            "isSort": true
        }
    },
    "response": {
        // Returns full response as one bundle: { resultInfo, orderList[], totalCount }
        "output": "{{body.data}}"
    }
}
```

### Module Communication (`JSON`, paste)

```json
{
    "url": "{{connection.baseUrl}}/integration/fetchOrderList?mid={{connection.merchantId}}",
    "method": "POST",
    "headers": {
        "X-Signature": "{{sha256(connection.merchantId; 'hex'; connection.keySecret; 'utf8')}}"
    },
    "body": {
        "requestId": "{{formatDate(now; 'X')}}000",
        "timestamp": "{{formatDate(now; 'X')}}000",
        "params": {
            "mid": "{{connection.merchantId}}",
            "fromDate": "{{formatDate(parameters.startDate; 'YYYY-MM-DD')}}T00:00:00+05:30",
            "toDate": "{{formatDate(parameters.endDate; 'YYYY-MM-DD')}}T23:59:59+05:30",
            "orderSearchStatus": "{{if(parameters.orderSearchStatus == 'ALL'; 'SUCCESS|FAILURE|PENDING'; ifempty(parameters.orderSearchStatus; 'SUCCESS'))}}",
            "orderSearchType": "{{ifempty(parameters.orderSearchType; 'ALL')}}",
            "pageNumber": "{{ifempty(parameters.pageNumber; 1)}}",
            "pageSize": "{{ifempty(parameters.limit; 20)}}",
            "isSort": true
        }
    },
    "response": {
        "output": "{{body.data}}"
    }
}
```

---

## 5. `orderDetail` (Action (RTDD / settlement via proxy))
**Source:** [`app/modules/orderDetail.jsonc`](../app/modules/orderDetail.jsonc)
### Mappable parameters

| Parameter `name` | Notes |
|---|---|
| `bizOrderId` | Used in `params` — add matching Make form field |
| `excludePaymentsData` | Used in `params` — add matching Make form field |
| `isSettlementInfo` | Used in `params` — add matching Make form field |

### Response mapping

| `output` | `{{body.data}}` |

### Module Communication — reference (`jsonc`)

```jsonc
/**
 * MODULE: orderDetail
 * TYPE: Action (single-item response)
 * PAYTM ENDPOINT: RTDD via proxy
 * PROXY FUNCTION: orderDetail
 *
 * RTDD/Settlement envelope — proxy builds the signed downstream body.
 * No checksum logic in IML.
 *
 * RESPONSE STRUCTURE
 *   Proxy wraps Paytm response: { status, function, requestId, data: <paytm_response> }
 *   Verify body.data path against actual Paytm response during E2E testing.
 */
{
    "url": "{{connection.baseUrl}}/integration/orderDetail?mid={{connection.merchantId}}",
    "method": "POST",
    "headers": {
        "X-Signature": "{{sha256(connection.merchantId; 'hex'; connection.keySecret; 'utf8')}}"
    },
    "body": {
        "requestId": "{{formatDate(now; 'X')}}000",
        "timestamp": "{{formatDate(now; 'X')}}000",
        "params": {
            "bizOrderId": "{{parameters.bizOrderId}}",
            "isSettlementInfo": "{{ifempty(parameters.isSettlementInfo; false)}}",
            "excludePaymentsData": "{{ifempty(parameters.excludePaymentsData; false)}}"
        }
    },
    "response": {
        // Verify body.data is the correct output path during E2E testing.
        "output": "{{body.data}}"
    }
}
```

### Module Communication (`JSON`, paste)

```json
{
    "url": "{{connection.baseUrl}}/integration/orderDetail?mid={{connection.merchantId}}",
    "method": "POST",
    "headers": {
        "X-Signature": "{{sha256(connection.merchantId; 'hex'; connection.keySecret; 'utf8')}}"
    },
    "body": {
        "requestId": "{{formatDate(now; 'X')}}000",
        "timestamp": "{{formatDate(now; 'X')}}000",
        "params": {
            "bizOrderId": "{{parameters.bizOrderId}}",
            "isSettlementInfo": "{{ifempty(parameters.isSettlementInfo; false)}}",
            "excludePaymentsData": "{{ifempty(parameters.excludePaymentsData; false)}}"
        }
    },
    "response": {
        "output": "{{body.data}}"
    }
}
```

---

## 6. `initiateRefund` (Action)
**Source:** [`app/modules/initiateRefund.jsonc`](../app/modules/initiateRefund.jsonc)
### Mappable parameters

| Parameter `name` | Notes |
|---|---|
| `comments` | Used in `params` — add matching Make form field |
| `orderId` | Used in `params` — add matching Make form field |
| `refId` | Used in `params` — add matching Make form field |
| `refundAmount` | Used in `params` — add matching Make form field |
| `txnId` | Used in `params` — add matching Make form field |

### Response mapping

| `output` | `{{body.data}}` |

### Module Communication — reference (`jsonc`)

```jsonc
/**
 * MODULE: initiateRefund
 * TYPE: Action (single-item response)
 * PAYTM ENDPOINT: POST /refund/apply (via proxy)
 * PROXY FUNCTION: initiateRefund
 *
 * All four IDs (orderId, txnId, refId, refundAmount) are required.
 * refId must be unique per refund request (idempotency key).
 *
 * RESPONSE STRUCTURE
 *   Proxy wraps Paytm response: { status, function, requestId, data: <paytm_response> }
 *   Verify body.data path during E2E testing.
 */
{
    "url": "{{connection.baseUrl}}/integration/initiateRefund?mid={{connection.merchantId}}",
    "method": "POST",
    "headers": {
        "X-Signature": "{{sha256(connection.merchantId; 'hex'; connection.keySecret; 'utf8')}}"
    },
    "body": {
        "requestId": "{{formatDate(now; 'X')}}000",
        "timestamp": "{{formatDate(now; 'X')}}000",
        "params": {
            "orderId": "{{parameters.orderId}}",
            "txnId": "{{parameters.txnId}}",
            "refId": "{{parameters.refId}}",
            "refundAmount": "{{parameters.refundAmount}}",
            "comments": "{{parameters.comments}}"
        }
    },
    "response": {
        "output": "{{body.data}}"
    }
}
```

### Module Communication (`JSON`, paste)

```json
{
    "url": "{{connection.baseUrl}}/integration/initiateRefund?mid={{connection.merchantId}}",
    "method": "POST",
    "headers": {
        "X-Signature": "{{sha256(connection.merchantId; 'hex'; connection.keySecret; 'utf8')}}"
    },
    "body": {
        "requestId": "{{formatDate(now; 'X')}}000",
        "timestamp": "{{formatDate(now; 'X')}}000",
        "params": {
            "orderId": "{{parameters.orderId}}",
            "txnId": "{{parameters.txnId}}",
            "refId": "{{parameters.refId}}",
            "refundAmount": "{{parameters.refundAmount}}",
            "comments": "{{parameters.comments}}"
        }
    },
    "response": {
        "output": "{{body.data}}"
    }
}
```

---

## 7. `checkRefundStatus` (Action)
**Source:** [`app/modules/checkRefundStatus.jsonc`](../app/modules/checkRefundStatus.jsonc)
### Mappable parameters

| Parameter `name` | Notes |
|---|---|
| `orderId` | Used in `params` — add matching Make form field |
| `refId` | Used in `params` — add matching Make form field |

### Response mapping

| `output` | `{{body.data}}` |

### Module Communication — reference (`jsonc`)

```jsonc
/**
 * MODULE: checkRefundStatus
 * TYPE: Action (single-item response)
 * PAYTM ENDPOINT: POST /v2/refund/status (via proxy)
 * PROXY FUNCTION: checkRefundStatus
 *
 * RESPONSE STRUCTURE
 *   Proxy wraps Paytm response: { status, function, requestId, data: <paytm_response> }
 *   Verify body.data path during E2E testing.
 */
{
    "url": "{{connection.baseUrl}}/integration/checkRefundStatus?mid={{connection.merchantId}}",
    "method": "POST",
    "headers": {
        "X-Signature": "{{sha256(connection.merchantId; 'hex'; connection.keySecret; 'utf8')}}"
    },
    "body": {
        "requestId": "{{formatDate(now; 'X')}}000",
        "timestamp": "{{formatDate(now; 'X')}}000",
        "params": {
            "orderId": "{{parameters.orderId}}",
            "refId": "{{parameters.refId}}"
        }
    },
    "response": {
        "output": "{{body.data}}"
    }
}
```

### Module Communication (`JSON`, paste)

```json
{
    "url": "{{connection.baseUrl}}/integration/checkRefundStatus?mid={{connection.merchantId}}",
    "method": "POST",
    "headers": {
        "X-Signature": "{{sha256(connection.merchantId; 'hex'; connection.keySecret; 'utf8')}}"
    },
    "body": {
        "requestId": "{{formatDate(now; 'X')}}000",
        "timestamp": "{{formatDate(now; 'X')}}000",
        "params": {
            "orderId": "{{parameters.orderId}}",
            "refId": "{{parameters.refId}}"
        }
    },
    "response": {
        "output": "{{body.data}}"
    }
}
```

---

## 8. `fetchRefundList` (Search)
**Source:** [`app/modules/fetchRefundList.jsonc`](../app/modules/fetchRefundList.jsonc)
### Mappable parameters

| Parameter `name` | Notes |
|---|---|
| `endDate` | Used in `params` — add matching Make form field |
| `isSort` | Used in `params` — add matching Make form field |
| `limit` | Used in `params` — add matching Make form field |
| `pageNum` | Used in `params` — add matching Make form field |
| `startDate` | Used in `params` — add matching Make form field |

### Response mapping (Search)

| Field | Expression |
|-------|------------|
| `iterate` | `{{body.data.refundDetailList}}` |
| `output` | `{{item}}` |

### Module Communication — reference (`jsonc`)

```jsonc
/**
 * MODULE: fetchRefundList
 * TYPE: Search (returns a list of refunds)
 * PAYTM ENDPOINT: POST /merchant-passbook/api/v1/refundList (via proxy)
 * PROXY FUNCTION: fetchRefundList
 *
 * RESPONSE STRUCTURE
 *   Proxy wraps Paytm response: { status, function, requestId, data: <paytm_response> }
 *   Verify body.data.refundDetailList iterate path during E2E testing.
 */
{
    "url": "{{connection.baseUrl}}/integration/fetchRefundList?mid={{connection.merchantId}}",
    "method": "POST",
    "headers": {
        "X-Signature": "{{sha256(connection.merchantId; 'hex'; connection.keySecret; 'utf8')}}"
    },
    "body": {
        "requestId": "{{formatDate(now; 'X')}}000",
        "timestamp": "{{formatDate(now; 'X')}}000",
        "params": {
            "startDate": "{{formatDate(parameters.startDate; 'YYYY-MM-DD')}}",
            "endDate": "{{formatDate(parameters.endDate; 'YYYY-MM-DD')}}",
            "pageNum": "{{ifempty(parameters.pageNum; 1)}}",
            "pageSize": "{{ifempty(parameters.limit; 20)}}",
            "isSort": "{{ifempty(parameters.isSort; true)}}"
        }
    },
    "response": {
        // Verify body.data.refundDetailList is the correct iterate path during E2E testing.
        "iterate": "{{body.data.refundDetailList}}",
        "output": "{{item}}"
    }
}
```

### Module Communication (`JSON`, paste)

```json
{
    "url": "{{connection.baseUrl}}/integration/fetchRefundList?mid={{connection.merchantId}}",
    "method": "POST",
    "headers": {
        "X-Signature": "{{sha256(connection.merchantId; 'hex'; connection.keySecret; 'utf8')}}"
    },
    "body": {
        "requestId": "{{formatDate(now; 'X')}}000",
        "timestamp": "{{formatDate(now; 'X')}}000",
        "params": {
            "startDate": "{{formatDate(parameters.startDate; 'YYYY-MM-DD')}}",
            "endDate": "{{formatDate(parameters.endDate; 'YYYY-MM-DD')}}",
            "pageNum": "{{ifempty(parameters.pageNum; 1)}}",
            "pageSize": "{{ifempty(parameters.limit; 20)}}",
            "isSort": "{{ifempty(parameters.isSort; true)}}"
        }
    },
    "response": {
        "iterate": "{{body.data.refundDetailList}}",
        "output": "{{item}}"
    }
}
```

---

## 9. `settlementBillList` (Search (RTDD))
**Source:** [`app/modules/settlementBillList.jsonc`](../app/modules/settlementBillList.jsonc)
### Mappable parameters

| Parameter `name` | Notes |
|---|---|
| `limit` | Used in `params` — add matching Make form field |
| `pageNum` | Used in `params` — add matching Make form field |
| `settleStatus` | Used in `params` — add matching Make form field |
| `settlementBillId` | Used in `params` — add matching Make form field |
| `settlementEndTime` | Used in `params` — add matching Make form field |
| `settlementStartTime` | Used in `params` — add matching Make form field |
| `utrNo` | Used in `params` — add matching Make form field |

### Response mapping (Search)

| Field | Expression |
|-------|------------|
| `iterate` | `{{body.data.body.settleBillList}}` |
| `output` | `{{item}}` |

### Module Communication — reference (`jsonc`)

```jsonc
/**
 * MODULE: settlementBillList
 * TYPE: Search (returns a list of settlement bills / payouts)
 * PAYTM ENDPOINT: RTDD via proxy
 * PROXY FUNCTION: settlementBillList
 *
 * RTDD/Settlement envelope — proxy builds the signed downstream body.
 * No checksum logic in IML.
 *
 * NOTE ON PARAMS
 *   settlementStartTime / settlementEndTime — NOT startDate / endDate.
 *   pageSize max is 50.
 *   settleStatus valid values: BANK_INITIATED / PAYOUT_SETTLED / PAYOUT_UNSETTLED / WAIT_FOR_SETTLE
 *
 * RESPONSE STRUCTURE
 *   Proxy wraps Paytm response: { status, function, requestId, data: <paytm_response> }
 *   Verify body.data.body.settleBillList iterate path during E2E testing.
 */
{
    "url": "{{connection.baseUrl}}/integration/settlementBillList?mid={{connection.merchantId}}",
    "method": "POST",
    "headers": {
        "X-Signature": "{{sha256(connection.merchantId; 'hex'; connection.keySecret; 'utf8')}}"
    },
    "body": {
        "requestId": "{{formatDate(now; 'X')}}000",
        "timestamp": "{{formatDate(now; 'X')}}000",
        "params": {
            "settlementStartTime": "{{formatDate(parameters.settlementStartTime; 'YYYY-MM-DD HH:mm:ss')}}",
            "settlementEndTime": "{{formatDate(parameters.settlementEndTime; 'YYYY-MM-DD HH:mm:ss')}}",
            "pageNum": "{{ifempty(parameters.pageNum; 1)}}",
            "pageSize": "{{ifempty(parameters.limit; 20)}}",
            "settlementBillId": "{{parameters.settlementBillId}}",
            "settleStatus": "{{parameters.settleStatus}}",
            "utrNo": "{{parameters.utrNo}}"
        }
    },
    "response": {
        // Verify body.data.body.settleBillList is the correct iterate path during E2E testing.
        "iterate": "{{body.data.body.settleBillList}}",
        "output": "{{item}}"
    }
}
```

### Module Communication (`JSON`, paste)

```json
{
    "url": "{{connection.baseUrl}}/integration/settlementBillList?mid={{connection.merchantId}}",
    "method": "POST",
    "headers": {
        "X-Signature": "{{sha256(connection.merchantId; 'hex'; connection.keySecret; 'utf8')}}"
    },
    "body": {
        "requestId": "{{formatDate(now; 'X')}}000",
        "timestamp": "{{formatDate(now; 'X')}}000",
        "params": {
            "settlementStartTime": "{{formatDate(parameters.settlementStartTime; 'YYYY-MM-DD HH:mm:ss')}}",
            "settlementEndTime": "{{formatDate(parameters.settlementEndTime; 'YYYY-MM-DD HH:mm:ss')}}",
            "pageNum": "{{ifempty(parameters.pageNum; 1)}}",
            "pageSize": "{{ifempty(parameters.limit; 20)}}",
            "settlementBillId": "{{parameters.settlementBillId}}",
            "settleStatus": "{{parameters.settleStatus}}",
            "utrNo": "{{parameters.utrNo}}"
        }
    },
    "response": {
        "iterate": "{{body.data.body.settleBillList}}",
        "output": "{{item}}"
    }
}
```

---

## 10. `settlementTxnListByDate` (Search (RTDD))
**Source:** [`app/modules/settlementTxnListByDate.jsonc`](../app/modules/settlementTxnListByDate.jsonc)
### Mappable parameters

| Parameter `name` | Notes |
|---|---|
| `endDate` | Used in `params` — add matching Make form field |
| `limit` | Used in `params` — add matching Make form field |
| `pageNum` | Used in `params` — add matching Make form field |
| `settlementOrderId` | Used in `params` — add matching Make form field |
| `startDate` | Used in `params` — add matching Make form field |

### Response mapping (Search)

| Field | Expression |
|-------|------------|
| `iterate` | `{{body.data.body.txnList}}` |
| `output` | `{{item}}` |

### Module Communication — reference (`jsonc`)

```jsonc
/**
 * MODULE: settlementTxnListByDate
 * TYPE: Search (returns a list of settled transactions)
 * PAYTM ENDPOINT: RTDD via proxy
 * PROXY FUNCTION: settlementTxnListByDate
 *
 * RTDD/Settlement envelope — proxy builds the signed downstream body.
 * No checksum logic in IML.
 *
 * RESPONSE STRUCTURE
 *   Proxy wraps Paytm response: { status, function, requestId, data: <paytm_response> }
 *   Verify body.data.body.txnList iterate path during E2E testing.
 */
{
    "url": "{{connection.baseUrl}}/integration/settlementTxnListByDate?mid={{connection.merchantId}}",
    "method": "POST",
    "headers": {
        "X-Signature": "{{sha256(connection.merchantId; 'hex'; connection.keySecret; 'utf8')}}"
    },
    "body": {
        "requestId": "{{formatDate(now; 'X')}}000",
        "timestamp": "{{formatDate(now; 'X')}}000",
        "params": {
            "startDate": "{{formatDate(parameters.startDate; 'YYYY-MM-DD HH:mm:ss')}}",
            "endDate": "{{formatDate(parameters.endDate; 'YYYY-MM-DD HH:mm:ss')}}",
            "pageNum": "{{ifempty(parameters.pageNum; 1)}}",
            "pageSize": "{{ifempty(parameters.limit; 20)}}",
            "settlementOrderId": "{{parameters.settlementOrderId}}"
        }
    },
    "response": {
        // Verify body.data.body.txnList is the correct iterate path during E2E testing.
        "iterate": "{{body.data.body.txnList}}",
        "output": "{{item}}"
    }
}
```

### Module Communication (`JSON`, paste)

```json
{
    "url": "{{connection.baseUrl}}/integration/settlementTxnListByDate?mid={{connection.merchantId}}",
    "method": "POST",
    "headers": {
        "X-Signature": "{{sha256(connection.merchantId; 'hex'; connection.keySecret; 'utf8')}}"
    },
    "body": {
        "requestId": "{{formatDate(now; 'X')}}000",
        "timestamp": "{{formatDate(now; 'X')}}000",
        "params": {
            "startDate": "{{formatDate(parameters.startDate; 'YYYY-MM-DD HH:mm:ss')}}",
            "endDate": "{{formatDate(parameters.endDate; 'YYYY-MM-DD HH:mm:ss')}}",
            "pageNum": "{{ifempty(parameters.pageNum; 1)}}",
            "pageSize": "{{ifempty(parameters.limit; 20)}}",
            "settlementOrderId": "{{parameters.settlementOrderId}}"
        }
    },
    "response": {
        "iterate": "{{body.data.body.txnList}}",
        "output": "{{item}}"
    }
}
```

---

## 11. `fetchSubscriptionStatus` (Action)
**Source:** [`app/modules/fetchSubscriptionStatus.jsonc`](../app/modules/fetchSubscriptionStatus.jsonc)
### Mappable parameters

| Parameter `name` | Notes |
|---|---|
| `custId` | Used in `params` — add matching Make form field |
| `linkId` | Used in `params` — add matching Make form field |
| `orderId` | Used in `params` — add matching Make form field |
| `subsId` | Used in `params` — add matching Make form field |

### Response mapping

| `output` | `{{body.data}}` |

### Module Communication — reference (`jsonc`)

```jsonc
/**
 * MODULE: fetchSubscriptionStatus
 * TYPE: Action (single-item response)
 * PAYTM ENDPOINT: POST /subscription/subscription/checkStatus (via proxy)
 * PROXY FUNCTION: fetchSubscriptionStatus
 *
 * At least one of subsId / orderId / linkId / custId should be provided.
 *
 * RESPONSE STRUCTURE
 *   Proxy wraps Paytm response: { status, function, requestId, data: <paytm_response> }
 *   Verify body.data path during E2E testing.
 */
{
    "url": "{{connection.baseUrl}}/integration/fetchSubscriptionStatus?mid={{connection.merchantId}}",
    "method": "POST",
    "headers": {
        "X-Signature": "{{sha256(connection.merchantId; 'hex'; connection.keySecret; 'utf8')}}"
    },
    "body": {
        "requestId": "{{formatDate(now; 'X')}}000",
        "timestamp": "{{formatDate(now; 'X')}}000",
        "params": {
            "subsId": "{{parameters.subsId}}",
            "orderId": "{{parameters.orderId}}",
            "linkId": "{{parameters.linkId}}",
            "custId": "{{parameters.custId}}"
        }
    },
    "response": {
        "output": "{{body.data}}"
    }
}
```

### Module Communication (`JSON`, paste)

```json
{
    "url": "{{connection.baseUrl}}/integration/fetchSubscriptionStatus?mid={{connection.merchantId}}",
    "method": "POST",
    "headers": {
        "X-Signature": "{{sha256(connection.merchantId; 'hex'; connection.keySecret; 'utf8')}}"
    },
    "body": {
        "requestId": "{{formatDate(now; 'X')}}000",
        "timestamp": "{{formatDate(now; 'X')}}000",
        "params": {
            "subsId": "{{parameters.subsId}}",
            "orderId": "{{parameters.orderId}}",
            "linkId": "{{parameters.linkId}}",
            "custId": "{{parameters.custId}}"
        }
    },
    "response": {
        "output": "{{body.data}}"
    }
}
```

---

## 12. `pauseResumeSubscription` (Action)
**Source:** [`app/modules/pauseResumeSubscription.jsonc`](../app/modules/pauseResumeSubscription.jsonc)
### Mappable parameters

| Parameter `name` | Notes |
|---|---|
| `status` | Used in `params` — add matching Make form field |
| `subsId` | Used in `params` — add matching Make form field |

### Response mapping

| `output` | `{{body.data}}` |

### Module Communication — reference (`jsonc`)

```jsonc
/**
 * MODULE: pauseResumeSubscription
 * TYPE: Action (single-item response)
 * PAYTM ENDPOINT: POST /subscription/subscription/status/modify (via proxy)
 * PROXY FUNCTION: pauseResumeSubscription
 *
 * status: SUSPENDED (pause) / ACTIVE (resume)
 *
 * RESPONSE STRUCTURE
 *   Proxy wraps Paytm response: { status, function, requestId, data: <paytm_response> }
 *   Verify body.data path during E2E testing.
 */
{
    "url": "{{connection.baseUrl}}/integration/pauseResumeSubscription?mid={{connection.merchantId}}",
    "method": "POST",
    "headers": {
        "X-Signature": "{{sha256(connection.merchantId; 'hex'; connection.keySecret; 'utf8')}}"
    },
    "body": {
        "requestId": "{{formatDate(now; 'X')}}000",
        "timestamp": "{{formatDate(now; 'X')}}000",
        "params": {
            "subsId": "{{parameters.subsId}}",
            "status": "{{parameters.status}}"
        }
    },
    "response": {
        "output": "{{body.data}}"
    }
}
```

### Module Communication (`JSON`, paste)

```json
{
    "url": "{{connection.baseUrl}}/integration/pauseResumeSubscription?mid={{connection.merchantId}}",
    "method": "POST",
    "headers": {
        "X-Signature": "{{sha256(connection.merchantId; 'hex'; connection.keySecret; 'utf8')}}"
    },
    "body": {
        "requestId": "{{formatDate(now; 'X')}}000",
        "timestamp": "{{formatDate(now; 'X')}}000",
        "params": {
            "subsId": "{{parameters.subsId}}",
            "status": "{{parameters.status}}"
        }
    },
    "response": {
        "output": "{{body.data}}"
    }
}
```

---

## 13. `cancelSubscription` (Action)
**Source:** [`app/modules/cancelSubscription.jsonc`](../app/modules/cancelSubscription.jsonc)
### Mappable parameters

| Parameter `name` | Notes |
|---|---|
| `subsId` | Used in `params` — add matching Make form field |

### Response mapping

| `output` | `{{body.data}}` |

### Module Communication — reference (`jsonc`)

```jsonc
/**
 * MODULE: cancelSubscription
 * TYPE: Action (single-item response)
 * PAYTM ENDPOINT: POST /subscription/subscription/cancel (via proxy)
 * PROXY FUNCTION: cancelSubscription
 *
 * RESPONSE STRUCTURE
 *   Proxy wraps Paytm response: { status, function, requestId, data: <paytm_response> }
 *   Verify body.data path during E2E testing.
 */
{
    "url": "{{connection.baseUrl}}/integration/cancelSubscription?mid={{connection.merchantId}}",
    "method": "POST",
    "headers": {
        "X-Signature": "{{sha256(connection.merchantId; 'hex'; connection.keySecret; 'utf8')}}"
    },
    "body": {
        "requestId": "{{formatDate(now; 'X')}}000",
        "timestamp": "{{formatDate(now; 'X')}}000",
        "params": {
            "subsId": "{{parameters.subsId}}"
        }
    },
    "response": {
        "output": "{{body.data}}"
    }
}
```

### Module Communication (`JSON`, paste)

```json
{
    "url": "{{connection.baseUrl}}/integration/cancelSubscription?mid={{connection.merchantId}}",
    "method": "POST",
    "headers": {
        "X-Signature": "{{sha256(connection.merchantId; 'hex'; connection.keySecret; 'utf8')}}"
    },
    "body": {
        "requestId": "{{formatDate(now; 'X')}}000",
        "timestamp": "{{formatDate(now; 'X')}}000",
        "params": {
            "subsId": "{{parameters.subsId}}"
        }
    },
    "response": {
        "output": "{{body.data}}"
    }
}
```

---

## 14. `makeApiCall` (Universal)
**Source:** [`app/modules/makeApiCall.jsonc`](../app/modules/makeApiCall.jsonc)
### Mappable parameters

| Parameter `name` | Notes |
|---|---|
| `body` | Used in `params` — add matching Make form field |
| `headers` | Used in `params` — add matching Make form field |
| `method` | Used in `params` — add matching Make form field |
| `url` | Used in `params` — add matching Make form field |

### Response mapping

| `output` | `{{body.data}}` |

### Module Communication — reference (`jsonc`)

```jsonc
/**
 * MODULE: makeApiCall
 * TYPE: Universal (required by Make platform — one per app)
 * PURPOSE: Custom Paytm API call for endpoints not covered by other modules.
 *
 * IMPORTANT — RELATIVE PATHS ONLY
 *   The `url` parameter must be a relative path, e.g. /link/fetch
 *   The proxy prepends the Paytm base URL server-side.
 *   Make will reject absolute URLs (https://...) in Universal modules.
 *
 * PROXY FUNCTION: makeApiCall
 *   The proxy forwards params.url + params.method + params.body to the
 *   corresponding Paytm endpoint, applying the correct AES checksum.
 */
{
    "url": "{{connection.baseUrl}}/integration/makeApiCall?mid={{connection.merchantId}}",
    "method": "POST",
    "headers": {
        "X-Signature": "{{sha256(connection.merchantId; 'hex'; connection.keySecret; 'utf8')}}"
    },
    "body": {
        "requestId": "{{formatDate(now; 'X')}}000",
        "timestamp": "{{formatDate(now; 'X')}}000",
        "params": {
            "method": "{{parameters.method}}",
            "url": "{{parameters.url}}",
            "headers": "{{parameters.headers}}",
            "body": "{{parameters.body}}"
        }
    },
    "response": {
        "output": "{{body.data}}"
    }
}
```

### Module Communication (`JSON`, paste)

```json
{
    "url": "{{connection.baseUrl}}/integration/makeApiCall?mid={{connection.merchantId}}",
    "method": "POST",
    "headers": {
        "X-Signature": "{{sha256(connection.merchantId; 'hex'; connection.keySecret; 'utf8')}}"
    },
    "body": {
        "requestId": "{{formatDate(now; 'X')}}000",
        "timestamp": "{{formatDate(now; 'X')}}000",
        "params": {
            "method": "{{parameters.method}}",
            "url": "{{parameters.url}}",
            "headers": "{{parameters.headers}}",
            "body": "{{parameters.body}}"
        }
    },
    "response": {
        "output": "{{body.data}}"
    }
}
```

---

## Related

- [`make-connection-paytm.md`](./make-connection-paytm.md)
- [`api-mapping.md`](./api-mapping.md)
- [`checksum-algorithm.md`](./checksum-algorithm.md)
- [`e2e-integration-testing.md`](./e2e-integration-testing.md)
