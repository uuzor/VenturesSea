'use client';

/**
 * Privacy Controls Component
 * 
 * Manages selective disclosure and privacy settings for FHE data.
 */

import React, { useState, useCallback } from 'react';
import { Hash } from 'viem';
import { 
  usePrivacySettings, 
  usePrivacyDashboard,
  useSelectiveDisclosure,
  PrivacyLevel 
} from '@/hooks/privacy';

interface PrivacyControlsProps {
  dataKey: string;
  onReveal?: () => void;
}

export function PrivacyControls({ dataKey, onReveal }: PrivacyControlsProps) {
  const { canReveal, updatePolicy, disclosurePolicies } = usePrivacySettings();
  const { logReveal } = usePrivacyDashboard();
  const { grantAccess, revokeAccess, canAccess } = useSelectiveDisclosure();
  
  const [showSettings, setShowSettings] = useState(false);
  const [selectedLevel, setSelectedLevel] = useState<PrivacyLevel>(
    disclosurePolicies[dataKey]?.level || PrivacyLevel.PERMIT_REQUIRED
  );
  const [allowedAddresses, setAllowedAddresses] = useState<Hash[]>(
    disclosurePolicies[dataKey]?.allowedAddresses || []
  );
  const [newAddress, setNewAddress] = useState('');

  const currentPolicy = disclosurePolicies[dataKey];
  const canCurrentlyReveal = canReveal(dataKey, '0x0000000000000000000000000000000000000000' as Hash);

  const handleReveal = useCallback(() => {
    if (canCurrentlyReveal) {
      logReveal(dataKey);
      onReveal?.();
    }
  }, [canCurrentlyReveal, dataKey, logReveal, onReveal]);

  const handleAddAddress = useCallback(() => {
    if (newAddress && newAddress.startsWith('0x')) {
      setAllowedAddresses(prev => [...prev, newAddress as Hash]);
      setNewAddress('');
    }
  }, [newAddress]);

  const handleRemoveAddress = useCallback((addr: Hash) => {
    setAllowedAddresses(prev => prev.filter(a => a !== addr));
  }, []);

  const handleSaveSettings = useCallback(() => {
    updatePolicy(dataKey, {
      level: selectedLevel,
      allowedAddresses: selectedLevel === PrivacyLevel.SELECTIVE ? allowedAddresses : undefined,
    });
    setShowSettings(false);
  }, [dataKey, selectedLevel, allowedAddresses, updatePolicy]);

  const getLevelLabel = (level: PrivacyLevel): string => {
    switch (level) {
      case PrivacyLevel.FULL_PRIVATE: return 'Fully Private';
      case PrivacyLevel.SELECTIVE: return 'Selective Disclosure';
      case PrivacyLevel.PERMIT_REQUIRED: return 'Permit Required';
      case PrivacyLevel.PUBLIC: return 'Public';
    }
  };

  return (
    <div className="bg-gray-900 rounded-xl border border-gray-700 overflow-hidden">
      {/* Header */}
      <div className="p-4 border-b border-gray-700 flex items-center justify-between">
        <div className="flex items-center gap-3">
          <div className="w-8 h-8 bg-purple-600 rounded-lg flex items-center justify-center">
            <svg className="w-5 h-5 text-white" fill="none" viewBox="0 0 24 24" stroke="currentColor">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M12 15v2m-6 4h12a2 2 0 002-2v-6a2 2 0 00-2-2H6a2 2 0 00-2 2v6a2 2 0 002 2zm10-10V7a4 4 0 00-8 0v4h8z" />
            </svg>
          </div>
          <div>
            <h3 className="font-semibold text-white">Privacy Controls</h3>
            <p className="text-xs text-gray-400">Manage who can view this data</p>
          </div>
        </div>
        <button
          onClick={() => setShowSettings(!showSettings)}
          className="p-2 hover:bg-gray-800 rounded-lg transition-all"
        >
          <svg className="w-5 h-5 text-gray-400" fill="none" viewBox="0 0 24 24" stroke="currentColor">
            <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M10.325 4.317c.426-1.756 2.924-1.756 3.35 0a1.724 1.724 0 002.573 1.066c1.543-.94 3.31.826 2.37 2.37a1.724 1.724 0 001.065 2.572c1.756.426 1.756 2.924 0 3.35a1.724 1.724 0 00-1.066 2.573c.94 1.543-.826 3.31-2.37 2.37a1.724 1.724 0 00-2.572 1.065c-.426 1.756-2.924 1.756-3.35 0a1.724 1.724 0 00-2.573-1.066c-1.543.94-3.31-.826-2.37-2.37a1.724 1.724 0 00-1.065-2.572c-1.756-.426-1.756-2.924 0-3.35a1.724 1.724 0 001.066-2.573c-.94-1.543.826-3.31 2.37-2.37.996.608 2.296.07 2.572-1.065z" />
            <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M15 12a3 3 0 11-6 0 3 3 0 016 0z" />
          </svg>
        </button>
      </div>

      {/* Current Status */}
      <div className="p-4 bg-gray-800/50">
        <div className="flex items-center justify-between mb-3">
          <span className="text-sm text-gray-400">Current Privacy Level</span>
          <span className={`px-3 py-1 rounded-full text-xs font-medium ${
            currentPolicy?.level === PrivacyLevel.FULL_PRIVATE 
              ? 'bg-red-500/20 text-red-400' 
              : currentPolicy?.level === PrivacyLevel.PUBLIC
                ? 'bg-green-500/20 text-green-400'
                : 'bg-yellow-500/20 text-yellow-400'
          }`}>
            {getLevelLabel(currentPolicy?.level || PrivacyLevel.PERMIT_REQUIRED)}
          </span>
        </div>

        {/* Quick Actions */}
        <div className="flex gap-2">
          <button
            onClick={handleReveal}
            disabled={!canCurrentlyReveal}
            className={`flex-1 py-2 px-4 rounded-lg font-medium transition-all ${
              canCurrentlyReveal
                ? 'bg-purple-600 hover:bg-purple-700 text-white'
                : 'bg-gray-700 text-gray-400 cursor-not-allowed'
            }`}
          >
            Reveal to Self
          </button>
          <button
            onClick={() => grantAccess(dataKey, '0x0000000000000000000000000000000000000000' as Hash, 3600, PrivacyLevel.PERMIT_REQUIRED)}
            className="py-2 px-4 bg-gray-700 hover:bg-gray-600 rounded-lg font-medium text-white transition-all"
          >
            Grant Access
          </button>
        </div>
      </div>

      {/* Settings Panel */}
      {showSettings && (
        <div className="p-4 border-t border-gray-700">
          <h4 className="text-sm font-medium text-white mb-3">Privacy Level</h4>
          <div className="grid grid-cols-2 gap-2 mb-4">
            {Object.values(PrivacyLevel).filter(v => typeof v === 'number').map(level => (
              <button
                key={level}
                onClick={() => setSelectedLevel(level as PrivacyLevel)}
                className={`p-3 rounded-lg border-2 transition-all ${
                  selectedLevel === level
                    ? 'border-purple-500 bg-purple-500/20 text-purple-400'
                    : 'border-gray-700 hover:border-gray-600 text-gray-400'
                }`}
              >
                <div className="text-sm font-medium">{getLevelLabel(level as PrivacyLevel)}</div>
              </button>
            ))}
          </div>

          {/* Selective Disclosure Address List */}
          {selectedLevel === PrivacyLevel.SELECTIVE && (
            <>
              <h4 className="text-sm font-medium text-white mb-3">Allowed Addresses</h4>
              <div className="space-y-2 mb-4">
                {allowedAddresses.map((addr, i) => (
                  <div key={i} className="flex items-center justify-between p-2 bg-gray-800 rounded-lg">
                    <span className="font-mono text-sm text-gray-300">{addr}</span>
                    <button
                      onClick={() => handleRemoveAddress(addr)}
                      className="text-red-400 hover:text-red-300"
                    >
                      <svg className="w-4 h-4" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                        <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M6 18L18 6M6 6l12 12" />
                      </svg>
                    </button>
                  </div>
                ))}
              </div>
              <div className="flex gap-2">
                <input
                  type="text"
                  value={newAddress}
                  onChange={(e) => setNewAddress(e.target.value)}
                  placeholder="0x..."
                  className="flex-1 px-3 py-2 bg-gray-800 border border-gray-700 rounded-lg text-white text-sm font-mono focus:border-purple-500 focus:outline-none"
                />
                <button
                  onClick={handleAddAddress}
                  className="px-4 py-2 bg-purple-600 hover:bg-purple-700 rounded-lg text-white text-sm transition-all"
                >
                  Add
                </button>
              </div>
            </>
          )}

          <button
            onClick={handleSaveSettings}
            className="w-full mt-4 py-2 bg-green-600 hover:bg-green-700 rounded-lg font-medium text-white transition-all"
          >
            Save Privacy Settings
          </button>
        </div>
      )}
    </div>
  );
}

