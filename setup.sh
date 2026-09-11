#!/usr/bin/env bash
# setup.sh — Installation du workspace infra Nina.fm sur une nouvelle machine
# Usage: bash setup.sh

set -e

echo "🎛️  Nina.fm Infra Workspace Setup"
echo "================================"

WORKSPACE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ── 1. Vérifications préalables ─────────────────────────────────────
# Les repos d'infra n'ont pas de package.json : ni node ni pnpm ne sont
# nécessaires. GitHub passe par le CLI gh (pas de serveur MCP).
echo ""
echo "📋 Vérification des prérequis..."

command -v git >/dev/null 2>&1 || { echo "❌ git requis"; exit 1; }
command -v gh >/dev/null 2>&1 || { echo "❌ gh requis (https://cli.github.com)"; exit 1; }

echo "✅ git, gh détectés"

# ── 2. Clonage des repos ────────────────────────────────────────────
echo ""
echo "📦 Clonage des repos..."

REPOS=(
  "nina.fm-backup"
  "nina.fm-broadcast"
  "nina.fm-webserver"
)

for repo in "${REPOS[@]}"; do
  if [ -d "$WORKSPACE_DIR/$repo" ]; then
    echo "  ↩️  $repo déjà présent — skip"
  else
    echo "  ⬇️  Clonage de $repo..."
    git clone "git@github.com:nina-fm/$repo.git" "$WORKSPACE_DIR/$repo"
  fi
done

# ── 3. Authentification GitHub ──────────────────────────────────────
echo ""
echo "🔑 CLI GitHub (PRs, merges, issues)"
if gh auth status >/dev/null 2>&1; then
  echo "  ✅ gh authentifié"
else
  echo "  ⚠️  gh non authentifié → gh auth login"
fi

echo ""
echo "================================"
echo "✅ Setup terminé !"
echo ""
echo "Les secrets de déploiement vivent dans les GitHub Secrets de chaque repo :"
echo "aucun .env n'est nécessaire pour travailler sur l'infra."
