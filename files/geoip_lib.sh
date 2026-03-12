#!/bin/bash
#
# geoip_lib.sh — GeoIP Metadata Library 1.0.0
###
# Copyright (C) 2026 R-fx Networks <proj@rfxn.com>
#                     Ryan MacDonald <ryan@rfxn.com>
#
#    This program is free software; you can redistribute it and/or modify
#    it under the terms of the GNU General Public License as published by
#    the Free Software Foundation; either version 2 of the License, or
#    (at your option) any later version.
#
#    This program is distributed in the hope that it will be useful,
#    but WITHOUT ANY WARRANTY; without even the implied warranty of
#    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#    GNU General Public License for more details.
#
#    You should have received a copy of the GNU General Public License
#    along with this program; if not, write to the Free Software
#    Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA
###
#
# Shared GeoIP metadata library for rfxn projects.
# Source this file to access country name, continent, and code validation functions.
# No project-specific code — all behavior controlled via variables.

# Source guard — safe for repeated sourcing
# shellcheck disable=SC2154
[[ -n "${_GEOIP_LIB_LOADED:-}" ]] && return 0 2>/dev/null
_GEOIP_LIB_LOADED=1

# shellcheck disable=SC2034
GEOIP_LIB_VERSION="1.0.0"

# ---------------------------------------------------------------------------
# Module-level continent CC lists (ISO 3166 assignments per UN geoscheme)
# Defined once, used by geoip_cc_continent() and geoip_expand_codes().
# Set at source time — inherited by subshells, never modified after init.
# ---------------------------------------------------------------------------
_GEOIP_CC_AF="AO,BF,BI,BJ,BW,CD,CF,CG,CI,CM,CV,DJ,DZ,EG,EH,ER,ET,GA,GH,GM,GN,GQ,GW,KE,KM,LR,LS,LY,MA,MG,ML,MR,MU,MW,MZ,NA,NE,NG,RE,RW,SC,SD,SH,SL,SN,SO,SS,ST,SZ,TD,TG,TN,TZ,UG,YT,ZA,ZM,ZW"
_GEOIP_CC_AS="AE,AF,AM,AZ,BD,BH,BN,BT,CN,CY,GE,HK,ID,IL,IN,IQ,IR,JO,JP,KG,KH,KP,KR,KW,KZ,LA,LB,LK,MM,MN,MO,MV,MY,NP,OM,PH,PK,PS,QA,SA,SG,SY,TH,TJ,TL,TM,TR,TW,UZ,VN,YE"
_GEOIP_CC_EU="AD,AL,AT,AX,BA,BE,BG,BY,CH,CZ,DE,DK,EE,ES,FI,FO,FR,GB,GG,GI,GR,HR,HU,IE,IM,IS,IT,JE,LI,LT,LU,LV,MC,MD,ME,MK,MT,NL,NO,PL,PT,RO,RS,RU,SE,SI,SK,SM,UA,VA,XK"
_GEOIP_CC_NA="AG,AI,AW,BB,BL,BM,BQ,BS,BZ,CA,CR,CU,CW,DM,DO,GD,GL,GP,GT,HN,HT,JM,KN,KY,LC,MF,MQ,MS,MX,NI,PA,PM,PR,SV,SX,TC,TT,US,VC,VG,VI"
_GEOIP_CC_SA="AR,BO,BR,CL,CO,EC,FK,GF,GY,PE,PY,SR,UY,VE"
_GEOIP_CC_OC="AS,AU,CK,FJ,FM,GU,KI,MH,MP,NC,NF,NR,NU,NZ,PF,PG,PN,PW,SB,TK,TO,TV,VU,WF,WS"

