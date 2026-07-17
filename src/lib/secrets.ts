import {
  GetSecretValueCommand,
  SecretsManagerClient,
} from '@aws-sdk/client-secrets-manager';
import { runtimeEnv } from './env';

export type SecretBag = Record<string, string>;

let cachedSecrets: SecretBag | null = null;

function stringifySecretValue(value: unknown): string | undefined {
  if (value === null || value === undefined) return undefined;
  if (typeof value === 'string') return value;
  if (typeof value === 'number' || typeof value === 'boolean') {
    return String(value);
  }
  return JSON.stringify(value);
}

/**
 * Normalize a Secrets Manager JSON payload into a flat string map.
 * Nested objects/arrays are JSON-stringified.
 */
export function normalizeSecretPayload(payload: unknown): SecretBag {
  if (!payload || typeof payload !== 'object' || Array.isArray(payload)) {
    return {};
  }

  const result: SecretBag = {};
  for (const [key, value] of Object.entries(payload as Record<string, unknown>)) {
    const asString = stringifySecretValue(value);
    if (asString !== undefined) {
      result[key] = asString;
    }
  }
  return result;
}

async function fetchSecretsFromManager(secretName: string): Promise<SecretBag> {
  const region = runtimeEnv('AWS_REGION') ?? runtimeEnv('AWS_DEFAULT_REGION') ?? 'us-east-1';
  const client = new SecretsManagerClient({ region });
  const response = await client.send(
    new GetSecretValueCommand({ SecretId: secretName }),
  );

  const raw = response.SecretString;
  if (!raw) {
    throw new Error(`Secret "${secretName}" has no SecretString payload`);
  }

  let parsed: unknown;
  try {
    parsed = JSON.parse(raw);
  } catch {
    throw new Error(`Secret "${secretName}" is not valid JSON`);
  }

  return normalizeSecretPayload(parsed);
}

/**
 * Load all key/value pairs from Secrets Manager when SECRET_NAME is set.
 * Locally (no SECRET_NAME), returns an empty map — use process.env / .env instead.
 */
export async function loadSecrets(forceRefresh = false): Promise<SecretBag> {
  if (cachedSecrets && !forceRefresh) {
    return cachedSecrets;
  }

  const secretName = runtimeEnv('SECRET_NAME');
  if (!secretName) {
    cachedSecrets = {};
    return cachedSecrets;
  }

  cachedSecrets = await fetchSecretsFromManager(secretName);
  return cachedSecrets;
}

export function clearSecretsCache(): void {
  cachedSecrets = null;
}
