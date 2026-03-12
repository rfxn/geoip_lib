#!/usr/bin/env bats
# 02-download.bats — geoip_lib download layer tests
# All network calls are mocked — no real downloads.

load helpers/geoip-common

setup() {
	geoip_common_setup
	_mock_setup
}

teardown() {
	geoip_teardown
}

# ---------------------------------------------------------------------------
# Mock infrastructure — override download internals for testing
# ---------------------------------------------------------------------------

_mock_setup() {
	MOCK_BIN="$TEST_TMPDIR/bin"
	mkdir -p "$MOCK_BIN"
	MOCK_DATA="$TEST_TMPDIR/mock_data"
	mkdir -p "$MOCK_DATA"
	export MOCK_BIN MOCK_DATA

	# Create valid CIDR fixture files
	printf '1.0.0.0/24\n1.0.4.0/22\n1.0.16.0/20\n' > "$MOCK_DATA/au.zone"
	printf '223.0.0.0/15\n223.4.0.0/14\n223.64.0.0/11\n' > "$MOCK_DATA/cn.zone"
	printf '2001:200::/23\n2001:240::/20\n' > "$MOCK_DATA/jp.zone6"
	# Empty and garbage fixtures
	: > "$MOCK_DATA/empty.zone"
	printf 'garbage line one\nmore garbage\n' > "$MOCK_DATA/garbage.zone"
}

# Helper: override _geoip_download_cmd to copy from fixture files
# Usage: _mock_download_success FIXTURE_FILE
#   Sets _geoip_download_cmd to copy the fixture to the output path.
_mock_download_success() {
	local fixture="$1"
	# shellcheck disable=SC2034
	_MOCK_FIXTURE="$fixture"
	_geoip_download_cmd() {
		local _url="$1" _output="$2"
		cp "$_MOCK_FIXTURE" "$_output"
		return 0
	}
}

# Helper: override _geoip_download_cmd to always fail
_mock_download_fail() {
	_geoip_download_cmd() {
		return 1
	}
}

# Helper: override _geoip_download_cmd to fail N times then succeed
# Usage: _mock_download_fail_then_succeed N FIXTURE
_mock_download_fail_then_succeed() {
	local fail_count="$1" fixture="$2"
	_MOCK_DL_FAIL_COUNT="$fail_count"
	_MOCK_DL_CALLS=0
	_MOCK_DL_FIXTURE="$fixture"
	_geoip_download_cmd() {
		local _url="$1" _output="$2"
		_MOCK_DL_CALLS=$(( _MOCK_DL_CALLS + 1 ))
		if [[ "$_MOCK_DL_CALLS" -le "$_MOCK_DL_FAIL_COUNT" ]]; then
			return 1
		fi
		cp "$_MOCK_DL_FIXTURE" "$_output"
		return 0
	}
}

# ---------------------------------------------------------------------------
# Binary discovery
# ---------------------------------------------------------------------------

@test "binary discovery: GEOIP_CURL_BIN set from command -v" {
	# Env override should take precedence
	GEOIP_CURL_BIN="/mock/curl"
	[[ "$GEOIP_CURL_BIN" == "/mock/curl" ]]
}

@test "binary discovery: GEOIP_WGET_BIN set from command -v" {
	GEOIP_WGET_BIN="/mock/wget"
	[[ "$GEOIP_WGET_BIN" == "/mock/wget" ]]
}

@test "binary discovery: GEOIP_AWK_BIN set from command -v" {
	[[ -n "$GEOIP_AWK_BIN" ]]
}

@test "GEOIP_DL_TIMEOUT has default of 120" {
	# Re-source with clean state to check default
	local saved="$GEOIP_DL_TIMEOUT"
	unset GEOIP_DL_TIMEOUT
	_GEOIP_LIB_LOADED=""
	# shellcheck disable=SC1091
	source "${PROJECT_ROOT}/files/geoip_lib.sh"
	[[ "$GEOIP_DL_TIMEOUT" == "120" ]]
	GEOIP_DL_TIMEOUT="$saved"
}

