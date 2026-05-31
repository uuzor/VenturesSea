'use client';

/**
 * Privacy & Selective Disclosure Hooks
 * 
 * Manages what information is revealed to whom in the FHE-enabled protocol.
 */

import { useState, useCallback, useMemo } from 'react';
import { useAccount, useChainId, useReadContract, useWriteContract, useWaitForTransactionReceipt } from 'wagmi';
import { Hash, 0n } from 'viem';
import { 
  CONFIDENTIAL_TOKEN_ABI, 
  CONFIDENTIAL_FUNDING_POOL_ABI,
  CONFIDENTIAL_IDEA_DAO_ABI,
  ENCRYPTED_SWAP_ABI,
} from '@/lib/contracts/abis';
import { CONTRACT_ADDRESSES, FHENIX_CHAIN_ID } from '@/lib/contracts/addresses';

// ── Privacy Level Types ───────────────────────────────────────────────────────

export enum PrivacyLevel {
  FULL_PRIVATE = 0,    // No one can view
  SELECTIVE = 1,       // Only selected addresses
  PERMIT_REQUIRED = 2, // Requires decryption permit
  PUBLIC = 3,           // Anyone can view (decrypt)
}

// ── Disclosure Policy ───────────────────────────────────────────────────────

export interface DisclosurePolicy {
  level: PrivacyLevel;
  allowedAddresses?: Hash[];
  requiredPermits?: string[];
}

// ── Encrypted State Types ─────────────────────────────────────────────────────

export interface EncryptedValue<T = bigint> {
  ctHash: Hash;
  revealed: boolean;
  value?: T;
  lastDecryptedAt?: number;
  decryptedBy?: Hash;
}

// ── usePrivacySettings Hook ──────────────────────────────────────────────────

export function usePrivacySettings() {
  const { address } = useAccount();
  
  const [defaultPolicy, setDefaultPolicy] = useState<DisclosurePolicy>({
    level: PrivacyLevel.PERMIT_REQUIRED,
  });

  const [disclosurePolicies, setDisclosurePolicies] = useState<
    Record<string, DisclosurePolicy>
  >({});

  const updatePolicy = useCallback((key: string, policy: DisclosurePolicy) => {
    setDisclosurePolicies(prev => ({
      ...prev,
      [key]: policy,
    }));
  }, []);

  const removePolicy = useCallback((key: string) => {
    setDisclosurePolicies(prev => {
      const { [key]: _, ...rest } = prev;
      return rest;
    });
  }, []);

  const canReveal = useCallback(
    (key: string, viewer: Hash): boolean => {
      const policy = disclosurePolicies[key] || defaultPolicy;
      
      if (policy.level === PrivacyLevel.FULL_PRIVATE) {
        return false;
      }
      
      if (policy.level === PrivacyLevel.PUBLIC) {
        return true;
      }
      
      if (policy.level === PrivacyLevel.SELECTIVE) {
        return policy.allowedAddresses?.includes(viewer) || false;
      }
      
      // PERMIT_REQUIRED - check if viewer has permit
      if (address && policy.requiredPermits?.includes(address)) {
        return true;
      }
      
      return viewer === address; // Owner can always see their own
    },
    [address, defaultPolicy, disclosurePolicies]
  );

  return {
    defaultPolicy,
    setDefaultPolicy,
    disclosurePolicies,
    updatePolicy,
    removePolicy,
    canReveal,
  };
}

// ── useEncryptedBalance Hook ──────────────────────────────────────────────────

