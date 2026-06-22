# YieldZero Enforced Composer - Audit Findings

## F2: Share Transfer Bypass
- **Severity**: High
- **Description**: The Deposit Cap could be bypassed because `userShares` only tracked composer operations and ignored ERC20 share transfers.
- **Impact**: Users could exceed their individual deposit caps.

## F3: TVL Unit Mismatch 
- **Severity**: High
- **Description**: TVL accounting was decrementing shares instead of assets during cross-chain operations.
- **Impact**: Led to TVL accounting drift and potential underflow/overflow.

## F5: Rate Limiter DoS
- **Severity**: Medium
- **Description**: `recordOperation()` lacked access control, allowing malicious actors to exhaust rate limits.
- **Impact**: Denial of Service on cross-chain transfers.
