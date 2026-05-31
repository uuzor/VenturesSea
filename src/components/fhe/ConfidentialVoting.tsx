'use client';

/**
 * Confidential Voting Component
 * 
 * Implements sealed-bid voting for builder selection with encrypted ballots.
 * Vote amounts and choices remain private until reveal.
 */

import React, { useState, useEffect, useCallback } from 'react';
import { useFHE, FheTypes } from './FHEProvider';
import { Hash, useContractRead, useContractWrite, useWaitForTransaction } from 'wagmi';
import { formatUnits } from 'viem';

// ── Types ─────────────────────────────────────────────────────────────────────

export interface VotingSession {
  id: bigint;
  proposalId: Hash;
  startTime: bigint;
  endTime: bigint;
  voteCount: bigint;
  totalVotes: bigint;
  revealed: boolean;
  status: 'active' | 'ended' | 'revealed';
}

export interface EncryptedVote {
  ctHash: Hash;
  encryptedAmount: bigint;
  encryptedChoice: boolean;
  timestamp: bigint;
}

export interface VoteResult {
  choice: boolean;
  amount: bigint;
  voter: string;
  revealed: boolean;
}

interface ConfidentialVotingProps {
  daoAddress: Hash;
  proposalId: Hash;
  currentUser: Hash;
  minVoteAmount?: bigint;
}

// ── Component ──────────────────────────────────────────────────────────────────

