#!/bin/bash
# Reset database script for development
# This script drops the database, recreates it, runs migrations, and seeds it

set -e

# Load environment variables if .env file exists
if [ -f .env ]; then
  set -a
  source .env
  set +a
fi

echo "🔄 Resetting database..."

# Check if Mix is available
if ! command -v mix &> /dev/null; then
  echo "❌ Error: Mix is not available. This script requires Mix for development."
  exit 1
fi

# Reset the database using Mix
mix ecto.reset

echo "✅ Database reset complete!"
echo ""
echo "The database has been:"
echo "  - Dropped"
echo "  - Recreated"
echo "  - Migrated"
echo "  - Seeded (if seeds.exs exists)"
