'use client';

/**
 * Encrypted Swap Component
 * 
 * P2P encrypted token swap interface with sealed bids.
 * Users can create and accept encrypted offers without revealing amounts.
 */

import React, { useState, useCallback, useEffect } from 'react';
import { useFHE, FheTypes } from './FHEProvider';
import { Hash } from 'viem';
import { formatUnits, parseUnits } from 'viem';

interface SwapOffer {
  id: Hash;
  maker: Hash;
  tokenA: Hash;
  tokenB: Hash;
  encryptedAmountA: Hash;
  encryptedAmountB: Hash;
  expiresAt: bigint;
  status: 'open' | 'filled' | 'cancelled';
}

interface EncryptedSwapProps {
  swapContractAddress: Hash;
  supportedTokens: Hash[];
  currentUser: Hash;
}

export function EncryptedSwap({
  swapContractAddress,
  supportedTokens,
  currentUser,
}: EncryptedSwapProps) {
  const { encryptUint128, decryptForView, isConnected, isEncrypting } = useFHE();

  const [activeTab, setActiveTab] = useState<'create' | 'browse'>('create');
  const [tokenA, setTokenA] = useState<Hash>(supportedTokens[0] || '0x0000000000000000000000000000000000000001');
  const [tokenB, setTokenB] = useState<Hash>(supportedTokens[1] || '0x0000000000000000000000000000000000000002');
  const [amountA, setAmountA] = useState<string>('0');
  const [amountB, setAmountB] = useState<string>('0');
  const [expiryHours, setExpiryHours] = useState<24>();

  const [isSubmitting, setIsSubmitting] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [success, setSuccess] = useState<string | null>(null);
  
  // Open offers
  const [offers, setOffers] = useState<SwapOffer[]>([]);
  const [selectedOffer, setSelectedOffer] = useState<SwapOffer | null>(null);

  // Load open offers
  useEffect(() => {
    // TODO: Load from contract
    // const openOffers = await contract.read.getOpenOffers();
    // setOffers(openOffers);
  }, []);

  // Create encrypted swap offer
  const handleCreateOffer = useCallback(async () => {
    if (!isConnected) {
      setError('Please connect your wallet');
      return;
    }

    if (tokenA === tokenB) {
      setError('Token A and B must be different');
      return;
    }

    const amountABigInt = parseUnits(amountA, 18);
    const amountBBigInt = parseUnits(amountB, 18);

    if (amountABigInt <= 0n || amountBBigInt <= 0n) {
      setError('Amounts must be greater than 0');
      return;
    }

    try {
      setIsSubmitting(true);
      setError(null);
      setSuccess(null);

      // Encrypt both amounts
      const [encryptedAmountA, encryptedAmountB] = await Promise.all([
        encryptUint128(amountABigInt),
        encryptUint128(amountBBigInt),
      ]);

      console.log('Creating encrypted offer:', {
        tokenA,
        tokenB,
        encryptedAmountA,
        encryptedAmountB,
        expiresAt: BigInt(Math.floor(Date.now() / 1000) + expiryHours * 3600),
      });

      // TODO: Call contract createOffer(...)
      // const tx = await contractWrite.createOffer({
      //   tokenA,
      //   tokenB,
      //   encryptedAmountA,
      //   encryptedAmountB,
      //   expiryBlocks,
      // });

      // Simulate success
      await new Promise(resolve => setTimeout(resolve, 2000));

      setSuccess(`Swap offer created (encrypted amounts)`);
      setAmountA('0');
      setAmountB('0');

    } catch (err) {
      const message = err instanceof Error ? err.message : 'Failed to create offer';
      setError(message);
    } finally {
      setIsSubmitting(false);
    }
  }, [isConnected, tokenA, tokenB, amountA, amountB, expiryHours, encryptUint128]);

  // Accept encrypted offer
  const handleAcceptOffer = useCallback(async (offer: SwapOffer) => {
    if (!isConnected) {
      setError('Please connect your wallet');
      return;
    }

    try {
      setIsSubmitting(true);
      setError(null);

      // TODO: Call contract acceptOffer(offer.id)
      // This will use threshold decryption to verify both parties have sufficient balances

      // Simulate acceptance
      await new Promise(resolve => setTimeout(resolve, 2000));

      setSuccess('Offer accepted! Swap executed.');
      setSelectedOffer(null);

    } catch (err) {
      const message = err instanceof Error ? err.message : 'Failed to accept offer';
      setError(message);
    } finally {
      setIsSubmitting(false);
    }
  }, [isConnected]);

  // Cancel offer
  const handleCancelOffer = useCallback(async (offer: SwapOffer) => {
    try {
      setIsSubmitting(true);
      setError(null);

      // TODO: Call contract cancelOffer(offer.id)

      // Simulate cancellation
      await new Promise(resolve => setTimeout(resolve, 1000));

      setSuccess('Offer cancelled.');
      setOffers(prev => prev.filter(o => o.id !== offer.id));

    } catch (err) {
      const message = err instanceof Error ? err.message : 'Failed to cancel offer';
      setError(message);
    } finally {
      setIsSubmitting(false);
    }
  }, []);

  // View offer details (decrypt amounts)
  const viewOfferDetails = useCallback(async (offer: SwapOffer) => {
    setSelectedOffer(offer);

    try {
      // Decrypt the amounts to view
      const [decryptedAmountA, decryptedAmountB] = await Promise.all([
        decryptForView(offer.encryptedAmountA, FheTypes.Uint128),
        decryptForView(offer.encryptedAmountB, FheTypes.Uint128),
      ]);

      console.log('Offer details decrypted:', {
        amountA: decryptedAmountA,
        amountB: decryptedAmountB,
      });
    } catch (err) {
      console.error('Failed to decrypt offer:', err);
    }
  }, [decryptForView]);

  // Format time remaining
  const formatTimeRemaining = (expiresAt: bigint): string => {
    const now = BigInt(Math.floor(Date.now() / 1000));
    const remaining = expiresAt - now;
    
    if (remaining <= 0n) return 'Expired';
    
    const hours = remaining / 3600n;
    const minutes = (remaining % 3600n) / 60n;
    
    return `${hours}h ${minutes}m`;
  };

  return (
    <div className="encrypted-swap p-6 bg-gradient-to-br from-amber-900/20 to-orange-900/20 rounded-xl border border-amber-500/30">
      {/* Header */}
      <div className="flex items-center gap-3 mb-6">
        <div className="w-10 h-10 bg-amber-600 rounded-lg flex items-center justify-center">
          <svg className="w-6 h-6 text-white" fill="none" viewBox="0 0 24 24" stroke="currentColor">
            <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M8 7h12m0 0l-4-4m4 4l-4 4m0 6H4m0 0l4 4m-4-4l4-4" />
          </svg>
        </div>
        <div>
          <h3 className="text-lg font-semibold text-white">Encrypted P2P Swap</h3>
          <p className="text-sm text-gray-400">Trade with encrypted amounts</p>
        </div>
      </div>

      {/* Tab Switcher */}
      <div className="flex gap-2 mb-6">
        <button
          onClick={() => { setActiveTab('create'); setError(null); setSuccess(null); }}
          className={`flex-1 py-2 px-4 rounded-lg font-medium transition-all ${
            activeTab === 'create'
              ? 'bg-amber-600 text-white'
              : 'bg-gray-700 text-gray-400 hover:bg-gray-600'
          }`}
        >
          Create Offer
        </button>
        <button
          onClick={() => { setActiveTab('browse'); setError(null); setSuccess(null); }}
          className={`flex-1 py-2 px-4 rounded-lg font-medium transition-all ${
            activeTab === 'browse'
              ? 'bg-amber-600 text-white'
              : 'bg-gray-700 text-gray-400 hover:bg-gray-600'
          }`}
        >
          Browse Offers
        </button>
      </div>

      {/* Create Offer Form */}
      {activeTab === 'create' && (
        <div className="space-y-4">
          {/* Token Selection */}
          <div className="grid grid-cols-2 gap-4">
            <div>
              <label className="block text-xs text-gray-400 mb-1">You Give</label>
              <select
                value={tokenA}
                onChange={(e) => setTokenA(e.target.value as Hash)}
                className="w-full p-3 bg-black/30 border border-gray-600 rounded-lg text-white focus:border-amber-500 focus:outline-none"
              >
                {supportedTokens.map(token => (
                  <option key={token} value={token}>
                    Token {token.slice(0, 6)}...{token.slice(-4)}
                  </option>
                ))}
              </select>
            </div>
            <div>
              <label className="block text-xs text-gray-400 mb-1">You Get</label>
              <select
                value={tokenB}
                onChange={(e) => setTokenB(e.target.value as Hash)}
                className="w-full p-3 bg-black/30 border border-gray-600 rounded-lg text-white focus:border-amber-500 focus:outline-none"
              >
                {supportedTokens.map(token => (
                  <option key={token} value={token}>
                    Token {token.slice(0, 6)}...{token.slice(-4)}
                  </option>
                ))}
              </select>
            </div>
          </div>

          {/* Amount Inputs */}
          <div className="grid grid-cols-2 gap-4">
            <div>
              <label className="block text-xs text-gray-400 mb-1">Amount to Give</label>
              <input
                type="number"
                value={amountA}
                onChange={(e) => setAmountA(e.target.value)}
                placeholder="0.0"
                className="w-full p-3 bg-black/30 border border-gray-600 rounded-lg text-white font-mono focus:border-amber-500 focus:outline-none"
              />
            </div>
            <div>
              <label className="block text-xs text-gray-400 mb-1">Amount to Receive</label>
              <input
                type="number"
                value={amountB}
                onChange={(e) => setAmountB(e.target.value)}
                placeholder="0.0"
                className="w-full p-3 bg-black/30 border border-gray-600 rounded-lg text-white font-mono focus:border-amber-500 focus:outline-none"
              />
            </div>
          </div>

          {/* Expiry */}
          <div>
            <label className="block text-xs text-gray-400 mb-1">Offer Expires In</label>
            <select
              value={expiryHours}
              onChange={(e) => setExpiryHours(Number(e.target.value) as 24)}
              className="w-full p-3 bg-black/30 border border-gray-600 rounded-lg text-white focus:border-amber-500 focus:outline-none"
            >
              <option value={1}>1 hour</option>
              <option value={6}>6 hours</option>
              <option value={24}>24 hours</option>
              <option value={72}>3 days</option>
              <option value={168}>7 days</option>
            </select>
          </div>

          {/* Submit Button */}
          <button
            onClick={handleCreateOffer}
            disabled={isSubmitting || isEncrypting || !isConnected}
            className={`w-full py-3 rounded-lg font-semibold transition-all ${
              isSubmitting || isEncrypting
                ? 'bg-gray-600 cursor-not-allowed'
                : 'bg-amber-600 hover:bg-amber-700 text-white'
            }`}
          >
            {isSubmitting || isEncrypting ? (
              <span className="flex items-center justify-center gap-2">
                <svg className="animate-spin h-5 w-5" viewBox="0 0 24 24">
                  <circle className="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" strokeWidth="4" fill="none" />
                  <path className="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4z" />
                </svg>
                Encrypting Offer...
              </span>
            ) : (
              'Create Encrypted Offer'
            )}
          </button>
        </div>
      )}

      {/* Browse Offers */}
      {activeTab === 'browse' && (
        <div className="space-y-4">
          {offers.length === 0 ? (
            <div className="text-center py-8 text-gray-500">
              <p>No open offers</p>
              <button
                onClick={() => setActiveTab('create')}
                className="mt-2 text-amber-400 hover:underline"
              >
                Create the first offer
              </button>
            </div>
          ) : (
            offers.map(offer => (
              <div
                key={offer.id}
                className="p-4 bg-black/30 rounded-lg border border-gray-700 hover:border-amber-500/50 transition-all"
              >
                <div className="flex justify-between items-start mb-3">
                  <div className="flex items-center gap-2">
                    <span className="text-xs text-gray-400">
                      Maker: {offer.maker.slice(0, 6)}...{offer.maker.slice(-4)}
                    </span>
                    <span className={`px-2 py-0.5 rounded text-xs ${
                      offer.status === 'open' ? 'bg-green-600/20 text-green-400' : 'bg-gray-600/20 text-gray-400'
                    }`}>
                      {offer.status}
                    </span>
                  </div>
                  <span className="text-xs text-gray-500">
                    Expires: {formatTimeRemaining(offer.expiresAt)}
                  </span>
                </div>

                <div className="flex justify-center items-center gap-4 my-3">
                  <div className="text-center">
                    <p className="text-xs text-gray-400 mb-1">You Give</p>
                    <p className="font-mono text-white">??? ETH</p>
                    <p className="text-xs text-gray-500">{offer.tokenA.slice(0, 8)}...</p>
                  </div>
                  <div className="text-2xl text-amber-500">⇄</div>
                  <div className="text-center">
                    <p className="text-xs text-gray-400 mb-1">You Get</p>
                    <p className="font-mono text-white">??? ETH</p>
                    <p className="text-xs text-gray-500">{offer.tokenB.slice(0, 8)}...</p>
                  </div>
                </div>

                <div className="flex gap-2">
                  <button
                    onClick={() => viewOfferDetails(offer)}
                    className="flex-1 py-2 px-3 bg-gray-700 hover:bg-gray-600 rounded-lg text-sm text-gray-300 transition-all"
                  >
                    View Details
                  </button>
                  {offer.maker.toLowerCase() !== currentUser.toLowerCase() && (
                    <button
                      onClick={() => handleAcceptOffer(offer)}
                      disabled={isSubmitting}
                      className="flex-1 py-2 px-3 bg-green-600 hover:bg-green-700 rounded-lg text-sm text-white transition-all"
                    >
                      Accept
                    </button>
                  )}
                  {offer.maker.toLowerCase() === currentUser.toLowerCase() && (
                    <button
                      onClick={() => handleCancelOffer(offer)}
                      disabled={isSubmitting}
                      className="flex-1 py-2 px-3 bg-red-600 hover:bg-red-700 rounded-lg text-sm text-white transition-all"
                    >
                      Cancel
                    </button>
                  )}
                </div>
              </div>
            ))
          )}
        </div>
      )}

      {/* Selected Offer Modal */}
      {selectedOffer && (
        <div className="fixed inset-0 bg-black/50 flex items-center justify-center z-50 p-4">
          <div className="bg-gray-900 p-6 rounded-xl border border-amber-500/30 max-w-md w-full">
            <h4 className="text-lg font-semibold text-white mb-4">Offer Details</h4>
            <div className="space-y-3">
              <div className="flex justify-between">
                <span className="text-gray-400">Maker</span>
                <span className="text-white font-mono text-sm">
                  {selectedOffer.maker}
                </span>
              </div>
              <div className="flex justify-between">
                <span className="text-gray-400">Status</span>
                <span className="text-green-400">{selectedOffer.status}</span>
              </div>
              <div className="flex justify-between">
                <span className="text-gray-400">Expires</span>
                <span className="text-white">{formatTimeRemaining(selectedOffer.expiresAt)}</span>
              </div>
            </div>
            <div className="mt-6 flex gap-3">
              <button
                onClick={() => setSelectedOffer(null)}
                className="flex-1 py-2 px-4 bg-gray-700 hover:bg-gray-600 rounded-lg text-white transition-all"
              >
                Close
              </button>
              {selectedOffer.maker.toLowerCase() !== currentUser.toLowerCase() && (
                <button
                  onClick={() => handleAcceptOffer(selectedOffer)}
                  disabled={isSubmitting}
                  className="flex-1 py-2 px-4 bg-green-600 hover:bg-green-700 rounded-lg text-white transition-all"
                >
                  Accept Offer
                </button>
              )}
            </div>
          </div>
        </div>
      )}

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
      <div className="mt-6 p-3 bg-amber-500/10 border border-amber-500/20 rounded-lg">
        <div className="flex items-start gap-2">
          <svg className="w-5 h-5 text-amber-400 mt-0.5" fill="none" viewBox="0 0 24 24" stroke="currentColor">
            <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M13 16h-1v-4h-1m1-4h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z" />
          </svg>
          <div className="text-sm text-gray-400">
            <p className="font-semibold text-amber-400">Sealed Bids</p>
            <p className="mt-1">All swap amounts are encrypted. Accepting an offer triggers threshold decryption to verify balances without revealing them.</p>
          </div>
        </div>
      </div>
    </div>
  );
}

export default EncryptedSwap;