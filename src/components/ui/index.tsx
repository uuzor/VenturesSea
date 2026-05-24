'use client';

import React, { forwardRef } from 'react';

// ============================================
// BUTTON COMPONENTS
// ============================================

interface ButtonProps extends React.ButtonHTMLAttributes<HTMLButtonElement> {
  variant?: 'primary' | 'secondary' | 'ghost' | 'outline';
  size?: 'sm' | 'md' | 'lg';
  icon?: React.ReactNode;
  children?: React.ReactNode;
  isLoading?: boolean;
}

const Button = forwardRef<HTMLButtonElement, ButtonProps>(
  ({ 
    variant = 'primary', 
    size = 'md', 
    icon, 
    children, 
    isLoading,
    className = '',
    disabled,
    ...props 
  }, ref) => {
    const baseStyles = `
      inline-flex items-center justify-center gap-2
      font-inter font-medium tracking-tight
      transition-all duration-200 ease-out
      cursor-pointer select-none
      disabled:opacity-50 disabled:cursor-not-allowed
    `;

    const variantStyles = {
      primary: `
        bg-[var(--color-midnight)] text-white
        hover:bg-[var(--color-charcoal-primary)] hover:-translate-y-0.5
        active:translate-y-0
      `,
      secondary: `
        bg-[var(--color-stone-surface)] text-[var(--color-midnight)]
        hover:bg-[var(--color-parchment-card)] hover:-translate-y-0.5
        active:translate-y-0
      `,
      ghost: `
        bg-transparent text-[var(--color-ember-orange)]
        hover:underline hover:underline-offset-2
      `,
      outline: `
        bg-transparent text-[var(--color-graphite)]
        border border-[var(--color-graphite)]
        hover:bg-[var(--color-stone-surface)]
      `,
    };

    const sizeStyles = {
      sm: 'px-4 py-2 text-xs rounded-[var(--radius-md)]',
      md: 'px-6 py-3 text-sm rounded-[var(--radius-buttons)]',
      lg: 'px-8 py-4 text-base rounded-[var(--radius-buttons)]',
    };

    return (
      <button
        ref={ref}
        className={`${baseStyles} ${variantStyles[variant]} ${sizeStyles[size]} ${className}`}
        disabled={disabled || isLoading}
        {...props}
      >
        {isLoading ? (
          <svg className="animate-spin h-4 w-4" viewBox="0 0 24 24">
            <circle
              className="opacity-25"
              cx="12"
              cy="12"
              r="10"
              stroke="currentColor"
              strokeWidth="4"
              fill="none"
            />
            <path
              className="opacity-75"
              fill="currentColor"
              d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"
            />
          </svg>
        ) : icon ? (
          <span className="flex-shrink-0">{icon}</span>
        ) : null}
        {children}
      </button>
    );
  }
);

Button.displayName = 'Button';

// ============================================
// ICON BUTTON
// ============================================

interface IconButtonProps extends React.ButtonHTMLAttributes<HTMLButtonElement> {
  icon: React.ReactNode;
  label: string;
  size?: 'sm' | 'md' | 'lg';
  variant?: 'default' | 'filled';
}

const IconButton: React.FC<IconButtonProps> = ({
  icon,
  label,
  size = 'md',
  variant = 'default',
  className = '',
  ...props
}) => {
  const sizeStyles = {
    sm: 'w-8 h-8',
    md: 'w-10 h-10',
    lg: 'w-12 h-12',
  };

  const variantStyles = {
    default: 'bg-[var(--color-stone-surface)] text-[var(--color-graphite)] hover:bg-[var(--color-parchment-card)] hover:text-[var(--color-charcoal-primary)]',
    filled: 'bg-[var(--color-ember-orange)] text-white hover:opacity-90',
  };

  return (
    <button
      className={`
        ${sizeStyles[size]} ${variantStyles[variant]}
        rounded-full flex items-center justify-center
        transition-all duration-150 ease-out
        cursor-pointer
        ${className}
      `}
      aria-label={label}
      title={label}
      {...props}
    >
      {icon}
    </button>
  );
};

