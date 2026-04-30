# Paytm Checksum Algorithm — Implementation Guide

This document explains the Paytm checksum algorithm and how it is implemented in Make's IML.

---

## Algorithm (Official Paytm SDK)

```
signingString = sortedValues.join('|') + '|' + keySecret
checksum      = Base64( SHA-256( signingString ) )
```

Steps in detail:

1. Take all body parameters that are **part of the signed payload** for the endpoint.
2. **Sort their keys alphabetically** (case-sensitive, ASCII order).
3. Build the signing string: for each key in sorted order, append its value followed by `|`.
4. Append `keySecret` (no trailing `|` after the secret — the last `|` comes from the last body param).
5. Compute `SHA-256` of the full string and `Base64`-encode the raw digest.

Reference: `PaytmChecksum.js` in the official Paytm PHP/Node SDK.

---

## Make IML Implementation

### The Problem

Make's `sha256(input; encoding)` function accepts a single string expression.  
Building the signing string requires calling `formatDate()`, `ifempty()`, and `toString()` on individual parameters, then concatenating them.

Make's IML parser fails with **"Unexpected end of string"** when more than ~3 such nested calls are concatenated inside a single `sha256()` expression.

### The Solution — `temp` block

Make supports a `temp` block in module communications JSON. It is evaluated **before** `body`, `headers`, and `url`, and its values are available as `temp.<name>`.

Each `temp` entry:
- Applies the necessary IML function (`formatDate`, `ifempty`, `toString`).
- Appends the `|` separator that the Paytm algorithm requires.

The `sha256()` call then concatenates only `temp.*` property references — no nested function calls — staying within the parser limit.

```jsonc
"temp": {
    "sd":     "{{formatDate(parameters.startDate; 'YYYY-MM-DD') + '|'}}",
    "isSort": "true|",
    "mid":    "{{connection.merchantId + '|'}}",
    // ...
},
"body": {
    "paytmChecksum": "{{sha256(temp.sd + temp.isSort + temp.mid + ...; 'base64')}}"
}
```

---

## Signing Key Order Per Module

Every module's `.jsonc` file documents the exact signing key order. Quick reference:

| Module | Signed Keys (alphabetical) |
|--------|---------------------------|
| `listOrders` | fromDate · isSort · mid · orderSearchStatus · orderSearchType · pageNumber · pageSize · toDate |
| `listPaymentLinks` | fromDate · mid · pageNumber · pageSize · toDate |
| `listTransactionsForLink` | linkId · mid · pageNumber · pageSize |
| `createPaymentLink` | amount · currency · mid · orderId |
| `listRefunds` | fromDate · mid · pageNumber · pageSize · toDate |
| `checkRefundStatus` | mid · refId · txnId |
| `initiateRefund` | mid · orderId · refAmount · refId · txnId · txnType |

> **RTDD modules** use a different authentication mechanism (Signed Request Envelope) — see the RTDD module files for details.

---

## Verifying a Checksum Locally

```bash
# Node.js one-liner to verify the checksum for a known payload
node -e "
const crypto = require('crypto');
const params = { fromDate:'2025-01-01', isSort:'true', mid:'YOUR_MID', orderSearchStatus:'ALL', orderSearchType:'TRANSACTION', pageNumber:'1', pageSize:'10', toDate:'2025-01-31' };
const str = Object.keys(params).sort().map(k => params[k]).join('|') + '|YOUR_KEY_SECRET';
console.log(Buffer.from(crypto.createHash('sha256').update(str).digest()).toString('base64'));
"
```
