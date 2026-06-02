// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {FHE, euint128, ebool} from "@fhenixprotocol/cofhe-contracts/FHE.sol";
import {InEuint128} from "@fhenixprotocol/cofhe-contracts/ICofhe.sol";
import "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../utils/SimpleOwnable.sol";

/**
 * @title BuilderHub
 * @notice Unified contract for builder management, quests, agreements, and milestones.
 *         Consolidates: BuilderAgreement + Milestone + BuilderMarketplace
 * 
 * @dev Protocol Flow:
 *      1. registerBuilder() - Builder creates profile
 *      2. submitQuest() - Builder proposes for an idea
 *      3. signAgreement() - Terms agreed on-chain
 *      4. submitMilestone() - Builder submits progress
 *      5. submitDeliverable() - Final MVP submission
 */
contract BuilderHub is Initializable, SimpleOwnable {
    using SafeERC20 for IERC20;

    // ── Errors ─────────────────────────────────────────────────────────────────

    error BuilderNotRegistered(address builder);
    error BuilderAlreadyRegistered(address builder);
    error QuestAlreadySubmitted(uint256 ideaId, address builder);
    error QuestNotFound(uint256 ideaId, address builder);
    error AgreementNotFound(uint256 ideaId);
    error AgreementAlreadySigned(uint256 ideaId);
    error MilestoneNotFound(uint256 ideaId, uint256 index);
    error MilestoneAlreadySubmitted(uint256 ideaId, uint256 index);
    error NothingToClaim();

    // ── Types ─────────────────────────────────────────────────────────────────

    enum BuilderStatus {
        None,
        Registered,
        Suspended,
        Banned
    }

    enum QuestStatus {
        None,
        Submitted,
        Shortlisted,
        Selected,
        Rejected
    }

    enum AgreementStatus {
        None,
        Proposed,
        Signed,
        Terminated
    }

    enum MilestoneStatus {
        None,
        Submitted,
        Approved,
        Rejected,
        Disputed
    }

    // ── Structs ────────────────────────────────────────────────────────────────

    struct Builder {
        address builder;
        string ipfsProfile;
        BuilderStatus status;
        uint256 completedProjects;
        uint256 activeProjects;
        bool isVerified;
    }

    struct Quest {
        uint256 ideaId;
        address builder;
        string ipfsProposal;
        uint256 requestedBudget;       // USDY
        uint256 suggestedTokenAlloc;   // % (e.g., 1500 = 15%)
        uint256 submissionTime;
        QuestStatus status;
    }

    struct Agreement {
        uint256 ideaId;
        address builder;
        uint256 budget;                // USDY to pay builder
        uint256 tokenAllocPct;         // Token allocation % (10-30%)
        uint256 vestingMonths;
        bytes32 ipfsHash;              // Terms stored on IPFS
        AgreementStatus status;
        uint256 signedTime;
    }

    struct Milestone {
        uint256 ideaId;
        uint256 index;
        string ipfsDescription;
        string criteria;
        uint256 releaseAmount;          // USDY to release on approval
        uint256 releaseTokenPct;       // Additional token % on approval
        MilestoneStatus status;
        uint256 submittedTime;
        uint256 approvedTime;
    }

    struct Deliverable {
        uint256 ideaId;
        string ipfsHash;               // Final MVP / deliverable
        uint256 submittedTime;
        bool finalApproved;
        bool claimed;
    }

    // ── State ─────────────────────────────────────────────────────────────────

    address public governance;
    address public treasury;
    address public usdyToken;
    address public ideaToken;

    /// @notice Registered builders
    mapping(address => Builder) public builders;

    /// @notice Active builders list
    address[] public activeBuilders;

    /// @notice Quests (ideaId → builder → Quest)
    mapping(uint256 => mapping(address => Quest)) public quests;

    /// @notice Agreements (ideaId → Agreement)
    mapping(uint256 => Agreement) public agreements;

    /// @notice Milestones (ideaId → index → Milestone)
    mapping(uint256 => mapping(uint256 => Milestone)) public milestones;

    /// @notice Milestone counts per idea
    mapping(uint256 => uint256) public milestoneCounts;

    /// @notice Final deliverables per idea
    mapping(uint256 => Deliverable) public deliverables;

    /// @notice Encrypted builder reputation
    mapping(address => euint128) private _encryptedReputation;

    /// @notice Builder quests per idea
    mapping(uint256 => address[]) public questSubmissions;

    // ── Events ─────────────────────────────────────────────────────────────────

    event BuilderRegistered(address indexed builder, string ipfsProfile);
    event BuilderVerified(address indexed builder);
    event BuilderSuspended(address indexed builder);
    event QuestSubmitted(uint256 indexed ideaId, address indexed builder, string ipfsProposal);
    event QuestStatusChanged(uint256 indexed ideaId, address indexed builder, QuestStatus status);
    event AgreementProposed(uint256 indexed ideaId, address indexed builder, uint256 budget, uint256 tokenAlloc);
    event AgreementSigned(uint256 indexed ideaId, address indexed builder, bytes32 ipfsHash);
    event AgreementTerminated(uint256 indexed ideaId);
    event MilestoneSubmitted(uint256 indexed ideaId, uint256 indexed index, string ipfsDescription);
    event MilestoneApproved(uint256 indexed ideaId, uint256 indexed index);
    event MilestoneRejected(uint256 indexed ideaId, uint256 indexed index);
    event DeliverableSubmitted(uint256 indexed ideaId, string ipfsHash);
    event DeliverableFinalApproved(uint256 indexed ideaId);

    // ── Initialization ─────────────────────────────────────────────────────────

    function initialize(
        address _governance,
        address _treasury,
        address _usdyToken,
        address _ideaToken,
        address _owner
    ) external initializer {
        require(_governance != address(0), "Zero governance");
        require(_treasury != address(0), "Zero treasury");
        require(_usdyToken != address(0), "Zero USDY");
        
        governance = _governance;
        treasury = _treasury;
        usdyToken = _usdyToken;
        ideaToken = _ideaToken;
        
        _initializeOwner(_owner);
    }

    // ── Builder Management ────────────────────────────────────────────────────

    /**
     * @notice Register as a builder in the marketplace.
     */
    function registerBuilder(string calldata ipfsProfile) external returns (bool success) {
        if (builders[msg.sender].status != BuilderStatus.None) {
            revert BuilderAlreadyRegistered(msg.sender);
        }
        
        builders[msg.sender] = Builder({
            builder: msg.sender,
            ipfsProfile: ipfsProfile,
            status: BuilderStatus.Registered,
            completedProjects: 0,
            activeProjects: 0,
            isVerified: false
        });
        
        activeBuilders.push(msg.sender);
        
        emit BuilderRegistered(msg.sender, ipfsProfile);
        return true;
    }

    /**
     * @notice Verify a builder (off-chain verification recorded on-chain).
     */
    function verifyBuilder(address builder) external {
        require(msg.sender == governance || msg.sender == owner(), "Not governance or owner");
        builders[builder].isVerified = true;
        emit BuilderVerified(builder);
    }

    /**
     * @notice Suspend a builder.
     */
    function suspendBuilder(address builder) external {
        require(msg.sender == governance || msg.sender == owner(), "Not governance or owner");
        builders[builder].status = BuilderStatus.Suspended;
        emit BuilderSuspended(builder);
    }

    // ── Quest Management ──────────────────────────────────────────────────────

    /**
     * @notice Submit a quest proposal for an idea.
     */
    function submitQuest(
        uint256 ideaId,
        string calldata ipfsProposal,
        uint256 requestedBudget,
        uint256 suggestedTokenAlloc
    ) external returns (uint256 questIndex) {
        Builder storage builder = builders[msg.sender];
        if (builder.status == BuilderStatus.None) revert BuilderNotRegistered(msg.sender);
        if (builder.status == BuilderStatus.Suspended) revert BuilderNotRegistered(msg.sender);
        
        Quest storage quest = quests[ideaId][msg.sender];
        if (quest.status != QuestStatus.None) revert QuestAlreadySubmitted(ideaId, msg.sender);
        
        questSubmissions[ideaId].push(msg.sender);
        
        quests[ideaId][msg.sender] = Quest({
            ideaId: ideaId,
            builder: msg.sender,
            ipfsProposal: ipfsProposal,
            requestedBudget: requestedBudget,
            suggestedTokenAlloc: suggestedTokenAlloc,
            submissionTime: block.timestamp,
            status: QuestStatus.Submitted
        });
        
        builder.activeProjects++;
        
        emit QuestSubmitted(ideaId, msg.sender, ipfsProposal);
    }

    /**
     * @notice Update quest status (called by governance).
     */
    function updateQuestStatus(uint256 ideaId, address builder, QuestStatus status) external {
        require(msg.sender == governance || msg.sender == owner(), "Not governance or owner");
        
        Quest storage quest = quests[ideaId][builder];
        if (quest.status == QuestStatus.None) revert QuestNotFound(ideaId, builder);
        
        quest.status = status;
        
        if (status == QuestStatus.Selected) {
            builders[builder].activeProjects++;
        }
        
        emit QuestStatusChanged(ideaId, builder, status);
    }

    // ── Agreement Management ───────────────────────────────────────────────────

    /**
     * @notice Propose an agreement for an idea (terms set by governance).
     */
    function proposeAgreement(
        uint256 ideaId,
        address builder,
        uint256 budget,
        uint256 tokenAllocPct,
        uint256 vestingMonths,
        bytes32 ipfsHash
    ) external {
        require(msg.sender == governance || msg.sender == owner(), "Not governance or owner");
        
        agreements[ideaId] = Agreement({
            ideaId: ideaId,
            builder: builder,
            budget: budget,
            tokenAllocPct: tokenAllocPct,
            vestingMonths: vestingMonths,
            ipfsHash: ipfsHash,
            status: AgreementStatus.Proposed,
            signedTime: 0
        });
        
        emit AgreementProposed(ideaId, builder, budget, tokenAllocPct);
    }

    /**
     * @notice Sign the agreement (builder accepts terms).
     */
    function signAgreement(uint256 ideaId, bytes32 ipfsHash) external returns (bool) {
        Agreement storage agreement = agreements[ideaId];
        if (agreement.builder != msg.sender) revert AgreementNotFound(ideaId);
        if (agreement.status != AgreementStatus.Proposed) revert AgreementAlreadySigned(ideaId);
        
        agreement.status = AgreementStatus.Signed;
        agreement.ipfsHash = ipfsHash;
        agreement.signedTime = block.timestamp;
        
        emit AgreementSigned(ideaId, msg.sender, ipfsHash);
        return true;
    }

    /**
     * @notice Terminate an agreement.
     */
    function terminateAgreement(uint256 ideaId) external {
        require(msg.sender == governance || msg.sender == owner(), "Not governance or owner");
        agreements[ideaId].status = AgreementStatus.Terminated;
        emit AgreementTerminated(ideaId);
    }

    // ── Milestone Management ───────────────────────────────────────────────────

    /**
     * @notice Submit a milestone for an idea.
     */
    function submitMilestone(
        uint256 ideaId,
        string calldata ipfsDescription,
        string calldata criteria,
        uint256 releaseAmount,
        uint256 releaseTokenPct
    ) external returns (uint256 index) {
        Agreement storage agreement = agreements[ideaId];
        if (agreement.builder != msg.sender) revert AgreementNotFound(ideaId);
        if (agreement.status != AgreementStatus.Signed) revert AgreementNotFound(ideaId);
        
        index = milestoneCounts[ideaId]++;
        
        milestones[ideaId][index] = Milestone({
            ideaId: ideaId,
            index: index,
            ipfsDescription: ipfsDescription,
            criteria: criteria,
            releaseAmount: releaseAmount,
            releaseTokenPct: releaseTokenPct,
            status: MilestoneStatus.Submitted,
            submittedTime: block.timestamp,
            approvedTime: 0
        });
        
        emit MilestoneSubmitted(ideaId, index, ipfsDescription);
    }

    /**
     * @notice Approve a milestone (called by governance).
     */
    function approveMilestone(uint256 ideaId, uint256 index) external {
        require(msg.sender == governance || msg.sender == owner(), "Not governance or owner");
        
        Milestone storage milestone = milestones[ideaId][index];
        if (milestone.status == MilestoneStatus.None) revert MilestoneNotFound(ideaId, index);
        
        milestone.status = MilestoneStatus.Approved;
        milestone.approvedTime = block.timestamp;
        
        emit MilestoneApproved(ideaId, index);
    }

    /**
     * @notice Reject a milestone (called by governance).
     */
    function rejectMilestone(uint256 ideaId, uint256 index) external {
        require(msg.sender == governance || msg.sender == owner(), "Not governance or owner");
        
        Milestone storage milestone = milestones[ideaId][index];
        if (milestone.status == MilestoneStatus.None) revert MilestoneNotFound(ideaId, index);
        
        milestone.status = MilestoneStatus.Rejected;
        
        emit MilestoneRejected(ideaId, index);
    }

    // ── Deliverable Management ─────────────────────────────────────────────────

    /**
     * @notice Submit final deliverable / MVP.
     */
    function submitDeliverable(uint256 ideaId, string calldata ipfsHash) external {
        Agreement storage agreement = agreements[ideaId];
        if (agreement.builder != msg.sender) revert AgreementNotFound(ideaId);
        
        deliverables[ideaId] = Deliverable({
            ideaId: ideaId,
            ipfsHash: ipfsHash,
            submittedTime: block.timestamp,
            finalApproved: false,
            claimed: false
        });
        
        emit DeliverableSubmitted(ideaId, ipfsHash);
    }

    /**
     * @notice Mark final deliverable as approved (called by governance).
     */
    function approveFinalDeliverable(uint256 ideaId) external {
        require(msg.sender == governance || msg.sender == owner(), "Not governance or owner");
        deliverables[ideaId].finalApproved = true;
        emit DeliverableFinalApproved(ideaId);
    }

    /**
     * @notice Mark deliverable as claimed by builder.
     */
    function markDeliverableClaimed(uint256 ideaId) external {
        require(msg.sender == treasury, "Not treasury");
        deliverables[ideaId].claimed = true;
    }

    // ── Reputation ──────────────────────────────────────────────────────────────

    /**
     * @notice Update builder reputation (encrypted).
     */
    function updateReputation(address builder, InEuint128 calldata encryptedScore) external {
        require(msg.sender == governance || msg.sender == owner(), "Not governance or owner");
        
        euint128 score = FHE.asEuint128(encryptedScore);
        _encryptedReputation[builder] = FHE.add(_encryptedReputation[builder], score);
        FHE.allowThis(_encryptedReputation[builder]);
    }

    /**
     * @notice Increment completed projects count.
     */
    function markProjectCompleted(uint256 ideaId) external {
        require(msg.sender == governance || msg.sender == owner(), "Not governance or owner");
        
        Agreement storage agreement = agreements[ideaId];
        if (agreement.builder != address(0)) {
            builders[agreement.builder].completedProjects++;
            builders[agreement.builder].activeProjects--;
        }
    }

    // ── View Functions ─────────────────────────────────────────────────────────

    function getBuilder(address builder) external view returns (Builder memory) {
        return builders[builder];
    }

    function getQuest(uint256 ideaId, address builder) external view returns (Quest memory) {
        return quests[ideaId][builder];
    }

    function getQuestsForIdea(uint256 ideaId) external view returns (Quest[] memory result) {
        address[] storage submissions = questSubmissions[ideaId];
        result = new Quest[](submissions.length);
        for (uint256 i = 0; i < submissions.length; i++) {
            result[i] = quests[ideaId][submissions[i]];
        }
    }

    function getAgreement(uint256 ideaId) external view returns (Agreement memory) {
        return agreements[ideaId];
    }

    function getMilestone(uint256 ideaId, uint256 index) external view returns (Milestone memory) {
        return milestones[ideaId][index];
    }

    function getMilestoneCount(uint256 ideaId) external view returns (uint256) {
        return milestoneCounts[ideaId];
    }

    function getDeliverable(uint256 ideaId) external view returns (Deliverable memory) {
        return deliverables[ideaId];
    }

    function getEncryptedReputation(address builder) external view returns (euint128) {
        return _encryptedReputation[builder];
    }

    function isBuilderRegistered(address builder) external view returns (bool) {
        return builders[builder].status != BuilderStatus.None;
    }

    function isBuilderVerified(address builder) external view returns (bool) {
        return builders[builder].isVerified;
    }

    function getActiveBuilderCount() external view returns (uint256) {
        return activeBuilders.length;
    }

    // ── Permissioned Disclosure ───────────────────────────────────────────────

    /**
     * @notice Request to disclose reputation to a specific address.
     */
    function requestReputationDisclosure(address builder, address recipient) external {
        require(builders[builder].builder == builder, "Not a builder");
        euint128 rep = _encryptedReputation[builder];
        FHE.allow(rep, recipient);
    }
}