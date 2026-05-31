/**
 * VenturesSea Contract Addresses
 * 
 * Fhenix testnet deployment addresses for FHE-enabled IdeaFi contracts.
 */

import { Hash } from 'viem';

// ── Fhenix Chain ID ───────────────────────────────────────────────────────────
export const FHENIX_CHAIN_ID = 80085;

// ── Contract Addresses (Fhenix Testnet) ───────────────────────────────────────
export const CONTRACT_ADDRESSES = {
  [FHENIX_CHAIN_ID]: {
    // Core FHE Contracts
    thresholdDecryptor: (process.env.NEXT_PUBLIC_THRESHOLD_DECRYPTOR || '0x0000000000000000000000000000000000000000') as Hash,
    
    // IdeaFi Protocol
    confidentialIdeaToken: (process.env.NEXT_PUBLIC_CONFIDENTIAL_TOKEN || '0x0000000000000000000000000000000000000000') as Hash,
    confidentialFundingPool: (process.env.NEXT_PUBLIC_FUNDING_POOL || '0x0000000000000000000000000000000000000000') as Hash,
    confidentialIdeaDAO: (process.env.NEXT_PUBLIC_IDEA_DAO || '0x0000000000000000000000000000000000000000') as Hash,
    encryptedSwap: (process.env.NEXT_PUBLIC_ENCRYPTED_SWAP || '0x0000000000000000000000000000000000000000') as Hash,
    
    // Legacy (for migration)
    ideaToken: (process.env.NEXT_PUBLIC_IDEA_TOKEN || '0x0000000000000000000000000000000000000000') as Hash,
    ideaFactory: (process.env.NEXT_PUBLIC_IDEA_FACTORY || '0x0000000000000000000000000000000000000000') as Hash,
  },
} as const;

// ── Default Network ───────────────────────────────────────────────────────────
export const DEFAULT_CHAIN_ID = FHENIX_CHAIN_ID;

// ── Address Helper ───────────────────────────────────────────────────────────
export function getContractAddress(
  chainId: number, 
  contractName: keyof typeof CONTRACT_ADDRESSES[typeof FHENIX_CHAIN_ID]
): Hash {
  return (CONTRACT_ADDRESSES[chainId]?.[contractName] as Hash) || '0x0000000000000000000000000000000000000000';
}

// ── Contract Name Types ───────────────────────────────────────────────────────
export type IdeaFiContractName = 
  | 'thresholdDecryptor'
  | 'confidentialIdeaToken'
  | 'confidentialFundingPool'
  | 'confidentialIdeaDAO'
  | 'encryptedSwap'
  | 'ideaToken'
  | 'ideaFactory';
