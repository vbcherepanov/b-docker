# =============================================================================
# BITRIX PUSH SERVER
# Node.js based push server for Bitrix real-time notifications
# =============================================================================

FROM node:20-alpine

LABEL maintainer="DevOps Team"
LABEL description="Bitrix Push&Pull Server"

# Install dependencies
RUN apk add --no-cache \
    redis \
    curl \
    && rm -rf /var/cache/apk/*

WORKDIR /opt/push-server

# Copy push server files
COPY config.json /opt/push-server/config.json

# Install push-server from npm
RUN npm install -g push-server@1.0.15

# Expose ports
# 8010 - HTTP
# 8011 - HTTPS (optional)
# 9010 - Internal
EXPOSE 8010 9010

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=10s --retries=3 \
    CMD curl -f http://localhost:8010/server-stat/ || exit 1

CMD ["push-server", "--config", "/opt/push-server/config.json"]
