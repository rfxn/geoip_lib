#!/usr/bin/env bats
# 01-metadata.bats — geoip_lib metadata function tests

load helpers/geoip-common

setup() {
	geoip_common_setup
}

teardown() {
	geoip_teardown
}

# ---------------------------------------------------------------------------
# Scaffold
# ---------------------------------------------------------------------------

@test "GEOIP_LIB_VERSION is set and follows semver" {
	[[ -n "$EXPECTED_VERSION" ]]
	local semver_pat='^[0-9]+\.[0-9]+\.[0-9]+$'
	[[ "$EXPECTED_VERSION" =~ $semver_pat ]]
}

@test "source guard prevents double-sourcing side effects" {
	local ver_before="$GEOIP_LIB_VERSION"
	# shellcheck disable=SC1091
	source "${PROJECT_ROOT}/files/geoip_lib.sh"
	[[ "$GEOIP_LIB_VERSION" == "$ver_before" ]]
}

@test "module-level continent variables are set after sourcing" {
	[[ -n "$_GEOIP_CC_AF" ]]
	[[ -n "$_GEOIP_CC_AS" ]]
	[[ -n "$_GEOIP_CC_EU" ]]
	[[ -n "$_GEOIP_CC_NA" ]]
	[[ -n "$_GEOIP_CC_SA" ]]
	[[ -n "$_GEOIP_CC_OC" ]]
}

# ---------------------------------------------------------------------------
# geoip_cc_name
# ---------------------------------------------------------------------------

@test "geoip_cc_name: CN returns China" {
	run geoip_cc_name "CN"
	[[ "$status" -eq 0 ]]
	[[ "$output" == "China" ]]
}

@test "geoip_cc_name: US returns United States" {
	run geoip_cc_name "US"
	[[ "$status" -eq 0 ]]
	[[ "$output" == "United States" ]]
}

@test "geoip_cc_name: AE returns UAE (abbreviated)" {
	run geoip_cc_name "AE"
	[[ "$status" -eq 0 ]]
	[[ "$output" == "UAE" ]]
}

@test "geoip_cc_name: BA returns Bosnia (abbreviated)" {
	run geoip_cc_name "BA"
	[[ "$status" -eq 0 ]]
	[[ "$output" == "Bosnia" ]]
}

@test "geoip_cc_name: CD returns DR Congo (abbreviated)" {
	run geoip_cc_name "CD"
	[[ "$status" -eq 0 ]]
	[[ "$output" == "DR Congo" ]]
}

@test "geoip_cc_name: GB returns United Kingdom" {
	run geoip_cc_name "GB"
	[[ "$status" -eq 0 ]]
	[[ "$output" == "United Kingdom" ]]
}

@test "geoip_cc_name: XK returns Kosovo" {
	run geoip_cc_name "XK"
	[[ "$status" -eq 0 ]]
	[[ "$output" == "Kosovo" ]]
}

@test "geoip_cc_name: unknown CC returns bare code (passthrough)" {
	run geoip_cc_name "ZZ"
	[[ "$status" -eq 0 ]]
	[[ "$output" == "ZZ" ]]
}

@test "geoip_cc_name: empty input returns empty string" {
	run geoip_cc_name ""
	[[ "$status" -eq 0 ]]
	[[ "$output" == "" ]]
}

# ---------------------------------------------------------------------------
# geoip_cc_continent
# ---------------------------------------------------------------------------

@test "geoip_cc_continent: CN maps to @AS (Asia)" {
	run geoip_cc_continent "CN"
	[[ "$status" -eq 0 ]]
	[[ "$output" == "@AS" ]]
}

@test "geoip_cc_continent: US maps to @NA (North America)" {
	run geoip_cc_continent "US"
	[[ "$status" -eq 0 ]]
	[[ "$output" == "@NA" ]]
}

@test "geoip_cc_continent: ZA maps to @AF (Africa)" {
	run geoip_cc_continent "ZA"
	[[ "$status" -eq 0 ]]
	[[ "$output" == "@AF" ]]
}

@test "geoip_cc_continent: DE maps to @EU (Europe)" {
	run geoip_cc_continent "DE"
	[[ "$status" -eq 0 ]]
	[[ "$output" == "@EU" ]]
}

@test "geoip_cc_continent: BR maps to @SA (South America)" {
	run geoip_cc_continent "BR"
	[[ "$status" -eq 0 ]]
	[[ "$output" == "@SA" ]]
}