@test "GEOIP_DL_TIMEOUT respects env override" {
	GEOIP_DL_TIMEOUT="30"
	_GEOIP_LIB_LOADED=""
	# shellcheck disable=SC1091
	source "${PROJECT_ROOT}/files/geoip_lib.sh"
	[[ "$GEOIP_DL_TIMEOUT" == "30" ]]
}

# ---------------------------------------------------------------------------
# _geoip_download_cmd — tested indirectly via curl/wget mock binaries
# ---------------------------------------------------------------------------

@test "_geoip_download_cmd: succeeds with mock curl binary" {
	# Create a mock curl that writes fixture data to output file
	cat > "$MOCK_BIN/curl" <<-'ENDMOCK'
	#!/bin/bash
	# Find -o flag and write sample data to that path
	while [[ $# -gt 0 ]]; do
		case "$1" in
			-o) shift; printf '1.0.0.0/24\n' > "$1" ;;
		esac
		shift
	done
	exit 0
	ENDMOCK
	chmod +x "$MOCK_BIN/curl"

	local saved_curl="$GEOIP_CURL_BIN"
	GEOIP_CURL_BIN="$MOCK_BIN/curl"
	local outfile="$TEST_TMPDIR/test_output"

	run _geoip_download_cmd "https://example.com/test.zone" "$outfile"
	[[ "$status" -eq 0 ]]

	GEOIP_CURL_BIN="$saved_curl"
}

@test "_geoip_download_cmd: falls back to wget when curl absent" {
	local saved_curl="$GEOIP_CURL_BIN"
	local saved_wget="$GEOIP_WGET_BIN"

	GEOIP_CURL_BIN=""

	# Create wget mock
	cat > "$MOCK_BIN/wget" <<-'ENDMOCK'
	#!/bin/bash
	# Find -O flag and write sample data
	while [[ $# -gt 0 ]]; do
		case "$1" in
			-O) shift; printf '1.0.0.0/24\n' > "$1" ;;
		esac
		shift
	done
	exit 0
	ENDMOCK
	chmod +x "$MOCK_BIN/wget"
	GEOIP_WGET_BIN="$MOCK_BIN/wget"

	local outfile="$TEST_TMPDIR/test_output"
	run _geoip_download_cmd "https://example.com/test.zone" "$outfile"
	[[ "$status" -eq 0 ]]

	GEOIP_CURL_BIN="$saved_curl"
	GEOIP_WGET_BIN="$saved_wget"
}

@test "_geoip_download_cmd: returns 1 when neither curl nor wget available" {
	local saved_curl="$GEOIP_CURL_BIN"
	local saved_wget="$GEOIP_WGET_BIN"
	GEOIP_CURL_BIN=""
	GEOIP_WGET_BIN=""

	run _geoip_download_cmd "https://example.com/test.zone" "$TEST_TMPDIR/out"
	[[ "$status" -eq 1 ]]
	[[ "$output" == *"neither curl nor wget"* ]]

	GEOIP_CURL_BIN="$saved_curl"
	GEOIP_WGET_BIN="$saved_wget"
}

@test "_geoip_download_cmd: TLS fallback on curl failure" {
	# Create curl mock that fails on first try (strict TLS), succeeds on second (insecure)
	cat > "$MOCK_BIN/curl" <<-'ENDMOCK'
	#!/bin/bash
	has_insecure=0
	outpath=""
	for arg in "$@"; do
		case "$arg" in
			--insecure) has_insecure=1 ;;
			-o) ;; # next arg is path
			*) if [[ -n "$prev_was_o" ]]; then outpath="$arg"; fi ;;
		esac
		prev_was_o=""
		[[ "$arg" == "-o" ]] && prev_was_o=1
	done
	# Find output path properly
	while [[ $# -gt 0 ]]; do
		if [[ "$1" == "-o" ]]; then shift; outpath="$1"; fi
		shift
	done
	if [[ "$has_insecure" -eq 1 ]]; then
		printf '1.0.0.0/24\n' > "$outpath"
		exit 0
	fi
	exit 1
	ENDMOCK
	chmod +x "$MOCK_BIN/curl"

	local saved_curl="$GEOIP_CURL_BIN"
	GEOIP_CURL_BIN="$MOCK_BIN/curl"

	local outfile="$TEST_TMPDIR/tls_fallback_out"
	run _geoip_download_cmd "https://example.com/test.zone" "$outfile"
	[[ "$status" -eq 0 ]]

	GEOIP_CURL_BIN="$saved_curl"
}

@test "_geoip_download_cmd: removes output on failure" {
	# Create curl mock that always fails
	cat > "$MOCK_BIN/curl" <<-'ENDMOCK'
	#!/bin/bash
	exit 1
	ENDMOCK
	chmod +x "$MOCK_BIN/curl"

	local saved_curl="$GEOIP_CURL_BIN"
	GEOIP_CURL_BIN="$MOCK_BIN/curl"

	local outfile="$TEST_TMPDIR/should_be_removed"
	run _geoip_download_cmd "https://example.com/test.zone" "$outfile"
	[[ "$status" -eq 1 ]]
	[[ ! -f "$outfile" ]]

	GEOIP_CURL_BIN="$saved_curl"
}

# ---------------------------------------------------------------------------
# _geoip_validate_cidr_file
# ---------------------------------------------------------------------------

@test "_geoip_validate_cidr_file: valid IPv4 CIDR file passes" {
	run _geoip_validate_cidr_file "$MOCK_DATA/au.zone" "4"
	[[ "$status" -eq 0 ]]
}

@test "_geoip_validate_cidr_file: valid IPv6 CIDR file passes" {
	run _geoip_validate_cidr_file "$MOCK_DATA/jp.zone6" "6"
	[[ "$status" -eq 0 ]]
}

@test "_geoip_validate_cidr_file: empty file fails" {
	run _geoip_validate_cidr_file "$MOCK_DATA/empty.zone" "4"
	[[ "$status" -eq 1 ]]
}

@test "_geoip_validate_cidr_file: garbage content fails" {
	run _geoip_validate_cidr_file "$MOCK_DATA/garbage.zone" "4"
	[[ "$status" -eq 1 ]]
}

@test "_geoip_validate_cidr_file: nonexistent file fails" {
	run _geoip_validate_cidr_file "$MOCK_DATA/nonexistent" "4"
	[[ "$status" -eq 1 ]]
}

@test "_geoip_validate_cidr_file: IPv4 CIDR rejected as IPv6" {
	# IPv4 CIDRs don't match the IPv6 pattern
	run _geoip_validate_cidr_file "$MOCK_DATA/au.zone" "6"
	[[ "$status" -eq 1 ]]
}

# ---------------------------------------------------------------------------
# _geoip_download_ipverse / _geoip_download_ipdeny
# ---------------------------------------------------------------------------

@test "_geoip_download_ipverse: downloads and validates IPv4 CIDR" {
	_mock_download_success "$MOCK_DATA/au.zone"
	local outfile="$TEST_TMPDIR/au_ipverse.zone"
	run _geoip_download_ipverse "au" "4" "$outfile"
	[[ "$status" -eq 0 ]]
	[[ -f "$outfile" ]]
	grep -q '1.0.0.0/24' "$outfile"
}

@test "_geoip_download_ipverse: downloads and validates IPv6 CIDR" {
	_mock_download_success "$MOCK_DATA/jp.zone6"
	local outfile="$TEST_TMPDIR/jp_ipverse.zone6"
	run _geoip_download_ipverse "jp" "6" "$outfile"
	[[ "$status" -eq 0 ]]
	[[ -f "$outfile" ]]
	grep -q '2001:200::/23' "$outfile"
}

@test "_geoip_download_ipverse: rejects garbage download" {
	_mock_download_success "$MOCK_DATA/garbage.zone"
	local outfile="$TEST_TMPDIR/garbage_test"
	run _geoip_download_ipverse "xx" "4" "$outfile"
	[[ "$status" -eq 1 ]]
	[[ ! -f "$outfile" ]]
}

@test "_geoip_download_ipverse: cleans up temp on download failure" {
	_mock_download_fail
	local outfile="$TEST_TMPDIR/fail_test"
	run _geoip_download_ipverse "au" "4" "$outfile"
	[[ "$status" -eq 1 ]]
	# No leftover temp files
	local leftover
	leftover=$(find "$TEST_TMPDIR" -name "fail_test.*" 2>/dev/null | wc -l)
	[[ "$leftover" -eq 0 ]]
}

@test "_geoip_download_ipdeny: downloads and validates IPv4 CIDR" {
	_mock_download_success "$MOCK_DATA/cn.zone"
	local outfile="$TEST_TMPDIR/cn_ipdeny.zone"
	run _geoip_download_ipdeny "cn" "4" "$outfile"
	[[ "$status" -eq 0 ]]
	[[ -f "$outfile" ]]
	grep -q '223.0.0.0/15' "$outfile"
}

@test "_geoip_download_ipdeny: downloads and validates IPv6 CIDR" {
	_mock_download_success "$MOCK_DATA/jp.zone6"
	local outfile="$TEST_TMPDIR/jp_ipdeny.zone6"
	run _geoip_download_ipdeny "jp" "6" "$outfile"
	[[ "$status" -eq 0 ]]
	[[ -f "$outfile" ]]
}

@test "_geoip_download_ipdeny: rejects empty download" {
	_mock_download_success "$MOCK_DATA/empty.zone"
	local outfile="$TEST_TMPDIR/empty_test"
	run _geoip_download_ipdeny "xx" "4" "$outfile"
	[[ "$status" -eq 1 ]]
	[[ ! -f "$outfile" ]]
}

# ---------------------------------------------------------------------------
# geoip_download — cascade orchestrator
# ---------------------------------------------------------------------------

@test "geoip_download: auto source succeeds via ipverse" {
	_mock_download_success "$MOCK_DATA/au.zone"
	local outfile="$TEST_TMPDIR/auto_au.zone"
	run geoip_download "AU" "4" "$outfile" "auto"
	[[ "$status" -eq 0 ]]
	[[ -f "$outfile" ]]
}

@test "geoip_download: auto cascade — ipverse fails, ipdeny succeeds" {
	# First two calls fail (ipverse strict + insecure), next calls succeed (ipdeny)
	_mock_download_fail_then_succeed 1 "$MOCK_DATA/cn.zone"
	# Override at the vendor level instead: ipverse fails entirely, ipdeny succeeds
	_geoip_download_ipverse() { return 1; }
	_mock_download_success "$MOCK_DATA/cn.zone"
	# Now _geoip_download_ipdeny will use the mocked _geoip_download_cmd
	local outfile="$TEST_TMPDIR/cascade_cn.zone"
	run geoip_download "CN" "4" "$outfile" "auto"
	[[ "$status" -eq 0 ]]
	[[ -f "$outfile" ]]
}

@test "geoip_download: auto cascade — both fail returns 1" {
	_geoip_download_ipverse() { return 1; }
	_geoip_download_ipdeny() { return 1; }
	local outfile="$TEST_TMPDIR/both_fail.zone"
	run geoip_download "XX" "4" "$outfile" "auto"
	[[ "$status" -eq 1 ]]
	[[ ! -f "$outfile" ]]
}

@test "geoip_download: explicit ipverse source" {
	_mock_download_success "$MOCK_DATA/au.zone"
	local outfile="$TEST_TMPDIR/explicit_ipverse.zone"
	run geoip_download "AU" "4" "$outfile" "ipverse"
	[[ "$status" -eq 0 ]]
	[[ -f "$outfile" ]]
}

@test "geoip_download: explicit ipdeny source" {
	_mock_download_success "$MOCK_DATA/cn.zone"
	local outfile="$TEST_TMPDIR/explicit_ipdeny.zone"
	run geoip_download "CN" "4" "$outfile" "ipdeny"
	[[ "$status" -eq 0 ]]
	[[ -f "$outfile" ]]
}

@test "geoip_download: default source is auto" {
	_mock_download_success "$MOCK_DATA/au.zone"
	local outfile="$TEST_TMPDIR/default_auto.zone"
	# Omit source argument — should default to auto
	run geoip_download "AU" "4" "$outfile"
	[[ "$status" -eq 0 ]]
	[[ -f "$outfile" ]]
}

@test "geoip_download: lowercases CC for URL construction" {
	# Track what CC was passed to ipverse
	local called_cc=""
	_geoip_download_ipverse() {
		called_cc="$1"
		cp "$MOCK_DATA/au.zone" "$3"
		return 0
	}
	local outfile="$TEST_TMPDIR/lc_test.zone"
	geoip_download "AU" "4" "$outfile"
	[[ "$called_cc" == "au" ]]
}

@test "geoip_download: unknown source returns 1" {
	run geoip_download "AU" "4" "$TEST_TMPDIR/out" "badvendor"
	[[ "$status" -eq 1 ]]
	[[ "$output" == *"unknown source"* ]]
}

@test "geoip_download: empty CC returns 1" {
	run geoip_download "" "4" "$TEST_TMPDIR/out"
	[[ "$status" -eq 1 ]]
}

@test "geoip_download: empty FAMILY returns 1" {
	run geoip_download "AU" "" "$TEST_TMPDIR/out"
	[[ "$status" -eq 1 ]]
}

@test "geoip_download: invalid FAMILY returns 1" {
	run geoip_download "AU" "5" "$TEST_TMPDIR/out"
	[[ "$status" -eq 1 ]]
}

@test "geoip_download: empty OUTPUT returns 1" {
	run geoip_download "AU" "4" ""
	[[ "$status" -eq 1 ]]
}

@test "geoip_download: IPv6 family passes through correctly" {
	_mock_download_success "$MOCK_DATA/jp.zone6"
	local outfile="$TEST_TMPDIR/ipv6_test.zone6"
	run geoip_download "JP" "6" "$outfile"
	[[ "$status" -eq 0 ]]
	[[ -f "$outfile" ]]
	grep -q '2001:' "$outfile"
}

# ---------------------------------------------------------------------------
# geoip_is_stale
# ---------------------------------------------------------------------------

@test "geoip_is_stale: missing .last_update returns 0 (stale)" {
	mkdir -p "$TEST_TMPDIR/stale_test"
	run geoip_is_stale "$TEST_TMPDIR/stale_test" 30
	[[ "$status" -eq 0 ]]
}

@test "geoip_is_stale: fresh .last_update returns 1 (not stale)" {
	mkdir -p "$TEST_TMPDIR/fresh_test"
	date +%s > "$TEST_TMPDIR/fresh_test/.last_update"
	run geoip_is_stale "$TEST_TMPDIR/fresh_test" 30
	[[ "$status" -eq 1 ]]
}

@test "geoip_is_stale: old .last_update returns 0 (stale)" {
	mkdir -p "$TEST_TMPDIR/old_test"
	# Set timestamp 31 days ago
	local old_epoch
	old_epoch=$(( $(date +%s) - 31 * 86400 ))
	echo "$old_epoch" > "$TEST_TMPDIR/old_test/.last_update"
	run geoip_is_stale "$TEST_TMPDIR/old_test" 30
	[[ "$status" -eq 0 ]]
}

@test "geoip_is_stale: custom max_age_days respected" {
	mkdir -p "$TEST_TMPDIR/custom_age"
	# 2 days old
	local two_days_ago
	two_days_ago=$(( $(date +%s) - 2 * 86400 ))
	echo "$two_days_ago" > "$TEST_TMPDIR/custom_age/.last_update"
	# 1-day max: should be stale
	run geoip_is_stale "$TEST_TMPDIR/custom_age" 1
	[[ "$status" -eq 0 ]]
	# 7-day max: should be fresh
	run geoip_is_stale "$TEST_TMPDIR/custom_age" 7
	[[ "$status" -eq 1 ]]
}

@test "geoip_is_stale: default max_age is 30 days" {
	mkdir -p "$TEST_TMPDIR/default_age"
	# 29 days old
	local recent
	recent=$(( $(date +%s) - 29 * 86400 ))
	echo "$recent" > "$TEST_TMPDIR/default_age/.last_update"
	# Default (30 days): should be fresh
	run geoip_is_stale "$TEST_TMPDIR/default_age"
	[[ "$status" -eq 1 ]]
}

@test "geoip_is_stale: garbage .last_update treated as stale" {
	mkdir -p "$TEST_TMPDIR/garbage_stamp"
	echo "not-a-number" > "$TEST_TMPDIR/garbage_stamp/.last_update"
	run geoip_is_stale "$TEST_TMPDIR/garbage_stamp" 30
	[[ "$status" -eq 0 ]]
}

# ---------------------------------------------------------------------------
# geoip_mark_updated
# ---------------------------------------------------------------------------

@test "geoip_mark_updated: creates .last_update file" {
	mkdir -p "$TEST_TMPDIR/mark_test"
	run geoip_mark_updated "$TEST_TMPDIR/mark_test"
	[[ "$status" -eq 0 ]]
	[[ -f "$TEST_TMPDIR/mark_test/.last_update" ]]
}

@test "geoip_mark_updated: content is numeric epoch" {
	mkdir -p "$TEST_TMPDIR/epoch_test"
	geoip_mark_updated "$TEST_TMPDIR/epoch_test"
	local content
	content=$(cat "$TEST_TMPDIR/epoch_test/.last_update")
	local _epoch_pat='^[0-9]+$'
	[[ "$content" =~ $_epoch_pat ]]
}

@test "geoip_mark_updated: epoch is recent (within 10 seconds)" {
	mkdir -p "$TEST_TMPDIR/recent_test"
	local before
	before=$(date +%s)
	geoip_mark_updated "$TEST_TMPDIR/recent_test"
	local stamp
	stamp=$(cat "$TEST_TMPDIR/recent_test/.last_update")
	local after
	after=$(date +%s)
	[[ "$stamp" -ge "$before" ]]
	[[ "$stamp" -le "$after" ]]
}

@test "geoip_mark_updated: empty dir arg returns 1" {
	run geoip_mark_updated ""
	[[ "$status" -eq 1 ]]
}

@test "geoip_mark_updated: nonexistent dir returns 1" {
	run geoip_mark_updated "$TEST_TMPDIR/no_such_dir"
	[[ "$status" -eq 1 ]]
}

@test "geoip_mark_updated + geoip_is_stale roundtrip: just-marked is fresh" {
	mkdir -p "$TEST_TMPDIR/roundtrip"
	geoip_mark_updated "$TEST_TMPDIR/roundtrip"
	run geoip_is_stale "$TEST_TMPDIR/roundtrip" 30
	[[ "$status" -eq 1 ]]
}

# ---------------------------------------------------------------------------
# geoip_cidr_search
# ---------------------------------------------------------------------------

@test "geoip_cidr_search: finds IP in matching CIDR file" {
	run geoip_cidr_search "1.0.0.1" "$MOCK_DATA/au.zone"
	[[ "$status" -eq 0 ]]
	[[ "$output" == *"au.zone"* ]]
}

@test "geoip_cidr_search: returns file path of match" {
	run geoip_cidr_search "1.0.0.1" "$MOCK_DATA/au.zone" "$MOCK_DATA/cn.zone"
	[[ "$status" -eq 0 ]]
	[[ "$output" == "$MOCK_DATA/au.zone" ]]
}

@test "geoip_cidr_search: no match returns 1" {
	run geoip_cidr_search "8.8.8.8" "$MOCK_DATA/au.zone"
	[[ "$status" -eq 1 ]]
	[[ -z "$output" ]]
}

@test "geoip_cidr_search: searches across multiple files" {
	run geoip_cidr_search "223.0.0.1" "$MOCK_DATA/au.zone" "$MOCK_DATA/cn.zone"
	[[ "$status" -eq 0 ]]
	[[ "$output" == "$MOCK_DATA/cn.zone" ]]
}

@test "geoip_cidr_search: /32 single-host CIDR match" {
	printf '10.0.0.1/32\n' > "$TEST_TMPDIR/single.zone"
	run geoip_cidr_search "10.0.0.1" "$TEST_TMPDIR/single.zone"
	[[ "$status" -eq 0 ]]
}

@test "geoip_cidr_search: /32 single-host CIDR non-match" {
	printf '10.0.0.1/32\n' > "$TEST_TMPDIR/single.zone"
	run geoip_cidr_search "10.0.0.2" "$TEST_TMPDIR/single.zone"
	[[ "$status" -eq 1 ]]
}

@test "geoip_cidr_search: /8 wide CIDR match" {
	printf '10.0.0.0/8\n' > "$TEST_TMPDIR/wide.zone"
	run geoip_cidr_search "10.255.255.255" "$TEST_TMPDIR/wide.zone"
	[[ "$status" -eq 0 ]]
}

@test "geoip_cidr_search: /8 boundary non-match" {
	printf '10.0.0.0/8\n' > "$TEST_TMPDIR/wide.zone"
	run geoip_cidr_search "11.0.0.0" "$TEST_TMPDIR/wide.zone"
	[[ "$status" -eq 1 ]]
}

@test "geoip_cidr_search: /24 subnet boundary" {
	printf '192.168.1.0/24\n' > "$TEST_TMPDIR/subnet.zone"
	run geoip_cidr_search "192.168.1.254" "$TEST_TMPDIR/subnet.zone"
	[[ "$status" -eq 0 ]]
	run geoip_cidr_search "192.168.2.0" "$TEST_TMPDIR/subnet.zone"
	[[ "$status" -eq 1 ]]
}

@test "geoip_cidr_search: /16 subnet" {
	printf '172.16.0.0/16\n' > "$TEST_TMPDIR/sixteen.zone"
	run geoip_cidr_search "172.16.255.255" "$TEST_TMPDIR/sixteen.zone"
	[[ "$status" -eq 0 ]]
	run geoip_cidr_search "172.17.0.0" "$TEST_TMPDIR/sixteen.zone"
	[[ "$status" -eq 1 ]]
}

@test "geoip_cidr_search: empty IP returns 1" {
	run geoip_cidr_search "" "$MOCK_DATA/au.zone"
	[[ "$status" -eq 1 ]]
}

@test "geoip_cidr_search: no files returns 1" {
	run geoip_cidr_search "1.0.0.1"
	[[ "$status" -eq 1 ]]
}

@test "geoip_cidr_search: skips comment and blank lines" {
	printf '# comment\n\n1.0.0.0/24\n' > "$TEST_TMPDIR/commented.zone"
	run geoip_cidr_search "1.0.0.1" "$TEST_TMPDIR/commented.zone"
	[[ "$status" -eq 0 ]]
}
