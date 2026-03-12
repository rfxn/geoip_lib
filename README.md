# geoip_lib -- GeoIP Metadata Library for Bash

[![CI](https://github.com/rfxn/geoip_lib/actions/workflows/ci.yml/badge.svg)](https://github.com/rfxn/geoip_lib/actions/workflows/ci.yml)
[![Version](https://img.shields.io/badge/version-1.0.0-blue.svg)](https://github.com/rfxn/geoip_lib)
[![Bash](https://img.shields.io/badge/bash-4.1%2B-green.svg)](https://www.gnu.org/software/bash/)
[![License](https://img.shields.io/badge/license-GPL%20v2-orange.svg)](https://www.gnu.org/licenses/old-licenses/gpl-2.0.html)

A shared Bash library for GeoIP metadata operations: country name resolution,
continent mapping, continent-to-country expansion, and country code validation.
Source it into your script and call the functions -- no dependencies, no
subprocesses, no network access required for metadata operations.

Consumed by [BFD](https://github.com/rfxn/linux-brute-force-detection) and
[APF](https://github.com/rfxn/linux-firewall) via source inclusion.

```bash
source /opt/myapp/lib/geoip_lib.sh
geoip_cc_name "CN"        # => "China"
geoip_cc_continent "CN"   # => "@AS"
geoip_continent_name "@AS" # => "Asia"
```

## Features

- **Country name lookup** -- ISO 3166-1 alpha-2 to country name (~180 countries)
- **Continent mapping** -- country code to continent shorthand (@AF/@AS/@EU/@NA/@SA/@OC)
- **Continent expansion** -- shorthand to full comma-separated country code list
- **Code validation** -- country or continent format validation with typed output
- **Module-level data** -- continent lists defined once, no duplication across functions
- **Eval-free** -- case-based comma search replaces eval-based variable lookup
- **Bash 4.1+ compatible** -- no associative arrays, no bash 4.2+ features
- **Source guard** -- safe for repeated sourcing

## Quick Start

```bash
# Source the library
source /path/to/geoip_lib.sh

# Look up a country name
name=$(geoip_cc_name "US")
echo "$name"  # "United States"

# Get continent for a country
cont=$(geoip_cc_continent "BR")
echo "$cont"  # "@SA"

# Expand continent to country list
geoip_expand_codes "@EU"
echo "$_GEOIP_VCC_CODES"  # "AD,AL,AT,AX,BA,BE,..."

# Validate input (country or continent)
if geoip_validate_cc "@AF"; then
    echo "Type: $_GEOIP_VCC_TYPE"    # "continent"
    echo "Codes: $_GEOIP_VCC_CODES"  # "AO,BF,BI,..."
fi
```

## API Reference

### geoip_cc_name(CC)

Map a 2-letter ISO 3166-1 alpha-2 country code to its common name.

- **Args:** `CC` -- uppercase 2-letter country code
- **Output:** Prints country name to stdout; returns bare code for unrecognized input
- **Returns:** Always 0

```bash
geoip_cc_name "CN"   # "China"
geoip_cc_name "AE"   # "UAE"
geoip_cc_name "ZZ"   # "ZZ" (passthrough)
```

### geoip_cc_continent(CC)

Map a country code to its continent shorthand.

- **Args:** `CC` -- uppercase 2-letter country code
- **Output:** Prints continent shorthand (@AF, @AS, @EU, @NA, @SA, @OC) or "unknown"
- **Returns:** Always 0

```bash
geoip_cc_continent "US"   # "@NA"
geoip_cc_continent "ZA"   # "@AF"
geoip_cc_continent "ZZ"   # "unknown"
```

### geoip_continent_name(CONT)

Map a continent shorthand to its full name.

- **Args:** `CONT` -- continent shorthand (@AF, @AS, @EU, @NA, @SA, @OC)
- **Output:** Prints full name or passthrough for unrecognized input
- **Returns:** Always 0

```bash
geoip_continent_name "@EU"   # "Europe"
geoip_continent_name "@XX"   # "@XX" (passthrough)
```

### geoip_expand_codes(INPUT)

Expand a continent shorthand to a comma-separated list of country codes.

- **Args:** `INPUT` -- continent shorthand (@AF, @AS, @EU, @NA, @SA, @OC)
- **Sets:** `_GEOIP_VCC_CODES` -- comma-separated CC list
- **Returns:** 0 on success, 1 on unknown continent

```bash
geoip_expand_codes "@AF"
echo "$_GEOIP_VCC_CODES"  # "AO,BF,BI,BJ,..."
```

### geoip_validate_cc(INPUT)

Validate a country code or continent shorthand.

- **Args:** `INPUT` -- 2-letter country code (XX) or continent shorthand (@XX)
- **Sets:** `_GEOIP_VCC_TYPE` ("country" or "continent"), `_GEOIP_VCC_CODES` (CC list)
- **Returns:** 0 on valid input, 1 on invalid

For country codes, `_GEOIP_VCC_CODES` is set to the input code directly.
For continent shorthands, `_GEOIP_VCC_CODES` is set to the expanded CC list.

```bash
geoip_validate_cc "CN"
# _GEOIP_VCC_TYPE="country", _GEOIP_VCC_CODES="CN"

geoip_validate_cc "@EU"
# _GEOIP_VCC_TYPE="continent", _GEOIP_VCC_CODES="AD,AL,AT,..."
```

## Module Variables

After sourcing, these read-only variables are available:

| Variable | Description |
|----------|-------------|
| `GEOIP_LIB_VERSION` | Library version (semver) |
| `_GEOIP_CC_AF` | Africa country codes (comma-separated) |
| `_GEOIP_CC_AS` | Asia country codes (comma-separated) |
| `_GEOIP_CC_EU` | Europe country codes (comma-separated) |
| `_GEOIP_CC_NA` | North America country codes (comma-separated) |
| `_GEOIP_CC_SA` | South America country codes (comma-separated) |
| `_GEOIP_CC_OC` | Oceania country codes (comma-separated) |

## Consumer Integration

To use geoip_lib in your project:

1. Copy `files/geoip_lib.sh` to your project's internals directory
2. Source it early in your startup sequence:
   ```bash
   if [ -f "$_internals_dir/geoip_lib.sh" ]; then
       # shellcheck disable=SC1091
       . "$_internals_dir/geoip_lib.sh"
   fi
   ```
3. Call functions directly -- all output is via stdout or named variables

## Testing

```bash
# Run tests on Debian 12 (default)
make -C tests test

# Run on a specific OS
make -C tests test-rocky9

# Run on all supported OS targets
make -C tests test-all
```

## Requirements

- Bash 4.1+ (CentOS 6 compatible)
- No external dependencies for metadata functions

## License

GNU General Public License v2 -- see source file headers for details.
