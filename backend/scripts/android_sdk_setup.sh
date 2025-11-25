#!/usr/bin/env bash
set -euo pipefail

# === Konfig ===
SDK_ROOT="${HOME}/Android/Sdk"
CML_TOOLS_ZIP="commandlinetools-linux.zip"
CML_TOOLS_URL="https://dl.google.com/android/repository/commandlinetools-linux-11076708_latest.zip"  # Googles senaste per okt 2025
NEEDED_PKGS=( "openjdk-17-jdk" "curl" "wget" "unzip" "zip" )

echo "==> Installerar baspaket (sudo krävs en gång)..."
if command -v apt >/dev/null 2>&1; then
  sudo apt update -y
  sudo apt install -y "${NEEDED_PKGS[@]}"
else
  echo "Stödd distro saknas (skriptet antar Debian/Ubuntu). Avbryter."
  exit 1
fi

echo "==> Skapar SDK-root: ${SDK_ROOT}"
mkdir -p "${SDK_ROOT}/cmdline-tools"
cd "${SDK_ROOT}"

if [ ! -f "${CML_TOOLS_ZIP}" ]; then
  echo "==> Hämtar Android cmdline-tools..."
  wget -O "${CML_TOOLS_ZIP}" "${CML_TOOLS_URL}"
fi

echo "==> Packar upp cmdline-tools..."
rm -rf "${SDK_ROOT}/cmdline-tools/latest" || true
unzip -q -o "${CML_TOOLS_ZIP}" -d "${SDK_ROOT}/cmdline-tools"
# Google packar mappen som 'cmdline-tools'; vi vill ha 'latest'
if [ -d "${SDK_ROOT}/cmdline-tools/cmdline-tools" ]; then
  mv "${SDK_ROOT}/cmdline-tools/cmdline-tools" "${SDK_ROOT}/cmdline-tools/latest"
fi

# Export för denna session
export ANDROID_SDK_ROOT="${SDK_ROOT}"
export PATH="${ANDROID_SDK_ROOT}/cmdline-tools/latest/bin:${ANDROID_SDK_ROOT}/platform-tools:${PATH}"

echo "==> Installerar SDK-komponenter via sdkmanager..."
yes | sdkmanager --licenses >/dev/null 2>&1 || true
sdkmanager --install \
  "platform-tools" \
  "cmdline-tools;latest" \
  "platforms;android-36" \
  "build-tools;36.0.0" \
  "build-tools;28.0.3"

echo "==> Accepterar licenser..."
yes | sdkmanager --licenses

echo "==> Verifierar installation..."
sdkmanager --list | head -n 50 || true
echo "ANDROID_SDK_ROOT=${ANDROID_SDK_ROOT}"

# Lägg till PATH permanent i bashrc om saknas
BASHRC="${HOME}/.bashrc"
ADD_EXPORTS=$(cat <<'EOF'
# >>> Android SDK (autoinstallerat) >>>
export ANDROID_SDK_ROOT="$HOME/Android/Sdk"
export PATH="$ANDROID_SDK_ROOT/cmdline-tools/latest/bin:$ANDROID_SDK_ROOT/platform-tools:$PATH"
# <<< Android SDK <<<
EOF
)

if ! grep -q 'Android SDK (autoinstallerat)' "${BASHRC}" 2>/dev/null; then
  echo "==> Lägger PATH-rader i ${BASHRC}"
  printf "\n%s\n" "${ADD_EXPORTS}" >> "${BASHRC}"
fi

echo "==> Klart! Starta en ny terminal eller kör:"
echo "source ~/.bashrc"
