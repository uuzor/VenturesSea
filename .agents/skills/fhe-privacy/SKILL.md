# FHE Privacy Skill for VenturesSea

FHE (Fully Homomorphic Encryption) privacy implementation skill for confidential smart contracts on Fhenix/Arbitrum using the CoFHE stack.

## Quick Reference

### Required Imports
```solidity
import "@fhenixprotocol/cofhe-contracts/FHE.sol";
import {InEuint128} from "@fhenixprotocol/cofhe-contracts/ICofhe.sol";
```

### Core Access Functions

| Function | Purpose | When to Use |
|----------|---------|-------------|
| `FHE.allow(value, address)` | Grant specific address access | Sharing with other contracts/users |
| `FHE.allowSender(value)` | Grant caller access (efficient) | Creating/returning user data |
| `FHE.allowThis(value)` | Grant contract access | Storing for later contract use |
| `FHE.allowTransient(value, address)` | Temporary access (1 tx) | One-time operations |

### FHE Types

- `euint128` - Encrypted 128-bit integer (for balances, amounts)
- `euint64` - Encrypted 64-bit integer (for counts, percentages)
- `ebool` - Encrypted boolean (for conditions)
- `InEuint128` - Input struct from SDK (for encrypted params)

### Type Selection

Choose bit length based on data range:
- `euint128` → balances (up to ~3.4e38)
- `euint64` → counts, percentages (up to ~1.8e19)
- `euint32` → small integers (up to ~4.2e9)

## Contract Patterns

### Pattern 1: Encrypted Balance with Plaintext Composability

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {FHE, euint128} from "@fhenixprotocol/cofhe-contracts/FHE.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract ConfidentialToken is ERC20 {
    mapping(address => euint128) private _encryptedBalances;
    
    // Mint with encryption
    function mint(address to, uint256 amount) external {
        _mint(to, amount);
        
        // Update encrypted balance
        euint128 encAmount = FHE.asEuint128(amount);
        _encryptedBalances[to] = FHE.add(_encryptedBalances[to], encAmount);
        FHE.allowThis(_encryptedBalances[to]);  // Allow contract to access
    }
    
    // Encrypted balance query
    function getEncryptedBalance(address account) external view returns (euint128) {
        return _encryptedBalances[account];
    }
    
    // Permissioned disclosure
    function discloseTo(address recipient) external {
        FHE.allow(_encryptedBalances[msg.sender], recipient);
    }
}
```

### Pattern 2: Conditional Release (Threshold)

```solidity
function releaseFundsIfThresholdMet(
    euint128 currentVotes, 
    euint128 threshold,
    address recipient
) external {
    ebool canRelease = FHE.gte(currentVotes, threshold);
    euint128 amount = FHE.select(canRelease, allocatedAmount, FHE.asEuint128(0));
    
    if (FHE.decrypt(canRelease)) {
        FHE.allow(amount, recipient);
    }
}
```

### Pattern 3: Multi-Transaction Decryption

```solidity
// Step 1: User encrypts vote and sends
await contract.castVote(proposalId, true, encryptedAmount);

// Step 2: After voting period, anyone requests decryption
await contract.requestVoteDecryption(proposalId);

// Step 3: Threshold validator decrypts
// Contract receives decrypted result for processing
```

## Best Practices

1. **Storage Pattern**: Always use `FHE.allowThis()` on encrypted storage variables
2. **Access Control**: Grant permissions explicitly before decryption
3. **Type Selection**: Use smallest sufficient bit length
4. **Error Handling**: Use `FHE.select()` instead of `if` with `ebool`
5. **Permission Revocation**: Use transient for one-time permissions

## Testing with Hardhat

```javascript
const { CofheClient, Encryptable, FheTypes } = require('@cofhe/sdk');

describe('Confidential Contract', () => {
  let cofheClient;
  
  before(async () => {
    [signer] = await hre.ethers.getSigners();
    cofheClient = await hre.cofhe.createClientWithBatteries(signer);
  });
  
  it('encrypts and sends', async () => {
    const [encrypted] = await cofheClient.encryptInputs([
      Encryptable.uint128(1000n)
    ]).execute();
    
    await contract.deposit(encrypted);
  });
  
  it('decrypts result', async () => {
    const handle = await contract.getEncryptedBalance(user);
    const balance = await cofheClient.decryptForView(handle, FheTypes.Uint128).execute();
    console.log(balance); // 1000n
  });
});
```

## Network Configuration

### Arbitrum Mainnet Fork (for testing)
```javascript
// hardhat.config.js
networks: {
  arb_fork: {
    url: "https://arb-mainnet.g.alchemy.com/v2/YOUR_KEY",
    chainId: 42161,
    forking: { url: "https://arb-mainnet.g.alchemy.com/v2/YOUR_KEY" }
  }
}
```

## Contract Deployment Checklist

- [ ] Import FHE.sol and ICofhe.sol
- [ ] Add `using FHE for *;` directive
- [ ] Use initializer pattern for clones (ERC-1167)
- [ ] Apply `FHE.allowThis()` to all encrypted storage
- [ ] Apply `FHE.allow()` before returning encrypted values
- [ ] Use `FHE.select()` for conditional logic
- [ ] Test on arb-fork before mainnet deployment

## Privacy Guarantees

### What FHE Protects
- ✅ Deposit amounts hidden from other users
- ✅ Token balances private until explicitly shared
- ✅ Vote counts hidden during voting period
- ✅ Revenue amounts private until threshold reached

### What FHE Does NOT Protect
- ❌ Transaction sender visibility (use stealth addresses)
- ❌ Timing correlation (batch transactions)
- ❌ Dusting attacks (use minimum thresholds)

## References

- [CoFHE SDK](https://cofhe-docs.fhenix.zone/client-sdk/quick-start/javascript)
- [Hardhat Plugin](https://cofhe-docs.fhenix.zone/client-sdk/hardhat-plugin/getting-started)
- [FHE Assistant](https://github.com/marronjo/fhe-assistant/blob/main/core.md)