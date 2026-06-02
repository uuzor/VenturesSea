// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

interface IIdeaRegistry {
    function getIdeaDAO(uint256 ideaId) external view returns (address);
    function getBuilderAgreement(uint256 ideaId) external view returns (address);
    function getMilestone(uint256 ideaId) external view returns (address);
    function getFundingPool(uint256 ideaId) external view returns (address);
    function getRevenueReport(uint256 ideaId) external view returns (address);
    function updateStatus(uint256 ideaId, uint8 status) external;
    function linkContracts(
        uint256 ideaId,
        address pool,
        address token,
        address builderAgreement,
        address milestone,
        address revenueReport,
        address ideaDAO
    ) external;
}

interface IIdeaToken {
    function mint(address to, uint256 amount) external;
    function burn(address from, uint256 amount) external;
    function balanceOf(address account) external view returns (uint256);
}

interface IFundingPool {
    function releaseBuilderFunds(address builder, uint256 amount) external;
    function deposits(address lp) external view returns (uint256);
    function lockPool() external;
    function emergencyRefund() external;
}

interface IBuilderAgreement {
    function getBuilder() external view returns (address);
    function getMusdPayout() external view returns (uint256);
    function propose(
        address builder,
        uint256 musdPayout,
        uint256 tokenSharePct,
        bytes32 agreementHash,
        uint256 stakeBps
    ) external;
    function accept() external;
}

interface IMilestone {
    function approveMilestone(uint256 milestoneId) external;
}

interface IIdeaFactory {
    function deployIdeaContracts(uint256 ideaId, address creator, address musd) external;
}
