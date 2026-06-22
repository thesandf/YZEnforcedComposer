# YieldZero Enforced Composer - Remediation Report

## F2: Share Transfer Bypass
- **Status:** Resolved via Protocol Redesign
- **Original Behavior:** Cap enforced cumulative lifetime deposits.
- **New Behavior:** Maximum Ownership Cap enforced. The system now checks `IERC20(SHARE_ERC20).balanceOf(user)` to strictly limit maximum current wallet ownership.
- **Regression Test:** `test/regression/F2_ShareTransferBypassRegression.t.sol`

## F3: TVL Unit Mismatch
- **Status:** Resolved
- **Fix:** Decrement TVL by actual `expectedAssets` returned by the Vault, not by the shares amount.
- **Regression Test:** `test/regression/F3_TVLUnitMismatchRegression.t.sol`

## F5: RateLimiter DoS
- **Status:** Resolved
- **Fix:** Restricted `recordOperation()` to authorized paths, separating rate limits by entry point. Added custom errors.
- **Regression Test:** `test/regression/F5_RateLimiterAuthorizationRegression.t.sol`
