# Security Policy & Protocol Threat Model

## 1. Vulnerability Disclosure Process

At YieldZero, we prioritize protocol security and asset safety. If you discover a vulnerability or security issue within this repository, please follow our coordinated disclosure policy:

* **Reporting Channel**: Send a detailed description of the issue to **security@yieldzero.finance** or contact the core engineering team via our encrypted communication channels.
* **Encrypt Sensitive Reports**: If possible, encrypt your report using our core security PGP keys.
* **Do NOT Disclose Publicly**: Give us a reasonable response window to triage and patch the issue before making any public announcements.
* **Bug Bounty Scope**: The `YZEnforcedComposer` contract, along with its stateless library `EnforcementLib` and custom interfaces, is in active scope for our bug bounty program. High and critical findings qualify for payouts based on TVL-at-risk.

---

## 2. Protocol Threat Model

The `YZEnforcedComposer` contract operates on the execution-level boundary to enforce risk caps and whitelist constraints for LayerZero V2 omnichain ERC4626 vault operations. Its security architecture assumes the following trust boundaries:

### A. Trusted Roles
* **Admin / Owner**: The `admin` role is considered highly privileged. It holds administrative power to:
  * Adjust TVL caps (`setTVLCap`).
  * Modify individual and batch user deposit caps (`setUserCap`, `batchSetUserCaps`).
  * Enable/disable global whitelisting (`setWhitelistEnabled`, `setWhitelist`, `batchSetWhitelist`).
  * Execute emergency pausing (`pauseDeposits`, `pauseRedemptions`, `pauseAll`).
  * Withdraw stuck funds (`emergencyWithdraw`, `emergencyWithdrawShares`, `emergencyWithdrawNative`). This introduces a **custodial assumption**: if a cross-chain compose retry or refund path temporarily leaves user assets/shares inside the composer contract, the admin has the technical power to withdraw them. Users must trust the admin not to act maliciously during these periods.
  * **Mitigation**: In production networks, this role MUST reside within a multi-signature wallet (e.g., Gnosis Safe 3-of-5) or a decentralized governance time-lock.

### B. Core Integration Trust Boundaries
* **ERC4626 Vault**: The composer trusts the underlying `VAULT` contract (`totalAssets()`, `maxDeposit()`, standard ERC4626 conversions). If the vault's assets or share conversions are manipulated or exploited, the composer will inherit those state changes.
* **LayerZero OApp Stack**: The contract assumes LayerZero V2 endpoints are secure, decentralized, and functional. Reentrancy protections, message authenticity, replay protection, and the underlying bridging mechanics are delegated to LayerZero.
* **Asset & Share OFTs**: Standard LayerZero OFT and OFTAdapter contracts are trusted to manage cross-chain token wrapping correctly.

---

## 3. Incident Response and Pausability

In the event of an active bridge exploit, Oracle manipulation, or smart contract vulnerability:
1. **Immediate Action**: The Admin can trigger `pauseAll()` using our off-chain monitoring keepers or manual scripts.
2. **Impact**:
   * **Deposits Paused**: Rejects any inbound omnichain deposit commands, automatically reverting so that incoming funds are safely captured by LayerZero's try-catch mechanisms and returned to the refund address on the spoke chain.
   * **Redemptions Paused**: Blocks share redemptions. This is an extreme emergency measure to protect vault assets from drainage during an exploit. Pausing redemptions must be unpaused as soon as the threat is resolved.
