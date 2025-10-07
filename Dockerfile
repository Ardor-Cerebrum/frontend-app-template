# Build-time arguments that are used in FROM instructions must be before first FROM
ARG NODE_VERSION=22.14.0
ARG NGINX_VERSION=alpine

# Other build-time arguments
ARG PNPM_VERSION=latest
ARG BUILD_DATE=unknown
ARG VCS_REF=unknown
ARG VERSION=1.0.0

# Add a build argument for the build mode
ARG BUILD_MODE=production

# Application metadata
ARG APP_TITLE="Frontend Application"
ARG APP_DESCRIPTION="Production image for frontend application"
ARG APP_REPO="your-org/your-repo"

# ---- Build Stage ----
FROM node:${NODE_VERSION}-alpine AS build

# Re-declare ARGs used in this stage
ARG PNPM_VERSION
ARG NODE_VERSION

# Performance optimization
ENV NODE_OPTIONS="--max_old_space_size=8192"
ENV GENERATE_SOURCEMAP="false"
WORKDIR /app

# Install dependencies first (better layer caching)
RUN npm install -g pnpm@${PNPM_VERSION}
COPY package.json pnpm-lock.yaml* ./
COPY .env* ./
RUN pnpm install --frozen-lockfile

# If you want to pass the env contents via ENV_FILE, materialize it:
# This creates .env.staging or .env.production inside the container
RUN printf "%s" "$ENV_FILE" > .env.${BUILD_MODE}

# Debug to confirm it's set in CI
RUN echo "BUILD_MODE=$BUILD_MODE" && ls -la .env* || true


# Build application
COPY . .
RUN if [ "$BUILD_MODE" = "staging" ]; then pnpm run build --mode staging; else pnpm run build; fi

# Extract version from package.json 
RUN pnpm pkg get version | tr -d '"' > /app/VERSION

# ---- Runtime Stage ----
FROM nginx:${NGINX_VERSION} AS runtime

# Re-declare ARGs used in this stage
ARG BUILD_MODE
ARG APP_TITLE
ARG APP_DESCRIPTION
ARG BUILD_DATE
ARG VCS_REF
ARG APP_REPO
ARG NODE_VERSION
ARG NGINX_VERSION

# Copy version file from build stage and set ENV
COPY --from=build /app/VERSION /app/VERSION
ENV VERSION=1.0.0

# Set permissions for nginx user (which already exists in nginx:alpine)
RUN chown -R nginx:nginx /usr/share/nginx/html && \
    chown -R nginx:nginx /var/cache/nginx && \
    chown -R nginx:nginx /var/log/nginx && \
    chown -R nginx:nginx /etc/nginx/conf.d && \
    chown -R nginx:nginx /var/run && \
    chown -R nginx:nginx /app

# Application metadata using OCI specification
LABEL org.opencontainers.image.title="${APP_TITLE}" \
      org.opencontainers.image.description="${APP_DESCRIPTION}" \
      org.opencontainers.image.version="${VERSION}" \
      org.opencontainers.image.created="${BUILD_DATE}" \
      org.opencontainers.image.revision="${VCS_REF}" \
      org.opencontainers.image.licenses="MIT" \
      org.opencontainers.image.vendor="Your Organization" \
      org.opencontainers.image.documentation="https://github.com/${APP_REPO}/README.md" \
      org.opencontainers.image.url="https://github.com/${APP_REPO}" \
      app.stack.node="${NODE_VERSION}" \
      app.stack.nginx="${NGINX_VERSION}" \
      app.stack.package_manager="pnpm" \
      app.environment="${BUILD_MODE}"

# Application setup
COPY --from=build /app/dist /usr/share/nginx/html
COPY nginx.conf /etc/nginx/

# Runtime configuration
USER nginx
EXPOSE 80
ENTRYPOINT ["nginx", "-g", "daemon off;"]

# Container health monitoring
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD ["curl", "-f", "http://localhost/", "||", "exit", "1"]
