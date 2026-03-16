#!/usr/bin/env bats
# 03-ipdb.bats — geoip_lib IP database layer tests
# Tests: geoip_all_cc, _geoip_cidr4_to_ranges, geoip_ip_lookup,
#        _geoip_download_ipdeny_bulk, geoip_build_ipdb

load helpers/geoip-common

setup() {
	geoip_common_setup
	_ipdb_mock_setup
}

teardown() {
	geoip_teardown
}

# ---------------------------------------------------------------------------
# Mock infrastructure
# ---------------------------------------------------------------------------

_ipdb_mock_setup() {
	MOCK_DATA="$TEST_TMPDIR/mock_data"
	mkdir -p "$MOCK_DATA"
	export MOCK_DATA

	# Create valid CIDR fixture files
	printf '192.0.2.0/24\n' > "$MOCK_DATA/xx.zone"
	printf '198.51.100.0/25\n198.51.100.128/25\n' > "$MOCK_DATA/yy.zone"
	printf '203.0.113.0/24\n' > "$MOCK_DATA/zz.zone"
	# Multi-prefix country
	printf '10.0.0.0/8\n172.16.0.0/12\n' > "$MOCK_DATA/aa.zone"
	# Empty and garbage
	: > "$MOCK_DATA/empty.zone"
	printf 'not cidr data\ngarbage\n' > "$MOCK_DATA/garbage.zone"

	# Pre-built integer-range database fixture
	# Format: START_INT END_INT CC
	# 192.0.2.0/24   = 3221225984 .. 3221226239
	# 198.51.100.0/24 = 3325256704 .. 3325256959
	# 203.0.113.0/24  = 3405803776 .. 3405804031
	cat > "$MOCK_DATA/test.ipdb" <<-'EOF'
	3221225984 3221226239 XX
	3325256704 3325256959 YY
	3405803776 3405804031 ZZ
	EOF
}

