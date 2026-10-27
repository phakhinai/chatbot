import type { NextConfig } from 'next';
import { loadEnvConfig } from '@next/env';
import path from 'node:path';
loadEnvConfig(path.resolve(process.cwd(), '../..'));
const config: NextConfig = {
  poweredByHeader: false,
  output: 'standalone',
  outputFileTracingRoot: path.resolve(process.cwd(), '../..'),
};
export default config;
