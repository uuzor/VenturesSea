# VenturesSea - 4 Contract Architecture
## Minimal FHE-Private Builder-Investor Coordination Protocol

---

## Architecture Decision

**Constraint**: Maximum 4 contracts in `contracts/ideafi/`

**Approach**: Consolidate related functionality into unified contracts rather than one contract per feature.

---

## The 4 Contracts

```
┌─────────────────────────────────────────────────────────────────┐
│                    4-CONTRACT ARCHITECTURE                       │
└─────────────────────────────────────────────────────────────────┘

┌──────────────────────┐
│   1. IdeaVault       │  ← Idea + Funding + Token (State Machine)
│                      │    - Create idea
│                      │    - Funding window (open/close)
│                      │    - Deposits + token minting
│                      │    - Gating control
│                      │    - Funds lock/unlock
└──────────────────────┘
           │
           ▼
┌──────────────────────┐
│   2. BuilderHub      │  ← Builder + Agreement + Milestones
│                      │    - Builder registration
│                      │    - Quest proposals
│                      │    - BuilderAgreement (terms)
│                      │    - Milestone submission
│                      │    - Progress tracking
└──────────────────────┘
           │
           ▼
┌──────────────────────┐
│   3. GovernanceVault │  ← DAO + Voting + Decisions
│                      │    - Builder selection vote
│                      │    - Milestone approval vote
│                      │    - Final MVP vote
│                      │    - Refund/fork decisions
└──────────────────────┘
           │
           ▼
┌──────────────────────┐
│   4. TreasuryVault   │  ← Payouts + Revenue Distribution
│                      │    - USDY payout to builder
│                      │    - Token allocation (10-30%)
│                      │    - Product transfer (InvestorDAO)
│                      │    - Revenue claims
│                      │    - Refund processing
└──────────────────────┘
```

---

## Protocol Flow (Mapped to 4 Contracts)

```
[Request Posted] → IdeaVault.createIdea()
        ↓
[Funding Window Opens] → IdeaVault.openFundingWindow()
  └─ IdeaToken minted per USDY deposited → IdeaVault.fund()
  └─ Optional gating → IdeaVault.setGating()
        ↓
[Builder Marketplace Opens] → BuilderHub.register() + submitQuest()
  └─ Builders submit quest proposals (off-chain IPFS)
  └─ Hackathon / Top 3 winners recorded
        ↓
[DAO Selects Builder] → GovernanceVault.selectBuilder()
  └─ BuilderAgreement signed → BuilderHub.signAgreement()
        ↓
[FundingPool Locks] → IdeaVault.lockFunding()
  └─ builderAlloc reserved
  └─ investorPool reserved
        ↓
[Milestone Criteria Set] → GovernanceVault.setMilestoneCriteria()
        ↓
[Builder Submits Milestones] → BuilderHub.submitMilestone()
        ↓
[DAO Validates] → GovernanceVault.approveMilestone()
        ↓
[Final MVP → DAO Full Vote] → GovernanceVault.finalVote()
        ↓
    ┌───────────────────┬───────────────────┬───────────────────┐
    ↓                   ↓                   ↓                   ↓
[APPROVED]          [REJECTED pre]      [REJECTED post]
    │                   │                   │
    ├─ TreasuryVault    ├─ TreasuryVault    └─ GovernanceVault
    │   .payout()           .refund()          .fork()
    ├─ 10-30% tokens
    └─ Product → InvestorDAO (TreasuryVault.transferProduct())
        ↓
[Product Operates]
  └─ Revenue → TreasuryVault.distributeRevenue()
  └─ Token holders claim → TreasuryVault.claim()
```

---

## Contract 1: IdeaVault

**File**: `contracts/ideafi/IdeaVault.sol`

**Responsibilities**:
- Idea creation and lifecycle state machine
- Funding window (time-boxed)
- USDY deposits with token minting
- Optional gating for IdeaToken holders
- Fund locking after builder selection

**FHE Privacy**:
- Encrypted deposits (`euint128`)
- Encrypted total raised

**State Machine**:
```
RequestOpen → FundingOpen → FundingClosed → BuilderSelected → Locked → Operational
```

```solidity
contract IdeaVault {
    // State
    enum IdeaState { RequestOpen, FundingOpen, FundingClosed, BuilderSelected, Locked, Operational }
    
    struct Idea {
        uint256 id;
        address creator;
        string ipfsHash;
        IdeaState state;
        uint256 fundingTarget;
        uint256 fundingCap;
        uint256 fundingStart;
        uint256 fundingEnd;
        uint256 tokenMintRatio;  // tokens per 1 USDY
        bool gatingEnabled;
        address selectedBuilder;
    }
    
    // Functions
    function createIdea(string calldata ipfsHash, uint256 target, uint256 cap, uint256 duration) external;
    function openFundingWindow(uint256 ideaId) external;
    function fund(uint256 ideaId, uint256 usdyAmount) external returns (uint256 tokensMinted);
    function closeFunding(uint256 ideaId) external;
    function selectBuilder(uint256 ideaId, address builder) external onlyGovernance;
    function lockFunding(uint256 ideaId) external onlyGovernance;
    
    // FHE
    function getEncryptedDeposit(uint256 ideaId, address user) external view returns (euint128);
    function getEncryptedTotalRaised(uint256 ideaId) external view returns (euint128);
}
```

