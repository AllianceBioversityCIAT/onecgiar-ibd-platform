import { defineConfig } from 'astro/config';
import node from '@astrojs/node';

// SSR everywhere: output 'server' makes every route server-rendered by default.
// Individual pages can opt back into prerendering with `export const prerender = true`.
export default defineConfig({
  output: 'server',
  adapter: node({ mode: 'standalone' }),
});
