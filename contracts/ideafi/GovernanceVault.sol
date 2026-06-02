// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {FHE, euint128, ebool} from "@fhenixprotocol/cofhe-contracts/FHE.sol";
import {InEuint128} from "@fhenixprotocol/cofhe-contracts/ICofhe.sol";
import "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import "../utils/SimpleOwnable.sol";

/**
 * @title GovernanceVault
 * @notice Unified contract for all DAO voting decisions.
 *         Consolidates: IdeaDAO (all voting types)
 * 
 * @dev Vote Types:
 *      - BuilderSelection: Select builder for an idea
 *      - MilestoneApproval: Approve/reject milestone submissions
 *      - FinalMVP: Final vote on product/deliverable
 *      - Refund: Vote on refund (pre-lock rejection)
 *      - Fork: Vote on fork (post-lock rejection)
 * 
 * @dev All votes use FHE-encrypted weights for privacy.
 */
contract GovernanceVault is Initializable, SimpleOwnable {
    using FHE for *;

    // ── Errors ─────────────────────────────────────────────────────────────────

    error ProposalNotFound(uint256 proposalId);
    error VotingActive();
    error VotingEnded();
    error AlreadyExecuted();
    error QuorumNotReached();
    error InvalidVoteType();
    error AlreadyVoted(address voter);
    error NoPermission();

    // ── Types ─────────────────────────────────────────────────────────────────

    enum VoteType {
        None,
        BuilderSelection,  // Select builder for idea
        MilestoneApproval, // Approve milestone
        FinalMVP,          // Final product vote
        Refund,            // Pre-lock refund vote
        Fork               // Post-lock fork vote
    }

    enum Outcome {
        Pending,
        Approved,
        Rejected
    }

    // ── Structs ───────────────────────────────────────────────────────────────

    struct Proposal {
        uint256 id;
        uint256 ideaId;
        VoteType voteType;
        address targetAddress;        // Builder address for selection, new builder for fork
        uint256 votingDeadline;
        Outcome outcome;
        bool executed;
        uint256 createdAt;
    }

    struct Vote {
        address voter;
        bool support;
        euint128 weight;              // Encrypted voting weight (token balance)
        uint256 timestamp;
    }

    struct MilestoneCriteria {
        uint256 ideaId;
        string criteriaHash;         // IPFS hash with criteria details
        uint256 approvalThreshold;   // % of votes needed
        bool set;
    }

    struct ForkProposal {
        uint256 ideaId;
        address originalBuilder;
        address newBuilder;
        string reason;               // IPFS hash
        uint256 votesFor;
        uint256 votesAgainst;
        Outcome outcome;
    }

    // ── State ─────────────────────────────────────────────────────────────────

    address public ideaVault;
    address public builderHub;
    address public treasury;

    uint256 public proposalCounter;
    uint256 public votingDuration;    // Default voting period in seconds
    uint256 public quorumThreshold;   // Minimum participation %

    /// @notice Proposals by ID
    mapping(uint256 => Proposal) public proposals;

    /// @notice Votes (proposalId → voter → Vote)
    mapping(uint256 => mapping(address => Vote)) public votes;

    /// @notice Vote counts per proposal (encrypted)
    mapping(uint256 => euint128) private _encryptedVotesFor;
    mapping(uint256 => euint128) private _encryptedVotesAgainst;
    
    /// @notice Encrypted total participation
    mapping(uint256 => euint128) private _encryptedTotalVotes;

    /// @notice Milestone criteria per idea
    mapping(uint256 => MilestoneCriteria) public milestoneCriteria;

    /// @notice Fork proposals
    mapping(uint256 => ForkProposal) public forkProposals;

    /// @notice Voters per proposal (for iteration)
    mapping(uint256 => address[]) public proposalVoters;

    // ── Events ─────────────────────────────────────────────────────────────────

    event ProposalCreated(uint256 indexed proposalId, uint256 indexed ideaId, VoteType voteType);
    event VoteCast(uint256 indexed proposalId, address indexed voter, bool support);
    event VoteFinalized(uint256 indexed proposalId, Outcome outcome, uint256 votesFor, uint256 votesAgainst);
    event ProposalExecuted(uint256 indexed proposalId);
    event MilestoneCriteriaSet(uint256 indexed ideaId, string criteriaHash);
    event RefundApproved(uint256 indexed ideaId, uint256 amount);
    event ForkProposed(uint256 indexed ideaId, address newBuilder, string reason);
    event ForkExecuted(uint256 indexed ideaId, address newBuilder);

    // ── Initialization ─────────────────────────────────────────────────────────

    function initialize(
        address _ideaVault,
        address _builderHub,
        address _treasury,
        address _owner
    ) external initializer {
        require(_ideaVault != address(0), "Zero IdeaVault");
        require(_builderHub != address(0), "Zero BuilderHub");
        require(_treasury != address(0), "Zero Treasury");
        
        ideaVault = _ideaVault;
        builderHub = _builderHub;
        treasury = _treasury;
        proposalCounter = 1;
        votingDuration = 7 days;
        quorumThreshold = 500; // 5% of tokens must participate (in basis points)
        
        _initializeOwner(_owner);
    }

    // ── Proposal Creation ──────────────────────────────────────────────────────

    /**
     * @notice Create a builder selection vote.
     */
    function createBuilderSelectionVote(
        uint256 ideaId,
        address builder,
        uint256 duration
    ) external onlyOwner returns (uint256 proposalId) {
        proposalId = proposalCounter++;
        
        proposals[proposalId] = Proposal({
            id: proposalId,
            ideaId: ideaId,
            voteType: VoteType.BuilderSelection,
            targetAddress: builder,
            votingDeadline: block.timestamp + (duration > 0 ? duration : votingDuration),
            outcome: Outcome.Pending,
            executed: false,
            createdAt: block.timestamp
        });
        
        // Initialize encrypted vote counters
        _encryptedVotesFor[proposalId] = FHE.asEuint128(0);
        _encryptedVotesAgainst[proposalId] = FHE.asEuint128(0);
        _encryptedTotalVotes[proposalId] = FHE.asEuint128(0);
        FHE.allowThis(_encryptedVotesFor[proposalId]);
        FHE.allowThis(_encryptedVotesAgainst[proposalId]);
        FHE.allowThis(_encryptedTotalVotes[proposalId]);
        
        emit ProposalCreated(proposalId, ideaId, VoteType.BuilderSelection);
    }

    /**
     * @notice Create a milestone approval vote.
     */
    function createMilestoneApprovalVote(
        uint256 ideaId,
        uint256 duration
    ) external returns (uint256 proposalId) {
        require(msg.sender == builderHub, "Not BuilderHub");
        
        proposalId = proposalCounter++;
        
        proposals[proposalId] = Proposal({
            id: proposalId,
            ideaId: ideaId,
            voteType: VoteType.MilestoneApproval,
            targetAddress: address(0),
            votingDeadline: block.timestamp + (duration > 0 ? duration : votingDuration),
            outcome: Outcome.Pending,
            executed: false,
            createdAt: block.timestamp
        });
        
        _encryptedVotesFor[proposalId] = FHE.asEuint128(0);
        _encryptedVotesAgainst[proposalId] = FHE.asEuint128(0);
        _encryptedTotalVotes[proposalId] = FHE.asEuint128(0);
        FHE.allowThis(_encryptedVotesFor[proposalId]);
        FHE.allowThis(_encryptedVotesAgainst[proposalId]);
        FHE.allowThis(_encryptedTotalVotes[proposalId]);
        
        emit ProposalCreated(proposalId, ideaId, VoteType.MilestoneApproval);
    }

    /**
     * @notice Create a final MVP vote.
     */
    function createFinalMVPVote(
        uint256 ideaId,
        uint256 duration
    ) external returns (uint256 proposalId) {
        require(msg.sender == builderHub, "Not BuilderHub");
        
        proposalId = proposalCounter++;
        
        proposals[proposalId] = Proposal({
            id: proposalId,
            ideaId: ideaId,
            voteType: VoteType.FinalMVP,
            targetAddress: address(0),
            votingDeadline: block.timestamp + (duration > 0 ? duration : votingDuration),
            outcome: Outcome.Pending,
            executed: false,
            createdAt: block.timestamp
        });
        
        _encryptedVotesFor[proposalId] = FHE.asEuint128(0);
        _encryptedVotesAgainst[proposalId] = FHE.asEuint128(0);
        _encryptedTotalVotes[proposalId] = FHE.asEuint128(0);
        FHE.allowThis(_encryptedVotesFor[proposalId]);
        FHE.allowThis(_encryptedVotesAgainst[proposalId]);
        FHE.allowThis(_encryptedTotalVotes[proposalId]);
        
        emit ProposalCreated(proposalId, ideaId, VoteType.FinalMVP);
    }

    /**
     * @notice Create a refund vote (pre-lock rejection).
     */
    function createRefundVote(uint256 ideaId, uint256 duration) external onlyOwner returns (uint256 proposalId) {
        proposalId = proposalCounter++;
        
        proposals[proposalId] = Proposal({
            id: proposalId,
            ideaId: ideaId,
            voteType: VoteType.Refund,
            targetAddress: address(0),
            votingDeadline: block.timestamp + (duration > 0 ? duration : votingDuration),
            outcome: Outcome.Pending,
            executed: false,
            createdAt: block.timestamp
        });
        
        _encryptedVotesFor[proposalId] = FHE.asEuint128(0);
        _encryptedVotesAgainst[proposalId] = FHE.asEuint128(0);
        _encryptedTotalVotes[proposalId] = FHE.asEuint128(0);
        FHE.allowThis(_encryptedVotesFor[proposalId]);
        FHE.allowThis(_encryptedVotesAgainst[proposalId]);
        FHE.allowThis(_encryptedTotalVotes[proposalId]);
        
        emit ProposalCreated(proposalId, ideaId, VoteType.Refund);
    }

    // ── Voting ─────────────────────────────────────────────────────────────────

    /**
     * @notice Cast a vote with encrypted weight (FHE).
     */
    function castVote(uint256 proposalId, bool support, InEuint128 calldata encryptedWeight) external {
        Proposal storage proposal = proposals[proposalId];
        if (proposal.id != proposalId) revert ProposalNotFound(proposalId);
        if (block.timestamp > proposal.votingDeadline) revert VotingEnded();
        if (proposal.executed) revert AlreadyExecuted();
        
        // Check if already voted (use timestamp as indicator since FHE types can't be compared)
        Vote storage existingVote = votes[proposalId][msg.sender];
        require(existingVote.timestamp == 0, AlreadyVoted(msg.sender));
        
        // Get encrypted weight
        euint128 weight = FHE.asEuint128(encryptedWeight);
        
        // Record vote
        votes[proposalId][msg.sender] = Vote({
            voter: msg.sender,
            support: support,
            weight: weight,
            timestamp: block.timestamp
        });
        
        proposalVoters[proposalId].push(msg.sender);
        
        // Update encrypted totals
        if (support) {
            _encryptedVotesFor[proposalId] = FHE.add(_encryptedVotesFor[proposalId], weight);
        } else {
            _encryptedVotesAgainst[proposalId] = FHE.add(_encryptedVotesAgainst[proposalId], weight);
        }
        _encryptedTotalVotes[proposalId] = FHE.add(_encryptedTotalVotes[proposalId], weight);
        
        FHE.allowThis(_encryptedVotesFor[proposalId]);
        FHE.allowThis(_encryptedVotesAgainst[proposalId]);
        
        emit VoteCast(proposalId, msg.sender, support);
    }

    /**
     * @notice Finalize vote and determine outcome.
     */
    function finalizeVote(uint256 proposalId) external returns (Outcome) {
        Proposal storage proposal = proposals[proposalId];
        if (proposal.id != proposalId) revert ProposalNotFound(proposalId);
        if (block.timestamp < proposal.votingDeadline) revert VotingActive();
        if (proposal.executed) revert AlreadyExecuted();
        
        // Get encrypted vote counts - for simulation, use plaintext
        euint128 votesFor = _encryptedVotesFor[proposalId];
        euint128 votesAgainst = _encryptedVotesAgainst[proposalId];
        
        // Calculate outcome (simplified for simulation)
        // In production, this would decrypt and compare
        uint256 forCount = 0; // Would be FHE.decrypt(votesFor)
        uint256 againstCount = 0; // Would be FHE.decrypt(votesAgainst)
        
        // For now, mark as approved if any votes for
        // Real implementation uses proper decryption
        bool isApproved = forCount > againstCount || forCount > 0;
        
        proposal.outcome = isApproved ? Outcome.Approved : Outcome.Rejected;
        
        emit VoteFinalized(proposalId, proposal.outcome, forCount, againstCount);
        
        return proposal.outcome;
    }

    /**
     * @notice Execute approved proposal.
     */
    function executeProposal(uint256 proposalId) external returns (bool) {
        Proposal storage proposal = proposals[proposalId];
        if (proposal.id != proposalId) revert ProposalNotFound(proposalId);
        if (proposal.executed) revert AlreadyExecuted();
        if (proposal.outcome != Outcome.Approved) revert NoPermission();
        
        proposal.executed = true;
        
        // Execute based on vote type
        if (proposal.voteType == VoteType.BuilderSelection) {
            // Select builder in IdeaVault
            // This would call ideaVault.selectBuilder(proposal.ideaId, proposal.targetAddress, ...)
        }
        
        emit ProposalExecuted(proposalId);
        return true;
    }

    // ── Milestone Criteria ─────────────────────────────────────────────────────

    /**
     * @notice Set milestone criteria for an idea (DAO defines what builder must achieve).
     */
    function setMilestoneCriteria(uint256 ideaId, string calldata criteriaHash, uint256 approvalThreshold) external onlyOwner {
        milestoneCriteria[ideaId] = MilestoneCriteria({
            ideaId: ideaId,
            criteriaHash: criteriaHash,
            approvalThreshold: approvalThreshold,
            set: true
        });
        
        emit MilestoneCriteriaSet(ideaId, criteriaHash);
    }

    /**
     * @notice Get milestone criteria for an idea.
     */
    function getMilestoneCriteria(uint256 ideaId) external view returns (MilestoneCriteria memory) {
        return milestoneCriteria[ideaId];
    }

    // ── Refund ─────────────────────────────────────────────────────────────────

    /**
     * @notice Process refund vote result (called after refund vote approved).
     */
    function processRefundVote(uint256 ideaId, uint256 amount) external onlyOwner {
        Proposal storage proposal = proposals[ideaId]; // Using ideaId as proposalId for refunds
        if (proposal.outcome != Outcome.Approved) revert NoPermission();
        if (proposal.voteType != VoteType.Refund) revert InvalidVoteType();
        
        // Signal treasury to process refund
        emit RefundApproved(ideaId, amount);
    }

    // ── Fork ───────────────────────────────────────────────────────────────────

    /**
     * @notice Propose a fork (post-lock rejection → new builder).
     */
    function proposeFork(uint256 ideaId, address newBuilder, string calldata reason) external onlyOwner returns (uint256 forkId) {
        forkId = proposalCounter++;
        
        forkProposals[ideaId] = ForkProposal({
            ideaId: ideaId,
            originalBuilder: address(0), // Set from agreement
            newBuilder: newBuilder,
            reason: reason,
            votesFor: 0,
            votesAgainst: 0,
            outcome: Outcome.Pending
        });
        
        emit ForkProposed(ideaId, newBuilder, reason);
    }

    /**
     * @notice Execute fork - transfer to new builder.
     */
    function executeFork(uint256 ideaId) external onlyOwner {
        ForkProposal storage fork = forkProposals[ideaId];
        if (fork.outcome != Outcome.Approved) revert NoPermission();
        
        // Execute fork logic
        emit ForkExecuted(ideaId, fork.newBuilder);
    }

    // ── View Functions ─────────────────────────────────────────────────────────

    function getProposal(uint256 proposalId) external view returns (Proposal memory) {
        return proposals[proposalId];
    }

    function getVote(uint256 proposalId, address voter) external view returns (Vote memory) {
        return votes[proposalId][voter];
    }

    function getVoteCount(uint256 proposalId) external view returns (uint256 forCount, uint256 againstCount) {
        return (0, 0); // Would return decrypted counts in production
    }

    function getEncryptedVotesFor(uint256 proposalId) external view returns (euint128) {
        return _encryptedVotesFor[proposalId];
    }

    function getEncryptedVotesAgainst(uint256 proposalId) external view returns (euint128) {
        return _encryptedVotesAgainst[proposalId];
    }

    function getEncryptedTotalVotes(uint256 proposalId) external view returns (euint128) {
        return _encryptedTotalVotes[proposalId];
    }

    function isVotingActive(uint256 proposalId) external view returns (bool) {
        Proposal storage proposal = proposals[proposalId];
        return block.timestamp <= proposal.votingDeadline && !proposal.executed;
    }

    function hasVoted(uint256 proposalId, address voter) external view returns (bool) {
        Vote storage vote = votes[proposalId][voter];
        return vote.timestamp > 0;
    }

    // ── Configuration ─────────────────────────────────────────────────────────

    /**
     * @notice Update default voting duration.
     */
    function setVotingDuration(uint256 duration) external onlyOwner {
        votingDuration = duration;
    }

    /**
     * @notice Update quorum threshold.
     */
    function setQuorumThreshold(uint256 threshold) external onlyOwner {
        quorumThreshold = threshold;
    }
}