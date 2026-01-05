import { useTranslation } from 'react-i18next';
import { Monitor, Terminal, Apple } from 'lucide-react';
import { Button } from '../../ui/button';

export type Platform = 'linux' | 'windows' | 'macos';

interface PlatformStepProps {
  value: Platform;
  onChange: (platform: Platform) => void;
  onNext: () => void;
}

const platforms: { id: Platform; icon: typeof Monitor; label: string }[] = [
  { id: 'linux', icon: Terminal, label: 'Linux' },
  { id: 'windows', icon: Monitor, label: 'Windows' },
  { id: 'macos', icon: Apple, label: 'macOS' },
];

export function PlatformStep({ value, onChange, onNext }: PlatformStepProps) {
  const { t } = useTranslation();

  return (
    <div className="space-y-6">
      <div>
        <h3 className="text-lg font-medium mb-2">
          {t('wizard.selectPlatform', 'Select Target Platform')}
        </h3>
        <p className="text-sm text-[var(--color-muted-foreground)]">
          {t('wizard.platformDescription', 'Choose the operating system where you want to install the agent.')}
        </p>
      </div>

      <div className="grid grid-cols-3 gap-4">
        {platforms.map((platform) => {
          const Icon = platform.icon;
          const isSelected = value === platform.id;

          return (
            <button
              key={platform.id}
              type="button"
              onClick={() => onChange(platform.id)}
              className={`
                flex flex-col items-center justify-center p-6 rounded-lg border-2 transition-all
                ${isSelected
                  ? 'border-[var(--color-primary)] bg-[var(--color-primary)]/10'
                  : 'border-[var(--color-border)] hover:border-[var(--color-primary)]/50 hover:bg-[var(--color-muted)]/50'
                }
              `}
            >
              <Icon className={`w-10 h-10 mb-2 ${isSelected ? 'text-[var(--color-primary)]' : 'text-[var(--color-muted-foreground)]'}`} />
              <span className={`font-medium ${isSelected ? 'text-[var(--color-primary)]' : ''}`}>
                {platform.label}
              </span>
            </button>
          );
        })}
      </div>

      <div className="flex justify-end">
        <Button onClick={onNext}>
          {t('wizard.next', 'Next')}
        </Button>
      </div>
    </div>
  );
}