export function useEncryptedBalance(
  tokenAddress: Hash,
  ownerAddress?: Hash
) {
  const { address } = useAccount();
  const chainId = useChainId();
  const effectiveOwner = ownerAddress || address;
  
  const [revealedBalance, setRevealedBalance] = useState<bigint | null>(null);
  const [isRevealing, setIsRevealing] = useState(false);
  const [privacyLevel, setPrivacyLevel] = useState(PrivacyLevel.PERMIT_REQUIRED);

  // Read encrypted balance from contract
  const { data: encryptedBalance, isLoading: isLoadingEncrypted } = useReadContract({
    address: tokenAddress,
    abi: CONFIDENTIAL_TOKEN_ABI,
    functionName: 'getEncryptedBalance',
    args: effectiveOwner ? [effectiveOwner] : undefined,
    chainId: chainId || FHENIX_CHAIN_ID,
  });

  // Decrypt balance (requires permit)
  const decryptBalance = useCallback(async () => {
    if (!encryptedBalance || !effectiveOwner) return;
    
    setIsRevealing(true);
    try {
      // In production, use CoFHE SDK:
      // const decrypted = await cofheClient.decryptForView(encryptedBalance, FheTypes.Uint128);
      // setRevealedBalance(decrypted as bigint);
      
      // Simulated for demo
      await new Promise(resolve => setTimeout(resolve, 1000));
      setRevealedBalance(0n);
    } finally {
      setIsRevealing(false);
    }
  }, [encryptedBalance, effectiveOwner]);

  const canView = useMemo(() => {
    return privacyLevel === PrivacyLevel.PUBLIC || 
           privacyLevel === PrivacyLevel.PERMIT_REQUIRED ||
           (address && address === effectiveOwner);
  }, [privacyLevel, address, effectiveOwner]);

  return {
    encryptedBalance,
    revealedBalance,
    isLoadingEncrypted,
    isRevealing,
    privacyLevel,
    setPrivacyLevel,
    canView,
    decryptBalance,
    hideBalance: () => setRevealedBalance(null),
  };
}

// ── useConfidentialVoting Hook ───────────────────────────────────────────────

export function useConfidentialVoting(daoAddress: Hash) {
  const { address } = useAccount();
  const chainId = useChainId();
  
  const [myEncryptedVote, setMyEncryptedVote] = useState<Hash | null>(null);
  const [hasVoted, setHasVoted] = useState(false);
  const [isVoting, setIsVoting] = useState(false);

  // Check if user has voted
  const { data: votedStatus } = useReadContract({
    address: daoAddress,
    abi: CONFIDENTIAL_IDEA_DAO_ABI,
    functionName: 'hasVoted',
    args: [BigInt(0)], // proposalId placeholder
    chainId: chainId || FHENIX_CHAIN_ID,
  });

  // Get encrypted vote for a proposal
  const getEncryptedVote = useCallback(async (proposalId: bigint) => {
    if (!address) return null;
    
    // In production:
    // const ctHash = await publicClient.readContract({
    //   address: daoAddress,
    //   abi: CONFIDENTIAL_IDEA_DAO_ABI,
    //   functionName: 'getEncryptedVote',
    //   args: [proposalId, address],
    // });
    
    return myEncryptedVote;
  }, [address, myEncryptedVote]);

  // Cast encrypted vote
  const castVote = useCallback(async (
    proposalId: bigint,
    encryptedVote: Hash,
    encryptedAmount: Hash
  ) => {
    if (!address) return;

    setIsVoting(true);
    try {
      // In production:
      // const hash = await writeContract({
      //   address: daoAddress,
      //   abi: CONFIDENTIAL_IDEA_DAO_ABI,
      //   functionName: 'castVote',
      //   args: [proposalId, encryptedVote, encryptedAmount],
      // });
      
      setMyEncryptedVote(encryptedVote);
      setHasVoted(true);
      console.log('Vote cast for proposal:', proposalId);
    } finally {
      setIsVoting(false);
    }
  }, [address]);

  // Reveal vote (after voting period)
  const revealVote = useCallback(async (proposalId: bigint) => {
    const encryptedVote = await getEncryptedVote(proposalId);
    if (!encryptedVote) return null;

    // In production, use CoFHE SDK to decrypt
    // const decrypted = await cofheClient.decryptForView(encryptedVote, FheTypes.Bool);
    
    return { choice: true, amount: 0n }; // Placeholder
  }, [getEncryptedVote]);

  return {
    myEncryptedVote,
    hasVoted: votedStatus ?? hasVoted,
    isVoting,
    getEncryptedVote,
    castVote,
    revealVote,
  };
}

// ── useConfidentialFunding Hook ────────────────────────────────────────────────

