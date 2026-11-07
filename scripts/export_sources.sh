#!/bin/zsh
set -e
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
EXPORT_FILE="$ROOT_DIR/FULL_SOURCE_EXPORT.md"

echo "# Pełny Kod Źródłowy Aplikacji Breeze (Apple Silicon Fan Control)" > "$EXPORT_FILE"
echo "Wygenerowano dla celów audytu i skanowania kodu przez zewnętrznego agenta." >> "$EXPORT_FILE"
echo "" >> "$EXPORT_FILE"

find "$ROOT_DIR/Sources" -type f -name "*.swift" | sort | while read -r file; do
    rel="${file#$ROOT_DIR/}"
    echo "---" >> "$EXPORT_FILE"
    echo "## Plik: \`$rel\`" >> "$EXPORT_FILE"
    echo '```swift' >> "$EXPORT_FILE"
    cat "$file" >> "$EXPORT_FILE"
    echo '```' >> "$EXPORT_FILE"
    echo "" >> "$EXPORT_FILE"
done

for script in "$ROOT_DIR/scripts"/*.sh "$ROOT_DIR/scripts"/*.swift; do
    rel="${script#$ROOT_DIR/}"
    echo "---" >> "$EXPORT_FILE"
    echo "## Skrypt: \`$rel\`" >> "$EXPORT_FILE"
    echo '```bash' >> "$EXPORT_FILE"
    cat "$script" >> "$EXPORT_FILE"
    echo '```' >> "$EXPORT_FILE"
    echo "" >> "$EXPORT_FILE"
done

echo "Plik eksportu gotowy: $EXPORT_FILE"
