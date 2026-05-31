/**
 * VenturesSea Contract ABIs
 * FHE-enabled contract ABIs for IdeaFi protocol on Fhenix.
 */

import { Abi } from 'viem';

// ── Encrypted Input Type ─────────────────────────────────────────────────────
export interface EncryptedInput {
  ctHash: `0x${string}`;
  securityZone: number;
  utype: number;
  signature: `0x${string}`;
}

// ── ThresholdDecryptor ABI ────────────────────────────────────────────────────
export const THRESHOLD_DECRYPTOR_ABI: Abi = [
  { inputs: [], name: 'owner', outputs: [{ name: '', type: 'address' }], stateMutability: 'view', type: 'function' },
  { inputs: [], name: 'getGuardianCount', outputs: [{ name: '', type: 'uint256' }], stateMutability: 'view', type: 'function' },
  { inputs: [{ name: 'account', type: 'address' }], name: 'isGuardian', outputs: [{ name: '', type: 'bool' }], stateMutability: 'view', type: 'function' },
  { inputs: [{ name: 'guardian', type: 'address' }], name: 'addGuardian', outputs: [], stateMutability: 'nonpayable', type: 'function' },
  { inputs: [{ name: 'guardian', type: 'address' }], name: 'removeGuardian', outputs: [], stateMutability: 'nonpayable', type: 'function' },
  { inputs: [{ name: 'handler', type: 'address' }, { name: 'authorized', type: 'bool' }], name: 'setAuthorizedHandler', outputs: [], stateMutability: 'nonpayable', type: 'function' },
  { inputs: [{ name: 'handler', type: 'address' }], name: 'isAuthorizedHandler', outputs: [{ name: '', type: 'bool' }], stateMutability: 'view', type: 'function' },
  { inputs: [{ name: 'ciphertextHash', type: 'bytes32' }, { name: 'conditionType', type: 'uint256' }, { name: 'conditionData', type: 'bytes' }], name: 'requestDecrypt', outputs: [{ name: 'requestId', type: 'uint256' }], stateMutability: 'nonpayable', type: 'function' },
  { inputs: [{ name: 'requestId', type: 'uint256' }], name: 'approveDecrypt', outputs: [], stateMutability: 'nonpayable', type: 'function' },
  { inputs: [{ name: 'requestId', type: 'uint256' }], name: 'hasSufficientApprovals', outputs: [{ name: '', type: 'bool' }], stateMutability: 'view', type: 'function' },
  { inputs: [], name: 'requestCount', outputs: [{ name: '', type: 'uint256' }], stateMutability: 'view', type: 'function' },
  { inputs: [], name: 'minApprovals', outputs: [{ name: '', type: 'uint256' }], stateMutability: 'view', type: 'function' },
];

// ── ConfidentialIdeaToken ABI ─────────────────────────────────────────────────
export const CONFIDENTIAL_TOKEN_ABI: Abi = [
  { inputs: [], name: 'name', outputs: [{ name: '', type: 'string' }], stateMutability: 'view', type: 'function' },
  { inputs: [], name: 'symbol', outputs: [{ name: '', type: 'string' }], stateMutability: 'view', type: 'function' },
  { inputs: [], name: 'decimals', outputs: [{ name: '', type: 'uint8' }], stateMutability: 'view', type: 'function' },
  { inputs: [], name: 'totalSupply', outputs: [{ name: '', type: 'uint256' }], stateMutability: 'view', type: 'function' },
  { inputs: [{ name: 'account', type: 'address' }], name: 'balanceOf', outputs: [{ name: '', type: 'uint256' }], stateMutability: 'view', type: 'function' },
  { inputs: [{ name: 'from', type: 'address' }, { name: 'to', type: 'address' }, { name: 'amount', type: 'uint256' }], name: 'transferFrom', outputs: [{ name: '', type: 'bool' }], stateMutability: 'nonpayable', type: 'function' },
  { inputs: [{ name: 'to', type: 'address' }, { name: 'encryptedAmount', type: 'tuple(bytes32 ctHash, uint256 securityZone, uint8 utype, bytes signature)' }], name: 'confidentialTransfer', outputs: [], stateMutability: 'nonpayable', type: 'function' },
  { inputs: [{ name: 'account', type: 'address' }], name: 'getEncryptedBalance', outputs: [{ name: '', type: 'bytes32' }], stateMutability: 'view', type: 'function' },
  { inputs: [{ name: 'to', type: 'address' }, { name: 'amount', type: 'uint256' }], name: 'mint', outputs: [], stateMutability: 'nonpayable', type: 'function' },
];

// ── ConfidentialFundingPool ABI ───────────────────────────────────────────────
export const CONFIDENTIAL_FUNDING_POOL_ABI: Abi = [
  { inputs: [{ name: '_owner', type: 'address' }, { name: '_token', type: 'address' }, { name: '_minDeposit', type: 'uint256' }, { name: '_maxDeposit', type: 'uint256' }, { name: '_treasury', type: 'address' }, { name: '_thresholdDecryptor', type: 'address' }], name: 'initialize', outputs: [], stateMutability: 'nonpayable', type: 'function' },
  { inputs: [{ name: 'investor', type: 'address' }, { name: 'encryptedAmount', type: 'tuple(bytes32 ctHash, uint256 securityZone, uint8 utype, bytes signature)' }], name: 'confidentialDeposit', outputs: [], stateMutability: 'payable', type: 'function' },
  { inputs: [{ name: 'encryptedAmount', type: 'tuple(bytes32 ctHash, uint256 securityZone, uint8 utype, bytes signature)' }], name: 'confidentialWithdraw', outputs: [], stateMutability: 'nonpayable', type: 'function' },
  { inputs: [{ name: 'investor', type: 'address' }], name: 'getEncryptedBalance', outputs: [{ name: '', type: 'bytes32' }], stateMutability: 'view', type: 'function' },
  { inputs: [], name: 'totalDeposits', outputs: [{ name: '', type: 'uint256' }], stateMutability: 'view', type: 'function' },
  { inputs: [], name: 'investorCount', outputs: [{ name: '', type: 'uint256' }], stateMutability: 'view', type: 'function' },
  { inputs: [], name: 'maxCapacity', outputs: [{ name: '', type: 'uint256' }], stateMutability: 'view', type: 'function' },
];

