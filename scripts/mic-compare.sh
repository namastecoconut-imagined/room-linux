#!/usr/bin/env bash
# Which mic does Deepgram hear best? (Records every mic at once; Room keeps running.)
HERE="$(cd "$(dirname "$0")/.." && pwd)"
"$HERE/voice/.venv/bin/python" -I "$HERE/voice/miccompare.py"
