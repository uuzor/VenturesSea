// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "@fhenixprotocol/contracts/FHE.sol";
import "@openzeppelin/contracts/proxy/utils/Initializable.sol";

/**
 * @title ThresholdDecryptor
 * @notice Manages threshold decryption of FHE ciphertexts for authorized reveals.
 *         Implements a guardian-based decryption threshold where a minimum number
 *         of guardians must approve a reveal request before decryption occurs.
 *         
 *         Privacy model:
 *         - Encrypted data stays encrypted until authorized threshold is met
 *         - Guardians can be DAO members, multi-sig holders, or protocol operators
 *         - Reveal conditions can be time-based, event-based, or governance-approved
 *         - Each ciphertext can have custom reveal conditions
 *
 * @dev This contract serves as the privacy gateway for all confidential operations.
 *      All encrypted data that needs to become public goes through this contract.
 */
contract ThresholdDecryptor is Initializable {
    using FHE for *;

    // ── Types ─────────────────────────────────────────────────────────────────

    /// @notice Represents a decryption request
    struct DecryptRequest {
        bytes32 ciphertextHash;      // Hash of the ciphertext to decrypt
        address requester;          // Who requested the decryption
        uint256 conditionType;      // 0=manual, 1=time-based, 2=event-based, 3=governance
        bytes conditionData;        // Condition-specific data
        uint256 approveCount;       // Number of guardian approvals
        uint256 deadline;           // Time by which decryption must occur
        bool executed;              // Whether decryption has been executed
        bool cancelled;             // Whether request was cancelled
        uint256 createdAt;          // Timestamp of creation
    }

    /// @notice Guardian approval record
    struct GuardianApproval {
        bool approved;
        uint256 timestamp;
    }

    /// @notice Reveal condition types
    enum ConditionType {
        Manual,        // Manual reveal by guardians
        TimeBased,     // Automatic after time passes
        EventBased,    // Reveal after certain on-chain event
        Governance     // Reveal after DAO vote
    }

    // ── State ─────────────────────────────────────────────────────────────────

    /// @notice Minimum number of guardian approvals required
    uint256 public minApprovals;

    /// @notice Maximum time a decrypt request can be pending
    uint256 public maxRequestDuration;

    /// @notice List of guardian addresses
    address[] public guardians;

    /// @notice Mapping of guardian addresses to boolean (clean approach)
    mapping(address => bool) public guardianStatus;

    /// @notice Mapping of request ID to DecryptRequest
    mapping(uint256 => DecryptRequest) public decryptRequests;

    /// @notice Mapping of request ID to guardian approvals
    mapping(uint256 => mapping(address => GuardianApproval)) public approvals;

    /// @notice Current request counter
    uint256 public requestCount;

    /// @notice Contract owner for access control
    address public owner;

    /// @notice Mapping of authorized handlers (contracts that can request decryption)
    mapping(address => bool) public authorizedHandlers;

    /// @notice Emitted when a decrypt request is created
    event DecryptRequested(
        uint256 indexed requestId,
        bytes32 indexed ciphertextHash,
        address indexed requester,
        uint256 conditionType
    );

    /// @notice Emitted when a guardian approves a request
    event GuardianApproved(
        uint256 indexed requestId,
        address indexed guardian,
        uint256 newApprovalCount
    );

    /// @notice Emitted when a decrypt request is executed
    event DecryptExecuted(
        uint256 indexed requestId,
        uint256 decryptedValue,
        address indexed recipient
    );

    /// @notice Emitted when a request is cancelled
    event DecryptCancelled(uint256 indexed requestId, address indexed canceller);

    /// @notice Emitted when a guardian is added
    event GuardianAdded(address indexed guardian);

    /// @notice Emitted when a guardian is removed
    event GuardianRemoved(address indexed guardian);

    /// @notice Emitted when authorized handler is updated
    event AuthorizedHandlerUpdated(address indexed handler, bool authorized);

    // ── Errors ─────────────────────────────────────────────────────────────────

    error NotAuthorizedHandler();
    error InvalidGuardian();
    error AlreadyApproved();
    error NotApproved();
    error RequestNotFound();
    error RequestExpired();
    error InsufficientApprovals();
    error AlreadyExecuted();
    error AlreadyCancelled();
    error InvalidConditionType();
    error ConditionNotMet();

    // ── Modifiers ──────────────────────────────────────────────────────────────

    modifier onlyOwner() {
        require(msg.sender == owner, "ThresholdDecryptor: not owner");
        _;
    }

    modifier onlyGuardian() {
        require(guardianStatus[msg.sender], "ThresholdDecryptor: not a guardian");
        _;
    }

    modifier onlyAuthorizedHandler() {
        require(authorizedHandlers[msg.sender], "ThresholdDecryptor: not authorized handler");
        _;
    }

    // ── Initialization ────────────────────────────────────────────────────────

    /**
     * @notice Initialize the threshold decryptor
     * @param _owner Owner address for access control
     * @param _guardians Initial list of guardian addresses
     * @param _minApprovals Minimum approvals required (must be <= guardian count)
     * @param _maxDuration Maximum request duration in seconds
     */
    function initialize(
        address _owner,
        address[] memory _guardians,
        uint256 _minApprovals,
        uint256 _maxDuration
    ) public initializer {
        require(_owner != address(0), "ThresholdDecryptor: zero owner");
        require(_guardians.length > 0, "ThresholdDecryptor: no guardians");
        require(_minApprovals > 0 && _minApprovals <= _guardians.length, 
            "ThresholdDecryptor: invalid approval threshold");
        
        owner = _owner; // Set contract owner
        
        minApprovals = _minApprovals;
        maxRequestDuration = _maxDuration;
        
        // Add guardians
        for (uint256 i = 0; i < _guardians.length; i++) {
            _addGuardian(_guardians[i]);
        }
        
        requestCount = 0;
    }

    // ── Internal Guardian Management ───────────────────────────────────────────

    /**
     * @notice Internal function to add a guardian
     * @param guardian Address to add
     */
    function _addGuardian(address guardian) internal {
        require(guardian != address(0), "ThresholdDecryptor: zero guardian");
        require(!guardianStatus[guardian], "ThresholdDecryptor: already a guardian");
        
        guardianStatus[guardian] = true;
        guardians.push(guardian);
        
        emit GuardianAdded(guardian);
    }

    // ── Guardian Management ─────────────────────────────────────────────────────

    /**
     * @notice Add a new guardian
     * @dev Only owner can call this
     * @param guardian Address to add as guardian
     */
    function addGuardian(address guardian) external onlyOwner {
        _addGuardian(guardian);
    }

    /**
     * @notice Remove a guardian
     * @dev Only owner can call this. Maintains minimum approval threshold.
     * @param guardian Address to remove from guardians
     */
    function removeGuardian(address guardian) external onlyOwner {
        require(guardians.length > minApprovals, "ThresholdDecryptor: cannot remove, minimum reached");
        require(guardianStatus[guardian], "ThresholdDecryptor: not a guardian");
        
        guardianStatus[guardian] = false;
        
        // Find and replace with last element
        for (uint256 i = 0; i < guardians.length; i++) {
            if (guardians[i] == guardian) {
                guardians[i] = guardians[guardians.length - 1];
                guardians.pop();
                break;
            }
        }
        
        emit GuardianRemoved(guardian);
    }

    /**
     * @notice Update minimum approvals required
     * @dev Only owner can call this
     * @param _minApprovals New minimum approval count
     */
    function updateMinApprovals(uint256 _minApprovals) external onlyOwner {
        require(_minApprovals > 0 && _minApprovals <= guardians.length,
            "ThresholdDecryptor: invalid approval threshold");
        minApprovals = _minApprovals;
    }

    /**
     * @notice Update maximum request duration
     * @dev Only owner can call this
     * @param _maxDuration New maximum duration in seconds
     */
    function updateMaxDuration(uint256 _maxDuration) external onlyOwner {
        require(_maxDuration > 0, "ThresholdDecryptor: invalid duration");
        maxRequestDuration = _maxDuration;
    }

    // ── Authorized Handlers ─────────────────────────────────────────────────────

    /**
     * @notice Authorize a contract to request decryption
     * @dev Only owner can call this
     * @param handler Contract address to authorize
     * @param authorized True to authorize, false to revoke
     */
    function setAuthorizedHandler(address handler, bool authorized) external onlyOwner {
        require(handler != address(0), "ThresholdDecryptor: zero handler");
        authorizedHandlers[handler] = authorized;
        emit AuthorizedHandlerUpdated(handler, authorized);
    }

    // ── Decryption Request Management ──────────────────────────────────────────

    /**
     * @notice Create a new decryption request
     * @param ciphertextHash Hash of the ciphertext to decrypt
     * @param conditionType Type of reveal condition
     * @param conditionData Condition-specific data (encoded)
     * @return requestId ID of the created request
     */
    function requestDecrypt(
        bytes32 ciphertextHash,
        uint256 conditionType,
        bytes calldata conditionData
    ) external onlyAuthorizedHandler returns (uint256) {
        require(conditionType <= uint256(ConditionType.Governance), "ThresholdDecryptor: invalid condition");
        
        uint256 requestId = requestCount++;
        
        decryptRequests[requestId] = DecryptRequest({
            ciphertextHash: ciphertextHash,
            requester: msg.sender,
            conditionType: conditionType,
            conditionData: conditionData,
            approveCount: 0,
            deadline: block.timestamp + maxRequestDuration,
            executed: false,
            cancelled: false,
            createdAt: block.timestamp
        });
        
        emit DecryptRequested(requestId, ciphertextHash, msg.sender, conditionType);
        
        return requestId;
    }

    /**
     * @notice Approve a decryption request (guardian action)
     * @param requestId ID of the request to approve
     */
    function approveDecrypt(uint256 requestId) external onlyGuardian {
        DecryptRequest storage request = decryptRequests[requestId];
        
        if (request.ciphertextHash == bytes32(0)) revert RequestNotFound();
        if (request.executed) revert AlreadyExecuted();
        if (request.cancelled) revert AlreadyCancelled();
        if (block.timestamp > request.deadline) revert RequestExpired();
        
        GuardianApproval storage approval = approvals[requestId][msg.sender];
        if (approval.approved) revert AlreadyApproved();
        
        approval.approved = true;
        approval.timestamp = block.timestamp;
        request.approveCount++;
        
        emit GuardianApproved(requestId, msg.sender, request.approveCount);
    }

    /**
     * @notice Revoke approval for a decryption request
     * @param requestId ID of the request to revoke
     */
    function revokeApproval(uint256 requestId) external onlyGuardian {
        DecryptRequest storage request = decryptRequests[requestId];
        
        if (request.ciphertextHash == bytes32(0)) revert RequestNotFound();
        if (request.executed) revert AlreadyExecuted();
        
        GuardianApproval storage approval = approvals[requestId][msg.sender];
        if (!approval.approved) revert NotApproved();
        
        approval.approved = false;
        request.approveCount--;
        
        emit GuardianApproved(requestId, msg.sender, request.approveCount);
    }

    /**
     * @notice Cancel a decryption request
     * @param requestId ID of the request to cancel
     */
    function cancelRequest(uint256 requestId) external {
        DecryptRequest storage request = decryptRequests[requestId];
        
        if (request.ciphertextHash == bytes32(0)) revert RequestNotFound();
        if (request.executed) revert AlreadyExecuted();
        if (request.cancelled) revert AlreadyCancelled();
        
        // Only requester, owner, or all guardians can cancel
        bool canCancel = msg.sender == owner || msg.sender == request.requester;
        
        if (!canCancel) {
            // Check if all guardians have revoked
            uint256 revokedCount = 0;
            for (uint256 i = 0; i < guardians.length; i++) {
                if (!approvals[requestId][guardians[i]].approved) {
                    revokedCount++;
                }
            }
            canCancel = (revokedCount == guardians.length);
        }
        
        require(canCancel, "ThresholdDecryptor: cannot cancel");
        
        request.cancelled = true;
        
        emit DecryptCancelled(requestId, msg.sender);
    }

    /**
     * @notice Execute a decryption request if conditions are met
     * @param requestId ID of the request to execute
     * @return success Whether the decryption was successful
     */
    function executeDecrypt(uint256 requestId) external onlyAuthorizedHandler returns (bool) {
        DecryptRequest storage request = decryptRequests[requestId];
        
        if (request.ciphertextHash == bytes32(0)) revert RequestNotFound();
        if (request.executed) revert AlreadyExecuted();
        if (request.cancelled) revert AlreadyCancelled();
        if (request.approveCount < minApprovals) revert InsufficientApprovals();
        if (block.timestamp > request.deadline) revert RequestExpired();
        
        // Check condition
        if (!_checkCondition(request)) revert ConditionNotMet();
        
        request.executed = true;
        
        emit DecryptExecuted(requestId, 0, request.requester);
        
        return true;
    }

    /**
     * @notice Execute with a specific decrypted value (for testing)
     * @dev In production, the actual decryption happens off-chain or via precompile
     * @param requestId ID of the request
     * @param decryptedValue The decrypted value to emit
     * @param recipient Who receives the decrypted value
     */
    function executeDecryptWithValue(
        uint256 requestId,
        uint256 decryptedValue,
        address recipient
    ) external onlyAuthorizedHandler returns (bool) {
        DecryptRequest storage request = decryptRequests[requestId];
        
        if (request.ciphertextHash == bytes32(0)) revert RequestNotFound();
        if (request.executed) revert AlreadyExecuted();
        if (request.cancelled) revert AlreadyCancelled();
        if (request.approveCount < minApprovals) revert InsufficientApprovals();
        
        request.executed = true;
        
        emit DecryptExecuted(requestId, decryptedValue, recipient);
        
        return true;
    }

    // ── Condition Checking ─────────────────────────────────────────────────────

    /**
     * @notice Check if a condition is met for a decrypt request
     * @param request The decrypt request to check
     * @return satisfied Whether the condition is satisfied
     */
    function _checkCondition(DecryptRequest storage request) internal view returns (bool) {
        ConditionType condType = ConditionType(request.conditionType);
        
        if (condType == ConditionType.Manual) {
            // Manual: just needs approval threshold
            return true;
        } else if (condType == ConditionType.TimeBased) {
            // Time-based: must wait until deadline
            return block.timestamp >= request.createdAt + abi.decode(request.conditionData, (uint256));
        } else if (condType == ConditionType.EventBased) {
            // Event-based: check if event has occurred (custom logic per event)
            // For now, assume event-based means governance has voted
            return request.approveCount >= minApprovals;
        } else if (condType == ConditionType.Governance) {
            // Governance: requires supermajority (2x minimum)
            return request.approveCount >= minApprovals * 2;
        }
        
        return false;
    }

    // ── View Functions ──────────────────────────────────────────────────────────

    /**
     * @notice Get guardian count
     * @return Number of guardians
     */
    function getGuardianCount() external view returns (uint256) {
        return guardians.length;
    }

    /**
     * @notice Check if an address is a guardian
     * @param account Address to check
     * @return Whether the address is a guardian
     */
    function checkGuardian(address account) external view returns (bool) {
        return guardianStatus[account];
    }

    /**
     * @notice Check if a request has sufficient approvals
     * @param requestId ID of the request to check
     * @return Whether the request has sufficient approvals
     */
    function hasSufficientApprovals(uint256 requestId) external view returns (bool) {
        DecryptRequest storage request = decryptRequests[requestId];
        return request.approveCount >= minApprovals;
    }

    /**
     * @notice Get request details
     * @param requestId ID of the request
     * @return ciphertextHash All details of the request
    @return requester
     */
    function getRequest(uint256 requestId) external view returns (
        bytes32 ciphertextHash,
        address requester,
        uint256 conditionType,
        uint256 approveCount,
        uint256 deadline,
        bool executed,
        bool cancelled
    ) {
        DecryptRequest storage request = decryptRequests[requestId];
        return (
            request.ciphertextHash,
            request.requester,
            request.conditionType,
            request.approveCount,
            request.deadline,
            request.executed,
            request.cancelled
        );
    }

    // ── End of Contract ───────────────────────────────────────────────────────
}