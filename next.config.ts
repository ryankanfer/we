import type { NextConfig } from "next";

const nextConfig: NextConfig = {
  // Apple fetches this to learn which links open the iPhone app. It has no
  // file extension, so without this header it would be served as a download.
  async headers() {
    return [
      {
        source: "/.well-known/apple-app-site-association",
        headers: [{ key: "Content-Type", value: "application/json" }],
      },
    ];
  },

  // The old web app's screens. WE is the iPhone app now; anyone following an
  // old bookmark lands on the front door instead of a stale copy of it.
  async redirects() {
    return ["/home", "/plan", "/profile", "/insight/:path*"].map((source) => ({
      source,
      destination: "/",
      permanent: false,
    }));
  },
};

export default nextConfig;
