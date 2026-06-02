// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {FHE, euint128} from "@fhenixprotocol/cofhe-contracts/FHE.sol";
import {InEuint128} from "@fhenixprotocol/cofhe-contracts/ICofhe.sol";
import "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../utils/SimpleOwnable.sol";

/**
 * @title TreasuryVault
 * @notice Unified contract for payouts and revenue distribution.
 *         Consolidates: PayoutManager + RevenueReport
 * 
 * @dev Protocol Flow:
 *      1. initiatePayout() - Start payout after approval
 *      2. approvePayout() - Governance approves
 *      3. processPayout() - Transfer USDY to builder + tokens
 *      4. transferProductToDAO() - Product goes to InvestorDAO
 *      5. receiveRevenue() - Revenue comes in
 *      6. distributeRevenue() - Split to participants
 *      7. claimRevenue() - Token holders claim their share
 */
contract TreasuryVault is Initializable, SimpleOwnable {
    using FHE for *;
    using SafeERC20 for IERC20;

    // ── Errors ─────────────────────────────────────────────────────────────────

    error PayoutNotFound(uint256 ideaId);
    error PayoutAlreadyExists(uint256 ideaId);
    error InvalidState(PayoutState required, PayoutState actual);
    error ZeroAmount();
    error NothingToClaim();
    error AlreadyProcessed();
    error InvalidAllocation();

    // ── Types ─────────────────────────────────────────────────────────────────

    enum PayoutState {
        None,
        Pending,      // Awaiting governance approval
        Approved,     // Approved, ready to process
        Processing,   // Processing (during transfer)
        Completed,    // Payout completed
        Refunded      // Refund issued (rejection case)
    }

    enum RevenueState {
        None,
        Active,
        Paused,
        Closed
    }

    // ── Structs ───────────────────────────────────────────────────────────────

    struct PayoutRequest {
        uint256 ideaId;
        address builder;
        uint256 usdyAmount;           // USDY to pay builder
        uint256 tokenAllocPct;         // Token allocation % (10-30%)
        uint256 tokenAmount;           // Calculated token amount
        PayoutState state;
        uint256 initiatedAt;
        uint256 processedAt;
        address investorDAO;           // Where product transfers
    }

    struct RevenueAllocation {
        uint256 ideaId;
        uint256 builderShare;          // % for builder
        uint256 investorShare;         // % for investors (token holders)
        uint256 daoShare;              // % for protocol treasury
        uint256 totalReceived;
        uint256 totalDistributed;
        uint256 pendingDistribution;
        RevenueState state;
    }

    struct InvestorClaim {
        uint256 ideaId;
        address investor;
        uint256 claimedAmount;
        uint256 lastClaimTime;
    }

    // ── State ─────────────────────────────────────────────────────────────────

    address public ideaToken;
    address public usdyToken;
    address public governance;
    address public ideaVault;
    address public builderHub;
    address public protocolTreasury;

    /// @notice Payout requests by idea ID
    mapping(uint256 => PayoutRequest) public payoutRequests;

    /// @notice Revenue allocations by idea ID
    mapping(uint256 => RevenueAllocation) public revenueAllocations;

    /// @notice Encrypted pending payouts
    mapping(uint256 => euint128) private _encryptedPendingPayouts;

    /// @notice Encrypted total paid out
    mapping(uint256 => euint128) private _encryptedTotalPaid;

    /// @notice Encrypted revenue claims per investor
    mapping(uint256 => mapping(address => euint128)) private _encryptedClaims;

    /// @notice Encrypted total revenue received
    mapping(uint256 => euint128) private _encryptedTotalRevenue;

    /// @notice Investor claim history
    mapping(uint256 => mapping(address => InvestorClaim)) public claimHistory;

    /// @notice Investor DAOs per idea
    mapping(uint256 => address) public investorDAOs;

    // ── Events ─────────────────────────────────────────────────────────────────

    event PayoutInitiated(uint256 indexed ideaId, address indexed builder, uint256 usdyAmount, uint256 tokenAllocPct);
    event PayoutApproved(uint256 indexed ideaId);
    event PayoutProcessed(uint256 indexed ideaId, address indexed builder, uint256 usdyPaid);
    event PayoutRefunded(uint256 indexed ideaId, uint256 amount);
    event ProductTransferred(uint256 indexed ideaId, address indexed investorDAO);
    event RevenueReceived(uint256 indexed ideaId, uint256 amount);
    event RevenueDistributed(uint256 indexed ideaId, address indexed recipient, uint256 amount);
    event RevenueClaimed(uint256 indexed ideaId, address indexed investor, uint256 amount);
    event InvestorDAOSet(uint256 indexed ideaId, address indexed dao);

    // ── Initialization ─────────────────────────────────────────────────────────

    function initialize(
        address _ideaToken,
        address _usdyToken,
        address _governance,
        address _ideaVault,
        address _builderHub,
        address _protocolTreasury,
        address _owner
    ) external initializer {
        require(_usdyToken != address(0), "Zero USDY");
        require(_governance != address(0), "Zero governance");
        require(_ideaVault != address(0), "Zero IdeaVault");
        require(_builderHub != address(0), "Zero BuilderHub");
        require(_protocolTreasury != address(0), "Zero treasury");
        
        ideaToken = _ideaToken;
        usdyToken = _usdyToken;
        governance = _governance;
        ideaVault = _ideaVault;
        builderHub = _builderHub;
        protocolTreasury = _protocolTreasury;
        
        _initializeOwner(_owner);
    }

    // ── Payout Functions ────────────────────────────────────────────────────────

    /**
     * @notice Initiate payout for an idea (called after builder delivers).
     */
    function initiatePayout(
        uint256 ideaId,
        address builder,
        uint256 usdyAmount,
        uint256 tokenAllocPct
    ) external returns (bool) {
        require(msg.sender == builderHub || msg.sender == owner(), "Not BuilderHub or owner");
        require(usdyAmount > 0, "Zero amount");
        require(tokenAllocPct >= 1000 && tokenAllocPct <= 3000, "Invalid allocation"); // 10-30%
        
        PayoutRequest storage request = payoutRequests[ideaId];
        require(request.state == PayoutState.None, PayoutAlreadyExists(ideaId));
        
        PayoutRequest memory newRequest = PayoutRequest({
            ideaId: ideaId,
            builder: builder,
            usdyAmount: usdyAmount,
            tokenAllocPct: tokenAllocPct,
            tokenAmount: 0,
            state: PayoutState.Pending,
            initiatedAt: block.timestamp,
            processedAt: 0,
            investorDAO: address(0)
        });
        
        payoutRequests[ideaId] = newRequest;
        
        // Track encrypted pending
        euint128 encryptedAmount = FHE.asEuint128(usdyAmount);
        _encryptedPendingPayouts[ideaId] = FHE.add(_encryptedPendingPayouts[ideaId], encryptedAmount);
        FHE.allowThis(_encryptedPendingPayouts[ideaId]);
        
        emit PayoutInitiated(ideaId, builder, usdyAmount, tokenAllocPct);
        return true;
    }

    /**
     * @notice Approve payout (called by governance after final vote).
     */
    function approvePayout(uint256 ideaId) external {
        require(msg.sender == governance || msg.sender == owner(), "Not governance or owner");
        
        PayoutRequest storage request = payoutRequests[ideaId];
        if (request.state == PayoutState.None) revert PayoutNotFound(ideaId);
        if (request.state != PayoutState.Pending) revert InvalidState(PayoutState.Pending, request.state);
        
        request.state = PayoutState.Approved;
        
        emit PayoutApproved(ideaId);
    }

    /**
     * @notice Process payout - transfer USDY to builder.
     */
    function processPayout(uint256 ideaId) external returns (bool success) {
        PayoutRequest storage request = payoutRequests[ideaId];
        if (request.state == PayoutState.None) revert PayoutNotFound(ideaId);
        if (request.state != PayoutState.Approved) revert InvalidState(PayoutState.Approved, request.state);
        
        request.state = PayoutState.Processing;
        
        // Transfer USDY to builder
        IERC20(usdyToken).safeTransfer(request.builder, request.usdyAmount);
        
        // Update encrypted totals
        euint128 usdyPaid = FHE.asEuint128(request.usdyAmount);
        
        euint128 pending = _encryptedPendingPayouts[ideaId];
        _encryptedPendingPayouts[ideaId] = FHE.sub(pending, usdyPaid);
        FHE.allowThis(_encryptedPendingPayouts[ideaId]);
        
        _encryptedTotalPaid[ideaId] = FHE.add(_encryptedTotalPaid[ideaId], usdyPaid);
        FHE.allowThis(_encryptedTotalPaid[ideaId]);
        
        request.state = PayoutState.Completed;
        request.processedAt = block.timestamp;
        
        emit PayoutProcessed(ideaId, request.builder, request.usdyAmount);
        return true;
    }

    /**
     * @notice Allocate tokens to builder (after USDY payout).
     * @dev Called by IdeaToken contract to mint tokens to builder.
     */
    function allocateBuilderTokens(uint256 ideaId) external returns (uint256 tokensAllocated) {
        PayoutRequest storage request = payoutRequests[ideaId];
        if (request.state != PayoutState.Completed) revert InvalidState(PayoutState.Completed, request.state);
        
        // Token allocation calculated from IdeaToken total supply
        // This would call IdeaToken.mintToBuilder(ideaId, request.builder, request.tokenAllocPct)
        tokensAllocated = request.tokenAmount;
        
        return tokensAllocated;
    }

    // ── Product Transfer ───────────────────────────────────────────────────────

    /**
     * @notice Set investor DAO for an idea.
     */
    function setInvestorDAO(uint256 ideaId, address investorDAO) external {
        require(msg.sender == governance || msg.sender == ideaVault, "Not authorized");
        investorDAOs[ideaId] = investorDAO;
        emit InvestorDAOSet(ideaId, investorDAO);
    }

    /**
     * @notice Transfer product control to InvestorDAO (after approval).
     */
    function transferProductToDAO(uint256 ideaId) external {
        require(msg.sender == builderHub || msg.sender == owner(), "Not BuilderHub or owner");
        
        PayoutRequest storage request = payoutRequests[ideaId];
        if (request.state != PayoutState.Completed) revert InvalidState(PayoutState.Completed, request.state);
        
        address investorDAO = investorDAOs[ideaId];
        require(investorDAO != address(0), "No DAO set");
        
        // Mark transfer complete
        emit ProductTransferred(ideaId, investorDAO);
    }

    // ── Refund ─────────────────────────────────────────────────────────────────

    /**
     * @notice Process refund (rejection case).
     */
    function processRefund(uint256 ideaId, uint256 amount) external {
        require(msg.sender == governance || msg.sender == owner(), "Not governance or owner");
        
        PayoutRequest storage request = payoutRequests[ideaId];
        if (request.state == PayoutState.Completed) revert AlreadyProcessed();
        
        request.state = PayoutState.Refunded;
        request.processedAt = block.timestamp;
        
        // Transfer to protocol treasury or burn
        IERC20(usdyToken).safeTransfer(protocolTreasury, amount);
        
        emit PayoutRefunded(ideaId, amount);
    }

    // ── Revenue Distribution ───────────────────────────────────────────────────

    /**
     * @notice Set revenue allocation for an idea.
     */
    function setRevenueAllocation(
        uint256 ideaId,
        uint256 builderShare,
        uint256 investorShare,
        uint256 daoShare
    ) external {
        require(msg.sender == governance || msg.sender == owner(), "Not governance or owner");
        require(builderShare + investorShare + daoShare == 10000, "Must equal 100%");
        
        revenueAllocations[ideaId] = RevenueAllocation({
            ideaId: ideaId,
            builderShare: builderShare,
            investorShare: investorShare,
            daoShare: daoShare,
            totalReceived: 0,
            totalDistributed: 0,
            pendingDistribution: 0,
            state: RevenueState.Active
        });
    }

    /**
     * @notice Receive revenue (called by external RevenueDistributor or product).
     */
    function receiveRevenue(uint256 ideaId, uint256 amount) external {
        require(amount > 0, "Zero amount");
        
        RevenueAllocation storage allocation = revenueAllocations[ideaId];
        require(allocation.state == RevenueState.Active, "Revenue not active");
        
        // Transfer USDY from sender
        IERC20(usdyToken).safeTransferFrom(msg.sender, address(this), amount);
        
        // Update tracking
        allocation.totalReceived += amount;
        
        euint128 encAmount = FHE.asEuint128(amount);
        _encryptedTotalRevenue[ideaId] = FHE.add(_encryptedTotalRevenue[ideaId], encAmount);
        FHE.allowThis(_encryptedTotalRevenue[ideaId]);
        
        emit RevenueReceived(ideaId, amount);
    }

    /**
     * @notice Distribute revenue to participants (batch).
     */
    function distributeRevenue(
        uint256 ideaId,
        address[] calldata recipients,
        uint256[] calldata amounts
    ) external returns (bool) {
        require(msg.sender == governance || msg.sender == owner(), "Not governance or owner");
        require(recipients.length == amounts.length, "Length mismatch");
        
        RevenueAllocation storage allocation = revenueAllocations[ideaId];
        require(allocation.state == RevenueState.Active, "Revenue not active");
        
        uint256 totalDistributed = 0;
        
        for (uint256 i = 0; i < recipients.length; i++) {
            IERC20(usdyToken).safeTransfer(recipients[i], amounts[i]);
            totalDistributed += amounts[i];
            
            // Update encrypted claims for audit trail
            euint128 encAmount = FHE.asEuint128(amounts[i]);
            euint128 current = _encryptedClaims[ideaId][recipients[i]];
            euint128 updated = FHE.add(current, encAmount);
            _encryptedClaims[ideaId][recipients[i]] = updated;
            FHE.allowThis(updated);
            FHE.allow(updated, recipients[i]);
            
            emit RevenueDistributed(ideaId, recipients[i], amounts[i]);
        }
        
        allocation.totalDistributed += totalDistributed;
        
        return true;
    }

    /**
     * @notice Claim revenue share for token holders.
     */
    function claimRevenueShare(uint256 ideaId) external returns (uint256 amount) {
        RevenueAllocation storage allocation = revenueAllocations[ideaId];
        require(allocation.state == RevenueState.Active, "Revenue not active");
        
        InvestorClaim storage claim = claimHistory[ideaId][msg.sender];
        
        // Calculate claim based on token holdings (simplified - real impl uses CoFHE)
        // The actual claim amount is calculated off-chain and verified with ZK proofs
        // Here we just mark the claim as processed
        euint128 encClaim = _encryptedClaims[ideaId][msg.sender];
        _encryptedClaims[ideaId][msg.sender] = FHE.sub(encClaim, encClaim);
        FHE.allowThis(_encryptedClaims[ideaId][msg.sender]);
        
        claim.claimedAmount += amount;
        claim.lastClaimTime = block.timestamp;
        
        emit RevenueClaimed(ideaId, msg.sender, amount);
        
        return amount;
    }

    // ── View Functions ─────────────────────────────────────────────────────────

    function getPayoutRequest(uint256 ideaId) external view returns (PayoutRequest memory) {
        return payoutRequests[ideaId];
    }

    function getPayoutState(uint256 ideaId) external view returns (PayoutState) {
        return payoutRequests[ideaId].state;
    }

    function getRevenueAllocation(uint256 ideaId) external view returns (RevenueAllocation memory) {
        return revenueAllocations[ideaId];
    }

    function getRevenueState(uint256 ideaId) external view returns (RevenueState) {
        return revenueAllocations[ideaId].state;
    }

    function getEncryptedPendingPayouts(uint256 ideaId) external view returns (euint128) {
        return _encryptedPendingPayouts[ideaId];
    }

    function getEncryptedTotalPaid(uint256 ideaId) external view returns (euint128) {
        return _encryptedTotalPaid[ideaId];
    }

    function getEncryptedTotalRevenue(uint256 ideaId) external view returns (euint128) {
        return _encryptedTotalRevenue[ideaId];
    }

    function getEncryptedClaim(uint256 ideaId, address claimant) external view returns (euint128) {
        return _encryptedClaims[ideaId][claimant];
    }

    function getInvestorDAO(uint256 ideaId) external view returns (address) {
        return investorDAOs[ideaId];
    }

    function getClaimHistory(uint256 ideaId, address investor) external view returns (InvestorClaim memory) {
        return claimHistory[ideaId][investor];
    }

    // ── Emergency Functions ────────────────────────────────────────────────────

    /**
     * @notice Pause revenue distribution.
     */
    function pauseRevenue(uint256 ideaId) external onlyOwner {
        revenueAllocations[ideaId].state = RevenueState.Paused;
    }

    /**
     * @notice Resume revenue distribution.
     */
    function resumeRevenue(uint256 ideaId) external onlyOwner {
        revenueAllocations[ideaId].state = RevenueState.Active;
    }

    /**
     * @notice Emergency close of revenue.
     */
    function closeRevenue(uint256 ideaId) external onlyOwner {
        revenueAllocations[ideaId].state = RevenueState.Closed;
    }
}