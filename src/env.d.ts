/// <reference types="astro/client" />

interface ImportMetaEnv {
  readonly SECRET_NAME?: string;
  readonly AWS_REGION?: string;
}

interface ImportMeta {
  readonly env: ImportMetaEnv;
}
