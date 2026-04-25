#!/bin/bash
INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path')
if [[ "$FILE_PATH" == *.swift ]] && command -v swiftformat &>/dev/null; then
  swiftformat "$FILE_PATH" --quiet 2>/dev/null || true
fi
exit 0
