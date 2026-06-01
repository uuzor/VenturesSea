// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

contract ThresholdDecryptor is Initializable {
    address public owner;
    address[] public guardians;
    uint256 public minApprovals;
    uint256 public approvalWindow;
    uint256 public requestCount;
    
    mapping(uint256 => bytes32) public decryptionRequests;
    mapping(uint256 => mapping(address => bool)) public approvals;
    mapping(address => bool) public authorizedHandlers;
    
    event DecryptRequestCreated(uint256 indexed requestId, bytes32 ciphertextHash);
    event DecryptApproved(uint256 indexed requestId, address indexed guardian);
    event DecryptionCompleted(uint256 indexed requestId);
    
    function initialize(address _owner, address[] memory _guardians, uint256 _minApprovals, uint256 _approvalWindow) external initializer {
        owner = _owner;
        guardians = _guardians;
        minApprovals = _minApprovals;
        approvalWindow = _approvalWindow;
        requestCount = 0;
    }
    
    function getGuardianCount() external view returns (uint256) {
        return guardians.length;
    }
    
    function setAuthorizedHandler(address handler, bool authorized) external {
        require(msg.sender == owner, "Not owner");
        authorizedHandlers[handler] = authorized;
    }
    
    function requestDecrypt(bytes32 ciphertextHash, uint256, bytes calldata) external returns (uint256) {
        uint256 requestId = requestCount++;
        decryptionRequests[requestId] = ciphertextHash;
        emit DecryptRequestCreated(requestId, ciphertextHash);
        return requestId;
    }
    
    function approveDecrypt(uint256 requestId) external {
        require(decryptionRequests[requestId] != bytes32(0), "Invalid request");
        approvals[requestId][msg.sender] = true;
        emit DecryptApproved(requestId, msg.sender);
    }
    
    function hasSufficientApprovals(uint256 requestId) external view returns (bool) {
        uint256 approvalCount = 0;
        for (uint256 i = 0; i < guardians.length; i++) {
            if (approvals[requestId][guardians[i]]) {
                approvalCount++;
            }
        }
        return approvalCount >= minApprovals;
    }
}
