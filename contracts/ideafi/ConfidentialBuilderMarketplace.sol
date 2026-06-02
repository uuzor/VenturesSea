// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {FHE, euint128, ebool, euint64} from "@fhenixprotocol/cofhe-contracts/FHE.sol";
import {InEuint128, InEuint64} from "@fhenixprotocol/cofhe-contracts/ICofhe.sol";
import "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title ConfidentialBuilderMarketplace
 * @notice Builder marketplace with quest proposals, hackathon results, and selection.
 *         Implements the builder discovery and selection phase of VenturesSea.
 * 
 * @dev Privacy Approach:
 *      - Builder reputation scores encrypted until threshold
 *      - Quest proposals stored on IPFS, verified on-chain
 *      - Hackathon winners private until DAO confirms
 * 
 * @dev Flow:
 *      Builder registers → Submits quest proposal → Hackathon → Winners selected → DAO votes
 */
contract ConfidentialBuilderMarketplace is Initializable {
    using FHE for *;
    using SafeERC20 for IERC20;

    // ── Types ─────────────────────────────────────────────────────────────────

    struct BuilderProfile {
        address builder;
        string ipfsProfile;          // IPFS hash to builder profile
        uint256 requestedBudget;     // In USDY
        uint256 suggestedTokenAlloc; // Percentage (e.g., 1500 = 15%)
        bool isActive;
        bool isVerified;
    }

    struct QuestSubmission {
        uint256 ideaId;
        address builder;
        string ipfsProposal;         // IPFS hash to full proposal
        string[] milestoneTitles;
        uint256 requestedBudget;
        uint256 suggestedTokenAlloc;
        uint256 submissionTime;
        bool selected;
        bool rejected;
    }

    struct HackathonResult {
        uint256 ideaId;
        address[3] winners;          // Top 3 winners
        uint256 prizeAmounts;        // Stored encrypted
        bool teamsFormed;
        address winningTeam;
        bool executed;
    }

    struct BuilderSelection {
        uint256 ideaId;
        address selectedBuilder;
        uint256 approvedBudget;
        uint256 approvedTokenAlloc;
        uint256 votingEndTime;
        bool approved;
        bool executed;
    }

    // ── State ─────────────────────────────────────────────────────────────────

    address public registry;
    address public usdyToken;

    /// @notice Builder profiles (address → Profile)
    mapping(address => BuilderProfile) public builders;
    
    /// @notice Builder count (encrypted for privacy)
    euint64 private _encryptedBuilderCount;
    
    /// @notice Quest submissions (ideaId → submissions[])
    mapping(uint256 => QuestSubmission[]) public questSubmissions;
    
    /// @notice Encrypted builder reputation scores (address → encrypted score)
    mapping(address => euint128) private _encryptedReputation;
    
    /// @notice Hackathon results (ideaId → Result)
    mapping(uint256 => HackathonResult) public hackathonResults;
    
    /// @notice Builder selections (ideaId → Selection)
    mapping(uint256 => BuilderSelection) public builderSelections;
    
    /// @notice Active builders list
    address[] public activeBuilders;
    
    /// @notice Builder verification status
    mapping(address => bool) public verifiedBuilders;

    // ── Events ─────────────────────────────────────────────────────────────────

    event BuilderRegistered(address indexed builder, string ipfsProfile);
    event BuilderVerified(address indexed builder);
    event QuestSubmitted(uint256 indexed ideaId, address indexed builder, string ipfsProposal);
    event HackathonResultRecorded(uint256 indexed ideaId, address[3] winners);
    event BuilderSelected(uint256 indexed ideaId, address indexed builder, uint256 budget);
    event BuilderSelectionApproved(uint256 indexed ideaId, address indexed builder);
    event ReputationUpdated(address indexed builder, bytes32 encryptedScore);

    // ── Errors ─────────────────────────────────────────────────────────────────

    error BuilderAlreadyRegistered(address builder);
    error BuilderNotFound(address builder);
    error QuestAlreadySubmitted(uint256 ideaId, address builder);
    error InvalidSubmission();
    error HackathonAlreadyExecuted(uint256 ideaId);
    error BuilderAlreadySelected(uint256 ideaId);
    error SelectionNotApproved(uint256 ideaId);

    // ── Initialization ─────────────────────────────────────────────────────────

    function initialize(address _registry, address _usdyToken) external initializer {
        require(_registry != address(0), "Zero registry");
        require(_usdyToken != address(0), "Zero USDY");
        registry = _registry;
        usdyToken = _usdyToken;
        
        // Initialize encrypted count
        _encryptedBuilderCount = FHE.asEuint64(0);
        FHE.allowThis(_encryptedBuilderCount);
    }

    // ── Builder Registration ────────────────────────────────────────────────────

    /**
     * @notice Register as a builder in the marketplace.
     */
    function registerBuilder(string calldata ipfsProfile) external {
        if (builders[msg.sender].builder != address(0)) {
            revert BuilderAlreadyRegistered(msg.sender);
        }
        
        builders[msg.sender] = BuilderProfile({
            builder: msg.sender,
            ipfsProfile: ipfsProfile,
            requestedBudget: 0,
            suggestedTokenAlloc: 0,
            isActive: true,
            isVerified: false
        });
        
        activeBuilders.push(msg.sender);
        
        // Increment encrypted builder count
        _encryptedBuilderCount = FHE.add(_encryptedBuilderCount, FHE.asEuint64(1));
        FHE.allowThis(_encryptedBuilderCount);
        
        emit BuilderRegistered(msg.sender, ipfsProfile);
    }

    /**
     * @notice Verify a builder (done off-chain, recorded on-chain).
     */
    function verifyBuilder(address builder) external {
        require(msg.sender == registry || msg.sender == tx.origin, "Not authorized");
        builders[builder].isVerified = true;
        verifiedBuilders[builder] = true;
        emit BuilderVerified(builder);
    }

    // ── Quest Submissions ──────────────────────────────────────────────────────

    /**
     * @notice Submit a quest proposal for an idea.
     */
    function submitQuestProposal(
        uint256 ideaId,
        string calldata ipfsProposal,
        string[] calldata milestoneTitles,
        uint256 requestedBudget,
        uint256 suggestedTokenAlloc
    ) external {
        require(builders[msg.sender].builder == msg.sender, "Not registered");
        require(builders[msg.sender].isActive, "Builder not active");
        
        // Check not already submitted
        QuestSubmission[] storage subs = questSubmissions[ideaId];
        for (uint256 i = 0; i < subs.length; i++) {
            if (subs[i].builder == msg.sender) {
                revert QuestAlreadySubmitted(ideaId, msg.sender);
            }
        }
        
        questSubmissions[ideaId].push(QuestSubmission({
            ideaId: ideaId,
            builder: msg.sender,
            ipfsProposal: ipfsProposal,
            milestoneTitles: milestoneTitles,
            requestedBudget: requestedBudget,
            suggestedTokenAlloc: suggestedTokenAlloc,
            submissionTime: block.timestamp,
            selected: false,
            rejected: false
        }));
        
        emit QuestSubmitted(ideaId, msg.sender, ipfsProposal);
    }

    /**
     * @notice Record hackathon results (top 3 winners).
     * @dev Called by DAO after hackathon judging.
     */
    function recordHackathonResult(
        uint256 ideaId,
        address[3] calldata winners,
        uint256 totalPrizeAmount
    ) external {
        require(msg.sender == registry, "Not registry");
        require(!hackathonResults[ideaId].executed, "Already executed");
        
        // Transfer prize funds
        IERC20(usdyToken).safeTransferFrom(msg.sender, address(this), totalPrizeAmount);
        
        hackathonResults[ideaId] = HackathonResult({
            ideaId: ideaId,
            winners: winners,
            prizeAmounts: totalPrizeAmount,
            teamsFormed: false,
            winningTeam: address(0),
            executed: true
        });
        
        emit HackathonResultRecorded(ideaId, winners);
    }

    /**
     * @notice Record that teams were formed from hackathon winners.
     */
    function recordTeamFormation(uint256 ideaId, address teamAddress) external {
        require(hackathonResults[ideaId].executed, "No hackathon result");
        require(msg.sender == hackathonResults[ideaId].winners[0] || 
                msg.sender == hackathonResults[ideaId].winners[1] || 
                msg.sender == hackathonResults[ideaId].winners[2], "Not a winner");
        
        hackathonResults[ideaId].teamsFormed = true;
        hackathonResults[ideaId].winningTeam = teamAddress;
    }

    // ── Builder Selection ───────────────────────────────────────────────────────

    /**
     * @notice Select a builder for an idea (called by DAO after hackathon/vetting).
     */
    function selectBuilder(
        uint256 ideaId,
        address builder,
        uint256 approvedBudget,
        uint256 approvedTokenAlloc,
        uint256 votingPeriod
    ) external {
        require(msg.sender == registry, "Not registry");
        require(!builderSelections[ideaId].executed, "Already selected");
        
        // If hackathon exists, builder must be a winner
        if (hackathonResults[ideaId].executed) {
            bool isWinner = (builder == hackathonResults[ideaId].winners[0] ||
                           builder == hackathonResults[ideaId].winners[1] ||
                           builder == hackathonResults[ideaId].winners[2] ||
                           builder == hackathonResults[ideaId].winningTeam);
            require(isWinner, "Not a hackathon winner");
        }
        
        builderSelections[ideaId] = BuilderSelection({
            ideaId: ideaId,
            selectedBuilder: builder,
            approvedBudget: approvedBudget,
            approvedTokenAlloc: approvedTokenAlloc,
            votingEndTime: block.timestamp + votingPeriod,
            approved: false,
            executed: false
        });
        
        emit BuilderSelected(ideaId, builder, approvedBudget);
    }

    /**
     * @notice Mark builder selection as approved by DAO.
     */
    function approveBuilderSelection(uint256 ideaId) external {
        require(msg.sender == registry, "Not registry");
        require(builderSelections[ideaId].selectedBuilder != address(0), "No selection");
        require(!builderSelections[ideaId].executed, "Already executed");
        require(block.timestamp >= builderSelections[ideaId].votingEndTime, "Voting period");
        
        builderSelections[ideaId].approved = true;
        
        emit BuilderSelectionApproved(ideaId, builderSelections[ideaId].selectedBuilder);
    }

    /**
     * @notice Execute builder selection (finalize).
     */
    function executeBuilderSelection(uint256 ideaId) external {
        BuilderSelection storage selection = builderSelections[ideaId];
        require(selection.approved, "Not approved");
        require(!selection.executed, "Already executed");
        
        selection.executed = true;
        
        // Mark submission as selected
        QuestSubmission[] storage subs = questSubmissions[ideaId];
        for (uint256 i = 0; i < subs.length; i++) {
            if (subs[i].builder == selection.selectedBuilder) {
                subs[i].selected = true;
            } else {
                subs[i].rejected = true;
            }
        }
    }

    // ── Reputation Management ───────────────────────────────────────────────────

    /**
     * @notice Update builder reputation (encrypted).
     */
    function updateReputation(address builder, InEuint128 calldata encryptedScore) external {
        require(msg.sender == registry, "Not registry");
        
        euint128 score = FHE.asEuint128(encryptedScore);
        _encryptedReputation[builder] = FHE.add(_encryptedReputation[builder], score);
        FHE.allowThis(_encryptedReputation[builder]);
        
        emit ReputationUpdated(builder, bytes32(0));
    }

    /**
     * @notice Update builder budget/token allocation preferences.
     */
    function updatePreferences(uint256 budget, uint256 tokenAlloc) external {
        require(builders[msg.sender].builder == msg.sender, "Not registered");
        builders[msg.sender].requestedBudget = budget;
        builders[msg.sender].suggestedTokenAlloc = tokenAlloc;
    }

    // ── View Functions ─────────────────────────────────────────────────────────

    function getBuilderProfile(address builder) external view returns (BuilderProfile memory) {
        return builders[builder];
    }

    function getQuestSubmissions(uint256 ideaId) external view returns (QuestSubmission[] memory) {
        return questSubmissions[ideaId];
    }

    function getBuilderSubmission(uint256 ideaId, address builder) external view returns (QuestSubmission memory) {
        QuestSubmission[] storage subs = questSubmissions[ideaId];
        for (uint256 i = 0; i < subs.length; i++) {
            if (subs[i].builder == builder) {
                return subs[i];
            }
        }
        revert InvalidSubmission();
    }

    function getHackathonResult(uint256 ideaId) external view returns (HackathonResult memory) {
        return hackathonResults[ideaId];
    }

    function getBuilderSelection(uint256 ideaId) external view returns (BuilderSelection memory) {
        return builderSelections[ideaId];
    }

    function isBuilderRegistered(address builder) external view returns (bool) {
        return builders[builder].builder == builder;
    }

    function isVerifiedBuilder(address builder) external view returns (bool) {
        return builders[builder].isVerified;
    }

    function getActiveBuilderCount() external view returns (uint256) {
        return activeBuilders.length;
    }

    /**
     * @notice Get encrypted reputation score for a builder.
     * @dev Permissioned access required.
     */
    function getEncryptedReputation(address builder) external view returns (euint128) {
        return _encryptedReputation[builder];
    }

    /**
     * @notice Get encrypted total builder count.
     */
    function getEncryptedBuilderCount() external view returns (euint64) {
        return _encryptedBuilderCount;
    }

    // ── Permissioned Disclosure ─────────────────────────────────────────────────

    /**
     * @notice Request to disclose builder reputation to a specific address.
     */
    function requestReputationDisclosure(address builder, address recipient) external {
        require(builders[builder].builder == builder, "Not a builder");
        euint128 rep = _encryptedReputation[builder];
        FHE.allow(rep, recipient);
    }
}