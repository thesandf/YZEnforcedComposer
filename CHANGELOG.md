# Changelog

All notable changes to the YieldZero Enforced Composer repository will be documented in this file.

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
