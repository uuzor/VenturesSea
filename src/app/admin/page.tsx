'use client';

import React, { useState, useEffect } from 'react';
import { motion } from 'framer-motion';
import { Button, Card, Badge, Avatar } from '@/components/ui';

interface Application {
  id: string;
  idea_id: string;
  idea_title: string;
  builder_name: string;
  builder_email: string;
  builder_github?: string;
  portfolio_url?: string;
  pitch_message: string;
  proposed_timeline: string;
  budget_estimate: string;
  status: 'pending' | 'shortlisted' | 'selected' | 'rejected' | 'compensated';
  created_at: string;
}

export default function AdminPage() {
  const [applications, setApplications] = useState<Application[]>([]);
  const [loading, setLoading] = useState(true);
  const [showCompensationModal, setShowCompensationModal] = useState(false);
  const [selectedApp, setSelectedApp] = useState<Application | null>(null);
  const [compensationAmount, setCompensationAmount] = useState('');

  useEffect(() => {
    const mockApplications: Application[] = [
      {
        id: '1',
        idea_id: '1',
        idea_title: 'DeFi Lending Protocol',
        builder_name: 'Alex Chen',
        builder_email: 'alex@example.com',
        builder_github: 'https://github.com/alexchen',
        portfolio_url: 'https://alexchen.dev',
        pitch_message: 'I have 5+ years of experience building DeFi protocols. Previously worked at Aave and Compound.',
        proposed_timeline: '2-3 months',
        budget_estimate: '$35,000',
        status: 'pending',
        created_at: '2024-01-15',
      },
      {
        id: '2',
        idea_id: '1',
        idea_title: 'DeFi Lending Protocol',
        builder_name: 'Sarah Kim',
        builder_email: 'sarah@example.com',
        builder_github: 'https://github.com/sarahkim',
        pitch_message: 'Full-stack developer with expertise in Solidity and React.',
        proposed_timeline: '1-2 months',
        budget_estimate: '$28,000',
        status: 'shortlisted',
        created_at: '2024-01-14',
      },
      {
        id: '3',
        idea_id: '2',
        idea_title: 'NFT Marketplace V2',
        builder_name: 'Emily Davis',
        builder_email: 'emily@example.com',
        pitch_message: 'NFT specialist with experience building two successful marketplaces.',
        proposed_timeline: '2-3 months',
        budget_estimate: '$45,000',
        status: 'selected',
        created_at: '2024-01-12',
      },
    ];

    setApplications(mockApplications);
    setLoading(false);
  }, []);

  const handleShortlist = (app: Application) => {
    setApplications(prev =>
      prev.map(a => a.id === app.id ? { ...a, status: 'shortlisted' } : a)
    );
  };

  const handleSelect = (app: Application) => {
    setApplications(prev =>
      prev.map(a => a.id === app.id ? { ...a, status: 'selected' } : a)
    );
  };

  const handleReject = (app: Application) => {
    setApplications(prev =>
      prev.map(a => a.id === app.id ? { ...a, status: 'rejected' } : a)
    );
  };

  const openCompensate = (app: Application) => {
    setSelectedApp(app);
    setShowCompensationModal(true);
  };

  const handleCompensate = () => {
    if (!selectedApp) return;
    setApplications(prev =>
      prev.map(a => a.id === selectedApp.id ? { ...a, status: 'compensated' } : a)
    );
    setShowCompensationModal(false);
    setSelectedApp(null);
    setCompensationAmount('');
  };

  const statusColors: Record<string, string> = {
    pending: 'default',
    shortlisted: 'yellow',
    selected: 'green',
    rejected: 'default',
    compensated: 'blue',
  };

  if (loading) {
    return (
      <div className="min-h-screen pt-16 bg-[var(--color-warm-canvas)] flex items-center justify-center">
        <div className="text-center">
          <div className="w-12 h-12 border-4 border-[var(--color-stone-surface)] border-t-[var(--color-ember-orange)] rounded-full animate-spin mx-auto mb-4" />
          <p className="text-[var(--color-ash)]">Loading admin panel...</p>
        </div>
      </div>
    );
  }

  return (
    <div className="min-h-screen pt-16 bg-[var(--color-warm-canvas)]">
      <div className="max-w-[1400px] mx-auto px-8 py-12">
        <motion.div initial={{ opacity: 0, y: 30 }} animate={{ opacity: 1, y: 0 }} className="mb-12">
          <span className="inline-block px-4 py-1.5 bg-[var(--color-stone-surface)] rounded-full text-sm font-medium text-[var(--color-ember-orange)] mb-4">
            Admin Panel
          </span>
          <h1 className="font-family text-4xl font-medium text-[var(--color-charcoal-primary)] mb-2">
            Builder Selection
          </h1>
          <p className="text-[var(--color-graphite)]">
            Review applications, shortlist builders, and select winners.
          </p>
        </motion.div>

        <motion.div initial={{ opacity: 0, y: 20 }} animate={{ opacity: 1, y: 0 }} transition={{ delay: 0.1 }}
          className="grid grid-cols-2 md:grid-cols-4 gap-4 mb-12">
          {[
            { label: 'Total', value: applications.length },
            { label: 'Pending', value: applications.filter(a => a.status === 'pending').length },
            { label: 'Shortlisted', value: applications.filter(a => a.status === 'shortlisted').length },
            { label: 'Selected', value: applications.filter(a => a.status === 'selected').length },
          ].map((stat) => (
            <Card key={stat.label} className="p-4 text-center">
              <div className="text-2xl font-semibold text-[var(--color-charcoal-primary)]">{stat.value}</div>
              <div className="text-sm text-[var(--color-ash)]">{stat.label}</div>
            </Card>
          ))}
        </motion.div>

        <motion.div initial={{ opacity: 0, y: 20 }} animate={{ opacity: 1, y: 0 }} transition={{ delay: 0.2 }}>
          <Card className="overflow-hidden" padding="none">
            <div className="overflow-x-auto">
              <table className="w-full">
                <thead className="bg-[var(--color-stone-surface)]">
                  <tr>
                    <th className="px-6 py-4 text-left text-xs font-semibold text-[var(--color-charcoal-primary)] uppercase tracking-wider">Builder</th>
                    <th className="px-6 py-4 text-left text-xs font-semibold text-[var(--color-charcoal-primary)] uppercase tracking-wider">Idea</th>
                    <th className="px-6 py-4 text-left text-xs font-semibold text-[var(--color-charcoal-primary)] uppercase tracking-wider">Timeline</th>
                    <th className="px-6 py-4 text-left text-xs font-semibold text-[var(--color-charcoal-primary)] uppercase tracking-wider">Budget</th>
                    <th className="px-6 py-4 text-left text-xs font-semibold text-[var(--color-charcoal-primary)] uppercase tracking-wider">Status</th>
                    <th className="px-6 py-4 text-left text-xs font-semibold text-[var(--color-charcoal-primary)] uppercase tracking-wider">Actions</th>
                  </tr>
                </thead>
                <tbody className="divide-y divide-[var(--color-stone-surface)]">
                  {applications.map((app) => (
                    <tr key={app.id} className="hover:bg-[var(--color-parchment-card)] transition-colors">
                      <td className="px-6 py-4">
                        <div className="flex items-center gap-3">
                          <Avatar name={app.builder_name} size="md" />
                          <div>
                            <div className="font-medium text-[var(--color-charcoal-primary)]">{app.builder_name}</div>
                            <div className="text-sm text-[var(--color-ash)]">{app.builder_email}</div>
                          </div>
                        </div>
                      </td>
                      <td className="px-6 py-4 text-sm text-[var(--color-graphite)]">{app.idea_title}</td>
                      <td className="px-6 py-4 text-sm text-[var(--color-graphite)]">{app.proposed_timeline}</td>
                      <td className="px-6 py-4 text-sm font-medium text-[var(--color-charcoal-primary)]">{app.budget_estimate}</td>
                      <td className="px-6 py-4"><Badge variant={statusColors[app.status] as any}>{app.status}</Badge></td>
                      <td className="px-6 py-4">
                        <div className="flex items-center gap-2">
                          {app.status === 'pending' && (
                            <>
                              <Button variant="outline" size="sm" onClick={() => handleShortlist(app)}>Shortlist</Button>
                              <Button variant="ghost" size="sm" onClick={() => handleReject(app)}>Reject</Button>
                            </>
                          )}
                          {app.status === 'shortlisted' && (
                            <>
                              <Button variant="primary" size="sm" onClick={() => handleSelect(app)}>Select Winner</Button>
                              <Button variant="ghost" size="sm" onClick={() => openCompensate(app)}>Compensate</Button>
                            </>
                          )}
                          {(app.status === 'selected' || app.status === 'compensated') && (
                            <span className="text-sm text-[var(--color-ash)]">Completed</span>
                          )}
                        </div>
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          </Card>
        </motion.div>
      </div>

      {showCompensationModal && selectedApp && (
        <div className="fixed inset-0 bg-black/50 backdrop-blur-sm z-50 flex items-center justify-center p-4">
          <motion.div initial={{ opacity: 0, scale: 0.9 }} animate={{ opacity: 1, scale: 1 }}
            className="bg-white rounded-[10px] p-8 max-w-md w-full">
            <h2 className="text-xl font-semibold text-[var(--color-charcoal-primary)] mb-4">Compensate Builder</h2>
            <p className="text-[var(--color-graphite)] mb-6">
              Enter the compensation amount for {selectedApp.builder_name}.
            </p>
            <div className="mb-6">
              <label className="block text-sm font-medium text-[var(--color-charcoal-primary)] mb-2">Compensation Amount (USD)</label>
              <input type="text" value={compensationAmount} onChange={(e) => setCompensationAmount(e.target.value)}
                placeholder="$5,000"
                className="w-full px-4 py-3 bg-white border border-[var(--color-stone-surface)] rounded-[10px] text-[15px] text-[var(--color-charcoal-primary)] focus:outline-none focus:border-[var(--color-ember-orange)]" />
            </div>
            <div className="flex justify-end gap-3">
              <Button variant="secondary" onClick={() => setShowCompensationModal(false)}>Cancel</Button>
              <Button variant="primary" onClick={handleCompensate}>Confirm Compensation</Button>
            </div>
          </motion.div>
        </div>
      )}
    </div>
  );
}
