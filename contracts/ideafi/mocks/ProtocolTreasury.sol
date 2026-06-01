// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/**
 * @title ProtocolTreasury
 * @notice Mock treasury for testing
 */
contract ProtocolTreasury {
    address public immutable multisig;
    uint256 public immutable minSigners;

    mapping(address => bool) public isSigner;
    mapping(address => uint256) public withdrawalRequests;

    constructor(address[] memory _signers, uint256 _minSigners) {
        require(_minSigners <= _signers.length, "Invalid min signers");
        multisig = msg.sender;
        minSigners = _minSigners;
        for (uint256 i = 0; i < _signers.length; i++) {
            isSigner[_signers[i]] = true;
        }
    }

    receive() external payable {}

    function withdrawTo(address payable recipient, uint256 amount) external {
        require(msg.sender == multisig, "Only multisig");
        require(address(this).balance >= amount, "Insufficient balance");
        (bool success, ) = recipient.call{value: amount}("");
        require(success, "Transfer failed");
    }

    function getBalance() external view returns (uint256) {
        return address(this).balance;
    }
}