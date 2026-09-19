#!/usr/bin/env bash
set -euo pipefail

###############################################################################
# One-command bootstrap + analysis + verification
#
# If Conda is unavailable, install a pinned Miniforge release locally.
# A project-local Conda environment is used even when a system Conda exists,
# avoiding collisions with another user's environment of the same name.
###############################################################################

export LC_ALL=C
export LANG=C
export TZ=UTC

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
cd "$ROOT"

ENV_FILE="$ROOT/environment.yml"
ENV_PREFIX="$ROOT/.conda-env"

MINIFORGE_VERSION="26.7.2-0"
OS="$(uname -s)"
ARCH="$(uname -m)"

[[ "$OS" == "Linux" ]] || {
    echo "ERROR: This bootstrap currently supports Linux only."
    echo "Detected OS: $OS"
    exit 1
}

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
        echo "ERROR: Unsupported Linux architecture: $ARCH"
        exit 1
        ;;
esac

INSTALLER="Miniforge3-${MINIFORGE_VERSION}-Linux-${MINIFORGE_ARCH}.sh"
INSTALLER_URL="https://github.com/conda-forge/miniforge/releases/download/${MINIFORGE_VERSION}/${INSTALLER}"
BOOTSTRAP_DIR="$ROOT/.bootstrap"
LOCAL_CONDA_DIR="$ROOT/.miniforge"
INSTALLER_PATH="$BOOTSTRAP_DIR/$INSTALLER"

mkdir -p "$BOOTSTRAP_DIR" "$ROOT/metadata"

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
    echo "Using existing Conda executable:"
    echo "  $CONDA_EXE"
elif [[ -x "$LOCAL_CONDA_DIR/bin/conda" ]]; then
    CONDA_EXE="$LOCAL_CONDA_DIR/bin/conda"
    echo "Using project-local Miniforge:"
    echo "  $CONDA_EXE"
else
    echo "Conda was not found. Installing pinned Miniforge locally."
    echo "Version : $MINIFORGE_VERSION"
    echo "Prefix  : $LOCAL_CONDA_DIR"

    if [[ ! -s "$INSTALLER_PATH" ]]; then
        echo "Downloading $INSTALLER_URL"
        download_file "$INSTALLER_URL" "$INSTALLER_PATH"
    fi

    command -v sha256sum >/dev/null 2>&1 || {
        echo "ERROR: sha256sum is required to verify the installer."
        exit 1
    }

    actual_sha256="$(sha256sum "$INSTALLER_PATH" | awk '{print $1}')"

    if [[ "$actual_sha256" != "$INSTALLER_SHA256" ]]; then
        echo "ERROR: Miniforge installer checksum mismatch."
        echo "Expected: $INSTALLER_SHA256"
        echo "Observed: $actual_sha256"
        rm -f "$INSTALLER_PATH"
        exit 1
    fi

    echo "Miniforge installer checksum verified."

    rm -rf "$LOCAL_CONDA_DIR"
    bash "$INSTALLER_PATH" -b -p "$LOCAL_CONDA_DIR"

    CONDA_EXE="$LOCAL_CONDA_DIR/bin/conda"
    [[ -x "$CONDA_EXE" ]] || {
        echo "ERROR: Miniforge installation failed."
        exit 1
    }
fi

"$CONDA_EXE" --version

###############################################################################
# Record bootstrap provenance
###############################################################################

{
    echo "bootstrap_os=$OS"
    echo "bootstrap_arch=$ARCH"
    echo "miniforge_version=$MINIFORGE_VERSION"
    echo "conda_executable=$CONDA_EXE"
    "$CONDA_EXE" --version
} > "$ROOT/metadata/bootstrap_environment.txt"

###############################################################################
# Create/update a PROJECT-LOCAL analysis environment
###############################################################################

if [[ -x "$ENV_PREFIX/bin/python" ]]; then
    echo
    echo "Updating existing project environment to match environment.yml..."
    "$CONDA_EXE" env update \
        --prefix "$ENV_PREFIX" \
        --file "$ENV_FILE" \
        --prune
else
    echo
    echo "Creating project environment from environment.yml..."
    "$CONDA_EXE" env create \
        --prefix "$ENV_PREFIX" \
        --file "$ENV_FILE" \
        --yes
fi

###############################################################################
# Run analysis
###############################################################################

echo
echo "======================================================================"
echo "RUNNING ANALYSIS"
echo "======================================================================"

"$CONDA_EXE" run \
    --no-capture-output \
    --prefix "$ENV_PREFIX" \
    bash "$ROOT/run.sh"

###############################################################################
# Verify against canonical checksums
###############################################################################

echo
echo "======================================================================"
echo "VERIFYING AGAINST CANONICAL CHECKSUMS"
echo "======================================================================"

"$CONDA_EXE" run \
    --no-capture-output \
    --prefix "$ENV_PREFIX" \
    bash "$ROOT/verify.sh"

echo
echo "======================================================================"
echo "SETUP + ANALYSIS + VERIFICATION COMPLETE"
echo "======================================================================"
