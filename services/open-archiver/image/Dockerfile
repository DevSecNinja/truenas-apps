FROM docker.io/logiclabshq/open-archiver:2082eba@sha256:c1a70098db59cdb3559cdbe4f4bf33bb33a8339b8c86a3c56c4d1ac8bfd7025b

LABEL org.opencontainers.image.source="https://github.com/DevSecNinja/truenas-apps" \
      org.opencontainers.image.title="Open Archiver non-root runtime" \
      org.opencontainers.image.upstream.revision="2082eba984ca771c23c2a7c60fc9284794e24b9b"

WORKDIR /app
ENV NODE_ENV=production \
    HOME=/tmp \
    CI=true

# Upstream ships compiled code but installs dependencies at every startup.
# Bake the locked dependencies, including the SQLite binding used by imports.
RUN node -e "const fs=require('fs'); const p=require('./package.json'); p.pnpm.onlyBuiltDependencies=['esbuild','sqlite3']; fs.writeFileSync('package.json', JSON.stringify(p));" \
    && pnpm install --frozen-lockfile --prod \
    && cd /app/packages/backend \
    && node -e "require('sqlite3')" \
    && chmod -R a+rX /app

COPY start.mjs /usr/local/bin/open-archiver-start.mjs

USER 3132:3132
ENTRYPOINT ["node", "/usr/local/bin/open-archiver-start.mjs"]
CMD []
HEALTHCHECK --interval=30s --timeout=10s --start-period=90s --retries=5 \
    CMD node -e "fetch('http://127.0.0.1:3000/api/v1/auth/status').then(r=>process.exit(r.ok?0:1)).catch(()=>process.exit(1))"
