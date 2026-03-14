#!/usr/bin/env bats
# 04-ipv6.bats — geoip_lib IPv6 normalization, CIDR-to-range, lookup, and builder tests
# Tests: v6hex (via _GEOIP_V6_AWK), _geoip_cidr6_to_ranges, geoip_ip6_lookup,
#        geoip_build_ip6db

load helpers/geoip-common

setup() {
	geoip_common_setup
}

teardown() {
	geoip_teardown
}

# ---------------------------------------------------------------------------
# Test helper: invoke v6hex awk function directly
# ---------------------------------------------------------------------------

_test_v6hex() {
	"$GEOIP_AWK_BIN" -v ip="$1" "${_GEOIP_V6_AWK}"'
	BEGIN { result = v6hex(ip); if (result != "") print result; exit }'
}

# ---------------------------------------------------------------------------
# v6hex normalization
# ---------------------------------------------------------------------------

@test "v6hex: full form normalizes to 32 chars" {
	run _test_v6hex "2001:0db8:0000:0000:0000:0000:0000:0001"
	[[ "$status" -eq 0 ]]
	[[ "$output" == "20010db8000000000000000000000001" ]]
}

@test "v6hex: abbreviated 2001:db8::1 expands correctly" {
	run _test_v6hex "2001:db8::1"
	[[ "$status" -eq 0 ]]
	[[ "$output" == "20010db8000000000000000000000001" ]]
}

@test "v6hex: ::1 (loopback) expands correctly" {
	run _test_v6hex "::1"
	[[ "$status" -eq 0 ]]
	[[ "$output" == "00000000000000000000000000000001" ]]
}

@test "v6hex: :: (all zeros) expands to 32 zeros" {
	run _test_v6hex "::"
	[[ "$status" -eq 0 ]]
	[[ "$output" == "00000000000000000000000000000000" ]]
}

@test "v6hex: fe80:: expands correctly" {
	run _test_v6hex "fe80::"
	[[ "$status" -eq 0 ]]
	[[ "$output" == "fe800000000000000000000000000000" ]]
}

@test "v6hex: 2001:db8::1:0:0:1 middle expansion" {
	run _test_v6hex "2001:db8::1:0:0:1"
	[[ "$status" -eq 0 ]]
	[[ "$output" == "20010db8000000000001000000000001" ]]
}

@test "v6hex: already-normalized hex roundtrips" {
	run _test_v6hex "2001:0db8:85a3:0000:0000:8a2e:0370:7334"
	[[ "$status" -eq 0 ]]
	[[ "$output" == "20010db885a3000000008a2e03707334" ]]
}

@test "v6hex: mixed case normalizes to lowercase" {
	run _test_v6hex "2001:0DB8:ABCD:0000:0000:0000:0000:0001"
	[[ "$status" -eq 0 ]]
	[[ "$output" == "20010db8abcd00000000000000000001" ]]
}

@test "v6hex: rejects dotted-quad (::ffff:192.168.1.1)" {
	run _test_v6hex "::ffff:192.168.1.1"
	[[ "$status" -eq 0 ]]
	[[ -z "$output" ]]
}

@test "v6hex: rejects multiple :: separators (1::2::3)" {
	run _test_v6hex "1::2::3"
	[[ "$status" -eq 0 ]]
	[[ -z "$output" ]]
}

@test "v6hex: rejects non-hex characters (2001:db8::xyz1)" {
	run _test_v6hex "2001:db8::xyz1"
	[[ "$status" -eq 0 ]]
	[[ -z "$output" ]]
}

@test "v6hex: rejects too few groups without :: (7 groups)" {
	run _test_v6hex "2001:db8:1:2:3:4:5"
	[[ "$status" -eq 0 ]]
	[[ -z "$output" ]]
}

@test "v6hex: rejects too many groups (9 groups)" {
	run _test_v6hex "2001:db8:1:2:3:4:5:6:7"
	[[ "$status" -eq 0 ]]
	[[ -z "$output" ]]
}

@test "v6hex: rejects empty string" {
	run _test_v6hex ""
	[[ "$status" -eq 0 ]]
	[[ -z "$output" ]]
}

