#!/usr/bin/env bash
# setup.sh — Installation du workspace infra Nina.fm sur une nouvelle machine
# Usage: bash setup.sh

set -e

echo "🎛️  Nina.fm Infra Workspace Setup"
echo "================================"

WORKSPACE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ── 1. Vérifications préalables ─────────────────────────────────────
echo ""
echo "📋 Vérification des prérequis..."

command -v git >/dev/null 2>&1 || { echo "❌ git requis"; exit 1; }
command -v node >/dev/null 2>&1 || { echo "❌ node requis (recommandé: via nvm)"; exit 1; }
command -v pnpm >/dev/null 2>&1 || { echo "❌ pnpm requis (npm install -g pnpm)"; exit 1; }

echo "✅ git, node, pnpm détectés"

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

# ── 3. Variables d'environnement ────────────────────────────────────
echo ""
echo "⚙️  Variables d'environnement..."

for repo in "${REPOS[@]}"; do
  env_example="$WORKSPACE_DIR/$repo/.env.example"
  env_file="$WORKSPACE_DIR/$repo/.env"
  if [ -f "$env_example" ] && [ ! -f "$env_file" ]; then
    cp "$env_example" "$env_file"
    echo "  📄 $repo/.env créé depuis .env.example — à compléter !"
  fi
done

# ── 4. GitHub Token ─────────────────────────────────────────────────
echo ""
echo "🔑 GitHub Personal Access Token (MCP GitHub)"
if [ -z "$GITHUB_PERSONAL_ACCESS_TOKEN" ]; then
  echo "  ⚠️  GITHUB_PERSONAL_ACCESS_TOKEN non défini"
  echo "  → Ajouter dans ~/.zshrc : export GITHUB_PERSONAL_ACCESS_TOKEN=ghp_xxxx"
  echo "  → Token requis pour le MCP GitHub (branches, PRs automatiques)"
else
  echo "  ✅ GITHUB_PERSONAL_ACCESS_TOKEN défini"
fi

# ── 5. MCPs ─────────────────────────────────────────────────────────
echo ""
echo "🔌 MCPs (Model Context Protocol)..."
echo "  → Les MCPs seront installés automatiquement par Claude Code via npx"
echo "  → Config dans: $WORKSPACE_DIR/.mcp.json"

# ── 6. Git hooks (commitlint + lint-staged) ─────────────────────────
echo ""
echo "🪝 Git hooks..."
for repo in "${REPOS[@]}"; do
  if [ -f "$WORKSPACE_DIR/$repo/package.json" ]; then
    if grep -q '"husky"' "$WORKSPACE_DIR/$repo/package.json" 2>/dev/null; then
      echo "  → Husky dans $repo..."
      (cd "$WORKSPACE_DIR/$repo" && pnpm husky install 2>/dev/null || true)
    fi
  fi
done

echo ""
echo "================================"
echo "✅ Setup terminé !"
echo ""
echo "Prochaines étapes manuelles :"
echo "  1. Compléter les fichiers .env dans chaque repo"
echo "  2. Configurer GITHUB_PERSONAL_ACCESS_TOKEN dans ~/.zshrc"
echo "  3. Lancer Nginx : voir nina.fm-webserver/docker-compose.yml"
echo "  4. Lancer Libretime : voir nina.fm-broadcast/libretime/docker-compose.yml"
echo "  5. Lancer Icecast : voir nina.fm-broadcast/icecast/docker-compose.yml"
