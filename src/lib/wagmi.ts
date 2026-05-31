/**
 * Wagmi Configuration for VenturesSea
 * 
 * Wallet Connect v2 and Viem setup for Fhenix network.
 */

import { http, createConfig } from 'wagmi';
import { mainnet, sepolia } from 'wagmi/chains';
import { injected, walletConnect } from 'wagmi/connectors';

// ── Fhenix Chain Configuration ─────────────────────────────────────────────────

export const fhenixChain = {
  id: 80085,
  name: 'Fhenix',
  network: 'fhenix',
  nativeCurrency: {
    decimals: 18,
    name: 'Fhenix Ether',
    symbol: 'FETH',
  },
  rpcUrls: {
    default: {
      http: [process.env.NEXT_PUBLIC_FHENIX_RPC || 'https://api.testnet.fhenix.zone'],
    },
    public: {
      http: [process.env.NEXT_PUBLIC_FHENIX_RPC || 'https://api.testnet.fhenix.zone'],
    },
  },
  blockExplorers: {
    default: {
      name: 'Fhenix Explorer',
      url: 'https://explorer.fhenix.io',
    },
  },
} as const;

// ── WalletConnect Project ID ──────────────────────────────────────────────────
// Get from https://cloud.walletconnect.com

const WALLETCONNECT_PROJECT_ID = process.env.NEXT_PUBLIC_WALLETCONNECT_PROJECT_ID || 'your-project-id';

// ── Wagmi Config ──────────────────────────────────────────────────────────────

export const wagmiConfig = createConfig({
  chains: [fhenixChain, mainnet, sepolia],
  connectors: [
    injected(),
    walletConnect({ 
      projectId: WALLETCONNECT_PROJECT_ID,
      metadata: {
        name: 'VenturesSea',
        description: 'Confidential Computing Protocol for Web3 Ventures',
        url: 'https://venturessea.io',
        icons: ['https://venturessea.io/icon.png'],
      },
    }),
  ],
  transports: {
    [fhenixChain.id]: http(),
    [mainnet.id]: http(),
    [sepolia.id]: http(),
  },
});

// ── Supported Chains ─────────────────────────────────────────────────────────

export const SUPPORTED_CHAINS = [fhenixChain] as const;

// ── Chain Helpers ─────────────────────────────────────────────────────────────

export function isFhenixChain(chainId: number): boolean {
  return chainId === fhenixChain.id;
}

export function getChainName(chainId: number): string {
  const chain = SUPPORTED_CHAINS.find(c => c.id === chainId);
  return chain?.name || 'Unknown';
}