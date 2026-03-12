#!/bin/bash
# geoip-common.bash — shared BATS helper for geoip_lib tests
# Sources geoip_lib.sh and provides setup/teardown functions.

PROJECT_ROOT="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
export PROJECT_ROOT

# Source library under test
# shellcheck disable=SC1091
source "${PROJECT_ROOT}/files/geoip_lib.sh"

# Expected version from sourced library — tests use this instead of hardcoded strings
EXPECTED_VERSION="$GEOIP_LIB_VERSION"
export EXPECTED_VERSION

# Load bats-support and bats-assert if available
if [[ -d /usr/local/lib/bats/bats-support ]]; then
	# shellcheck disable=SC1091
	source /usr/local/lib/bats/bats-support/load.bash
	# shellcheck disable=SC1091
	source /usr/local/lib/bats/bats-assert/load.bash
fi

geoip_common_setup() {
	TEST_TMPDIR=$(mktemp -d)
	export TEST_TMPDIR

	# Reset source guard to allow re-sourcing for clean state
	_GEOIP_LIB_LOADED=""
	# shellcheck disable=SC1091
	source "${PROJECT_ROOT}/files/geoip_lib.sh"
}

geoip_teardown() {
	rm -rf "$TEST_TMPDIR"
}
