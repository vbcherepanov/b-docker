# --- Stage 1: Builder ---
FROM golang:alpine AS builder

RUN apk add --no-cache git
RUN go install github.com/mailhog/MailHog@latest

# --- Stage 2: Runtime ---
FROM alpine:latest

RUN apk --no-cache add ca-certificates bash curl

ARG ENVIRONMENT=production
ENV ENVIRONMENT=${ENVIRONMENT}

COPY --from=builder /go/bin/MailHog /usr/local/bin/MailHog

EXPOSE 1025 8025

COPY /docker/common/mailhog/docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh
RUN chmod +x /usr/local/bin/docker-entrypoint.sh
HEALTHCHECK --interval=30s --timeout=5s --retries=3 \
  CMD curl -f http://localhost:8025 || exit 1
ENTRYPOINT ["docker-entrypoint.sh"]