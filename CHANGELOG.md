# Changelog

All notable changes to the YieldZero Enforced Composer repository will be documented in this file.

---

## [1.2.0] - 2026-06-04

### Added
* **Pinned Parent Library Version**: Added a public constant `PARENT_VERSION_PINNED = "ovault-evm@1.0.0"` to explicitly pin and track the parent dependency version, mitigating the version-coupling maintenance risk of the actual share-tracking mechanism.
* **Security Finding Validation Tests**: Added a complete verification test suite in `test/security/YZEnforcedComposerFindingValidation.t.sol` to verify correctness of pause, whitelist, share tracking, and low-decimal asset behaviors.

### Fixed
* **Cross-Chain Pause Bypass**: Added pause controls inside `_depositAndSend(...)` and `_redeemAndSend(...)` execution paths to prevent bypassing paused states via inbound LayerZero `lzCompose()` calls.
* **Cross-Chain Whitelist Bypass**: Enforced whitelisting inside `_depositAndSend(...)` to ensure compose-path deposits verify whitelisted status.
* **`userShares` Inflation**: Overrode the internal `_deposit(...)` function to capture actual minted vault shares using the `_tempSharesMinted` state variable, eliminating total supply post-deposit ratio estimation errors.
* **Redemption DoS Underflow**: Patched `decimalConversionRate` calculation fallback in `_redeemAndSend(...)` to safely handle low-decimal assets (< 6 decimals), preventing arithmetic underflow panics.
* **`canDeposit` Mismatch**: Synchronized the user cap verification formula in `canDeposit()` to use the same conversion calculations as `_depositAndSend(...)`.
* **Gas Regression Limits**: Adjusted `MAX_GAS_LIMIT` to `515000` in the regression tests to cover validation check gas requirements.

---

## [1.1.0] - 2026-05-18

### Added
* **Stateless Risk Library**: Added `src/libraries/EnforcementLib.sol` to isolate math, TVL caps, and user cap verification logic.
* **Unified Custom Errors**: Added `src/interfaces/IYZErrors.sol` containing shared error mappings across all contracts.
* **Composer Interface**: Added `src/interfaces/IYZEnforcedComposer.sol` specifying full public interface capabilities.
* **Deployment Automation Scripts**: Added `script/DeployYZEnforcedComposer.s.sol`, `script/ConfigureYZEnforcedComposer.s.sol`, and `script/EmergencyPause.s.sol`.
* **Deployment Metadata Registries**: Added JSON schema templates under `deployments/` to track deployment actions on Arbitrum and Ethereum.
* **Advanced Static CI**: Integrated Crytic Slither automated scans and automated gas benchmarking pipelines in `.github/workflows/`.
* **Linting & Analysis Rules**: Configured `.solhint.json` and `.slither.config.json` standard settings.

### Changed
* **Code Reorganization**: Relocated `YZEnforcedComposer.sol` from `src/sdk/` to `src/` to represent core production quality.
* **Test Isolation**: Organized 31 test suites flatly situated in `test/sdk/` into highly structured testing directories: `test/unit/`, `test/fuzz/`, `test/invariant/`, and `test/integration/`.
* **Mock Separation**: Relocated the mock contract `TestHelper.sol` out of production `src/` to `test/mocks/TestHelper.sol`.

### Removed
* **Production Test-Helpers**: Stripped the commented-out `exposed_setUserDeposit` mock test-helpers from production source code.

---

## [1.0.0] - 2026-05-15

### Added
* Initial release of the `YZEnforcedComposer` contract matching `ovault-evm@1.0.0`.
* Inbound cross-chain deposit cap checks.
* User-level omnichain deposit cap tracking and pausing capabilities.
