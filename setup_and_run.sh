#!/usr/bin/env bash
set -euo pipefail

###############################################################################
# setup_and_run.sh
#
# Reproducibility bootstrap:
#   - works on Linux x86_64 and Linux aarch64
#   - uses existing Conda if available
#   - otherwise installs a pinned Miniforge locally (no sudo)
#   - verifies the Miniforge installer SHA-256
#   - creates the environment from environment.yml
#   - runs run.sh inside that environment
#
# Usage:
#   bash setup_and_run.sh
###############################################################################

export LC_ALL=C
export LANG=C
export TZ=UTC

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
cd "$ROOT"

ENV_FILE="$ROOT/environment.yml"
ENV_NAME="week5-best3145"

MINIFORGE_VERSION="26.7.2-0"

OS="$(uname -s)"
ARCH="$(uname -m)"

if [[ "$OS" != "Linux" ]]; then
    echo "ERROR: This bootstrap currently supports Linux only."
    echo "Detected OS: $OS"
    exit 1
fi

case "$ARCH" in
    x86_64|amd64)
        MINIFORGE_ARCH="x86_64"
        INSTALLER_SHA256="281b0ac7d550802efc81af633225a5e6116d29ae72f3ab4eae7168c3931a4c05"
        ;;
    aarch64|arm64)
        MINIFORGE_ARCH="aarch64"
        INSTALLER_SHA256="89b786c8d2c8b0fda7553914c1314ae4ddaa094503802f279377b19ac4463cb2"
        ;;
    *)
        echo "ERROR: Unsupported architecture: $ARCH"
        exit 1
        ;;
esac

INSTALLER="Miniforge3-${MINIFORGE_VERSION}-Linux-${MINIFORGE_ARCH}.sh"
INSTALLER_URL="https://github.com/conda-forge/miniforge/releases/download/${MINIFORGE_VERSION}/${INSTALLER}"

BOOTSTRAP_DIR="$ROOT/.bootstrap"
LOCAL_CONDA_DIR="$ROOT/.miniforge"
INSTALLER_PATH="$BOOTSTRAP_DIR/$INSTALLER"

mkdir -p "$BOOTSTRAP_DIR"

[[ -s "$ENV_FILE" ]] || {
    echo "ERROR: environment.yml not found: $ENV_FILE"
    exit 1
}

download_file() {
    local url="$1"
    local output="$2"

    if command -v curl >/dev/null 2>&1; then
        curl --fail --location --retry 3 --show-error "$url" -o "$output"
    elif command -v wget >/dev/null 2>&1; then
        wget --tries=3 -O "$output" "$url"
    else
        echo "ERROR: Neither curl nor wget is installed."
        exit 1
    fi
}

###############################################################################
# Find or install Conda
###############################################################################

CONDA_EXE=""

if command -v conda >/dev/null 2>&1; then
    CONDA_EXE="$(command -v conda)"
    echo "Using existing Conda:"
    echo "  $CONDA_EXE"

elif [[ -x "$LOCAL_CONDA_DIR/bin/conda" ]]; then
    CONDA_EXE="$LOCAL_CONDA_DIR/bin/conda"
    echo "Using existing project-local Miniforge:"
    echo "  $CONDA_EXE"

else
    echo
    echo "Conda not found."
    echo "Installing pinned Miniforge locally (no sudo)."
    echo "Version: $MINIFORGE_VERSION"
    echo "Path:    $LOCAL_CONDA_DIR"
    echo

    if [[ ! -s "$INSTALLER_PATH" ]]; then
        echo "Downloading Miniforge..."
        download_file "$INSTALLER_URL" "$INSTALLER_PATH"
    fi

    command -v sha256sum >/dev/null 2>&1 || {
        echo "ERROR: sha256sum is required."
        exit 1
    }

    ACTUAL_SHA256="$(sha256sum "$INSTALLER_PATH" | awk '{print $1}')"

    echo
    echo "Verifying Miniforge installer SHA-256..."

    if [[ "$ACTUAL_SHA256" != "$INSTALLER_SHA256" ]]; then
        echo "ERROR: Miniforge installer checksum mismatch."
        echo "Expected: $INSTALLER_SHA256"
        echo "Observed: $ACTUAL_SHA256"
        rm -f "$INSTALLER_PATH"
        exit 1
    fi

    echo "Checksum verified."

    rm -rf "$LOCAL_CONDA_DIR"

    bash "$INSTALLER_PATH" \
        -b \
        -p "$LOCAL_CONDA_DIR"

    CONDA_EXE="$LOCAL_CONDA_DIR/bin/conda"

    [[ -x "$CONDA_EXE" ]] || {
        echo "ERROR: Miniforge installation failed."
        exit 1
    }
fi

echo
"$CONDA_EXE" --version

###############################################################################
# Record bootstrap provenance
###############################################################################

mkdir -p "$ROOT/metadata"

{
    echo "bootstrap_os=$OS"
    echo "bootstrap_arch=$ARCH"
    echo "miniforge_version=$MINIFORGE_VERSION"
    echo "conda_executable=$CONDA_EXE"
    "$CONDA_EXE" --version
} > "$ROOT/metadata/bootstrap_environment.txt"

###############################################################################
# Create the environment if it does not already exist
###############################################################################

if "$CONDA_EXE" env list | awk 'NF >= 1 && $1 !~ /^#/ {print $1}' | grep -qx "$ENV_NAME"; then
    echo
    echo "Conda environment already exists:"
    echo "  $ENV_NAME"
    echo "Skipping environment creation."
else
    echo
    echo "Creating environment from:"
    echo "  $ENV_FILE"

    "$CONDA_EXE" env create \
        --file "$ENV_FILE" \
        --yes
fi

###############################################################################
# Run the analysis without requiring shell activation
###############################################################################

echo
echo "======================================================================"
echo "RUNNING ANALYSIS"
echo "======================================================================"
echo

"$CONDA_EXE" run \
    --no-capture-output \
    -n "$ENV_NAME" \
    bash "$ROOT/run.sh"

echo
echo "======================================================================"
echo "BOOTSTRAP + ANALYSIS COMPLETE"
echo "======================================================================"
echo
echo "To verify:"
echo "  $CONDA_EXE run -n $ENV_NAME bash $ROOT/verify.sh"