export function useConfidentialFunding(poolAddress: Hash) {
  const { address } = useAccount();
  
  const [depositedAmount, setDepositedAmount] = useState<bigint | null>(null);
  const [isDepositing, setIsDepositing] = useState(false);

  // Get encrypted balance
  const { data: encryptedBalance } = useReadContract({
    address: poolAddress,
    abi: CONFIDENTIAL_FUNDING_POOL_ABI,
    functionName: 'getEncryptedBalance',
    args: address ? [address] : undefined,
    chainId: FHENIX_CHAIN_ID,
  });

  // Confidential deposit
  const confidentialDeposit = useCallback(async (encryptedAmount: Hash) => {
    if (!address) return;

    setIsDepositing(true);
    try {
      // In production:
      // await writeContract({
      //   address: poolAddress,
      //   abi: CONFIDENTIAL_FUNDING_POOL_ABI,
      //   functionName: 'confidentialDeposit',
      //   args: [address, encryptedAmount],
      //   value: amount,
      // });
      
      console.log('Confidential deposit made');
    } finally {
      setIsDepositing(false);
    }
  }, [address, poolAddress]);

  // Decrypt and view balance
  const viewBalance = useCallback(async () => {
    if (!encryptedBalance || !address) return null;

    // In production, use CoFHE SDK
    // const decrypted = await cofheClient.decryptForView(encryptedBalance, FheTypes.Uint128);
    // setDepositedAmount(decrypted as bigint);
    
    return depositedAmount;
  }, [encryptedBalance, address, depositedAmount]);

  return {
    encryptedBalance,
    depositedAmount,
    isDepositing,
    confidentialDeposit,
    viewBalance,
  };
}

// ── useSelectiveDisclosure Hook ──────────────────────────────────────────────

/**
 * Manages selective disclosure of encrypted data to specific addresses.
 * Enables privacy-preserving data sharing.
 */
export function useSelectiveDisclosure() {
  const { address } = useAccount();
  
  const [grants, setGrants] = useState<
    Record<string, { grantedTo: Hash; expiresAt: number; level: PrivacyLevel }>
  >({});

  // Grant access to a specific address
  const grantAccess = useCallback((
    dataKey: string,
    grantee: Hash,
    expiresIn: number, // seconds
    level: PrivacyLevel = PrivacyLevel.PERMIT_REQUIRED
  ) => {
    setGrants(prev => ({
      ...prev,
      [dataKey]: {
        grantedTo: grantee,
        expiresAt: Date.now() + expiresIn * 1000,
        level,
      },
    }));
  }, []);

  // Revoke access
  const revokeAccess = useCallback((dataKey: string) => {
    setGrants(prev => {
      const { [dataKey]: _, ...rest } = prev;
      return rest;
    });
  }, []);

  // Check if address can access data
  const canAccess = useCallback(
    (dataKey: string, accessor: Hash): boolean => {
      const grant = grants[dataKey];
      
      if (!grant) return false;
      if (Date.now() > grant.expiresAt) return false;
      if (grant.grantedTo !== accessor && accessor !== address) return false;
      
      return true;
    },
    [grants, address]
  );

  // Get all grants for current user
  const getMyGrants = useCallback(() => {
    if (!address) return [];
    
    return Object.entries(grants)
      .filter(([_, grant]) => grant.grantedTo === address)
      .map(([key, grant]) => ({
        dataKey: key,
        expiresAt: grant.expiresAt,
        level: grant.level,
      }));
  }, [grants, address]);

  return {
    grants,
    grantAccess,
    revokeAccess,
    canAccess,
    getMyGrants,
  };
}

// ── usePrivacyDashboard Hook ─────────────────────────────────────────────────

export function usePrivacyDashboard() {
  const { address, isConnected } = useAccount();
  const { canReveal, updatePolicy, disclosurePolicies } = usePrivacySettings();
  const { getMyGrants } = useSelectiveDisclosure();
  
  const [activeReveals, setActiveReveals] = useState<Record<string, {
    timestamp: number;
    viewer: Hash;
  }>>({});

  // Log when data is revealed
  const logReveal = useCallback((dataKey: string) => {
    if (!address) return;
    
    setActiveReveals(prev => ({
      ...prev,
      [dataKey]: {
        timestamp: Date.now(),
        viewer: address,
      },
    }));
  }, [address]);

  // Get privacy summary
  const summary = useMemo(() => ({
    totalPolicies: Object.keys(disclosurePolicies).length,
    activeGrants: getMyGrants().length,
    recentReveals: Object.keys(activeReveals).length,
    isConnected,
    hasWallet: !!address,
  }), [disclosurePolicies, getMyGrants, activeReveals, isConnected, address]);

  return {
    ...summary,
    canReveal,
    updatePolicy,
    logReveal,
    activeReveals,
  };
}