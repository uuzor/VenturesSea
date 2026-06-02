// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import "../interfaces/IIdeaFi.sol";

// ---------------------------------------------------------------------------
// Milestone
// ---------------------------------------------------------------------------

contract Milestone is Initializable {
    // -----------------------------------------------------------------------
    // Types
    // -----------------------------------------------------------------------

    enum MilestoneStatus {
        CRITERIA_PENDING,
        OPEN,
        SUBMITTED,
        APPROVED,
        REJECTED
    }

    struct MilestoneData {
        uint256 milestoneId;
        bytes32 criteriaHash;
        bytes32 submissionHash;
        MilestoneStatus status;
        uint256 fundsPct; // basis points out of 10000
    }

    // -----------------------------------------------------------------------
    // State
    // -----------------------------------------------------------------------

    uint256 public ideaId;
    address public registry;
    address public fundingPool;

    uint256 public milestoneCount;
    mapping(uint256 => MilestoneData) public milestones;

    // -----------------------------------------------------------------------
    // Events
    // -----------------------------------------------------------------------

    event MilestoneCreated(uint256 indexed milestoneId, uint256 fundsPct);
    event CriteriaSet(uint256 indexed milestoneId, bytes32 criteriaHash);
    event Submitted(uint256 indexed milestoneId, bytes32 submissionHash);
    event Approved(uint256 indexed milestoneId, uint256 fundsReleased);
    event Rejected(uint256 indexed milestoneId);

    // -----------------------------------------------------------------------
    // Modifiers
    // -----------------------------------------------------------------------

    modifier onlyDAO() {
        address dao = IIdeaRegistry(registry).getIdeaDAO(ideaId);
        require(msg.sender == dao, "Milestone: caller is not the DAO");
        _;
    }

    modifier onlyBuilder() {
        address agreementAddr = IIdeaRegistry(registry).getBuilderAgreement(ideaId);
        require(agreementAddr != address(0), "Milestone: no builder agreement");
        address builderAddr = IBuilderAgreement(agreementAddr).getBuilder();
        require(msg.sender == builderAddr, "Milestone: caller is not the builder");
        _;
    }

    // -----------------------------------------------------------------------
    // Constructor (supports both direct deployment and proxy pattern)
    // -----------------------------------------------------------------------

    /**
     * @dev Flexible constructor for both direct deployment and proxy patterns.
     *      For direct deployment (tests): pass all initialization arguments
     *      For proxy pattern: pass zero registry and use initialize() afterwards
     */
    constructor(uint256 _ideaId, address _registry, address _fundingPool) {
        if (_registry != address(0)) {
            _initialize(_ideaId, _registry, _fundingPool);
        }
        // For proxy pattern, constructor does nothing - use initialize() instead
    }

    function _initialize(uint256 _ideaId, address _registry, address _fundingPool) internal {
        ideaId = _ideaId;
        registry = _registry;
        fundingPool = _fundingPool;
    }

    // -----------------------------------------------------------------------
    // Initializer (for proxy pattern)
    // -----------------------------------------------------------------------

    function initialize(uint256 _ideaId, address _registry, address _fundingPool) external initializer {
        require(_registry != address(0), "Milestone: zero registry");
        require(_fundingPool != address(0), "Milestone: zero fundingPool");
        _initialize(_ideaId, _registry, _fundingPool);
    }

    // -----------------------------------------------------------------------
    // DAO functions
    // -----------------------------------------------------------------------

    /// @notice Create a new milestone in CRITERIA_PENDING state.
    function createMilestone(uint256 fundsPct) external onlyDAO {
        require(fundsPct <= 10000, "Milestone: fundsPct > 10000");
        uint256 id = milestoneCount++;
        milestones[id] = MilestoneData({
            milestoneId: id,
            criteriaHash: bytes32(0),
            submissionHash: bytes32(0),
            status: MilestoneStatus.CRITERIA_PENDING,
            fundsPct: fundsPct
        });
        emit MilestoneCreated(id, fundsPct);
    }

    /// @notice Set acceptance criteria for a milestone and open it for submission.
    function setCriteria(uint256 milestoneId, bytes32 criteriaHash) external onlyDAO {
        MilestoneData storage m = milestones[milestoneId];
        require(m.status == MilestoneStatus.CRITERIA_PENDING, "Milestone: not in CRITERIA_PENDING");
        require(criteriaHash != bytes32(0), "Milestone: empty criteriaHash");
        m.criteriaHash = criteriaHash;
        m.status = MilestoneStatus.OPEN;
        emit CriteriaSet(milestoneId, criteriaHash);
    }

    /// @notice Approve a milestone.
    function approveMilestone(uint256 milestoneId) external onlyDAO {
        MilestoneData storage m = milestones[milestoneId];
        require(m.status == MilestoneStatus.SUBMITTED, "Milestone: not SUBMITTED");
        m.status = MilestoneStatus.APPROVED;

        // Calculate amount to release from builder allocation
        address agreementAddr = IIdeaRegistry(registry).getBuilderAgreement(ideaId);
        address builderAddr = IBuilderAgreement(agreementAddr).getBuilder();
        uint256 musdPayout = IBuilderAgreement(agreementAddr).getMusdPayout();
        uint256 releaseAmount = (musdPayout * m.fundsPct) / 10000;

        IFundingPool(fundingPool).releaseBuilderFunds(builderAddr, releaseAmount);
        emit Approved(milestoneId, releaseAmount);
    }

    /// @notice Reject a submitted milestone.
    function rejectMilestone(uint256 milestoneId) external onlyDAO {
        MilestoneData storage m = milestones[milestoneId];
        require(m.status == MilestoneStatus.SUBMITTED, "Milestone: not SUBMITTED");
        m.status = MilestoneStatus.REJECTED;
        emit Rejected(milestoneId);
    }

    // -----------------------------------------------------------------------
    // Builder functions
    // -----------------------------------------------------------------------

    /// @notice Submit work for a milestone.
    function submit(uint256 milestoneId, bytes32 submissionHash) external onlyBuilder {
        MilestoneData storage m = milestones[milestoneId];
        require(m.status == MilestoneStatus.OPEN, "Milestone: not OPEN");
        require(submissionHash != bytes32(0), "Milestone: empty submissionHash");
        m.submissionHash = submissionHash;
        m.status = MilestoneStatus.SUBMITTED;
        emit Submitted(milestoneId, submissionHash);
    }
}
