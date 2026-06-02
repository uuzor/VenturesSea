// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {FHE, euint128, ebool, euint64} from "@fhenixprotocol/cofhe-contracts/FHE.sol";
import {InEuint128} from "@fhenixprotocol/cofhe-contracts/ICofhe.sol";
import "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../interfaces/IIdeaFi.sol";
import "../utils/SimpleOwnable.sol";

/**
 * @title IdeaVault
 * @notice Unified contract for idea creation, funding window, and token minting.
 *         Consolidates: IdeaRegistry + IdeaToken + FundingPool + FundingWindow
 * 
 * @dev Protocol Flow:
 *      1. createIdea() - Creator posts idea with funding parameters
 *      2. openFunding() - Funding window opens
 *      3. fund() - Investors deposit USDY, receive IdeaTokens
 *      4. closeFunding() - Window closes, results finalized
 *      5. selectBuilder() - Governance selects builder (external call)
 *      6. lockFunding() - Funds locked for builder
 *      7. operational - Product live, revenue flows
 */
contract IdeaVault is Initializable, SimpleOwnable {
    using FHE for *;
    using SafeERC20 for IERC20;

    // ── Errors ─────────────────────────────────────────────────────────────────

    error IdeaNotFound(uint256 ideaId);
    error InvalidState(IdeaState required, IdeaState actual);
    error FundingExpired();
    error FundingTargetReached();
    error GatingEnabled(address user);
    error ZeroAmount();
    error AlreadyFinalized();
    error NoBuilderSelected();

    // ── Types ─────────────────────────────────────────────────────────────────

    enum IdeaState {
        RequestOpen,      // Idea created, awaiting funding
        FundingOpen,      // Funding window active
        FundingClosed,    // Window closed, awaiting builder
        BuilderSelected,  // Builder selected, not yet locked
        Locked,           // Funding locked, builder working
        Operational,      // Product live, revenue flowing
        Cancelled         // Idea cancelled
    }

    enum TokenType {
        None,
        InvestorToken,    // Issued to USDY depositors
        BuilderToken      // Issued to builder (10-30% allocation)
    }

    // ── Structs ────────────────────────────────────────────────────────────────

    struct Idea {
        uint256 id;
        address creator;
        string ipfsHash;           // Off-chain idea details
        IdeaState state;
        uint256 fundingTarget;     // Minimum to raise
        uint256 fundingCap;        // Maximum to raise
        uint256 fundingStartTime;
        uint256 fundingEndTime;
        uint256 tokenMintRatio;    // Tokens per 1 USDY (e.g., 100 = 100 tokens)
        bool gatingEnabled;        // Require IdeaToken to participate
        address selectedBuilder;   // Selected builder address
        uint256 builderAllocation; // Builder's token allocation %
        uint256 totalInvestors;    // Encrypted count
        bool finalized;
    }

    struct InvestorInfo {
        uint256 ideaId;
        address investor;
        uint256 usdyDeposited;
        uint256 tokensIssued;
        bool claimed;
    }

    // ── State ─────────────────────────────────────────────────────────────────

    address public usdyToken;
    address public governance;      // GovernanceVault address
    address public treasury;       // TreasuryVault address
    
    uint256 public ideaCounter;
    
    /// @notice Ideas by ID
    mapping(uint256 => Idea) public ideas;
    
    /// @notice Encrypted deposits per idea (ideaId → encrypted total)
    mapping(uint256 => euint128) private _encryptedTotalRaised;
    
    /// @notice Encrypted deposits per investor (ideaId → investor → encrypted amount)
    mapping(uint256 => mapping(address => euint128)) private _encryptedDeposits;
    
    /// @notice Gating whitelist (ideaId → user → bool)
    mapping(uint256 => mapping(address => bool)) public gatingWhitelist;
    
    /// @notice Investor token balances (ideaId → investor → amount)
    mapping(uint256 => mapping(address => uint256)) public investorTokens;
    
    /// @notice Builder tokens (ideaId → amount)
    mapping(uint256 => uint256) public builderTokens;
    
    /// @notice Total tokens per idea
    mapping(uint256 => uint256) public totalTokensIssued;

    // ── Events ─────────────────────────────────────────────────────────────────

    event IdeaCreated(uint256 indexed ideaId, address indexed creator, string ipfsHash);
    event FundingOpened(uint256 indexed ideaId, uint256 startTime, uint256 endTime);
    event Funded(address indexed investor, uint256 indexed ideaId, uint256 amount, uint256 tokensMinted);
    event FundingClosed(uint256 indexed ideaId);
    event BuilderSelected(uint256 indexed ideaId, address indexed builder);
    event FundingLocked(uint256 indexed ideaId);
    event Operational(uint256 indexed ideaId);
    event Cancelled(uint256 indexed ideaId);

    // ── Initialization ─────────────────────────────────────────────────────────

    function initialize(
        address _usdyToken,
        address _governance,
        address _treasury,
        address _owner
    ) external initializer {
        require(_usdyToken != address(0), "Zero USDY");
        require(_governance != address(0), "Zero governance");
        require(_treasury != address(0), "Zero treasury");
        
        usdyToken = _usdyToken;
        governance = _governance;
        treasury = _treasury;
        ideaCounter = 1;
        
        _initializeOwner(_owner);
    }

    // ── Idea Management ────────────────────────────────────────────────────────

    /**
     * @notice Create a new idea with funding parameters.
     * @param ipfsHash IPFS hash containing idea details
     * @param target Minimum funding target (USDY)
     * @param cap Maximum funding cap (USDY)
     * @param fundingDuration Duration of funding window in seconds
     * @param tokenMintRatio Tokens to mint per 1 USDY
     * @param gating Whether to require IdeaToken for participation
     */
    function createIdea(
        string calldata ipfsHash,
        uint256 target,
        uint256 cap,
        uint256 fundingDuration,
        uint256 tokenMintRatio,
        bool gating
    ) external returns (uint256 ideaId) {
        ideaId = ideaCounter++;
        
        ideas[ideaId] = Idea({
            id: ideaId,
            creator: msg.sender,
            ipfsHash: ipfsHash,
            state: IdeaState.RequestOpen,
            fundingTarget: target,
            fundingCap: cap > 0 ? cap : type(uint256).max,
            fundingStartTime: 0,
            fundingEndTime: 0,
            tokenMintRatio: tokenMintRatio,
            gatingEnabled: gating,
            selectedBuilder: address(0),
            builderAllocation: 0,
            totalInvestors: 0,
            finalized: false
        });
        
        emit IdeaCreated(ideaId, msg.sender, ipfsHash);
    }

    /**
     * @notice Open the funding window for an idea.
     */
    function openFunding(uint256 ideaId, uint256 duration) external onlyOwner {
        Idea storage idea = ideas[ideaId];
        if (idea.id != ideaId) revert IdeaNotFound(ideaId);
        if (idea.state != IdeaState.RequestOpen) revert InvalidState(IdeaState.RequestOpen, idea.state);
        
        idea.state = IdeaState.FundingOpen;
        idea.fundingStartTime = block.timestamp;
        idea.fundingEndTime = block.timestamp + duration;
        
        emit FundingOpened(ideaId, idea.fundingStartTime, idea.fundingEndTime);
    }

    /**
     * @notice Fund an idea - deposit USDY, receive IdeaTokens.
     */
    function fund(uint256 ideaId, uint256 usdyAmount) external returns (uint256 tokensMinted) {
        Idea storage idea = ideas[ideaId];
        if (idea.id != ideaId) revert IdeaNotFound(ideaId);
        if (idea.state != IdeaState.FundingOpen) revert InvalidState(IdeaState.FundingOpen, idea.state);
        if (block.timestamp > idea.fundingEndTime) revert FundingExpired();
        if (usdyAmount == 0) revert ZeroAmount();
        
        // Check gating if enabled
        if (idea.gatingEnabled && !gatingWhitelist[ideaId][msg.sender]) {
            revert GatingEnabled(msg.sender);
        }
        
        // Transfer USDY from investor
        IERC20(usdyToken).safeTransferFrom(msg.sender, address(this), usdyAmount);
        
        // Calculate tokens
        tokensMinted = usdyAmount * idea.tokenMintRatio / 1e18;
        
        // Update investor info
        investorTokens[ideaId][msg.sender] += tokensMinted;
        totalTokensIssued[ideaId] += tokensMinted;
        
        // Update encrypted deposit tracking
        euint128 encryptedAmount = FHE.asEuint128(usdyAmount);
        _encryptedDeposits[ideaId][msg.sender] = FHE.add(
            _encryptedDeposits[ideaId][msg.sender],
            encryptedAmount
        );
        FHE.allowThis(_encryptedDeposits[ideaId][msg.sender]);
        
        // Update encrypted total raised
        _encryptedTotalRaised[ideaId] = FHE.add(_encryptedTotalRaised[ideaId], encryptedAmount);
        FHE.allowThis(_encryptedTotalRaised[ideaId]);
        
        emit Funded(msg.sender, ideaId, usdyAmount, tokensMinted);
    }

    /**
     * @notice Close funding window (manual or time-based).
     */
    function closeFunding(uint256 ideaId) external onlyOwner {
        Idea storage idea = ideas[ideaId];
        if (idea.id != ideaId) revert IdeaNotFound(ideaId);
        if (idea.state != IdeaState.FundingOpen) revert InvalidState(IdeaState.FundingOpen, idea.state);
        
        idea.state = IdeaState.FundingClosed;
        
        emit FundingClosed(ideaId);
    }

    /**
     * @notice Select builder for an idea (called by GovernanceVault).
     */
    function selectBuilder(uint256 ideaId, address builder, uint256 tokenAllocPct) external {
        require(msg.sender == governance, "Not governance");
        
        Idea storage idea = ideas[ideaId];
        if (idea.id != ideaId) revert IdeaNotFound(ideaId);
        if (idea.state != IdeaState.FundingClosed && idea.state != IdeaState.BuilderSelected) {
            revert InvalidState(IdeaState.FundingClosed, idea.state);
        }
        
        idea.selectedBuilder = builder;
        idea.builderAllocation = tokenAllocPct;
        idea.state = IdeaState.BuilderSelected;
        
        // Calculate builder tokens (10-30% of total)
        uint256 builderTokenAmount = totalTokensIssued[ideaId] * tokenAllocPct / 10000;
        builderTokens[ideaId] = builderTokenAmount;
        
        emit BuilderSelected(ideaId, builder);
    }

    /**
     * @notice Lock funding after builder selection finalized.
     */
    function lockFunding(uint256 ideaId) external {
        require(msg.sender == governance, "Not governance");
        
        Idea storage idea = ideas[ideaId];
        if (idea.id != ideaId) revert IdeaNotFound(ideaId);
        if (idea.state != IdeaState.BuilderSelected) {
            revert InvalidState(IdeaState.BuilderSelected, idea.state);
        }
        if (idea.selectedBuilder == address(0)) revert NoBuilderSelected();
        
        idea.state = IdeaState.Locked;
        idea.finalized = true;
        
        emit FundingLocked(ideaId);
    }

    /**
     * @notice Mark idea as operational (product live).
     */
    function markOperational(uint256 ideaId) external {
        require(msg.sender == governance || msg.sender == treasury, "Not authorized");
        
        Idea storage idea = ideas[ideaId];
        if (idea.id != ideaId) revert IdeaNotFound(ideaId);
        if (idea.state != IdeaState.Locked) revert InvalidState(IdeaState.Locked, idea.state);
        
        idea.state = IdeaState.Operational;
        
        emit Operational(ideaId);
    }

    /**
     * @notice Cancel idea (before lock).
     */
    function cancelIdea(uint256 ideaId) external onlyOwner {
        Idea storage idea = ideas[ideaId];
        if (idea.id != ideaId) revert IdeaNotFound(ideaId);
        if (idea.state == IdeaState.Locked || idea.state == IdeaState.Operational) {
            revert AlreadyFinalized();
        }
        
        idea.state = IdeaState.Cancelled;
        
        emit Cancelled(ideaId);
    }

    // ── Gating ─────────────────────────────────────────────────────────────────

    /**
     * @notice Update gating whitelist.
     */
    function updateGatingWhitelist(
        uint256 ideaId,
        address[] calldata users,
        bool status
    ) external onlyOwner {
        Idea storage idea = ideas[ideaId];
        if (idea.id != ideaId) revert IdeaNotFound(ideaId);
        
        for (uint256 i = 0; i < users.length; i++) {
            gatingWhitelist[ideaId][users[i]] = status;
        }
    }

    // ── View Functions ─────────────────────────────────────────────────────────

    function getIdea(uint256 ideaId) external view returns (Idea memory) {
        return ideas[ideaId];
    }

    function getIdeaState(uint256 ideaId) external view returns (IdeaState) {
        return ideas[ideaId].state;
    }

    function getInvestorTokens(uint256 ideaId, address investor) external view returns (uint256) {
        return investorTokens[ideaId][investor];
    }

    function getBuilderTokens(uint256 ideaId) external view returns (uint256) {
        return builderTokens[ideaId];
    }

    /**
     * @notice Get encrypted total raised (permissioned).
     */
    function getEncryptedTotalRaised(uint256 ideaId) external view returns (euint128) {
        return _encryptedTotalRaised[ideaId];
    }

    /**
     * @notice Get encrypted deposit for an investor (permissioned).
     */
    function getEncryptedDeposit(uint256 ideaId, address investor) external view returns (euint128) {
        return _encryptedDeposits[ideaId][investor];
    }

    /**
     * @notice Request to disclose deposit to a specific address.
     */
    function requestDepositDisclosure(uint256 ideaId, address recipient) external {
        euint128 deposit = _encryptedDeposits[ideaId][msg.sender];
        FHE.allow(deposit, recipient);
    }

    /**
     * @notice Request to disclose total raised to governance.
     */
    function requestTotalDisclosure(uint256 ideaId) external {
        euint128 total = _encryptedTotalRaised[ideaId];
        FHE.allow(total, governance);
    }

    /**
     * @notice Check if investor is whitelisted for gated idea.
     */
    function isWhitelisted(uint256 ideaId, address user) external view returns (bool) {
        return gatingWhitelist[ideaId][user];
    }

    /**
     * @notice Check if idea is finalized.
     */
    function isFinalized(uint256 ideaId) external view returns (bool) {
        return ideas[ideaId].finalized;
    }

    // ── Modifiers ──────────────────────────────────────────────────────────────

    modifier onlyGovernance() {
        require(msg.sender == governance, "Not governance");
        _;
    }
}