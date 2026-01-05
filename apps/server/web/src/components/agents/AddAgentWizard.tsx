import { useState } from 'react';
import { useTranslation } from 'react-i18next';
import { X } from 'lucide-react';
import { PlatformStep, type Platform } from './wizard/PlatformStep';
import { ConfigStep, type AgentConfig } from './wizard/ConfigStep';
import { InstallStep } from './wizard/InstallStep';

type WizardStep = 'platform' | 'config' | 'install';

interface AddAgentWizardProps {
  onClose: () => void;
}

const steps: { id: WizardStep; number: number }[] = [
  { id: 'platform', number: 1 },
  { id: 'config', number: 2 },
  { id: 'install', number: 3 },
];

export function AddAgentWizard({ onClose }: AddAgentWizardProps) {
  const { t } = useTranslation();
  const [currentStep, setCurrentStep] = useState<WizardStep>('platform');
  const [platform, setPlatform] = useState<Platform>('linux');
  const [config, setConfig] = useState<AgentConfig>({
    agentName: '',
    permission: 0,
    enableShell: false,
    enableTls: false,
  });

  const getCurrentStepNumber = () => {
    const step = steps.find((s) => s.id === currentStep);
    return step?.number || 1;
  };

  const renderStep = () => {
    switch (currentStep) {
      case 'platform':
        return (
          <PlatformStep
            value={platform}
            onChange={setPlatform}
            onNext={() => setCurrentStep('config')}
          />
        );
      case 'config':
        return (
          <ConfigStep
            value={config}
            onChange={setConfig}
            onBack={() => setCurrentStep('platform')}
            onNext={() => setCurrentStep('install')}
          />
        );
      case 'install':
        return (
          <InstallStep
            platform={platform}
            config={config}
            onBack={() => setCurrentStep('config')}
            onComplete={onClose}
          />
        );
    }
  };

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center">
      {/* Backdrop */}
      <div
        className="absolute inset-0 bg-black/50 backdrop-blur-sm"
        onClick={onClose}
      />

      {/* Dialog */}
      <div className="relative bg-[var(--color-card)] rounded-lg shadow-xl w-full max-w-lg mx-4 max-h-[90vh] overflow-hidden flex flex-col">
        {/* Header */}
        <div className="flex items-center justify-between p-4 border-b border-[var(--color-border)]">
          <div>
            <h2 className="text-lg font-semibold">
              {t('wizard.addAgent', 'Add Agent')}
            </h2>
            <p className="text-sm text-[var(--color-muted-foreground)]">
              {t('wizard.step', 'Step')} {getCurrentStepNumber()}/3
            </p>
          </div>
          <button
            onClick={onClose}
            className="p-2 rounded-lg hover:bg-[var(--color-muted)] transition-colors"
          >
            <X className="w-5 h-5" />
          </button>
        </div>

        {/* Progress Bar */}
        <div className="px-4 pt-4">
          <div className="flex items-center justify-between mb-2">
            {steps.map((step, index) => (
              <div key={step.id} className="flex items-center">
                <div
                  className={`
                    w-8 h-8 rounded-full flex items-center justify-center text-sm font-medium
                    ${getCurrentStepNumber() > step.number
                      ? 'bg-[var(--color-primary)] text-white'
                      : getCurrentStepNumber() === step.number
                        ? 'bg-[var(--color-primary)] text-white'
                        : 'bg-[var(--color-muted)] text-[var(--color-muted-foreground)]'
                    }
                  `}
                >
                  {step.number}
                </div>
                {index < steps.length - 1 && (
                  <div
                    className={`
                      w-16 sm:w-24 h-1 mx-2
                      ${getCurrentStepNumber() > step.number
                        ? 'bg-[var(--color-primary)]'
                        : 'bg-[var(--color-muted)]'
                      }
                    `}
                  />
                )}
              </div>
            ))}
          </div>
        </div>

        {/* Content */}
        <div className="flex-1 overflow-y-auto p-4">
          {renderStep()}
        </div>
      </div>
    </div>
  );
}
