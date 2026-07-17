/**
 * Resolve env vars at runtime.
 * Prefer process.env (Lambda / Node) over import.meta.env (build-time bake).
 */
export function runtimeEnv(name: string): string | undefined {
  const fromProcess =
    typeof process !== 'undefined' ? process.env[name] : undefined;
  if (fromProcess) return fromProcess;

  const fromImportMeta = import.meta.env[name as keyof ImportMetaEnv];
  return typeof fromImportMeta === 'string' ? fromImportMeta : undefined;
}

export function requireRuntimeEnv(name: string): string {
  const value = runtimeEnv(name);
  if (!value) {
    throw new Error(`Missing required environment variable: ${name}`);
  }
  return value;
}
