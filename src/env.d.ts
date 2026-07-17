/// <reference types="astro/client" />
/// <reference types="node" />

interface ImportMetaEnv {
  readonly SECRET_NAME?: string;
  readonly AWS_REGION?: string;
}

interface ImportMeta {
  readonly env: ImportMetaEnv;
}