// ============================================
// CARD COMPONENT
// ============================================

interface CardProps extends React.HTMLAttributes<HTMLDivElement> {
  variant?: 'default' | 'recessed' | 'dark';
  padding?: 'none' | 'sm' | 'md' | 'lg';
  hoverable?: boolean;
  children: React.ReactNode;
}

const Card: React.FC<CardProps> = ({
  variant = 'default',
  padding = 'md',
  hoverable = false,
  className = '',
  children,
  ...props
}) => {
  const variantStyles = {
    default: 'bg-white shadow-[inset_0_0_0_1px_rgba(242,240,237,0.9)]',
    recessed: 'bg-[var(--color-parchment-card)]',
    dark: 'bg-black shadow-[var(--shadow-lg)]',
  };

  const paddingStyles = {
    none: '',
    sm: 'p-4',
    md: 'p-8',
    lg: 'p-10',
  };

  const hoverStyles = hoverable
    ? 'transition-all duration-300 ease-out hover:shadow-[var(--shadow-sm)] hover:-translate-y-1'
    : '';

  return (
    <div
      className={`
        rounded-[var(--radius-cards)] 
        ${variantStyles[variant]} 
        ${paddingStyles[padding]}
        ${hoverStyles}
        ${className}
      `}
      {...props}
    >
      {children}
    </div>
  );
};

// ============================================
// BADGE COMPONENT
// ============================================

interface BadgeProps extends React.HTMLAttributes<HTMLSpanElement> {
  variant?: 'default' | 'orange' | 'green' | 'blue' | 'yellow';
  size?: 'sm' | 'md';
  children: React.ReactNode;
}

const Badge: React.FC<BadgeProps> = ({
  variant = 'default',
  size = 'sm',
  className = '',
  children,
  ...props
}) => {
  const variantStyles = {
    default: 'bg-[var(--color-stone-surface)] text-[var(--color-graphite)]',
    orange: 'bg-[var(--color-ember-orange)] text-white',
    green: 'bg-[var(--color-meadow-green)] text-white',
    blue: 'bg-[var(--color-sky-blue)] text-white',
    yellow: 'bg-[var(--color-sunburst-yellow)] text-[var(--color-pepper)]',
  };

  const sizeStyles = {
    sm: 'px-2 py-0.5 text-[10px]',
    md: 'px-3 py-1 text-xs',
  };

  return (
    <span
      className={`
        inline-flex items-center gap-1
        font-inter font-medium
        rounded-[var(--radius-tags)]
        ${variantStyles[variant]}
        ${sizeStyles[size]}
        ${className}
      `}
      {...props}
    >
      {children}
    </span>
  );
};

// ============================================
// INPUT COMPONENT
// ============================================

interface InputProps extends React.InputHTMLAttributes<HTMLInputElement> {
  label?: string;
  error?: string;
  hint?: string;
}

const Input = forwardRef<HTMLInputElement, InputProps>(
  ({ label, error, hint, className = '', id, ...props }, ref) => {
    const inputId = id || label?.toLowerCase().replace(/\s+/g, '-');

    return (
      <div className="w-full">
        {label && (
          <label
            htmlFor={inputId}
            className="block mb-2 text-sm font-medium text-[var(--color-charcoal-primary)]"
          >
            {label}
          </label>
        )}
        <input
          ref={ref}
          id={inputId}
          className={`
            w-full px-4 py-3
            bg-white
            border border-[var(--color-stone-surface)]
            rounded-[var(--radius-inputs)]
            font-inter text-[15px] text-[var(--color-charcoal-primary)]
            placeholder:text-[var(--color-smoke)]
            transition-all duration-150 ease-out
            focus:outline-none focus:border-[var(--color-ember-orange)] focus:ring-2 focus:ring-[rgba(255,62,0,0.1)]
            disabled:opacity-50 disabled:cursor-not-allowed
            ${error ? 'border-[var(--color-coral-red)]' : ''}
            ${className}
          `}
          {...props}
        />
        {error && (
          <p className="mt-1 text-xs text-[var(--color-coral-red)]">{error}</p>
        )}
        {hint && !error && (
          <p className="mt-1 text-xs text-[var(--color-ash)]">{hint}</p>
        )}
      </div>
    );
  }
);

