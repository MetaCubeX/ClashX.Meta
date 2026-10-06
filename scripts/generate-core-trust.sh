#!/bin/bash
set -euo pipefail

archive="$1"
output="$2"

if [[ "$output" == */ ]] || [ -L "$output" ] || { [ -e "$output" ] && [ ! -f "$output" ]; }; then
    echo "error: Bundled core trust output must be a regular file path." >&2
    exit 1
fi

if [ ! -f "$archive" ]; then
    echo "error: Missing bundled core archive. Prepare the bundled core before building." >&2
    exit 1
fi

# Hash the executable after all build-time transformations, not the gzip container.
digest=$(/usr/bin/gzip -dc "$archive" | /usr/bin/shasum -a 256)
digest=${digest%% *}
if [[ ! "$digest" =~ ^[0-9a-f]{64}$ ]]; then
    echo "error: Unable to generate the bundled core trust manifest." >&2
    exit 1
fi

output_directory=$(/usr/bin/dirname "$output")
/bin/mkdir -p "$output_directory"
# Xcode permits temporary files in TEMP_DIR but only declared files in
# DERIVED_FILE_DIR. Keep staging on the output filesystem for an atomic rename.
temporary_directory="${3:-$output_directory}"
if [ ! -d "$temporary_directory" ] || \
    [ "$(/usr/bin/stat -L -f %d "$temporary_directory")" != "$(/usr/bin/stat -L -f %d "$output_directory")" ]; then
    echo "error: Core trust staging directory must exist on the output filesystem." >&2
    exit 1
fi
temporary=$(/usr/bin/mktemp "$temporary_directory/$(/usr/bin/basename "$output").XXXXXX")
trap '/bin/rm -f "$temporary"' EXIT
printf 'enum BundledCoreTrust {\n    static let sha256 = "%s"\n}\n' "$digest" > "$temporary"
if [ ! -f "$output" ] || ! /usr/bin/cmp -s "$temporary" "$output"; then
    /bin/mv -f "$temporary" "$output"
fi