# Helper: create a mock tarball containing zone files
_create_mock_tarball() {
	local tarball="$1"
	shift
	# remaining args: pairs of "cc content"
	local tar_src
	tar_src=$(mktemp -d "$TEST_TMPDIR/tar_src.XXXXXX")
	while [[ $# -ge 2 ]]; do
		echo "$2" > "$tar_src/$1.zone"
		shift 2
	done
	tar -czf "$tarball" -C "$tar_src" .
	rm -rf "$tar_src"
}

# ---------------------------------------------------------------------------
# geoip_all_cc
# ---------------------------------------------------------------------------

@test "geoip_all_cc: returns 190-260 country codes" {
	local count
	count=$(geoip_all_cc | wc -l)
	[[ "$count" -ge 190 ]]
	[[ "$count" -le 260 ]]
}

@test "geoip_all_cc: includes US from North America" {
	run geoip_all_cc
	[[ "$output" == *"US"* ]]
}

@test "geoip_all_cc: includes CN from Asia" {
	run geoip_all_cc
	[[ "$output" == *"CN"* ]]
}

@test "geoip_all_cc: includes DE from Europe" {
	run geoip_all_cc
	[[ "$output" == *"DE"* ]]
}

@test "geoip_all_cc: includes BR from South America" {
	run geoip_all_cc
	[[ "$output" == *"BR"* ]]
}

@test "geoip_all_cc: includes AU from Oceania" {
	run geoip_all_cc
	[[ "$output" == *"AU"* ]]
}

@test "geoip_all_cc: includes ZA from Africa" {
	run geoip_all_cc
	[[ "$output" == *"ZA"* ]]
}

@test "geoip_all_cc: one code per line, all uppercase 2-letter" {
	local _cc_re='^[A-Z]{2}$'
	local bad=0
	while IFS= read -r line; do
		if ! [[ "$line" =~ $_cc_re ]]; then
			bad=$((bad + 1))
		fi
	done < <(geoip_all_cc)
	[[ "$bad" -eq 0 ]]
}

@test "geoip_all_cc: no duplicate codes" {
	local total uniq
	total=$(geoip_all_cc | wc -l)
	uniq=$(geoip_all_cc | sort -u | wc -l)
	[[ "$total" -eq "$uniq" ]]
}

# ---------------------------------------------------------------------------
# _geoip_cidr4_to_ranges
# ---------------------------------------------------------------------------

@test "_geoip_cidr4_to_ranges: /24 produces correct start and end" {
	# 192.0.2.0/24 → start=3221225984 end=3221226239
	run _geoip_cidr4_to_ranges "$MOCK_DATA/xx.zone" "XX"
	[[ "$status" -eq 0 ]]
	[[ "$output" == "3221225984 3221226239 XX" ]]
}

@test "_geoip_cidr4_to_ranges: /25 produces two ranges" {
	run _geoip_cidr4_to_ranges "$MOCK_DATA/yy.zone" "YY"
	[[ "$status" -eq 0 ]]
	local line_count
	line_count=$(echo "$output" | wc -l)
	[[ "$line_count" -eq 2 ]]
}

@test "_geoip_cidr4_to_ranges: /32 single host" {
	printf '10.0.0.1/32\n' > "$TEST_TMPDIR/single.zone"
	run _geoip_cidr4_to_ranges "$TEST_TMPDIR/single.zone" "SH"
	[[ "$status" -eq 0 ]]
	# start == end for /32
	local start end
	start=$(echo "$output" | awk '{print $1}')
	end=$(echo "$output" | awk '{print $2}')
	[[ "$start" -eq "$end" ]]
}

@test "_geoip_cidr4_to_ranges: /8 large range" {
	printf '10.0.0.0/8\n' > "$TEST_TMPDIR/wide.zone"
	run _geoip_cidr4_to_ranges "$TEST_TMPDIR/wide.zone" "WD"
	[[ "$status" -eq 0 ]]
	# 10.0.0.0 = 167772160, end = 167772160 + 2^24 - 1 = 184549375
	local start end
	start=$(echo "$output" | awk '{print $1}')
	end=$(echo "$output" | awk '{print $2}')
	[[ "$start" -eq 167772160 ]]
	[[ "$end" -eq 184549375 ]]
}

@test "_geoip_cidr4_to_ranges: /0 entire address space" {
	printf '0.0.0.0/0\n' > "$TEST_TMPDIR/all.zone"
	run _geoip_cidr4_to_ranges "$TEST_TMPDIR/all.zone" "AL"
	[[ "$status" -eq 0 ]]
	local start end
	start=$(echo "$output" | awk '{print $1}')
	end=$(echo "$output" | awk '{print $2}')
	[[ "$start" -eq 0 ]]
	[[ "$end" -eq 4294967295 ]]
}

@test "_geoip_cidr4_to_ranges: /16 mid-range" {
	printf '172.16.0.0/16\n' > "$TEST_TMPDIR/mid.zone"
	run _geoip_cidr4_to_ranges "$TEST_TMPDIR/mid.zone" "MD"
	[[ "$status" -eq 0 ]]
	# 172.16.0.0 = 2886729728, size = 65536, end = 2886795263
	local start end
	start=$(echo "$output" | awk '{print $1}')
	end=$(echo "$output" | awk '{print $2}')
	[[ "$start" -eq 2886729728 ]]
	[[ "$end" -eq 2886795263 ]]
}

@test "_geoip_cidr4_to_ranges: skips comment and blank lines" {
	printf '# header comment\n\n192.0.2.0/24\n# trailing\n' > "$TEST_TMPDIR/commented.zone"
	run _geoip_cidr4_to_ranges "$TEST_TMPDIR/commented.zone" "CM"
	[[ "$status" -eq 0 ]]
	local line_count
	line_count=$(echo "$output" | wc -l)
	[[ "$line_count" -eq 1 ]]
}

@test "_geoip_cidr4_to_ranges: skips malformed lines (no prefix length)" {
	printf '192.0.2.0\n192.0.2.0/24\n' > "$TEST_TMPDIR/partial.zone"
	run _geoip_cidr4_to_ranges "$TEST_TMPDIR/partial.zone" "PT"
	[[ "$status" -eq 0 ]]
	local line_count
	line_count=$(echo "$output" | wc -l)
	[[ "$line_count" -eq 1 ]]
}

@test "_geoip_cidr4_to_ranges: CC tag preserved in output" {
	run _geoip_cidr4_to_ranges "$MOCK_DATA/xx.zone" "QQ"
	[[ "$status" -eq 0 ]]
	local cc_field
	cc_field=$(echo "$output" | awk '{print $3}')
	[[ "$cc_field" == "QQ" ]]
}

@test "_geoip_cidr4_to_ranges: missing file returns 1" {
	run _geoip_cidr4_to_ranges "$TEST_TMPDIR/nonexistent" "XX"
	[[ "$status" -eq 1 ]]
}

@test "_geoip_cidr4_to_ranges: real IP (223.255.254.0/24)" {
	printf '223.255.254.0/24\n' > "$TEST_TMPDIR/real.zone"
	run _geoip_cidr4_to_ranges "$TEST_TMPDIR/real.zone" "RL"
	[[ "$status" -eq 0 ]]
	# 223.255.254.0 = 223*16777216 + 255*65536 + 254*256 = 3758096896 + 16711680 + 65024 = 3758030336 + ...
	# Just verify it produces output with 3 fields
	local fields
	fields=$(echo "$output" | awk '{print NF}')
	[[ "$fields" -eq 3 ]]
}

# ---------------------------------------------------------------------------
# geoip_ip_lookup
# ---------------------------------------------------------------------------

@test "geoip_ip_lookup: finds IP in first range" {
	run geoip_ip_lookup "192.0.2.1" "$MOCK_DATA/test.ipdb"
	[[ "$status" -eq 0 ]]
	[[ "$output" == "XX" ]]
}

@test "geoip_ip_lookup: finds IP in middle range" {
	run geoip_ip_lookup "198.51.100.50" "$MOCK_DATA/test.ipdb"
	[[ "$status" -eq 0 ]]
	[[ "$output" == "YY" ]]
}

@test "geoip_ip_lookup: finds IP in last range" {
	run geoip_ip_lookup "203.0.113.200" "$MOCK_DATA/test.ipdb"
	[[ "$status" -eq 0 ]]
	[[ "$output" == "ZZ" ]]
}

@test "geoip_ip_lookup: no match returns 1" {
	run geoip_ip_lookup "8.8.8.8" "$MOCK_DATA/test.ipdb"
	[[ "$status" -eq 1 ]]
	[[ -z "$output" ]]
}

@test "geoip_ip_lookup: first IP in range matches" {
	run geoip_ip_lookup "192.0.2.0" "$MOCK_DATA/test.ipdb"
	[[ "$status" -eq 0 ]]
	[[ "$output" == "XX" ]]
}

@test "geoip_ip_lookup: last IP in range matches" {
	# 192.0.2.255 is the last IP in 192.0.2.0/24
	run geoip_ip_lookup "192.0.2.255" "$MOCK_DATA/test.ipdb"
	[[ "$status" -eq 0 ]]
	[[ "$output" == "XX" ]]
}

@test "geoip_ip_lookup: one past range end does not match" {
	# 192.0.3.0 is just past 192.0.2.0/24
	run geoip_ip_lookup "192.0.3.0" "$MOCK_DATA/test.ipdb"
	[[ "$status" -eq 1 ]]
}

@test "geoip_ip_lookup: IPv6 returns 1" {
	run geoip_ip_lookup "2001:db8::1" "$MOCK_DATA/test.ipdb"
	[[ "$status" -eq 1 ]]
}

@test "geoip_ip_lookup: non-numeric IP returns 1" {
	run geoip_ip_lookup "abc.def.ghi.jkl" "$MOCK_DATA/test.ipdb"
	[[ "$status" -eq 1 ]]
}

@test "geoip_ip_lookup: empty IP returns 1" {
	run geoip_ip_lookup "" "$MOCK_DATA/test.ipdb"
	[[ "$status" -eq 1 ]]
}

@test "geoip_ip_lookup: missing DB file returns 1" {
	run geoip_ip_lookup "192.0.2.1" "$TEST_TMPDIR/nonexistent.ipdb"
	[[ "$status" -eq 1 ]]
}

@test "geoip_ip_lookup: empty DB file returns 1" {
	: > "$TEST_TMPDIR/empty.ipdb"
	run geoip_ip_lookup "192.0.2.1" "$TEST_TMPDIR/empty.ipdb"
	[[ "$status" -eq 1 ]]
}

@test "geoip_ip_lookup: handles comment lines in DB" {
	cat > "$TEST_TMPDIR/commented.ipdb" <<-'EOF'
	# IP country database
	3221225984 3221226239 XX
	EOF
	run geoip_ip_lookup "192.0.2.1" "$TEST_TMPDIR/commented.ipdb"
	[[ "$status" -eq 0 ]]
	[[ "$output" == "XX" ]]
}

@test "geoip_ip_lookup: empty DB_FILE arg returns 1" {
	run geoip_ip_lookup "192.0.2.1" ""
	[[ "$status" -eq 1 ]]
}

# ---------------------------------------------------------------------------
# _geoip_download_ipdeny_bulk — mocked tarball tests
# ---------------------------------------------------------------------------

@test "_geoip_download_ipdeny_bulk: extracts valid zone files from tarball" {
	local tar_file="$TEST_TMPDIR/mock.tar.gz"
	_create_mock_tarball "$tar_file" \
		"us" "198.51.100.0/24" \
		"cn" "203.0.113.0/24"

	# Mock _geoip_download_cmd to copy our tarball
	local _saved_fixture="$tar_file"
	_geoip_download_cmd() {
		cp "$_saved_fixture" "$2"
		return 0
	}

	local outdir="$TEST_TMPDIR/bulk_out"
	run _geoip_download_ipdeny_bulk "$outdir"
	[[ "$status" -eq 0 ]]
	[[ -f "$outdir/US.zone" ]]
	[[ -f "$outdir/CN.zone" ]]
}

@test "_geoip_download_ipdeny_bulk: validates CIDR content" {
	local tar_file="$TEST_TMPDIR/mock_garbage.tar.gz"
	_create_mock_tarball "$tar_file" \
		"us" "198.51.100.0/24" \
		"xx" "not valid cidr data"

	local _saved_fixture="$tar_file"
	_geoip_download_cmd() {
		cp "$_saved_fixture" "$2"
		return 0
	}

	local outdir="$TEST_TMPDIR/bulk_validate"
	run _geoip_download_ipdeny_bulk "$outdir"
	[[ "$status" -eq 0 ]]
	# Valid file extracted
	[[ -f "$outdir/US.zone" ]]
	# Garbage file rejected
	[[ ! -f "$outdir/XX.zone" ]]
}

@test "_geoip_download_ipdeny_bulk: rejects non-CC filenames" {
	local tar_file="$TEST_TMPDIR/mock_badnames.tar.gz"
	local tar_src
	tar_src=$(mktemp -d "$TEST_TMPDIR/tar_src.XXXXXX")
	echo "198.51.100.0/24" > "$tar_src/us.zone"
	echo "10.0.0.0/8" > "$tar_src/toolong.zone"
	echo "10.0.0.0/8" > "$tar_src/1x.zone"
	tar -czf "$tar_file" -C "$tar_src" .
	rm -rf "$tar_src"

	local _saved_fixture="$tar_file"
	_geoip_download_cmd() {
		cp "$_saved_fixture" "$2"
		return 0
	}

	local outdir="$TEST_TMPDIR/bulk_names"
	run _geoip_download_ipdeny_bulk "$outdir"
	[[ "$status" -eq 0 ]]
	[[ -f "$outdir/US.zone" ]]
	[[ ! -f "$outdir/TOOLONG.zone" ]]
	[[ ! -f "$outdir/1X.zone" ]]
}

@test "_geoip_download_ipdeny_bulk: returns 1 on download failure" {
	_geoip_download_cmd() { return 1; }
	local outdir="$TEST_TMPDIR/bulk_fail"
	run _geoip_download_ipdeny_bulk "$outdir"
	[[ "$status" -eq 1 ]]
}

@test "_geoip_download_ipdeny_bulk: returns 1 on empty output dir arg" {
	run _geoip_download_ipdeny_bulk ""
	[[ "$status" -eq 1 ]]
}

@test "_geoip_download_ipdeny_bulk: cleans up temp files on success" {
	local tar_file="$TEST_TMPDIR/mock_clean.tar.gz"
	_create_mock_tarball "$tar_file" "us" "198.51.100.0/24"

	local _saved_fixture="$tar_file"
	_geoip_download_cmd() {
		cp "$_saved_fixture" "$2"
		return 0
	}

	local outdir="$TEST_TMPDIR/bulk_clean"
	_geoip_download_ipdeny_bulk "$outdir"
	# No leftover .bulk-* temp files
	local leftover
	leftover=$(find "$outdir" -name ".bulk-*" 2>/dev/null | wc -l)
	[[ "$leftover" -eq 0 ]]
}

@test "_geoip_download_ipdeny_bulk: returns 1 on corrupt tarball" {
	_geoip_download_cmd() {
		echo "not a tarball" > "$2"
		return 0
	}

	local outdir="$TEST_TMPDIR/bulk_corrupt"
	run _geoip_download_ipdeny_bulk "$outdir"
	[[ "$status" -eq 1 ]]
}

# ---------------------------------------------------------------------------
# geoip_build_ipdb — mocked end-to-end tests
# ---------------------------------------------------------------------------

@test "geoip_build_ipdb: produces sorted output from zone files" {
	# Mock: skip bulk (fail), mock per-country to provide 2 CCs
	_geoip_download_ipdeny_bulk() { return 1; }
	local _call_count=0
	geoip_download() {
		local cc="$1" _family="$2" output="$3"
		case "$cc" in
			# Only provide 2 countries, rest fail
			US) printf '198.51.100.0/24\n' > "$output"; return 0 ;;
			CN) printf '192.0.2.0/24\n' > "$output"; return 0 ;;
			*) return 1 ;;
		esac
	}

	local outfile="$TEST_TMPDIR/test_build.ipdb"
	run geoip_build_ipdb "$outfile" 1
	[[ "$status" -eq 0 ]]
	[[ -f "$outfile" ]]

	# Verify output is sorted by first field
	local prev=0 sorted=1
	while read -r start rest; do
		if [[ "$start" -lt "$prev" ]]; then
			sorted=0
			break
		fi
		prev="$start"
	done < "$outfile"
	[[ "$sorted" -eq 1 ]]
}