---

## Contract 2: BuilderHub

**File**: `contracts/ideafi/BuilderHub.sol`

**Responsibilities**:
- Builder registration and profiles
- Quest proposals (IPFS references)
- BuilderAgreement (on-chain terms)
- Milestone submission and tracking
- Final deliverable

**FHE Privacy**:
- Encrypted builder reputation

```solidity
contract BuilderHub {
    // State
    struct Builder {
        address builder;
        string ipfsProfile;
        bool isVerified;
        bool isActive;
    }
    
    struct Quest {
        uint256 ideaId;
        address builder;
        string ipfsProposal;
        uint256 requestedBudget;
        uint256 suggestedTokenAlloc;
        bool selected;
        uint256 submissionTime;
    }
    
    struct Agreement {
        uint256 ideaId;
        address builder;
        uint256 budget;           // USDY
        uint256 tokenAllocPct;    // 10-30%
        uint256 vestingMonths;
        bytes32 ipfsHash;
        bool signed;
    }
    
    struct Milestone {
        uint256 ideaId;
        uint256 index;
        string ipfsDescription;
        uint256 releaseAmount;
        bool submitted;
        bool approved;
    }
    
    // Functions
    function registerBuilder(string calldata ipfsProfile) external;
    function submitQuest(uint256 ideaId, string calldata ipfsProposal, uint256 budget, uint256 tokenAlloc) external;
    function signAgreement(uint256 ideaId, bytes32 ipfsHash) external;
    function submitMilestone(uint256 ideaId, string calldata ipfsDescription, uint256 releaseAmount) external;
    function finalizeDeliverable(uint256 ideaId, string calldata ipfsHash) external;
    
    // FHE
    function getEncryptedReputation(address builder) external view returns (euint128);
}
```

---

## Contract 3: GovernanceVault

**File**: `contracts/ideafi/GovernanceVault.sol`

**Responsibilities**:
- Builder selection voting
- Milestone approval voting
- Final MVP vote
- Refund/vote-for-fork decisions
- Setting milestone criteria

**FHE Privacy**:
- Encrypted vote counts (`euint128`)
- Encrypted quorum

```solidity
contract GovernanceVault {
    // Vote types
    enum VoteType { BuilderSelection, MilestoneApproval, FinalMVP, Refund, Fork }
    enum Outcome { Pending, Approved, Rejected }
    
    // State
    struct Proposal {
        uint256 id;
        uint256 ideaId;
        VoteType voteType;
        uint256 votingDeadline;
        Outcome outcome;
        bool executed;
    }
    
    // Functions
    function createBuilderSelectionVote(uint256 ideaId, address builder, uint256 duration) external;
    function castVote(uint256 proposalId, bool support, InEuint128 encryptedWeight) external;
    function finalizeVote(uint256 proposalId) external;
    function setMilestoneCriteria(uint256 ideaId, string calldata criteria) external;
    function voteOnRefund(uint256 ideaId, bool approve) external;
    function voteOnFork(uint256 ideaId, address newBuilder) external;
    function executeFork(uint256 ideaId) external;
    
    // FHE
    function getEncryptedVotesFor(uint256 proposalId) external view returns (euint128);
    function getEncryptedVotesAgainst(uint256 proposalId) external view returns (euint128);
}
```

---

## Contract 4: TreasuryVault

**File**: `contracts/ideafi/TreasuryVault.sol`

**Responsibilities**:
- USDY payout to builder (after approval)
- Token allocation (10-30% to builder)
- Product transfer to InvestorDAO
- Revenue distribution to token holders
- Refund processing

**FHE Privacy**:
- Encrypted payout amounts
- Encrypted revenue shares
- Encrypted claims

```solidity
contract TreasuryVault {
    // State
    enum PayoutState { Pending, Approved, Processing, Completed, Refunded }
    
    struct PayoutRequest {
        uint256 ideaId;
        address builder;
        uint256 usdyAmount;
        uint256 tokenAllocPct;
        PayoutState state;
        address investorDAO;
    }
    
    struct RevenueAllocation {
        uint256 ideaId;
        uint256 builderShare;   // %
        uint256 daoShare;      // %
        uint256 distributed;
        bool active;
    }
    
    // Functions
    function initiatePayout(uint256 ideaId, address builder, uint256 usdyAmount, uint256 tokenAllocPct) external;
    function approvePayout(uint256 ideaId) external onlyGovernance;
    function processPayout(uint256 ideaId) external returns (bool);
    function transferProductToDAO(uint256 ideaId, address investorDAO) external;
    
    function setRevenueAllocation(uint256 ideaId, uint256 builderShare, uint256 daoShare) external;
    function receiveRevenue(uint256 ideaId, uint256 amount) external;
    function distributeRevenue(uint256 ideaId, address[] calldata recipients, uint256[] calldata amounts) external;
    function claimRevenue(uint256 ideaId) external returns (uint256);
    
    function processRefund(uint256 ideaId, uint256 amount) external;
    
    // FHE
    function getEncryptedPendingPayouts(uint256 ideaId) external view returns (euint128);
    function getEncryptedClaim(uint256 ideaId, address claimant) external view returns (euint128);
}
```

