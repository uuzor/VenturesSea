# Contract Rewrite Implementation Plan
## VenturesSea Privacy-First Architecture

---

## Phase 1: Archive Existing Contracts

### Current State
The codebase contains both old (non-FHE) and new (Confidential) contracts. We need to archive the old ones and maintain only the privacy-first versions.

### Action Items
1. Move to `contracts/archived/`:
   - `BuilderAgreement.sol` (non-FHE)
   - `EncryptedSwap.sol` (non-FHE)
   - `FundingPool.sol` (non-FHE)
   - `IdeaDAO.sol` (non-FHE)
   - `IdeaFactory.sol` (non-FHE)
   - `IdeaRegistry.sol` (non-FHE)
   - `IdeaToken.sol` (non-FHE)
   - `ProtocolMarket.sol` (non-FHE)
   - `ProtocolTreasury.sol` (non-FHE)
   - `RevenueReport.sol` (non-FHE)
   - `ThresholdDecryptor.sol` (non-FHE)
   - All stubs in `stubs/`

2. Keep in `contracts/ideafi/`:
   - All `Confidential*` contracts (FHE-enabled)
   - `SimpleOwnable.sol` (utility)
   - `IIdeaFi.sol` (interfaces)
   - `Milestone.sol` (base implementation)
   - Mock contracts in `mocks/`

---

## Phase 2: Contract Architecture

### Core Contract Hierarchy

```
ConfidentialIdeaRegistry (proxy admin, idea creation)
├── ConfidentialIdeaFactory (clone deployment)
│   ├── ConfidentialIdeaToken (ERC20 + FHE balances)
│   ├── ConfidentialFundingPool (deposits + FHE tracking)
│   ├── ConfidentialIdeaDAO (governance + FHE voting)
│   ├── ConfidentialBuilderAgreement (terms + FHE)
│   ├── ConfidentialMilestone (progress + FHE)
│   └── ConfidentialRevenueReport (revenue + FHE)
```

### Privacy Features by Contract

| Contract | FHE Types | Privacy Guarantees |
|----------|-----------|-------------------|
| ConfidentialIdeaToken | euint128 | Encrypted balances, permissioned disclosure |
| ConfidentialFundingPool | euint128, euint64 | Private deposits, hidden totals |
| ConfidentialIdeaDAO | euint128, ebool | Encrypted votes, threshold reveal |
| ConfidentialBuilderAgreement | euint128 | Private allocation terms |
| ConfidentialMilestone | euint128, ebool | Encrypted progress, threshold release |
| ConfidentialRevenueReport | euint128, euint64 | Private revenue, ack threshold |

---

## Phase 3: Implementation Details

### 3.1 ConfidentialIdeaRegistry

**Purpose**: Entry point for idea creation, manages factory references.

**FHE Integration**: None (registry only, no private data).

**Key Functions**:
```solidity
function createIdea(bytes32 metadataHash, IdeaType ideaType) external;
function createConfidentialIdea(bytes32 metadataHash, IdeaType ideaType) external;
function setFactory(address _factory) external;
function setConfidentialFactory(address _factory) external;
```

### 3.2 ConfidentialIdeaToken

**Purpose**: FHE-enabled ERC20 token for idea participation.

**FHE Integration**:
- Parallel encrypted balances (`mapping(address => euint128)`)
- Encrypted total supply
- Permissioned balance disclosure

**Key Functions**:
```solidity
function mint(address to, uint256 amount) external;  // Pool-only
function mintEncrypted(address to, InEuint128 encryptedAmount) external;
function burn(address from, uint256 amount) external;
function mintBuilderAllocation(address to, uint256 amount) external;  // DAO-only
function getEncryptedBalance(address account) external view returns (euint128);
function getEncryptedTotalSupply() external view returns (euint128);
function requestDiscloseAmount(euint128 amount) external;
```

### 3.3 ConfidentialFundingPool

**Purpose**: Privacy-preserving deposits with FHE tracking.

**FHE Integration**:
- Encrypted user deposits
- Encrypted total deposited
- Encrypted builder allocation percentage

**Key Functions**:
```solidity
function deposit(uint256 amount) external;
function depositConfidential(InEuint128 encryptedAmount) external;
function withdraw(uint256 amount) external;
function getEncryptedDeposit(address user) external view returns (euint128);
function getEncryptedTotalDeposited() external view returns (eint128);
function getEncryptedBuilderAllocationPct() external view returns (euint64);
function isLocked() external view returns (bool);
```

### 3.4 ConfidentialIdeaDAO

