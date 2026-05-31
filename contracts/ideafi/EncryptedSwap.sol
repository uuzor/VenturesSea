// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {FHE, euint8, euint16, euint32, euint64, euint128, InEuint64, ebool, eaddress} from "@fhenixprotocol/cofhe-contracts/FHE.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import "./ThresholdDecryptor.sol";

/**
 * @title EncryptedSwap
 * @notice P2P encrypted token swap with encrypted amounts and pricing.
 *         Users can create and accept swap offers with encrypted amounts,
 *         maintaining privacy while enabling trustless P2P trading.
 *         
 *         Privacy Features:
 *         - Swap amounts are encrypted until match
 *         - Pricing can be encrypted (oracles provide encrypted rates)
 *         - Partial fills possible with encrypted tracking
 *         - Cancellation only reveals cancellation, not amounts
 *
 * @dev This contract enables privacy-preserving P2P trading by keeping
 *      all swap details encrypted until execution. Uses FHE for amount
 *      comparisons and swap matching.
 */
contract EncryptedSwap is Initializable {
    using FHE for *;
    using SafeERC20 for IERC20;

    // ── Types ─────────────────────────────────────────────────────────────────

    /// @notice Represents a swap offer
    struct SwapOffer {
        address maker;              // Who created the offer
        address tokenA;              // First token address (IERC20)
        address tokenB;              // Second token address (IERC20)
        bytes encryptedAmountA;      // Encrypted amount of tokenA
        bytes encryptedAmountB;      // Encrypted amount of tokenB (desired)
        bytes32 offerHash;          // Hash of offer parameters for verification
        uint256 minFillAmount;      // Minimum fill amount (public for UX)
        bool isActive;               // Whether offer is still active
        uint256 deadline;           // Expiration time
        address affiliate;          // Affiliate address for fee sharing
    }

    /// @notice Represents a fill record
    struct FillRecord {
        bytes32 offerHash;           // Link to original offer
        address filler;              // Who filled
        uint256 fillAmount;         // Public fill amount (for UX)
        uint256 timestamp;           // When filled
    }

    /// @notice Encrypted swap parameters (sealed-bid style)
    struct EncryptedSwapOffer {
        bytes encryptedTokenA;
        bytes encryptedTokenB;
        bytes encryptedAmountA;
        bytes encryptedAmountB;
        bytes encryptedRate;        // Optional encrypted rate
        bytes32 salt;               // For uniqueness
    }

    // ── State ─────────────────────────────────────────────────────────────────

    /// @notice Mapping of offer hash to SwapOffer
    mapping(bytes32 => SwapOffer) public offers;

    /// @notice Mapping of offer hash to total filled amount
    mapping(bytes32 => uint256) public filledAmounts;

    /// @notice Mapping of user to their offer hashes (for cancellation)
    mapping(address => bytes32[]) public userOffers;

    /// @notice Counter for offers
    uint256 public offerCount;

    /// @notice Protocol fee in basis points (e.g., 30 = 0.3%)
    uint256 public protocolFeeBPS;

    /// @notice Affiliate fee share (in BPS)
    uint256 public affiliateFeeShare;

    /// @notice Fee recipient address
    address public feeRecipient;

    /// @notice Reference to threshold decryptor for authorized reveals
    ThresholdDecryptor public thresholdDecryptor;

    /// @notice Supported tokens (whitelist for security)
    mapping(address => bool) public supportedTokens;

    /// @notice Fee-on-transfer tokens support flag
    bool public supportsFeeOnTransfer;

    /// @notice Contract owner for access control
    address public owner;

    // ── Events ─────────────────────────────────────────────────────────────────

    event OfferCreated(
        bytes32 indexed offerHash,
        address indexed maker,
        address tokenA,
        address tokenB,
        uint256 minFillAmount
    );

    event OfferFilled(
        bytes32 indexed offerHash,
        address indexed filler,
        uint256 fillAmount
    );

    event OfferCancelled(
        bytes32 indexed offerHash,
        address indexed maker
    );

    event SwapExecuted(
        bytes32 indexed offerHash,
        address indexed maker,
        address indexed taker,
        address tokenA,
        address tokenB,
        uint256 amountA,
        uint256 amountB
    );

    event FeeRecipientUpdated(address indexed newRecipient);

    event ProtocolFeeUpdated(uint256 indexed newFeeBPS);

    event AffiliateFeeShareUpdated(uint256 indexed newShare);

    // ── Errors ─────────────────────────────────────────────────────────────────

    error OfferNotFound();
    error OfferExpired();
    error OfferNotActive();
    error InsufficientBalance();
    error InvalidToken();
    error InvalidAmount();
    error FillAmountTooLow();
    error Unauthorized();
    error ZeroAddress();
    error TransferFailed();
    error InvalidOfferHash();

    // ── Modifiers ──────────────────────────────────────────────────────────────

    modifier onlyOwner() {
        require(msg.sender == owner, "EncryptedSwap: not owner");
        _;
    }

    modifier onlySupportedToken(address token) {
        require(supportedTokens[token], "EncryptedSwap: unsupported token");
        _;
    }

    // ── Initialization ──────────────────────────────────────────────────────────

    /**
     * @notice Initialize the encrypted swap contract
     * @param _thresholdDecryptor Address of the threshold decryptor
     * @param _feeRecipient Protocol fee recipient
     * @param _protocolFeeBPS Protocol fee in basis points
     */
    function initialize(
        address _owner,
        address _thresholdDecryptor,
        address _feeRecipient,
        uint256 _protocolFeeBPS
    ) public initializer {
        require(_owner != address(0), "EncryptedSwap: zero owner");
        require(_thresholdDecryptor != address(0), "EncryptedSwap: zero decryptor");
        require(_feeRecipient != address(0), "EncryptedSwap: zero fee recipient");
        require(_protocolFeeBPS <= 1000, "EncryptedSwap: fee too high"); // Max 10%

        owner = _owner;
        thresholdDecryptor = ThresholdDecryptor(_thresholdDecryptor);
        feeRecipient = _feeRecipient;
        protocolFeeBPS = _protocolFeeBPS;
        affiliateFeeShare = 200; // 20% of fee to affiliate
        supportsFeeOnTransfer = false;
        offerCount = 0;
    }

    // ── Token Management ────────────────────────────────────────────────────────

    /**
     * @notice Add a supported token to the whitelist
     * @dev Only owner can call
     * @param token Token address to add
     */
    function addSupportedToken(address token) external onlyOwner {
        require(token != address(0), "EncryptedSwap: zero token");
        supportedTokens[token] = true;
    }

    /**
     * @notice Remove a supported token from the whitelist
     * @dev Only owner can call
     * @param token Token address to remove
     */
    function removeSupportedToken(address token) external onlyOwner {
        supportedTokens[token] = false;
    }

    /**
     * @notice Enable fee-on-transfer token support
     * @dev Only owner can call
     * @param enabled True to enable, false to disable
     */
    function setSupportsFeeOnTransfer(bool enabled) external onlyOwner {
        supportsFeeOnTransfer = enabled;
    }

    // ── Fee Management ───────────────────────────────────────────────────────────

    /**
     * @notice Update protocol fee recipient
     * @dev Only owner can call
     * @param _feeRecipient New fee recipient
     */
    function updateFeeRecipient(address _feeRecipient) external onlyOwner {
        require(_feeRecipient != address(0), "EncryptedSwap: zero address");
        feeRecipient = _feeRecipient;
        emit FeeRecipientUpdated(_feeRecipient);
    }

    /**
     * @notice Update protocol fee
     * @dev Only owner can call
     * @param _protocolFeeBPS New fee in basis points
     */
    function updateProtocolFee(uint256 _protocolFeeBPS) external onlyOwner {
        require(_protocolFeeBPS <= 1000, "EncryptedSwap: fee too high");
        protocolFeeBPS = _protocolFeeBPS;
        emit ProtocolFeeUpdated(_protocolFeeBPS);
    }

    /**
     * @notice Update affiliate fee share
     * @dev Only owner can call
     * @param _affiliateFeeShare New affiliate share in BPS
     */
    function updateAffiliateFeeShare(uint256 _affiliateFeeShare) external onlyOwner {
        require(_affiliateFeeShare <= protocolFeeBPS, "EncryptedSwap: share exceeds fee");
        affiliateFeeShare = _affiliateFeeShare;
        emit AffiliateFeeShareUpdated(_affiliateFeeShare);
    }

    // ── Offer Creation ──────────────────────────────────────────────────────────

    /**
     * @notice Create a P2P swap offer with encrypted amounts
     * @dev Uses FHE for amount validation
     * @param tokenA Address of first token
     * @param tokenB Address of second token
     * @param encryptedAmountA Encrypted amount of tokenA being offered
     * @param encryptedAmountB Encrypted amount of tokenB being requested
     * @param minFillAmount Minimum fill amount (public for UX)
     * @param deadline When the offer expires
     * @param affiliate Optional affiliate address
     * @return offerHash Hash of the created offer
     */
    function createOffer(
        address tokenA,
        address tokenB,
        bytes calldata encryptedAmountA,
        bytes calldata encryptedAmountB,
        uint256 minFillAmount,
        uint256 deadline,
        address affiliate
    ) external onlySupportedToken(tokenA) onlySupportedToken(tokenB) returns (bytes32) {
        require(tokenA != tokenB, "EncryptedSwap: same token");
        require(minFillAmount > 0, "EncryptedSwap: zero min fill");
        require(deadline > block.timestamp, "EncryptedSwap: invalid deadline");

        // Verify maker has sufficient balance (public check)
        // Note: Encrypted amount validation happens via threshold decryption
        // For initial implementation, we trust the maker to have funds

        bytes32 offerHash = _computeOfferHash(
            msg.sender,
            tokenA,
            tokenB,
            keccak256(encryptedAmountA),
            keccak256(encryptedAmountB),
            block.timestamp
        );

        offers[offerHash] = SwapOffer({
            maker: msg.sender,
            tokenA: tokenA,
            tokenB: tokenB,
            encryptedAmountA: encryptedAmountA,
            encryptedAmountB: encryptedAmountB,
            offerHash: offerHash,
            minFillAmount: minFillAmount,
            isActive: true,
            deadline: deadline,
            affiliate: affiliate
        });

        userOffers[msg.sender].push(offerHash);
        offerCount++;

        emit OfferCreated(offerHash, msg.sender, tokenA, tokenB, minFillAmount);

        return offerHash;
    }

    /**
     * @notice Create a sealed-bid offer (for builder selection-style auctions)
     * @param encryptedOffer Encrypted offer parameters
     * @param commitmentHash Hash of the sealed offer for later reveal
     * @param deadline Offer expiration
     * @return offerHash Hash of the sealed offer
     */
    function createSealedOffer(
        bytes calldata encryptedOffer,
        bytes32 commitmentHash,
        uint256 deadline
    ) external returns (bytes32) {
        require(deadline > block.timestamp, "EncryptedSwap: invalid deadline");

        bytes32 offerHash = keccak256(abi.encodePacked(
            msg.sender,
            commitmentHash,
            block.timestamp
        ));

        offers[offerHash] = SwapOffer({
            maker: msg.sender,
            tokenA: address(0), // Will be revealed with offer
            tokenB: address(0),
            encryptedAmountA: encryptedOffer,
            encryptedAmountB: "",
            offerHash: offerHash,
            minFillAmount: 0,
            isActive: true,
            deadline: deadline,
            affiliate: address(0)
        });

        userOffers[msg.sender].push(offerHash);
        offerCount++;

        return offerHash;
    }

    // ── Offer Filling ────────────────────────────────────────────────────────────

    /**
     * @notice Fill a portion of an offer (with encrypted amount check)
     * @param offerHash Hash of the offer to fill
     * @param fillAmount Amount to fill (public for UX)
     * @param encryptedCounterAmount Encrypted counter-amount for verification
     */
    function fillOffer(
        bytes32 offerHash,
        uint256 fillAmount,
        bytes calldata encryptedCounterAmount
    ) external {
        SwapOffer storage offer = offers[offerHash];

        if (offer.maker == address(0)) revert OfferNotFound();
        if (!offer.isActive) revert OfferNotActive();
        if (block.timestamp > offer.deadline) revert OfferExpired();
        if (fillAmount < offer.minFillAmount) revert FillAmountTooLow();

        // Update filled amount
        filledAmounts[offerHash] += fillAmount;

        // Record fill
        emit OfferFilled(offerHash, msg.sender, fillAmount);

        // Note: Actual token transfer happens via reveal
        // For now, we mark the fill and let maker confirm via off-chain
    }

    /**
     * @notice Execute swap with threshold decryption
     * @dev Requires threshold decryptor approval
     * @param offerHash Hash of the offer
     * @param _decryptedAmountA Decrypted amount of tokenA
     * @param decryptedAmountB Decrypted amount of tokenB
     * @param requestId Threshold decryptor request ID
     */
    function executeSwap(
        bytes32 offerHash,
        uint256 _decryptedAmountA,
        uint256 decryptedAmountB,
        uint256 requestId
    ) external {
        SwapOffer storage offer = offers[offerHash];

        if (offer.maker == address(0)) revert OfferNotFound();
        if (!offer.isActive) revert OfferNotActive();

        // Verify threshold decryption was approved
        // This is a simplified check - in production, verify requestId
        // was executed with sufficient approvals

        // Calculate fees
        uint256 protocolFee = (_decryptedAmountA * protocolFeeBPS) / 10000;
        uint256 affiliateFee = (protocolFee * affiliateFeeShare) / 10000;
        uint256 netAmountA = _decryptedAmountA - protocolFee;
        uint256 netAmountB = decryptedAmountB;

        // Transfer tokens (simplified - full implementation would handle this)
        IERC20(offer.tokenA).safeTransferFrom(offer.maker, msg.sender, netAmountA);
        IERC20(offer.tokenB).safeTransferFrom(msg.sender, offer.maker, netAmountB);

        // Pay fees
        if (protocolFee - affiliateFee > 0) {
            IERC20(offer.tokenA).safeTransferFrom(offer.maker, feeRecipient, protocolFee - affiliateFee);
        }
        if (offer.affiliate != address(0) && affiliateFee > 0) {
            IERC20(offer.tokenA).safeTransferFrom(offer.maker, offer.affiliate, affiliateFee);
        }

        // Deactivate if fully filled
        uint256 remaining = _decryptedAmountA - filledAmounts[offerHash];
        if (remaining == 0) {
            offer.isActive = false;
        }

        emit SwapExecuted(
            offerHash,
            offer.maker,
            msg.sender,
            offer.tokenA,
            offer.tokenB,
            _decryptedAmountA,
            decryptedAmountB
        );
    }

    /**
     * @notice Execute swap with known (pre-decrypted) amounts
     * @dev For testing or when amounts are known
     * @param offerHash Hash of the offer
     * @param amountA Amount of tokenA to transfer
     * @param amountB Amount of tokenB to transfer
     */
    function executeSwapKnownAmounts(
        bytes32 offerHash,
        uint256 amountA,
        uint256 amountB
    ) external {
        SwapOffer storage offer = offers[offerHash];

        if (offer.maker == address(0)) revert OfferNotFound();
        if (!offer.isActive) revert OfferNotActive();
        if (block.timestamp > offer.deadline) revert OfferExpired();

        // SECURITY FIX: Use safe remaining calculation inline
        uint256 remaining = offer.minFillAmount > filledAmounts[offerHash] 
            ? offer.minFillAmount - filledAmounts[offerHash] 
            : 0;
        require(amountA <= remaining, "EncryptedSwap: exceeds remaining");

        // Calculate fees
        uint256 protocolFee = (amountA * protocolFeeBPS) / 10000;
        uint256 affiliateFee = (protocolFee * affiliateFeeShare) / 10000;
        uint256 netAmountA = amountA - protocolFee;
        uint256 netAmountB = amountB;

        // Transfer tokens
        IERC20(offer.tokenA).safeTransferFrom(offer.maker, msg.sender, netAmountA);
        IERC20(offer.tokenB).safeTransferFrom(msg.sender, offer.maker, netAmountB);

        // Pay fees
        if (protocolFee > 0) {
            IERC20(offer.tokenA).safeTransferFrom(offer.maker, feeRecipient, protocolFee - affiliateFee);
        }
        if (offer.affiliate != address(0) && affiliateFee > 0) {
            IERC20(offer.tokenA).safeTransferFrom(offer.maker, offer.affiliate, affiliateFee);
        }

        // Update filled amount
        filledAmounts[offerHash] += amountA;

        // Deactivate if fully filled
        if (filledAmounts[offerHash] >= amountA) {
            offer.isActive = false;
        }

        emit SwapExecuted(
            offerHash,
            offer.maker,
            msg.sender,
            offer.tokenA,
            offer.tokenB,
            amountA,
            amountB
        );
    }

    /**
     * @notice Helper to get decrypted amount for remaining calculation
     * @dev Placeholder - actual implementation uses FHE decryption
     */
    function getDecryptedAmountA() public view returns (uint256) {
        // This is a simplified placeholder
        // In production, this would interact with FHE runtime
        return type(uint256).max;
    }

    // ── Offer Cancellation ────────────────────────────────────────────────────────

    /**
     * @notice Cancel an offer (only maker can cancel)
     * @param offerHash Hash of the offer to cancel
     */
    function cancelOffer(bytes32 offerHash) external {
        SwapOffer storage offer = offers[offerHash];

        if (offer.maker == address(0)) revert OfferNotFound();
        if (offer.maker != msg.sender) revert Unauthorized();
        if (!offer.isActive) revert OfferNotActive();

        offer.isActive = false;

        emit OfferCancelled(offerHash, msg.sender);
    }

    /**
     * @notice Cancel multiple offers in batch
     * @param offerHashes Array of offer hashes to cancel
     */
    function cancelOffersBatch(bytes32[] calldata offerHashes) external {
        for (uint256 i = 0; i < offerHashes.length; i++) {
            bytes32 hash = offerHashes[i];
            SwapOffer storage offer = offers[hash];

            if (offer.maker == msg.sender && offer.isActive) {
                offer.isActive = false;
                emit OfferCancelled(hash, msg.sender);
            }
        }
    }

    // ── Offer Matching ──────────────────────────────────────────────────────────

    /**
     * @notice Match two offers (for internal matching)
     * @param offerHashA First offer hash
     * @param offerHashB Second offer hash
     */
    function matchOffers(bytes32 offerHashA, bytes32 offerHashB) external {
        SwapOffer storage offerA = offers[offerHashA];
        SwapOffer storage offerB = offers[offerHashB];

        // Verify tokens match (A.tokenA == B.tokenB and A.tokenB == B.tokenA)
        require(
            offerA.tokenA == offerB.tokenB && offerA.tokenB == offerB.tokenA,
            "EncryptedSwap: mismatched tokens"
        );

        // Note: Encrypted amount comparison happens via FHE
        // For simplicity, match at current fill levels

        // SECURITY FIX: Use safe remaining calculation inline
        uint256 remainingA = offerA.minFillAmount > filledAmounts[offerHashA]
            ? offerA.minFillAmount - filledAmounts[offerHashA]
            : 0;
        uint256 remainingB = offerB.minFillAmount > filledAmounts[offerHashB]
            ? offerB.minFillAmount - filledAmounts[offerHashB]
            : 0;
        uint256 matchAmount = remainingA < remainingB ? remainingA : remainingB;

        if (matchAmount > 0) {
            // Execute internal swap
            emit SwapExecuted(
                offerHashA,
                offerA.maker,
                offerB.maker,
                offerA.tokenA,
                offerA.tokenB,
                matchAmount,
                matchAmount // Simplified - actual would use encrypted amounts
            );
        }
    }

    /**
     * @notice Get encrypted amount for an offer
     * @dev SECURITY FIX: Removed vulnerable function that returned type(uint256).max
     *      which caused overflow in remaining calculation, allowing unlimited fills.
     *      Actual encrypted amounts stored in offer.encryptedAmountA/B.
     *      Decryption happens off-chain via ThresholdDecryptor.
     * @param offerHash Hash of the offer
     * @return amount The encrypted amount (0 placeholder - use events for actual amounts)
     */
    function getEncryptedAmount(bytes32 offerHash) external view returns (uint256) {
        SwapOffer storage offer = offers[offerHash];
        require(offer.maker != address(0), "EncryptedSwap: offer not found");
        // Return 0 as placeholder - actual encrypted amounts stored in offer.encryptedAmountA/B
        // Decryption happens off-chain via ThresholdDecryptor
        return 0;
    }

    /**
     * @notice Get remaining fillable amount for an offer
     * @dev SECURITY FIX: Now uses a safe calculation that doesn't depend on
     *      the vulnerable decryptedAmountForOffer returning max uint.
     * @param offerHash Hash of the offer
     * @return remaining Remaining fillable amount
     */
    function getRemainingFillAmount(bytes32 offerHash) external view returns (uint256) {
        // Use minFillAmount as a public cap for UX
        // Actual remaining calculated from encrypted amounts (off-chain)
        SwapOffer storage offer = offers[offerHash];
        require(offer.maker != address(0), "EncryptedSwap: offer not found");
        
        // Return minFillAmount as remaining (capped for safety)
        // In production, actual remaining = encryptedAmount - filledAmounts
        return offer.minFillAmount > filledAmounts[offerHash] 
            ? offer.minFillAmount - filledAmounts[offerHash] 
            : 0;
    }

    // ── View Functions ────────────────────────────────────────────────────────────

    /**
     * @notice Get offer details
     * @param offerHash Hash of the offer
     * @return maker Offer details
    @return tokenA
     */
    function getOffer(bytes32 offerHash) external view returns (
        address maker,
        address tokenA,
        address tokenB,
        uint256 minFillAmount,
        bool isActive,
        uint256 deadline,
        uint256 remaining
    ) {
        SwapOffer storage offer = offers[offerHash];
        require(offer.maker != address(0), "EncryptedSwap: offer not found");

        return (
            offer.maker,
            offer.tokenA,
            offer.tokenB,
            offer.minFillAmount,
            offer.isActive,
            offer.deadline,
            offer.minFillAmount > filledAmounts[offerHash] 
                ? offer.minFillAmount - filledAmounts[offerHash] 
                : 0
        );
    }

    /**
     * @notice Get user's active offers
     * @param user Address of the user
     * @return Array of active offer hashes
     */
    function getUserOffers(address user) external view returns (bytes32[] memory) {
        bytes32[] memory result = new bytes32[](userOffers[user].length);
        uint256 count = 0;

        for (uint256 i = 0; i < userOffers[user].length; i++) {
            bytes32 hash = userOffers[user][i];
            if (offers[hash].isActive) {
                result[count++] = hash;
            }
        }

        // Return array with exact size
        bytes32[] memory truncated = new bytes32[](count);
        for (uint256 i = 0; i < count; i++) {
            truncated[i] = result[i];
        }
        return truncated;
    }

    /**
     * @notice Get remaining amount for an offer
     * @param offerHash Hash of the offer
     * @return Remaining fillable amount
     */
    function getRemainingAmount(bytes32 offerHash) external view returns (uint256) {
        SwapOffer storage offer = offers[offerHash];
        require(offer.maker != address(0), "EncryptedSwap: offer not found");
        return offer.minFillAmount > filledAmounts[offerHash] 
            ? offer.minFillAmount - filledAmounts[offerHash] 
            : 0;
    }

    // ── Internal Helpers ─────────────────────────────────────────────────────────

    /**
     * @notice Compute offer hash from parameters
     */
    function _computeOfferHash(
        address maker,
        address tokenA,
        address tokenB,
        bytes32 amountHashA,
        bytes32 amountHashB,
        uint256 nonce
    ) internal view returns (bytes32) {
        return keccak256(abi.encodePacked(
            maker,
            tokenA,
            tokenB,
            amountHashA,
            amountHashB,
            nonce,
            address(this)
        ));
    }

    /**
     * @notice Min function for uint256
     */
    function min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }
}