# ---------------------------------------------------------------------------
# geoip_cc_name — Map ISO 3166-1 alpha-2 country code to country name.
# Falls back to bare code for uncommon/unrecognized countries.
# Args: cc (2-letter uppercase code)
# Prints: country name string (or bare code on unknown)
# ---------------------------------------------------------------------------
geoip_cc_name() {
	local cc="$1"
	case "$cc" in
		AD) echo "Andorra" ;; AE) echo "UAE" ;; AF) echo "Afghanistan" ;;
		AG) echo "Antigua & Barbuda" ;; AL) echo "Albania" ;; AM) echo "Armenia" ;;
		AO) echo "Angola" ;; AR) echo "Argentina" ;; AT) echo "Austria" ;;
		AU) echo "Australia" ;; AZ) echo "Azerbaijan" ;; BA) echo "Bosnia" ;;
		BB) echo "Barbados" ;; BD) echo "Bangladesh" ;; BE) echo "Belgium" ;;
		BF) echo "Burkina Faso" ;; BG) echo "Bulgaria" ;; BH) echo "Bahrain" ;;
		BI) echo "Burundi" ;; BJ) echo "Benin" ;; BN) echo "Brunei" ;;
		BO) echo "Bolivia" ;; BR) echo "Brazil" ;; BS) echo "Bahamas" ;;
		BT) echo "Bhutan" ;; BW) echo "Botswana" ;; BY) echo "Belarus" ;;
		BZ) echo "Belize" ;; CA) echo "Canada" ;; CD) echo "DR Congo" ;;
		CF) echo "Central African Republic" ;; CG) echo "Congo" ;;
		CH) echo "Switzerland" ;; CI) echo "Ivory Coast" ;; CL) echo "Chile" ;;
		CM) echo "Cameroon" ;; CN) echo "China" ;; CO) echo "Colombia" ;;
		CR) echo "Costa Rica" ;; CU) echo "Cuba" ;; CV) echo "Cape Verde" ;;
		CY) echo "Cyprus" ;; CZ) echo "Czech Republic" ;; DE) echo "Germany" ;;
		DJ) echo "Djibouti" ;; DK) echo "Denmark" ;; DM) echo "Dominica" ;;
		DO) echo "Dominican Republic" ;; DZ) echo "Algeria" ;; EC) echo "Ecuador" ;;
		EE) echo "Estonia" ;; EG) echo "Egypt" ;; ER) echo "Eritrea" ;;
		ES) echo "Spain" ;; ET) echo "Ethiopia" ;; FI) echo "Finland" ;;
		FJ) echo "Fiji" ;; FR) echo "France" ;; GA) echo "Gabon" ;;
		GB) echo "United Kingdom" ;; GE) echo "Georgia" ;; GH) echo "Ghana" ;;
		GR) echo "Greece" ;; GT) echo "Guatemala" ;; GN) echo "Guinea" ;;
		GW) echo "Guinea-Bissau" ;; GY) echo "Guyana" ;; HK) echo "Hong Kong" ;;
		HN) echo "Honduras" ;; HR) echo "Croatia" ;; HT) echo "Haiti" ;;
		HU) echo "Hungary" ;; ID) echo "Indonesia" ;; IE) echo "Ireland" ;;
		IL) echo "Israel" ;; IN) echo "India" ;; IQ) echo "Iraq" ;;
		IR) echo "Iran" ;; IS) echo "Iceland" ;; IT) echo "Italy" ;;
		JM) echo "Jamaica" ;; JO) echo "Jordan" ;; JP) echo "Japan" ;;
		KE) echo "Kenya" ;; KG) echo "Kyrgyzstan" ;; KH) echo "Cambodia" ;;
		KP) echo "North Korea" ;; KR) echo "South Korea" ;; KW) echo "Kuwait" ;;
		KZ) echo "Kazakhstan" ;; LA) echo "Laos" ;; LB) echo "Lebanon" ;;
		LK) echo "Sri Lanka" ;; LR) echo "Liberia" ;; LS) echo "Lesotho" ;;
		LT) echo "Lithuania" ;; LU) echo "Luxembourg" ;; LV) echo "Latvia" ;;
		LY) echo "Libya" ;; MA) echo "Morocco" ;; MC) echo "Monaco" ;;
		MD) echo "Moldova" ;; ME) echo "Montenegro" ;; MG) echo "Madagascar" ;;
		MK) echo "North Macedonia" ;; ML) echo "Mali" ;; MM) echo "Myanmar" ;;
		MN) echo "Mongolia" ;; MO) echo "Macau" ;; MR) echo "Mauritania" ;;
		MU) echo "Mauritius" ;; MV) echo "Maldives" ;; MW) echo "Malawi" ;;
		MX) echo "Mexico" ;; MY) echo "Malaysia" ;; MZ) echo "Mozambique" ;;
		NA) echo "Namibia" ;; NE) echo "Niger" ;; NG) echo "Nigeria" ;;
		NI) echo "Nicaragua" ;; NL) echo "Netherlands" ;; NO) echo "Norway" ;;
		NP) echo "Nepal" ;; NZ) echo "New Zealand" ;; OM) echo "Oman" ;;
		PA) echo "Panama" ;; PE) echo "Peru" ;; PG) echo "Papua New Guinea" ;;
		PH) echo "Philippines" ;; PK) echo "Pakistan" ;; PL) echo "Poland" ;;
		PR) echo "Puerto Rico" ;; PS) echo "Palestine" ;; PT) echo "Portugal" ;;
		PY) echo "Paraguay" ;; QA) echo "Qatar" ;; RO) echo "Romania" ;;
		RS) echo "Serbia" ;; RU) echo "Russia" ;; RW) echo "Rwanda" ;;
		SA) echo "Saudi Arabia" ;; SB) echo "Solomon Islands" ;;
		SC) echo "Seychelles" ;; SD) echo "Sudan" ;; SE) echo "Sweden" ;;
		SG) echo "Singapore" ;; SI) echo "Slovenia" ;; SK) echo "Slovakia" ;;
		SL) echo "Sierra Leone" ;; SN) echo "Senegal" ;; SO) echo "Somalia" ;;
		SR) echo "Suriname" ;; SS) echo "South Sudan" ;; SV) echo "El Salvador" ;;
		SY) echo "Syria" ;; SZ) echo "Eswatini" ;; TD) echo "Chad" ;;
		TG) echo "Togo" ;; TH) echo "Thailand" ;; TJ) echo "Tajikistan" ;;
		TL) echo "Timor-Leste" ;; TM) echo "Turkmenistan" ;; TN) echo "Tunisia" ;;
		TR) echo "Turkey" ;; TT) echo "Trinidad & Tobago" ;; TW) echo "Taiwan" ;;
		TZ) echo "Tanzania" ;; UA) echo "Ukraine" ;; UG) echo "Uganda" ;;
		US) echo "United States" ;; UY) echo "Uruguay" ;; UZ) echo "Uzbekistan" ;;
		VA) echo "Vatican City" ;; VE) echo "Venezuela" ;; VN) echo "Vietnam" ;;
		YE) echo "Yemen" ;; ZA) echo "South Africa" ;; ZM) echo "Zambia" ;;
		ZW) echo "Zimbabwe" ;; XK) echo "Kosovo" ;;
		*) echo "$cc" ;;
	esac
}