**Purpose**: FHE-encrypted governance voting.

**FHE Integration**:
- Encrypted vote counts (approval/rejection)
- Encrypted quorum tracking
- Threshold-based vote decryption

**Key Functions**:
```solidity
function createProposal(
    ProposalType proposalType,
    bytes32 descriptionHash,
    address target,
    bytes calldata data,
    uint256 votingPeriod
) external;

function castVote(
    uint256 proposalId,
    bool support,
    InEuint128 encryptedAmount
) external;

function castVoteWithReason(
    uint256 proposalId,
    bool support,
    InEuint128 encryptedAmount,
    string calldata reason
) external;

function getEncryptedVotes(uint256 proposalId) external view returns (euint128, euint128);
function requestVoteDecryption(uint256 proposalId) external;
function decryptionRequested(uint256 proposalId) external view returns (bool);
function executeProposal(uint256 proposalId) external;
```

### 3.5 ConfidentialBuilderAgreement

**Purpose**: Private terms between idea creator and builder.

**FHE Integration**:
- Encrypted allocation percentage
- Encrypted vesting schedules
- Permissioned term disclosure

**Key Functions**:
```solidity
function setTerms(
    address builder,
    uint256 allocationPct,
    uint256 vestingMonths,
    InEuint128 encryptedBonus
) external;

function getEncryptedAllocation() external view returns (euint128);
function getEncryptedVestingMonths() external view returns (euint64);
function acknowledgeTerms() external;
function requestTermsDisclosure() external;
```

### 3.6 ConfidentialMilestone

**Purpose**: FHE-encrypted progress tracking.

**FHE Integration**:
- Encrypted allocated amounts
- Encrypted released amounts
- Threshold-based release conditions

**Key Functions**:
```solidity
function createMilestone(
    string calldata description,
    uint256 deadline,
    InEuint128 encryptedAmount
) external;

function approveMilestone(uint256 milestoneId) external;
function rejectMilestone(uint256 milestoneId) external;
function requestRelease(uint256 milestoneId) external;

function getEncryptedAllocated() external view returns (euint128);
function getEncryptedReleased() external view returns (euint128);
function getMilestoneCount() external view returns (uint256);
```

### 3.7 ConfidentialRevenueReport

**Purpose**: Private revenue sharing with reveal thresholds.

**FHE Integration**:
- Encrypted revenue amounts
- Encrypted acknowledgment counts
- Threshold-based distribution release

**Key Functions**:
```solidity
function submitConfidentialRevenue(InEuint128 encryptedAmount) external returns (uint256);
function acknowledgeRevenue(uint256 reportId) external;
function requestDistribution(uint256 reportId) external;

function getEncryptedRevenue(uint256 reportId) external view returns (euint128);
function getEncryptedAckCount(uint256 reportId) external view returns (euint64);
function getReportCount() external view returns (uint256);
```

---

## Phase 4: Testing Strategy

### 4.1 Test Categories

1. **Unit Tests**: Each contract in isolation
2. **Integration Tests**: Multi-contract workflows
3. **Privacy Tests**: Verify encrypted handles, no plaintext leaks
4. **Fork Tests**: Mainnet interaction (arb-fork)

### 4.2 Privacy Test Patterns

```javascript
describe("Privacy Verification", function () {
  it("should NOT expose deposit amounts in events", async function () {
    const tx = await pool.deposit(amount);
    const receipt = await tx.wait();
    
    // Verify no amount in event logs
    receipt.logs.forEach(log => {
      // Event should not contain plaintext amounts
      expect(log.data).to.not.include(amount.toString());
    });
  });
  
  it("should return encrypted handles for balances", async function () {
    const handle = await token.getEncryptedBalance(user);
    expect(handle).to.be.a("string");
    expect(handle).to.match(/^0x[a-f0-9]+$/); // Valid handle format
  });
  
  it("should require permission to decrypt", async function () {
    // Attempting to decrypt without permission should fail
    await expect(
      cofheClient.decryptForView(handle, FheTypes.Uint128).execute()
    ).to.be.rejected;
  });
});
```

### 4.3 Network Configuration

```javascript
// hardhat.config.js
module.exports = {
  networks: {
    hardhat: {
      // Local FHE simulation
    },
    arb_fork: {
      url: "https://arb-mainnet.g.alchemy.com/v2/gBLyY4xTb-MP1ZkxdnJdTqkYKQjxi_XO",
      chainId: 42161,
      forking: {
        url: "https://arb-mainnet.g.alchemy.com/v2/gBLyY4xTb-MP1ZkxdnJdTqkYKQjxi_XO"
      }
    }
  },
  plugins: ['@fhenixprotocol/hardhat-cofhe']
};
```

