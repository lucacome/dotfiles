#!/bin/sh

# exit immediately if password-manager-binary is already in $PATH
type bws >/dev/null 2>&1 && exit

# Get BWS TAG
TAG=$(curl -sL https://api.github.com/repos/bitwarden/sdk-sm/tags | grep -o 'bws-v[^"]*' | sort -un | tail -n 1)
# Get the latest release URL
RELEASE_ARCHIVE_URLS=$(curl -Ls "https://api.github.com/repos/bitwarden/sdk-sm/releases/tags/$TAG" | grep -Eo 'https://[^"]*' | grep 'download')

case "$(uname -s)" in
Darwin)
    # commands to install password-manager-binary on Darwin
    RELEASE_ARCHIVE_URL=$(echo "${RELEASE_ARCHIVE_URLS}" | grep 'universal')
    ;;
Linux)
    # commands to install password-manager-binary on Linux
    ARCH=$(arch)
    RELEASE_ARCHIVE_URL=$(echo "${RELEASE_ARCHIVE_URLS}" | grep 'linux-gnu' | grep "${ARCH}")
    ;;
*)
    echo "unsupported OS"
    exit 1
    ;;
esac

# Download the release archive and extract the binary
curl -sL "${RELEASE_ARCHIVE_URL}" -o /tmp/bitwarden.zip
unzip -q /tmp/bitwarden.zip -d /tmp/

# Move the binary to bin directory
mkdir -p "${HOME}"/bin
mv /tmp/bws "${HOME}"/bin/bws

export PATH="${HOME}/bin:${PATH}"
