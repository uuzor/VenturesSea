# VenturesSea Protocol Flow Analysis
## Builder-Investor Coordination Protocol vs Current Implementation

---

## Executive Summary

The proposed VenturesSea protocol is a **capital + builder coordination system** - not a simple dApp but a structured funding pipeline from idea → build → product → revenue. 

**Current Implementation Gap**: The existing Confidential* contracts provide FHE privacy primitives but don't implement the full coordination workflow described in the protocol flow.

---

## Protocol Flow Comparison

### Proposed Protocol Flow (User's Vision)

```
┌─────────────────────────────────────────────────────────────────────┐
│                         PROTOCOL LIFECYCLE                           │
└─────────────────────────────────────────────────────────────────────┘

[Request Posted] OR [Idea Created]
        ↓
[Funding Window Opens]
  └─ IdeaToken minted per USDY deposited
  └─ Optional gating for IdeaToken holders
        ↓
[Builder Marketplace Opens]
  └─ Builders request off-chain first (hackathon style)
  └─ Top 3 win → can team up or DAO selects 1
        ↓
[DAO Selects Builder + Approves Terms]
  └─ BuilderAgreement signed on-chain + IPFS
        ↓
[FundingPool Locks]
  └─ builderAlloc reserved
  └─ investorPool reserved
        ↓
[Milestone Criteria Set by DAO]
        ↓
[Builder Submits Milestones → DAO Validates]
        ↓
[Final MVP → DAO Full Vote]
        ↓
    ┌───────────────────┬───────────────────┐
    ↓                   ↓                   ↓
[APPROVED]         [REJECTED pre]      [REJECTED post]
    │                   │                   │
    ├─ USDY payout      ├─ Full refund      ├─ Idea Fork
    ├─ 10-30% token     └─ (no lock)        └─ Dispute
    └─ Product →        └─ (no product)
    InvestorDAO
        ↓
[Product Operates]
  └─ Revenue → RevenueDistributor
  └─ Token holders claim proportional revenue
```

---

### Current Contract Coverage

| Protocol Stage | Current Contract | Status | Gap |
|---------------|------------------|--------|-----|
| Idea Created | ConfidentialIdeaRegistry | ✅ | Missing: FundingWindow state machine |
| Funding Opens | ConfidentialIdeaToken | ✅ | Missing: IdeaToken minting mechanics |
| Builder Selection | ConfidentialIdeaDAO | ⚠️ | Missing: Marketplace flow |
| BuilderAgreement | ConfidentialBuilderAgreement | ✅ | Good coverage |
| FundingPool Lock | ConfidentialFundingPool | ⚠️ | Missing: state-based locking |
| Milestone Criteria | ConfidentialMilestone | ⚠️ | Missing: DAO criteria setting |
| Builder Submission | ConfidentialMilestone | ✅ | Good coverage |
| DAO Validation | ConfidentialIdeaDAO | ⚠️ | Missing: milestone validation workflow |
| Final MVP Vote | ConfidentialIdeaDAO | ✅ | Vote exists |
| Payout | (not implemented) | ❌ | Missing: USDY payout + token allocation |
| Product Control | (not implemented) | ❌ | Missing: InvestorDAO transfer |
| Revenue Distribution | ConfidentialRevenueReport | ⚠️ | Needs upgrade for InvestorDAO |
| Refund/Fork | (not implemented) | ❌ | Missing: refund + fork mechanisms |

**Legend**: ✅ Complete | ⚠️ Partial | ❌ Missing

---

## Required Contract Additions

### 1. FundingWindowManager (NEW)

**Purpose**: Orchestrates the time-boxed funding phase.

**States**:
```solidity
enum FundingPhase {
    Inactive,      // Idea posted, no funding yet
    RequestOpen,   // Requests being submitted
    FundingOpen,   // Funding window active
    FundingClosed, // Window closed, results finalized
    BuilderSelect, // Builder selection phase
    Locked         // Funding locked, builder working
}
```

**Key Functions**:
```solidity
function openFundingWindow(uint256 ideaId, uint256 duration) external onlyDAO;
function depositIntoFunding(uint256 ideaId, uint256 usdyAmount) external returns (uint256 tokensMinted);
function closeFundingWindow(uint256 ideaId) external;
function getFundingPhase(uint256 ideaId) external view returns (FundingPhase);
function getFundingProgress(uint256 ideaId) external view returns (uint256, uint256); // raised, target
```

**Privacy Features**:
- Deposits tracked as encrypted amounts
- Total raised hidden until window closes (optional)
- Gating check for IdeaToken holders (optional)

### 2. BuilderMarketplace (NEW)

**Purpose**: Builder discovery, quest submission, and selection.

