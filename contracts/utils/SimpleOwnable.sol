// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/**
 * @title SimpleOwnable
 * @notice A minimal, clone-compatible ownership contract.
 *         Replaces OpenZeppelin's standard constructor-based Ownable to support ERC-1167 clones.
 */
abstract contract SimpleOwnable {
    address private _owner;

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    /**
     * @dev Returns the address of the current owner.
     */
    function owner() public view virtual returns (address) {
        return _owner;
    }

    /**
     * @dev Throws if called by any account other than the owner.
     */
    modifier onlyOwner() {
        require(owner() == msg.sender, "SimpleOwnable: caller is not the owner");
        _;
    }

    /**
     * @dev Initializes the contract owner. Can only be called once.
     */
    function _initializeOwner(address initialOwner) internal {
        require(_owner == address(0), "SimpleOwnable: already initialized");
        require(initialOwner != address(0), "SimpleOwnable: zero address");
        _owner = initialOwner;
        emit OwnershipTransferred(address(0), initialOwner);
    }

    /**
     * @dev Transfers ownership of the contract to a new account (`newOwner`).
     *      Can only be called by the current owner.
     */
    function transferOwnership(address newOwner) public virtual onlyOwner {
        require(newOwner != address(0), "SimpleOwnable: new owner is the zero address");
        emit OwnershipTransferred(_owner, newOwner);
        _owner = newOwner;
    }
}