@test "v6hex: rejects too many groups with :: (::1:2:3:4:5:6:7:8)" {
	run _test_v6hex "::1:2:3:4:5:6:7:8"
	[[ "$status" -eq 0 ]]
	[[ -z "$output" ]]
}

# ---------------------------------------------------------------------------
# _geoip_cidr6_to_ranges
# ---------------------------------------------------------------------------

@test "_geoip_cidr6_to_ranges: /1 first half of address space" {
	printf '::/1\n' > "$TEST_TMPDIR/net1.zone6"
	run _geoip_cidr6_to_ranges "$TEST_TMPDIR/net1.zone6" "XX"
	[[ "$status" -eq 0 ]]
	local start end_hex
	start=$(echo "$output" | awk '{print $1}')
	end_hex=$(echo "$output" | awk '{print $2}')
	[[ "$start" == "00000000000000000000000000000000" ]]
	[[ "${end_hex:0:1}" == "7" ]]
	[[ "${end_hex:1}" == "fffffffffffffffffffffffffffffff" ]]
}

@test "_geoip_cidr6_to_ranges: /127 point-to-point link (2 addresses)" {
	printf '2001:db8::2/127\n' > "$TEST_TMPDIR/net127.zone6"
	run _geoip_cidr6_to_ranges "$TEST_TMPDIR/net127.zone6" "XX"
	[[ "$status" -eq 0 ]]
	local start end_hex
	start=$(echo "$output" | awk '{print $1}')
	end_hex=$(echo "$output" | awk '{print $2}')
	# /127: last nibble boundary at pos=31 (rem=3), mask_hi=2
	# addr nibble "2" -> binary 0010, top 3 bits = 001 -> start_nib=2, end_nib=3
	[[ "${start:31:1}" == "2" ]]
	[[ "${end_hex:31:1}" == "3" ]]
	# First 31 chars should be identical
	[[ "${start:0:31}" == "${end_hex:0:31}" ]]
}

@test "_geoip_cidr6_to_ranges: skips /129 invalid prefix" {
	printf '2001:db8::/129\n2001:db8::/32\n' > "$TEST_TMPDIR/invalid_prefix.zone6"
	run _geoip_cidr6_to_ranges "$TEST_TMPDIR/invalid_prefix.zone6" "XX"
	[[ "$status" -eq 0 ]]
	# Only /32 should produce output
	local line_count
	line_count=$(echo "$output" | wc -l)
	[[ "$line_count" -eq 1 ]]
}

@test "_geoip_cidr6_to_ranges: skips bare address without /prefix" {
	printf '2001:db8::1\n2001:db8::/32\n' > "$TEST_TMPDIR/bare_addr.zone6"
	run _geoip_cidr6_to_ranges "$TEST_TMPDIR/bare_addr.zone6" "XX"
	[[ "$status" -eq 0 ]]
	# Only /32 should produce output
	local line_count
	line_count=$(echo "$output" | wc -l)
	[[ "$line_count" -eq 1 ]]
}

@test "_geoip_cidr6_to_ranges: /128 single host — start equals end" {
	printf '2001:db8::1/128\n' > "$TEST_TMPDIR/single.zone6"
	run _geoip_cidr6_to_ranges "$TEST_TMPDIR/single.zone6" "XX"
	[[ "$status" -eq 0 ]]
	local start end_hex
	start=$(echo "$output" | awk '{print $1}')
	end_hex=$(echo "$output" | awk '{print $2}')
	[[ "$start" == "$end_hex" ]]
	[[ "$start" == "20010db8000000000000000000000001" ]]
}

@test "_geoip_cidr6_to_ranges: /64 standard range" {
	printf '2001:db8::/64\n' > "$TEST_TMPDIR/net64.zone6"
	run _geoip_cidr6_to_ranges "$TEST_TMPDIR/net64.zone6" "JP"
	[[ "$status" -eq 0 ]]
	local start end_hex
	start=$(echo "$output" | awk '{print $1}')
	end_hex=$(echo "$output" | awk '{print $2}')
	[[ "$start" == "20010db8000000000000000000000000" ]]
	[[ "$end_hex" == "20010db800000000ffffffffffffffff" ]]
}