**Key Structures**:
```solidity
struct BuilderProfile {
    address builder;
    string offchainProfile;    // IPFS hash to profile
    uint256 reputationScore;
    uint256 completedProjects;
    bool isVerified;
}

struct QuestSubmission {
    uint256 ideaId;
    address builder;
    string questProposal;      // IPFS hash
    string[] milestones;
    uint256 requestedBudget;
    uint256 suggestedTokenAlloc;
    uint256 submissionTime;
    bool selected;
}

struct HackathonResult {
    uint256 ideaId;
    address[3] winners;
    uint256 prizeAmounts;
    bool teamsFormed;
    address winningTeam;
}
```

**Key Functions**:
```solidity
function registerBuilder(string calldata ipfsProfile) external;
function submitQuestProposal(uint256 ideaId, string calldata proposalHash) external;
function recordHackathonResult(uint256 ideaId, address[3] calldata winners) external onlyDAO;
function selectBuilderFromMarket(uint256 ideaId, address builder) external onlyDAO;
function getBuilderProfile(address builder) external view returns (BuilderProfile memory);
function getQuestSubmissions(uint256 ideaId) external view returns (QuestSubmission[] memory);
```

### 3. InvestorDAO (NEW - or upgrade ConfidentialIdeaDAO)

**Purpose**: Investor governance over funded products.

**Key Additions**:
```solidity
function acceptProductTransfer(uint256 ideaId) external onlyTokenHolders;
function proposeProductUpgrade(uint256 ideaId, address newImplementation) external;
function setRevenueSplit(uint256 ideaId, uint256 builderPct, uint256 daoPct) external;
function emergencyPauseProduct(uint256 ideaId) external;
```

### 4. Enhanced FundingPool

**Upgrades Needed**:
```solidity
// State machine
enum PoolState { Open, Locked, MilestoneActive, Completed, Refunded }

function lockPool(uint256 ideaId) external onlyRegistry;
function unlockAndRefund(uint256 ideaId) external onlyDAO;
function processMilestonePayout(uint256 ideaId, uint256 milestoneIndex) external onlyDAO;

// Reserved allocations
function reserveBuilderAllocation(uint256 ideaId, uint256 amount) external onlyRegistry;
function reserveInvestorAllocation(uint256 ideaId, uint256 amount) external onlyRegistry;
function releaseBuilderAllocation(uint256 ideaId, address builder) external onlyDAO;
```

### 5. DisputeResolver (NEW)

**Purpose**: Handle rejection/fork scenarios.

```solidity
enum DisputeOutcome { Pending, Refund, Fork, Resolved }

function initiateDispute(uint256 ideaId, string calldata reason) external;
function castDisputeVote(uint256 ideaId, DisputeOutcome outcome) external;
function executeDisputeResolution(uint256 ideaId) external onlyAfterVoting;
function forkProduct(uint256 ideaId, address newBuilder) external onlyDAO;
```

---

## Privacy Architecture for New Components

### FHE-Encrypted States

```solidity
// FundingPool - encrypted deposit tracking
mapping(uint256 => euint128) private _encryptedDeposits;
mapping(uint256 => euint128) private _encryptedTotalRaised;

// BuilderMarketplace - encrypted reputation
mapping(address => euint128) private _encryptedReputation;

// Milestone - encrypted approval thresholds
mapping(uint256 => euint128) private _encryptedMilestoneVotes;
mapping(uint256 => ebool) private _milestoneApproved;
```

### CoFHE Integration Points

1. **Private Deposits**: `depositConfidential(InEuint128 encryptedAmount)`
2. **Encrypted Voting**: `castVote(proposalId, support, encryptedAmount)`
3. **Private Reputation**: Builders with hidden reputation until threshold
4. **Confidential Revenue**: `submitConfidentialRevenue(InEuint128 encryptedAmount)`

---

## Implementation Priority

### Phase 1: Core Flow (MVP)
1. ✅ ConfidentialIdeaRegistry (existing)
2. ✅ ConfidentialIdeaToken (existing)
3. **NEW**: FundingWindowManager
4. **NEW**: BuilderMarketplace (simplified)
5. **NEW**: Enhanced FundingPool with locking
6. ✅ ConfidentialIdeaDAO (upgrade)
7. ✅ ConfidentialBuilderAgreement (existing)
8. ✅ ConfidentialMilestone (existing)
9. **NEW**: Basic PayoutManager

### Phase 2: Revenue (Post-Launch)
10. **NEW**: InvestorDAO
11. Enhanced ConfidentialRevenueReport for InvestorDAO
12. **NEW**: RevenueDistributor

### Phase 3: Edge Cases
13. **NEW**: DisputeResolver
14. **NEW**: ForkManager

---

## Contract Interaction Diagram

