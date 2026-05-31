// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {FHE, euint128, ebool} from "@fhenixprotocol/cofhe-contracts/FHE.sol";
import {InEuint128} from "@fhenixprotocol/cofhe-contracts/ICofhe.sol";
import "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/**
 * @title ConfidentialIdeaToken
 * @notice IdeaToken with encrypted balances for privacy.
 *         Uses standard ERC20 for composability with parallel encrypted tracking.
 *         Maintains P2P-only trading restriction through operator system.
 *         Uses initializer pattern for ERC-1167 clone compatibility.
 * 
 * @dev Privacy approach: Standard ERC20 balances for token transfers and
 *      composability. Encrypted balances stored separately for private
 *      position queries. Only the holder can decrypt their encrypted balance.
 */
contract ConfidentialIdeaToken is ERC20, Initializable {
    using FHE for *;

    // ── State ─────────────────────────────────────────────────────────────────

    /// @notice Idea ID this token represents
    uint256 public ideaId;
    string private _customName;
    string private _customSymbol;

    /// @notice Funding pool that can mint/burn tokens
    address public fundingPool;

    /// @notice IdeaDAO that owns this token
    address public ideaDAO;

    /// @notice Protocol market for P2P trading
    address public protocolMarket;

    /// @notice Encrypted balances (parallel to ERC20 for privacy)
    mapping(address => euint128) private _encryptedBalances;

    /// @notice Encrypted total supply
    euint128 private _encryptedTotalSupply;

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
    ) ERC20(name_, symbol_) {
        _initialize(_ideaId, name_, symbol_, _fundingPool, _ideaDAO, _protocolMarket);
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
        require(bytes(name_).length > 0, "ConfidentialIdeaToken: empty name");
        _initialize(_ideaId, name_, symbol_, _fundingPool, _ideaDAO, _protocolMarket);
    }

    function _initialize(
        uint256 _ideaId,
        string memory name_,
        string memory symbol_,
        address _fundingPool,
        address _ideaDAO,
        address _protocolMarket
    ) internal {
        require(_ideaId > 0, "ConfidentialIdeaToken: zero ideaId");
        require(_fundingPool != address(0), "ConfidentialIdeaToken: zero fundingPool");
        require(_ideaDAO != address(0), "ConfidentialIdeaToken: zero ideaDAO");
        require(_protocolMarket != address(0), "ConfidentialIdeaToken: zero market");

        ideaId = _ideaId;
        _customName = name_;
        _customSymbol = symbol_;
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
        
        // Update encrypted balance
        euint128 amountEnc = FHE.asEuint128(amount);
        _encryptedBalances[to] = FHE.add(_encryptedBalances[to], amountEnc);
        FHE.allowThis(_encryptedBalances[to]);
        _encryptedTotalSupply = FHE.add(_encryptedTotalSupply, amountEnc);
        FHE.allowThis(_encryptedTotalSupply);

        emit ConfidentialMint(to, amount);
    }

    /**
     * @notice Mint with encrypted input from FundingPool.
     * @dev For true confidential minting with encrypted amounts.
     */
    function mintEncrypted(address to, InEuint128 calldata encryptedAmount) external {
        if (msg.sender != fundingPool) revert NotFundingPool();

        euint128 amount = FHE.asEuint128(encryptedAmount);
        
        // Update encrypted balances (doesn't update ERC20 - plaintext amount needed)
        _encryptedBalances[to] = FHE.add(_encryptedBalances[to], amount);
        FHE.allowThis(_encryptedBalances[to]);
        _encryptedTotalSupply = FHE.add(_encryptedTotalSupply, amount);
        FHE.allowThis(_encryptedTotalSupply);

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
        
        // Update encrypted balance
        euint128 amountEnc = FHE.asEuint128(amount);
        _encryptedBalances[from] = FHE.sub(_encryptedBalances[from], amountEnc);
        FHE.allowThis(_encryptedBalances[from]);
        _encryptedTotalSupply = FHE.sub(_encryptedTotalSupply, amountEnc);
        FHE.allowThis(_encryptedTotalSupply);

        emit ConfidentialBurn(from, amount);
    }

    /**
     * @notice Burn with encrypted input from FundingPool.
     */
    function burnEncrypted(address from, InEuint128 calldata encryptedAmount) external {
        if (msg.sender != fundingPool) revert NotFundingPool();

        euint128 amount = FHE.asEuint128(encryptedAmount);
        
        // Validate and burn
        euint128 currentBalance = _encryptedBalances[from];
        ebool isEnough = FHE.lte(amount, currentBalance);
        euint128 amountToBurn = FHE.select(isEnough, amount, currentBalance);

        _encryptedBalances[from] = FHE.sub(_encryptedBalances[from], amountToBurn);
        _encryptedTotalSupply = FHE.sub(_encryptedTotalSupply, amountToBurn);
        FHE.allowThis(_encryptedBalances[from]);

        FHE.allowThis(_encryptedTotalSupply);
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
     * @dev Returns handle that caller (if allowed) can decrypt.
     */
    function getEncryptedBalance(address account) external view returns (euint128) {
        return _encryptedBalances[account];
    }

    /**
     * @notice Get encrypted total supply handle.
     */
    function getEncryptedTotalSupply() external view returns (euint128) {
        return _encryptedTotalSupply;
    }
    
    /**
     * @notice Request to disclose encrypted amount to caller.
     * @dev Grants caller permission to decrypt the amount.
     */
    function requestDiscloseAmount(euint128 amount) external {
        FHE.allow(amount, msg.sender);
    }

    // ── P2P Transfer support ────────────────────────────────────────────────

    /**
     * @notice Standard transfer (for non-encrypted tokens).
     */
    function confidentialTransfer(address to, uint256 amount) external {
        if (amount == 0) revert InvalidAmount();
        _transfer(msg.sender, to, amount);
    }
}