@test "_geoip_cidr6_to_ranges: /48 range" {
	printf '2001:db8:1234::/48\n' > "$TEST_TMPDIR/net48.zone6"
	run _geoip_cidr6_to_ranges "$TEST_TMPDIR/net48.zone6" "DE"
	[[ "$status" -eq 0 ]]
	local start end_hex
	start=$(echo "$output" | awk '{print $1}')
	end_hex=$(echo "$output" | awk '{print $2}')
	# 48/4 = 12 network nibbles, 20 host nibbles
	[[ ${#start} -eq 32 ]]
	[[ ${#end_hex} -eq 32 ]]
	# First 12 chars must match
	[[ "${start:0:12}" == "20010db81234" ]]
	[[ "${end_hex:0:12}" == "20010db81234" ]]
	# Host portion: all zeros for start, all f for end
	[[ "${start:12}" == "00000000000000000000" ]]
	[[ "${end_hex:12}" == "ffffffffffffffffffff" ]]
}

@test "_geoip_cidr6_to_ranges: /32 range" {
	printf '2001:db8::/32\n' > "$TEST_TMPDIR/net32.zone6"
	run _geoip_cidr6_to_ranges "$TEST_TMPDIR/net32.zone6" "US"
	[[ "$status" -eq 0 ]]
	local start end_hex
	start=$(echo "$output" | awk '{print $1}')
	end_hex=$(echo "$output" | awk '{print $2}')
	[[ "$start" == "20010db8000000000000000000000000" ]]
	[[ "$end_hex" == "20010db8ffffffffffffffffffffffff" ]]
}

@test "_geoip_cidr6_to_ranges: /16 range" {
	printf '2001::/16\n' > "$TEST_TMPDIR/net16.zone6"
	run _geoip_cidr6_to_ranges "$TEST_TMPDIR/net16.zone6" "CN"
	[[ "$status" -eq 0 ]]
	local start end_hex
	start=$(echo "$output" | awk '{print $1}')
	end_hex=$(echo "$output" | awk '{print $2}')
	[[ "${start:0:4}" == "2001" ]]
	[[ "${start:4}" == "0000000000000000000000000000" ]]
	[[ "${end_hex:0:4}" == "2001" ]]
	[[ "${end_hex:4}" == "ffffffffffffffffffffffffffff" ]]
}

@test "_geoip_cidr6_to_ranges: /0 full address space" {
	printf '::/0\n' > "$TEST_TMPDIR/all.zone6"
	run _geoip_cidr6_to_ranges "$TEST_TMPDIR/all.zone6" "AL"
	[[ "$status" -eq 0 ]]
	local start end_hex
	start=$(echo "$output" | awk '{print $1}')
	end_hex=$(echo "$output" | awk '{print $2}')
	[[ "$start" == "00000000000000000000000000000000" ]]
	[[ "$end_hex" == "ffffffffffffffffffffffffffffffff" ]]
}

@test "_geoip_cidr6_to_ranges: non-nibble-aligned /29 boundary masking" {
	# 2001:db80::/29 — 7 full nibbles + 1 bit in boundary nibble
	# hex for 2001:db80:: = 2001db80 0000...
	# pos=7 means first 7 chars "2001db8" are fully network
	# boundary char (8th) = "0" = 0b0000
	# 1 network bit: top bit = 0
	# start_nib = int(0/8)*8 = 0, end_nib = 7
	printf '2001:db80::/29\n' > "$TEST_TMPDIR/net29.zone6"
	run _geoip_cidr6_to_ranges "$TEST_TMPDIR/net29.zone6" "BR"
	[[ "$status" -eq 0 ]]
	local start end_hex
	start=$(echo "$output" | awk '{print $1}')
	end_hex=$(echo "$output" | awk '{print $2}')
	# First 7 nibbles: "2001db8" fixed
	[[ "${start:0:7}" == "2001db8" ]]
	[[ "${end_hex:0:7}" == "2001db8" ]]
	# Boundary nibble (8th): start=0, end=7
	[[ "${start:7:1}" == "0" ]]
	[[ "${end_hex:7:1}" == "7" ]]
	# Host portion (24 chars): all zeros/all f
	[[ "${start:8}" == "000000000000000000000000" ]]
	[[ "${end_hex:8}" == "ffffffffffffffffffffffff" ]]
}

@test "_geoip_cidr6_to_ranges: non-nibble-aligned /35 boundary masking" {
	# 2001:db8:8000::/35 — 8 full nibbles + 3 bits in boundary nibble
	# hex: 20010db880000000...
	# 9th nibble = '8' = 0b1000, top 3 bits = 100 = 4
	# mask_hi = 2^(4-3) = 2
	# start_nib = int(8/2)*2 = 8, end_nib = 8+2-1 = 9
	printf '2001:db8:8000::/35\n' > "$TEST_TMPDIR/net35.zone6"
	run _geoip_cidr6_to_ranges "$TEST_TMPDIR/net35.zone6" "RU"
	[[ "$status" -eq 0 ]]
	local start end_hex
	start=$(echo "$output" | awk '{print $1}')
	end_hex=$(echo "$output" | awk '{print $2}')
	# First 8 chars: "20010db8" fixed
	[[ "${start:0:8}" == "20010db8" ]]
	[[ "${end_hex:0:8}" == "20010db8" ]]
	# Boundary nibble (9th): start=8, end=9
	[[ "${start:8:1}" == "8" ]]
	[[ "${end_hex:8:1}" == "9" ]]
	# Host portion (23 chars)
	[[ "${start:9}" == "00000000000000000000000" ]]
	[[ "${end_hex:9}" == "fffffffffffffffffffffff" ]]
}

@test "_geoip_cidr6_to_ranges: skips comment and blank lines" {
	printf '# header comment\n\n2001:db8::/32\n# trailing\n' > "$TEST_TMPDIR/commented.zone6"
	run _geoip_cidr6_to_ranges "$TEST_TMPDIR/commented.zone6" "CM"
	[[ "$status" -eq 0 ]]
	local line_count
	line_count=$(echo "$output" | wc -l)
	[[ "$line_count" -eq 1 ]]
}

@test "_geoip_cidr6_to_ranges: skips lines with dots (mapped IPv4)" {
	printf '::ffff:192.168.1.0/120\n2001:db8::/32\n' > "$TEST_TMPDIR/mixed.zone6"
	run _geoip_cidr6_to_ranges "$TEST_TMPDIR/mixed.zone6" "MX"
	[[ "$status" -eq 0 ]]
	local line_count
	line_count=$(echo "$output" | wc -l)
	[[ "$line_count" -eq 1 ]]
	# Only the non-dotted line should appear
	[[ "$output" == *"20010db8"* ]]
}

@test "_geoip_cidr6_to_ranges: missing file returns 1" {
	run _geoip_cidr6_to_ranges "$TEST_TMPDIR/nonexistent" "XX"
	[[ "$status" -eq 1 ]]
}

@test "_geoip_cidr6_to_ranges: CC tag preserved in output" {
	printf '2001:db8::/32\n' > "$TEST_TMPDIR/cc.zone6"
	run _geoip_cidr6_to_ranges "$TEST_TMPDIR/cc.zone6" "QQ"
	[[ "$status" -eq 0 ]]
	local cc_field
	cc_field=$(echo "$output" | awk '{print $3}')
	[[ "$cc_field" == "QQ" ]]
}

@test "_geoip_cidr6_to_ranges: output fields are 32-char hex strings" {
	printf '2001:db8::/32\nfe80::/10\n' > "$TEST_TMPDIR/fields.zone6"
	run _geoip_cidr6_to_ranges "$TEST_TMPDIR/fields.zone6" "XX"
	[[ "$status" -eq 0 ]]
	local _hex_re='^[0-9a-f]{32}$'
	while IFS= read -r line; do
		local start end_hex
		start=$(echo "$line" | awk '{print $1}')
		end_hex=$(echo "$line" | awk '{print $2}')
		[[ "$start" =~ $_hex_re ]]
		[[ "$end_hex" =~ $_hex_re ]]
	done <<< "$output"
}

# ---------------------------------------------------------------------------
# geoip_ip6_lookup
# ---------------------------------------------------------------------------

# Helper: create a hex-range fixture DB for IPv6 lookup tests
_create_ip6_fixture_db() {
	# Three ranges:
	# 2001:db8::/32      = 20010db8{00..ff} → JP
	# 2400:cb00::/32     = 2400cb00{00..ff} → US
	# 2a00:1450::/32     = 2a001450{00..ff} → DE
	cat > "$TEST_TMPDIR/test.ip6db" <<-'EOF'
	20010db8000000000000000000000000 20010db8ffffffffffffffffffffffff JP
	2400cb00000000000000000000000000 2400cb00ffffffffffffffffffffffff US
	2a001450000000000000000000000000 2a001450ffffffffffffffffffffffff DE
	EOF
}

@test "geoip_ip6_lookup: finds IP in first range" {
	_create_ip6_fixture_db
	run geoip_ip6_lookup "2001:db8::1" "$TEST_TMPDIR/test.ip6db"
	[[ "$status" -eq 0 ]]
	[[ "$output" == "JP" ]]
}

@test "geoip_ip6_lookup: finds IP in middle range" {
	_create_ip6_fixture_db
	run geoip_ip6_lookup "2400:cb00:2048:1::6814:155" "$TEST_TMPDIR/test.ip6db"
	[[ "$status" -eq 0 ]]
	[[ "$output" == "US" ]]
}

@test "geoip_ip6_lookup: finds IP in last range" {
	_create_ip6_fixture_db
	run geoip_ip6_lookup "2a00:1450:4001::200e" "$TEST_TMPDIR/test.ip6db"
	[[ "$status" -eq 0 ]]
	[[ "$output" == "DE" ]]
}

@test "geoip_ip6_lookup: first IP in range matches" {
	_create_ip6_fixture_db
	run geoip_ip6_lookup "2001:db8::" "$TEST_TMPDIR/test.ip6db"
	[[ "$status" -eq 0 ]]
	[[ "$output" == "JP" ]]
}

@test "geoip_ip6_lookup: last IP in range matches" {
	_create_ip6_fixture_db
	run geoip_ip6_lookup "2001:db8:ffff:ffff:ffff:ffff:ffff:ffff" "$TEST_TMPDIR/test.ip6db"
	[[ "$status" -eq 0 ]]
	[[ "$output" == "JP" ]]
}

@test "geoip_ip6_lookup: one past range end does not match" {
	_create_ip6_fixture_db
	# 2001:db9:: is just past 2001:db8::/32
	run geoip_ip6_lookup "2001:db9::" "$TEST_TMPDIR/test.ip6db"
	[[ "$status" -eq 1 ]]
}

@test "geoip_ip6_lookup: no match returns 1" {
	_create_ip6_fixture_db
	run geoip_ip6_lookup "fe80::1" "$TEST_TMPDIR/test.ip6db"
	[[ "$status" -eq 1 ]]
	[[ -z "$output" ]]
}

@test "geoip_ip6_lookup: various abbreviations resolve correctly" {
	_create_ip6_fixture_db
	# All these are in 2001:db8::/32
	run geoip_ip6_lookup "2001:0db8:0000:0000:0000:0000:0000:0001" "$TEST_TMPDIR/test.ip6db"
	[[ "$status" -eq 0 ]]
	[[ "$output" == "JP" ]]
	run geoip_ip6_lookup "2001:DB8::1" "$TEST_TMPDIR/test.ip6db"
	[[ "$status" -eq 0 ]]
	[[ "$output" == "JP" ]]
}

@test "geoip_ip6_lookup: IPv4 input returns 1" {
	_create_ip6_fixture_db
	run geoip_ip6_lookup "192.0.2.1" "$TEST_TMPDIR/test.ip6db"
	[[ "$status" -eq 1 ]]
}

@test "geoip_ip6_lookup: dotted-quad mapped address returns 1" {
	_create_ip6_fixture_db
	run geoip_ip6_lookup "::ffff:192.168.1.1" "$TEST_TMPDIR/test.ip6db"
	[[ "$status" -eq 1 ]]
}

@test "geoip_ip6_lookup: empty IP returns 1" {
	_create_ip6_fixture_db
	run geoip_ip6_lookup "" "$TEST_TMPDIR/test.ip6db"
	[[ "$status" -eq 1 ]]
}

@test "geoip_ip6_lookup: missing DB file returns 1" {
	run geoip_ip6_lookup "2001:db8::1" "$TEST_TMPDIR/nonexistent.ip6db"
	[[ "$status" -eq 1 ]]
}

@test "geoip_ip6_lookup: empty DB file returns 1" {
	: > "$TEST_TMPDIR/empty.ip6db"
	run geoip_ip6_lookup "2001:db8::1" "$TEST_TMPDIR/empty.ip6db"
	[[ "$status" -eq 1 ]]
}

@test "geoip_ip6_lookup: comment lines in DB skipped" {
	cat > "$TEST_TMPDIR/commented.ip6db" <<-'EOF'
	# IPv6 country database
	20010db8000000000000000000000000 20010db8ffffffffffffffffffffffff JP
	EOF
	run geoip_ip6_lookup "2001:db8::1" "$TEST_TMPDIR/commented.ip6db"
	[[ "$status" -eq 0 ]]
	[[ "$output" == "JP" ]]
}

@test "geoip_ip6_lookup: empty DB_FILE arg returns 1" {
	run geoip_ip6_lookup "2001:db8::1" ""
	[[ "$status" -eq 1 ]]
}

@test "geoip_ip6_lookup: roundtrip — _geoip_cidr6_to_ranges output fed to lookup" {
	printf '2001:db8::/32\n2400:cb00::/32\n' > "$TEST_TMPDIR/roundtrip.zone6"
	_geoip_cidr6_to_ranges "$TEST_TMPDIR/roundtrip.zone6" "JP" > "$TEST_TMPDIR/roundtrip.ip6db"
	# Verify lookup works on converter output
	run geoip_ip6_lookup "2001:db8:1234::1" "$TEST_TMPDIR/roundtrip.ip6db"
	[[ "$status" -eq 0 ]]
	[[ "$output" == "JP" ]]
	# Address outside both ranges
	run geoip_ip6_lookup "fe80::1" "$TEST_TMPDIR/roundtrip.ip6db"
	[[ "$status" -eq 1 ]]
}

# ---------------------------------------------------------------------------
# geoip_build_ip6db — mocked end-to-end tests
# ---------------------------------------------------------------------------

@test "geoip_build_ip6db: produces sorted output from zone files" {
	# Mock per-country download to provide 2 CCs
	geoip_download() {
		local cc="$1" _family="$2" output="$3"
		case "$cc" in
			US) printf '2400:cb00::/32\n' > "$output"; return 0 ;;
			CN) printf '2001:db8::/32\n' > "$output"; return 0 ;;
			*) return 1 ;;
		esac
	}

	local outfile="$TEST_TMPDIR/test_build6.ip6db"
	run geoip_build_ip6db "$outfile" 1
	[[ "$status" -eq 0 ]]
	[[ -f "$outfile" ]]

	# Verify output is sorted lexicographically by first field
	local prev="" sorted=1
	while read -r start rest; do
		if [[ -n "$prev" ]] && [[ "$start" < "$prev" ]]; then
			sorted=0
			break
		fi
		prev="$start"
	done < "$outfile"
	[[ "$sorted" -eq 1 ]]
}

@test "geoip_build_ip6db: output is valid hex-range format" {
	geoip_download() {
		local cc="$1" _family="$2" output="$3"
		case "$cc" in
			US) printf '2400:cb00::/32\n' > "$output"; return 0 ;;
			*) return 1 ;;
		esac
	}

	local outfile="$TEST_TMPDIR/format6.ip6db"
	geoip_build_ip6db "$outfile" 1

	local _hex_re='^[0-9a-f]{32}$'
	while read -r start end_hex cc; do
		[[ "$start" =~ $_hex_re ]]
		[[ "$end_hex" =~ $_hex_re ]]
		[[ ${#cc} -eq 2 ]]
	done < "$outfile"
}

@test "geoip_build_ip6db: sets _GEOIP_BUILD6_COUNT and _GEOIP_BUILD6_RANGES" {
	geoip_download() {
		local cc="$1" _family="$2" output="$3"
		case "$cc" in
			US) printf '2400:cb00::/32\n' > "$output"; return 0 ;;
			CN) printf '2001:db8::/32\n' > "$output"; return 0 ;;
			*) return 1 ;;
		esac
	}

	local outfile="$TEST_TMPDIR/count_build6.ip6db"
	geoip_build_ip6db "$outfile" 1
	[[ "$_GEOIP_BUILD6_COUNT" -eq 2 ]]
	[[ "$_GEOIP_BUILD6_RANGES" -eq 2 ]]
	[[ "$_GEOIP_BUILD6_FAIL" -gt 0 ]]
}

@test "geoip_build_ip6db: aborts below min_ranges threshold" {
	geoip_download() {
		local cc="$1" _family="$2" output="$3"
		case "$cc" in
			US) printf '2400:cb00::/32\n' > "$output"; return 0 ;;
			*) return 1 ;;
		esac
	}

	local outfile="$TEST_TMPDIR/min_build6.ip6db"
	run geoip_build_ip6db "$outfile" 1000
	[[ "$status" -eq 1 ]]
	[[ "$output" == *"only"*"ranges"* ]]
}