@test "geoip_cc_continent: AU maps to @OC (Oceania)" {
	run geoip_cc_continent "AU"
	[[ "$status" -eq 0 ]]
	[[ "$output" == "@OC" ]]
}

@test "geoip_cc_continent: unknown CC returns 'unknown'" {
	run geoip_cc_continent "ZZ"
	[[ "$status" -eq 0 ]]
	[[ "$output" == "unknown" ]]
}

# ---------------------------------------------------------------------------
# geoip_continent_name
# ---------------------------------------------------------------------------

@test "geoip_continent_name: @AF returns Africa" {
	run geoip_continent_name "@AF"
	[[ "$status" -eq 0 ]]
	[[ "$output" == "Africa" ]]
}

@test "geoip_continent_name: @AS returns Asia" {
	run geoip_continent_name "@AS"
	[[ "$status" -eq 0 ]]
	[[ "$output" == "Asia" ]]
}

@test "geoip_continent_name: @EU returns Europe" {
	run geoip_continent_name "@EU"
	[[ "$status" -eq 0 ]]
	[[ "$output" == "Europe" ]]
}

@test "geoip_continent_name: @NA returns North America" {
	run geoip_continent_name "@NA"
	[[ "$status" -eq 0 ]]
	[[ "$output" == "North America" ]]
}

@test "geoip_continent_name: @SA returns South America" {
	run geoip_continent_name "@SA"
	[[ "$status" -eq 0 ]]
	[[ "$output" == "South America" ]]
}

@test "geoip_continent_name: @OC returns Oceania" {
	run geoip_continent_name "@OC"
	[[ "$status" -eq 0 ]]
	[[ "$output" == "Oceania" ]]
}

@test "geoip_continent_name: unknown passthrough returns input" {
	run geoip_continent_name "@XX"
	[[ "$status" -eq 0 ]]
	[[ "$output" == "@XX" ]]
}

@test "geoip_continent_name: arbitrary string passthrough" {
	run geoip_continent_name "foobar"
	[[ "$status" -eq 0 ]]
	[[ "$output" == "foobar" ]]
}

# ---------------------------------------------------------------------------
# geoip_expand_codes
# ---------------------------------------------------------------------------