---

## Phase 5: Deployment Checklist

### Pre-Deployment

- [ ] All 21 tests passing
- [ ] Privacy tests verify no plaintext leaks
- [ ] Fork tests pass on arb-fork
- [ ] Gas optimization complete
- [ ] Security audit ready

### Deployment Order

1. Deploy MockMUSD (if needed)
2. Deploy ProtocolTreasury
3. Deploy ConfidentialIdeaRegistry
4. Deploy all implementation contracts (with proxy pattern):
   - ConfidentialIdeaToken
   - ConfidentialFundingPool
   - ConfidentialIdeaDAO
   - ConfidentialBuilderAgreement
   - ConfidentialMilestone
   - ConfidentialRevenueReport
5. Deploy ConfidentialIdeaFactory with implementations
6. Set factory on registry
7. Verify full lifecycle works

### Post-Deployment

- [ ] Verify contracts on explorer
- [ ] Run integration tests on target network
- [ ] Update documentation with deployed addresses
- [ ] Monitor for隐私 leaks in transactions

---

## Phase 6: Frontend Integration

### CoFHE SDK Setup

```bash
npm install @cofhe/sdk@^0.5.2 viem
```

### Privacy-First UI Patterns

```javascript
import { CofheClient, Encryptable, FheTypes } from '@cofhe/sdk';

// 1. Initialize client
const cofheClient = new CofheClient(wallet);

// 2. Privacy deposit flow
async function depositPrivately(amount) {
  // Encrypt amount client-side
  const [encrypted] = await cofheClient.encryptInputs([
    Encryptable.uint128(amount)
  ]).execute();
  
  // Send encrypted deposit
  await fundingPool.depositConfidential(encrypted);
  
  // Get encrypted balance
  const handle = await fundingPool.getEncryptedDeposit(userAddress);
  
  // Decrypt for local display only
  const balance = await cofheClient.decryptForView(handle, FheTypes.Uint128).execute();
  updateUI(balance);
}

// 3. Privacy governance flow
async function castVotePrivately(proposalId, support, amount) {
  const [encrypted] = await cofheClient.encryptInputs([
    Encryptable.uint128(amount)
  ]).execute();
  
  await dao.castVote(proposalId, support, encrypted);
}

// 4. Permissioned balance disclosure
async function shareBalanceWith(recipient) {
  const handle = await token.getEncryptedBalance(myAddress);
  await token.requestDiscloseAmount(handle);
  // recipient can now decrypt
}
```

---

## Appendix: File Structure

```
contracts/
├── archived/                    # Old non-FHE contracts
│   ├── BuilderAgreement.sol
│   ├── EncryptedSwap.sol
│   ├── FundingPool.sol
│   ├── IdeaDAO.sol
│   ├── IdeaFactory.sol
│   ├── IdeaRegistry.sol
│   ├── IdeaToken.sol
│   ├── ProtocolMarket.sol
│   ├── ProtocolTreasury.sol
│   ├── RevenueReport.sol
│   ├── ThresholdDecryptor.sol
│   └── stubs/
│       └── *.sol
│
├── ideafi/                      # Current FHE-enabled contracts
│   ├── ConfidentialBuilderAgreement.sol
│   ├── ConfidentialFundingPool.sol
│   ├── ConfidentialIdeaDAO.sol
│   ├── ConfidentialIdeaFactory.sol
│   ├── ConfidentialIdeaRegistry.sol
│   ├── ConfidentialIdeaToken.sol
│   ├── ConfidentialMilestone.sol
│   ├── ConfidentialRevenueReport.sol
│   ├── ConfidentialSwap.sol
│   ├── IIdeaFi.sol              # Interfaces
│   ├── Milestone.sol            # Base implementation
│   ├── SimpleOwnable.sol        # Utility
│   └── mocks/
│       ├── EncryptedSwap.sol
│       ├── MockMUSD.sol
│       ├── ProtocolTreasury.sol
│       └── ThresholdDecryptor.sol
│
fhe-privacy/                     # CoFHE library
└── (from @fhenixprotocol/cofhe-contracts)

test/
├── privacy-simulation.cjs        # Integration tests
└── unit/                        # Unit tests by contract

docs/
└── privacy-design/
    ├── PRIVACY_ARCHITECTURE.md   # Design document
    └── IMPLEMENTATION_PLAN.md    # This file
```

---

*Last Updated: 2026-06-01*  
*Version: 1.0*