@test "geoip_build_ipdb: uses bulk tarball when available" {
	local bulk_called=0
	_geoip_download_ipdeny_bulk() {
		local dir="$1"
		bulk_called=1
		printf '192.0.2.0/24\n' > "$dir/XX.zone"
		printf '198.51.100.0/24\n' > "$dir/YY.zone"
		return 0
	}
	# Per-country should not be needed for bulk-provided CCs
	geoip_download() { return 1; }

	local outfile="$TEST_TMPDIR/bulk_build.ipdb"
	geoip_build_ipdb "$outfile" 1
	[[ "$bulk_called" -eq 1 ]]
	[[ -f "$outfile" ]]
}

@test "geoip_build_ipdb: falls back to per-country when bulk fails" {
	_geoip_download_ipdeny_bulk() { return 1; }
	geoip_download() {
		local cc="$1" _family="$2" output="$3"
		case "$cc" in
			US) printf '198.51.100.0/24\n' > "$output"; return 0 ;;
			*) return 1 ;;
		esac
	}

	local outfile="$TEST_TMPDIR/fallback_build.ipdb"
	geoip_build_ipdb "$outfile" 1
	# If build succeeded with bulk disabled, per-country must have been used
	[[ -f "$outfile" ]]
	# Verify US range is present in output (came from per-country download)
	run geoip_ip_lookup "198.51.100.1" "$outfile"
	[[ "$status" -eq 0 ]]
	[[ "$output" == "US" ]]
}