@test "geoip_expand_codes: @AF returns 54+ comma-separated CCs" {
	geoip_expand_codes "@AF"
	# Count comma-separated entries
	local _save_ifs="$IFS"
	IFS=','
	# shellcheck disable=SC2206
	local codes=( $_GEOIP_VCC_CODES )
	IFS="$_save_ifs"
	[[ ${#codes[@]} -ge 54 ]]
}

@test "geoip_expand_codes: @AF includes ZA" {
	geoip_expand_codes "@AF"
	[[ ",$_GEOIP_VCC_CODES," == *",ZA,"* ]]
}

@test "geoip_expand_codes: @AS includes CN" {
	geoip_expand_codes "@AS"
	[[ ",$_GEOIP_VCC_CODES," == *",CN,"* ]]
}

@test "geoip_expand_codes: @EU includes DE" {
	geoip_expand_codes "@EU"
	[[ ",$_GEOIP_VCC_CODES," == *",DE,"* ]]
}

@test "geoip_expand_codes: @NA includes US" {
	geoip_expand_codes "@NA"
	[[ ",$_GEOIP_VCC_CODES," == *",US,"* ]]
}

@test "geoip_expand_codes: @SA includes BR" {
	geoip_expand_codes "@SA"
	[[ ",$_GEOIP_VCC_CODES," == *",BR,"* ]]
}

@test "geoip_expand_codes: @OC includes AU" {
	geoip_expand_codes "@OC"
	[[ ",$_GEOIP_VCC_CODES," == *",AU,"* ]]
}

@test "geoip_expand_codes: unknown continent returns 1" {
	run geoip_expand_codes "@XX"
	[[ "$status" -eq 1 ]]
}

@test "geoip_expand_codes: invalid string returns 1" {
	run geoip_expand_codes "INVALID"
	[[ "$status" -eq 1 ]]
}

@test "geoip_expand_codes: all six continents succeed" {
	for cont in @AF @AS @EU @NA @SA @OC; do
		geoip_expand_codes "$cont"
		[[ -n "$_GEOIP_VCC_CODES" ]]
	done
}

# ---------------------------------------------------------------------------
# geoip_validate_cc
# ---------------------------------------------------------------------------

@test "geoip_validate_cc: valid country code CN" {
	geoip_validate_cc "CN"
	[[ "$_GEOIP_VCC_TYPE" == "country" ]]
	[[ "$_GEOIP_VCC_CODES" == "CN" ]]
}

@test "geoip_validate_cc: valid country code US" {
	geoip_validate_cc "US"
	[[ "$_GEOIP_VCC_TYPE" == "country" ]]
	[[ "$_GEOIP_VCC_CODES" == "US" ]]
}

@test "geoip_validate_cc: valid continent @AF" {
	geoip_validate_cc "@AF"
	[[ "$_GEOIP_VCC_TYPE" == "continent" ]]
	[[ -n "$_GEOIP_VCC_CODES" ]]
	# Continent expansion includes African CCs
	[[ ",$_GEOIP_VCC_CODES," == *",ZA,"* ]]
}

@test "geoip_validate_cc: valid continent @EU" {
	geoip_validate_cc "@EU"
	[[ "$_GEOIP_VCC_TYPE" == "continent" ]]
	[[ ",$_GEOIP_VCC_CODES," == *",DE,"* ]]
}

@test "geoip_validate_cc: lowercase input fails" {
	run geoip_validate_cc "cn"
	[[ "$status" -eq 1 ]]
}

@test "geoip_validate_cc: three-letter code fails" {
	run geoip_validate_cc "USA"
	[[ "$status" -eq 1 ]]
}

@test "geoip_validate_cc: numeric input fails" {
	run geoip_validate_cc "12"
	[[ "$status" -eq 1 ]]
}

@test "geoip_validate_cc: empty input fails" {
	run geoip_validate_cc ""
	[[ "$status" -eq 1 ]]
}

@test "geoip_validate_cc: invalid continent @XX fails" {
	run geoip_validate_cc "@XX"
	[[ "$status" -eq 1 ]]
}

@test "geoip_validate_cc: country code sets _GEOIP_VCC_CODES directly (no expand)" {
	# Country branch: _GEOIP_VCC_CODES = input, not expansion result
	geoip_validate_cc "ZZ"
	[[ "$_GEOIP_VCC_TYPE" == "country" ]]
	[[ "$_GEOIP_VCC_CODES" == "ZZ" ]]
}

@test "geoip_validate_cc: clears state on failure" {
	# Set state from prior successful call
	geoip_validate_cc "US"
	[[ "$_GEOIP_VCC_TYPE" == "country" ]]
	# Failed call should clear
	run geoip_validate_cc "invalid"
	# After run (subshell), parent state is unchanged — test fresh call
	_GEOIP_VCC_TYPE="leftover"
	_GEOIP_VCC_CODES="leftover"
	geoip_validate_cc "invalid" || true
	[[ "$_GEOIP_VCC_TYPE" == "" ]]
	[[ "$_GEOIP_VCC_CODES" == "" ]]
}

# ---------------------------------------------------------------------------
# Cross-function integration
# ---------------------------------------------------------------------------

@test "geoip_cc_name + geoip_cc_continent roundtrip: China is in Asia" {
	local name
	name=$(geoip_cc_name "CN")
	[[ "$name" == "China" ]]
	local cont
	cont=$(geoip_cc_continent "CN")
	[[ "$cont" == "@AS" ]]
	local cont_name
	cont_name=$(geoip_continent_name "$cont")
	[[ "$cont_name" == "Asia" ]]
}

@test "geoip_expand_codes: all @AF CCs resolve to @AF via geoip_cc_continent" {
	geoip_expand_codes "@AF"
	local _save_ifs="$IFS"
	IFS=','
	# shellcheck disable=SC2206
	local codes=( $_GEOIP_VCC_CODES )
	IFS="$_save_ifs"
	# Spot-check first, last, and middle entries
	local first="${codes[0]}"
	local last="${codes[${#codes[@]}-1]}"
	local mid="${codes[28]}"
	local result
	result=$(geoip_cc_continent "$first")
	[[ "$result" == "@AF" ]]
	result=$(geoip_cc_continent "$last")
	[[ "$result" == "@AF" ]]
	result=$(geoip_cc_continent "$mid")
	[[ "$result" == "@AF" ]]
}

@test "geoip_validate_cc then geoip_cc_name: country path" {
	geoip_validate_cc "JP"
	[[ "$_GEOIP_VCC_TYPE" == "country" ]]
	local name
	name=$(geoip_cc_name "$_GEOIP_VCC_CODES")
	[[ "$name" == "Japan" ]]
}