// ── Privacy Dashboard ─────────────────────────────────────────────────────────

export function PrivacyDashboard() {
  const { 
    totalPolicies, 
    activeGrants, 
    recentReveals, 
    isConnected, 
    hasWallet 
  } = usePrivacyDashboard();
  const { getMyGrants } = useSelectiveDisclosure();

  const myGrants = getMyGrants();

  return (
    <div className="bg-gray-900 rounded-xl border border-gray-700 p-6">
      <h3 className="text-lg font-bold text-white mb-4">Privacy Dashboard</h3>
      
      {/* Stats Grid */}
      <div className="grid grid-cols-3 gap-4 mb-6">
        <div className="p-4 bg-gray-800 rounded-lg text-center">
          <div className="text-2xl font-bold text-purple-400">{totalPolicies}</div>
          <div className="text-xs text-gray-400">Privacy Policies</div>
        </div>
        <div className="p-4 bg-gray-800 rounded-lg text-center">
          <div className="text-2xl font-bold text-blue-400">{activeGrants}</div>
          <div className="text-xs text-gray-400">Active Grants</div>
        </div>
        <div className="p-4 bg-gray-800 rounded-lg text-center">
          <div className="text-2xl font-bold text-green-400">{recentReveals}</div>
          <div className="text-xs text-gray-400">Recent Reveals</div>
        </div>
      </div>

      {/* Status */}
      <div className="p-4 bg-gray-800/50 rounded-lg mb-4">
        <div className="flex items-center gap-2">
          <div className={`w-3 h-3 rounded-full ${isConnected ? 'bg-green-500' : 'bg-gray-500'}`} />
          <span className="text-white">Wallet {isConnected ? 'Connected' : 'Disconnected'}</span>
        </div>
        {hasWallet && (
          <div className="mt-2 text-sm text-gray-400">
            You have {myGrants.length} active data access grants
          </div>
        )}
      </div>

      {/* Privacy Levels Legend */}
      <div className="space-y-2 text-sm">
        <div className="flex items-center gap-2">
          <div className="w-3 h-3 bg-red-500 rounded" />
          <span className="text-gray-400">Fully Private - No one can view</span>
        </div>
        <div className="flex items-center gap-2">
          <div className="w-3 h-3 bg-yellow-500 rounded" />
          <span className="text-gray-400">Permit Required - Needs authorization</span>
        </div>
        <div className="flex items-center gap-2">
          <div className="w-3 h-3 bg-blue-500 rounded" />
          <span className="text-gray-400">Selective - Specific addresses only</span>
        </div>
        <div className="flex items-center gap-2">
          <div className="w-3 h-3 bg-green-500 rounded" />
          <span className="text-gray-400">Public - Anyone can view</span>
        </div>
      </div>
    </div>
  );
}

