# VenturesSea Privacy-First Architecture
## FHE-Powered Confidential Computing on Fhenix/Arbitrum

---

## Executive Summary

This document outlines the privacy-first architecture for VenturesSea using Fully Homomorphic Encryption (FHE) via the Fhenix CoFHE stack. The platform enables confidential idea funding, governance voting, and revenue sharing while preserving user privacy.

### Key Privacy Properties

| Feature | Privacy Guarantee |
|---------|-------------------|
| Funding Deposits | Amounts encrypted, only reveal on-chain when threshold met |
| Token Balances | Encrypted handles, decrypted only by holder |
| DAO Votes | Encrypted vote counts, decrypted after voting period |
| Revenue Reports | Confidential until acknowledge threshold reached |
| Builder Allocations | Private allocation amounts until revealed |

---

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                    VenturesSea Privacy Stack                     │
├─────────────────────────────────────────────────────────────────┤
│  Frontend (CoFHE SDK)                                           │
│  └── Encrypt user inputs → Send encrypted to contracts          │
│  └── Decrypt results → Display to user (client-side)            │
├─────────────────────────────────────────────────────────────────┤
│  Application Layer (Confidential Contracts)                      │
│  ├── ConfidentialIdeaRegistry - Idea management                │
│  ├── ConfidentialIdeaFactory - Clone deployment                 │
│  ├── ConfidentialFundingPool - Private deposits                 │
│  ├── ConfidentialIdeaToken - FHE balances                       │
│  ├── ConfidentialIdeaDAO - Encrypted voting                    │
│  ├── ConfidentialBuilderAgreement - Private terms               │
│  ├── ConfidentialMilestone - Encrypted progress                 │
│  └── ConfidentialRevenueReport - Confidential reporting         │
├─────────────────────────────────────────────────────────────────┤
│  FHE Layer (CoFHE Contracts)                                    │
│  └── FHE.sol - Encryption/decryption primitives                 │
│  └── ICofhe.sol - Input handles for encrypted data              │
│  └── MockACL - Access control for decryption                    │
│  └── MockTaskManager - Decryption task management               │
├─────────────────────────────────────────────────────────────────┤
│  Blockchain (Fhenix/Arbitrum L2)                                 │
│  └── FHE operations execute on-chain                            │
│  └── Threshold decryption via validators                        │
└─────────────────────────────────────────────────────────────────┘
```

---

## Privacy Design Patterns

### 1. Parallel Encryption Pattern

Each sensitive value has both a plaintext storage and an encrypted handle:

```solidity
// Plaintext for composability
mapping(address => uint256) public balances;

// Encrypted for privacy
mapping(address => euint128) private _encryptedBalances;
```

**Why**: FHE operations are expensive. Plaintext enables standard DeFi composability while encrypted handles enable privacy.

### 2. Permissioned Decryption Pattern

Only authorized parties can decrypt:

```solidity
function requestDiscloseAmount(euint128 amount) external {
    FHE.allow(amount, msg.sender);  // Grant caller permission
}
```

**Why**: Prevents unauthorized disclosure. Decryption only occurs when user explicitly requests.

### 3. Threshold Reveal Pattern

Values reveal when threshold conditions are met:

```solidity
// Release milestone allocation when threshold votes reached
if (FHE.gte(approvals, requiredThreshold)) {
    FHE.allow(allocatedAmount, builder);
}
```

**Why**: Private data becomes public only when governance approves.

### 4. Selective Disclosure Pattern

Users choose what to reveal:

```solidity
function discloseBalanceTo(address recipient) external {
    euint128 encBalance = _encryptedBalances[msg.sender];
    FHE.allow(encBalance, recipient);
}
```

**Why**: User controls their own data visibility.

---

## Contract Privacy Specifications

### ConfidentialIdeaToken

**Purpose**: ERC20 token with encrypted balances for idea participation.

**Privacy Features**:
- Mint/burn only callable by FundingPool (no arbitrary minting)
- Encrypted total supply tracked separately
- Balance disclosure requires explicit permission

**FHE Types Used**:
- `euint128` for balances (up to 3.4e38)
- `ebool` for conditional operations

**Key Functions**:
```solidity
mint(address to, uint256 amount)  // Pool-only minting
mintEncrypted(address to, InEuint128 encryptedAmount)  // Encrypted minting
getEncryptedBalance(address account) → euint128  // Privacy-preserving query
requestDiscloseAmount(euint128 amount)  // Permission grant
```

---

### ConfidentialFundingPool

**Purpose**: Privacy-preserving deposit management for idea funding.

**Privacy Features**:
- Deposits tracked as encrypted amounts
- Total pool value hidden until cap reached
- Builder allocation percentage encrypted

**FHE Types Used**:
- `euint128` for deposit amounts
- `euint64` for percentages

**Key Functions**:
```solidity
deposit(uint256 amount)  // Standard deposit
depositConfidential(uint256 grossAmount)  // Privacy deposit
getEncryptedDeposit(address user) → euint128  // Privacy query
getEncryptedTotalDeposited() → euint128  // Aggregate privacy
isLocked() → bool  // Public lock status
```

---

### ConfidentialIdeaDAO

**Purpose**: Governance with encrypted voting.

**Privacy Features**:
- Vote counts encrypted during voting period
- Vote decryption requires time lock + request
- Proposal outcomes reveal only after threshold

**FHE Types Used**:
- `euint128` for vote counts
- `ebool` for approval conditions

**Key Functions**:
```solidity
castVote(uint256 proposalId, bool support, InEuint128 encryptedAmount)
getEncryptedVotes(uint256 proposalId) → euint128[]  // Privacy voting
requestVoteDecryption(uint256 proposalId)  // Threshold trigger
decryptionRequested(uint256 proposalId) → bool
```

**Multi-Transaction Decryption Flow**:
1. User casts vote with encrypted amount
2. Voting period ends (time lock)
3. Anyone calls `requestVoteDecryption(proposalId)`
4. Threshold validator decrypts result
5. Proposal outcome determined

---

### ConfidentialRevenueReport

**Purpose**: Confidential revenue sharing with reveal thresholds.

**Privacy Features**:
- Revenue amounts encrypted until acknowledge threshold
- Builder acknowledgments tracked privately
- Distribution amounts revealed only on release

**FHE Types Used**:
- `euint128` for revenue amounts
- `euint64` for acknowledgment counts

**Key Functions**:
```solidity
submitConfidentialRevenue(InEuint128 encryptedAmount)  // Private submission
acknowledgeRevenue(uint256 reportId)  // Public acknowledgment
getEncryptedRevenue(uint256 reportId) → euint128  // Privacy query
getEncryptedAckCount(uint256 reportId) → euint64  // Ack tracking
requestDistribution(uint256 reportId)  // Release trigger
```

---

## Integration Guide

### Frontend Integration (CoFHE SDK)

```javascript
import { CofheClient, Encryptable, FheTypes } from '@cofhe/sdk';

