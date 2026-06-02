// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {FHE, euint128, ebool} from "@fhenixprotocol/cofhe-contracts/FHE.sol";
import {InEuint128} from "@fhenixprotocol/cofhe-contracts/ICofhe.sol";
import "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title PayoutManager
 * @notice Handles USDY payouts to builders and token allocations after approval.
 *         Part of VenturesSea protocol - executes the final stage of milestone funding.
 * 
 * @dev Flow:
 *      DAO approves final MVP → PayoutManager releases funds → 
 *      Builder receives USDY + IdeaToken allocation → Product transfers to InvestorDAO
 * 
 * @dev Privacy Features:
 *      - Payout amounts can be encrypted until release
 *      - Token allocations tracked privately
 */
contract PayoutManager is Initializable {
    using FHE for *;
    using SafeERC20 for IERC20;

    // ── Types ─────────────────────────────────────────────────────────────────

    enum PayoutState {
        Pending,      // Waiting for DAO approval
        Approved,     // DAO approved final MVP
        Processing,   // Payout in progress
        Completed,    // Payout completed
        Refunded,     // Full refund issued (rejection case)
        Disputed      // Under dispute resolution
    }

    struct PayoutRequest {
        uint256 ideaId;
        address builder;
        uint256 usdyAmount;           // USDY to pay builder
        uint256 tokenAllocPercent;     // Token allocation % (e.g., 1500 = 15%)
        uint256 tokenAmount;           // Calculated token amount
        uint256 daoRevenueShare;       // DAO's share of revenue
        PayoutState state;
        uint256 requestedAt;
        uint256 processedAt;
    }

    struct RevenueAllocation {
        uint256 ideaId;
        uint256 totalRevenue;          // Encrypted total
        uint256 builderShare;          // % for builder
        uint256 investorShare;         // % for investors
        uint256 daoShare;              // % for protocol
        uint256 distributed;           // Amount distributed
        bool active;
    }

    // ── State ─────────────────────────────────────────────────────────────────

    address public registry;
    address public usdyToken;
    address public ideaToken;
    address public treasury;

    /// @notice Payout requests (ideaId → PayoutRequest)
    mapping(uint256 => PayoutRequest) public payoutRequests;
    
    /// @notice Revenue allocations (ideaId → RevenueAllocation)
    mapping(uint256 => RevenueAllocation) public revenueAllocations;
    
    /// @notice Encrypted total payouts per idea
    mapping(uint256 => euint128) private _encryptedTotalPayouts;
    
    /// @notice Encrypted pending payouts
    mapping(uint256 => euint128) private _encryptedPendingPayouts;
    
    /// @notice DAO revenue per idea (encrypted)
    mapping(uint256 => euint128) private _encryptedDaoRevenue;
    
    /// @notice Investor claims per idea (address → encrypted)
    mapping(uint256 => mapping(address => euint128)) private _encryptedClaims;

    // ── Events ─────────────────────────────────────────────────────────────────

    event PayoutRequested(uint256 indexed ideaId, address indexed builder, uint256 usdyAmount);
    event PayoutApproved(uint256 indexed ideaId);
    event PayoutProcessed(uint256 indexed ideaId, address indexed builder, uint256 usdyPaid, uint256 tokensAllocated);
    event RefundIssued(uint256 indexed ideaId, uint256 amount);
    event RevenueReceived(uint256 indexed ideaId, uint256 amount);
    event RevenueDistributed(uint256 indexed ideaId, address indexed recipient, uint256 amount);
    event ProductTransferred(uint256 indexed ideaId, address indexed newController);
    event TokenAllocationUpdated(uint256 indexed ideaId, uint256 percent);

    // ── Errors ─────────────────────────────────────────────────────────────────

    error PayoutAlreadyExists(uint256 ideaId);
    error PayoutNotFound(uint256 ideaId);
    error InvalidState(PayoutState required, PayoutState actual);
    error InvalidAllocation();
    error TransferFailed(address to, uint256 amount);
    error ZeroAddress();
    error AlreadyProcessed(uint256 ideaId);

    // ── Initialization ─────────────────────────────────────────────────────────

    function initialize(
        address _registry,
        address _usdyToken,
        address _ideaToken,
        address _treasury
    ) external initializer {
        require(_registry != address(0), "Zero registry");
        require(_usdyToken != address(0), "Zero USDY");
        require(_ideaToken != address(0), "Zero IdeaToken");
        require(_treasury != address(0), "Zero treasury");
        
        registry = _registry;
        usdyToken = _usdyToken;
        ideaToken = _ideaToken;
        treasury = _treasury;
    }

    // ── Payout Request Functions ────────────────────────────────────────────────

    /**
     * @notice Request payout for an idea (called after final DAO approval).
     */
    function requestPayout(
        uint256 ideaId,
        address builder,
        uint256 usdyAmount,
        uint256 tokenAllocPercent
    ) external returns (uint256 requestId) {
        require(msg.sender == registry, "Not registry");
        require(payoutRequests[ideaId].state == PayoutState.Pending || 
                payoutRequests[ideaId].state == PayoutState(0), "Payout exists");
        require(builder != address(0), "Zero builder");
        require(usdyAmount > 0, "Zero amount");
        require(tokenAllocPercent <= 3000, "Invalid token %"); // Max 30%
        
        // Calculate token amount based on total supply
        uint256 tokenAmount = calculateTokenAllocation(ideaId, tokenAllocPercent);
        
        payoutRequests[ideaId] = PayoutRequest({
            ideaId: ideaId,
            builder: builder,
            usdyAmount: usdyAmount,
            tokenAllocPercent: tokenAllocPercent,
            tokenAmount: tokenAmount,
            daoRevenueShare: 0,
            state: PayoutState.Pending,
            requestedAt: block.timestamp,
            processedAt: 0
        });
        
        // Track encrypted pending
        _encryptedPendingPayouts[ideaId] = FHE.asEuint128(usdyAmount);
        FHE.allowThis(_encryptedPendingPayouts[ideaId]);
        
        emit PayoutRequested(ideaId, builder, usdyAmount);
        emit TokenAllocationUpdated(ideaId, tokenAllocPercent);
        
        return ideaId;
    }

    /**
     * @notice Approve payout (called after final MVP approval vote).
     */
    function approvePayout(uint256 ideaId) external {
        require(msg.sender == registry, "Not registry");
        require(payoutRequests[ideaId].state == PayoutState.Pending, "Not pending");
        
        payoutRequests[ideaId].state = PayoutState.Approved;
        
        emit PayoutApproved(ideaId);
    }

    /**
     * @notice Process payout - transfer USDY and allocate tokens.
     */
    function processPayout(uint256 ideaId) external returns (bool success) {
        PayoutRequest storage request = payoutRequests[ideaId];
        require(request.state == PayoutState.Approved, "Not approved");
        
        request.state = PayoutState.Processing;
        
        // Transfer USDY to builder
        IERC20(usdyToken).safeTransfer(request.builder, request.usdyAmount);
        
        // Update encrypted totals
        euint128 usdyPaid = FHE.asEuint128(request.usdyAmount);
        _encryptedTotalPayouts[ideaId] = FHE.add(_encryptedTotalPayouts[ideaId], usdyPaid);
        FHE.allowThis(_encryptedTotalPayouts[ideaId]);
        
        // Clear pending
        euint128 pending = _encryptedPendingPayouts[ideaId];
        _encryptedPendingPayouts[ideaId] = FHE.sub(pending, usdyPaid);
        FHE.allowThis(_encryptedPendingPayouts[ideaId]);
        
        request.state = PayoutState.Completed;
        request.processedAt = block.timestamp;
        
        emit PayoutProcessed(
            ideaId, 
            request.builder, 
            request.usdyAmount, 
            request.tokenAmount
        );
        
        return true;
    }

    /**
     * @notice Allocate tokens to builder after USDY payout.
     * @dev Tokens are minted to builder from reserves.
     */
    function allocateTokens(uint256 ideaId) external returns (uint256 tokensAllocated) {
        PayoutRequest storage request = payoutRequests[ideaId];
        require(request.state == PayoutState.Completed, "Payout not completed");
        require(request.tokenAmount > 0, "No tokens to allocate");
        
        uint256 tokens = request.tokenAmount;
        request.tokenAmount = 0; // Prevent double allocation
        
        // Token transfer would go through IdeaToken contract
        // emit TokenAllocated(ideaId, request.builder, tokens);
        
        return tokens;
    }

    /**
     * @notice Transfer product control to InvestorDAO.
     */
    function transferProductToDAO(uint256 ideaId, address investorDAO) external {
        require(msg.sender == registry, "Not registry");
        require(payoutRequests[ideaId].state == PayoutState.Completed, "Payout incomplete");
        require(investorDAO != address(0), "Zero DAO");
        
        emit ProductTransferred(ideaId, investorDAO);
    }

    // ── Refund Functions ────────────────────────────────────────────────────────

    /**
     * @notice Issue full refund (pre-lock rejection case).
     */
    function processRefund(uint256 ideaId, uint256 amount) external {
        require(msg.sender == registry, "Not registry");
        
        PayoutRequest storage request = payoutRequests[ideaId];
        require(request.state != PayoutState.Refunded, "Already refunded");
        require(request.state != PayoutState.Completed, "Already paid");
        
        request.state = PayoutState.Refunded;
        request.processedAt = block.timestamp;
        
        // Transfer to treasury or burn
        IERC20(usdyToken).safeTransfer(treasury, amount);
        
        emit RefundIssued(ideaId, amount);
    }

    // ── Revenue Functions ──────────────────────────────────────────────────────

    /**
     * @notice Set revenue allocation for an idea.
     */
    function setRevenueAllocation(
        uint256 ideaId,
        uint256 builderShare,
        uint256 investorShare,
        uint256 daoShare
    ) external {
        require(msg.sender == registry, "Not registry");
        require(builderShare + investorShare + daoShare == 10000, "Must equal 100%");
        
        revenueAllocations[ideaId] = RevenueAllocation({
            ideaId: ideaId,
            totalRevenue: 0,
            builderShare: builderShare,
            investorShare: investorShare,
            daoShare: daoShare,
            distributed: 0,
            active: true
        });
    }

    /**
     * @notice Receive revenue (called by RevenueDistributor).
     */
    function receiveRevenue(uint256 ideaId, uint256 amount) external {
        require(msg.sender == registry, "Not registry");
        require(revenueAllocations[ideaId].active, "No allocation");
        
        IERC20(usdyToken).safeTransferFrom(msg.sender, address(this), amount);
        
        // Update encrypted total
        euint128 encAmount = FHE.asEuint128(amount);
        revenueAllocations[ideaId].totalRevenue += amount;
        _encryptedDaoRevenue[ideaId] = FHE.add(
            _encryptedDaoRevenue[ideaId], 
            FHE.div(encAmount, FHE.asEuint128(10000))
        );
        FHE.allowThis(_encryptedDaoRevenue[ideaId]);
        
        emit RevenueReceived(ideaId, amount);
    }

    /**
     * @notice Distribute revenue to participants.
     */
    function distributeRevenue(
        uint256 ideaId, 
        address[] calldata recipients, 
        uint256[] calldata amounts
    ) external returns (bool) {
        require(msg.sender == registry, "Not registry");
        require(recipients.length == amounts.length, "Length mismatch");
        
        RevenueAllocation storage allocation = revenueAllocations[ideaId];
        require(allocation.active, "No allocation");
        
        uint256 totalDistributed = 0;
        
        for (uint256 i = 0; i < recipients.length; i++) {
            IERC20(usdyToken).safeTransfer(recipients[i], amounts[i]);
            totalDistributed += amounts[i];
            
            // Update encrypted claim for this recipient
            euint128 encAmount = FHE.asEuint128(amounts[i]);
            euint128 currentClaim = _encryptedClaims[ideaId][recipients[i]];
            euint128 newClaim = FHE.add(currentClaim, encAmount);
            _encryptedClaims[ideaId][recipients[i]] = newClaim;
            FHE.allowThis(newClaim);
            FHE.allow(newClaim, recipients[i]);
            
            emit RevenueDistributed(ideaId, recipients[i], amounts[i]);
        }
        
        allocation.distributed += totalDistributed;
        return true;
    }

    /**
     * @notice Claim revenue share for token holders.
     * @dev Claims are encrypted - verification happens via CoFHE SDK off-chain.
     */
    function claimRevenueShare(uint256 ideaId) external returns (uint256 amount) {
        require(revenueAllocations[ideaId].active, "No allocation");
        
        // Encrypted claim - client must prove ownership via CoFHE
        // This function marks the claim as processed
        euint128 claim = _encryptedClaims[ideaId][msg.sender];
        _encryptedClaims[ideaId][msg.sender] = FHE.sub(
            _encryptedClaims[ideaId][msg.sender],
            claim
        );
        FHE.allowThis(_encryptedClaims[ideaId][msg.sender]);
        
        // Note: Actual amount must be verified off-chain
        // Return 0 as placeholder - real implementation uses ZK proofs
        return 0;
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

    function getEncryptedTotalPayouts(uint256 ideaId) external view returns (euint128) {
        return _encryptedTotalPayouts[ideaId];
    }

    function getEncryptedPendingPayouts(uint256 ideaId) external view returns (euint128) {
        return _encryptedPendingPayouts[ideaId];
    }

    function getEncryptedDaoRevenue(uint256 ideaId) external view returns (euint128) {
        return _encryptedDaoRevenue[ideaId];
    }

    function getEncryptedClaim(uint256 ideaId, address claimant) external view returns (euint128) {
        return _encryptedClaims[ideaId][claimant];
    }

    // ── Internal Functions ─────────────────────────────────────────────────────

    function calculateTokenAllocation(uint256 ideaId, uint256 percent) internal view returns (uint256) {
        // This would get total supply from IdeaToken contract
        // For now, return placeholder
        return percent * 1e18; // Simplified calculation
    }
}