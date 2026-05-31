/**
 * CoFHE SDK Integration Guide for VenturesSea
 * 
 * This document explains how to integrate Fully Homomorphic Encryption (FHE)
 * into the VenturesSea frontend using the @cofhe/sdk package.
 */

// ── Installation ─────────────────────────────────────────────────────────────

/**
 * Required packages:
 * 
 * npm install @cofhe/sdk@^0.5.2 @cofhe/sdk/web  (for browser)
 * npm install @cofhe/sdk@^0.5.2 @cofhe/sdk/node (for Node.js)
 * npm install @fhenixprotocol/contracts@^0.1.3 (for contract ABIs)
 */

// ── Quick Reference ───────────────────────────────────────────────────────────

/**
 * 1. Creating a FHE Client
 * 
 * import { createCofheConfig, createCofheClient } from '@cofhe/sdk/web';
 * import { chains } from '@cofhe/sdk/chains';
 * 
 * const config = createCofheConfig({
 *   supportedChains: [chains.sepolia, chains.fhenix],
 * });
 * 
 * const client = createCofheClient(config);
 */

// ── Encrypting Inputs ─────────────────────────────────────────────────────────

/**
 * 2. Encrypting Values for Contract Calls
 * 
 * import { Encryptable, FheTypes } from '@cofhe/sdk';
 * 
 * // Connect to wallet
 * await client.connect(publicClient, walletClient);
 * 
 * // Encrypt values (generates ZK proof)
 * const [encryptedAmount] = await client
 *   .encryptInputs([Encryptable.uint128(1000n)])
 *   .execute();
 * 
 * // Use in contract call
 * await contract.write.deposit({ encryptedAmount });
 */

// ── Decrypting for View ───────────────────────────────────────────────────────

/**
 * 3. Decrypting Values for UI Display
 * 
 * // Create permit (one-time setup)
 * await client.permits.getOrCreateSelfPermit();
 * 
 * // Read encrypted value from contract
 * const ctHash = await contract.read.getMyBalance();
 * 
 * // Decrypt locally (never published on-chain)
 * const balance = await client
 *   .decryptForView(ctHash, FheTypes.Uint128)
 *   .execute();
 * 
 * console.log('Balance:', balance); // e.g., 1000000000000000000n
 */

// ── Encryptable Types ─────────────────────────────────────────────────────────

/**
 * Available types for encryption:
 * 
 * Encryptable.bool(true/false)      → FheTypes.Bool      → InEbool
 * Encryptable.uint8(value)          → FheTypes.Uint8     → InEuint8
 * Encryptable.uint16(value)         → FheTypes.Uint16    → InEuint16
 * Encryptable.uint32(value)         → FheTypes.Uint32    → InEuint32
 * Encryptable.uint64(value)         → FheTypes.Uint64    → InEuint64
 * Encryptable.uint128(value)        → FheTypes.Uint128   → InEuint128
 * Encryptable.address(value)        → FheTypes.Uint160   → InEaddress
 */

// ── Decrypt Types ─────────────────────────────────────────────────────────────

/**
 * Supported decryption types (FheTypes):
 * 
 * FheTypes.Bool     → returns boolean
 * FheTypes.Uint8    → returns bigint
 * FheTypes.Uint16   → returns bigint
 * FheTypes.Uint32   → returns bigint
 * FheTypes.Uint64   → returns bigint
 * FheTypes.Uint128  → returns bigint
 * FheTypes.Uint160  → returns checksummed '0x...' address string
 */

// ── Builder API Options ───────────────────────────────────────────────────────

/**
 * encryptInputs().execute() options:
 * 
 * .setAccount(address)     // Override owner of encrypted input
 * .setChainId(chainId)     // Override target chain
 * .setUseWorker(boolean)   // Use Web Worker for ZK proof (default: true)
 * .onStep(callback)        // Progress callback
 */

// ── Common Workflows ──────────────────────────────────────────────────────────

/**
 * Workflow 1: Confidential Voting
 * 
 * // Encrypt vote choice and stake amount
 * const [encryptedChoice] = await client
 *   .encryptInputs([Encryptable.bool(true)])  // Approve
 *   .execute();
 * 
 * const [encryptedAmount] = await client
 *   .encryptInputs([Encryptable.uint128(stakeAmount)])
 *   .execute();
 * 
 * // Submit to DAO
 * await daoContract.write.vote({
 *   proposalId,
 *   encryptedChoice,
 *   encryptedAmount,
 * });
 * 
 * // Reveal after voting ends
 * const choice = await client
 *   .decryptForView(voteCtHash, FheTypes.Bool)
 *   .execute();
 */

/**
 * Workflow 2: Private Deposits
 * 
 * // Encrypt deposit amount
 * const [encryptedAmount] = await client
 *   .encryptInputs([Encryptable.uint128(depositAmount)])
 *   .execute();
 * 
 * // Deposit to funding pool
 * await fundingPoolContract.write.deposit({ encryptedAmount });
 * 
 * // View encrypted balance
 * const balance = await client
 *   .decryptForView(balanceCtHash, FheTypes.Uint128)
 *   .execute();
 */

/**
 * Workflow 3: P2P Encrypted Swaps
 * 
 * // Create sealed offer
 * const [encryptedAmountA, encryptedAmountB] = await client
 *   .encryptInputs([
 *     Encryptable.uint128(amountA),
 *     Encryptable.uint128(amountB),
 *   ])
 *   .execute();
 * 
 * await swapContract.write.createOffer({
 *   tokenA, tokenB,
 *   encryptedAmountA,
 *   encryptedAmountB,
 *   expiryBlocks,
 * });
 */

// ── Error Handling ────────────────────────────────────────────────────────────

/**
 * Common errors:
 * 
 * - 'Client not connected' → Call client.connect() first
 * - 'Missing permit' → Call client.permits.getOrCreateSelfPermit()
 * - 'Wrong utype' → Pass correct FheTypes enum
 * - 'Bit limit exceeded' → Single call max 2048 bits of plaintext
 * 
 * try {
 *   const result = await client.encryptInputs([...]).execute();
 * } catch (err) {
 *   if (err instanceof CofheError) {
 *     console.error(err.code, err.message);
 *   }
 * }
 */

// ── Best Practices ────────────────────────────────────────────────────────────

/**
 * 1. Initialize client once at app start
 *    - Reuse the same client instance across components
 *    - Client persists permit storage
 * 
 * 2. Create permits after wallet connection
 *    - Permits are scoped to chainId + account
 *    - Create new permit when switching networks
 * 
 * 3. Handle encryption loading states
 *    - ZK proof generation takes 1-3 seconds
 *    - Show loading indicators during encrypt/decrypt
 * 
 * 4. Use Web Workers for browser apps
 *    - Default behavior for @cofhe/sdk/web
 *    - Prevents UI blocking during proof generation
 * 
 * 5. Batch encrypt when possible
 *    - Single call can encrypt up to 2048 bits
 *    - Reduces proof generation overhead
 */