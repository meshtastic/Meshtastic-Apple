#!/bin/bash

# Sign with the 6YF6QJH524 team through a git-ignored local override.
cat > "$(dirname "$0")/../Config/Local.xcconfig" <<'XCCONFIG'
MESHTASTIC_DEVELOPMENT_TEAM = 6YF6QJH524
MESHTASTIC_BUNDLE_ID_PREFIX = thebentern.MeshtasticClient
MESHTASTIC_APP_GROUP = group.thebentern.MeshtasticClient
XCCONFIG
