// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title ConfidentialIdeaRegistry
 * @notice Central registry that stores every idea and coordinates deployment
 *         of per-idea confidential contracts via ConfidentialIdeaFactory.
 *         
 *         Supports both standard and FHE-enabled contracts.
 */
contract ConfidentialIdeaRegistry is Ownable {

    // ── Enums ─────────────────────────────────────────────────────────────

    enum IdeaType   { ORIGINAL, REQUESTED }
    enum IdeaStatus { OPEN, BUILDER_SELECTION, ACTIVE, MVP_SUBMITTED, LIVE, CANCELLED }

    // ── Structs ───────────────────────────────────────────────────────────

    struct Idea {
        uint256   ideaId;
        address   creator;
        bytes32   metadataHash;
        IdeaType  ideaType;
        IdeaStatus status;
        address   fundingPool;
        address   ideaToken;
        address   builderAgreement;
        address   milestoneContract;
        address   revenueReport;
        address   ideaDAO;
        uint256   createdAt;
        bool      isConfidential;  // Flag for FHE-enabled contracts
    }

    // ── State ─────────────────────────────────────────────────────────────

    mapping(uint256 => Idea) public ideas;
    uint256 public ideaCount;
    address public factory;
    address public confidentialFactory;

    // ── Events ─────────────────────────────────────────────────────────────

    event IdeaCreated(uint256 indexed ideaId, address indexed creator, IdeaType ideaType, bool isConfidential);
    event StatusUpdated(uint256 indexed ideaId, IdeaStatus status);
    event ContractsLinked(uint256 indexed ideaId);
    event FactorySet(address indexed factory);
    event ConfidentialFactorySet(address indexed factory);

    // ── Modifiers ──────────────────────────────────────────────────────────

    modifier onlyFactory() {
        require(msg.sender == factory || msg.sender == confidentialFactory, 
                "IdeaRegistry: caller is not a factory");
        _;
    }

    modifier ideaExists(uint256 ideaId) {
        require(ideaId > 0 && ideaId <= ideaCount, "IdeaRegistry: idea does not exist");
        _;
    }

    // ── Constructor ──────────────────────────────────────────────────────────

    constructor() Ownable(msg.sender) {}

    // ── Admin ───────────────────────────────────────────────────────────────

    /**
     * @notice Set the standard IdeaFactory address.
     */
    function setFactory(address _factory) external onlyOwner {
        require(_factory != address(0), "IdeaRegistry: zero address");
        factory = _factory;
        emit FactorySet(_factory);
    }

    /**
     * @notice Set the ConfidentialIdeaFactory address.
     */
    function setConfidentialFactory(address _factory) external onlyOwner {
        require(_factory != address(0), "IdeaRegistry: zero address");
        confidentialFactory = _factory;
        emit ConfidentialFactorySet(_factory);
    }

    // ── Idea creation ──────────────────────────────────────────────────────

    /**
     * @notice Submit a new idea with standard (non-FHE) contracts.
     */
    function createIdea(bytes32 metadataHash, IdeaType ideaType) external {
        _createIdeaInternal(metadataHash, ideaType, false);
    }

    /**
     * @notice Submit a new idea with FHE-enabled confidential contracts.
     */
    function createConfidentialIdea(bytes32 metadataHash, IdeaType ideaType) external {
        require(confidentialFactory != address(0), 
                "IdeaRegistry: confidential factory not set");
        _createIdeaInternal(metadataHash, ideaType, true);
    }

    function _createIdeaInternal(bytes32 metadataHash, IdeaType ideaType, bool confidentialMode) internal {
        require(factory != address(0) || confidentialFactory != address(0), 
                "IdeaRegistry: no factory set");

        ideaCount += 1;
        uint256 ideaId = ideaCount;

        ideas[ideaId] = Idea({
            ideaId:           ideaId,
            creator:          msg.sender,
            metadataHash:     metadataHash,
            ideaType:         ideaType,
            status:           IdeaStatus.OPEN,
            fundingPool:      address(0),
            ideaToken:        address(0),
            builderAgreement: address(0),
            milestoneContract: address(0),
            revenueReport:    address(0),
            ideaDAO:          address(0),
            createdAt:        block.timestamp,
            isConfidential:   confidentialMode
        });

        emit IdeaCreated(ideaId, msg.sender, ideaType, confidentialMode);

        // Deploy via appropriate factory
        if (confidentialMode && confidentialFactory != address(0)) {
            // Use interface to call deployIdeaContracts
            (bool success, ) = confidentialFactory.call(
                abi.encodeWithSignature(
                    "deployIdeaContracts(uint256,address,address)",
                    ideaId, msg.sender, address(0)
                )
            );
            require(success, "IdeaRegistry: confidential deployment failed");
        } else if (factory != address(0)) {
            (bool success, ) = factory.call(
                abi.encodeWithSignature(
                    "deployIdeaContracts(uint256,address,address)",
                    ideaId, msg.sender, address(0)
                )
            );
            require(success, "IdeaRegistry: standard deployment failed");
        }
    }

    // ── Factory callback ───────────────────────────────────────────────────

    /**
     * @notice Persist per-idea contract addresses. Only callable by factories.
     */
    function linkContracts(
        uint256 ideaId,
        address pool,
        address token,
        address builderAgreement,
        address milestone,
        address revenueReport,
        address ideaDAO
    )
        external
        onlyFactory
        ideaExists(ideaId)
    {
        Idea storage idea = ideas[ideaId];
        idea.fundingPool       = pool;
        idea.ideaToken         = token;
        idea.builderAgreement  = builderAgreement;
        idea.milestoneContract = milestone;
        idea.revenueReport     = revenueReport;
        idea.ideaDAO           = ideaDAO;

        emit ContractsLinked(ideaId);
    }

    /**
     * @notice Alternative link for confidential contracts (same signature).
     */
    function linkConfidentialContracts(
        uint256 ideaId,
        address pool,
        address token,
        address builderAgreement,
        address milestone,
        address revenueReport,
        address ideaDAO
    )
        external
        onlyFactory
        ideaExists(ideaId)
    {
        Idea storage idea = ideas[ideaId];
        idea.fundingPool       = pool;
        idea.ideaToken         = token;
        idea.builderAgreement  = builderAgreement;
        idea.milestoneContract = milestone;
        idea.revenueReport     = revenueReport;
        idea.ideaDAO           = ideaDAO;

        emit ContractsLinked(ideaId);
    }

    // ── Status updates ────────────────────────────────────────────────────

    /**
     * @notice Transition an idea's status. Only callable by that idea's IdeaDAO.
     */
    function updateStatus(uint256 ideaId, IdeaStatus status)
        external
        ideaExists(ideaId)
    {
        Idea storage idea = ideas[ideaId];
        require(
            msg.sender == idea.ideaDAO,
            "IdeaRegistry: caller is not the idea's IdeaDAO"
        );
        idea.status = status;
        emit StatusUpdated(ideaId, status);
    }

    // ── View ───────────────────────────────────────────────────────────────

    function getIdea(uint256 ideaId) external view ideaExists(ideaId) returns (Idea memory) {
        return ideas[ideaId];
    }

    function getIdeaDAO(uint256 ideaId) external view ideaExists(ideaId) returns (address) {
        return ideas[ideaId].ideaDAO;
    }

    function getFundingPool(uint256 ideaId) external view ideaExists(ideaId) returns (address) {
        return ideas[ideaId].fundingPool;
    }

    function getBuilderAgreement(uint256 ideaId) external view ideaExists(ideaId) returns (address) {
        return ideas[ideaId].builderAgreement;
    }

    function getMilestone(uint256 ideaId) external view ideaExists(ideaId) returns (address) {
        return ideas[ideaId].milestoneContract;
    }

    function getRevenueReport(uint256 ideaId) external view ideaExists(ideaId) returns (address) {
        return ideas[ideaId].revenueReport;
    }

    function isConfidential(uint256 ideaId) external view ideaExists(ideaId) returns (bool) {
        return ideas[ideaId].isConfidential;
    }
}