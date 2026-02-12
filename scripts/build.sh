#!/bin/sh
set -e

# Prefer DEVELOPMENT_TEAM from .env when present.
# Accepts lines like: DEVELOPMENT_TEAM=ABC123XYZ9
if [ -f .env ]; then
  ENV_DEVELOPMENT_TEAM=$(sed -nE 's/^[[:space:]]*DEVELOPMENT_TEAM[[:space:]]*=[[:space:]]*([^#[:space:]]+).*/\1/p' .env | tail -n 1)
  if [ -n "$ENV_DEVELOPMENT_TEAM" ]; then
    DEVELOPMENT_TEAM="$ENV_DEVELOPMENT_TEAM"
  fi
fi

if [ -z "$DEVELOPMENT_TEAM" ] || [ "$DEVELOPMENT_TEAM" = "YOUR_TEAM_ID" ]; then
  echo "Warning: DEVELOPMENT_TEAM is not set. Building without code signing."
  OUTPUT=$(xcodegen generate 2>&1 && \
    xcodebuild -project Tabbed.xcodeproj -scheme Tabbed -derivedDataPath build \
      CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO \
      build 2>&1) || {
    echo "$OUTPUT"
    exit 1
  }
else
  OUTPUT=$(xcodegen generate 2>&1 && \
    xcodebuild -project Tabbed.xcodeproj -scheme Tabbed -derivedDataPath build \
      DEVELOPMENT_TEAM="$DEVELOPMENT_TEAM" \
      -allowProvisioningUpdates \
      build 2>&1) || {
    echo "$OUTPUT"
    exit 1
  }
fi
