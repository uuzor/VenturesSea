'use client';

/**
 * useCofheWallet Hook
 * 
 * Connects CoFHE SDK to Wagmi wallet for seamless FHE operations.
 */

import { useCallback, useEffect, useState } from 'react';
import { useAccount, usePublicClient, useWalletClient } from 'wagmi';
import { Hash } from 'viem';
import { useFHE } from '../components/fhe/FHEProvider';

interface CofheWalletState {
  isReady: boolean;
  chainId: number | null;
  address: Hash | null;
}

export function useCofheWallet() {
  const { address, isConnected, chain } = useAccount();
  const publicClient = usePublicClient();
  const { data: walletClient } = useWalletClient();
  
  const { connect, disconnect, isConnected: fheConnected, error } = useFHE();
  
  const [state, setState] = useState<CofheWalletState>({
    isReady: false,
    chainId: null,
    address: null,
  });

  // Connect CoFHE when wallet connects
  useEffect(() => {
    if (isConnected && publicClient && walletClient && address) {
      const init = async () => {
        try {
          await connect(publicClient, walletClient);
          setState({
            isReady: true,
            chainId: chain?.id || null,
            address,
          });
        } catch (err) {
          console.error('Failed to init CoFHE:', err);
        }
      };
      init();
    } else {
      setState({
        isReady: false,
        chainId: null,
        address: null,
      });
    }
  }, [isConnected, publicClient, walletClient, address, chain, connect]);

  // Disconnect handler
  const handleDisconnect = useCallback(() => {
    disconnect();
    setState({
      isReady: false,
      chainId: null,
      address: null,
    });
  }, [disconnect]);

  return {
    ...state,
    address,
    isConnected,
    fheConnected,
    error,
    disconnect: handleDisconnect,
    reConnect: connect,
  };
}

/**
 * useEncryptedBalance Hook
 * 
 * Manages encrypted balance display for a specific token.
 */
export function useEncryptedBalance(tokenAddress: Hash, userAddress: Hash | undefined) {
  const { decryptForView, isReady } = useFHE();
  const [balance, setBalance] = useState<bigint | null>(null);
  const [isLoading, setIsLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const loadBalance = useCallback(async () => {
    if (!isReady || !userAddress) return;

    setIsLoading(true);
    setError(null);

    try {
      // TODO: Get encrypted balance from contract
      // const ctHash = await contract.read.getEncryptedBalance({ account: userAddress });
      // const decryptedBalance = await decryptForView(ctHash, FheTypes.Uint128);
      // setBalance(decryptedBalance as bigint);

      // Mock for demo
      setTimeout(() => {
        setBalance(BigInt(Math.floor(Math.random() * 10000) * 1e18));
        setIsLoading(false);
      }, 500);
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to load balance');
      setIsLoading(false);
    }
  }, [isReady, userAddress, decryptForView]);

  useEffect(() => {
    loadBalance();
  }, [loadBalance]);

  return { balance, isLoading, error, refresh: loadBalance };
}

/**
 * useConfidentialVote Hook
 * 
 * Manages the voting flow with encrypted ballots.
 */
export function useConfidentialVote(
  daoAddress: Hash,
  proposalId: Hash,
  onVoteSubmitted?: (ctHash: Hash) => void
) {
  const { encryptBool, encryptUint128, decryptForView, isReady } = useFHE();

  const [isSubmitting, setIsSubmitting] = useState(false);
  const [voteSubmitted, setVoteSubmitted] = useState(false);
  const [encryptedVoteHash, setEncryptedVoteHash] = useState<Hash | null>(null);
  const [error, setError] = useState<string | null>(null);

  const submitVote = useCallback(async (choice: boolean, amount: bigint) => {
    if (!isReady) {
      setError('Wallet not connected to FHE network');
      return;
    }

    setIsSubmitting(true);
    setError(null);

    try {
      // Encrypt choice
      const encryptedChoice = await encryptBool(choice);
      
      // Encrypt amount
      const encryptedAmount = await encryptUint128(amount);

      console.log('Vote encrypted:', { choice, amount, encryptedChoice, encryptedAmount });

      // TODO: Submit to contract
      // await contract.write.submitVote({
      //   proposalId,
      //   encryptedChoice,
      //   encryptedAmount,
      // });

      setEncryptedVoteHash(encryptedChoice);
      setVoteSubmitted(true);
      onVoteSubmitted?.(encryptedChoice);

    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to submit vote');
    } finally {
      setIsSubmitting(false);
    }
  }, [isReady, encryptBool, encryptUint128, onVoteSubmitted]);

  const revealVote = useCallback(async (): Promise<{ choice: boolean; amount: bigint } | null> => {
    if (!encryptedVoteHash) {
      setError('No vote to reveal');
      return null;
    }

    try {
      const choice = await decryptForView(encryptedVoteHash, 'Bool' as any) as boolean;
      // Would also need ctHash for amount in real implementation
      return { choice, amount: 0n };
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to reveal vote');
      return null;
    }
  }, [encryptedVoteHash, decryptForView]);

  return {
    submitVote,
    revealVote,
    isSubmitting,
    voteSubmitted,
    encryptedVoteHash,
    error,
    reset: () => {
      setVoteSubmitted(false);
      setEncryptedVoteHash(null);
      setError(null);
    },
  };
}

/**
 * useEncryptedSwap Hook
 * 
 * Manages P2P encrypted swap creation and acceptance.
 */
export function useEncryptedSwap(swapContract: Hash) {
  const { encryptUint128, isReady } = useFHE();

  const [isProcessing, setIsProcessing] = useState(false);
  const [lastOfferId, setLastOfferId] = useState<Hash | null>(null);
  const [error, setError] = useState<string | null>(null);

  const createOffer = useCallback(async (
    tokenA: Hash,
    tokenB: Hash,
    amountA: bigint,
    amountB: bigint,
    expiryHours: number = 24
  ) => {
    if (!isReady) {
      setError('Wallet not connected to FHE network');
      return null;
    }

    setIsProcessing(true);
    setError(null);

    try {
      // Encrypt amounts
      const [encryptedAmountA, encryptedAmountB] = await Promise.all([
        encryptUint128(amountA),
        encryptUint128(amountB),
      ]);

      console.log('Creating encrypted swap:', {
        tokenA,
        tokenB,
        amountA,
        amountB,
        encryptedAmountA,
        encryptedAmountB,
      });

      // TODO: Submit to contract
      // const tx = await contract.write.createOffer({
      //   tokenA,
      //   tokenB,
      //   encryptedAmountA,
      //   encryptedAmountB,
      //   expiryBlocks,
      // });

      // Mock offer ID
      const mockOfferId = `0x${Math.random().toString(16).slice(2)}${Date.now().toString(16)}` as Hash;
      setLastOfferId(mockOfferId);
      
      return mockOfferId;
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to create offer');
      return null;
    } finally {
      setIsProcessing(false);
    }
  }, [isReady, encryptUint128]);

  const acceptOffer = useCallback(async (offerId: Hash) => {
    if (!isReady) {
      setError('Wallet not connected to FHE network');
      return false;
    }

    setIsProcessing(true);
    setError(null);

    try {
      // TODO: Submit to contract
      // await contract.write.acceptOffer({ offerId });
      
      return true;
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to accept offer');
      return false;
    } finally {
      setIsProcessing(false);
    }
  }, [isReady]);

  return {
    createOffer,
    acceptOffer,
    isProcessing,
    lastOfferId,
    error,
  };
}