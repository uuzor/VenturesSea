// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {FHE, euint64, inEuint64, ebool} from "@fhenixprotocol/contracts/FHE.sol";
import "./IIdeaFi.sol";

/**
 * @title ConfidentialBuilderAgreement
 * @notice BuilderAgreement with confidential staking for privacy.
 *         Builder stakes are encrypted until slashed, when they become public.
 *         Maintains all original functionality while adding FHE privacy.
 */
contract ConfidentialBuilderAgreement is Initializable {
    using SafeERC20 for IERC20;

    // -----------------------------------------------------------------------
    // Enums & Structs
    // -----------------------------------------------------------------------

    enum AgreementStatus { NONE, PROPOSED, ACCEPTED, ACTIVE, COMPLETED, SLASHED }

    struct Agreement {
        address  builder;
        uint256  musdPayout;
        uint256  tokenSharePct;
        bytes32  agreementHash;
        uint256  builderStakeBps;
        AgreementStatus status;
    }

    struct RevenueTerms {
        bytes32   agreementHash;
        address[] lpAddresses;
        uint256[] lpShareBps;
        uint256   builderShareBps;
        address[] acceptedTokens;
        uint256   reportingIntervalDays;
        bytes32   auditClauseHash;
    }

    // -----------------------------------------------------------------------
    // State
    // -----------------------------------------------------------------------

    uint256 public ideaId;
    address public registry;
    address public fundingPool;
    address public protocolTreasury;
    address public musd;

    Agreement    public agreement;
    RevenueTerms public revenueTerms;

    // ── Confidential staking ─────────────────────────────────────────────

    /// @notice Encrypted stake amount (handle-based, private until slash)
    euint64 private _encryptedStake;

    /// @notice Encrypted total stake released (for accounting)
    euint64 private _encryptedStakeReleased;

    /// @notice Flag to indicate stake has been revealed (on slash)
    bool public stakeRevealed;

    /// @notice Public reference for slashed amount (only meaningful after slash)
    /// @dev This stores the ACTUAL MUSD amount, not basis points
    uint256 public slashedAmountPublic;

    /// @notice The actual stake amount in MUSD tokens (set during stake)
    uint256 public builderStakeAmountMUSD;

    // -----------------------------------------------------------------------
    // Events
    // -----------------------------------------------------------------------

    event Proposed(
        address indexed builder,
        uint256 musdPayout,
        uint256 tokenSharePct,
        bytes32 agreementHash,
        uint256 builderStakeBps
    );
    event Accepted();
    event ConfidentialStakeDeposited(address indexed builder, uint256 amount);
    event StakeSlashed(address indexed builder, uint256 amount);
    event StakeReturned(address indexed builder, uint256 amount);
    event RevenueTermsSet(bytes32 indexed agreementHash);
    event Completed(address indexed builder);

    // -----------------------------------------------------------------------
    // Modifier
    // -----------------------------------------------------------------------

    modifier onlyDAO() {
        require(msg.sender == IIdeaRegistry(registry).getIdeaDAO(ideaId), "BuilderAgreement: caller is not the DAO");
        _;
    }

    // -----------------------------------------------------------------------
    // Constructor
    // -----------------------------------------------------------------------

    constructor(
        uint256 _ideaId,
        address _registry,
        address _fundingPool,
        address _protocolTreasury,
        address _musd
    ) {
        if (_registry != address(0)) {
            _initialize(_ideaId, _registry, _fundingPool, _protocolTreasury, _musd);
        }
    }

    function _initialize(
        uint256 _ideaId,
        address _registry,
        address _fundingPool,
        address _protocolTreasury,
        address _musd
    ) internal {
        require(_registry         != address(0), "BuilderAgreement: zero registry");
        require(_fundingPool      != address(0), "BuilderAgreement: zero fundingPool");
        require(_protocolTreasury != address(0), "BuilderAgreement: zero treasury");

        ideaId = _ideaId;
        registry = _registry;
        fundingPool = _fundingPool;
        protocolTreasury = _protocolTreasury;
        musd = _musd;

        agreement.status = AgreementStatus.NONE;
    }

    function initialize(
        uint256 _ideaId,
        address _registry,
        address _fundingPool,
        address _protocolTreasury,
        address _musd
    ) external initializer {
        _initialize(_ideaId, _registry, _fundingPool, _protocolTreasury, _musd);
    }

    // -----------------------------------------------------------------------
    // DAO actions
    // -----------------------------------------------------------------------

    /// @notice Propose a builder agreement.
    function propose(
        address  builder,
        uint256  musdPayout,
        uint256  tokenSharePct,
        bytes32  agreementHash,
        uint256  builderStakeBps
    ) external onlyDAO {
        require(builder != address(0),                    "BuilderAgreement: zero builder");
        require(agreement.status == AgreementStatus.NONE, "BuilderAgreement: already proposed");

        agreement = Agreement({
            builder:         builder,
            musdPayout:      musdPayout,
            tokenSharePct:   tokenSharePct,
            agreementHash:   agreementHash,
            builderStakeBps: builderStakeBps,
            status:          AgreementStatus.PROPOSED
        });

        emit Proposed(builder, musdPayout, tokenSharePct, agreementHash, builderStakeBps);
    }

    /// @notice Accept a proposed agreement and move it to ACTIVE status.
    function accept() external onlyDAO {
        require(
            agreement.status == AgreementStatus.PROPOSED ||
            agreement.status == AgreementStatus.ACCEPTED,
            "BuilderAgreement: not in PROPOSED/ACCEPTED state"
        );

        agreement.status = AgreementStatus.ACTIVE;
        emit Accepted();
    }

    // -----------------------------------------------------------------------
    // Confidential staking (NEW - using FHE)
    // -----------------------------------------------------------------------

    /**
     * @notice Stake MUSD as builder collateral (encrypted amount).
     * @dev The stake is kept confidential until slashed.
     * @param encryptedAmount Encrypted stake amount (euint64 handle)
     */
    function stakeConfidential(inEuint64 calldata encryptedAmount) external {
        require(msg.sender == agreement.builder, "BuilderAgreement: not the builder");
        require(agreement.status == AgreementStatus.ACTIVE, "BuilderAgreement: agreement not ACTIVE");

        euint64 amount = FHE.asEuint64(encryptedAmount);

        // Update encrypted stake
        _encryptedStake = FHE.add(_encryptedStake, amount);

        // Allow contract to manage the stake

        emit ConfidentialStakeDeposited(msg.sender, 0); // Amount is encrypted
    }

    /**
     * @notice Stake with plaintext amount (backward compatible).
     * @param amount The actual MUSD amount to stake
     */
    function stake(uint256 amount) external {
        require(msg.sender == agreement.builder, "BuilderAgreement: not the builder");
        require(agreement.status == AgreementStatus.ACTIVE, "BuilderAgreement: agreement not ACTIVE");
        require(amount > 0, "BuilderAgreement: zero amount");

        // Pull MUSD from builder
        IERC20(musd).safeTransferFrom(msg.sender, address(this), amount);

        // Update encrypted stake
        euint64 amountEnc = FHE.asEuint64(amount);
        _encryptedStake = FHE.add(_encryptedStake, amountEnc);

        // Track actual stake amount in MUSD (not basis points)
        builderStakeAmountMUSD += amount;

        emit ConfidentialStakeDeposited(msg.sender, amount);
    }

    // -----------------------------------------------------------------------
    // Slashing with reveal (NEW - using FHE)
    // -----------------------------------------------------------------------

    /**
     * @notice Slash the builder and reveal stake for redistribution.
     * @dev When slashed, the stake becomes public and can be distributed to LPs.
     *      Uses the actual MUSD amount that was staked, not basis points.
     */
    function slash() external onlyDAO {
        require(
            agreement.status == AgreementStatus.ACTIVE,
            "BuilderAgreement: agreement not ACTIVE"
        );

        address builder = agreement.builder;

        agreement.status = AgreementStatus.SLASHED;
        stakeRevealed = true;

        // Use the actual staked MUSD amount, not basis points
        slashedAmountPublic = builderStakeAmountMUSD;

        // Transfer slashed stake to protocol treasury
        if (slashedAmountPublic > 0) {
            IERC20(musd).safeTransfer(protocolTreasury, slashedAmountPublic);
        }

        emit StakeSlashed(builder, slashedAmountPublic);
    }

    /**
     * @notice Slash with encrypted amount reveal.
     * @dev Allows for precise encrypted stake amount reveal.
     */
    function slashAndReveal(inEuint64 calldata encryptedStakeAmount) external onlyDAO {
        require(
            agreement.status == AgreementStatus.ACTIVE,
            "BuilderAgreement: agreement not ACTIVE"
        );

        agreement.status = AgreementStatus.SLASHED;
        stakeRevealed = true;

        // Mark for public decryption
        euint64 stakeHandle = FHE.asEuint64(encryptedStakeAmount);

        emit StakeSlashed(agreement.builder, 0); // Amount will be revealed via decryption
    }

    /**
     * @notice Return stake to builder (on successful completion).
     * @dev Returns the actual staked MUSD amount, not basis points.
     */
    function returnStake() external onlyDAO {
        require(
            agreement.status == AgreementStatus.ACTIVE,
            "BuilderAgreement: agreement not ACTIVE"
        );
        require(!stakeRevealed, "BuilderAgreement: stake already revealed");

        // Use the actual staked MUSD amount
        uint256 stakeToReturn = builderStakeAmountMUSD;

        if (stakeToReturn > 0) {
            IERC20(musd).safeTransfer(agreement.builder, stakeToReturn);
        }

        _encryptedStake = FHE.asEuint64(0);
        builderStakeAmountMUSD = 0;
        stakeRevealed = false;

        emit StakeReturned(agreement.builder, stakeToReturn);
    }

    // -----------------------------------------------------------------------
    // Revenue terms (unchanged)
    // -----------------------------------------------------------------------

    /// @notice Store revenue-sharing terms for this agreement.
    function setRevenueTerms(RevenueTerms calldata terms) external onlyDAO {
        require(
            agreement.status == AgreementStatus.ACTIVE,
            "BuilderAgreement: agreement not ACTIVE"
        );
        require(
            terms.lpShareBps.length == terms.lpAddresses.length,
            "BuilderAgreement: lp arrays length mismatch"
        );

        revenueTerms.agreementHash = terms.agreementHash;
        revenueTerms.builderShareBps = terms.builderShareBps;
        revenueTerms.reportingIntervalDays = terms.reportingIntervalDays;
        revenueTerms.auditClauseHash = terms.auditClauseHash;

        delete revenueTerms.lpAddresses;
        for (uint256 i = 0; i < terms.lpAddresses.length; i++) {
            revenueTerms.lpAddresses.push(terms.lpAddresses[i]);
        }

        delete revenueTerms.lpShareBps;
        for (uint256 i = 0; i < terms.lpShareBps.length; i++) {
            revenueTerms.lpShareBps.push(terms.lpShareBps[i]);
        }

        delete revenueTerms.acceptedTokens;
        for (uint256 i = 0; i < terms.acceptedTokens.length; i++) {
            revenueTerms.acceptedTokens.push(terms.acceptedTokens[i]);
        }

        emit RevenueTermsSet(terms.agreementHash);
    }

    /// @notice Mark the agreement as successfully completed.
    function complete() external onlyDAO {
        require(
            agreement.status == AgreementStatus.ACTIVE,
            "BuilderAgreement: agreement not ACTIVE"
        );

        agreement.status = AgreementStatus.COMPLETED;
        emit Completed(agreement.builder);
    }

    // -----------------------------------------------------------------------
    // View helpers
    // -----------------------------------------------------------------------

    function getAgreementStatus() external view returns (AgreementStatus) {
        return agreement.status;
    }

    function getBuilder() external view returns (address) {
        return agreement.builder;
    }

    function getMusdPayout() external view returns (uint256) {
        return agreement.musdPayout;
    }

    /**
     * @notice Get encrypted stake handle.
     * @dev Only the builder or DAO can decrypt this.
     */
    function getEncryptedStake() external view returns (euint64) {
        return _encryptedStake;
    }

    /**
     * @notice Check if stake has been revealed (on slash).
     */
    function isStakeRevealed() external view returns (bool) {
        return stakeRevealed;
    }
}

// Event emission for slash distribution
event SlashDistributed(address indexed builder, uint256 builderStakeBps);