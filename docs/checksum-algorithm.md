# Paytm Checksum Algorithm — Reference & Proxy Rationale

> **Make IML cannot compute the Paytm checksum.**
> All checksum generation is handled server-side by the merchant-adapter signing proxy.
> Module JSONC files only need to send an HMAC-SHA256 inbound auth header (`X-Signature`) to the proxy.
> This document is reference material — it explains WHY the proxy exists.

---

## Full Paytm Checksum Algorithm (Official SDK)

```
signingString = sortedParamValues.join('|') + '|' + salt
sha256Hash    = SHA-256( signingString )
checksum      = AES-128-CBC( sha256Hash + '|' + salt, keySecret, IV="@@@@&&&&####$$" )
```

Steps in detail:

1. Collect all body parameters that are part of the signed payload for the endpoint.
2. **Sort their keys alphabetically** (case-sensitive, ASCII order).
3. For each key in sorted order, append its value followed by `|`.
4. Append `keySecret` (no trailing `|` after it).
5. Compute `SHA-256` of the full string — this is the hash.
6. Encrypt `(hash + "|" + salt)` with AES-128-CBC using `keySecret` as the encryption key and `"@@@@&&&&####$$"` as the fixed IV.
7. Base64-encode the AES output — this is the final `paytmChecksum`.

Reference implementation: `PaytmChecksum.java` in Paytm's Java SDK.

---

## Why Make IML Cannot Do This

Make's IML crypto functions: `sha256()`, `hmac()`, `base64()`, `md5()`.

Step 5 (SHA-256) is possible. Step 6 (AES-128-CBC encryption) is **not available in IML** — there is no `aes()` or `encrypt()` function.

Attempting to use only SHA-256 (without the AES layer) produces a wrong checksum that Paytm will reject with `CHECKSUM_INVALID`.

---

## What Make Modules Do Instead

Modules authenticate to the proxy using HMAC-SHA256 (which IML _can_ compute):

```jsonc
"headers": {
    "X-Signature": "{{hmac(json(body); connection.keySecret; 'sha256')}}"
},
"body": {
    "requestId": "{{uuid()}}",
    "timestamp": "{{toTimestamp(now)}}",
    "params": { ...module params... }
}
```

The proxy:
1. Verifies `X-Signature` = HMAC-SHA256(raw body, keySecret).
2. Extracts `params` from the body.
3. Builds the full Paytm checksum (SHA-256 + AES) server-side.
4. Forwards the signed request to Paytm.

---

## Settlement Envelope (modules 5, 9, 10)

RTDD and settlement APIs use a different envelope format:

```json
{ "request": { "body": {...}, "head": {...} }, "signature": "<checksum>" }
```

This is also handled entirely by the proxy (`buildRtddSignedDownstreamBody` in `WrapperExecuteHelper`).

---

## Signing Key Order Per Module (reference)

| Module | Signed Keys (alphabetical order) |
|--------|----------------------------------|
| `fetchPaymentLinks` | fromDate · mid · pageNumber · pageSize · toDate |
| `fetchTransactionsForLink` | linkId · mid · pageNumber · pageSize |
| `createPaymentLink` | amount · currency · mid · orderId |
| `fetchRefundList` | fromDate · mid · pageNumber · pageSize · toDate |
| `checkRefundStatus` | mid · refId · txnId |
| `initiateRefund` | mid · orderId · refAmount · refId · txnId · txnType |
| RTDD modules (fetchOrderList, orderDetail, settlementBillList, settlementTxnListByDate) | Proxy-handled — different envelope |