Input.displayName = 'Input';

// ============================================
// TEXTAREA COMPONENT
// ============================================

interface TextareaProps extends React.TextareaHTMLAttributes<HTMLTextAreaElement> {
  label?: string;
  error?: string;
  hint?: string;
}

const Textarea = forwardRef<HTMLTextAreaElement, TextareaProps>(
  ({ label, error, hint, className = '', id, ...props }, ref) => {
    const textareaId = id || label?.toLowerCase().replace(/\s+/g, '-');

    return (
      <div className="w-full">
        {label && (
          <label
            htmlFor={textareaId}
            className="block mb-2 text-sm font-medium text-[var(--color-charcoal-primary)]"
          >
            {label}
          </label>
        )}
        <textarea
          ref={ref}
          id={textareaId}
          className={`
            w-full px-4 py-3
            bg-white
            border border-[var(--color-stone-surface)]
            rounded-[var(--radius-inputs)]
            font-inter text-[15px] text-[var(--color-charcoal-primary)]
            placeholder:text-[var(--color-smoke)]
            resize-y min-h-[120px]
            transition-all duration-150 ease-out
            focus:outline-none focus:border-[var(--color-ember-orange)] focus:ring-2 focus:ring-[rgba(255,62,0,0.1)]
            disabled:opacity-50 disabled:cursor-not-allowed
            ${error ? 'border-[var(--color-coral-red)]' : ''}
            ${className}
          `}
          {...props}
        />
        {error && (
          <p className="mt-1 text-xs text-[var(--color-coral-red)]">{error}</p>
        )}
        {hint && !error && (
          <p className="mt-1 text-xs text-[var(--color-ash)]">{hint}</p>
        )}
      </div>
    );
  }
);

Textarea.displayName = 'Textarea';

// ============================================
// SELECT COMPONENT
// ============================================

interface SelectProps extends React.SelectHTMLAttributes<HTMLSelectElement> {
  label?: string;
  error?: string;
  options: { value: string; label: string }[];
}

const Select = forwardRef<HTMLSelectElement, SelectProps>(
  ({ label, error, options, className = '', id, ...props }, ref) => {
    const selectId = id || label?.toLowerCase().replace(/\s+/g, '-');

    return (
      <div className="w-full">
        {label && (
          <label
            htmlFor={selectId}
            className="block mb-2 text-sm font-medium text-[var(--color-charcoal-primary)]"
          >
            {label}
          </label>
        )}
        <select
          ref={ref}
          id={selectId}
          className={`
            w-full px-4 py-3
            bg-white
            border border-[var(--color-stone-surface)]
            rounded-[var(--radius-inputs)]
            font-inter text-[15px] text-[var(--color-charcoal-primary)]
            transition-all duration-150 ease-out
            focus:outline-none focus:border-[var(--color-ember-orange)] focus:ring-2 focus:ring-[rgba(255,62,0,0.1)]
            cursor-pointer
            ${error ? 'border-[var(--color-coral-red)]' : ''}
            ${className}
          `}
          {...props}
        >
          {options.map((option) => (
            <option key={option.value} value={option.value}>
              {option.label}
            </option>
          ))}
        </select>
        {error && (
          <p className="mt-1 text-xs text-[var(--color-coral-red)]">{error}</p>
        )}
      </div>
    );
  }
);

Select.displayName = 'Select';

// ============================================
// AVATAR COMPONENT
// ============================================

interface AvatarProps {
  src?: string;
  alt?: string;
  name?: string;
  size?: 'sm' | 'md' | 'lg';
  className?: string;
}

