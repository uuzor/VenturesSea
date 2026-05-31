'use client';

/**
 * Wallet Connection Component
 * 
 * Supports MetaMask, WalletConnect, and other wallets.
 * Displays connection status and FHE readiness.
 */

import React, { useState, useEffect, useCallback } from 'react';
import { useAccount, useConnect, useDisconnect, useChainId, useSwitchChain } from 'wagmi';
import { Hash } from 'viem';
import { fhenixChain } from '@/lib/wagmi';

interface WalletStatus {
  isConnected: boolean;
  isConnecting: boolean;
  address: Hash | null;
  chainId: number | null;
  isCorrectNetwork: boolean;
  isFHEReady: boolean;
}

interface WalletButtonProps {
  className?: string;
}

export function WalletButton({ className = '' }: WalletButtonProps) {
  const { address, isConnected, chain } = useAccount();
  const { connect, connectors, isPending } = useConnect();
  const { disconnect } = useDisconnect();
  const { switchChain } = useSwitchChain();
  
  const [showMenu, setShowMenu] = useState(false);
  const [showConnectorModal, setShowConnectorModal] = useState(false);

  const isCorrectNetwork = chain?.id === fhenixChain.id;

  const handleConnect = useCallback(() => {
    setShowConnectorModal(true);
  }, []);

  const handleDisconnect = useCallback(() => {
    disconnect();
    setShowMenu(false);
  }, [disconnect]);

  const handleSwitchNetwork = useCallback(() => {
    switchChain({ chainId: fhenixChain.id });
  }, [switchChain]);

  // Format address for display
  const formatAddress = (addr: Hash): string => {
    return `${addr.slice(0, 6)}...${addr.slice(-4)}`;
  };

  if (!isConnected) {
    return (
      <>
        <button
          onClick={handleConnect}
          className={`px-6 py-3 bg-gradient-to-r from-purple-600 to-blue-600 rounded-xl font-semibold text-white hover:opacity-90 transition-all ${className}`}
        >
          {isPending ? (
            <span className="flex items-center gap-2">
              <div className="w-4 h-4 border-2 border-white border-t-transparent rounded-full animate-spin" />
              Connecting...
            </span>
          ) : (
            'Connect Wallet'
          )}
        </button>

        {/* Connector Modal */}
        {showConnectorModal && (
          <div className="fixed inset-0 bg-black/50 flex items-center justify-center z-50 p-4">
            <div className="bg-gray-900 rounded-2xl p-6 max-w-md w-full border border-gray-700">
              <h3 className="text-xl font-bold text-white mb-4">Connect Wallet</h3>
              <p className="text-gray-400 mb-6">Choose a wallet to connect to VenturesSea</p>
              
              <div className="space-y-3">
                {connectors.map((connector) => (
                  <button
                    key={connector.id}
                    onClick={() => {
                      connect({ connector });
                      setShowConnectorModal(false);
                    }}
                    className="w-full p-4 bg-gray-800 hover:bg-gray-700 rounded-xl flex items-center gap-4 transition-all"
                  >
                    <div className="w-10 h-10 bg-gray-700 rounded-lg flex items-center justify-center">
                      {connector.name === 'MetaMask' && (
                        <span className="text-xl">🦊</span>
                      )}
                      {connector.name === 'WalletConnect' && (
                        <span className="text-xl">🔗</span>
                      )}
                      {!['MetaMask', 'WalletConnect'].includes(connector.name) && (
                        <span className="text-xl">👛</span>
                      )}
                    </div>
                    <div className="text-left">
                      <div className="font-semibold text-white">{connector.name}</div>
                      <div className="text-sm text-gray-400">
                        {connector.id === 'injected' ? 'Browser wallet' : 'QR code wallet'}
                      </div>
                    </div>
                  </button>
                ))}
              </div>

              <button
                onClick={() => setShowConnectorModal(false)}
                className="w-full mt-4 py-2 text-gray-400 hover:text-white transition-colors"
              >
                Cancel
              </button>
            </div>
          </div>
        )}
      </>
    );
  }

  // Connected state
  return (
    <div className="relative">
      {/* Network Warning Banner */}
      {!isCorrectNetwork && (
        <div className="mb-3 p-3 bg-yellow-500/20 border border-yellow-500/30 rounded-lg">
          <div className="flex items-center justify-between">
            <span className="text-yellow-400 text-sm">
              Please switch to Fhenix network
            </span>
            <button
              onClick={handleSwitchNetwork}
              className="px-3 py-1 bg-yellow-500 hover:bg-yellow-600 rounded-lg text-sm font-medium text-black transition-all"
            >
              Switch Network
            </button>
          </div>
        </div>
      )}

      {/* Wallet Button */}
      <div className="flex items-center gap-3">
        {/* FHE Ready Indicator */}
        <div className="flex items-center gap-2 px-3 py-2 bg-green-500/10 rounded-lg border border-green-500/30">
          <div className="w-2 h-2 bg-green-500 rounded-full animate-pulse" />
          <span className="text-xs text-green-400">FHE Ready</span>
        </div>

        {/* Connected Wallet */}
        <button
          onClick={() => setShowMenu(!showMenu)}
          className={`px-4 py-2 bg-gray-800 hover:bg-gray-700 rounded-xl flex items-center gap-2 transition-all ${className}`}
        >
          <div className="w-3 h-3 bg-green-500 rounded-full" />
          <span className="font-mono text-white">{formatAddress(address!)}</span>
          <svg className="w-4 h-4 text-gray-400" fill="none" viewBox="0 0 24 24" stroke="currentColor">
            <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M19 9l-7 7-7-7" />
          </svg>
        </button>
      </div>

      {/* Dropdown Menu */}
      {showMenu && (
        <>
          <div 
            className="fixed inset-0 z-40" 
            onClick={() => setShowMenu(false)} 
          />
          <div className="absolute right-0 mt-2 w-64 bg-gray-900 rounded-xl border border-gray-700 shadow-xl z-50 overflow-hidden">
            {/* Address Section */}
            <div className="p-4 border-b border-gray-700">
              <div className="text-xs text-gray-400 mb-1">Connected</div>
              <div className="font-mono text-white text-sm">{address}</div>
            </div>

            {/* Network */}
            <div className="p-4 border-b border-gray-700">
              <div className="text-xs text-gray-400 mb-1">Network</div>
              <div className="flex items-center gap-2">
                <div className={`w-2 h-2 rounded-full ${isCorrectNetwork ? 'bg-green-500' : 'bg-red-500'}`} />
                <span className="text-white text-sm">{chain?.name || 'Unknown'}</span>
              </div>
              {!isCorrectNetwork && (
                <button
                  onClick={handleSwitchNetwork}
                  className="mt-2 w-full py-2 bg-purple-600 hover:bg-purple-700 rounded-lg text-sm font-medium text-white transition-all"
                >
                  Switch to Fhenix
                </button>
              )}
            </div>

            {/* Actions */}
            <div className="p-2">
              <button
                onClick={() => {
                  navigator.clipboard.writeText(address!);
                  setShowMenu(false);
                }}
                className="w-full p-3 text-left hover:bg-gray-800 rounded-lg transition-all"
              >
                <div className="text-sm text-white">Copy Address</div>
              </button>
              <a
                href={`https://explorer.fhenix.io/address/${address}`}
                target="_blank"
                rel="noopener noreferrer"
                className="w-full p-3 text-left hover:bg-gray-800 rounded-lg transition-all block"
              >
                <div className="text-sm text-white">View on Explorer</div>
              </a>
              <button
                onClick={handleDisconnect}
                className="w-full p-3 text-left hover:bg-red-500/10 rounded-lg transition-all"
              >
                <div className="text-sm text-red-400">Disconnect</div>
              </button>
            </div>
          </div>
        </>
      )}
    </div>
  );
}

