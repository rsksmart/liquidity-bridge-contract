#!/usr/bin/env bash
#
# One-command Python dev-environment setup for liquidity-bridge-contract.
#
# Creates `.venv/` at the repo root and installs the pinned Python tooling
# (pre-commit + Halmos) from the project's two requirements files. Re-running
# is safe -- it upgrades the existing venv in place rather than recreating it.
#
# Strategy:
#   1. If `uv` is on PATH, use it -- it can fetch its own Python 3.12 if the
#      system doesn't have one.
#   2. Otherwise, look for python3.12 or python3.11 on PATH (Halmos requires
#      Python >= 3.11).
#   3. If neither is available, fail with installation instructions.

set -euo pipefail

VENV_DIR=".venv"
TARGET_PYTHON="3.12"   # used by uv; matches CI's actions/setup-python step
REQ_DEV="requirements-dev.txt"
REQ_FORMAL="requirements-formal.txt"

SCRIPT_DIR="$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &>/dev/null && pwd )"
REPO_ROOT="$( cd -- "$SCRIPT_DIR/.." &>/dev/null && pwd )"
cd "$REPO_ROOT"

if [ ! -f "$REQ_DEV" ] || [ ! -f "$REQ_FORMAL" ]; then
    echo "error: $REQ_DEV or $REQ_FORMAL not found in $REPO_ROOT" >&2
    exit 1
fi

if command -v uv >/dev/null 2>&1; then
    echo "==> uv detected; provisioning $VENV_DIR/ with Python $TARGET_PYTHON"
    if [ ! -d "$VENV_DIR" ]; then
        uv venv "$VENV_DIR" --python "$TARGET_PYTHON"
    else
        echo "    reusing existing $VENV_DIR/"
    fi
    uv pip install \
        --python "$VENV_DIR/bin/python" \
        -r "$REQ_DEV" -r "$REQ_FORMAL"
else
    echo "==> uv not found; falling back to system python"
    PY=""
    for cand in python3.12 python3.11; do
        if command -v "$cand" >/dev/null 2>&1; then
            PY="$cand"
            break
        fi
    done
    if [ -z "$PY" ]; then
        cat >&2 <<EOF
error: no compatible Python found (need python3.12 or python3.11 on PATH).
       Halmos requires Python >= 3.11.

Recommended fix: install uv, which manages its own Python:
    curl -LsSf https://astral.sh/uv/install.sh | sh

Or install Python 3.12 from your package manager and re-run.
EOF
        exit 1
    fi
    echo "    using $PY ($($PY --version 2>&1))"
    if [ ! -d "$VENV_DIR" ]; then
        "$PY" -m venv "$VENV_DIR"
    else
        echo "    reusing existing $VENV_DIR/"
    fi
    "$VENV_DIR/bin/pip" install --upgrade --quiet pip
    "$VENV_DIR/bin/pip" install -r "$REQ_DEV" -r "$REQ_FORMAL"
fi

if [ -d ".git" ]; then
    "$VENV_DIR/bin/pre-commit" install --install-hooks >/dev/null
fi

echo ""
echo "==> Python dev environment ready at $VENV_DIR/"
echo "    Activate with:  source $VENV_DIR/bin/activate"
echo "    halmos:         $($VENV_DIR/bin/halmos --version 2>/dev/null || echo 'not installed')"
echo "    pre-commit:     $($VENV_DIR/bin/pre-commit --version 2>/dev/null || echo 'not installed')"
