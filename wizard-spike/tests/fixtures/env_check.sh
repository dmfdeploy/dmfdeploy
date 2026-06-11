#!/bin/sh
if [ -n "${LEAK:-}" ]; then
  echo "leaked: $LEAK" >&2
  exit 1
fi
exit 0
