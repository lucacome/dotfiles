# dotfiles

Personal dotfiles managed with [chezmoi](https://www.chezmoi.io/), targeting macOS and Linux.

## Setup

```sh
sh -c "$(curl -fsLS get.chezmoi.io)" -- init --apply lucacome
```

Or, if chezmoi is already installed:

```sh
chezmoi init --apply lucacome
```

## Contents

### Shell

| Tool | Purpose |
|---|---|
| [Zsh](https://www.zsh.org/) + [Oh My Zsh](https://ohmyz.sh/) | Shell with plugins configured via template |
| [oh-my-posh](https://ohmyposh.dev/) | Prompt theme (`shell_theme.omp.json`) |
| [Atuin](https://atuin.sh/) | Shell history with sync |

Useful options enabled: `autocd`, `autopushd`, `share_history`, large history (10M entries), and `Ctrl+Space` to accept autosuggestions.

### macOS Desktop

| Tool | Purpose |
|---|---|
| [AeroSpace](https://github.com/nikitabobko/AeroSpace) | Tiling window manager |
| [Sketchybar](https://felixkratz.github.io/SketchyBar/) | Custom menu bar |
| [JankyBorders](https://github.com/FelixKratz/JankyBorders) | Focused window border highlight |
| [Hammerspoon](https://www.hammerspoon.org/) | macOS automation & hotkeys |

### Terminal

[Ghostty](https://ghostty.org/)

### Tool Management

[mise](https://mise.jdx.dev/) manages tool versions. Managed tools include:

- `bitwarden` / `bitwarden-secrets-manager`
- `age`, `atuin`, `oh-my-posh`, `eza` (Linux only)

### Aliases

Aliases are templated per OS/available tools:

| Alias | Command |
|---|---|
| `update` | Full system update (brew on macOS, apt on Debian, + mise) |
| `cat` | `bat` / `batcat` |
| `ls` / `la` / `ll` / `lrt` / `lart` | `eza` variants with git integration |
| `fd` | `fdfind` |

## Structure

```sh
home/
├── dot_aliases.tmpl          # Shell aliases (OS-aware)
├── dot_zprofile.tmpl         # Homebrew env setup
├── dot_zshrc.tmpl            # Zsh config with oh-my-zsh
└── dot_config/
    ├── aerospace/            # AeroSpace tiling WM config
    ├── atuin/                # Shell history config
    ├── borders/              # JankyBorders config
    ├── ghostty/              # Ghostty terminal config
    ├── mise/                 # mise tool version config
    ├── oh-my-posh/           # Prompt theme
    └── sketchybar/           # Menu bar
```
