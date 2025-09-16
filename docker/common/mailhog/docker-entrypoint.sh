#!/bin/sh
set -e

if [ "$ENVIRONMENT" = "local" -o  "$ENVIRONMENT" = "dev" ]; then
  echo "📬 Starting MailHog in local mode..."
  exec MailHog
else
  echo "⚠️  MailHog is disabled in ENV=$ENVIRONMENT"
  tail -f /dev/null
fi