# ---------------------------------------------------------------------------
# geoip_cc_continent — Map ISO 3166-1 country code to continent shorthand.
# Uses module-level continent lists (no eval, case-based comma search).
# Args: cc (2-letter uppercase code)
# Prints: continent shorthand (@AF, @AS, @EU, @NA, @SA, @OC) or "unknown"
# ---------------------------------------------------------------------------
geoip_cc_continent() {
	local cc="$1"
	case ",$_GEOIP_CC_AF," in *,"$cc",*) echo "@AF"; return 0 ;; esac
	case ",$_GEOIP_CC_AS," in *,"$cc",*) echo "@AS"; return 0 ;; esac
	case ",$_GEOIP_CC_EU," in *,"$cc",*) echo "@EU"; return 0 ;; esac
	case ",$_GEOIP_CC_NA," in *,"$cc",*) echo "@NA"; return 0 ;; esac
	case ",$_GEOIP_CC_SA," in *,"$cc",*) echo "@SA"; return 0 ;; esac
	case ",$_GEOIP_CC_OC," in *,"$cc",*) echo "@OC"; return 0 ;; esac
	echo "unknown"
}

# ---------------------------------------------------------------------------
# geoip_continent_name — Map continent shorthand to full name.
# Args: continent shorthand (@AF, @AS, @EU, @NA, @SA, @OC)
# Prints: full name (e.g., "Africa") or passthrough on unknown
# ---------------------------------------------------------------------------
geoip_continent_name() {
	case "$1" in
		@AF) echo "Africa" ;; @AS) echo "Asia" ;; @EU) echo "Europe" ;;
		@NA) echo "North America" ;; @SA) echo "South America" ;; @OC) echo "Oceania" ;;
		*) echo "$1" ;;
	esac
}

# ---------------------------------------------------------------------------
# geoip_expand_codes — Expand continent shorthand to comma-separated CC list.
# Sets _GEOIP_VCC_CODES. Returns 1 for unknown continent.
# Args: continent shorthand (@AF, @AS, @EU, @NA, @SA, @OC)
# ---------------------------------------------------------------------------
geoip_expand_codes() {
	local input="$1"
	case "$input" in
		@AF) _GEOIP_VCC_CODES="$_GEOIP_CC_AF" ;;
		@AS) _GEOIP_VCC_CODES="$_GEOIP_CC_AS" ;;
		@EU) _GEOIP_VCC_CODES="$_GEOIP_CC_EU" ;;
		@NA) _GEOIP_VCC_CODES="$_GEOIP_CC_NA" ;;
		@SA) _GEOIP_VCC_CODES="$_GEOIP_CC_SA" ;;
		@OC) _GEOIP_VCC_CODES="$_GEOIP_CC_OC" ;;
		*) return 1 ;;
	esac
	return 0
}

# ---------------------------------------------------------------------------
# geoip_validate_cc — Validate ISO 3166-1 country code or continent shorthand.
# Sets: _GEOIP_VCC_TYPE ("country" or "continent"), _GEOIP_VCC_CODES (CC list)
# Accepts: XX (2-letter country code) or @XX (continent shorthand).
# Returns 1 on invalid input.
# ---------------------------------------------------------------------------
geoip_validate_cc() {
	local input="$1"
	local _vcc_cc='^[A-Z]{2}$'
	local _vcc_cont='^@[A-Z]{2}$'
	_GEOIP_VCC_TYPE=""
	_GEOIP_VCC_CODES=""
	if [[ "$input" =~ $_vcc_cc ]]; then
		_GEOIP_VCC_TYPE="country"
		_GEOIP_VCC_CODES="$input"
		return 0
	fi
	if [[ "$input" =~ $_vcc_cont ]]; then
		if geoip_expand_codes "$input"; then
			_GEOIP_VCC_TYPE="continent"
			return 0
		fi
	fi
	return 1
}