@test "geoip_build_ipdb: sets _GEOIP_BUILD_COUNT and _GEOIP_BUILD_RANGES" {
	_geoip_download_ipdeny_bulk() { return 1; }
	geoip_download() {
		local cc="$1" _family="$2" output="$3"
		case "$cc" in
			US) printf '198.51.100.0/24\n' > "$output"; return 0 ;;
			CN) printf '192.0.2.0/24\n' > "$output"; return 0 ;;
			*) return 1 ;;
		esac
	}

	local outfile="$TEST_TMPDIR/count_build.ipdb"
	geoip_build_ipdb "$outfile" 1
	[[ "$_GEOIP_BUILD_COUNT" -eq 2 ]]
	[[ "$_GEOIP_BUILD_RANGES" -eq 2 ]]
	[[ "$_GEOIP_BUILD_FAIL" -gt 0 ]]
}

@test "geoip_build_ipdb: aborts when below min_ranges" {
	_geoip_download_ipdeny_bulk() { return 1; }
	geoip_download() {
		local cc="$1" _family="$2" output="$3"
		case "$cc" in
			US) printf '198.51.100.0/24\n' > "$output"; return 0 ;;
			*) return 1 ;;
		esac
	}

	local outfile="$TEST_TMPDIR/min_build.ipdb"
	run geoip_build_ipdb "$outfile" 1000
	[[ "$status" -eq 1 ]]
	[[ "$output" == *"only"*"ranges"* ]]
}

