'use client';

/**
 * Confidential Funding Pool Component
 * 
 * Implements encrypted deposits and withdrawals where amounts remain private.
 * Uses FHE for confidential balance operations.
 */

import React, { useState, useCallback, useEffect } from 'react';
import { useFHE, FheTypes } from './FHEProvider';
import { Hash, useBalance } from 'wagmi';
import { formatUnits, parseUnits } from 'viem';

interface ConfidentialFundingPoolProps {
  poolAddress: Hash;
  tokenAddress: Hash;
  currentUser: Hash;
  minDeposit?: bigint;
  maxDeposit?: bigint;
}

// ── Mock Pool State ────────────────────────────────────────────────────────────

interface PoolStats {
  totalDeposits: bigint;
  investorCount: bigint;
  currentRound: bigint;
  maxCapacity: bigint;
}

export function ConfidentialFundingPool({
  poolAddress,
  tokenAddress,
  currentUser,
  minDeposit = 0n,
  maxDeposit = parseUnits('1000000', 18), // 1M default max
}: ConfidentialFundingPoolProps) {
  const { encryptUint128, decryptForView, isConnected, isEncrypting } = useFHE();
  
  const [amount, setAmount] = useState<string>('0');
  const [isSubmitting, setIsSubmitting] = useState(false);
  const [activeTab, setActiveTab] = useState<'deposit' | 'withdraw'>('deposit');
  const [error, setError] = useState<string | null>(null);
  const [success, setSuccess] = useState<string | null>(null);
  
  // Mock pool stats
  const [poolStats] = useState<PoolStats>({
    totalDeposits: parseUnits('500000', 18),
    investorCount: 42n,
    currentRound: 3n,
    maxCapacity: parseUnits('1000000', 18),
  });

  // User's encrypted balance
  const [myBalance, setMyBalance] = useState<bigint | null>(null);
  const [isLoadingBalance, setIsLoadingBalance] = useState(false);

  // Decrypt own balance when connected
  const loadMyBalance = useCallback(async () => {
    if (!isConnected) return;
    
    setIsLoadingBalance(true);
    try {
      // TODO: Call contract getMyEncryptedBalance()
      // const ctHash = await contract.read.getMyEncryptedBalance();
      // const balance = await decryptForView(ctHash, FheTypes.Uint128);
      // setMyBalance(balance as bigint);
      
      // Mock for demo
      setTimeout(() => {
        setMyBalance(parseUnits('5000', 18));
        setIsLoadingBalance(false);
      }, 1000);
    } catch (err) {
      console.error('Failed to load balance:', err);
      setIsLoadingBalance(false);
    }
  }, [isConnected, decryptForView]);

  useEffect(() => {
    loadMyBalance();
  }, [loadMyBalance]);

  // Encrypt deposit amount
  const handleDeposit = useCallback(async () => {
    if (!isConnected) {
      setError('Please connect your wallet');
      return;
    }

    const amountBigInt = parseUnits(amount, 18);
    
    if (amountBigInt < minDeposit) {
      setError(`Minimum deposit is ${formatUnits(minDeposit, 18)} tokens`);
      return;
    }

    if (amountBigInt > maxDeposit) {
      setError(`Maximum deposit is ${formatUnits(maxDeposit, 18)} tokens`);
      return;
    }

    if (amountBigInt > poolStats.maxCapacity - poolStats.totalDeposits) {
      setError('Amount exceeds remaining pool capacity');
      return;
    }

    try {
      setIsSubmitting(true);
      setError(null);
      setSuccess(null);

      // Encrypt the deposit amount
      const encryptedAmount = await encryptUint128(amountBigInt);
      
      console.log('Encrypted deposit:', encryptedAmount);

      // TODO: Call contract deposit(encryptedAmount)
      // await contractWrite.deposit({ encryptedAmount });

      // Simulate successful deposit
      await new Promise(resolve => setTimeout(resolve, 2000));

      setSuccess(`Deposited ${amount} tokens (encrypted)`);
      setAmount('0');
      
      // Refresh balance
      loadMyBalance();

    } catch (err) {
      const message = err instanceof Error ? err.message : 'Failed to deposit';
      setError(message);
    } finally {
      setIsSubmitting(false);
    }
  }, [isConnected, amount, minDeposit, maxDeposit, poolStats, encryptUint128, loadMyBalance]);

  // Handle withdraw
  const handleWithdraw = useCallback(async () => {
    if (!isConnected) {
      setError('Please connect your wallet');
      return;
    }

    if (!myBalance || myBalance === 0n) {
      setError('No balance to withdraw');
      return;
    }

    const amountBigInt = parseUnits(amount, 18);
    
    if (amountBigInt > myBalance) {
      setError(`Cannot withdraw more than your balance (${formatUnits(myBalance, 18)} tokens)`);
      return;
    }

    try {
      setIsSubmitting(true);
      setError(null);
      setSuccess(null);

      // Encrypt withdraw amount
      const encryptedAmount = await encryptUint128(amountBigInt);

      console.log('Encrypted withdraw:', encryptedAmount);

      // TODO: Call contract withdraw(encryptedAmount)
      // await contractWrite.withdraw({ encryptedAmount });

      // Simulate successful withdrawal
      await new Promise(resolve => setTimeout(resolve, 2000));

      setSuccess(`Withdrawal initiated for ${amount} tokens (encrypted)`);
      setAmount('0');
      
      // Refresh balance
      loadMyBalance();

    } catch (err) {
      const message = err instanceof Error ? err.message : 'Failed to withdraw';
      setError(message);
    } finally {
      setIsSubmitting(false);
    }
  }, [isConnected, amount, myBalance, encryptUint128, loadMyBalance]);

  // Calculate pool utilization
  const utilization = (poolStats.totalDeposits * 100n) / poolStats.maxCapacity;

  return (
    <div className="confidential-funding-pool p-6 bg-gradient-to-br from-emerald-900/20 to-teal-900/20 rounded-xl border border-emerald-500/30">
      {/* Header */}
      <div className="flex items-center gap-3 mb-6">
        <div className="w-10 h-10 bg-emerald-600 rounded-lg flex items-center justify-center">
          <svg className="w-6 h-6 text-white" fill="none" viewBox="0 0 24 24" stroke="currentColor">
            <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M12 8c-1.657 0-3 .895-3 2s1.343 2 3 2 3 .895 3 2-1.343 2-3 2m0-8c1.11 0 2.08.402 2.599 1M12 8V7m0 1v8m0 0v1m0-1c-1.11 0-2.08-.402-2.599-1M21 12a9 9 0 11-18 0 9 9 0 0118 0z" />
          </svg>
        </div>
        <div>
          <h3 className="text-lg font-semibold text-white">Confidential Funding Pool</h3>
          <p className="text-sm text-gray-400">Deposit amounts are encrypted</p>
        </div>
      </div>

      {/* Pool Stats */}
      <div className="grid grid-cols-2 gap-4 mb-6">
        <div className="p-4 bg-black/30 rounded-lg">
          <p className="text-xs text-gray-400 mb-1">Total Deposits</p>
          <p className="text-lg font-semibold text-white font-mono">
            {formatUnits(poolStats.totalDeposits, 18)} ETH
          </p>
        </div>
        <div className="p-4 bg-black/30 rounded-lg">
          <p className="text-xs text-gray-400 mb-1">Pool Capacity</p>
          <div className="flex items-center gap-2">
            <div className="flex-1 h-2 bg-gray-700 rounded-full overflow-hidden">
              <div 
                className="h-full bg-emerald-500 transition-all"
                style={{ width: `${Number(utilization)}%` }}
              />
            </div>
            <span className="text-xs text-gray-400">{Number(utilization)}%</span>
          </div>
        </div>
        <div className="p-4 bg-black/30 rounded-lg">
          <p className="text-xs text-gray-400 mb-1">My Balance</p>
          <p className={`text-lg font-semibold font-mono ${isLoadingBalance ? 'text-gray-400' : 'text-emerald-400'}`}>
            {isLoadingBalance ? 'Loading...' : formatUnits(myBalance || 0n, 18)}
          </p>
          <p className="text-xs text-gray-500">Encrypted balance</p>
        </div>
        <div className="p-4 bg-black/30 rounded-lg">
          <p className="text-xs text-gray-400 mb-1">Current Round</p>
          <p className="text-lg font-semibold text-white">#{poolStats.currentRound.toString()}</p>
        </div>
      </div>

      {/* Tab Switcher */}
      <div className="flex gap-2 mb-6">
        <button
          onClick={() => { setActiveTab('deposit'); setError(null); setSuccess(null); }}
          className={`flex-1 py-2 px-4 rounded-lg font-medium transition-all ${
            activeTab === 'deposit'
              ? 'bg-emerald-600 text-white'
              : 'bg-gray-700 text-gray-400 hover:bg-gray-600'
          }`}
        >
          Deposit
        </button>
        <button
          onClick={() => { setActiveTab('withdraw'); setError(null); setSuccess(null); }}
          className={`flex-1 py-2 px-4 rounded-lg font-medium transition-all ${
            activeTab === 'withdraw'
              ? 'bg-blue-600 text-white'
              : 'bg-gray-700 text-gray-400 hover:bg-gray-600'
          }`}
        >
          Withdraw
        </button>
      </div>

      {/* Amount Input */}
      <div className="mb-6">
        <label className="block text-sm text-gray-400 mb-2">
          Amount ({activeTab === 'deposit' ? 'to deposit' : 'to withdraw'})
        </label>
        <div className="relative">
          <input
            type="number"
            value={amount}
            onChange={(e) => setAmount(e.target.value)}
            min="0"
            step="0.01"
            className="w-full p-3 pr-16 bg-black/30 border border-gray-600 rounded-lg text-white font-mono focus:border-emerald-500 focus:outline-none"
            placeholder="0.0"
          />
          <span className="absolute right-4 top-1/2 -translate-y-1/2 text-gray-500">ETH</span>
        </div>
        <div className="flex justify-between mt-2 text-xs text-gray-500">
          <span>Min: {formatUnits(minDeposit, 18)} ETH</span>
          <span>Max: {formatUnits(maxDeposit, 18)} ETH</span>
        </div>
      </div>

      {/* Quick Amount Buttons */}
      <div className="flex gap-2 mb-6">
        {[0.1, 0.5, 1, 5].map(val => (
          <button
            key={val}
            onClick={() => setAmount(val.toString())}
            className="flex-1 py-2 px-3 bg-gray-700 hover:bg-gray-600 rounded-lg text-sm text-gray-300 transition-all"
          >
            {val} ETH
          </button>
        ))}
        <button
          onClick={() => myBalance && setAmount(formatUnits(myBalance, 18))}
          className="flex-1 py-2 px-3 bg-gray-700 hover:bg-gray-600 rounded-lg text-sm text-emerald-400 transition-all"
        >
          Max
        </button>
      </div>

      {/* Submit Button */}
      <button
        onClick={activeTab === 'deposit' ? handleDeposit : handleWithdraw}
        disabled={isSubmitting || isEncrypting || !isConnected}
        className={`w-full py-3 rounded-lg font-semibold transition-all ${
          isSubmitting || isEncrypting
            ? 'bg-gray-600 cursor-not-allowed'
            : activeTab === 'deposit'
              ? 'bg-emerald-600 hover:bg-emerald-700 text-white'
              : 'bg-blue-600 hover:bg-blue-700 text-white'
        }`}
      >
        {isSubmitting || isEncrypting ? (
          <span className="flex items-center justify-center gap-2">
            <svg className="animate-spin h-5 w-5" viewBox="0 0 24 24">
              <circle className="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" strokeWidth="4" fill="none" />
              <path className="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4z" />
            </svg>
            Encrypting...
          </span>
        ) : (
          activeTab === 'deposit' ? 'Deposit (Encrypted)' : 'Withdraw (Encrypted)'
        )}
      </button>

      {/* Error Display */}
      {error && (
        <div className="mt-4 p-3 bg-red-500/20 border border-red-500/30 rounded-lg text-red-400 text-sm">
          {error}
        </div>
      )}

      {/* Success Display */}
      {success && (
        <div className="mt-4 p-3 bg-green-500/20 border border-green-500/30 rounded-lg text-green-400 text-sm">
          ✓ {success}
        </div>
      )}

      {/* Privacy Notice */}
      <div className="mt-6 p-3 bg-emerald-500/10 border border-emerald-500/20 rounded-lg">
        <div className="flex items-start gap-2">
          <svg className="w-5 h-5 text-emerald-400 mt-0.5" fill="none" viewBox="0 0 24 24" stroke="currentColor">
            <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M9 12l2 2 4-4m5.618-4.016A11.955 11.955 0 0112 2.944a11.955 11.955 0 01-8.618 3.04A12.02 12.02 0 003 9c0 5.591 3.824 10.29 9 11.622 5.176-1.332 9-6.03 9-11.622 0-1.042-.133-2.052-.382-3.016z" />
          </svg>
          <div className="text-sm text-gray-400">
            <p className="font-semibold text-emerald-400">Encrypted Transactions</p>
            <p className="mt-1">Your deposit/withdrawal amounts are encrypted using Fully Homomorphic Encryption. No one can see how much you're investing.</p>
          </div>
        </div>
      </div>
    </div>
  );
}

export default ConfidentialFundingPool;