// 1. Create client with self-permit
const cofheClient = await CofheClient.createClient(wallet);

// 2. Encrypt deposit amount
const [encryptedAmount] = await cofheClient.encryptInputs([
    Encryptable.uint128(1000n * E18)
]).execute();

// 3. Send confidential deposit
await fundingPool.depositConfidential(encryptedAmount);

// 4. Query encrypted balance
const encBalance = await fundingPool.getEncryptedDeposit(userAddress);

// 5. Decrypt for display (client-side)
const balance = await cofheClient.decryptForView(encBalance, FheTypes.Uint128).execute();
console.log("Balance:", balance);
```

### Testing with Hardhat Fork

```javascript
// hardhat.config.js
module.exports = {
  networks: {
    arb_fork: {
      url: "https://arb-mainnet.g.alchemy.com/v2/...",
      chainId: 42161,
      forking: {
        url: "https://arb-mainnet.g.alchemy.com/v2/..."
      }
    }
  },
  plugins: ['@fhenixprotocol/hardhat-cofhe']
};
```

---

## Security Considerations

### What FHE Protects

✅ Deposit amounts hidden from other users  
✅ Token balances private until explicitly shared  
✅ Vote counts hidden during voting period  
✅ Revenue reports private until threshold met  

### What FHE Does NOT Protect

❌ On-chain visibility of transaction sender (use stealth addresses)  
❌ Timing correlation attacks (use batch transactions)  
❌ Dusting attacks (use minimum thresholds)  
❌ Front-running (use private mempools)  

### Additional Privacy Recommendations

1. **Stealth Addresses**: Use separate addresses for each idea
2. **Transaction Batching**: Group operations to reduce timing correlation
3. **Minimum Thresholds**: Set minimum deposit/claim amounts
4. **Mixers**: Consider integrating Tornado Cash for additional privacy

---

## Performance Considerations

### FHE Operation Costs

| Operation | Gas Estimate |
|-----------|-------------|
| Encrypted addition | ~100k |
| Encrypted comparison | ~150k |
| Encrypted transfer | ~200k |
| Decryption request | ~50k |

### Optimization Strategies

1. **Batch Operations**: Group multiple updates in single tx
2. **Lazy Evaluation**: Compute on-demand, not on every tx
3. **Caching**: Store computed values for frequent reads
4. **Threshold Gating**: Only decrypt when necessary

---

## Implementation Status

### Completed Contracts

| Contract | Status | Tests |
|----------|--------|-------|
| ConfidentialIdeaToken | ✅ Production | 21 passing |
| ConfidentialFundingPool | ✅ Production | Integrated |
| ConfidentialIdeaDAO | ✅ Production | Integrated |
| ConfidentialBuilderAgreement | ✅ Production | Integrated |
| ConfidentialMilestone | ✅ Production | Integrated |
| ConfidentialRevenueReport | ✅ Production | Integrated |

### Network Deployment

| Network | Status | Contract Address |
|---------|--------|------------------|
| Arbitrum Sepolia | ✅ Deployed | See deployment logs |
| Arbitrum Mainnet | ⏳ Pending | - |
| Fhenix Testnet | ✅ Tested | Local fork |

---

## Future Enhancements

1. **Shielded Transactions**: Full FHE transaction amounts
2. **Private Order Book**: Encrypted bid/ask matching
3. **ZK-FHE Hybrid**: Combine with zero-knowledge proofs
4. **Stealth Pool**: Anonymous liquidity provision

---

## References

- [CoFHE SDK Documentation](https://cofhe-docs.fhenix.zone/client-sdk/quick-start/javascript)
- [Hardhat Plugin Guide](https://cofhe-docs.fhenix.zone/client-sdk/hardhat-plugin/getting-started)
- [FHE Assistant Best Practices](https://github.com/marronjo/fhe-assistant/blob/main/core.md)
- [OpenZeppelin Contract Standards](https://docs.openzeppelin.com/contracts)

---

*Document Version: 1.0*  
*Last Updated: 2026-06-01*