# Deployment and Configuration Manual

This document details the multi-chain deployment and post-deployment configuration manual for the `YZEnforcedComposer` contract stack.

---

## 1. Prerequisites and Setup

Ensure you have Foundry installed on your machine and dependencies loaded:

```bash
# Clone the repository and initialize submodules
git clone <repo_url> --recursive
cd YZEnforcedComposer

# Update and synchronize submodules
git submodule update --init --recursive
```

---

## 2. Environment Variables

Create a `.env` file in the root directory based on the following template:

```env
# Network RPC Endpoints
MAINNET_RPC_URL=https://eth-mainnet.g.alchemy.com/v2/your-api-key
ARBITRUM_RPC_URL=https://arb-mainnet.g.alchemy.com/v2/your-api-key
OPTIMISM_RPC_URL=https://opt-mainnet.g.alchemy.com/v2/your-api-key
POLYGON_RPC_URL=https://polygon-mainnet.g.alchemy.com/v2/your-api-key
SEPOLIA_RPC_URL=https://eth-sepolia.g.alchemy.com/v2/your-api-key

# Deployer Accounts
PRIVATE_KEY=0x...          # Deployment account private key
ADMIN_ADDRESS=0x...        # Protocol Admin multisig address

# Deployment Parameters (Target Chain)
VAULT_ADDRESS=0x...        # Underlying ERC4626 Vault
ASSET_OFT_ADDRESS=0x...    # LayerZero Asset OFT
SHARE_OFT_ADDRESS=0x...    # LayerZero Share OFT Adapter

# Configuration Parameter Updates
COMPOSER_ADDRESS=0x...     # Deployed YZEnforcedComposer address
ADMIN_PRIVATE_KEY=0x...    # Protocol Admin private key (for automated configuration)
TVL_CAP=1000000000000000000000 # TVL Cap in asset decimals (e.g. 1000 assets)
WHITELIST_ENABLED=false
```

---

## 3. Local Compilation

To build and compile the Solidity contracts:

```bash
forge build
```

---

## 4. Multi-Chain Deployment Scripts

We utilize Foundry scripts located in `script/` for reproducible deployment actions.

### A. Deploy YZEnforcedComposer
To deploy to a target chain (e.g. Arbitrum Sepolia):

```bash
forge script script/DeployYZEnforcedComposer.s.sol \
  --rpc-url $ARBITRUM_RPC_URL \
  --broadcast \
  --verify \
  --etherscan-api-key <arbitrum_etherscan_key>
```

Upon successful deployment, update the `deployments/arbitrum.json` registry file with the new contract address and transaction metadata.

### B. Configure Caps and Whitelisting
To automate post-deployment configuration (e.g., setting the TVL cap or whitelisting settings):

```bash
forge script script/ConfigureYZEnforcedComposer.s.sol \
  --rpc-url $ARBITRUM_RPC_URL \
  --broadcast
```

### C. Execute Emergency Pause
In an emergency situation, to immediately pause all deposits and redemptions:

```bash
forge script script/EmergencyPause.s.sol \
  --rpc-url $ARBITRUM_RPC_URL \
  --broadcast
```

---

## 5. Security & Verification Best Practices

1. **Verify Source Code**: Always execute `--verify` during deployment. If that fails, verify manually using `forge verify-contract`.
2. **Cold Admin Setup**: The `ADMIN_ADDRESS` passed to the constructor MUST be a cold Gnosis Safe multisig.
3. **Registry Audit**: Update the appropriate JSON file in `deployments/` and submit a Pull Request to master after every live deployment to maintain git cleanliness.
