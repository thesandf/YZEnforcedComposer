# Security Audit Report: YZEnforcedComposer

**Protocol:** YZEnforcedComposer
**Audited Branch:** Audit/Original-state
**Solidity Version:** `^0.8.26`
**Version Audited:** `ovault-evm@1.0.0` (pinned dependency) 
**Audit Date:** Mar 2 2026
**Auditor:** thesandf
**Scope:** `src/sdk/YZEnforcedComposer.sol`
**Assessment Type:** Manual Review + Targeted Foundry Regression Testing
**Severity Scale:** Critical / High / Medium / Low / Informational

---

# Executive Summary

YZEnforcedComposer extends LayerZero V2’s vault compose flow with protocol-level enforcement controls including:

* TVL caps
* Per-user deposit caps
* Deposit pause controls
* Whitelist gating
* Emergency admin recovery functions

The protocol architecture demonstrates a strong understanding of LayerZero compose execution and ERC4626 accounting semantics. In particular:

* enforcement is inserted at the correct execution layer,
* LayerZero retry/refund guarantees are preserved,
* and ERC4626 share accounting is mostly handled correctly.

The audit identified:

* **2 Medium severity vulnerabilities**
* **4 Low severity issues**
* **2 Informational findings**

No Critical or High severity vulnerabilities were identified.

Importantly, this report applies to the **original vulnerable branch** only.

After this audit, the contract was fully refactored and the vulnerable implementation no longer exists in the current codebase. The fixes described here were validated independently through dedicated regression tests.

---

# Scope

| File                             | Description                     |
| -------------------------------- | ------------------------------- |
| `src/sdk/YZEnforcedComposer.sol` | Primary audit target            |
| `README.md`                      | Protocol architecture reference |
| `foundry.toml`                   | Build configuration             |

### Out of Scope

* LayerZero upstream contracts
* `VaultComposerSync`
* ERC4626 vault internals
* OFT implementations

---

# Findings Summary

| ID      | Title                                                                     | Severity      | Status            |
| ------- | ------------------------------------------------------------------------- | ------------- | ----------------- |
| YZ-M-01 | Slippage validation bypass due to OFT truncation mismatch                 | Medium        | Fixed in refactor |
| YZ-M-02 | `canDeposit()` share-cap desynchronization allows false-positive deposits | Medium        | Fixed in refactor |
| YZ-L-01 | Missing zero-address validation in batch setters                          | Low           | Fixed in refactor |
| YZ-L-02 | Single-step admin transfer risks permanent admin loss                     | Low           | Fixed in refactor |
| YZ-L-03 | `emergencyWithdrawNative()` emits no event                                | Low           | Fixed in refactor |
| YZ-L-04 | Inconsistent revert style (`require` strings vs custom errors)            | Low           | Fixed in refactor |
| YZ-I-01 | TVL cap race condition inherent to async compose execution                | Informational | Acknowledged      |
| YZ-I-02 | Full `_redeemAndSend()` replication increases upgrade fragility           | Informational | Acknowledged      |

---

# Detailed Findings

---

# YZ-M-01 - Slippage Validation Bypass Due to OFT Truncation Mismatch

**Severity:** Medium
**Status:** Fixed in refactor

## Description

The overridden `_redeemAndSend()` implementation manually performed slippage validation before forwarding assets through the OFT bridge flow.

The implementation validated slippage using the raw `assetAmountReceived` value:

```solidity
_assertSlippage(assetAmountReceived, _sendParam.minAmountLD);
```

After validation, the function disabled the OFT’s internal slippage check by setting:

```solidity
_sendParam.minAmountLD = 0;
```

The issue is that OFT transfers truncate values to `sharedDecimals` precision during `_send()`.

As a result, the amount validated by `_assertSlippage()` could be larger than the amount actually delivered cross-chain after truncation.

Because the OFT check was disabled, the truncation discrepancy was never caught.

---

## Proof of Concept

