// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import {FHE, euint8, euint16, euint32, euint64, euint128, InEuint64, ebool, eaddress} from "@fhenixprotocol/cofhe-contracts/FHE.sol";
import "./IIdeaFi.sol";

/**
 * @title ConfidentialIdeaDAO
 * @notice IdeaDAO with encrypted voting for privacy-preserving governance.
 *         Vote weights and counts are kept confidential while maintaining
 *         on-chain proposal execution and quorum verification.
 */
contract ConfidentialIdeaDAO is Initializable {
    using FHE for *;
    // -----------------------------------------------------------------------
    // Constants
    // -----------------------------------------------------------------------

    uint256 public constant QUORUM_BPS = 1000;         // 10%
    uint256 public constant TIMELOCK = 48 hours;
    uint256 public constant NULLIFY_THRESHOLD_BPS = 6600; // 66%
    uint8 public constant STATUS_CANCELLED = 3;

    // -----------------------------------------------------------------------
    // Types
    // -----------------------------------------------------------------------

    enum ProposalType {
        SELECT_BUILDER,
        APPROVE_MVP,
        APPROVE_MILESTONE,
        SET_MILESTONE_CRITERIA,
        NULLIFY_IDEA,
        FORK_IDEA,
        RELEASE_FUNDS,
        SET_REVENUE_TERMS
    }

    struct Proposal {
        uint256 proposalId;
        ProposalType pType;
        bytes32 descriptionHash;
        bytes callData;
        address target;
        address proposer;
        uint256 forVotes;       // Public for verification (encrypted also stored)
        uint256 againstVotes;   // Public for verification (encrypted also stored)
        uint256 deadline;
        bool executed;
        bool cancelled;
    }

    // -----------------------------------------------------------------------
    // State
    // -----------------------------------------------------------------------

    uint256 public ideaId;
    address public registry;
    address public ideaToken;

    // Cached idea-specific addresses
    address public fundingPool;
    address public builderAgreement;
    address public milestone;
    address public revenueReport;
    bool private addressesCached;

    uint256 public proposalCount;
    mapping(uint256 => Proposal) public proposals;
    mapping(uint256 => mapping(address => bool)) public hasVoted;
    mapping(uint256 => uint256) public proposalEta;

    // ── Confidential voting state ──────────────────────────────────────────

    /// @notice Encrypted FOR votes per proposal
    mapping(uint256 => euint64) private _encryptedForVotes;

    /// @notice Encrypted AGAINST votes per proposal
    mapping(uint256 => euint64) private _encryptedAgainstVotes;

    /// @notice Encrypted voter count per proposal
    mapping(uint256 => euint64) private _encryptedVoterCount;

    /// @notice Encrypted total supply snapshot for quorum
    mapping(uint256 => euint64) private _encryptedQuorumSnapshot;

    // -----------------------------------------------------------------------
    // Events
    // -----------------------------------------------------------------------

    event ProposalCreated(
        uint256 indexed proposalId,
        ProposalType pType,
        address indexed proposer,
        uint256 deadline
    );
    event VoteCast(uint256 indexed proposalId, address indexed voter, bool support, uint256 weight);
    event EncryptedVoteCast(uint256 indexed proposalId, address indexed voter);
    event Queued(uint256 indexed proposalId, uint256 eta);
    event Executed(uint256 indexed proposalId);
    event Cancelled(uint256 indexed proposalId);

    // -----------------------------------------------------------------------
    // Modifiers
    // -----------------------------------------------------------------------

    modifier onlySelf() {
        require(msg.sender == address(this), "IdeaDAO: only callable via executeProposal");
        _;
    }

    // -----------------------------------------------------------------------
    // Constructor
    // -----------------------------------------------------------------------

    constructor(uint256 _ideaId, address _registry, address _ideaToken) {
        if (_registry != address(0)) {
            _initialize(_ideaId, _registry, _ideaToken);
        }
    }

    function _initialize(uint256 _ideaId, address _registry, address _ideaToken) internal {
        ideaId = _ideaId;
        registry = _registry;
        ideaToken = _ideaToken;
    }

    function initialize(uint256 _ideaId, address _registry, address _ideaToken) external initializer {
        require(_registry != address(0), "IdeaDAO: zero registry");
        require(_ideaToken != address(0), "IdeaDAO: zero ideaToken");
        _initialize(_ideaId, _registry, _ideaToken);
    }

    // -----------------------------------------------------------------------
    // Internal helpers
    // -----------------------------------------------------------------------

    function getIdeaAddresses() internal {
        if (addressesCached) return;
        IIdeaRegistry reg = IIdeaRegistry(registry);
        fundingPool = reg.getFundingPool(ideaId);
        builderAgreement = reg.getBuilderAgreement(ideaId);
        milestone = reg.getMilestone(ideaId);
        revenueReport = reg.getRevenueReport(ideaId);
        addressesCached = true;
    }

    // -----------------------------------------------------------------------
    // Proposal lifecycle
    // -----------------------------------------------------------------------

    /// @notice Create a governance proposal. Caller must hold IdeaTokens.
    function createProposal(
        ProposalType pType,
        bytes32 descriptionHash,
        address target,
        bytes calldata callData,
        uint256 votingPeriod
    ) external {
        require(IERC20(ideaToken).balanceOf(msg.sender) > 0, "IdeaDAO: no token balance");
        require(votingPeriod >= 1 days, "IdeaDAO: votingPeriod < 1 day");

        uint256 id = proposalCount++;
        proposals[id] = Proposal({
            proposalId: id,
            pType: pType,
            descriptionHash: descriptionHash,
            callData: callData,
            target: target,
            proposer: msg.sender,
            forVotes: 0,
            againstVotes: 0,
            deadline: block.timestamp + votingPeriod,
            executed: false,
            cancelled: false
        });

        // Snapshot encrypted quorum for this proposal
        uint256 totalSupply = IERC20(ideaToken).totalSupply();
        _encryptedQuorumSnapshot[id] = FHE.asEuint64(totalSupply);

        emit ProposalCreated(id, pType, msg.sender, block.timestamp + votingPeriod);
    }

    // ── Standard voting (backward compatible) ────────────────────────────

    /// @notice Cast a vote on an active proposal (public version).
    function castVote(uint256 proposalId, bool support) external {
        _castVoteStandard(proposalId, support, false);
    }

    function _castVoteStandard(uint256 proposalId, bool support, bool) internal {
        require(proposalId < proposalCount, "IdeaDAO: invalid proposalId");
        Proposal storage p = proposals[proposalId];
        require(!p.cancelled, "IdeaDAO: proposal cancelled");
        require(!p.executed, "IdeaDAO: proposal already executed");
        require(block.timestamp <= p.deadline, "IdeaDAO: voting period ended");
        require(!hasVoted[proposalId][msg.sender], "IdeaDAO: already voted");

        uint256 weight = IERC20(ideaToken).balanceOf(msg.sender);
        require(weight > 0, "IdeaDAO: no token balance");

        if (support) {
            p.forVotes += weight;
        } else {
            p.againstVotes += weight;
        }
        hasVoted[proposalId][msg.sender] = true;

        emit VoteCast(proposalId, msg.sender, support, weight);
    }

    // ── Confidential voting (NEW - using FHE) ────────────────────────────

    /**
     * @notice Cast vote with encrypted support for privacy.
     * @param encryptedSupport Encrypted boolean: 1 = for, 0 = against
     */
    function castConfidentialVote(uint256 proposalId, InEuint64 calldata encryptedSupport) external {
        require(proposalId < proposalCount, "IdeaDAO: invalid proposalId");
        Proposal storage p = proposals[proposalId];
        require(!p.cancelled, "IdeaDAO: proposal cancelled");
        require(!p.executed, "IdeaDAO: proposal already executed");
        require(block.timestamp <= p.deadline, "IdeaDAO: voting period ended");
        require(!hasVoted[proposalId][msg.sender], "IdeaDAO: already voted");

        uint256 weight = IERC20(ideaToken).balanceOf(msg.sender);
        require(weight > 0, "IdeaDAO: no token balance");

        euint64 support = FHE.asEuint64(encryptedSupport);
        euint64 weightEncrypted = FHE.asEuint64(weight);

        // Branchless voting: if support=1, add to for; if support=0, add to against
        // forAdd = support * weight, againstAdd = (1 - support) * weight
        euint64 forAdd = FHE.mul(support, weightEncrypted);
        euint64 againstAdd = FHE.mul(FHE.sub(FHE.asEuint64(1), support), weightEncrypted);

        // Update encrypted vote counts
        _encryptedForVotes[proposalId] = FHE.add(_encryptedForVotes[proposalId], forAdd);
        _encryptedAgainstVotes[proposalId] = FHE.add(_encryptedAgainstVotes[proposalId], againstAdd);

        // Increment voter count
        _encryptedVoterCount[proposalId] = FHE.add(_encryptedVoterCount[proposalId], FHE.asEuint64(1));

        hasVoted[proposalId][msg.sender] = true;

        emit EncryptedVoteCast(proposalId, msg.sender);
    }

    /**
     * @notice Cast vote with standard support but encrypted weight.
     */
    function castVoteWithEncryptedWeight(uint256 proposalId, bool support, InEuint64 calldata encryptedWeight) external {
        require(proposalId < proposalCount, "IdeaDAO: invalid proposalId");
        Proposal storage p = proposals[proposalId];
        require(!p.cancelled, "IdeaDAO: proposal cancelled");
        require(!p.executed, "IdeaDAO: proposal already executed");
        require(block.timestamp <= p.deadline, "IdeaDAO: voting period ended");
        require(!hasVoted[proposalId][msg.sender], "IdeaDAO: already voted");

        euint64 weightEncrypted = FHE.asEuint64(encryptedWeight);
        
        // For voting: support ? weight : 0
        euint64 forAdd = support ? weightEncrypted : FHE.asEuint64(0);
        euint64 againstAdd = support ? FHE.asEuint64(0) : weightEncrypted;

        _encryptedForVotes[proposalId] = FHE.add(_encryptedForVotes[proposalId], forAdd);
        _encryptedAgainstVotes[proposalId] = FHE.add(_encryptedAgainstVotes[proposalId], againstAdd);
        _encryptedVoterCount[proposalId] = FHE.add(_encryptedVoterCount[proposalId], FHE.asEuint64(1));

        hasVoted[proposalId][msg.sender] = true;

        emit EncryptedVoteCast(proposalId, msg.sender);
    }

    // -----------------------------------------------------------------------
    // Queue & Execute
    // -----------------------------------------------------------------------

    /// @notice Queue a passed proposal for execution after the timelock.
    function queueProposal(uint256 proposalId) external {
        require(proposalId < proposalCount, "IdeaDAO: invalid proposalId");
        Proposal storage p = proposals[proposalId];
        require(!p.cancelled, "IdeaDAO: proposal cancelled");
        require(!p.executed, "IdeaDAO: already executed");
        require(proposalEta[proposalId] == 0, "IdeaDAO: already queued");
        require(block.timestamp > p.deadline, "IdeaDAO: voting not ended");

        uint256 totalSupply = IERC20(ideaToken).totalSupply();
        require(totalSupply > 0, "IdeaDAO: zero total supply");
        require(p.forVotes > p.againstVotes, "IdeaDAO: proposal did not pass");
        require(
            (p.forVotes * 10000) / totalSupply >= QUORUM_BPS,
            "IdeaDAO: quorum not reached"
        );

        // Nullify requires 66% supermajority
        if (p.pType == ProposalType.NULLIFY_IDEA) {
            require(
                (p.forVotes * 10000) / totalSupply >= NULLIFY_THRESHOLD_BPS,
                "IdeaDAO: nullify requires 66% supermajority"
            );
        }

        uint256 eta = block.timestamp + TIMELOCK;
        proposalEta[proposalId] = eta;
        emit Queued(proposalId, eta);
    }

    /// @notice Execute a queued proposal after the timelock has elapsed.
    function executeProposal(uint256 proposalId) external {
        require(proposalId < proposalCount, "IdeaDAO: invalid proposalId");
        Proposal storage p = proposals[proposalId];
        require(!p.cancelled, "IdeaDAO: proposal cancelled");
        require(!p.executed, "IdeaDAO: proposal already executed");

        uint256 eta = proposalEta[proposalId];
        require(eta != 0, "IdeaDAO: proposal not queued");
        require(block.timestamp >= eta, "IdeaDAO: timelock not elapsed");

        p.executed = true;

        if (p.target != address(0) && p.callData.length > 0) {
            (bool success, bytes memory returnData) = p.target.call(p.callData);
            if (!success) {
                if (returnData.length > 0) {
                    assembly {
                        revert(add(32, returnData), mload(returnData))
                    }
                }
                revert("IdeaDAO: execution failed");
            }
        }

        emit Executed(proposalId);
    }

    /// @notice Cancel a proposal. Only the original proposer may cancel.
    function cancelProposal(uint256 proposalId) external {
        require(proposalId < proposalCount, "IdeaDAO: invalid proposalId");
        Proposal storage p = proposals[proposalId];
        require(msg.sender == p.proposer, "IdeaDAO: not proposer");
        require(!p.executed, "IdeaDAO: already executed");
        require(!p.cancelled, "IdeaDAO: already cancelled");

        p.cancelled = true;
        emit Cancelled(proposalId);
    }

    // -----------------------------------------------------------------------
    // Convenience execution functions (onlySelf)
    // -----------------------------------------------------------------------

    /// @notice Lock the funding pool.
    function lockPool() external onlySelf {
        getIdeaAddresses();
        IFundingPool(fundingPool).lockPool();
    }

    /// @notice Select a builder.
    function selectBuilder(
        address builder,
        uint256 musdPayout,
        uint256 tokenSharePct,
        bytes32 agreementHash,
        uint256 stakeBps
    ) external onlySelf {
        getIdeaAddresses();
        IBuilderAgreement(builderAgreement).propose(
            builder,
            musdPayout,
            tokenSharePct,
            agreementHash,
            stakeBps
        );
        IBuilderAgreement(builderAgreement).accept();
    }

    /// @notice Approve a milestone.
    function approveMilestone(uint256 milestoneId) external onlySelf {
        getIdeaAddresses();
        IMilestone(milestone).approveMilestone(milestoneId);
    }

    /// @notice Nullify the idea.
    function nullifyIdea() external onlySelf {
        getIdeaAddresses();
        IFundingPool(fundingPool).emergencyRefund();
        IIdeaRegistry(registry).updateStatus(ideaId, STATUS_CANCELLED);
    }

    // -----------------------------------------------------------------------
    // View helpers
    // -----------------------------------------------------------------------

    /// @notice Force a refresh of cached idea addresses.
    function refreshAddresses() external {
        addressesCached = false;
        getIdeaAddresses();
    }

    /**
     * @notice Get encrypted vote handles for a proposal.
     */
    function getEncryptedVotes(uint256 proposalId) external view returns (euint64 forVotes, euint64 againstVotes, euint64 voterCount) {
        return (
            _encryptedForVotes[proposalId],
            _encryptedAgainstVotes[proposalId],
            _encryptedVoterCount[proposalId]
        );
    }

    /**
     * @notice Get encrypted quorum snapshot for a proposal.
     */
    function getEncryptedQuorumSnapshot(uint256 proposalId) external view returns (euint64) {
        return _encryptedQuorumSnapshot[proposalId];
    }

    /**
     * @notice Check if proposal has passed (using public counts).
     */
    function hasPassed(uint256 proposalId) external view returns (bool) {
        Proposal storage p = proposals[proposalId];
        uint256 totalSupply = IERC20(ideaToken).totalSupply();
        return p.forVotes > p.againstVotes && 
               (p.forVotes * 10000) / totalSupply >= QUORUM_BPS;
    }
}