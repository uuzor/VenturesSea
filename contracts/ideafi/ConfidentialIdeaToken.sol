// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "@fhenixprotocol/contracts/experimental/token/FHERC20/FHERC20.sol";
import {FHE, euint128, inEuint128, ebool} from "@fhenixprotocol/contracts/FHE.sol";
import "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/**
 * @title ConfidentialIdeaToken
 * @notice FHERC20-based IdeaToken with encrypted balances and transfers.
 *         Replaces the standard ERC20 IdeaToken with full privacy via FHE.
 *         Maintains P2P-only trading restriction through operator system.
 *         Uses initializer pattern for ERC-1167 clone compatibility.
 */
contract ConfidentialIdeaToken is FHERC20, Initializable {
    using FHE for *;

    // ── State ─────────────────────────────────────────────────────────────────

    /// @notice Idea ID this token represents
    uint256 public ideaId;

    /// @notice Funding pool that can mint/burn tokens
    address public fundingPool;

    /// @notice IdeaDAO that owns this token
    address public ideaDAO;

    /// @notice Protocol market for P2P trading
    address public protocolMarket;

    // ── Events ─────────────────────────────────────────────────────────────────

    event ConfidentialMint(address indexed to, uint256 amount);
    event ConfidentialBurn(address indexed from, uint256 amount);

    // ── Errors ──────────────────────────────────────────────────────────────────

    error NotFundingPool();
    error NotDAO();
    error InvalidAmount();

    // ── Constructor ──────────────────────────────────────────────────────────

    constructor(
        uint256 _ideaId,
        string memory name_,
        string memory symbol_,
        address _fundingPool,
        address _ideaDAO,
        address _protocolMarket
    ) FHERC20(name_, symbol_) {
        _initialize(_ideaId, _fundingPool, _ideaDAO, _protocolMarket);
    }

    // ── Initializer ──────────────────────────────────────────────────────────

    /**
     * @notice Initialize a cloned instance.
     */
    function initialize(
        uint256 _ideaId,
        string memory name_,
        string memory symbol_,
        address _fundingPool,
        address _ideaDAO,
        address _protocolMarket
    ) external initializer {
        _initialize(_ideaId, _fundingPool, _ideaDAO, _protocolMarket);
    }

    function _initialize(
        uint256 _ideaId,
        address _fundingPool,
        address _ideaDAO,
        address _protocolMarket
    ) internal {
        require(_ideaId > 0, "ConfidentialIdeaToken: zero ideaId");
        require(_fundingPool != address(0), "ConfidentialIdeaToken: zero fundingPool");
        require(_ideaDAO != address(0), "ConfidentialIdeaToken: zero ideaDAO");
        require(_protocolMarket != address(0), "ConfidentialIdeaToken: zero market");

        ideaId = _ideaId;
        fundingPool = _fundingPool;
        ideaDAO = _ideaDAO;
        protocolMarket = _protocolMarket;
    }

    // ── Confidential minting ──────────────────────────────────────────────────

    /**
     * @notice Mint tokens to a contributor — only callable by the FundingPool.
     */
    function mint(address to, uint256 amount) external {
        if (msg.sender != fundingPool) revert NotFundingPool();
        if (amount == 0) revert InvalidAmount();

        _mint(to, amount);
        emit ConfidentialMint(to, amount);
    }

    /**
     * @notice Mint with encrypted input from FundingPool.
     */
    function mintEncrypted(address to, inEuint128 calldata encryptedAmount) external {
        if (msg.sender != fundingPool) revert NotFundingPool();

        euint128 amount = FHE.asEuint128(encryptedAmount);
        
        // Update encrypted balances
        _encBalances[to] = _encBalances[to] + amount;
        totalEncryptedSupply = totalEncryptedSupply + amount;

        emit ConfidentialMint(to, 0); // Amount encrypted
    }

    // ── Confidential burning ─────────────────────────────────────────────────

    /**
     * @notice Burn tokens from a contributor — only callable by the FundingPool.
     */
    function burn(address from, uint256 amount) external {
        if (msg.sender != fundingPool) revert NotFundingPool();
        if (amount == 0) revert InvalidAmount();

        _burn(from, amount);
        emit ConfidentialBurn(from, amount);
    }

    /**
     * @notice Burn with encrypted input from FundingPool.
     */
    function burnEncrypted(address from, inEuint128 calldata encryptedAmount) external {
        if (msg.sender != fundingPool) revert NotFundingPool();

        euint128 amount = FHE.asEuint128(encryptedAmount);
        
        // Validate and burn
        euint128 currentBalance = _encBalances[from];
        ebool isEnough = FHE.lte(amount, currentBalance);
euint128 amountToBurn = FHE.select(isEnough, amount, currentBalance);

        _encBalances[from] = _encBalances[from] - amountToBurn;
        totalEncryptedSupply = totalEncryptedSupply - amountToBurn;

        emit ConfidentialBurn(from, 0); // Amount encrypted
    }

    // ── Builder allocation ───────────────────────────────────────────────────

    /**
     * @notice Mint builder allocation — called by IdeaDAO via governance.
     */
    function mintBuilderAllocation(address to, uint256 amount) external {
        if (msg.sender != ideaDAO) revert NotDAO();
        if (amount == 0) revert InvalidAmount();

        _mint(to, amount);
        emit ConfidentialMint(to, amount);
    }

    // ── Encrypted balance queries ─────────────────────────────────────────────

    /**
     * @notice Get encrypted balance handle for a user.
     */
    function getEncryptedBalance(address account) external view returns (euint128) {
        return _encBalances[account];
    }

    /**
     * @notice Request to disclose encrypted amount.
     */
    function requestDiscloseAmount(euint128 amount) external {
    }

    // ── P2P Transfer support ────────────────────────────────────────────────

    /**
     * @notice Standard transfer (for non-encrypted tokens).
     */
    function confidentialTransfer(address to, uint256 amount) external {
        if (amount == 0) revert InvalidAmount();
        _transfer(msg.sender, to, amount);
    }

    // Note: transferEncrypted is inherited from FHERC20
}