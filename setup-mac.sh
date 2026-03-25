#!/bin/bash
set -euo pipefail

# macOS セットアップスクリプト
# 使い方: curl or コピペで実行
#   bash scripts/setup-mac.sh          # 全社員共通のみ
#   bash scripts/setup-mac.sh --dev    # 全社員共通 + 開発ツール
#   bash scripts/setup-mac.sh --all    # 同上

CYAN='\033[0;36m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

info()  { echo -e "${CYAN}[INFO]${NC} $1"; }
ok()    { echo -e "${GREEN}[OK]${NC} $1"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
err()   { echo -e "${RED}[ERROR]${NC} $1"; }

# 対話プロンプト
ask() {
  local prompt="$1"
  local var_name="$2"
  local default="${3:-}"
  if [[ -n "$default" ]]; then
    read -rp "$(echo -e "${CYAN}[?]${NC} ${prompt} [${default}]: ")" input
    eval "$var_name=\"${input:-$default}\""
  else
    read -rp "$(echo -e "${CYAN}[?]${NC} ${prompt}: ")" input
    eval "$var_name=\"$input\""
  fi
}

# yes/no プロンプト
confirm() {
  local prompt="$1"
  local answer
  read -rp "$(echo -e "${CYAN}[?]${NC} ${prompt} (y/n): ")" answer
  [[ "$answer" =~ ^[Yy] ]]
}

# ------------------------------------------------------------------
# Homebrew
# ------------------------------------------------------------------
install_homebrew() {
  if command -v brew &>/dev/null; then
    ok "Homebrew already installed"
  else
    info "Installing Homebrew..."
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    ok "Homebrew installed"
  fi

  # PATH に brew が通っていなければ .zprofile に追加
  if ! command -v brew &>/dev/null; then
    if [[ $(uname -m) == "arm64" ]]; then
      local brew_path="/opt/homebrew/bin/brew"
    else
      local brew_path="/usr/local/bin/brew"
    fi

    if [[ -x "$brew_path" ]]; then
      echo "eval \"\$(${brew_path} shellenv)\"" >> "$HOME/.zprofile"
      eval "$("$brew_path" shellenv)"
      ok "Homebrew PATH added to ~/.zprofile"
    fi
  fi
}

# ------------------------------------------------------------------
# インストールヘルパー
# ------------------------------------------------------------------
install_cask() {
  local name="$1"
  if brew list --cask "$name" &>/dev/null; then
    ok "$name already installed"
  else
    info "Installing $name..."
    brew install --cask "$name" || warn "Failed to install $name"
  fi
}

install_formula() {
  local name="$1"
  if brew list "$name" &>/dev/null; then
    ok "$name already installed"
  else
    info "Installing $name..."
    brew install "$name" || warn "Failed to install $name"
  fi
}

install_mas_app() {
  local name="$1"
  local app_id="$2"
  if ! command -v mas &>/dev/null; then
    brew install mas || { warn "mas のインストールに失敗。${name} は App Store から手動でインストールしてください"; return; }
  fi
  mas install "$app_id" 2>/dev/null && ok "$name installed" || ok "$name already installed"
}

# ------------------------------------------------------------------
# 全社員共通
# ------------------------------------------------------------------
install_common() {
  echo ""
  echo "========================================="
  echo " 全社員共通ツール"
  echo "========================================="
  echo ""

  install_cask "google-chrome"
  install_cask "slack"
  install_cask "figma"
  install_cask "raycast"
  install_cask "google-japanese-ime"
  install_mas_app "RunCat" 1429033973

  # nani (翻訳ツール) - ブラウザベースのためブックマークを開く
  info "Opening nani (translation tool) in browser..."
  open "https://nani.now/ja"
  ok "nani: bookmark https://nani.now/ja in your browser"

  echo ""
  warn "Google 日本語入力はインストール後に手動で有効化が必要です"
  warn "  システム設定 > キーボード > 入力ソース > 編集 > + > Google"
}

# ------------------------------------------------------------------
# 開発ツール
# ------------------------------------------------------------------
install_dev() {
  echo ""
  echo "========================================="
  echo " 開発ツール"
  echo "========================================="
  echo ""

  install_cask "cursor"
  install_cask "orbstack"
  install_cask "postman"
  install_cask "tableplus"
  install_formula "gh"

  # Xcode Command Line Tools
  if xcode-select -p &>/dev/null; then
    ok "Xcode Command Line Tools already installed"
  else
    info "Installing Xcode Command Line Tools..."
    xcode-select --install 2>/dev/null || true
    warn "Xcode のインストールダイアログが表示されたら承認してください"
    warn "完了後にこのスクリプトを再実行してください"
    return
  fi

  # Xcode 本体 (App Store)
  if [ -d "/Applications/Xcode.app" ]; then
    ok "Xcode.app already installed"
  else
    install_mas_app "Xcode" 497799835
  fi
}

# ------------------------------------------------------------------
# mise (ランタイムマネージャー)
# ------------------------------------------------------------------
setup_mise() {
  echo ""
  echo "========================================="
  echo " mise (Node.js / pnpm)"
  echo "========================================="
  echo ""

  if command -v mise &>/dev/null; then
    ok "mise already installed"
  else
    info "Installing mise..."
    curl https://mise.run | sh

    # ~/.zshrc に mise activate を追加
    local mise_bin="$HOME/.local/bin/mise"
    if [[ -x "$mise_bin" ]] && ! grep -q "mise activate" "$HOME/.zshrc" 2>/dev/null; then
      echo "eval \"\$(${mise_bin} activate zsh)\"" >> "$HOME/.zshrc"
      ok "mise activate added to ~/.zshrc"
    fi

    # 現在のセッションでも使えるようにする
    eval "$("$mise_bin" activate zsh)"
    ok "mise installed"
  fi

  # Node.js と pnpm をグローバル設定
  info "Setting up Node.js (LTS) and pnpm..."
  mise use --global node@lts
  mise use --global pnpm@latest
  ok "Node.js $(node -v) installed"
  ok "pnpm $(pnpm -v) installed"
}

# ------------------------------------------------------------------
# Git 初期設定 (対話形式)
# ------------------------------------------------------------------
setup_git() {
  echo ""
  echo "========================================="
  echo " Git 初期設定"
  echo "========================================="
  echo ""

  # git インストール (Homebrew 版)
  install_formula "git"

  # 既存の設定を確認
  local current_name current_email
  current_name=$(git config --global user.name 2>/dev/null || echo "")
  current_email=$(git config --global user.email 2>/dev/null || echo "")

  if [[ -n "$current_name" && -n "$current_email" ]]; then
    ok "Git user: ${current_name} <${current_email}>"
    if ! confirm "Git の設定を変更しますか?"; then
      return
    fi
  fi

  local git_name git_email

  ask "Git user.name (表示名)" git_name "$current_name"
  ask "Git user.email" git_email "$current_email"

  if [[ -z "$git_name" || -z "$git_email" ]]; then
    warn "名前またはメールが空のため、Git 設定をスキップしました"
    return
  fi

  git config --global user.name "$git_name"
  git config --global user.email "$git_email"
  ok "Git configured: ${git_name} <${git_email}>"
}

# ------------------------------------------------------------------
# Shell alias 設定
# ------------------------------------------------------------------
setup_aliases() {
  echo ""
  echo "========================================="
  echo " Shell alias 設定"
  echo "========================================="
  echo ""

  local zshrc="$HOME/.zshrc"
  local marker="# --- nichicoma aliases ---"

  # 既に設定済みならスキップ確認
  if grep -q "$marker" "$zshrc" 2>/dev/null; then
    ok "Aliases already configured in ~/.zshrc"
    if ! confirm "alias 設定を上書きしますか?"; then
      return
    fi
    # 既存ブロックを削除
    sed -i '' "/${marker}/,/# --- end nichicoma aliases ---/d" "$zshrc"
  fi

  cat >> "$zshrc" << 'ALIASES'

# --- nichicoma aliases ---

# turbo
alias cac='cd apps/client'
alias caa='cd apps/admin'
alias cau='cd apps/user'
alias cas='cd apps/server'
alias cpb='cd packages/ui'
alias cpr='cd packages/react-modules'
alias cput='cd packages/utils'
alias cpu='cd packages/ui'

# prisma
alias ppmr='pnpm prisma migrate reset -f'
alias ppg='pnpm prisma generate'
alias ppmd='pnpm prisma migrate dev'

# aspida
alias pba='pnpm build:api'
alias pga='pnpm generate:api'

# ls
alias ls='ls -G'
alias ll='ls -l'
alias la='ls -a'
alias l='clear && ls'

# cd
alias ..='cd ..'
alias ...='cd ../..'
alias ....='cd ../../..'

# git
alias g='git'
alias ga='git add'
alias gd='git diff'
alias gs='git status'
alias gp='git push'
alias gb='git branch'
alias gst='git status'
alias gss='git stash save'
alias gco='git checkout'
alias gf='git fetch'
alias gc='git commit -m'
alias gcpa='git cherry-pick --abort'
alias grm='git rebase master'
alias grc='git rebase --continue'
alias gpfh='git push --force-with-lease origin HEAD'
alias gdb='git branch | grep -v "develop" | grep -v "staging" | grep -v "master" | grep -v "main" | xargs git branch -D'
alias grhm='git reset --hard origin/main'
alias grhd='git reset --hard origin/develop'
alias grh='git reset --hard'
alias gswitch='gh auth switch && gh auth setup-git'

# pnpm
alias pn='pnpm'
alias pd='pnpm dev'
alias pda='pnpm dev:apps'
alias pdp='pnpm dev:packages'
alias pdf='pnpm dev:frontend'
alias pds='pnpm dev:server'
alias pa='pnpm add'
alias pf='pnpm --filter'
alias pul='pnpm up -L -i'
alias pr='pnpm remove'
alias pc='pnpm run check'
alias pb='pnpm build'
alias pbp='pnpm build:packages'
alias ps='pnpm serve'
alias pl='pnpm lint'
alias pct='pnpm check-types'
alias ptc='pnpm types:check'
alias pt='pnpm test'

# 1文字
alias m='mkdir'
alias o='open'
alias p='pnpm install'

# ユーティリティ
alias cpcd='pwd | tr -d "\n" | pbcopy'
alias config='code ~/.zshrc'
alias gconfig="code ~/Library/'Application Support'/com.mitchellh.ghostty/config"
alias sshconfig='code ~/.ssh/config'
alias gitconfig='code ~/.gitconfig'
alias reload='source ~/.zshrc'

# ポート番号でプロセスを kill
function killport() { lsof -i -P | grep "$1" | awk '{print $2}' | xargs kill -9; }
alias kp='killport'

# PostgreSQL
alias rm-pid='rm -f /usr/local/var/postgres/postmaster.pid'

# --- end nichicoma aliases ---
ALIASES

  ok "Aliases added to ~/.zshrc"
}

# ------------------------------------------------------------------
# メイン
# ------------------------------------------------------------------
select_role() {
  echo ""
  echo "========================================="
  echo " macOS Setup Script"
  echo "========================================="
  echo ""
  echo "  あなたの役割を選んでください"
  echo ""
  echo "  1) エンジニア (全社員共通 + 開発ツール)"
  echo "  2) エンジニア以外 (全社員共通のみ)"
  echo ""

  local choice
  while true; do
    read -rp "$(echo -e "${CYAN}[?]${NC} 番号を入力 (1/2): ")" choice
    case "$choice" in
      1) echo "engineer"; return ;;
      2) echo "non-engineer"; return ;;
      *) warn "1 または 2 を入力してください" ;;
    esac
  done
}

main() {
  # 引数があればそのまま使う、なければ対話で選択
  local role
  if [[ "${1:-}" == "--dev" || "${1:-}" == "--all" ]]; then
    role="engineer"
  elif [[ "${1:-}" == "--common" ]]; then
    role="non-engineer"
  else
    role=$(select_role)
  fi

  install_homebrew
  install_common
  setup_aliases

  if [[ "$role" == "engineer" ]]; then
    install_dev
    setup_mise
    setup_git
  fi

  echo ""
  echo "========================================="
  echo -e " ${GREEN}Setup complete!${NC}"
  echo "========================================="
  echo ""
  warn "変更を反映するためにターミナルを再起動してください"
  warn "  exec zsh"
}

main "$@"
