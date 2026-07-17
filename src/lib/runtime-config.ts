import { runtimeEnv } from './env';
import { loadSecrets, type SecretBag } from './secrets';

export type RuntimeConfig = {
  /** True when config was loaded from AWS Secrets Manager. */
  fromSecretsManager: boolean;
  /** Full secret map (all keys in the JSON). Empty when SECRET_NAME is unset. */
  secrets: SecretBag;
  /** Convenience: secret value or process.env fallback. */
  get: (key: string) => string | undefined;
};

let cachedConfig: RuntimeConfig | null = null;

/**
 * Runtime configuration for Lambda / local.
 * - Production: Lambda env only needs SECRET_NAME (+ AWS_REGION).
 * - Local: omit SECRET_NAME and put values in .env / process.env.
 *
 * All keys inside the secret JSON are exposed via `secrets` and `get()`.
 */
export async function getRuntimeConfig(forceRefresh = false): Promise<RuntimeConfig> {
  if (cachedConfig && !forceRefresh) {
    return cachedConfig;
  }

  const secretName = runtimeEnv('SECRET_NAME');
  const secrets = await loadSecrets(forceRefresh);

  cachedConfig = {
    fromSecretsManager: Boolean(secretName),
    secrets,
    get(key: string) {
      return secrets[key] ?? runtimeEnv(key);
    },
  };

  return cachedConfig;
}

export function clearRuntimeConfigCache(): void {
  cachedConfig = null;
}