// ── ConfidentialIdeaDAO ABI ────────────────────────────────────────────────────
export const CONFIDENTIAL_IDEA_DAO_ABI: Abi = [
  { inputs: [{ name: 'proposalId', type: 'uint256' }, { name: 'encryptedVote', type: 'tuple(bytes32 ctHash, uint256 securityZone, uint8 utype, bytes signature)' }, { name: 'encryptedAmount', type: 'tuple(bytes32 ctHash, uint256 securityZone, uint8 utype, bytes signature)' }], name: 'castVote', outputs: [], stateMutability: 'nonpayable', type: 'function' },
  { inputs: [{ name: 'proposalId', type: 'uint256' }], name: 'state', outputs: [{ name: '', type: 'uint8' }], stateMutability: 'view', type: 'function' },
  { inputs: [{ name: 'proposalId', type: 'uint256' }], name: 'hasVoted', outputs: [{ name: '', type: 'bool' }], stateMutability: 'view', type: 'function' },
  { inputs: [{ name: 'proposalId', type: 'uint256' }], name: 'proposalVotes', outputs: [{ name: 'forVotes', type: 'uint256' }, { name: 'againstVotes', type: 'uint256' }], stateMutability: 'view', type: 'function' },
  { inputs: [{ name: 'proposalId', type: 'uint256' }], name: 'getEncryptedVote', outputs: [{ name: '', type: 'bytes32' }], stateMutability: 'view', type: 'function' },
];

// ── EncryptedSwap ABI ─────────────────────────────────────────────────────────
export const ENCRYPTED_SWAP_ABI: Abi = [
  { inputs: [{ name: 'tokenA', type: 'address' }, { name: 'tokenB', type: 'address' }, { name: 'encryptedAmountA', type: 'tuple(bytes32 ctHash, uint256 securityZone, uint8 utype, bytes signature)' }, { name: 'encryptedAmountB', type: 'tuple(bytes32 ctHash, uint256 securityZone, uint8 utype, bytes signature)' }, { name: 'nonce', type: 'uint256' }, { name: 'expiry', type: 'uint256' }, { name: 'recipient', type: 'address' }], name: 'createOffer', outputs: [{ name: 'offerHash', type: 'bytes32' }], stateMutability: 'nonpayable', type: 'function' },
  { inputs: [{ name: 'offerHash', type: 'bytes32' }, { name: 'tokenA', type: 'address' }, { name: 'tokenB', type: 'address' }, { name: 'encryptedAmountA', type: 'tuple(bytes32 ctHash, uint256 securityZone, uint8 utype, bytes signature)' }, { name: 'encryptedAmountB', type: 'tuple(bytes32 ctHash, uint256 securityZone, uint8 utype, bytes signature)' }, { name: 'nonce', type: 'uint256' }], name: 'acceptOffer', outputs: [], stateMutability: 'nonpayable', type: 'function' },
  { inputs: [{ name: 'offerHash', type: 'bytes32' }], name: 'cancelOffer', outputs: [], stateMutability: 'nonpayable', type: 'function' },
  { inputs: [{ name: 'offerHash', type: 'bytes32' }], name: 'getOffer', outputs: [{ name: '', type: 'tuple(address maker, address tokenA, address tokenB, uint256 nonce, uint256 expiry, uint8 status)' }], stateMutability: 'view', type: 'function' },
  { inputs: [{ name: 'token', type: 'address' }], name: 'isSupportedToken', outputs: [{ name: '', type: 'bool' }], stateMutability: 'view', type: 'function' },
  { inputs: [{ name: 'token', type: 'address' }], name: 'addSupportedToken', outputs: [], stateMutability: 'nonpayable', type: 'function' },
];

// ── Legacy ABIs (for migration) ──────────────────────────────────────────────
export const IDEA_TOKEN_ABI = [
  { inputs: [], name: 'name', outputs: [{ name: '', type: 'string' }], stateMutability: 'view', type: 'function' },
  { inputs: [], name: 'symbol', outputs: [{ name: '', type: 'string' }], stateMutability: 'view', type: 'function' },
  { inputs: [], name: 'decimals', outputs: [{ name: '', type: 'uint8' }], stateMutability: 'view', type: 'function' },
  { inputs: [], name: 'totalSupply', outputs: [{ name: '', type: 'uint256' }], stateMutability: 'view', type: 'function' },
  { inputs: [{ name: 'account', type: 'address' }], name: 'balanceOf', outputs: [{ name: '', type: 'uint256' }], stateMutability: 'view', type: 'function' },
  { inputs: [{ name: 'to', type: 'address' }, { name: 'amount', type: 'uint256' }], name: 'mint', outputs: [], stateMutability: 'nonpayable', type: 'function' },
] as const;
