import { useState, useEffect } from 'react';
import { useTranslation } from 'react-i18next';
import { Copy, Check, Download, Loader2 } from 'lucide-react';
import { Button } from '../../ui/button';
import type {Platform} from './PlatformStep';
import type {AgentConfig} from './ConfigStep';

interface InstallStepProps {
  platform: Platform;
  config: AgentConfig;
  onBack: () => void;
  onComplete: () => void;
}

interface GeneratedConfig {
  configYaml: string;
  installCommandUnix: string;
  installCommandWindows: string;
  generatedToken?: string;
  serverId: string;
}

export function InstallStep({ platform, config, onBack, onComplete }: InstallStepProps) {
  const { t } = useTranslation();
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [generatedConfig, setGeneratedConfig] = useState<GeneratedConfig | null>(null);
  const [copied, setCopied] = useState<'command' | 'yaml' | null>(null);

  useEffect(() => {
    generateConfig();
  }, []);

  const generateConfig = async () => {
    setLoading(true);
    setError(null);

    try {
      // First get server info
      const serverInfoRes = await fetch('/api/server-info');
      if (!serverInfoRes.ok) {
        throw new Error('Failed to get server info');
      }
      const serverInfo = await serverInfoRes.json();

      // Then generate config
      const res = await fetch('/api/config/generate', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({
          serverUrl: serverInfo.wsUrl,
          permission: config.permission,
          tlsVerify: config.enableTls,
          hostname: config.agentName || undefined,
          shellEnabled: config.enableShell,
        }),
      });

      if (!res.ok) {
        throw new Error('Failed to generate configuration');
      }

      const data = await res.json();
      setGeneratedConfig(data);
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Unknown error');
    } finally {
      setLoading(false);
    }
  };

  const copyToClipboard = async (text: string, type: 'command' | 'yaml') => {
    try {
      await navigator.clipboard.writeText(text);
      setCopied(type);
      setTimeout(() => setCopied(null), 2000);
    } catch (err) {
      console.error('Failed to copy:', err);
    }
  };

  const getInstallCommand = () => {
    if (!generatedConfig) return '';
    return platform === 'windows'
      ? generatedConfig.installCommandWindows
      : generatedConfig.installCommandUnix;
  };

  if (loading) {
    return (
      <div className="flex flex-col items-center justify-center py-12">
        <Loader2 className="w-8 h-8 animate-spin text-[var(--color-primary)] mb-4" />
        <p className="text-[var(--color-muted-foreground)]">
          {t('wizard.generating', 'Generating configuration...')}
        </p>
      </div>
    );
  }

  if (error) {
    return (
      <div className="space-y-4">
        <div className="p-4 rounded-lg bg-red-500/10 border border-red-500/20 text-red-500">
          <p className="font-medium">{t('wizard.error', 'Error')}</p>
          <p className="text-sm">{error}</p>
        </div>
        <div className="flex justify-between">
          <Button variant="outline" onClick={onBack}>
            {t('wizard.back', 'Back')}
          </Button>
          <Button onClick={generateConfig}>
            {t('wizard.retry', 'Retry')}
          </Button>
        </div>
      </div>
    );
  }

  return (
    <div className="space-y-6">
      <div>
        <h3 className="text-lg font-medium mb-2">
          {t('wizard.installAgent', 'Install Agent')}
        </h3>
        <p className="text-sm text-[var(--color-muted-foreground)]">
          {t('wizard.installDescription', 'Run the following command on your target server to install the agent.')}
        </p>
      </div>

      {/* Install Command */}
      <div className="space-y-2">
        <div className="flex items-center justify-between">
          <label className="text-sm font-medium">
            {t('wizard.installCommand', 'Installation Command')}
          </label>
          <Button
            variant="ghost"
            size="sm"
            onClick={() => copyToClipboard(getInstallCommand(), 'command')}
          >
            {copied === 'command' ? (
              <>
                <Check className="w-4 h-4 mr-1" />
                {t('wizard.copied', 'Copied!')}
              </>
            ) : (
              <>
                <Copy className="w-4 h-4 mr-1" />
                {t('wizard.copy', 'Copy')}
              </>
            )}
          </Button>
        </div>
        <div className="relative">
          <pre className="p-4 rounded-lg bg-[var(--color-muted)] overflow-x-auto text-sm font-mono whitespace-pre-wrap break-all">
            {getInstallCommand()}
          </pre>
        </div>
      </div>

      {/* Generated Token */}
      {generatedConfig?.generatedToken && (
        <div className="p-4 rounded-lg bg-yellow-500/10 border border-yellow-500/20">
          <p className="font-medium text-yellow-600 dark:text-yellow-400 mb-2">
            {t('wizard.importantToken', 'Important: Save this token')}
          </p>
          <p className="text-sm text-[var(--color-muted-foreground)] mb-2">
            {t('wizard.tokenWarning', 'This token is required for the agent to authenticate. Make sure to add it to your server configuration.')}
          </p>
          <code className="block p-2 rounded bg-[var(--color-muted)] font-mono text-sm break-all">
            {generatedConfig.generatedToken}
          </code>
        </div>
      )}

      {/* YAML Config (Collapsible) */}
      <details className="group">
        <summary className="cursor-pointer text-sm font-medium text-[var(--color-primary)] hover:underline">
          {t('wizard.showYaml', 'Show YAML Configuration')}
        </summary>
        <div className="mt-2 space-y-2">
          <div className="flex justify-end">
            <Button
              variant="ghost"
              size="sm"
              onClick={() => copyToClipboard(generatedConfig?.configYaml || '', 'yaml')}
            >
              {copied === 'yaml' ? (
                <>
                  <Check className="w-4 h-4 mr-1" />
                  {t('wizard.copied', 'Copied!')}
                </>
              ) : (
                <>
                  <Copy className="w-4 h-4 mr-1" />
                  {t('wizard.copyYaml', 'Copy YAML')}
                </>
              )}
            </Button>
          </div>
          <pre className="p-4 rounded-lg bg-[var(--color-muted)] overflow-x-auto text-xs font-mono max-h-64">
            {generatedConfig?.configYaml}
          </pre>
        </div>
      </details>

      {/* Download Options */}
      <div className="space-y-2">
        <label className="text-sm font-medium">
          {t('wizard.downloadOptions', 'Download Options')}
        </label>
        <div className="flex flex-wrap gap-2">
          <a
            href="https://github.com/chenqi92/NanoLink/releases/latest"
            target="_blank"
            rel="noopener noreferrer"
            className="inline-flex items-center justify-center rounded-md text-sm font-medium border border-[var(--color-border)] bg-transparent hover:bg-[var(--color-muted)] h-8 px-3 transition-colors"
          >
            <Download className="w-4 h-4 mr-1" />
            {platform === 'linux' && 'Linux Binary'}
            {platform === 'windows' && 'Windows Binary'}
            {platform === 'macos' && 'macOS Binary'}
          </a>
        </div>
      </div>

      <div className="flex justify-between pt-4 border-t border-[var(--color-border)]">
        <Button variant="outline" onClick={onBack}>
          {t('wizard.back', 'Back')}
        </Button>
        <Button onClick={onComplete}>
          {t('wizard.done', 'Done')}
        </Button>
      </div>
    </div>
  );
}
