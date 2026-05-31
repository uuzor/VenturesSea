// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/// @dev Test-only registry that exposes every getter shape consumed by the
///      ideafi contracts (FundingPool, BuilderAgreement, RevenueReport,
///      Milestone, IdeaDAO) without requiring the full IdeaFactory deployment.
///      Addresses are set directly by the test harness.
contract MockRegistry {
    struct IdeaAddresses {
        address ideaDAO;
        address fundingPool;
        address builderAgreement;
        address milestoneContract;
        address revenueReport;
        address ideaToken;
    }

    mapping(uint256 => IdeaAddresses) public ideaAddrs;

    // ── Setters (called by test harness) ─────────────────────────────────────

    function setIdeaAddresses(
        uint256 ideaId,
        address ideaDAO,
        address fundingPool,
        address builderAgreement,
        address milestone,
        address revenueReport,
        address ideaToken
    ) external {
        ideaAddrs[ideaId] = IdeaAddresses({
            ideaDAO:          ideaDAO,
            fundingPool:      fundingPool,
            builderAgreement: builderAgreement,
            milestoneContract: milestone,
            revenueReport:    revenueReport,
            ideaToken:        ideaToken
        });
    }

    // ── Getters consumed by contracts ─────────────────────────────────────────

    function getIdeaDAO(uint256 ideaId) external view returns (address) {
        return ideaAddrs[ideaId].ideaDAO;
    }

    function getFundingPool(uint256 ideaId) external view returns (address) {
        return ideaAddrs[ideaId].fundingPool;
    }

    function getBuilderAgreement(uint256 ideaId) external view returns (address) {
        return ideaAddrs[ideaId].builderAgreement;
    }

    function getMilestone(uint256 ideaId) external view returns (address) {
        return ideaAddrs[ideaId].milestoneContract;
    }

    function getRevenueReport(uint256 ideaId) external view returns (address) {
        return ideaAddrs[ideaId].revenueReport;
    }

    // updateStatus called by IdeaDAO.nullifyIdea — no-op in mock
    function updateStatus(uint256, uint8) external {}

    // linkContracts passthrough for IdeaFactory compatibility
    function linkContracts(
        uint256 ideaId,
        address pool,
        address token,
        address builderAgreement,
        address milestone,
        address revenueReport,
        address ideaDAO
    ) external {
        ideaAddrs[ideaId] = IdeaAddresses({
            ideaDAO: ideaDAO,
            fundingPool: pool,
            builderAgreement: builderAgreement,
            milestoneContract: milestone,
            revenueReport: revenueReport,
            ideaToken: token
        });
    }
}
