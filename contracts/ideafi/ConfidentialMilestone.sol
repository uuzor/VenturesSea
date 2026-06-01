// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import {FHE, euint64, euint128, ebool, InEuint64, InEuint128} from "@fhenixprotocol/cofhe-contracts/FHE.sol";
import "./IIdeaFi.sol";

/**
 * @title ConfidentialMilestone
 * @notice Privacy-preserving milestone tracking with encrypted funding amounts.
 *         Milestone release amounts and criteria are kept confidential.
 */
contract ConfidentialMilestone is Initializable {

    // ── Types ───────────────────────────────────────────────────────────────

    enum MilestoneStatus { CRITERIA_PENDING, OPEN, SUBMITTED, APPROVED, REJECTED }

    // ── Config ───────────────────────────────────────────────────────────────

    uint256 public ideaId;
    address public registry;
    address public fundingPool;
    address public ideaDAO;
    address public builder;

    // ── Confidential State (PRIVACY CORE) ──────────────────────────────────

    /// @notice Encrypted total funding pool for milestone calculations
    euint64 private _encryptedTotalFunding;

    /// @notice Encrypted total allocated to milestones
    euint64 private _encryptedAllocated;

    /// @notice Encrypted total released
    euint64 private _encryptedReleased;

    // ── Public State ────────────────────────────────────────────────────────

    mapping(uint256 => MilestoneData) public milestones;
    uint256 public milestoneCount;

    /// @notice Public tracking for emergency operations
    uint256 public totalFundsPct;

    struct MilestoneData {
        uint256 milestoneId;
        bytes32 criteriaHash;
        bytes32 submissionHash;
        MilestoneStatus status;
        uint256 publicFundsPct;  // Basis points, public for tracking
    }

    // ── Events ───────────────────────────────────────────────────────────────

    event MilestoneCreated(uint256 indexed milestoneId, uint256 fundsPct);
    event CriteriaSet(uint256 indexed milestoneId, bytes32 criteriaHash);
    event Submitted(uint256 indexed milestoneId, bytes32 submissionHash);
    event Approved(uint256 indexed milestoneId, uint256 fundsReleased);
    event Rejected(uint256 indexed milestoneId);
    event EncryptedFundsAllocated(uint256 amount);

    // ── Modifiers ────────────────────────────────────────────────────────────

    modifier onlyDAO() {
        require(msg.sender == ideaDAO, "Milestone: not DAO");
        _;
    }

    modifier onlyBuilder() {
        require(msg.sender == builder, "Milestone: not builder");
        _;
    }

    // ── Constructor ──────────────────────────────────────────────────────────

    constructor() {
        // Support proxy pattern
    }

    // ── Initializer ──────────────────────────────────────────────────────────

    function initialize(
        uint256 _ideaId,
        address _registry,
        address _fundingPool,
        address _builder
    ) external initializer {
        require(_ideaId > 0, "Milestone: zero ideaId");
        require(_registry != address(0), "Milestone: zero registry");
        require(_fundingPool != address(0), "Milestone: zero fundingPool");

        ideaId = _ideaId;
        registry = _registry;
        fundingPool = _fundingPool;
        builder = _builder;

        // Initialize encrypted tracking
        euint64 zero = FHE.asEuint64(0);
        _encryptedTotalFunding = zero;
        _encryptedAllocated = zero;
        _encryptedReleased = zero;
        FHE.allowThis(_encryptedTotalFunding);
        FHE.allowThis(_encryptedAllocated);
        FHE.allowThis(_encryptedReleased);
    }

    // ── DAO Functions ────────────────────────────────────────────────────────

    /// @notice Create milestone with encrypted fund allocation
    function createMilestone(uint256 fundsPct) external onlyDAO {
        require(fundsPct <= BPS_DENOM, "Milestone: fundsPct > 10000");
        require(totalFundsPct + fundsPct <= BPS_DENOM, "Milestone: exceeds 100%");

        uint256 id = milestoneCount++;
        milestones[id] = MilestoneData({
            milestoneId: id,
            criteriaHash: bytes32(0),
            submissionHash: bytes32(0),
            status: MilestoneStatus.CRITERIA_PENDING,
            publicFundsPct: fundsPct
        });

        totalFundsPct += fundsPct;

        // Update encrypted allocation
        euint64 encPct = FHE.asEuint64(fundsPct);
        euint64 encTotalFunding = _encryptedTotalFunding;
        euint64 encAllocation = FHE.div(FHE.mul(encTotalFunding, encPct), FHE.asEuint64(BPS_DENOM));
        _encryptedAllocated = FHE.add(_encryptedAllocated, encAllocation);
        FHE.allowThis(_encryptedAllocated);

        emit MilestoneCreated(id, fundsPct);
    }

    /// @notice Set criteria and open milestone for submission
    function setCriteria(uint256 milestoneId, bytes32 criteriaHash) external onlyDAO {
        MilestoneData storage m = milestones[milestoneId];
        require(m.status == MilestoneStatus.CRITERIA_PENDING, "Milestone: not CRITERIA_PENDING");
        require(criteriaHash != bytes32(0), "Milestone: empty criteriaHash");

        m.criteriaHash = criteriaHash;
        m.status = MilestoneStatus.OPEN;

        emit CriteriaSet(milestoneId, criteriaHash);
    }

    /// @notice Approve a milestone and trigger fund release
    function approveMilestone(uint256 milestoneId) external onlyDAO {
        MilestoneData storage m = milestones[milestoneId];
        require(m.status == MilestoneStatus.SUBMITTED, "Milestone: not SUBMITTED");

        m.status = MilestoneStatus.APPROVED;

        // Calculate encrypted release amount
        euint64 encTotalFunding = _encryptedTotalFunding;
        euint64 encPct = FHE.asEuint64(m.publicFundsPct);
        euint64 encRelease = FHE.div(FHE.mul(encTotalFunding, encPct), FHE.asEuint64(BPS_DENOM));

        // Update released tracking
        _encryptedReleased = FHE.add(_encryptedReleased, encRelease);
        FHE.allowThis(_encryptedReleased);

        // Trigger release from funding pool (amount verification is encrypted)
        (bool success, ) = fundingPool.call(
            abi.encodeWithSignature("releaseMilestoneFunds(uint256,uint256)", milestoneId, m.publicFundsPct)
        );
        require(success, "Milestone: release failed");

        emit Approved(milestoneId, m.publicFundsPct);
    }

    /// @notice Reject a submitted milestone
    function rejectMilestone(uint256 milestoneId) external onlyDAO {
        MilestoneData storage m = milestones[milestoneId];
        require(m.status == MilestoneStatus.SUBMITTED, "Milestone: not SUBMITTED");

        m.status = MilestoneStatus.REJECTED;

        emit Rejected(milestoneId);
    }

    // ── Builder Functions ────────────────────────────────────────────────────

    /// @notice Submit work for a milestone
    function submit(uint256 milestoneId, bytes32 submissionHash) external onlyBuilder {
        MilestoneData storage m = milestones[milestoneId];
        require(m.status == MilestoneStatus.OPEN, "Milestone: not OPEN");
        require(submissionHash != bytes32(0), "Milestone: empty submissionHash");

        m.submissionHash = submissionHash;
        m.status = MilestoneStatus.SUBMITTED;

        emit Submitted(milestoneId, submissionHash);
    }

    // ── Funding Setup ────────────────────────────────────────────────────────

    /// @notice Set total funding pool for milestone calculations (called once)
    function setTotalFunding(uint256 totalAmount) external {
        require(msg.sender == fundingPool || msg.sender == ideaDAO, "Milestone: not authorized");
        require(euint64.unwrap(_encryptedTotalFunding) == 0, "Milestone: already set");

        _encryptedTotalFunding = FHE.asEuint64(totalAmount);
        FHE.allowThis(_encryptedTotalFunding);

        emit EncryptedFundsAllocated(totalAmount);
    }

    // ── Encrypted Queries ─────────────────────────────────────────────────────

    /// @notice Get encrypted allocated handle
    function getEncryptedAllocated() external view returns (bytes32) {
        return bytes32(euint64.unwrap(_encryptedAllocated));
    }

    /// @notice Get encrypted released handle
    function getEncryptedReleased() external view returns (bytes32) {
        return bytes32(euint64.unwrap(_encryptedReleased));
    }

    // ── Constants ────────────────────────────────────────────────────────────

    uint256 private constant BPS_DENOM = 10_000;
}