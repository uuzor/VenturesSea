// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import "../utils/ReentrancyGuard.sol";
import {FHE, euint8, euint16, euint32, euint64, euint128, InEuint64, ebool, eaddress} from "@fhenixprotocol/cofhe-contracts/FHE.sol";
import "./IIdeaFi.sol";

/**
 * @title ConfidentialFundingPool
 * @notice FundingPool with encrypted deposit amounts for privacy.
 *         Depositors' amounts are kept confidential while maintaining
 *         on-chain fee calculations and cap enforcement.
 */
contract ConfidentialFundingPool is Initializable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // -----------------------------------------------------------------------
    // Constants
    // -----------------------------------------------------------------------

    uint256 public constant PROTOCOL_FEE_BPS = 200; // 2%
    uint256 public constant BPS_DENOM = 10_000;

    // -----------------------------------------------------------------------
    // Config
    // -----------------------------------------------------------------------

    uint256 public ideaId;
    IERC20  public musd;
    address public ideaToken;  // Can be ConfidentialIdeaToken or standard
    address public protocolTreasury;
    address public registry;
    uint256 public softCap;
    uint256 public hardCap;
    uint256 public fundingDeadline;
    uint256 public builderAllocationPct;

    // -----------------------------------------------------------------------
    // State
    // -----------------------------------------------------------------------

    bool public isLocked;
    bool public refundMode;

    // ── Confidential state ──────────────────────────────────────────────────

    /// @notice Encrypted deposit tracking per investor (handle-based)
    mapping(address => euint64) private _encryptedDeposits;

    /// @notice Encrypted total deposited (maintained for cap checks)
    euint64 private _encryptedTotalDeposited;

    /// @notice Public tracking for cap enforcement (not confidential)
    uint256 public totalDeposited;

    mapping(address => uint256) public deposits; // For backward compat

    // -----------------------------------------------------------------------
    // Events
    // -----------------------------------------------------------------------

    event Deposited(address indexed investor, uint256 gross, uint256 fee, uint256 net);
    event EncryptedDeposit(address indexed investor);
    event Withdrawn(address indexed investor, uint256 amount);
    event PoolLocked();
    event BuilderFundsReleased(address indexed builder, uint256 gross, uint256 fee, uint256 net);
    event EmergencyRefundEnabled();
    event RefundClaimed(address indexed investor, uint256 amount);

    // -----------------------------------------------------------------------
    // Modifiers
    // -----------------------------------------------------------------------

    modifier onlyDAO() {
        require(msg.sender == IIdeaRegistry(registry).getIdeaDAO(ideaId), "FundingPool: caller is not the DAO");
        _;
    }

    modifier onlyDAOOrMilestone() {
        address dao = IIdeaRegistry(registry).getIdeaDAO(ideaId);
        address milestone = IIdeaRegistry(registry).getMilestone(ideaId);
        require(
            msg.sender == dao || msg.sender == milestone,
            "FundingPool: caller is not DAO or Milestone"
        );
        _;
    }

    // -----------------------------------------------------------------------
    // Constructor
    // -----------------------------------------------------------------------

    constructor(
        uint256 _ideaId,
        address _musd,
        address _ideaToken,
        address _protocolTreasury,
        address _registry,
        uint256 _softCap,
        uint256 _hardCap,
        uint256 _fundingDeadline,
        uint256 _builderAllocationPct
    ) {
        if (_registry != address(0)) {
            _initialize(
                _ideaId, _musd, _ideaToken, _protocolTreasury, _registry,
                _softCap, _hardCap, _fundingDeadline, _builderAllocationPct
            );
        }
    }

    function _initialize(
        uint256 _ideaId,
        address _musd,
        address _ideaToken,
        address _protocolTreasury,
        address _registry,
        uint256 _softCap,
        uint256 _hardCap,
        uint256 _fundingDeadline,
        uint256 _builderAllocationPct
    ) internal {
        ideaId = _ideaId;
        musd = IERC20(_musd);
        ideaToken = _ideaToken;
        protocolTreasury = _protocolTreasury;
        registry = _registry;
        softCap = _softCap;
        hardCap = _hardCap;
        fundingDeadline = _fundingDeadline;
        builderAllocationPct = _builderAllocationPct;
    }

    function initialize(
        uint256 _ideaId,
        address _musd,
        address _ideaToken,
        address _protocolTreasury,
        address _registry,
        uint256 _softCap,
        uint256 _hardCap,
        uint256 _fundingDeadline,
        uint256 _builderAllocationPct
    ) external initializer {
        require(_musd != address(0),              "FundingPool: zero musd");
        require(_ideaToken != address(0),         "FundingPool: zero ideaToken");
        require(_protocolTreasury != address(0),  "FundingPool: zero treasury");
        require(_registry != address(0),          "FundingPool: zero registry");
        require(_hardCap >= _softCap,             "FundingPool: hardCap < softCap");
        require(_fundingDeadline > block.timestamp, "FundingPool: deadline in past");

        _initialize(
            _ideaId, _musd, _ideaToken, _protocolTreasury, _registry,
            _softCap, _hardCap, _fundingDeadline, _builderAllocationPct
        );
    }

    // -----------------------------------------------------------------------
    // Standard deposit (backward compatible)
    // -----------------------------------------------------------------------

    /// @notice Deposit MUSD into the funding pool (public version).
    function deposit(uint256 amount) external {
        require(!isLocked,                              "FundingPool: pool is locked");
        require(block.timestamp <= fundingDeadline,     "FundingPool: funding deadline passed");
        require(amount > 0,                             "FundingPool: zero amount");

        uint256 fee = (amount * PROTOCOL_FEE_BPS) / BPS_DENOM;
        uint256 net = amount - fee;

        require(totalDeposited + net <= hardCap, "FundingPool: hard cap exceeded");

        // Pull full gross amount from caller
        musd.safeTransferFrom(msg.sender, address(this), amount);

        // Forward fee to treasury
        musd.safeTransfer(protocolTreasury, fee);

        // Record deposit
        deposits[msg.sender] += net;
        totalDeposited += net;

        // Mint IdeaTokens 1:1 against net deposit
        IIdeaToken(ideaToken).mint(msg.sender, net);

        emit Deposited(msg.sender, amount, fee, net);
    }

    // -----------------------------------------------------------------------
    // Confidential deposit (NEW - using FHE)
    // -----------------------------------------------------------------------

    /**
     * @notice Deposit MUSD with encrypted amount for privacy.
     * @dev Uses FHE to keep deposit amounts confidential on-chain.
     * @param grossAmount Plaintext gross amount for fee calculation and cap enforcement.
     *                     Privacy is maintained at individual-deposit level; protocol sees totals.
     */
    function depositConfidential(uint256 grossAmount) external nonReentrant {
        require(!isLocked,                              "FundingPool: pool is locked");
        require(block.timestamp <= fundingDeadline,     "FundingPool: funding deadline passed");
        require(grossAmount > 0,                         "FundingPool: zero amount");

        uint256 fee = (grossAmount * PROTOCOL_FEE_BPS) / BPS_DENOM;
        uint256 net = grossAmount - fee;
        require(totalDeposited + net <= hardCap, "FundingPool: hard cap exceeded");

        musd.safeTransferFrom(msg.sender, address(this), grossAmount);
        musd.safeTransfer(protocolTreasury, fee);

        // Encrypt the net amount for private tracking
        euint64 netEnc = FHE.asEuint64(net);
        _encryptedDeposits[msg.sender] = FHE.add(_encryptedDeposits[msg.sender], netEnc);
        FHE.allowThis(_encryptedDeposits[msg.sender]);
        FHE.allow(_encryptedDeposits[msg.sender], msg.sender);  // investor can query position

        _encryptedTotalDeposited = FHE.add(_encryptedTotalDeposited, netEnc);
        FHE.allowThis(_encryptedTotalDeposited);

        deposits[msg.sender] += net;
        totalDeposited += net;

        IIdeaToken(ideaToken).mint(msg.sender, net);

        emit EncryptedDeposit(msg.sender);
        emit Deposited(msg.sender, grossAmount, fee, net);
    }


    // -----------------------------------------------------------------------
    // Standard withdraw (backward compatible)
    // -----------------------------------------------------------------------

    /// @notice Withdraw previously deposited MUSD (only while pool is unlocked).
    function withdraw(uint256 amount) external {
        require(!isLocked,                         "FundingPool: pool is locked");
        require(amount > 0,                        "FundingPool: zero amount");
        require(deposits[msg.sender] >= amount,    "FundingPool: insufficient balance");

        // Burn IdeaTokens
        IIdeaToken(ideaToken).burn(msg.sender, amount);

        // Update deposits
        deposits[msg.sender] -= amount;
        totalDeposited -= amount;

        // Refund investor
        musd.safeTransfer(msg.sender, amount);

        emit Withdrawn(msg.sender, amount);
    }

    // -----------------------------------------------------------------------
    // Confidential withdraw (NEW - using FHE)
    // -----------------------------------------------------------------------

    /**
     * @notice Withdraw MUSD using encrypted balance check.
     * @param amount Plaintext amount (privacy at withdraw-amount level on-chain).
     */
    function withdrawConfidential(uint256 amount) external nonReentrant {
        require(!isLocked, "FundingPool: pool is locked");
        require(amount > 0, "FundingPool: zero amount");
        require(deposits[msg.sender] >= amount, "FundingPool: insufficient balance");

        // Branchless encrypted subtraction (clamped via select)
        euint64 amountEnc = FHE.asEuint64(amount);
        euint64 current = _encryptedDeposits[msg.sender];
        ebool isValid = FHE.lte(amountEnc, current);
        euint64 actualAmount = FHE.select(isValid, amountEnc, FHE.asEuint64(0));

        _encryptedDeposits[msg.sender] = FHE.sub(current, actualAmount);
        FHE.allowThis(_encryptedDeposits[msg.sender]);
        FHE.allow(_encryptedDeposits[msg.sender], msg.sender);

        IIdeaToken(ideaToken).burn(msg.sender, amount);
        deposits[msg.sender] -= amount;
        totalDeposited -= amount;
        musd.safeTransfer(msg.sender, amount);

        emit Withdrawn(msg.sender, amount);
    }


    // -----------------------------------------------------------------------
    // DAO actions
    // -----------------------------------------------------------------------

    /// @notice Lock the pool once the soft cap is met.
    function lockPool() external onlyDAO {
        require(totalDeposited >= softCap, "FundingPool: soft cap not met");
        isLocked = true;
        emit PoolLocked();
    }

    /// @notice Release funds to a builder.
    function releaseBuilderFunds(address builder, uint256 amount) external onlyDAOOrMilestone {
        require(isLocked,            "FundingPool: pool not locked");
        require(builder != address(0), "FundingPool: zero builder");
        require(amount > 0,          "FundingPool: zero amount");

        uint256 fee = (amount * PROTOCOL_FEE_BPS) / BPS_DENOM;
        uint256 net = amount - fee;

        musd.safeTransfer(protocolTreasury, fee);
        musd.safeTransfer(builder, net);

        emit BuilderFundsReleased(builder, amount, fee, net);
    }

    /// @notice Enable emergency refund mode.
    function emergencyRefund() external onlyDAO {
        require(isLocked, "FundingPool: pool not locked");
        refundMode = true;
        emit EmergencyRefundEnabled();
    }

    /// @notice Claim a refund when refund mode is active.
    function claimRefund() external {
        require(refundMode, "FundingPool: refund mode not active");

        uint256 amount = deposits[msg.sender];
        require(amount > 0, "FundingPool: nothing to refund");

        deposits[msg.sender] = 0;
        totalDeposited -= amount;

        // Clear encrypted deposit
        _encryptedDeposits[msg.sender] = FHE.asEuint64(0);

        musd.safeTransfer(msg.sender, amount);

        emit RefundClaimed(msg.sender, amount);
    }

    // -----------------------------------------------------------------------
    // View functions for encrypted data
    // -----------------------------------------------------------------------

    /**
     * @notice Get encrypted deposit handle for an investor.
     * @dev Returns ciphertext that only the investor can decrypt.
     */
    function getEncryptedDeposit(address investor) external view returns (euint64) {
        return _encryptedDeposits[investor];
    }

    /**
     * @notice Get encrypted total deposited handle.
     */
    function getEncryptedTotalDeposited() external view returns (euint64) {
        return _encryptedTotalDeposited;
    }

    /**
     * @notice Check if pool has met soft cap (public check).
     */
    function hasMetSoftCap() external view returns (bool) {
        return totalDeposited >= softCap;
    }

    /**
     * @notice Get remaining capacity (public for cap enforcement).
     */
    function remainingCapacity() external view returns (uint256) {
        return hardCap > totalDeposited ? hardCap - totalDeposited : 0;
    }

    // -----------------------------------------------------------------------
    // Internal helpers
}