@test "geoip_build_ipdb: empty OUTPUT returns 1" {
	run geoip_build_ipdb ""
	[[ "$status" -eq 1 ]]
	[[ "$output" == *"OUTPUT required"* ]]
}

@test "geoip_build_ipdb: output is usable by geoip_ip_lookup" {
	_geoip_download_ipdeny_bulk() { return 1; }
	geoip_download() {
		local cc="$1" _family="$2" output="$3"
		case "$cc" in
			US) printf '198.51.100.0/24\n' > "$output"; return 0 ;;
			CN) printf '192.0.2.0/24\n' > "$output"; return 0 ;;
			*) return 1 ;;
		esac
	}

	local outfile="$TEST_TMPDIR/roundtrip.ipdb"
	geoip_build_ipdb "$outfile" 1

	# Look up an IP in the built database
	run geoip_ip_lookup "198.51.100.50" "$outfile"
	[[ "$status" -eq 0 ]]
	[[ "$output" == "US" ]]

	run geoip_ip_lookup "192.0.2.1" "$outfile"
	[[ "$status" -eq 0 ]]
	[[ "$output" == "CN" ]]

	# IP not in any range
	run geoip_ip_lookup "8.8.8.8" "$outfile"
	[[ "$status" -eq 1 ]]
}

@test "geoip_build_ipdb: cleans up temp directory on success" {
	_geoip_download_ipdeny_bulk() { return 1; }
	geoip_download() {
		local cc="$1" _family="$2" output="$3"
		case "$cc" in
			US) printf '198.51.100.0/24\n' > "$output"; return 0 ;;
			*) return 1 ;;
		esac
	}

	local outfile="$TEST_TMPDIR/cleanup.ipdb"
	geoip_build_ipdb "$outfile" 1

	# No leftover build directories
	local leftover
	leftover=$(find "$TEST_TMPDIR" -name "cleanup.ipdb.build-*" -type d 2>/dev/null | wc -l)
	[[ "$leftover" -eq 0 ]]
}

@test "geoip_build_ipdb: cleans up temp directory on failure" {
	_geoip_download_ipdeny_bulk() { return 1; }
	geoip_download() { return 1; }

	local outfile="$TEST_TMPDIR/fail_cleanup.ipdb"
	run geoip_build_ipdb "$outfile" 1000
	[[ "$status" -eq 1 ]]

	local leftover
	leftover=$(find "$TEST_TMPDIR" -name "fail_cleanup.ipdb.build-*" -type d 2>/dev/null | wc -l)
	[[ "$leftover" -eq 0 ]]
}
