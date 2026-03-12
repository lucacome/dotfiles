#!/bin/sh

# exit immediately if mise is already in $PATH
type mise >/dev/null 2>&1 && exit

case "$(uname -s)" in
Darwin)
    brew install mise
    ;;
Linux)
    apt-get update -y && apt-get install -y curl
    install -dm 755 /etc/apt/keyrings
    curl -fSs https://mise.jdx.dev/gpg-key.pub | tee /etc/apt/keyrings/mise-archive-keyring.asc 1>/dev/null
    echo "deb [signed-by=/etc/apt/keyrings/mise-archive-keyring.asc] https://mise.jdx.dev/deb stable main" | tee /etc/apt/sources.list.d/mise.list
    apt-get update -y
    apt-get install -y mise
    ;;
*)
    echo "unsupported OS"
    exit 1
    ;;
esac
