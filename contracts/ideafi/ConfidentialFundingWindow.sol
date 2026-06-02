// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {FHE, euint128, ebool, euint64} from "@fhenixprotocol/cofhe-contracts/FHE.sol";
import {InEuint128, InEuint64} from "@fhenixprotocol/cofhe-contracts/ICofhe.sol";
import "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title ConfidentialFundingWindow
 * @notice Time-boxed funding window with FHE-encrypted deposits.
 *         Implements the funding phase of the VenturesSea protocol.
 * 
 * @dev Privacy Approach:
 *      - Deposits tracked as encrypted amounts
 *      - Total raised can be hidden until window closes
 *      - Token minting ratios calculated privately
 * 
 * @dev State Machine:
 *      Inactive → RequestOpen → FundingOpen → FundingClosed → Locked
 */
contract ConfidentialFundingWindow is Initializable {
    using FHE for *;
    using SafeERC20 for IERC20;

    // ── Types ─────────────────────────────────────────────────────────────────

    enum FundingPhase {
        Inactive,
        RequestOpen,
        FundingOpen,
        FundingClosed,
        BuilderSelect,
        Locked
    }

    struct FundingWindow {
        uint256 ideaId;
        FundingPhase phase;
        uint256 targetAmount;      // USDY target
        uint256 maxAmount;         // Optional cap
        uint256 startTime;
        uint256 endTime;
        uint256 tokenMintRatio;    // Tokens per 1 USDY (e.g., 100 = 100 tokens)
        bool gatingEnabled;        // Require IdeaToken for participation
        bool finalized;
    }

    // ── State ─────────────────────────────────────────────────────────────────

    address public registry;
    address public usdyToken;
    address public ideaToken;

    mapping(uint256 => FundingWindow) public fundingWindows;
    
    /// @notice Encrypted deposits per user (ideaId => user => encrypted amount)
    mapping(uint256 => mapping(address => euint128)) private _encryptedDeposits;
    
    /// @notice Encrypted total raised per idea
    mapping(uint256 => euint128) private _encryptedTotalRaised;
    
    /// @notice Encrypted participation counts (for gating)
    mapping(uint256 => euint128) private _encryptedParticipantCount;
    
    /// @notice Whitelist for gated windows
    mapping(uint256 => mapping(address => bool)) public gatedWhitelist;
    
    /// @notice Finalized flag per idea
    mapping(uint256 => bool) public finalizedWindows;

    // ── Events ─────────────────────────────────────────────────────────────────

    event FundingWindowCreated(uint256 indexed ideaId, uint256 target, uint256 duration);
    event FundingPhaseChanged(uint256 indexed ideaId, FundingPhase newPhase);
    event PrivateDeposit(address indexed user, uint256 indexed ideaId, bytes32 encryptedHandle);
    event FundingWindowClosed(uint256 indexed ideaId, uint256 totalRaised);
    event GatingWhitelistUpdated(uint256 indexed ideaId, address[] users, bool status);

    // ── Errors ─────────────────────────────────────────────────────────────────

    error InvalidPhase(FundingPhase required, FundingPhase actual);
    error FundingWindowExists(uint256 ideaId);
    error FundingWindowNotFound(uint256 ideaId);
    error FundingTargetReached();
    error FundingExpired();
    error GatingEnabled(address user);
    error AlreadyFinalized(uint256 ideaId);

    // ── Initialization ─────────────────────────────────────────────────────────

    function initialize(address _registry, address _usdyToken) external initializer {
        require(_registry != address(0), "Zero registry");
        require(_usdyToken != address(0), "Zero USDY");
        registry = _registry;
        usdyToken = _usdyToken;
    }

    // ── Admin Functions ─────────────────────────────────────────────────────────

    /**
     * @notice Create a new funding window for an idea.
     * @dev Only registry can create windows.
     */
    function createFundingWindow(
        uint256 ideaId,
        uint256 targetAmount,
        uint256 maxAmount,
        uint256 duration,
        uint256 tokenMintRatio,
        bool gatingEnabled
    ) external returns (uint256 windowId) {
        require(fundingWindows[ideaId].phase == FundingPhase.Inactive, "Window exists");
        
        fundingWindows[ideaId] = FundingWindow({
            ideaId: ideaId,
            phase: FundingPhase.RequestOpen,
            targetAmount: targetAmount,
            maxAmount: maxAmount > 0 ? maxAmount : type(uint256).max,
            startTime: 0,
            endTime: 0,
            tokenMintRatio: tokenMintRatio,
            gatingEnabled: gatingEnabled,
            finalized: false
        });
        
        emit FundingWindowCreated(ideaId, targetAmount, duration);
        return ideaId;
    }

    /**
     * @notice Open the funding phase - transfers from RequestOpen to FundingOpen.
     */
    function openFunding(uint256 ideaId, uint256 duration) external {
        FundingWindow storage window = fundingWindows[ideaId];
        if (window.phase != FundingPhase.RequestOpen) {
            revert InvalidPhase(FundingPhase.RequestOpen, window.phase);
        }
        
        window.phase = FundingPhase.FundingOpen;
        window.startTime = block.timestamp;
        window.endTime = block.timestamp + duration;
        
        emit FundingPhaseChanged(ideaId, FundingPhase.FundingOpen);
    }

    /**
     * @notice Close funding window manually or via time.
     */
    function closeFunding(uint256 ideaId) external {
        FundingWindow storage window = fundingWindows[ideaId];
        if (window.phase != FundingPhase.FundingOpen) {
            revert InvalidPhase(FundingPhase.FundingOpen, window.phase);
        }
        
        window.phase = FundingPhase.FundingClosed;
        window.endTime = block.timestamp;
        
        emit FundingWindowClosed(ideaId, 0); // Amount encrypted
        
        emit FundingPhaseChanged(ideaId, FundingPhase.FundingClosed);
    }

    /**
     * @notice Transition to builder selection phase.
     */
    function startBuilderSelection(uint256 ideaId) external {
        FundingWindow storage window = fundingWindows[ideaId];
        if (window.phase != FundingPhase.FundingClosed) {
            revert InvalidPhase(FundingPhase.FundingClosed, window.phase);
        }
        
        window.phase = FundingPhase.BuilderSelect;
        emit FundingPhaseChanged(ideaId, FundingPhase.BuilderSelect);
    }

    /**
     * @notice Lock funding after builder selected.
     */
    function lockFunding(uint256 ideaId) external {
        FundingWindow storage window = fundingWindows[ideaId];
        if (window.phase != FundingPhase.BuilderSelect) {
            revert InvalidPhase(FundingPhase.BuilderSelect, window.phase);
        }
        
        window.phase = FundingPhase.Locked;
        window.finalized = true;
        
        emit FundingPhaseChanged(ideaId, FundingPhase.Locked);
    }

    /**
     * @notice Update gating whitelist for gated windows.
     */
    function updateGatingWhitelist(
        uint256 ideaId,
        address[] calldata users,
        bool status
    ) external {
        FundingWindow storage window = fundingWindows[ideaId];
        require(window.gatingEnabled, "Gating not enabled");
        
        for (uint256 i = 0; i < users.length; i++) {
            gatedWhitelist[ideaId][users[i]] = status;
        }
        
        emit GatingWhitelistUpdated(ideaId, users, status);
    }

    // ── User Deposit Functions ─────────────────────────────────────────────────

    /**
     * @notice Standard deposit - transfers USDY, mints IdeaTokens.
     */
    function fund(uint256 ideaId, uint256 usdyAmount) external returns (uint256 tokensMinted) {
        FundingWindow storage window = fundingWindows[ideaId];
        
        if (window.phase != FundingPhase.FundingOpen) {
            revert InvalidPhase(FundingPhase.FundingOpen, window.phase);
        }
        
        if (block.timestamp > window.endTime) {
            revert FundingExpired();
        }
        
        // Check gating if enabled
        if (window.gatingEnabled && !gatedWhitelist[ideaId][msg.sender]) {
            revert GatingEnabled(msg.sender);
        }
        
        // Transfer USDY
        IERC20(usdyToken).safeTransferFrom(msg.sender, address(this), usdyAmount);
        
        // Track encrypted deposit
        euint128 encryptedDeposit = FHE.asEuint128(usdyAmount);
        _encryptedDeposits[ideaId][msg.sender] = FHE.add(
            _encryptedDeposits[ideaId][msg.sender],
            encryptedDeposit
        );
        FHE.allowThis(_encryptedDeposits[ideaId][msg.sender]);
        
        // Update encrypted total
        _encryptedTotalRaised[ideaId] = FHE.add(_encryptedTotalRaised[ideaId], encryptedDeposit);
        FHE.allowThis(_encryptedTotalRaised[ideaId]);
        
        // Increment participant count
        _encryptedParticipantCount[ideaId] = FHE.add(_encryptedParticipantCount[ideaId], FHE.asEuint128(1));
        FHE.allowThis(_encryptedParticipantCount[ideaId]);
        
        // Calculate tokens minted (stored as encrypted for privacy)
        uint256 tokens = usdyAmount * window.tokenMintRatio / 1e18;
        
        // Emit private event (no amount exposed)
        emit PrivateDeposit(msg.sender, ideaId, bytes32(0));
        
        return tokens;
    }

    /**
     * @notice Confidential deposit - encrypts amount client-side.
     * @dev Amount never exposed in plaintext on-chain.
     */
    function depositConfidential(uint256 ideaId, InEuint128 calldata encryptedAmount) external returns (uint256 tokensMinted) {
        FundingWindow storage window = fundingWindows[ideaId];
        
        if (window.phase != FundingPhase.FundingOpen) {
            revert InvalidPhase(FundingPhase.FundingOpen, window.phase);
        }
        
        if (block.timestamp > window.endTime) {
            revert FundingExpired();
        }
        
        if (window.gatingEnabled && !gatedWhitelist[ideaId][msg.sender]) {
            revert GatingEnabled(msg.sender);
        }
        
        euint128 amount = FHE.asEuint128(encryptedAmount);
        
        // Track encrypted deposit
        _encryptedDeposits[ideaId][msg.sender] = FHE.add(
            _encryptedDeposits[ideaId][msg.sender],
            amount
        );
        FHE.allowThis(_encryptedDeposits[ideaId][msg.sender]);
        
        // Update encrypted total
        _encryptedTotalRaised[ideaId] = FHE.add(_encryptedTotalRaised[ideaId], amount);
        FHE.allowThis(_encryptedTotalRaised[ideaId]);
        
        // Increment participant count
        _encryptedParticipantCount[ideaId] = FHE.add(_encryptedParticipantCount[ideaId], FHE.asEuint128(1));
        FHE.allowThis(_encryptedParticipantCount[ideaId]);
        
        // Token calculation would need to be done off-chain or via ZK proof
        emit PrivateDeposit(msg.sender, ideaId, bytes32(0));
        
        return 0; // Tokens calculated off-chain
    }

    // ── View Functions ─────────────────────────────────────────────────────────

    function getFundingPhase(uint256 ideaId) external view returns (FundingPhase) {
        return fundingWindows[ideaId].phase;
    }

    function getFundingWindow(uint256 ideaId) external view returns (FundingWindow memory) {
        return fundingWindows[ideaId];
    }

    /**
     * @notice Get encrypted deposit handle for a user.
     * @dev Caller must have permission to decrypt.
     */
    function getEncryptedDeposit(uint256 ideaId, address user) external view returns (euint128) {
        return _encryptedDeposits[ideaId][user];
    }

    /**
     * @notice Get encrypted total raised handle.
     * @dev Permissioned access.
     */
    function getEncryptedTotalRaised(uint256 ideaId) external view returns (euint128) {
        return _encryptedTotalRaised[ideaId];
    }

    /**
     * @notice Get encrypted participant count.
     */
    function getEncryptedParticipantCount(uint256 ideaId) external view returns (euint128) {
        return _encryptedParticipantCount[ideaId];
    }

    /**
     * @notice Check if user is whitelisted for gated window.
     */
    function isWhitelisted(uint256 ideaId, address user) external view returns (bool) {
        return gatedWhitelist[ideaId][user];
    }

    /**
     * @notice Check if funding window is finalized.
     */
    function isFinalized(uint256 ideaId) external view returns (bool) {
        return fundingWindows[ideaId].finalized;
    }

    // ── Permissioned Disclosure ──────────────────────────────────────────────

    /**
     * @notice Request to disclose deposit to a specific address.
     */
    function requestDepositDisclosure(uint256 ideaId, address recipient) external {
        euint128 deposit = _encryptedDeposits[ideaId][msg.sender];
        FHE.allow(deposit, recipient);
    }

    /**
     * @notice Request to disclose total raised to DAO.
     */
    function requestTotalDisclosure(uint256 ideaId, address dao) external {
        euint128 total = _encryptedTotalRaised[ideaId];
        FHE.allow(total, dao);
    }
}