export function ConfidentialVoting({
  daoAddress,
  proposalId,
  currentUser,
  minVoteAmount = 0n,
}: ConfidentialVotingProps) {
  const { encryptBool, encryptUint128, decryptForView, isConnected, isEncrypting } = useFHE();
  
  const [voteChoice, setVoteChoice] = useState<boolean>(true);
  const [voteAmount, setVoteAmount] = useState<string>('0');
  const [isSubmitting, setIsSubmitting] = useState(false);
  const [txHash, setTxHash] = useState<Hash | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [encryptedVote, setEncryptedVote] = useState<EncryptedVote | null>(null);

  // Mock contract reads - replace with actual contract ABI
  const [session, setSession] = useState<VotingSession | null>(null);
  
  // Load voting session
  useEffect(() => {
    // Simulated session data - replace with contract call
    setSession({
      id: 0n,
      proposalId,
      startTime: BigInt(Math.floor(Date.now() / 1000) - 3600),
      endTime: BigInt(Math.floor(Date.now() / 1000) + 86400 * 7),
      voteCount: 0n,
      totalVotes: 0n,
      revealed: false,
      status: 'active',
    });
  }, [proposalId]);

  // Encrypt vote for submission
  const encryptVote = useCallback(async () => {
    try {
      setError(null);
      
      // Encrypt the vote choice (for/against)
      const encryptedChoice = await encryptBool(voteChoice);
      
      // Encrypt the vote amount (how much stake)
      const amountBigInt = BigInt(Math.floor(parseFloat(voteAmount) * 1e18));
      const encryptedAmount = await encryptUint128(amountBigInt);

      return { encryptedChoice, encryptedAmount };
    } catch (err) {
      const message = err instanceof Error ? err.message : 'Failed to encrypt vote';
      setError(message);
      throw err;
    }
  }, [voteChoice, voteAmount, encryptBool, encryptUint128]);

  // Submit encrypted vote
  const submitVote = useCallback(async () => {
    if (!isConnected) {
      setError('Please connect your wallet');
      return;
    }

    const amountBigInt = BigInt(Math.floor(parseFloat(voteAmount) * 1e18));
    if (amountBigInt < minVoteAmount) {
      setError(`Minimum vote amount is ${formatUnits(minVoteAmount, 18)} ETH`);
      return;
    }

    try {
      setIsSubmitting(true);
      setError(null);

      // Encrypt vote
      const { encryptedChoice, encryptedAmount } = await encryptVote();

      // Store encrypted vote locally for reveal later
      setEncryptedVote({
        ctHash: encryptedChoice,
        encryptedAmount,
        encryptedChoice,
        timestamp: BigInt(Math.floor(Date.now() / 1000)),
      });

      // TODO: Call contract submitEncryptedVote(encryptedChoice, encryptedAmount)
      // await contractWrite.submitVote({
      //   proposalId,
      //   encryptedChoice,
      //   encryptedAmount,
      // });

      console.log('Encrypted vote submitted:', {
        choice: encryptedChoice,
        amount: encryptedAmount,
      });

    } catch (err) {
      const message = err instanceof Error ? err.message : 'Failed to submit vote';
      setError(message);
    } finally {
      setIsSubmitting(false);
    }
  }, [isConnected, voteChoice, voteAmount, minVoteAmount, encryptVote]);

  // Reveal vote (after voting period ends)
  const revealVote = useCallback(async () => {
    if (!encryptedVote || !session?.revealed) {
      setError('Vote cannot be revealed yet');
      return;
    }

    try {
      setError(null);

      // Decrypt choice for reveal
      const choice = await decryptForView(encryptedVote.ctHash, FheTypes.Bool);
      
      // Decrypt amount for reveal
      const amount = await decryptForView(
        encryptedVote.encryptedAmount as Hash, 
        FheTypes.Uint128
      );

      console.log('Vote revealed:', { choice, amount });

      // TODO: Call contract revealVote(proposalId, choice, amount, encryptedVote.ctHash)
      
    } catch (err) {
      const message = err instanceof Error ? err.message : 'Failed to reveal vote';
      setError(message);
    }
  }, [encryptedVote, session, decryptForView]);

  // Countdown timer
  const [timeLeft, setTimeLeft] = useState<string>('');
  
  useEffect(() => {
    if (!session) return;

    const updateTimer = () => {
      const now = BigInt(Math.floor(Date.now() / 1000));
      const remaining = session.endTime - now;
      
      if (remaining <= 0n) {
        setTimeLeft('Voting ended');
      } else {
        const days = remaining / 86400n;
        const hours = (remaining % 86400n) / 3600n;
        const minutes = (remaining % 3600n) / 60n;
        setTimeLeft(`${days}d ${hours}h ${minutes}m remaining`);
      }
    };

    updateTimer();
    const interval = setInterval(updateTimer, 60000);
    return () => clearInterval(interval);
  }, [session]);

  return (
    <div className="confidential-voting p-6 bg-gradient-to-br from-purple-900/20 to-blue-900/20 rounded-xl border border-purple-500/30">
      <div className="flex items-center gap-3 mb-6">
        <div className="w-10 h-10 bg-purple-600 rounded-lg flex items-center justify-center">
          <svg className="w-6 h-6 text-white" fill="none" viewBox="0 0 24 24" stroke="currentColor">
            <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M9 12l2 2 4-4m5.618-4.016A11.955 11.955 0 0112 2.944a11.955 11.955 0 01-8.618 3.04A12.02 12.02 0 003 9c0 5.591 3.824 10.29 9 11.622 5.176-1.332 9-6.03 9-11.622 0-1.042-.133-2.052-.382-3.016z" />
          </svg>
        </div>
        <div>
          <h3 className="text-lg font-semibold text-white">Confidential Voting</h3>
          <p className="text-sm text-gray-400">Your vote remains encrypted until reveal</p>
        </div>
      </div>

      {/* Vote Status */}
      <div className="mb-6 p-4 bg-black/30 rounded-lg">
        <div className="flex justify-between items-center">
          <span className="text-gray-400">Status</span>
          <span className={`px-3 py-1 rounded-full text-sm ${
            session?.status === 'active' 
              ? 'bg-green-600/20 text-green-400 border border-green-500/30'
              : 'bg-gray-600/20 text-gray-400'
          }`}>
            {session?.status || 'Loading...'}
          </span>
        </div>
        <div className="flex justify-between items-center mt-2">
          <span className="text-gray-400">Time Remaining</span>
          <span className="text-white font-mono">{timeLeft}</span>
        </div>
        <div className="flex justify-between items-center mt-2">
          <span className="text-gray-400">Your Vote</span>
          <span className={encryptedVote ? 'text-green-400' : 'text-yellow-400'}>
            {encryptedVote ? 'Encrypted ✓' : 'Not submitted'}
          </span>
        </div>
      </div>

      {/* Vote Selection */}
      <div className="mb-6">
        <label className="block text-sm text-gray-400 mb-2">Vote Choice</label>
        <div className="grid grid-cols-2 gap-4">
          <button
            onClick={() => setVoteChoice(true)}
            className={`p-4 rounded-lg border-2 transition-all ${
              voteChoice 
                ? 'border-green-500 bg-green-500/20 text-green-400' 
                : 'border-gray-600 hover:border-gray-500 text-gray-400'
            }`}
          >
            <div className="text-2xl mb-2">👍</div>
            <div className="font-semibold">Approve</div>
            <div className="text-xs mt-1 opacity-75">Support this proposal</div>
          </button>
          <button
            onClick={() => setVoteChoice(false)}
            className={`p-4 rounded-lg border-2 transition-all ${
              !voteChoice 
                ? 'border-red-500 bg-red-500/20 text-red-400' 
                : 'border-gray-600 hover:border-gray-500 text-gray-400'
            }`}
          >
            <div className="text-2xl mb-2">👎</div>
            <div className="font-semibold">Reject</div>
            <div className="text-xs mt-1 opacity-75">Oppose this proposal</div>
          </button>
        </div>
      </div>

      {/* Vote Amount */}
      <div className="mb-6">
        <label className="block text-sm text-gray-400 mb-2">
          Vote Amount (ETH)
          <span className="text-xs ml-2 text-gray-500">Encrypted stake</span>
        </label>
        <input
          type="number"
          value={voteAmount}
          onChange={(e) => setVoteAmount(e.target.value)}
          min="0"
          step="0.01"
          className="w-full p-3 bg-black/30 border border-gray-600 rounded-lg text-white font-mono focus:border-purple-500 focus:outline-none"
          placeholder="0.0"
        />
        {minVoteAmount > 0n && (
          <p className="text-xs text-gray-500 mt-1">
            Minimum: {formatUnits(minVoteAmount, 18)} ETH
          </p>
        )}
      </div>

      {/* Submit Button */}
      <button
        onClick={submitVote}
        disabled={isSubmitting || isEncrypting || !isConnected}
        className={`w-full py-3 rounded-lg font-semibold transition-all ${
          isSubmitting || isEncrypting
            ? 'bg-gray-600 cursor-not-allowed'
            : 'bg-purple-600 hover:bg-purple-700 text-white'
        }`}
      >
        {isSubmitting || isEncrypting ? (
          <span className="flex items-center justify-center gap-2">
            <svg className="animate-spin h-5 w-5" viewBox="0 0 24 24">
              <circle className="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" strokeWidth="4" fill="none" />
              <path className="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4z" />
            </svg>
            Encrypting Vote...
          </span>
        ) : (
          'Submit Encrypted Vote'
        )}
      </button>

      {/* Reveal Button (after voting ends) */}
      {encryptedVote && session?.status === 'ended' && !session.revealed && (
        <button
          onClick={revealVote}
          className="w-full mt-3 py-3 rounded-lg font-semibold bg-blue-600 hover:bg-blue-700 text-white transition-all"
        >
          Reveal Your Vote
        </button>
      )}

      {/* Error Display */}
      {error && (
        <div className="mt-4 p-3 bg-red-500/20 border border-red-500/30 rounded-lg text-red-400 text-sm">
          {error}
        </div>
      )}

      {/* Privacy Notice */}
      <div className="mt-6 p-3 bg-purple-500/10 border border-purple-500/20 rounded-lg">
        <div className="flex items-start gap-2">
          <svg className="w-5 h-5 text-purple-400 mt-0.5" fill="none" viewBox="0 0 24 24" stroke="currentColor">
            <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M12 15v2m-6 4h12a2 2 0 002-2v-6a2 2 0 00-2-2H6a2 2 0 00-2 2v6a2 2 0 002 2zm10-10V7a4 4 0 00-8 0v4h8z" />
          </svg>
          <div className="text-sm text-gray-400">
            <p className="font-semibold text-purple-400">Privacy Guaranteed</p>
            <p className="mt-1">Your vote choice and amount are encrypted using FHE. Only you can reveal your vote after the voting period ends.</p>
          </div>
        </div>
      </div>
    </div>
  );
}

export default ConfidentialVoting;