// ── Selective Disclosure Modal ─────────────────────────────────────────────────

interface SelectiveDisclosureModalProps {
  isOpen: boolean;
  onClose: () => void;
  dataKey: string;
  dataLabel: string;
}

export function SelectiveDisclosureModal({ 
  isOpen, 
  onClose, 
  dataKey, 
  dataLabel 
}: SelectiveDisclosureModalProps) {
  const { grantAccess } = useSelectiveDisclosure();
  const [address, setAddress] = useState('');
  const [duration, setDuration] = useState(3600);

  const handleGrant = () => {
    if (address && address.startsWith('0x')) {
      grantAccess(dataKey, address as Hash, duration, PrivacyLevel.SELECTIVE);
      onClose();
    }
  };

  if (!isOpen) return null;

  return (
    <div className="fixed inset-0 bg-black/50 flex items-center justify-center z-50 p-4">
      <div className="bg-gray-900 rounded-2xl p-6 max-w-md w-full border border-gray-700">
        <h3 className="text-xl font-bold text-white mb-4">
          Share &quot;{dataLabel}&quot;
        </h3>
        <p className="text-sm text-gray-400 mb-6">
          Grant selective access to this encrypted data
        </p>

        <div className="space-y-4">
          <div>
            <label className="block text-sm text-gray-400 mb-2">Wallet Address</label>
            <input
              type="text"
              value={address}
              onChange={(e) => setAddress(e.target.value)}
              placeholder="0x..."
              className="w-full px-4 py-3 bg-gray-800 border border-gray-700 rounded-lg text-white font-mono focus:border-purple-500 focus:outline-none"
            />
          </div>

          <div>
            <label className="block text-sm text-gray-400 mb-2">Access Duration</label>
            <select
              value={duration}
              onChange={(e) => setDuration(Number(e.target.value))}
              className="w-full px-4 py-3 bg-gray-800 border border-gray-700 rounded-lg text-white focus:border-purple-500 focus:outline-none"
            >
              <option value={3600}>1 hour</option>
              <option value={86400}>24 hours</option>
              <option value={604800}>7 days</option>
              <option value={2592000}>30 days</option>
            </select>
          </div>
        </div>

        <div className="flex gap-3 mt-6">
          <button
            onClick={onClose}
            className="flex-1 py-3 bg-gray-700 hover:bg-gray-600 rounded-lg font-medium text-white transition-all"
          >
            Cancel
          </button>
          <button
            onClick={handleGrant}
            disabled={!address.startsWith('0x')}
            className="flex-1 py-3 bg-purple-600 hover:bg-purple-700 rounded-lg font-medium text-white transition-all disabled:opacity-50"
          >
            Grant Access
          </button>
        </div>
      </div>
    </div>
  );
}