@test "geoip_build_ip6db: empty OUTPUT returns 1" {
	run geoip_build_ip6db ""
	[[ "$status" -eq 1 ]]
	[[ "$output" == *"OUTPUT required"* ]]
}

@test "geoip_build_ip6db: output is usable by geoip_ip6_lookup" {
	geoip_download() {
		local cc="$1" _family="$2" output="$3"
		case "$cc" in
			US) printf '2400:cb00::/32\n' > "$output"; return 0 ;;
			CN) printf '2001:db8::/32\n' > "$output"; return 0 ;;
			*) return 1 ;;
		esac
	}

	local outfile="$TEST_TMPDIR/roundtrip6.ip6db"
	geoip_build_ip6db "$outfile" 1

	# Look up IPs in the built database
	run geoip_ip6_lookup "2400:cb00:2048::1" "$outfile"
	[[ "$status" -eq 0 ]]
	[[ "$output" == "US" ]]

	run geoip_ip6_lookup "2001:db8::1" "$outfile"
	[[ "$status" -eq 0 ]]
	[[ "$output" == "CN" ]]

	# IP not in any range
	run geoip_ip6_lookup "fe80::1" "$outfile"
	[[ "$status" -eq 1 ]]
}

@test "geoip_build_ip6db: cleans up temp directory on success" {
	geoip_download() {
		local cc="$1" _family="$2" output="$3"
		case "$cc" in
			US) printf '2400:cb00::/32\n' > "$output"; return 0 ;;
			*) return 1 ;;
		esac
	}

	local outfile="$TEST_TMPDIR/cleanup6.ip6db"
	geoip_build_ip6db "$outfile" 1

	local leftover
	leftover=$(find "$TEST_TMPDIR" -name "cleanup6.ip6db.build6-*" -type d 2>/dev/null | wc -l)
	[[ "$leftover" -eq 0 ]]
}

@test "geoip_build_ip6db: cleans up temp directory on failure" {
	geoip_download() { return 1; }

	local outfile="$TEST_TMPDIR/fail_cleanup6.ip6db"
	run geoip_build_ip6db "$outfile" 1000
	[[ "$status" -eq 1 ]]

	local leftover
	leftover=$(find "$TEST_TMPDIR" -name "fail_cleanup6.ip6db.build6-*" -type d 2>/dev/null | wc -l)
	[[ "$leftover" -eq 0 ]]
}
