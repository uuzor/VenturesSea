// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

contract EncryptedSwap is Initializable {
    address public thresholdDecryptor;
    address public feeRecipient;
    uint256 public feePercentage;
    mapping(address => bool) public supportedTokens;
    
    struct Offer {
        address tokenA;
        address tokenB;
        bytes encryptedAmountA;
        bytes encryptedAmountB;
        uint256 minFillPct;
        uint256 deadline;
        address maker;
        bool filled;
    }
    
    Offer[] public offers;
    uint256 public offerCount;
    
    function initialize(address _thresholdDecryptor, address _feeRecipient, uint256 _feePercentage) external initializer {
        thresholdDecryptor = _thresholdDecryptor;
        feeRecipient = _feeRecipient;
        feePercentage = _feePercentage;
        offerCount = 0;
    }
    
    function addSupportedToken(address token) external {
        supportedTokens[token] = true;
    }
    
    function createOffer(
        address tokenA,
        address tokenB,
        bytes memory encryptedAmountA,
        bytes memory encryptedAmountB,
        uint256 minFillPct,
        uint256 deadline,
        address
    ) external returns (bytes32) {
        require(supportedTokens[tokenA] && supportedTokens[tokenB], "Unsupported token");
        
        offers.push(Offer({
            tokenA: tokenA,
            tokenB: tokenB,
            encryptedAmountA: encryptedAmountA,
            encryptedAmountB: encryptedAmountB,
            minFillPct: minFillPct,
            deadline: deadline,
            maker: msg.sender,
            filled: false
        }));
        
        offerCount++;
        
        return keccak256(abi.encode(
            tokenA, tokenB, encryptedAmountA, encryptedAmountB,
            minFillPct, deadline, msg.sender, offers.length - 1
        ));
    }
    
    function getOfferCount() external view returns (uint256) {
        return offerCount;
    }
}
