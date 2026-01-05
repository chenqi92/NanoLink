import { useTranslation } from 'react-i18next';
import { Button } from '../../ui/button';
import { Input } from '../../ui/input';

export interface AgentConfig {
  agentName: string;
  permission: 0 | 1 | 2 | 3;
  enableShell: boolean;
  enableTls: boolean;
}

interface ConfigStepProps {
  value: AgentConfig;
  onChange: (config: AgentConfig) => void;
  onBack: () => void;
  onNext: () => void;
}

const permissionLevels = [
  { value: 0, label: 'READ_ONLY', description: 'View metrics only' },
  { value: 1, label: 'BASIC_WRITE', description: 'Basic operations' },
  { value: 2, label: 'SERVICE_CONTROL', description: 'Manage services' },
  { value: 3, label: 'SYSTEM_ADMIN', description: 'Full control' },
];

export function ConfigStep({ value, onChange, onBack, onNext }: ConfigStepProps) {
  const { t } = useTranslation();

  const handleChange = (field: keyof AgentConfig, fieldValue: AgentConfig[keyof AgentConfig]) => {
    onChange({ ...value, [field]: fieldValue });
  };

  return (
    <div className="space-y-6">
      <div>
        <h3 className="text-lg font-medium mb-2">
          {t('wizard.configureAgent', 'Configure Agent')}
        </h3>
        <p className="text-sm text-[var(--color-muted-foreground)]">
          {t('wizard.configDescription', 'Set up the agent permissions and features.')}
        </p>
      </div>

      {/* Agent Name */}
      <div className="space-y-2">
        <label className="text-sm font-medium">
          {t('wizard.agentName', 'Agent Name')}
          <span className="text-[var(--color-muted-foreground)] ml-1">
            ({t('wizard.optional', 'optional')})
          </span>
        </label>
        <Input
          value={value.agentName}
          onChange={(e) => handleChange('agentName', e.target.value)}
          placeholder={t('wizard.agentNamePlaceholder', 'Leave empty to auto-generate')}
        />
      </div>

      {/* Permission Level */}
      <div className="space-y-2">
        <label className="text-sm font-medium">
          {t('wizard.permissionLevel', 'Permission Level')}
        </label>
        <div className="space-y-2">
          {permissionLevels.map((level) => (
            <label
              key={level.value}
              className={`
                flex items-center p-3 rounded-lg border cursor-pointer transition-all
                ${value.permission === level.value
                  ? 'border-[var(--color-primary)] bg-[var(--color-primary)]/10'
                  : 'border-[var(--color-border)] hover:border-[var(--color-primary)]/50'
                }
              `}
            >
              <input
                type="radio"
                name="permission"
                value={level.value}
                checked={value.permission === level.value}
                onChange={() => handleChange('permission', level.value as 0 | 1 | 2 | 3)}
                className="mr-3"
              />
              <div>
                <span className="font-medium">{level.label}</span>
                <span className="text-sm text-[var(--color-muted-foreground)] ml-2">
                  - {t(`permission.${level.label.toLowerCase()}`, level.description)}
                </span>
              </div>
            </label>
          ))}
        </div>
      </div>

      {/* Feature Toggles */}
      <div className="space-y-3">
        <label className="text-sm font-medium">
          {t('wizard.features', 'Features')}
        </label>

        <label className="flex items-center p-3 rounded-lg border border-[var(--color-border)] cursor-pointer hover:bg-[var(--color-muted)]/50">
          <input
            type="checkbox"
            checked={value.enableShell}
            onChange={(e) => handleChange('enableShell', e.target.checked)}
            className="mr-3"
          />
          <div>
            <span className="font-medium">{t('wizard.enableShell', 'Enable Remote Shell')}</span>
            <p className="text-sm text-[var(--color-muted-foreground)]">
              {t('wizard.shellDescription', 'Allow executing commands on this agent remotely')}
            </p>
          </div>
        </label>

        <label className="flex items-center p-3 rounded-lg border border-[var(--color-border)] cursor-pointer hover:bg-[var(--color-muted)]/50">
          <input
            type="checkbox"
            checked={value.enableTls}
            onChange={(e) => handleChange('enableTls', e.target.checked)}
            className="mr-3"
          />
          <div>
            <span className="font-medium">{t('wizard.enableTls', 'Enable TLS Encryption')}</span>
            <p className="text-sm text-[var(--color-muted-foreground)]">
              {t('wizard.tlsDescription', 'Encrypt communication between agent and server')}
            </p>
          </div>
        </label>
      </div>

      <div className="flex justify-between">
        <Button variant="outline" onClick={onBack}>
          {t('wizard.back', 'Back')}
        </Button>
        <Button onClick={onNext}>
          {t('wizard.next', 'Next')}
        </Button>
      </div>
    </div>
  );
}
