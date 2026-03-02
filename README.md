# YZEnforcedComposer

**Execution-level enforcement for LayerZero V2 OVault.**

---

## Table of Contents

1. [What is YZEnforcedComposer?](#what-is-yzenforcedcomposer)
2. [When Does It Work?](#when-does-it-work)
3. [How Does It Work?](#how-does-it-work)
4. [Architecture Diagrams](#architecture-diagrams)
5. [Flow Diagrams](#flow-diagrams)
6. [Reference](#api-reference)

---

## What is YZEnforcedComposer?

YZEnforcedComposer is a **smart contract extension** for LayerZero's `VaultComposerSync`. It adds **risk management controls** to cross-chain vault deposits and redemptions.

### The Problem

```
User (Spoke Chain) ──► Deposit 1000 USDC ──► Vault (Hub Chain)
                                              │
                                              ▼
                                        No limits!
                                        No caps!
                                        No control!
```

Without enforcement:
- Whale can deposit unlimited amount → TVL risk
- Single user can dominate vault → centralization risk
- No emergency pause → no circuit breaker
- Anyone can deposit → no access control

### The Solution

```
User (Spoke Chain) ──► Deposit 1000 USDC
                              │
                              ▼
                    YZEnforcedComposer
                              │
                              ├─► Check: TVL cap OK?
                              ├─► Check: User cap OK?
                              ├─► Check: Not paused?
                              ├─► Check: Whitelisted?
                              │
                              ▼
                        Vault (Hub Chain)
```

### Where It Fits

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                        LayerZero V2 OVault Architecture                     │
├─────────────────────────────────────────────────────────────────────────────┤
│  SPOKE CHAIN (eg, Ethereum)                │   HUB CHAIN (eg, Arbitrum)     │
│  ─────────────────────────────             │   ─────────────────────────    │
│                                            │                                │
│  ┌─────────────────┐                       │   ┌──────────────────────┐     │
│  │   AssetOFT      │                       │   │   AssetOFT (OFT)     │     │
│  │   (OFT)         │                       │   │                      │     │
│  │                 │                       │   │  Part of Asset Mesh  │     │
│  │  Part of Asset  │                       │   └──────────────────────┘     │
│  │  Mesh           │                       │              │                 │
│  └────────┬────────┘                       │              │                 │
│           │                                │              ▼                 │
│           │ 1. send() with composeMsg      │   ┌──────────────────────┐     │
│           │                                │   │  LayerZero Endpoint  │     │
│           ▼                                │   │                      │     │
│  ┌─────────────────────┐                   │   │ 2. lzReceive()       │     │
│  │  LayerZero Endpoint │                   │   │    - OFT mints       │     │
│  │                     │                   │   │      assets to       │     │
│  │                     │                   │   │      composer        │     │
│  └─────────────────────┘                   │   │    - Calls           │     │
│           │                                │   │      lzCompose()     │     │
│           │                                │   └──────────┬───────────┘     │
│           │                                │              │                 │
│           └──────── cross-chain message ───┼──────────────┘                 │
│                                            │              │                 │
│                                            │              ▼                 │
│                                            │   ┌──────────────────────┐     │
│                                            │   │ VaultComposerSync    │     │
│                                            │   │ (ReentrancyGuard)    │     │
│                                            │   │         │            │     │
│                                            │   │         ▼            │     │
│                                            │   │ ┌──────────────────┐ │     │
│                                            │   │ │YZEnforcedComposer│ │     │
│                                            │   │ │                  │ │     │
│                                            │   │ │ 3. Enforcement   │ │     │
│                                            │   │ │    Checks        │ │     │
│                                            │   │ └────────┬─────────┘ │     │
│                                            │   │          │           │     │
│                                            │   │          ▼           │     │
│                                            │   │ ┌──────────────────┐ │     │
│                                            │   │ │   ERC4626 Vault  │ │     │
│                                            │   │ └──────────────────┘ │     │
│                                            │   └──────────────────────┘     │
│                                            │                                │
│                                            │   ┌──────────────────────┐     │
│                                            │   │ ShareOFTAdapter      │     │
│                                            │   │ (Lockbox Model)      │◄──  Share OFT wraps
│                                            │   │                      │     │  vault shares
│                                            │   │  Locks vault shares  │     │
│                                            │   │  for cross-chain     │     │
│                                            │   └──────────────────────┘     │
│                                            │                                │
└────────────────────────────────────────────┼────────────────────────────────┘
                                             │
                    ┌────────────────────────┴───────────────────────────┐
                    │             KEY ARCHITECTURE POINTS                │
                    ├────────────────────────────────────────────────────┤
                    │  • Two OFT Meshes: Asset Mesh + Share Mesh         │
                    │  • ShareOFTAdapter uses lockbox model on hub       │
                    │  • Sequential flow: lzReceive → lzCompose          │
                    │  • Permissionless recovery: anyone can retry       │
                    │  • YZEnforcedComposer adds: caps, pause, whitelist │
                    └────────────────────────────────────────────────────┘
```

---

## When Does It Work?

### Trigger Points

```
┌─────────────────────────────────────────────────────────────┐
│                    YZEnforcedComposer                       │
│                                                             │
│  ┌─────────────────┐        ┌─────────────────┐             │
│  │ depositAndSend()│        │ redeemAndSend() │             │
│  │                 │        │                 │             │
│  │  Called when:   │        │  Called when:   │             │
│  │  User deposits  │        │  User redeems   │             │
│  │  assets to vault│        │  shares for     │             │
│  │                 │        │  assets         │             │
│  └────────┬────────┘        └────────┬────────┘             │
│           │                          │                      │
│           ▼                          ▼                      │
│  ┌─────────────────────────────────────────────────┐        │
│  │              _depositAndSend()                  │        │
│  │                                                 │        │
│  │  Enforcement happens HERE:                      │        │
│  │  • TVL cap check                                │        │
│  │  • User cap check                               │        │
│  │  • Pause check                                  │        │
│  │  • Whitelist check                              │        │
│  └─────────────────────────────────────────────────┘        │
│                                                             │
│  Also triggered via lzCompose() for cross-chain operations  │
└─────────────────────────────────────────────────────────────┘
```

### Execution Contexts

| Context | Entry Point | Flow |
|---------|-------------|------|
| Local deposit | `depositAndSend()` | User → Composer → Vault |
| Local redeem | `redeemAndSend()` | User → Composer → Vault |
| Cross-chain deposit | `lzCompose()` → `_depositAndSend()` | OFT → Composer → Vault |
| Cross-chain redeem | `lzCompose()` → `_redeemAndSend()` | OFT → Composer → Vault |

---

## How Does It Work?

### Enforcement Mechanism

```
┌──────────────────────────────────────────────────────────────┐
│                     Enforcement Flow                         │
├──────────────────────────────────────────────────────────────┤
│                                                              │
│   User Action                                                │
│       │                                                      │
│       ▼                                                      │
│   ┌───────────────────────────────────────────┐              │
│   │           Check: Paused?                  │              │
│   │                                           │              │
│   │   paused == true ──► REVERT ──► YZ_Paused │              │
│   └───────────────────┬───────────────────────┘              │
│                       │                                      │
│                       ▼                                      │
│   ┌───────────────────────────────────────────┐              │
│   │         Check: Whitelist?                 │              │
│   │                                           │              │
│   │   whitelistEnabled && !whitelist[user]    │              │
│   │            │                              │              │
│   │            ▼                              │              │
│   │   REVERT ──► "YZ: not whitelisted"        │              │
│   └───────────────────┬───────────────────────┘              │
│                       │                                      │
│                       ▼                                      │
│   ┌───────────────────────────────────────────┐              │
│   │         Check: TVL Cap?                   │              │
│   │                                           │              │
│   │   tvlCap > 0 &&                           │              │
│   │   currentTVL + amount > tvlCap            │              │
│   │            │                              │              │
│   │            ▼                              │              │
│   │   REVERT ──► YZ_TVLCapExceeded            │              │
│   └───────────────────┬───────────────────────┘              │
│                       │                                      │
│                       ▼                                      │
│   ┌───────────────────────────────────────────┐              │
│   │         Check: User Cap?                  │              │
│   │                                           │              │
│   │   userCap[user] > 0 &&                    │              │
│   │   userDeposits[user] + amount > userCap   │              │
│   │            │                              │              │
│   │            ▼                              │              │
│   │   REVERT ──► YZ_UserCapExceeded           │              │
│   └───────────────────┬───────────────────────┘              │
│                       │                                      │
│                       ▼                                      │
│   ┌───────────────────────────────────────────┐              │
│   │         Check: Vault Capacity?            │              │
│   │                                           │              │
│   │   amount > vault.maxDeposit(this)         │              │
│   │            │                              │              │
│   │            ▼                              │              │
│   │   REVERT ──► ERC4626ExceededMaxDeposit    │              │
│   └───────────────────┬───────────────────────┘              │
│                       │                                      │
│                       ▼                                      │
│   ┌───────────────────────────────────────────┐              │
│   │         ALL CHECKS PASSED                 │              │
│   │                                           │              │
│   │   Execute: super._depositAndSend()        │              │
│   │                                           │              │
│   │   Update: userDeposits[user] += actual    │              │
│   └───────────────────────────────────────────┘              │
│                                                              │
└──────────────────────────────────────────────────────────────┘
```

### OVault Design Guarantee

OVault operations have **only two possible final outcomes**:
1. **Success** - Assets deposited, shares minted, cross-chain transfer completed
2. **Failed (but Refunded)** - Assets returned to user on source chain

This is enforced by LayerZero's architecture. No partial state, no stuck funds.

---

### Automatic Refund Flow

```
┌──────────────────────────────────────────────────────────────┐
│              Automatic Refund on Enforcement Revert          │
├──────────────────────────────────────────────────────────────┤
│                                                              │
│   lzCompose() called by LayerZero Endpoint                   │
│       │                                                      │
│       ▼                                                      │
│   ┌───────────────────────────────────────────┐              │
│   │  try handleCompose()                      │              │
│   │       │                                   │              │
│   │       ▼                                   │              │
│   │  _depositAndSend()                        │              │
│   │       │                                   │              │
│   │       ▼                                   │              │
│   │  YZ Enforcement Check                     │              │
│   │       │                                   │              │
│   │       ├─► REVERT (cap exceeded)           │              │
│   │       │         │                         │              │
│   │       │         ▼                         │              │
│   │       │   ┌─────────────────┐             │              │
│   │       │   │ Caught by try/  │             │              │
│   │       │   │ catch in        │             │              │
│   │       │   │ lzCompose()     │             │              │
│   │       │   └────────┬────────┘             │              │
│   │       │            │                      │              │
│   │       │            ▼                      │              │
│   │       │   ┌─────────────────┐             │              │
│   │       │   │ _refund() called │            │              │
│   │       │   │                 │             │              │
│   │       │   │ Assets sent back│             │              │
│   │       │   │ to user on      │             │              │
│   │       │   │ source chain    │             │              │
│   │       │   └─────────────────┘             │              │
│   │       │                                   │              │
│   │       └─► SUCCESS                         │              │
│   │               │                           │              │
│   │               ▼                           │              │
│   │       Vault deposit proceeds              │              │
│   │                                           │              │
│   └───────────────────────────────────────────┘              │
│                                                              │
└──────────────────────────────────────────────────────────────┘
```

### Failure Modes

| Failure Mode | What Happens | User Action |
|--------------|--------------|-------------|
| **Insufficient `msg.value`** | Revert propagates to Endpoint | Retry with correct `msg.value` |
| **Slippage exceeded** | Caught by try-catch → `_refund()` | Adjust slippage tolerance, retry |
| **YZ Enforcement (cap/pause)** | Caught by try-catch → `_refund()` | Wait for cap increase or unpause |
| **Vault error** | Caught by try-catch → `_refund()` | Check vault state |

**Note:** Slippage failures are retriable with adjusted tolerance. Enforcement failures (TVL cap, pause) require admin intervention before retry.

## Architecture Diagrams

### Class Hierarchy

```
┌─────────────────────────────────────────────────────────────────┐
│                        Inheritance Tree                         │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│   ┌─────────────────────┐                                       │
│   │   ReentrancyGuard   │                                       │
│   │   (OpenZeppelin)    │                                       │
│   └──────────┬──────────┘                                       │
│              │                                                  │
│              │ protects against reentrant calls                 │
│              │                                                  │
│              ▼                                                  │
│   ┌─────────────────────┐                                       │
│   │  VaultComposerSync  │                                       │
│   │   (LayerZero)       │                                       │
│   │                     │                                       │
│   │  - VAULT            │ immutable                             │
│   │  - ASSET_OFT        │ immutable                             │
│   │  - SHARE_OFT        │ immutable                             │
│   │  - ENDPOINT         │ immutable                             │
│   │                     │                                       │
│   │  + depositAndSend() │ public                                │
│   │  + redeemAndSend()  │ public                                │
│   │  + lzCompose()      │ external                              │
│   │                     │                                       │
│   │  # _depositAndSend()│ virtual ◄── OVERRIDE                  │
│   │  # _redeemAndSend() │ virtual ◄── OVERRIDE                  │
│   │  # _deposit()       │ virtual                               │
│   │  # _redeem()        │ virtual                               │
│   │  # _assertSlippage()│ virtual                               │
│   └──────────┬──────────┘                                       │
│              │                                                  │
│              │ extends                                          │
│              │                                                  │
│              ▼                                                  │
│   ┌──────────────────────────────────────────────────────┐      │
│   │              YZEnforcedComposer                      │      │
│   │                                                      │      │
│   │  State:                                              │      │
│   │  - admin                    address                  │      │
│   │  - tvlCap                   uint256                  │      │
│   │  - userDepositCap           mapping(address=>uint)   │      │
│   │  - userDeposits             mapping(address=>uint)   │      │
│   │  - paused                   bool                     │      │
│   │  - whitelistEnabled         bool                     │      │
│   │  - whitelist                mapping(address=>bool)   │      │
│   │                                                      │      │
│   │  Admin Functions:                                    │      │
│   │  + setTVLCap()                                       │      │
│   │  + setUserCap()                                      │      │
│   │  + pause() / unpause()                               │      │
│   │  + setWhitelist()                                    │      │
│   │  + setAdmin()                                        │      │
│   │  + emergencyWithdraw()                               │      │
│   │                                                      │      │
│   │  View Functions:                                     │      │
│   │  + canDeposit()                                      │      │
│   │  + getUserDepositInfo()                              │      │
│   │  + getTotalValueLocked()                             │      │
│   │                                                      │      │
│   │  Overrides:                                          │      │
│   │  # _depositAndSend()   ◄── adds enforcement          │      │
│   │  # _redeemAndSend()    ◄── adds tracking             │      │
│   │                                                      │      │
│   └──────────────────────────────────────────────────────┘      │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### State Diagram

```
┌────────────────────────────────────────────────────────────────┐
│                      Contract States                           │
├────────────────────────────────────────────────────────────────┤
│                                                                │
│   ┌─────────────────────────────────────────────────────────┐  │
│   │                                                         │  │
│   │   ┌─────────────┐        pause()        ┌───────────┐   │  │
│   │   │   ACTIVE    │ ───────────────────►  │  PAUSED   │   │  │
│   │   │             │                       │           │   │  │
│   │   │ - Deposits  │ ◄───────────────────  │ - Blocked │   │  │
│   │   │ - Redempts  │       unpause()       │ - Redempts│   │  │
│   │   │   allowed   │                       │   blocked │   │  │
│   │   └─────────────┘                       └───────────┘   │  │
│   │                                                         │  │
│   └─────────────────────────────────────────────────────────┘  │
│                                                                │
│   ┌─────────────────────────────────────────────────────────┐  │
│   │                   Whitelist Mode                        │  │
│   │                                                         │  │
│   │   ┌─────────────┐   setWhitelistEnabled(true)           │  │
│   │   │   OPEN      │ ─────────────────────► ┌───────────┐  │  │
│   │   │             │                        │ WHITELIST │  │  │
│   │   │ Anyone can  │ ◄────────────────────  │ Only      │  │  │
│   │   │ deposit     │  setWhitelistEnabled   │ whitelisted│ │  │
│   │   │             │      (false)           │ users     │  │  │
│   │   └─────────────┘                        └───────────┘  │  │
│   │                                                         │  │
│   └─────────────────────────────────────────────────────────┘  │
│                                                                │
│   ┌─────────────────────────────────────────────────────────┐  │
│   │                    Cap States                           │  │
│   │                                                         │  │
│   │   tvlCap = 0  ──► Unlimited TVL                         │  │
│   │   tvlCap > 0  ──► Limited to tvlCap                     │  │
│   │                                                         │  │
│   │   userCap[user] = 0  ──► Unlimited for user             │  │
│   │   userCap[user] > 0  ──► Limited to userCap             │  │
│   │                                                         │  │
│   └─────────────────────────────────────────────────────────┘  │
│                                                                │
└────────────────────────────────────────────────────────────────┘
```

---

## Flow Diagrams

### Cross-Chain Deposit Flow

```
┌──────────────────────────────────────────────────────────────────────────┐
│                     Cross-Chain Deposit Flow                             │
├──────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│  SPOKE CHAIN (eg, Ethereum)          HUB CHAIN (eg, Arbitrum)            │
│                                                                          │
│  ┌─────────────────┐                  ┌─────────────────────────────────┐│
│  │     User        │                  │                                 ││
│  │                 │                  │  ┌─────────────────────────┐    ││
│  │  1. approve()   │                  │  │   LayerZero Endpoint    │    ││
│  │     assetOFT    │                  │  │                         │    ││
│  │                 │                  │  │  4. lzReceive()         │    ││
│  │  2. send()      │                  │  │     - verify DVN quorum │    ││
│  │     composeMsg  │                  │  │     - mint OFT to       │    ││
│  │     = SendParam │                  │  │       composer          │    ││
│  │     + minMsgVal │                  │  │                         │    ││
│  └────────┬────────┘                  │  └───────────┬─────────────┘    ││
│           │                           │              │                  ││
│           │                           │              ▼                  ││
│           │                           │  ┌─────────────────────────┐    ││
│           │                           │  │   lzCompose()           │    ││
│           │                           │  │                         │    ││
│           │                           │  │  5. try handleCompose() │    ││
│           │                           │  │         │               │    ││
│           │                           │  │         ▼               │    ││
│           │                           │  │  ┌───────────────────┐  │    ││
│           │                           │  │  │ YZEnforcedComposer│  │    ││
│           │                           │  │  │                   │  │    ││
│           │                           │  │  │ 6. _depositAndSend│  │    ││
│           │                           │  │  │    │              │  │    ││
│           │                           │  │  │    ▼              │  │    ││
│           │                           │  │  │ ┌───────────────┐ │  │    ││
│           │                           │  │  │ │ ENFORCEMENT   │ │  │    ││
│           │                           │  │  │ │               │ │  │    ││
│           │                           │  │  │ │ ✓ Not paused  │ │  │    ││
│           │                           │  │  │ │ ✓ Whitelisted │ │  │    ││
│           │                           │  │  │ │ ✓ TVL OK      │ │  │    ││
│           │                           │  │  │ │ ✓ User cap OK │ │  │    ││
│           │                           │  │  │ │ ✓ Vault OK    │ │  │    ││
│           │                           │  │  │ └───────┬───────┘ │  │    ││
│           │                           │  │  │         │         │  │    ││
│           │                           │  │  │         ▼         │  │    ││
│           │                           │  │  │ 7. vault.deposit()│  │    ││
│           │                           │  │  │ 8. _assertSlippage│  │    ││
│           │                           │  │  │ 9. _send() shares │  │    ││
│           │                           │  │  │10. Update tracking│  │    ││
│           │                           │  │  └───────────────────┘  │    ││
│           │                           │  │         │               │    ││
│           │                           │  │         ▼               │    ││
│           │                           │  │  SUCCESS ◄──────────────┤    ││
│           │                           │  │                         │    ││
│           │                           │  └─────────────────────────┘    ││
│           │                           │                                 ││
│           │  If REVERT:               │  ┌─────────────────────────┐    ││
│           │                           │  │ catch → _refund()       │    ││
│           │  ◄────────────────────────├──│                         │    ││
│           │  Assets returned to user  │  │ 11. Send assets back    │    ││
│           │  on spoke chain           │  │     to source chain     │    ││
│           │                           │  └─────────────────────────┘    ││
│           │                           │                                 ││
│           ▼                           └─────────────────────────────────┘│
│                                                                          │
└──────────────────────────────────────────────────────────────────────────┘
```

### Local Deposit Flow

```
┌──────────────────────────────────────────────────────────────────┐
│                     Local Deposit Flow                           │
├──────────────────────────────────────────────────────────────────┤
│                                                                  │
│   User on Hub Chain                                              │
│       │                                                          │
│       │ 1. approve(assetOFT, amount)                             │
│       │                                                          │
│       ▼                                                          │
│   ┌─────────────────────────────────────────────────────────┐    │
│   │                                                         │    │
│   │   composer.depositAndSend(amount, sendParam, refund)    │    │
│   │                                                         │    │
│   │   ┌─────────────────────────────────────────────────┐   │    │
│   │   │ 2. transferFrom(user, composer, amount)         │   │    │
│   │   └─────────────────────────────────────────────────┘   │    │
│   │                        │                                │    │
│   │                        ▼                                │    │
│   │   ┌──────────────────────────────────────────────────┐  │    │
│   │   │ 3. _depositAndSend()                             │  │    │
│   │   │                                                  │  │    │
│   │   │    ├─► Check: paused?                            │  │    │
│   │   │    ├─► Check: whitelisted?                       │  │    │
│   │   │    ├─► Check: TVL cap?                           │  │    │
│   │   │    ├─► Check: user cap?                          │  │    │
│   │   │    ├─► Check: vault.maxDeposit?                  │  │    │
│   │   │    │                                             │  │    │
│   │   │    ├─► Record TVL before                         │  │    │
│   │   │    ├─► super._depositAndSend()                   │  │    │
│   │   │    │    ├─► _deposit() → vault.deposit()         │  │    │
│   │   │    │    ├─► _assertSlippage()                    │  │    │
│   │   │    │    └─► _send() → local/remote               │  │    │
│   │   │    │                                             │  │    │
│   │   │    └─► Update userDeposits                       │  │    │
│   │   │                                                  │  │    │
│   │   └──────────────────────────────────────────────────┘  │    │
│   │                                                         │    │
│   └─────────────────────────────────────────────────────────┘    │
│       │                                                          │
│       ▼                                                          │
│   User receives shares (local or cross-chain)                    │
│                                                                  │
└──────────────────────────────────────────────────────────────────┘
```

---

## Reference

### Admin Functions

| Function | Description | Access |
|----------|-------------|--------|
| `setTVLCap(uint256 cap)` | Set maximum TVL | Admin only |
| `setUserCap(address user, uint256 cap)` | Set user deposit limit | Admin only |
| `batchSetUserCaps(address[], uint256[])` | Batch set user caps | Admin only |
| `pause()` | Stop all operations | Admin only |
| `unpause()` | Resume operations | Admin only |
| `setWhitelistEnabled(bool)` | Enable/disable whitelist | Admin only |
| `setWhitelist(address, bool)` | Set whitelist status | Admin only |
| `batchSetWhitelist(address[], bool[])` | Batch whitelist | Admin only |
| `setAdmin(address)` | Transfer admin role | Admin only |
| `emergencyWithdraw(uint256, address)` | Withdraw stuck assets | Admin only |

### View Functions

| Function | Returns | Description |
|----------|---------|-------------|
| `admin()` | address | Current admin |
| `tvlCap()` | uint256 | TVL limit (0 = unlimited) |
| `userDepositCap(address)` | uint256 | User's deposit limit |
| `userDeposits(address)` | uint256 | User's tracked deposits |
| `paused()` | bool | Pause state |
| `whitelistEnabled()` | bool | Whitelist mode |
| `whitelist(address)` | bool | User whitelist status |
| `canDeposit(address, uint256)` | (bool, string) | Check if deposit allowed |
| `getUserDepositInfo(address)` | (uint256, uint256, uint256) | deposit, cap, remaining |
| `getTotalValueLocked()` | uint256 | Current vault TVL |

### Errors

| Error | Trigger |
|-------|---------|
| `YZ_Paused()` | Contract is paused |
| `YZ_NotAdmin()` | Caller not admin |
| `YZ_ZeroAddress()` | Zero address provided |
| `YZ_TVLCapExceeded(currentTVL, amount, cap)` | TVL cap exceeded |
| `YZ_UserCapExceeded(user, current, amount, cap)` | User cap exceeded |

---

## ⚠️ Trade-offs

### _redeemAndSend Replication

The `_redeemAndSend()` override **replicates parent logic** instead of calling `super._redeemAndSend()`. This is necessary to track user deposits BEFORE assets are sent cross-chain.

**Why this matters:**
```
Parent flow: _redeem() → _assertSlippage() → _send()
                    │
                    └─► After _send(), assets have LEFT the contract
                         Balance delta would be 0 or negative
```

**Trade-off:**
- ✅ Correctly tracks assets before they leave
- ❌ Does NOT automatically inherit future `VaultComposerSync` updates

**Mitigation:**
1. Pin `@layerzerolabs/ovault-evm` to a specific version
2. Monitor releases for `_redeemAndSend` changes
3. Update override when parent changes

### Version Pinning (CRITICAL)

```toml
# foundry.toml
[dependencies]
"@layerzerolabs/ovault-evm" = "1.0.0"  # Pin specific version
```

### Test-Only Functions

The `exposed_setUserDeposit()` function is for testing only. **Remove before mainnet deployment.**

---

## 💡 Design Decisions

### Deterministic Pricing (No Oracles Needed)

YZEnforcedComposer uses `vault.totalAssets()` for TVL cap enforcement. This is valid because:

**OVault uses deterministic pricing:**
```
sharePrice = totalAssets / totalSupply
```

Per LayerZero docs: "OVault eliminates the need for oracles" — the ERC-4626 vault's accounting is self-contained and deterministic.

**Why this matters:**
- No oracle manipulation risk
- No stale price feeds
- No external dependencies for cap enforcement
- TVL is always accurate from vault state

> **Note:** Future versions may add Chainlink price feeds for multi-asset vaults or cross-chain TVL aggregation. Marked for v0.2 consideration.

### emergencyWithdraw vs Permissionless Recovery

There's a tension between admin-only `emergencyWithdraw()` and LayerZero's permissionless recovery principle:

| Mechanism | Who Can Call | Purpose |
|-----------|--------------|---------|
| `emergencyWithdraw()` | Admin only | Withdraw stuck assets from composer |
| LayerZero `_refund()` | Automatic | Return assets on failed compose |
| Endpoint recovery | Anyone | Clear failed messages |

**Clarification:**
- `emergencyWithdraw()` is for assets **stuck in the composer** (eg, failed transfers, dust accumulation)
- It does **NOT** override LayerZero's recovery flows
- Failed cross-chain operations still go through `_refund()` → assets return to source chain
- `emergencyWithdraw()` should only be used for edge cases, not to intercept user funds

**Best Practice:** Document all `emergencyWithdraw()` calls with on-chain evidence of stuck assets.

---

## 🔓 Permissionless Recovery (LayerZero Native)

YZEnforcedComposer does **NOT** interfere with LayerZero's built-in permissionless recovery mechanisms.

### What Remains Permissionless

| Function | Who Can Call | Purpose |
|----------|--------------|---------|
| `lzCompose()` retry | Anyone | Retry failed compose operations |
| `_refund()` | Automatic via try-catch | Returns assets on failure |
| Endpoint recovery | Anyone | Message recovery from endpoint |

### How It Works

```
┌──────────────────────────────────────────────────────────────┐
│           LayerZero Permissionless Recovery                  │
├──────────────────────────────────────────────────────────────┤
│                                                              │
│   Failed Transaction                                         │
│       │                                                      │
│       ▼                                                      │
│   ┌───────────────────────────────────────────┐              │
│   │  Payload stays in Endpoint                │              │
│   │                                           │              │
│   │  Anyone can:                              │              │
│   │  • Retry lzCompose() with correct msg.value│             │
│   │  • Trigger refund via _refund()           │              │
│   │  • Clear failed messages                  │              │
│   └───────────────────────────────────────────┘              │
│                                                              │
│   YZEnforcedComposer does NOT:                               │
│   • Block retry attempts                                     │
│   • Require admin approval for refunds                       │
│   • Add custom recovery logic                                │
│                                                              │
└──────────────────────────────────────────────────────────────┘
```

### Admin Controls vs Permissionless Recovery

| Admin Only | Permissionless (Anyone) |
|------------|------------------------|
| `pause()` / `unpause()` | Retry failed `lzCompose()` |
| `setTVLCap()` | Trigger refund |
| `setUserCap()` | Endpoint message recovery |
| `setWhitelist()` | |
| `emergencyWithdraw()` | |

**Key Insight:** Admin controls affect **new transactions only**. Failed transactions can always be recovered permissionlessly.

### Paused State Edge Case

When the contract is **paused**, retry attempts will still revert:

```
┌──────────────────────────────────────────────────────────────┐
│               Paused State + Retry Interaction               │
├──────────────────────────────────────────────────────────────┤
│                                                              │
│   User retries lzCompose() while paused                      │
│       │                                                      │
│       ▼                                                      │
│   ┌───────────────────────────────────────────┐              │
│   │  whenNotPaused modifier                   │              │
│   │       │                                   │              │
│   │       ▼                                   │              │
│   │  paused == true                           │              │
│   │       │                                   │              │
│   │       ▼                                   │              │
│   │  REVERT YZ_Paused                         │              │
│   │       │                                   │              │
│   │       ▼                                   │              │
│   │  Caught by try-catch                      │              │
│   │       │                                   │              │
│   │       ▼                                   │              │
│   │  _refund() triggered                      │              │
│   │       │                                   │              │
│   │       ▼                                   │              │
│   │  Assets returned to user                  │              │
│   └───────────────────────────────────────────┘              │
│                                                              │
│   Result: Pause forces all retries into refunds              │
│                                                              │
└──────────────────────────────────────────────────────────────┘
```

**Implication:** Pausing doesn't block recovery — it forces recovery via refund. Users get their assets back, but cannot complete deposits until unpaused.

---

## Quick Start

```solidity
import {YZEnforcedComposer} from "./sdk/YZEnforcedComposer.sol";

// Deploy
YZEnforcedComposer composer = new YZEnforcedComposer(
    address(vault),      // ERC4626 vault
    address(assetOFT),   // Asset OFT
    address(shareOFT),   // Share OFT Adapter
    admin                // Admin address
);

// Configure
composer.setTVLCap(100_000_000 * 1e6);  // 100M cap
composer.setUserCap(user, 100_000 * 1e6); // 100K per user
composer.setWhitelistEnabled(false);     // Open access

// Emergency
composer.pause();    // Stop all operations
composer.unpause();  // Resume
```

---

## License

MIT