// ── Wallet Status Indicator ────────────────────────────────────────────────────

export function WalletStatus() {
  const { address, isConnected, chain } = useAccount();
  const { switchChain } = useSwitchChain();
  
  const isCorrectNetwork = chain?.id === fhenixChain.id;
  const isFHEReady = isConnected && isCorrectNetwork;

  return (
    <div className="flex items-center gap-4">
      {/* Connection Status */}
      <div className="flex items-center gap-2">
        <div className={`w-3 h-3 rounded-full ${isConnected ? 'bg-green-500' : 'bg-gray-500'}`} />
        <span className="text-sm text-gray-400">
          {isConnected ? 'Connected' : 'Disconnected'}
        </span>
      </div>

      {/* Network Status */}
      <div className="flex items-center gap-2">
        <div className={`w-3 h-3 rounded-full ${isCorrectNetwork ? 'bg-blue-500' : 'bg-yellow-500'}`} />
        <span className="text-sm text-gray-400">
          {chain?.name || 'No Network'}
        </span>
      </div>

      {/* FHE Ready Status */}
      <div className="flex items-center gap-2">
        <div className={`w-3 h-3 rounded-full ${isFHEReady ? 'bg-purple-500 animate-pulse' : 'bg-gray-600'}`} />
        <span className="text-sm text-gray-400">
          {isFHEReady ? 'FHE Ready' : 'FHE Offline'}
        </span>
      </div>
    </div>
  );
}