---

## File Structure (After Consolidation)

```
contracts/ideafi/
├── IdeaVault.sol              ← NEW: Consolidated idea + funding + token
├── BuilderHub.sol             ← NEW: Consolidated builder + milestones
├── GovernanceVault.sol         ← NEW: Consolidated DAO + voting
├── TreasuryVault.sol          ← NEW: Consolidated payouts + revenue
├── ConfidentialIdeaFactory.sol ← Keep? (clone factory for proxies)
├── IIdeaFi.sol                ← Keep (interfaces)
└── SimpleOwnable.sol          ← Keep (utility)
```

**Removes**: 11 existing contracts → 4 new contracts

---

## Contract Interactions

```
User ─────┐
          │
          ▼
┌─────────────────────┐
│     IdeaVault       │◄──── User creates idea, funds, gets tokens
│                     │
│  createIdea()       │
│  fund()             │
│  getEncrypted*()     │
└──────────┬──────────┘
           │ builder selected
           ▼
┌─────────────────────┐
│    BuilderHub      │◄──── Builder registers, signs agreement, submits milestones
│                     │
│  registerBuilder()  │
│  submitQuest()      │
│  signAgreement()    │
│  submitMilestone()  │
└──────────┬──────────┘
           │ milestones approved
           ▼
┌─────────────────────┐
│  GovernanceVault   │◄──── All voting happens here
│                     │
│  createVote()       │
│  castVote()         │
│  finalizeVote()     │
│  voteOnFork()       │
└──────────┬──────────┘
           │ approved/rejected
           ▼
┌─────────────────────┐
│   TreasuryVault    │◄──── Payouts, revenue, refunds
│                     │
│  initiatePayout()  │
│  processPayout()   │
│  distributeRevenue()│
│  claimRevenue()    │
└─────────────────────┘
```

---

## State Transitions

### IdeaVault State Machine
```
RequestOpen → FundingOpen → FundingClosed → BuilderSelected → Locked → Operational
     │              │              │              │            │
     │              │              │              │            │
     ▼              ▼              ▼              ▼            ▼
 User creates    Deposits      Window closes   Builder       Product live
 idea            open          results in      selected      (revenue flows)
```

### Payout Flow
```
Pending → Approved → Processing → Completed
   │                        │
   │                        └── tokens minted to builder (10-30%)
   │
   └─ If rejected pre-lock: → Refunded (full refund)
```

---

## Privacy Features Summary

| Contract | FHE Type | Privacy Guarantee |
|----------|----------|-------------------|
| IdeaVault | euint128 | Deposit amounts hidden until reveal |
| BuilderHub | euint128 | Builder reputation private until threshold |
| GovernanceVault | euint128 | Vote counts hidden during voting |
| TreasuryVault | euint128 | Payout amounts private until release |

---

## Implementation Order

1. **IdeaVault** - Core concept + funding
2. **BuilderHub** - Builder management + milestones  
3. **GovernanceVault** - All voting decisions
4. **TreasuryVault** - Payouts + revenue (depends on all above)

---

## Testing Strategy

Single test file: `test/full-protocol.cjs`

```javascript
describe("Full Protocol", function () {
  it("should complete full flow: create → fund → select builder → milestones → payout", async function () {
    // 1. Create idea
    const ideaId = await ideaVault.createIdea(ipfsHash, target, cap, duration);
    
    // 2. Open funding
    await ideaVault.openFundingWindow(ideaId);
    await ideaVault.fund(ideaId, usdyAmount);
    
    // 3. Close funding
    await ideaVault.closeFunding(ideaId);
    
    // 4. Builder submits quest
    await builderHub.submitQuest(ideaId, proposal, budget, alloc);
    
    // 5. DAO selects builder
    const proposalId = await governance.createBuilderSelectionVote(ideaId, builder);
    await governance.castVote(proposalId, true, encryptedWeight);
    await governance.finalizeVote(proposalId);
    await ideaVault.selectBuilder(ideaId, builder);
    
    // 6. Lock funding
    await ideaVault.lockFunding(ideaId);
    
    // 7. Milestones
    await builderHub.submitMilestone(ideaId, desc, amount);
    await governance.approveMilestone(proposalId);
    
    // 8. Final vote
    await governance.finalVote(ideaId);
    
    // 9. Payout
    await treasury.initiatePayout(ideaId, builder, usdy, tokenAlloc);
    await treasury.approvePayout(ideaId);
    await treasury.processPayout(ideaId);
  });
});
```

---

*Document Version: 1.0*  
*Architecture Date: 2026-06-01*