```
┌─────────────────────────────────────────────────────────────────────────┐
│                        VenturesSea Protocol                               │
└─────────────────────────────────────────────────────────────────────────┘

User/Builder
    │
    ▼
┌─────────────────────┐
│ ConfidentialIdea    │ ←─── Registry: Idea creation
│    Registry         │
└─────────────────────┘
    │
    ▼
┌─────────────────────┐
│ FundingWindow       │ ←─── Time-boxed funding phase
│    Manager          │     FHE: Encrypted deposit tracking
└─────────────────────┘
    │
    ├──▶ IdeaToken (minting based on deposits)
    │
    ▼
┌─────────────────────┐
│ Builder             │ ←─── Quest proposals + hackathon winners
│  Marketplace        │     FHE: Encrypted builder reputation
└─────────────────────┘
    │
    ▼
┌─────────────────────┐
│ Confidential        │ ←─── DAO vote for builder selection
│   IdeaDAO           │     FHE: Encrypted voting
└─────────────────────┘
    │
    ▼
┌─────────────────────┐
│ Confidential        │ ←─── On-chain terms + IPFS
│ BuilderAgreement    │
└─────────────────────┘
    │
    ▼
┌─────────────────────┐
│ Confidential        │ ←─── Lock after selection
│  FundingPool        │     FHE: Private reserves
│                     │     States: Open → Locked → Completed
└─────────────────────┘
    │
    ├──▶ Builder: Milestone submissions
    │
    ▼
┌─────────────────────┐
│ Confidential        │ ←─── DAO validation per milestone
│   Milestone         │     FHE: Encrypted vote counts
└─────────────────────┘
    │
    ▼
┌─────────────────────┐
│ Confidential        │ ←─── Final MVP approval vote
│   IdeaDAO           │
└─────────────────────┘
    │
    ├──▶ APPROVED ──▶ PayoutManager ──▶ InvestorDAO (product control)
    │                     │
    │                     ├──▶ USDY payout to builder
    │                     └──▶ 10-30% IdeaToken to builder
    │
    ├──▶ REJECTED (pre-lock) ──▶ Full refund
    │
    └──▶ REJECTED (post-lock) ──▶ DisputeResolver ──▶ Fork or Resolve
                                               │
                                               ▼
                                    ┌─────────────────────┐
                                    │ InvestorDAO         │ ←─── Product governance
                                    │ (RevenueDistributor)│     FHE: Private claims
                                    └─────────────────────┘
```

---

## Key FHE Privacy Features by Stage

### Stage: Funding Window
- ✅ Deposit amounts encrypted during window
- ✅ Total raised hidden until close (optional)
- ✅ IdeaToken allocation private until reveal

### Stage: Builder Selection
- ✅ Builder reputation scores encrypted
- ✅ Hackathon winners revealed only after voting
- ✅ Selection vote counts encrypted

### Stage: Milestone Validation
- ✅ Milestone approval counts encrypted
- ✅ Builder progress hidden from competitors
- ✅ Release amounts permissioned

### Stage: Revenue Distribution
- ✅ Revenue amounts encrypted until distribution
- ✅ Claim amounts private
- ✅ Proportional shares revealed only on claim

---

## Technical Considerations

### State Machine Security

Each idea must follow strict state transitions:
```
REQUEST_POSTED → FUNDING_OPEN → FUNDING_CLOSED → BUILDER_SELECTED 
    → TERMS_SIGNED → POOL_LOCKED → MILESTONE_ACTIVE → MVP_SUBMITTED 
    → VOTING → APPROVED/REJECTED
```

**Critical Invariants**:
1. Cannot lock pool without signed BuilderAgreement
2. Cannot release funds without DAO milestone approval
3. Cannot fork after full product handover

### Gas Optimization

- Batch FHE operations where possible
- Use `FHE.allowTransient` for one-time disclosures
- Cache decrypted values when appropriate

### Frontend Integration (CoFHE SDK)

```javascript
// Private deposit
const [encrypted] = await cofheClient.encryptInputs([
    Encryptable.uint128(depositAmount)
]).execute();
await fundingWindow.deposit(ideaId, encrypted);

// Private vote on builder
const [encryptedVotes] = await cofheClient.encryptInputs([
    Encryptable.uint128(myTokenBalance)
]).execute();
await dao.castVote(proposalId, true, encryptedVotes);
```

---

## Recommendations

### Immediate (This Sprint)
1. Add `FundingWindowManager` contract with FHE-encrypted deposits
2. Enhance `FundingPool` with state-based locking
3. Add builder quest proposal mechanism to `ConfidentialIdeaDAO`

### Short-term (Next Sprint)
4. Implement `PayoutManager` for USDY + token allocation
5. Create `InvestorDAO` as product governance contract
6. Add revenue distribution flow

### Medium-term
7. `DisputeResolver` for fork scenarios
8. `ForkManager` for product continuity
9. Full CoFHE SDK integration tests

---

*Document Version: 1.0*  
*Analysis Date: 2026-06-01*  
*Status: Requires Implementation*