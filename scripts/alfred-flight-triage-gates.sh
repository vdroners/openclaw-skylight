#!/usr/bin/env bash
# Aggregator alias for historical alfred-flight-triage-gates.sh name.
exec "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/openclaw-flight-triage-gates.sh" "$@"