```text
assetAmountReceived = 1_000_001
minAmountLD        = 1_000_001

Pre-send slippage check:
_assertSlippage(1_000_001, 1_000_001) → passes

OFT truncation:
actual bridged amount = 1_000_000

User receives less than minAmountLD
Transaction does NOT revert
```

---

## Impact

Users could receive slightly less than their requested minimum amount without transaction failure.

The value difference is typically small, but the protocol violates its own slippage guarantees.

---

## Recommendation

Apply the same OFT truncation logic before validating slippage:

```solidity
uint256 truncatedAmount =
    (assetAmountReceived / decimalConversionRate)
        * decimalConversionRate;

_assertSlippage(truncatedAmount, _sendParam.minAmountLD);

_sendParam.amountLD = truncatedAmount;
_sendParam.minAmountLD = 0;
```

---

# YZ-M-02 - `canDeposit()` Share-Cap Desynchronization Allows False-Positive Deposits

**Severity:** Medium
**Status:** Fixed in refactor

## Description

The original implementation enforced per-user caps using raw asset amounts inside `canDeposit()`:

```solidity
uint256 currentDeposit = userShares[_user];

if (currentDeposit + _amount > userDepositCap[_user]) {
    return (false, "User cap exceeded");
}
```

This assumes:

```text
1 asset == 1 share
```

which is incorrect for ERC4626 vaults once share price changes.

After vault losses or asset burns, the vault exchange rate changes such that:

```text
1 asset > 1 share
```

At that point:

* `canDeposit()` still validates using raw asset amounts,
* while the actual deposit path uses `previewDeposit()` share math.

This creates a mismatch where:

* `canDeposit()` incorrectly returns `true`,
* but `depositAndSend()` later reverts with `YZ_UserCapExceeded`.

---

## Vulnerable Scenario

### Initial State

```text
User cap = 101 shares
User deposits 100 assets
Vault mints 100 shares
```

### Vault Loss Event

Vault loses 50 assets:

```text
Vault assets: 50
Vault shares: 100
```

Now:

```text
1 asset ≈ 2 shares
```

### Second Deposit

User calls:

```solidity
canDeposit(user, 1 ether)
```

Old logic checks:

```text
100 + 1 <= 101
```

and incorrectly returns:

```text
allowed = true
```

But the actual deposit path calculates:

```text
previewDeposit(1 ether) ≈ 2 shares
```

Result:

```text
100 + 2 > 101
```

which correctly reverts during execution.

---

## Proof of Vulnerability

The vulnerable branch reproduced this exact inconsistency.

### Vulnerable Behavior

```solidity
(bool allowed,) =
    yzEnforcedComposer_arb.canDeposit(userA, 1 ether);

assertTrue(allowed);
```

followed by:

```solidity
vm.expectRevert(
    abi.encodeWithSelector(
        YZEnforcedComposer.YZ_UserCapExceeded.selector,
        userA,
        100 ether,
        1999999999999999999,
        101 ether
    )
);

yzEnforcedComposer_arb.depositAndSend(1 ether, p, userA);
```

The transaction reverted because the actual share mint exceeded the cap despite `canDeposit()` previously approving it.

---

## Impact

This breaks the correctness guarantees of `canDeposit()`.

Integrators, frontends, routers, or off-chain automation relying on `canDeposit()` may:

* incorrectly display deposits as valid,
* submit transactions that always revert,
* or mis-handle risk validation logic.

---

## Recommendation

Validate caps using the actual share-equivalent amount:

```solidity
uint256 shares = VAULT.previewDeposit(_amount);

if (userShares[_user] + shares > userDepositCap[_user]) {
    return (false, "User cap exceeded");
}
```

---

# YZ-L-01 - Missing Zero-Address Validation in Batch Setters

**Severity:** Low
**Status:** Fixed in refactor

## Description

Batch setter functions failed to validate `address(0)` entries.

Affected functions:

* `batchSetUserCaps()`
* `batchSetWhitelist()`

