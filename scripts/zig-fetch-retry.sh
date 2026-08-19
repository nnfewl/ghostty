set -uo pipefail

# Resolve the Zig dependency tree up front, with retries.
#
# Zig pulls some dependencies straight from GitHub over git+https (e.g.
# pkg/wuffs -> google/wuffs-mirror-release-c). Hosted runners intermittently
# get the connection closed mid-negotiation:
#
#   pkg/wuffs/build.zig.zon:14:20: error: unable to discover remote git
#   server capabilities: HttpConnectionClosing
#
# A single blip there kills an otherwise-good build after several minutes of
# compiling. Fetching separately means we retry only the flaky network step;
# the build that follows then runs against a warm cache.
#
# --fetch=all is deliberate: wuffs is declared `.lazy = true`, so the default
# (`needed`) would defer it back into the build step we are protecting.

ATTEMPTS="${ZIG_FETCH_ATTEMPTS:-5}"
BACKOFF="${ZIG_FETCH_BACKOFF:-20}"

for attempt in $(seq 1 "$ATTEMPTS"); do
  if nix develop -c zig build --fetch=all; then
    echo "Dependencies fetched on attempt ${attempt}/${ATTEMPTS}"
    exit 0
  fi

  if [ "$attempt" -lt "$ATTEMPTS" ]; then
    delay=$((attempt * BACKOFF))
    echo "Fetch attempt ${attempt}/${ATTEMPTS} failed — retrying in ${delay}s" >&2
    sleep "$delay"
  fi
done

echo "ERROR: zig dependency fetch failed after ${ATTEMPTS} attempts" >&2
exit 1
