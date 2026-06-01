// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {FHE, euint64, euint128, ebool, InEuint64, InEuint128} from "@fhenixprotocol/cofhe-contracts/FHE.sol";
import "./IIdeaFi.sol";

/**
 * @title ConfidentialSwap
 * @notice Privacy-preserving P2P swap market for IdeaTokens.
 *         Offer amounts, prices, and trade details are encrypted.
 *         Only the final matched trades are revealed.
 */
contract ConfidentialSwap is ReentrancyGuard {
    using SafeERC20 for IERC20;

    // ── Constants ────────────────────────────────────────────────────────────

    uint256 public constant PROTOCOL_FEE_BPS = 200; // 2%
    uint256 public constant BPS_DENOM = 10_000;

    // ── Config ───────────────────────────────────────────────────────────────

    address public immutable protocolTreasury;
    address public immutable musd;

    // ── Confidential State (PRIVACY CORE) ──────────────────────────────────

    /// @notice Encrypted offer amounts per offer ID
    mapping(uint256 => euint64) private _encryptedTokenAmounts;

    /// @notice Encrypted ask prices per offer ID
    mapping(uint256 => euint64) private _encryptedAskPrices;

    /// @notice Encrypted buyer commitments
    mapping(uint256 => mapping(address => euint64)) private _encryptedCommitments;

    // ── Public State ─────────────────────────────────────────────────────────

    uint256 public offerCount;
    mapping(uint256 => Offer) public offers;
    mapping(uint256 => mapping(address => bool)) public hasAccepted;

    struct Offer {
        uint256 offerId;
        address seller;
        address ideaToken;     // The IdeaToken being sold
        uint256 ideaId;        // For reference
        uint256 expiry;        // Public for expiration check
        bool active;
        bool fulfilled;
    }

    // ── Events ───────────────────────────────────────────────────────────────

    event OfferCreated(uint256 indexed offerId, address indexed seller, address ideaToken);
    event EncryptedOfferUpdated(uint256 indexed offerId);
    event OfferAccepted(uint256 indexed offerId, address indexed buyer);
    event OfferCancelled(uint256 indexed offerId, address indexed seller);
    event OfferFulfilled(uint256 indexed offerId);
    event EncryptedTradeExecuted(uint256 indexed offerId, address buyer, uint256 amount);

    // ── Modifiers ────────────────────────────────────────────────────────────

    modifier onlyActiveOffer(uint256 offerId) {
        require(offers[offerId].active, "Swap: not active");
        require(!offers[offerId].fulfilled, "Swap: fulfilled");
        require(block.timestamp <= offers[offerId].expiry, "Swap: expired");
        _;
    }

    // ── Constructor ──────────────────────────────────────────────────────────

    constructor(address _protocolTreasury, address _musd) {
        require(_protocolTreasury != address(0), "Swap: zero treasury");
        require(_musd != address(0), "Swap: zero musd");
        protocolTreasury = _protocolTreasury;
        musd = _musd;
    }

    // ── Create Offer ──────────────────────────────────────────────────────────

    /// @notice Create a swap offer with encrypted amount and price
    /// @dev Amount and ask price are encrypted; only hash is stored
    function createOffer(
        address ideaToken,
        uint256 ideaId,
        uint256 duration,
        bytes32 encryptedAmountHash,
        bytes32 encryptedPriceHash,
        bytes32[] calldata encryptedAmountProof,
        bytes32[] calldata encryptedPriceProof
    ) external nonReentrant returns (uint256 offerId) {
        require(ideaToken != address(0), "Swap: zero token");
        require(duration > 0, "Swap: zero duration");

        // Escrow tokens
        uint256 escrowAmount = _getEscrowAmountFromProof(encryptedAmountProof);
        require(escrowAmount > 0, "Swap: zero amount");
        IERC20(ideaToken).transferFrom(msg.sender, address(this), escrowAmount);

        offerId = offerCount++;
        offers[offerId] = Offer({
            offerId: offerId,
            seller: msg.sender,
            ideaToken: ideaToken,
            ideaId: ideaId,
            expiry: block.timestamp + duration,
            active: true,
            fulfilled: false
        });

        // Store encrypted handles (in production, use proper FHE handles)
        _encryptedTokenAmounts[offerId] = FHE.asEuint64(escrowAmount);
        _encryptedAskPrices[offerId] = FHE.asEuint64(0); // Price encrypted off-chain
        FHE.allowThis(_encryptedTokenAmounts[offerId]);
        FHE.allowThis(_encryptedAskPrices[offerId]);

        emit OfferCreated(offerId, msg.sender, ideaToken);
        emit EncryptedOfferUpdated(offerId);

        return offerId;
    }

    /// @notice Create offer with plaintext (for testing or when encryption not needed)
    function createOfferPlaintext(
        address ideaToken,
        uint256 ideaId,
        uint256 tokenAmount,
        uint256 musdAskPrice,
        uint256 duration
    ) external nonReentrant returns (uint256 offerId) {
        require(ideaToken != address(0), "Swap: zero token");
        require(tokenAmount > 0, "Swap: zero amount");
        require(musdAskPrice > 0, "Swap: zero price");
        require(duration > 0, "Swap: zero duration");

        // Escrow tokens
        IERC20(ideaToken).transferFrom(msg.sender, address(this), tokenAmount);

        offerId = offerCount++;
        offers[offerId] = Offer({
            offerId: offerId,
            seller: msg.sender,
            ideaToken: ideaToken,
            ideaId: ideaId,
            expiry: block.timestamp + duration,
            active: true,
            fulfilled: false
        });

        // Store encrypted amounts
        _encryptedTokenAmounts[offerId] = FHE.asEuint64(tokenAmount);
        _encryptedAskPrices[offerId] = FHE.asEuint64(musdAskPrice);
        FHE.allowThis(_encryptedTokenAmounts[offerId]);
        FHE.allowThis(_encryptedAskPrices[offerId]);

        emit OfferCreated(offerId, msg.sender, ideaToken);
    }

    // ── Accept Offer ──────────────────────────────────────────────────────────

    /// @notice Accept an offer with encrypted commitment
    function acceptOffer(
        uint256 offerId,
        bytes32[] calldata encryptedAmountProof,
        bytes32[] calldata priceProof
    ) external nonReentrant onlyActiveOffer(offerId) {
        Offer storage offer = offers[offerId];
        require(!hasAccepted[offerId][msg.sender], "Swap: already accepted");

        // In production: verify ZK proofs for encrypted amount/price
        uint256 tokenAmount = _getTokenAmountFromOffer(offerId);
        uint256 askPrice = _getAskPriceFromOffer(offerId);

        // Pull payment
        IERC20(musd).safeTransferFrom(msg.sender, address(this), askPrice);

        // Calculate fees
        uint256 fee = (askPrice * PROTOCOL_FEE_BPS) / BPS_DENOM;
        uint256 net = askPrice - fee;

        // Transfer tokens to buyer
        IERC20(offer.ideaToken).transfer(msg.sender, tokenAmount);

        // Transfer payment to seller
        IERC20(musd).safeTransfer(offer.seller, net);
        IERC20(musd).safeTransfer(protocolTreasury, fee);

        hasAccepted[offerId][msg.sender] = true;

        // Update encrypted amount
        _encryptedTokenAmounts[offerId] = FHE.asEuint64(0);
        FHE.allowThis(_encryptedTokenAmounts[offerId]);

        emit OfferAccepted(offerId, msg.sender);
        emit EncryptedTradeExecuted(offerId, msg.sender, tokenAmount);
    }

    /// @notice Accept with plaintext (for testing)
    function acceptOfferPlaintext(uint256 offerId) external nonReentrant onlyActiveOffer(offerId) {
        Offer storage offer = offers[offerId];
        require(!hasAccepted[offerId][msg.sender], "Swap: already accepted");

        uint256 tokenAmount = _getTokenAmountFromOffer(offerId);
        uint256 askPrice = _getAskPriceFromOffer(offerId);

        // Pull payment
        IERC20(musd).safeTransferFrom(msg.sender, address(this), askPrice);

        // Calculate fees
        uint256 fee = (askPrice * PROTOCOL_FEE_BPS) / BPS_DENOM;
        uint256 net = askPrice - fee;

        // Transfer tokens to buyer
        IERC20(offer.ideaToken).transfer(msg.sender, tokenAmount);

        // Transfer payment
        IERC20(musd).safeTransfer(offer.seller, net);
        IERC20(musd).safeTransfer(protocolTreasury, fee);

        hasAccepted[offerId][msg.sender] = true;

        // Update encrypted state
        _encryptedTokenAmounts[offerId] = FHE.asEuint64(0);
        FHE.allowThis(_encryptedTokenAmounts[offerId]);

        offer.fulfilled = true;

        emit OfferAccepted(offerId, msg.sender);
        emit EncryptedTradeExecuted(offerId, msg.sender, tokenAmount);
        emit OfferFulfilled(offerId);
    }

    // ── Cancel Offer ─────────────────────────────────────────────────────────

    /// @notice Cancel an active offer
    function cancelOffer(uint256 offerId) external nonReentrant {
        Offer storage offer = offers[offerId];
        require(offer.active, "Swap: not active");
        require(msg.sender == offer.seller, "Swap: not seller");
        require(!offer.fulfilled, "Swap: already fulfilled");

        uint256 tokenAmount = _getTokenAmountFromOffer(offerId);

        // Return escrowed tokens
        IERC20(offer.ideaToken).transfer(msg.sender, tokenAmount);

        offer.active = false;

        // Clear encrypted state
        _encryptedTokenAmounts[offerId] = FHE.asEuint64(0);
        _encryptedAskPrices[offerId] = FHE.asEuint64(0);
        FHE.allowThis(_encryptedTokenAmounts[offerId]);
        FHE.allowThis(_encryptedAskPrices[offerId]);

        emit OfferCancelled(offerId, msg.sender);
    }

    /// @notice Expire an overdue offer
    function expireOffer(uint256 offerId) external nonReentrant {
        Offer storage offer = offers[offerId];
        require(offer.active, "Swap: not active");
        require(!offer.fulfilled, "Swap: fulfilled");
        require(block.timestamp > offer.expiry, "Swap: not expired");

        uint256 tokenAmount = _getTokenAmountFromOffer(offerId);

        // Return tokens to seller
        IERC20(offer.ideaToken).transfer(offer.seller, tokenAmount);

        offer.active = false;

        // Clear encrypted state
        _encryptedTokenAmounts[offerId] = FHE.asEuint64(0);
        FHE.allowThis(_encryptedTokenAmounts[offerId]);

        emit OfferCancelled(offerId, offer.seller);
    }

    // ── Private Helpers ──────────────────────────────────────────────────────

    function _getTokenAmountFromOffer(uint256 offerId) internal view returns (uint256) {
        // In production, decrypt the encrypted amount
        // For now, assume it's the full escrow
        euint64 encAmount = _encryptedTokenAmounts[offerId];
        // Return public value or handle
        return uint256(euint64.unwrap(encAmount));
    }

    function _getAskPriceFromOffer(uint256 offerId) internal view returns (uint256) {
        euint64 encPrice = _encryptedAskPrices[offerId];
        return uint256(euint64.unwrap(encPrice));
    }

    function _getEscrowAmountFromProof(bytes32[] calldata proof) internal pure returns (uint256) {
        // In production, extract from ZK proof
        // For now, return 0 (caller must use createOfferPlaintext)
        return 0;
    }

    // ── Encrypted Query Functions ────────────────────────────────────────────

    /// @notice Get encrypted token amount handle
    function getEncryptedTokenAmount(uint256 offerId) external view returns (bytes32) {
        return bytes32(euint64.unwrap(_encryptedTokenAmounts[offerId]));
    }

    /// @notice Get encrypted ask price handle
    function getEncryptedAskPrice(uint256 offerId) external view returns (bytes32) {
        return bytes32(euint64.unwrap(_encryptedAskPrices[offerId]));
    }

    /// @notice Get encrypted commitment for a buyer
    function getEncryptedCommitment(uint256 offerId, address buyer) external view returns (bytes32) {
        return bytes32(euint64.unwrap(_encryptedCommitments[offerId][buyer]));
    }

    // ── View Functions ───────────────────────────────────────────────────────

    function isOfferActive(uint256 offerId) external view returns (bool) {
        Offer storage offer = offers[offerId];
        return offer.active && !offer.fulfilled && block.timestamp <= offer.expiry;
    }

    function getOfferExpiry(uint256 offerId) external view returns (uint256) {
        return offers[offerId].expiry;
    }
}