const Avatar: React.FC<AvatarProps> = ({
  src,
  alt,
  name,
  size = 'md',
  className = '',
}) => {
  const sizeStyles = {
    sm: 'w-8 h-8 text-xs',
    md: 'w-10 h-10 text-sm',
    lg: 'w-14 h-14 text-base',
  };

  const initials = name
    ?.split(' ')
    .map((n) => n[0])
    .join('')
    .toUpperCase()
    .slice(0, 2);

  return (
    <div
      className={`
        ${sizeStyles[size]}
        rounded-full overflow-hidden
        bg-[var(--color-stone-surface)]
        flex items-center justify-center
        font-inter font-medium text-[var(--color-ash)]
        ${className}
      `}
    >
      {src ? (
        <img src={src} alt={alt || name || 'Avatar'} className="w-full h-full object-cover" />
      ) : initials ? (
        initials
      ) : (
        <svg className="w-1/2 h-1/2 text-[var(--color-smoke)]" fill="currentColor" viewBox="0 0 24 24">
          <path d="M12 12c2.21 0 4-1.79 4-4s-1.79-4-4-4-4 1.79-4 4 1.79 4 4 4zm0 2c-2.67 0-8 1.34-8 4v2h16v-2c0-2.66-5.33-4-8-4z" />
        </svg>
      )}
    </div>
  );
};

// ============================================
// PROGRESS BAR COMPONENT
// ============================================

interface ProgressBarProps {
  value: number;
  max?: number;
  label?: string;
  showPercentage?: boolean;
  variant?: 'default' | 'success' | 'warning';
  size?: 'sm' | 'md';
  className?: string;
}

const ProgressBar: React.FC<ProgressBarProps> = ({
  value,
  max = 100,
  label,
  showPercentage = false,
  variant = 'default',
  size = 'md',
  className = '',
}) => {
  const percentage = Math.min(100, Math.max(0, (value / max) * 100));

  const variantStyles = {
    default: 'bg-[var(--color-ember-orange)]',
    success: 'bg-[var(--color-meadow-green)]',
    warning: 'bg-[var(--color-sunburst-yellow)]',
  };

  const sizeStyles = {
    sm: 'h-1.5',
    md: 'h-2.5',
  };

  return (
    <div className={`w-full ${className}`}>
      {(label || showPercentage) && (
        <div className="flex justify-between items-center mb-2">
          {label && <span className="text-sm text-[var(--color-graphite)]">{label}</span>}
          {showPercentage && (
            <span className="text-sm font-medium text-[var(--color-charcoal-primary)]">
              {percentage.toFixed(0)}%
            </span>
          )}
        </div>
      )}
      <div className={`w-full bg-[var(--color-stone-surface)] rounded-full ${sizeStyles[size]} overflow-hidden`}>
        <div
          className={`${sizeStyles[size]} ${variantStyles[variant]} rounded-full transition-all duration-500 ease-out`}
          style={{ width: `${percentage}%` }}
        />
      </div>
    </div>
  );
};

// ============================================
// SKELETON LOADER COMPONENT
// ============================================

interface SkeletonProps {
  variant?: 'text' | 'circular' | 'rectangular';
  width?: string | number;
  height?: string | number;
  className?: string;
}

const Skeleton: React.FC<SkeletonProps> = ({
  variant = 'text',
  width,
  height,
  className = '',
}) => {
  const variantStyles = {
    text: 'rounded-[var(--radius-sm)] h-4',
    circular: 'rounded-full',
    rectangular: 'rounded-[var(--radius-lg)]',
  };

  const defaultWidth = variant === 'text' ? '100%' : variant === 'circular' ? 40 : '100%';
  const defaultHeight = variant === 'text' ? 16 : variant === 'circular' ? 40 : 100;

  return (
    <div
      className={`
        bg-[var(--color-stone-surface)]
        animate-pulse
        ${variantStyles[variant]}
        ${className}
      `}
      style={{
        width: width ?? defaultWidth,
        height: height ?? defaultHeight,
      }}
    />
  );
};

// Export all components
export { Button, IconButton, Card, Badge, Input, Textarea, Select, Avatar, ProgressBar, Skeleton };