// ── Multi-Wallet Support Hook ──────────────────────────────────────────────────

export function useWalletStatus(): WalletStatus {
  const { address, isConnected } = useAccount();
  const chainId = useChainId();
  
  return {
    isConnected,
    isConnecting: false,
    address: address || null,
    chainId,
    isCorrectNetwork: chainId === fhenixChain.id,
    isFHEReady: isConnected && chainId === fhenixChain.id,
  };
}

// ── Quick Connect Buttons ──────────────────────────────────────────────────────

interface QuickConnectProps {
  onConnected?: () => void;
}

export function QuickConnect({ onConnected }: QuickConnectProps) {
  const { connect, connectors, isPending } = useConnect();
  
  const handleConnect = (connectorId: string) => {
    const connector = connectors.find(c => c.id === connectorId);
    if (connector) {
      connect({ connector });
      onConnected?.();
    }
  };

  return (
    <div className="grid grid-cols-2 gap-3">
      {/* MetaMask */}
      <button
        onClick={() => handleConnect('io.metamask')}
        disabled={isPending}
        className="p-4 bg-gray-800 hover:bg-gray-700 rounded-xl flex flex-col items-center gap-2 transition-all disabled:opacity-50"
      >
        <span className="text-3xl">🦊</span>
        <span className="text-sm font-medium text-white">MetaMask</span>
      </button>

      {/* WalletConnect */}
      <button
        onClick={() => handleConnect('walletConnect')}
        disabled={isPending}
        className="p-4 bg-gray-800 hover:bg-gray-700 rounded-xl flex flex-col items-center gap-2 transition-all disabled:opacity-50"
      >
        <span className="text-3xl">🔗</span>
        <span className="text-sm font-medium text-white">WalletConnect</span>
      </button>

      {/* Coinbase Wallet */}
      <button
        onClick={() => handleConnect('coinbaseWalletSDK')}
        disabled={isPending}
        className="p-4 bg-gray-800 hover:bg-gray-700 rounded-xl flex flex-col items-center gap-2 transition-all disabled:opacity-50"
      >
        <span className="text-3xl">💳</span>
        <span className="text-sm font-medium text-white">Coinbase</span>
      </button>

      {/* WalletConnect Mobile */}
      <button
        onClick={() => handleConnect('walletConnect')}
        disabled={isPending}
        className="p-4 bg-gray-800 hover:bg-gray-700 rounded-xl flex flex-col items-center gap-2 transition-all disabled:opacity-50"
      >
        <span className="text-3xl">📱</span>
        <span className="text-sm font-medium text-white">Mobile</span>
      </button>
    </div>
  );
}