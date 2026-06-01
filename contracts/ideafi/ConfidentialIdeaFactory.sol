// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "@openzeppelin/contracts/proxy/Clones.sol";
import "./ConfidentialIdeaToken.sol";
import "./ConfidentialFundingPool.sol";
import "./ConfidentialBuilderAgreement.sol";
import "./ConfidentialIdeaDAO.sol";
import "./ConfidentialRevenueReport.sol";
import "./ConfidentialMilestone.sol";
import "./SimpleOwnable.sol";

/**
 * @title ConfidentialIdeaFactory
 * @notice Deploys the full suite of per-idea contracts via ERC-1167 clones
 *         when IdeaRegistry.createIdea() is called.
 *         
 *         This version deploys FHE-enabled confidential contracts for
 *         enhanced privacy in funding, voting, and revenue reporting.
 */
contract ConfidentialIdeaFactory {

    // ── Master Implementations ─────────────────────────────────────────────

    address public immutable registry;
    address public immutable protocolTreasury;
    address public immutable protocolMarket;
    address public immutable musd;

    // Implementation addresses for cloning
    address public immutable ideaDAOImpl;
    address public immutable fundingPoolImpl;
    address public immutable ideaTokenImpl;
    address public immutable builderAgreementImpl;
    address public immutable milestoneImpl;
    address public immutable revenueReportImpl;

    // -----------------------------------------------------------------------
    // Events
    // -----------------------------------------------------------------------

    event ConfidentialIdeaDeployed(
        uint256 indexed ideaId,
        address token,
        address pool,
        address builderAgreement,
        address milestone,
        address revenueReport,
        address ideaDAO
    );

    // -----------------------------------------------------------------------
    // Modifiers
    // -----------------------------------------------------------------------

    modifier onlyRegistry() {
        require(msg.sender == registry, "IdeaFactory: caller is not the registry");
        _;
    }

    // -----------------------------------------------------------------------
    // Constructor
    // -----------------------------------------------------------------------

    constructor(
        address _registry,
        address _protocolTreasury,
        address _protocolMarket,
        address _musd,
        address _ideaDAOImpl,
        address _fundingPoolImpl,
        address _ideaTokenImpl,
        address _builderAgreementImpl,
        address _milestoneImpl,
        address _revenueReportImpl
    ) {
        require(_registry             != address(0), "IdeaFactory: zero registry");
        require(_protocolTreasury     != address(0), "IdeaFactory: zero treasury");
        require(_protocolMarket       != address(0), "IdeaFactory: zero market");
        require(_musd                 != address(0), "IdeaFactory: zero musd");
        require(_ideaDAOImpl          != address(0), "IdeaFactory: zero dao impl");
        require(_fundingPoolImpl      != address(0), "IdeaFactory: zero pool impl");
        require(_ideaTokenImpl        != address(0), "IdeaFactory: zero token impl");
        require(_builderAgreementImpl != address(0), "IdeaFactory: zero agreement impl");
        require(_milestoneImpl        != address(0), "IdeaFactory: zero milestone impl");
        require(_revenueReportImpl    != address(0), "IdeaFactory: zero report impl");

        registry = _registry;
        protocolTreasury = _protocolTreasury;
        protocolMarket = _protocolMarket;
        musd = _musd;

        ideaDAOImpl = _ideaDAOImpl;
        fundingPoolImpl = _fundingPoolImpl;
        ideaTokenImpl = _ideaTokenImpl;
        builderAgreementImpl = _builderAgreementImpl;
        milestoneImpl = _milestoneImpl;
        revenueReportImpl = _revenueReportImpl;
    }

    // -----------------------------------------------------------------------
    // Core deployment
    // -----------------------------------------------------------------------

    /**
     * @notice Deploy all per-idea contracts via ERC-1167 clones and initialize them.
     * @param ideaId   The idea ID assigned by the registry.
     * @param creator  The address that submitted the idea.
     */
    function deployIdeaContracts(
        uint256 ideaId,
        address creator,
        address /* musd - use contract's musd instead */
    )
        external
        onlyRegistry
    {
        // 1. Create clone instances for all 6 contracts
        address ideaDAO = Clones.clone(ideaDAOImpl);
        address fundingPool = Clones.clone(fundingPoolImpl);
        address ideaToken = Clones.clone(ideaTokenImpl);
        address builderAgreement = Clones.clone(builderAgreementImpl);
        address milestone = Clones.clone(milestoneImpl);
        address revenueReport = Clones.clone(revenueReportImpl);

        // 2. Initialize IdeaDAO first
        ConfidentialIdeaDAO(ideaDAO).initialize(ideaId, registry, ideaToken);

        // 3. Initialize IdeaToken (use initialize for clones)
        string memory tokenName = _ideaTokenName(ideaId);
        string memory tokenSymbol = _ideaTokenSymbol(ideaId);
        ConfidentialIdeaToken(ideaToken).initialize(
            ideaId,
            tokenName,
            tokenSymbol,
            fundingPool,
            ideaDAO,
            protocolMarket
        );

        // 4. Initialize FundingPool (defaults: softCap = 1,000 net, hardCap = 10,000 net, 30 days deadline, 20% builder allocation)
        uint256 softCap = 1_000 * 10**18;
        uint256 hardCap = 10_000 * 10**18;
        uint256 fundingDeadline = block.timestamp + 30 days;
        uint256 builderAllocationPct = 20;

        ConfidentialFundingPool(fundingPool).initialize(
            ideaId,
            musd,
            ideaToken,
            protocolTreasury,
            registry,
            softCap,
            hardCap,
            fundingDeadline,
            builderAllocationPct
        );

        // 5. Initialize BuilderAgreement
        ConfidentialBuilderAgreement(builderAgreement).initialize(
            ideaId, registry, fundingPool, protocolTreasury, musd
        );

        // 6. Initialize Milestone (FHE-enabled confidential milestone)
        ConfidentialMilestone(milestone).initialize(ideaId, registry, fundingPool, address(0));

        // 7. Initialize RevenueReport
        ConfidentialRevenueReport(revenueReport).initialize(ideaId, registry, fundingPool);

        // 8. Register all clone addresses back to the registry
        // Note: Registry interface needs to be updated to accept new contract types
        // For now, we emit the event and the registry can be updated separately
        
        _linkContracts(
            ideaId,
            fundingPool,
            ideaToken,
            builderAgreement,
            milestone,
            revenueReport,
            ideaDAO
        );

        // 9. Emit summary event
        emit ConfidentialIdeaDeployed(
            ideaId,
            ideaToken,
            fundingPool,
            builderAgreement,
            milestone,
            revenueReport,
            ideaDAO
        );
    }

    // -----------------------------------------------------------------------
    // Internal helpers
    // -----------------------------------------------------------------------

    /**
     * @dev Link contracts in the registry (called by registry).
     */
    function _linkContracts(
        uint256 ideaId,
        address pool,
        address token,
        address builderAgreement,
        address milestone,
        address revenueReport,
        address ideaDAO
    ) internal {
        // Call the registry to link contracts
        // The registry should implement IIdeaFi interface
        (bool success, ) = registry.call(
            abi.encodeWithSignature(
                "linkConfidentialContracts(uint256,address,address,address,address,address,address)",
                ideaId, pool, token, builderAgreement, milestone, revenueReport, ideaDAO
            )
        );
        
        // If the registry doesn't support this signature, try the standard one
        if (!success) {
            (success, ) = registry.call(
                abi.encodeWithSignature(
                    "linkContracts(uint256,address,address,address,address,address,address)",
                    ideaId, pool, token, builderAgreement, milestone, revenueReport, ideaDAO
                )
            );
        }
    }

    /**
     * @dev Generate a human-readable token name from the idea ID.
     */
    function _ideaTokenName(uint256 ideaId) internal pure returns (string memory) {
        return string(abi.encodePacked("Confidential Idea #", _toString(ideaId)));
    }

    /**
     * @dev Generate a compact ticker symbol from the idea ID.
     */
    function _ideaTokenSymbol(uint256 ideaId) internal pure returns (string memory) {
        return string(abi.encodePacked("CIDEA", _toString(ideaId)));
    }

    /**
     * @dev Convert uint256 to its decimal string representation.
     */
    function _toString(uint256 value) internal pure returns (string memory) {
        if (value == 0) return "0";
        uint256 temp = value;
        uint256 digits;
        while (temp != 0) {
            digits++;
            temp /= 10;
        }
        bytes memory buffer = new bytes(digits);
        while (value != 0) {
            digits--;
            buffer[digits] = bytes1(uint8(48 + (value % 10)));
            value /= 10;
        }
        return string(buffer);
    }
}