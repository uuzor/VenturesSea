'use client';

/**
 * FHE Demo Page
 * 
 * Interactive demonstration of VenturesSea confidential computing features.
 */

import React, { useState, useEffect } from 'react';
import { useAccount } from 'wagmi';
import { 
  FHEProvider,
  ConfidentialVoting,
  ConfidentialFundingPool,
  EncryptedSwap
} from '@/components/fhe';
import { Hash } from 'viem';

// Mock contract addresses
const MOCK_ADDRESSES = {
  dao: '0x1234567890123456789012345678901234567890' as Hash,
  pool: '0x2345678901234567890123456789012345678901' as Hash,
  swap: '0x3456789012345678901234567890123456789012' as Hash,
  tokens: [
    '0x4567890123456789012345678901234567890123' as Hash,
    '0x5678901234567890123456789012345678901234' as Hash,
  ] as Hash[],
};

type DemoFeature = 'voting' | 'funding' | 'swap';

export default function FHEDemoPage() {
  const { address, isConnected } = useAccount();
  const [activeFeature, setActiveFeature] = useState<DemoFeature>('voting');
  const [fheStatus, setFheStatus] = useState<'initializing' | 'ready' | 'error'>('initializing');

  // Simulate FHE initialization
  useEffect(() => {
    const init = async () => {
      // Simulate SDK initialization delay
      await new Promise(resolve => setTimeout(resolve, 1500));
      setFheStatus('ready');
    };
    init();
  }, []);

  return (
    <FHEProvider>
      <div className="min-h-screen bg-gray-950 text-white">
        {/* Header */}
        <header className="border-b border-gray-800 bg-black/50 backdrop-blur-sm sticky top-0 z-50">
          <div className="max-w-7xl mx-auto px-4 py-4">
            <div className="flex items-center justify-between">
              <div className="flex items-center gap-3">
                <div className="w-10 h-10 bg-gradient-to-br from-purple-600 to-blue-600 rounded-lg flex items-center justify-center">
                  <svg className="w-6 h-6 text-white" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                    <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M12 15v2m-6 4h12a2 2 0 002-2v-6a2 2 0 00-2-2H6a2 2 0 00-2 2v6a2 2 0 002 2zm10-10V7a4 4 0 00-8 0v4h8z" />
                  </svg>
                </div>
                <div>
                  <h1 className="font-bold text-lg">VenturesSea FHE Demo</h1>
                  <p className="text-xs text-gray-400">Confidential Computing Showcase</p>
                </div>
              </div>

              {/* Wallet Connection */}
              <div className="flex items-center gap-4">
                {fheStatus === 'initializing' && (
                  <div className="flex items-center gap-2 px-4 py-2 bg-purple-500/10 rounded-lg">
                    <div className="w-4 h-4 border-2 border-purple-500 border-t-transparent rounded-full animate-spin" />
                    <span className="text-sm text-purple-400">Initializing FHE...</span>
                  </div>
                )}
                {fheStatus === 'ready' && (
                  <div className="flex items-center gap-2 px-4 py-2 bg-green-500/10 rounded-lg">
                    <div className="w-3 h-3 bg-green-500 rounded-full" />
                    <span className="text-sm text-green-400">FHE Ready</span>
                  </div>
                )}
                {isConnected ? (
                  <div className="px-4 py-2 bg-gray-800 rounded-lg">
                    <span className="text-sm font-mono text-gray-300">
                      {address?.slice(0, 6)}...{address?.slice(-4)}
                    </span>
                  </div>
                ) : (
                  <button className="px-6 py-2 bg-purple-600 hover:bg-purple-700 rounded-lg font-medium transition-colors">
                    Connect Wallet
                  </button>
                )}
              </div>
            </div>
          </div>
        </header>

        {/* Main Content */}
        <main className="max-w-7xl mx-auto px-4 py-8">
          {/* Feature Navigation */}
          <div className="mb-8">
            <h2 className="text-2xl font-bold mb-4">Confidential Features</h2>
            <div className="flex gap-4">
              {[
                { id: 'voting', label: 'Confidential Voting', icon: '🗳️', desc: 'Sealed-bid voting for proposals' },
                { id: 'funding', label: 'Private Funding', icon: '💰', desc: 'Encrypted deposit amounts' },
                { id: 'swap', label: 'Encrypted Swap', icon: '🔄', desc: 'P2P trading with hidden values' },
              ].map(feature => (
                <button
                  key={feature.id}
                  onClick={() => setActiveFeature(feature.id as DemoFeature)}
                  className={`flex-1 p-6 rounded-xl border transition-all ${
                    activeFeature === feature.id
                      ? 'bg-purple-900/30 border-purple-500/50'
                      : 'bg-gray-900 border-gray-700 hover:border-gray-600'
                  }`}
                >
                  <div className="text-3xl mb-2">{feature.icon}</div>
                  <div className="font-semibold text-white">{feature.label}</div>
                  <div className="text-sm text-gray-400 mt-1">{feature.desc}</div>
                </button>
              ))}
            </div>
          </div>

          {/* Feature Content */}
          <div className="grid lg:grid-cols-3 gap-8">
            {/* Main Feature Panel */}
            <div className="lg:col-span-2">
              <div className="bg-gray-900 rounded-2xl p-6 border border-gray-800">
                {activeFeature === 'voting' && (
                  <ConfidentialVoting
                    daoAddress={MOCK_ADDRESSES.dao}
                    proposalId={'0x' + '11'.repeat(32) as Hash}
                    currentUser={address || '0x' + '00'.repeat(20) as Hash}
                    minVoteAmount={BigInt(1e18)}
                  />
                )}
                {activeFeature === 'funding' && (
                  <ConfidentialFundingPool
                    poolAddress={MOCK_ADDRESSES.pool}
                    tokenAddress={MOCK_ADDRESSES.tokens[0]}
                    currentUser={address || '0x' + '00'.repeat(20) as Hash}
                  />
                )}
                {activeFeature === 'swap' && (
                  <EncryptedSwap
                    swapContractAddress={MOCK_ADDRESSES.swap}
                    supportedTokens={MOCK_ADDRESSES.tokens}
                    currentUser={address || '0x' + '00'.repeat(20) as Hash}
                  />
                )}
              </div>
            </div>

            {/* Info Sidebar */}
            <div className="space-y-6">
              {/* How It Works */}
              <div className="bg-gray-900 rounded-2xl p-6 border border-gray-800">
                <h3 className="font-bold text-lg mb-4 flex items-center gap-2">
                  <span className="text-purple-400">🔐</span>
                  How It Works
                </h3>
                <div className="space-y-4">
                  <div className="flex gap-3">
                    <div className="w-8 h-8 bg-purple-600 rounded-full flex items-center justify-center text-sm font-bold shrink-0">
                      1
                    </div>
                    <div>
                      <p className="font-medium">Encrypt</p>
                      <p className="text-sm text-gray-400">Your data is encrypted locally using FHE before being sent to the blockchain.</p>
                    </div>
                  </div>
                  <div className="flex gap-3">
                    <div className="w-8 h-8 bg-purple-600 rounded-full flex items-center justify-center text-sm font-bold shrink-0">
                      2
                    </div>
                    <div>
                      <p className="font-medium">Compute</p>
                      <p className="text-sm text-gray-400">Smart contracts operate on encrypted data without ever seeing your actual values.</p>
                    </div>
                  </div>
                  <div className="flex gap-3">
                    <div className="w-8 h-8 bg-purple-600 rounded-full flex items-center justify-center text-sm font-bold shrink-0">
                      3
                    </div>
                    <div>
                      <p className="font-medium">Decrypt</p>
                      <p className="text-sm text-gray-400">Only authorized parties (with permits) can decrypt results via threshold decryption.</p>
                    </div>
                  </div>
                </div>
              </div>

              {/* Security Info */}
              <div className="bg-gradient-to-br from-purple-900/30 to-blue-900/30 rounded-2xl p-6 border border-purple-500/30">
                <h3 className="font-bold text-lg mb-4 flex items-center gap-2">
                  <span>🛡️</span>
                  Security Guarantees
                </h3>
                <ul className="space-y-3 text-sm">
                  <li className="flex items-start gap-2">
                    <span className="text-green-400 mt-0.5">✓</span>
                    <span>End-to-end encryption for all sensitive data</span>
                  </li>
                  <li className="flex items-start gap-2">
                    <span className="text-green-400 mt-0.5">✓</span>
                    <span>ZK proofs verify encryption correctness</span>
                  </li>
                  <li className="flex items-start gap-2">
                    <span className="text-green-400 mt-0.5">✓</span>
                    <span>Threshold decryption prevents single points of failure</span>
                  </li>
                  <li className="flex items-start gap-2">
                    <span className="text-green-400 mt-0.5">✓</span>
                    <span>No plaintext values ever touch the blockchain</span>
                  </li>
                </ul>
              </div>

              {/* SDK Info */}
              <div className="bg-gray-900 rounded-2xl p-6 border border-gray-800">
                <h3 className="font-bold text-lg mb-3">CoFHE SDK</h3>
                <p className="text-sm text-gray-400 mb-4">
                  Built with @cofhe/sdk for Fhenix network integration.
                </p>
                <code className="block bg-black/30 p-3 rounded-lg text-xs text-gray-300 overflow-x-auto">
                  {`npm install @cofhe/sdk @cofhe/sdk/web`}
                </code>
              </div>
            </div>
          </div>
        </main>

        {/* Footer */}
        <footer className="border-t border-gray-800 mt-12 py-8">
          <div className="max-w-7xl mx-auto px-4 text-center text-gray-500 text-sm">
            <p>VenturesSea Confidential Computing Demo • Powered by Fhenix & CoFHE</p>
            <p className="mt-2">
              <span className="text-purple-400">FHE</span> enables privacy-preserving smart contracts
            </p>
          </div>
        </footer>
      </div>
    </FHEProvider>
  );
}