An accidental zero address in admin scripts would silently modify state for the null address.

---

## Recommendation

Validate every entry:

```solidity
if (_users[i] == address(0)) revert YZ_ZeroAddress();
```

---

# YZ-L-02 - Single-Step Admin Transfer Risks Permanent Admin Loss

**Severity:** Low
**Status:** Fixed in refactor

## Description

The original admin transfer mechanism immediately replaced the admin:

```solidity
admin = _newAdmin;
```

A mistaken address permanently transferred protocol control.

---

## Recommendation

Use a two-step admin handoff:

```solidity
proposeAdmin()
acceptAdmin()
```

---

# YZ-L-03 - `emergencyWithdrawNative()` Emits No Event

**Severity:** Low
**Status:** Fixed in refactor

## Description

Native asset withdrawals emitted no event, reducing observability for monitoring systems.

---

## Recommendation

Emit:

```solidity
event EmergencyWithdrawNative(address indexed to, uint256 amount);
```

---

# YZ-L-04 - Inconsistent Revert Style

**Severity:** Low
**Status:** Fixed in refactor

## Description

The codebase mixed:

* custom errors
* string-based `require()` statements

This increases gas costs and reduces consistency.

---

## Recommendation

Replace legacy string reverts with custom errors.

---

# YZ-I-01 - TVL Cap Race Condition

**Severity:** Informational

## Description

TVL enforcement is subject to asynchronous compose execution ordering.

Two deposits processed in the same block may both observe the same TVL before state updates complete.

This is an unavoidable limitation of asynchronous cross-chain execution.

---

## Recommendation

Document the limitation and configure TVL caps conservatively.

---

# YZ-I-02 - `_redeemAndSend()` Replication Increases Upgrade Fragility

**Severity:** Informational

## Description

The override replicated upstream parent logic instead of calling `super`.

This was architecturally necessary but creates maintenance risk:

future upstream changes will not automatically propagate.

---

## Recommendation

Review replicated logic on every upstream dependency upgrade.

---

# Regression Validation

All identified vulnerabilities were independently reproduced on the vulnerable branch and validated against the refactored implementation.

---

## YZ-M-02 Regression Validation

### Vulnerable Branch

The vulnerable branch demonstrated the inconsistency:

```text
canDeposit() → returns true
depositAndSend() → reverts with YZ_UserCapExceeded
```

The Foundry test:

```solidity
test_Vuln_CanDepositAllowsDepositThatActuallyExceedsCap()
```

successfully reproduced the bug.

---

### Refactored Implementation

After the fix, `canDeposit()` correctly used:

```solidity
VAULT.previewDeposit(_amount)
```

instead of raw asset amounts.

The vulnerable scenario now fails during validation itself:

```text
canDeposit() → returns false
```

The original vulnerable assertion:

```solidity
assertTrue(allowed);
```

now correctly fails because the contract rejects the deposit before execution.

A dedicated regression test confirmed the fix:

```solidity
test_Fixed_CanDepositRejectsDepositThatWouldExceedShareCap()
```

Result:

```text
[PASS]
```

This validates that the original vulnerability was real and fully resolved in the refactored implementation.

---

# Architecture Notes

The following design decisions were reviewed and considered correct:

* Enforcement occurs at the correct compose execution layer.
* LayerZero retry/refund guarantees remain intact.
* ERC4626 share accounting is mostly well understood.
* The protocol correctly avoids interfering with LayerZero compose replay semantics.
* Deposit tracking via TVL delta was architecturally sound aside from the share-cap mismatch issue.

---

# Disclaimer

This audit reflects the state of the vulnerable audited branch at the time of review.

The current codebase has since been refactored and no longer contains the exact vulnerable implementation discussed in this report.

This report does not guarantee the absence of vulnerabilities. Smart contract security remains probabilistic and requires continuous review, testing, and operational monitoring.

---

*Report generated: May 2026*
*Auditor: thesandf*
