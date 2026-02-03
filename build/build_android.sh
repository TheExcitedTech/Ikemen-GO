#!/usr/bin/env bash
set -euo pipefail

# Build Android APK via Docker Compose.
# Usage:
#   ./build/build_android.sh
#   ./build/build_android.sh --no-build
#   APP_VERSION=my-build APP_BUILDTIME=2026.01.13 ./build/build_android.sh

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"
cd "$REPO_ROOT"

COMPOSE_FILE="$REPO_ROOT/build/docker/android/docker-compose.yml"

pause_always_windows() {
  local status="${1:-0}"
  case "$OSTYPE" in
    msys|cygwin)
      # Don't pause in CI environments (prevents hanging GitHub Actions).
      if [[ -n "${CI:-}" || -n "${GITHUB_ACTIONS:-}" ]]; then
        return 0
      fi
      # If stdin/stdout are terminals, wait for a keypress so the window doesn't auto-close.
      if [[ -t 0 && -t 1 ]]; then
        echo
        if [[ "$status" -eq 0 ]]; then
          printf "Done. Press any key to close..."
        else
          printf "Failed (exit %s). Press any key to close..." "$status"
        fi
        IFS= read -r -n1 _ || true
        echo
      fi
    ;;
  esac
}
trap 'st=$?; pause_always_windows "$st"' EXIT

DO_BUILD=1
DO_RUN=1
FRESH=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --no-build)
      DO_BUILD=0
      shift
      ;;
    --build-only)
      DO_RUN=0
      shift
      ;;
    --fresh)
      FRESH=1
      shift
      ;;
    -h|--help)
      cat <<'EOF'
Usage: ./build/build_android.sh [--no-build] [--build-only] [--fresh]

Builds the Docker image and runs the android-build container to produce:
  - bin/ikemen-go.apk
  - bin/libmain.so, bin/libmain.h
  - lib/*.so

Options:
  --fresh       wipe compose cache volumes and rebuild image with --no-cache

Environment overrides (optional):
  APP_VERSION, APP_BUILDTIME, ANDROID_APK_REPO, ANDROID_APK_REF, BUILD_ANDROID_APK, DOCKER_PLATFORM
EOF
      exit 0
      ;;
    *)
      echo "ERROR: Unknown argument: $1" >&2
      echo "Run with --help for usage." >&2
      exit 1
      ;;
  esac
done

# The Android NDK toolchain in this pipeline is x86_64-hosted.
# On Apple Silicon, default to amd64 Docker emulation unless explicitly overridden.
DOCKER_PLATFORM="${DOCKER_PLATFORM:-}"
if [[ -z "$DOCKER_PLATFORM" ]]; then
  case "$(uname -m 2>/dev/null || true)" in
    arm64|aarch64)
      DOCKER_PLATFORM="linux/amd64"
      ;;
  esac
fi
if [[ -n "$DOCKER_PLATFORM" ]]; then
  export DOCKER_DEFAULT_PLATFORM="$DOCKER_PLATFORM"
  echo "==> Docker platform: $DOCKER_DEFAULT_PLATFORM"
fi

# Prefer "docker compose" but fall back to legacy "docker-compose" if present.
if docker compose version >/dev/null 2>&1; then
  DC=(docker compose -f "$COMPOSE_FILE")
elif command -v docker-compose >/dev/null 2>&1; then
  DC=(docker-compose -f "$COMPOSE_FILE")
else
  echo "ERROR: docker compose not found. Install Docker / Docker Compose." >&2
  exit 1
fi

# Ensure Docker daemon is reachable before trying to build/run.
if command -v docker >/dev/null 2>&1; then
  if ! docker info >/dev/null 2>&1; then
    echo "ERROR: Docker daemon is not running or not reachable." >&2
    echo "Start Docker Desktop (or dockerd) and retry." >&2
    exit 1
  fi
fi

if [[ "$FRESH" == "1" ]]; then
  echo "==> Fresh mode: removing compose containers and cache volumes"
  "${DC[@]}" down -v --remove-orphans || true
fi

if [[ "$DO_BUILD" == "1" ]]; then
  echo "==> Building Docker image: android-build"
  if [[ "$FRESH" == "1" ]]; then
    "${DC[@]}" build --no-cache android-build
  else
    "${DC[@]}" build android-build
  fi
fi

if [[ "$DO_RUN" == "1" ]]; then
  echo "==> Running container: android-build"
  "${DC[@]}" run --rm android-build
fi
