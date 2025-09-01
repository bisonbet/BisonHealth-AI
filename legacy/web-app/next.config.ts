import type {NextConfig} from "next";
import createNextIntlPlugin from 'next-intl/plugin';

const withNextIntl = createNextIntlPlugin();

const nextConfig: NextConfig = {
    /* config options here */
    // Enable standalone output for Docker optimization
    output: 'standalone',
    
    // Add build optimizations to prevent hanging
    experimental: {
        optimizePackageImports: ['lucide-react', 'react-icons'],
    },
    
    // Reduce bundle analysis time and optimize webpack
    webpack: (config, { isServer }) => {
        if (!isServer) {
            config.resolve.fallback = {
                ...config.resolve.fallback,
                fs: false,
            };
        }
        
        return config;
    },
    
    // Disable telemetry for faster builds (Note: this should be done via env var)
    // telemetry: false, // This is not a valid Next.js config option
};

export default withNextIntl(nextConfig);
