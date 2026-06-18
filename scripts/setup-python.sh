#!/usr/bin/env bash
#
# One-command Python dev-environment setup for liquidity-bridge-contract.
#
# Creates `.venv/` at the repo root and installs pinned Halmos for formal
# verification. Re-running is safe — upgrades the existing venv in place.
#
# Do not add a root-level requirements.txt — crytic/slither-action auto-installs
# it in CI inside a Python 3.9 container.
# Strategy:
#   1. If `uv` is on PATH, use it -- it can fetch its own Python 3.12 if the
#      system doesn't have one.
#   2. Otherwise, look for python3.12 or python3.11 on PATH (Halmos requires
#      Python >= 3.11).
#   3. If neither is available, fail with installation instructions.

set -euo pipefail

VENV_DIR=".venv"
TARGET_PYTHON="3.12"   # used by uv; matches CI's actions/setup-python step
MIN_PYTHON_MAJOR=3
MIN_PYTHON_MINOR=11
# Bump in lockstep with lib/halmos-cheatcodes and formal.yml.
HALMOS_VERSION="0.3.3"

SCRIPT_DIR="$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &>/dev/null && pwd )"
REPO_ROOT="$( cd -- "$SCRIPT_DIR/.." &>/dev/null && pwd )"
cd "$REPO_ROOT"

python_meets_minimum() {
    local py="$1"
    "$py" -c "import sys; sys.exit(0 if sys.version_info >= (${MIN_PYTHON_MAJOR}, ${MIN_PYTHON_MINOR}) else 1)"
}

remove_incompatible_venv() {
    if [ ! -d "$VENV_DIR" ] || [ ! -x "$VENV_DIR/bin/python" ]; then
        return
    fi
    if python_meets_minimum "$VENV_DIR/bin/python"; then
        return
    fi
    echo "==> removing $VENV_DIR/ ($("$VENV_DIR/bin/python" --version 2>&1); need Python >= ${MIN_PYTHON_MAJOR}.${MIN_PYTHON_MINOR})" >&2
    rm -rf "$VENV_DIR"
}

install_halmos() {
    local py="$1"
    if command -v uv >/dev/null 2>&1; then
        uv pip install --python "$py" "halmos==${HALMOS_VERSION}"
    else
        "$py" -m pip install --upgrade --quiet pip
        "$py" -m pip install "halmos==${HALMOS_VERSION}"
    fi
}

remove_incompatible_venv

if command -v uv >/dev/null 2>&1; then
    echo "==> uv detected; provisioning $VENV_DIR/ with Python $TARGET_PYTHON"
    if [ ! -d "$VENV_DIR" ]; then
        uv venv "$VENV_DIR" --python "$TARGET_PYTHON"
    else
        echo "    reusing existing $VENV_DIR/ ($("$VENV_DIR/bin/python" --version 2>&1))"
    fi
    if ! python_meets_minimum "$VENV_DIR/bin/python"; then
        echo "error: $VENV_DIR/bin/python is too old (need >= ${MIN_PYTHON_MAJOR}.${MIN_PYTHON_MINOR})" >&2
        exit 1
    fi
    install_halmos "$VENV_DIR/bin/python"
else
    echo "==> uv not found; falling back to system python"
    PY=""
    for cand in python3.12 python3.11; do
        if command -v "$cand" >/dev/null 2>&1 && python_meets_minimum "$cand"; then
            PY="$cand"
            break
        fi
    done
    if [ -z "$PY" ]; then
        cat >&2 <<EOF
error: no compatible Python found (need python3.12 or python3.11 on PATH).
       Halmos requires Python >= ${MIN_PYTHON_MAJOR}.${MIN_PYTHON_MINOR}.

Recommended fix: install uv, which manages its own Python:
    curl -LsSf https://astral.sh/uv/install.sh | sh
    make python-setup

Or install Python 3.12 from your package manager and re-run make python-setup.
EOF
        exit 1
    fi
    echo "    using $PY ($($PY --version 2>&1))"
    if [ ! -d "$VENV_DIR" ]; then
        "$PY" -m venv "$VENV_DIR"
    else
        echo "    reusing existing $VENV_DIR/ ($("$VENV_DIR/bin/python" --version 2>&1))"
    fi
    if ! python_meets_minimum "$VENV_DIR/bin/python"; then
        echo "error: $VENV_DIR/bin/python is too old (need >= ${MIN_PYTHON_MAJOR}.${MIN_PYTHON_MINOR})" >&2
        exit 1
    fi
    install_halmos "$VENV_DIR/bin/python"
fi

echo ""
echo "==> Python dev environment ready at $VENV_DIR/"
echo "    Activate with:  source $VENV_DIR/bin/activate"
echo "    halmos:         $($VENV_DIR/bin/halmos --version 2>/dev/null || echo 'not installed')"
