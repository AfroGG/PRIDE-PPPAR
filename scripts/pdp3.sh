#!/bin/bash

###############################################################################
##                                                                           ##
##  PURPOSE: GNSS PPP&PPP-AR data processing with PRIDE PPP-AR 2             ##
##                                                                           ##
##  AUTHOR : PRIDE LAB      pride@whu.edu.cn                                 ##
##                                                                           ##
##  VERSION: ver 2.2                                                         ##
##                                                                           ##
##  DATE   : Jun-06, 2022                                                    ##
##                                                                           ##
##              @ GNSS RESEARCH CENTER, WUHAN UNIVERSITY, 2022               ##
##                                                                           ##
##    Copyright (C) 2022 by Wuhan University                                 ##
##                                                                           ##
##    This program is free software: you can redistribute it and/or modify   ##
##    it under the terms of the GNU General Public License (version 3) as    ##
##    published by the Free Software Foundation.                             ##
##                                                                           ##
##    This program is distributed in the hope that it will be useful,        ##
##    but WITHOUT ANY WARRANTY; without even the implied warranty of         ##
##    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the          ##
##    GNU General Public License (version 3) for more details.               ##
##                                                                           ##
##    You should have received a copy of the GNU General Public License      ##
##    along with this program.  If not, see <https://www.gnu.org/licenses/>. ##
##                                                                           ##
###############################################################################

######################################################################
##                        Message Colors                            ##
######################################################################

readonly NC='\033[0m'
readonly RED='\033[0;31m'
readonly BLUE='\033[1;34m'
readonly CYAN='\033[0;36m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'

readonly MSGERR="${RED}error:$NC"
readonly MSGWAR="${YELLOW}warning:$NC"
readonly MSGINF="${BLUE}::$NC"
readonly MSGSTA="${BLUE}===>$NC"

######################################################################
##                        Basic Settings                            ##
######################################################################

shopt -s extglob                        # Enable Extendded Globbing

readonly DEBUG=NO                       # YES/NO (uppercase!)
readonly OFFLINE=NO                     # OFFLINE=YES will overwrite USECACHE=NO
readonly USECACHE=YES

readonly SCRIPT_NAME="pdp3"
readonly VERSION_NUM="2.2"

######################################################################
##                     Funciton definations                         ##
######################################################################

main() {
    args=$(ParseCmdArgs "$@") || exit 1
    CheckExecutables          || exit 1

    local rnxo_file=$(echo "$args" | sed -n 1p)       # absolute path
    local ctrl_path=$(echo "$args" | sed -n 2p)       # absolute path
    local ctrl_file=$(echo "$args" | sed -n 3p)       # temporary config
    local    date_s=$(echo "$args" | sed -n 4p)       # yyyy-mm-dd
    local    hour_s=$(echo "$args" | sed -n 5p)       # hh:mi:ss
    local    date_e=$(echo "$args" | sed -n 6p)       # yyyy-mm-dd
    local    hour_e=$(echo "$args" | sed -n 7p)       # hh:mi:ss
    local        AR=$(echo "$args" | sed -n 8p)       # A/Y/N, upper case

    local interval=$(get_ctrl "$ctrl_file" "Interval")
    local site=$(grep "^ .... [KSF]" "$ctrl_file" | cut -c 2-5)
    local mode=$(grep "^ .... [KSF]" "$ctrl_file" | cut -c 7-7)

    local rinex_dir=$(dirname  "$rnxo_file")
    local rnxo_name=$(basename "$rnxo_file")

    # Output processing infomation
    echo -e "$MSGINF Processing time range: $date_s $hour_s <==> $date_e $hour_e"
    echo -e "$MSGINF Processing interval: $interval"
    echo -e "$MSGINF Site name: $site"
    echo -e "$MSGINF Positioning mode: $mode"
    echo -e "$MSGINF AR switch: $AR"
    echo -e "$MSGINF Configuration file: $ctrl_path"
    echo -e "$MSGINF RINEX observation file: $rnxo_file"

    local doy_s=$(date -d "$date_s" +"%j")
    local doy_e=$(date -d "$date_e" +"%j")
    local ymd_s=($(echo "$date_s" | tr '-' ' '))
    local ymd_e=($(echo "$date_e" | tr '-' ' '))
    local mjd_s=$(ymd2mjd ${ymd_s[*]})
    local mjd_e=$(ymd2mjd ${ymd_e[*]})

    local mjd_span=$[$mjd_e-$mjd_s]
    local proj_dir=$(pwd)
    if [ $mjd_span -lt 0 ]; then
        echo -e "$MSGERR illegal time span: from $mjd_s to $mjd_e"
        exit 1
    elif [ $mjd_span -eq 0 ]; then
        local work_dir="$proj_dir/$ymd_s/$doy_s"
        mkdir -p "$work_dir" && cd "$work_dir"
        if [ $? -eq 0 ]; then
            ProcessSingleDay "$rnxo_file" "$ctrl_file" "$date_s" "$hour_s" "$date_e" "$hour_e" "$AR" \
                || echo -e "$MSGERR from $ymd_s $doy_s to $ymd_e $doy_e processing failed"
        else
            echo -e "$MSGERR no such directory: $work_dir"
        fi
    elif [ $mjd_span -lt 5 ]; then
        local work_dir="$proj_dir/$ymd_s/$doy_s-$doy_e"
        mkdir -p "$work_dir" && cd "$work_dir"
        if [ $? -eq 0 ]; then
            ProcessMultiDays "$rnxo_file" "$ctrl_file" "$date_s" "$hour_s" "$date_e" "$hour_e" "$AR" \
                || echo -e "$MSGERR from $ymd_s $doy_s to $ymd_e $doy_e processing failed"
        else
            echo -e "$MSGERR no such directory: $work_dir"
        fi
    elif [ $mjd_span -gt 5 ]; then
        echo -e "$MSGERR too long time span (> 5 days): from $mjd_s to $mjd_e"
        exit 1
    fi
}

ParseCmdArgs() { # purpose : parse command line into arguments
                 # usage   : ParseCmdArgs "$@"
    if [ $# -le 0 ]; then
        PRIDE_PPPAR_HELP
        >&2 echo ""
        PRIDE_PPPAR_INFO
        exit 1
    fi

    readonly local SITE_REGEX="^[[:alpha:]0-9]{4}$"
    readonly local PNUM_REGEX="^[+.]?[0-9]+([.][0-9]+)?$"

    local i s t iarg time_sec
    local rnxo_file ctrl_path ctrl_file ymd_s hms_s ymd_e hms_e site mode interval AR
    local avail_sys edt_opt ztd_opt htg_opt ion_opt tide_mask lam_opt pco_opt
    local gnss_mask map_opt ztdl ztdp htgp eloff

    local last_arg=${@: -1}
    case $last_arg in
    -V | --version )
        PRIDE_PPPAR_INFO && exit 1 ;;
    -H | --help )
        PRIDE_PPPAR_HELP && exit 1 ;;
    -* )
        >&2 echo -e "$MSGERR invalid argument (the last argument should be obs-file): $last_arg"
        >&2 echo -e "$MSGINF type ‘pdp3 -H’ or ‘pdp3 --help’ for more information"
        exit 1
    esac

    # Parse path of observation file
    if [ -e $last_arg ]; then
        rnxo_file="$(readlink -f $last_arg)"
    else
        >&2 echo -e "$MSGERR RINEX observation file doesn't exist: $last_arg"
        exit 1
    fi

    # Parse other options
    for iarg in $(seq 1 $[$#-1]); do
        case $1 in
        -?(-)+([-[:alnum:]_]) )
            case $1 in
            ## Version & Help
            -V | --version )
                PRIDE_PPPAR_INFO && exit 1 ;;
            -H | --help )
                PRIDE_PPPAR_HELP && exit 1 ;;
            ## Time setting
            -s | --start )
                [ -z "$ymd_s" ] && [ -z "$hms_s" ]              || throw_conflict_opt "$1"
                check_optional_arg "$2" "$last_arg"             || throw_require_arg  "$1"
                local time=($(echo $2 | tr '/:-' ' '))
                case ${#time[@]} in
                2 ) ymd_s=$(ydoy2ymd ${time[@]}  | awk '{printf("%04d-%02d-%02d\n",$1,$2,$3)}') ;;
                3 ) ymd_s=$(echo    "${time[@]}" | awk '{printf("%04d-%02d-%02d\n",$1,$2,$3)}') ;;
                * ) throw_invalid_arg "start date" "$2" ;;
                esac
                shift 1
                if check_optional_arg "$2" "$last_arg"; then
                    local time=($(echo $2 | tr '/:-' ' '))
                    [ ${#time[@]} -eq 3 ] \
                        && hms_s=$(echo "${time[@]}" | awk '{printf("%02d:%02d:%05.2f\n",$1,$2,$3)}') \
                        && [ ${time[0]%.*} -ge 0 -a ${time[0]%.*} -le 23 ] \
                        && [ ${time[1]%.*} -ge 0 -a ${time[1]%.*} -le 59 ] \
                        && [ ${time[2]%.*} -ge 0 -a ${time[2]%.*} -le 59 ] \
                        || throw_invalid_arg "start time" "$2"
                    shift 1
                fi ;;
            -e | --end )
                [ -z "$ymd_e" ] && [ -z "$hms_e" ]              || throw_conflict_opt "$1"
                check_optional_arg "$2" "$last_arg"             || throw_require_arg  "$1"
                local time=($(echo $2 | tr '/:-' ' '))
                case ${#time[@]} in
                2 ) ymd_e=$(ydoy2ymd ${time[@]}  | awk '{printf("%04d-%02d-%02d\n",$1,$2,$3)}') ;;
                3 ) ymd_e=$(echo    "${time[@]}" | awk '{printf("%04d-%02d-%02d\n",$1,$2,$3)}') ;;
                * ) throw_invalid_arg "end date" "$2" ;;
                esac
                shift 1
                if check_optional_arg "$2" "$last_arg"; then
                    local time=($(echo $2 | tr '/:-' ' '))
                    [ ${#time[@]} -eq 3 ] \
                        && hms_e=$(echo "${time[@]}" | awk '{printf("%02d:%02d:%05.2f\n",$1,$2,$3)}') \
                        && [ ${time[0]%.*} -ge 0 -a ${time[0]%.*} -le 23 ] \
                        && [ ${time[1]%.*} -ge 0 -a ${time[1]%.*} -le 59 ] \
                        && [ ${time[2]%.*} -ge 0 -a ${time[2]%.*} -le 59 ] \
                        || throw_invalid_arg "end time" "$2"
                    shift 1
                fi ;;
            ## General setting
            -cfg | --config )
                [ -z "$ctrl_path" ]                             || throw_conflict_opt "$1"
                check_optional_arg "$2" "$last_arg"             || throw_require_arg  "$1"
                [ -e "$2" ] && ctrl_path="$(readlink -f $2)"
                if [ $? -ne 0 ]; then
                    >&2 echo -e "$MSGERR PRIDE PPP-AR configuration file doesn't exist: $2"
                    exit 1
                fi
                shift 1 ;;
            -sys | --system )
                [ -z "$avail_sys" ]                             || throw_conflict_opt "$1"
                check_optional_arg "$2" "$last_arg"             || throw_require_arg  "$1"
                avail_sys=($(sed "s/C/23/;s/./& /g" <<< "$2"))  || throw_invalid_arg "GNSS" "$2"
                gnss_mask=("G" "R" "E" "2" "3" "J")
                for s in ${avail_sys[@]}; do
                    case ${s^^} in
                    @(G|R|E|2|3|J) ) gnss_mask=("${gnss_mask[@]/$s}");;
                    * ) throw_invalid_arg "GNSS" "$s" ;;
                    esac
                done
                shift 1 ;;
            -n | --site )
                [ -z "$site" ]                                  || throw_conflict_opt "$1"
                check_optional_arg "$2" "$last_arg"             || throw_require_arg  "$1"
                [[ "$2" =~ $SITE_REGEX ]] && site="$2"          || throw_invalid_arg "site name" "$2"
                shift 1 ;;
            -m | --mode )
                [ -z "$mode" ]                                  || throw_conflict_opt "$1"
                check_optional_arg "$2" "$last_arg"             || throw_require_arg  "$1"
                case $2 in
                "s" | "S" ) mode="S" ;;
                "k" | "K" ) mode="K" ;;
                "f" | "F" ) mode="F" ;;
                * ) throw_invalid_arg "mode" "$2"
                esac
                shift 1 ;;
            -i | --interval )
                [ -z "$interval" ]                              || throw_conflict_opt "$1"
                check_optional_arg "$2" "$last_arg"             || throw_require_arg  "$1"
                if [[ $2 =~ $PNUM_REGEX ]]               && \
                   [[ $(echo "0.02 <= $2" | bc) -eq 1 ]] && \
                   [[ $(echo "$2 <= 30.0" | bc) -eq 1 ]]; then
                    interval="$2"
                else
                    throw_invalid_arg "interval" "$2"
                fi
                shift 1 ;;
            -f | --float )
                [ -z "$AR" ] && AR="N"                          || throw_conflict_opt "$1"
                ;;
            ## Advanced settings
            -aoff | --wapc-off )
                [ -z "$pco_opt" ]                               || throw_conflict_opt "$1"
                pco_opt="NO"
                ;;
            -c | --cutoff-elev )
                [ -z "$eloff" ]                                 || throw_conflict_opt "$1"
                check_optional_arg "$2" "$last_arg"             || throw_require_arg  "$1"
                if [[ $2 =~ $PNUM_REGEX ]]               && \
                   [[ $(echo "0.00 <= $2" | bc) -eq 1 ]] && \
                   [[ $(echo "$2 <= 60.0" | bc) -eq 1 ]]; then
                    eloff="$2"
                else
                    throw_invalid_arg "cutoff elevation" "$2"
                fi
                shift 1 ;;
            -l | --loose-edit )
                [ -z "$edt_opt" ]                               || throw_conflict_opt "$1"
                edt_opt="NO"
                ;;
            -hion | --high-ion )
                [ -z "$ion_opt" ]                               || throw_conflict_opt "$1"
                ion_opt="YES"
                ;;
            -hoff | --htg-off )
                [ -z "$htg_off" ]                               || throw_conflict_opt "$1"
                htg_opt="NON"
                ;;
            -p | --mapping-func )
                [ -z "$map_opt" ]                               || throw_conflict_opt "$1"
                check_optional_arg "$2" "$last_arg"             || throw_require_arg  "$1"
                case ${2^^} in
                "G" |         "GMF" ) map_opt="GMF" ;;
                "N" | "NIE" | "NMF" ) map_opt="NIE" ;;
                "1" | "V1"  | "VM1" ) map_opt="VM1" ;;
                "3" | "V3"  | "VM3" ) map_opt="VM3" ;;
                * ) throw_invalid_arg "mapping function" "$2"
                esac
                shift 1 ;;
            -toff | --tide-off )
                [ -z "$tide_mask" ]                             || throw_conflict_opt "$1"
                check_optional_arg "$2" "$last_arg"             || throw_require_arg  "$1"
                tide_mask=($(sed "s/./& /g" <<< "$2"))          || throw_invalid_arg "tide model" "$2"
                for t in ${tide_mask[@]}; do
                    case ${t^^} in
                    @(S|O|P) ) continue ;;
                    * ) throw_invalid_arg "tide model" "$t" ;;
                    esac
                done
                shift 1 ;;
            -x | --fix-method )
                [ -z "$lam_opt" ]                               || throw_conflict_opt "$1"
                check_optional_arg "$2" "$last_arg"             || throw_require_arg  "$1"
                case ${2^^} in
                "1" ) lam_opt="NO"  ;;
                "2" ) lam_opt="YES" ;;
                * ) throw_invalid_arg "fixing method" "$2"
                esac
                shift 1 ;;
            -z | --ztd )
                [ -z "$ztd_opt" ]                               || throw_conflict_opt "$1"
                check_optional_arg "$2" "$last_arg"             || throw_require_arg  "$1"
                case ${2:0:1} in
                "p" | "P" )
                    ztd_opt="PWC" && ztdl=${2:1} && ztdl=${ztdl##*:}
                    [ -n "$ztdl" ] || ztdl="60"
                    if [[ $ztdl =~ $PNUM_REGEX ]]              && \
                       [[ $(echo "60 <= $ztdl" | bc) -eq 1 ]]; then
                        ztd_opt="${ztd_opt}:$ztdl"
                    else
                        throw_invalid_arg "ZTD piece length" "$ztdl"
                    fi
                    ;;
                "s" | "S" )
                    ztd_opt="STO"
                    ;;
                * ) throw_invalid_arg "ZTD model" "$2"
                esac
                shift 1
                if check_optional_arg "$2" "$last_arg"; then
                    if [[ $2 =~ $PNUM_REGEX ]]               && \
                       [[ $(echo "0.00 <= $2" | bc) -eq 1 ]] && \
                       [[ $(echo "$2 <= 10.0" | bc) -eq 1 ]]; then
                        ztdp="$2"
                    else
                        throw_invalid_arg "ZTD process noise" "$2"
                    fi
                    shift 1
                fi ;;
            ## End
            * )
                [[ $1 == $last_arg ]] && break
                throw_invalid_opt $1 ;;
            esac
            shift 1 ;;
        "" )
            break ;;
        ** )
            [[ $1 == $last_arg ]] && break
            throw_invalid_opt $1 ;;
        esac
    done

    # Use default config file
    local config_template_path="$(dirname $(which pdp3))/config_template"
    [ -n "$ctrl_path" ] || ctrl_path="$config_template_path"

    if [ ! -e "$ctrl_path" ]; then
        >&2 echo -e "$MSGERR PRIDE PPP-AR configuration file doesn't exist: $ctrl_path"
        exit 1
    fi

    local opt_lin=$(grep "^ .... [KSFX]" "$ctrl_path")
    local opt_num=$(echo "$opt_lin" | wc -l)
    if [ $opt_num -ne 1 ]; then
        [ $opt_num -eq 0 ] && >&2 echo -e "$MSGERR no option line to be processed: $ctrl_path"
        [ $opt_num -gt 1 ] && >&2 echo -e "$MSGERR more than one option line to be processed: $ctrl_path"
        exit 1
    fi

    # Create temporary config file
    ctrl_file=$(mktemp -u | sed "s/tmp\./config\./")
    cp -f "$ctrl_path" "$ctrl_file" && chmod 644 "$ctrl_file"
    if [ $? -ne 0 ]; then
        >&2 echo -e "$MSGERR failed to create temporary config file: $ctrl_file"
        exit 1
    fi

    # Try getting position mode option from config file
    if [ -z "$mode" ]; then
        if [ -n "$ctrl_path" ]; then
            mode=$(echo "$opt_lin" | cut -c 7-7)
            [ "$mode" == "X" ] && mode="K"
        fi
    fi

    [ -n "$mode" ] && mode=${mode^^} || mode="K"

    # Default as MARKER NAME or the name of observation file
    if [ -z "$site" ]; then
        site=$(grep "MARKER NAME" "$rnxo_file" | awk '{print substr($0,0,4)}')
        if [[ ! "$site" =~ $SITE_REGEX ]]; then
             local rnxo_name=$(basename "$rnxo_file")
             if [[ $rnxo_name =~ ^[[:alpha:]0-9]{9}_.+O\.(rnx|RNX)$ ]] || \
                [[ $rnxo_name =~ ^[[:alpha:]0-9]{4}[0-9]{3}.+\.[0-9]{2}(o|O)$ ]]; then
                 site=${rnxo_name:0:4}
             fi
        fi
        if [ -z "$site" ]; then
            site=$(echo "$opt_lin" | cut -c 2-5)
            [ "$site" == "xxxx" ] && site=""
        fi
        if [[ ! "$site" =~ $SITE_REGEX ]]; then
             >&2 echo -e "$MSGERR no valid site name from command or observation file"
             >&2 echo -e "$MSGINF please input site name with option ‘-n’ or ‘--site’"
             exit 1
        fi
    fi

    [ -n "$site" ] && site=${site,,} || site="xxxx"

    # Default as the first epoch of observation file
    if [ -z "$ymd_s" ] || [ -z "$hms_s" ]; then
        [ -z "$time_sec" ] && time_sec=$(grep -E "^(>| [ 0-9][0-9] [ 0-1][0-9] )" "$rnxo_file")
        local time=$(echo "$time_sec" | head -1)
        if [ -n "$time" ]; then
            if [[ $time =~ ^\> ]]; then
                [ -z "$ymd_s" ] && ymd_s=$(echo "$time" | awk '{printf("%04d-%02d-%02d\n",$2,$3,$4)}')
                [ -z "$hms_s" ] && hms_s=$(echo "$time" | awk '{printf("%02d:%02d:%05.2f\n",$5,$6,$7)}')
            else
                [ -z "$ymd_s" ] && ymd_s=$(echo "$time" | awk '{yr=$1+2000;if($1>80)yr-=100;printf("%04d-%02d-%02d\n",yr,$2,$3)}')
                [ -z "$hms_s" ] && hms_s=$(echo "$time" | awk '{printf("%02d:%02d:%05.2f\n",$4,$5,$6)}')
            fi
        else
            >&2 echo -e "$MSGERR no valid start time from command or observation file"
            >&2 echo -e "$MSGINF please input start time with option ‘-s’ or ‘--start’"
            exit 1
        fi
    fi

    # Default as the last epoch of observation file
    if [ -z "$ymd_e" ] || [ -z "$hms_e" ]; then
        [ -z "$time_sec" ] && time_sec=$(grep -E "^(>| [ 0-9][0-9] [ 0-1][0-9] )" "$rnxo_file")
        local time=$(echo "$time_sec" | tail -1)
        if [ -n "$time" ]; then
            if [[ $time =~ ^\> ]]; then
                [ -z "$ymd_e" ] && ymd_e=$(echo "$time" | awk '{printf("%04d-%02d-%02d\n",$2,$3,$4)}')
                [ -z "$hms_e" ] && hms_e=$(echo "$time" | awk '{printf("%02d:%02d:%05.2f\n",$5,$6,$7)}')
            else
                [ -z "$ymd_e" ] && ymd_e=$(echo "$time" | awk '{yr=$1+2000;if($1>80)yr-=100;printf("%04d-%02d-%02d\n",yr,$2,$3)}')
                [ -z "$hms_e" ] && hms_e=$(echo "$time" | awk '{printf("%02d:%02d:%05.2f\n",$4,$5,$6)}')
            fi
        else
            >&2 echo -e "$MSGERR no valid end time from command or observation file"
            >&2 echo -e "$MSGINF please input end time with option ‘-e’ or ‘--end’"
            exit 1
        fi
    fi

    # Check time span
    local sec_s=$(date -d "$ymd_s $hms_s" +"%s.%2N")
    local sec_e=$(date -d "$ymd_e $hms_e" +"%s.%2N")
    local sspan=$(echo "$sec_e  -  $sec_s" | bc)
    if [[ $(echo "$sspan <= 0" | bc) -eq 1 ]]; then
        >&2 echo -e "$MSGERR illegal time span: from $ymd_s $hms_s to $ymd_e $hms_e"
        exit 1
    fi

    local session_time="${ymd_s[@]//-/ } ${hms_s[@]//:/ } ${sspan}"
    sed -i "/^Session time/s/ = .*/ = $session_time/" "$ctrl_file"

    # Try getting observation interval option from config file
    [ -n "$interval" ] || interval=$(get_ctrl "$ctrl_file" "Interval")
    [ -z "$time_sec" ] && time_sec=$(grep -E "^(>| [ 0-9][0-9] [ 0-1][0-9] )" "$rnxo_file")
    obsintvl=$(echo "$time_sec" | awk 'BEGIN{
                                           mdif = 30
                                       }{
                                           if ($1 == ">") {
                                               this_sec = $5*3600+$6*60+$7
                                           } else {
                                               this_sec = $4*3600+$5*60+$6
                                           }
                                           if (last_sec != "") {
                                               vdif = this_sec - last_sec
                                               if (vdif < 0) vdif *= -1
                                               if (vdif < mdif && vdif != 0) mdif = vdif
                                           }
                                           last_sec = this_sec
                                       }END{
                                           print(mdif)
                                       }')

    if [[ -n "$interval" ]] && [[ "$interval" != "Default" ]]; then
        if [[ $(echo "$interval < $obsintvl" | bc) -eq 1 ]]; then
            >&2 echo -e "$MSGERR input interval is short than the observation interval: $interval < $obsintvl"
            exit 1
        fi
    else
        ## Align to the nearest candidate
        local last_can last_dif this_dif
        local cand=("86400" "30" "25" "20" "15" "10" "5" "2" "1" "0.5" "0.25" "0.2" "0.1" "0.05" "0.02" "-86400")
        for i in $(seq 1 $[${#cand[@]}-1]); do
            last_can=${cand[$[$i-1]]}
            last_dif=$(echo "$obsintvl" | awk '{print("'${last_can}'"-$0)}')
            this_dif=$(echo "$obsintvl" | awk '{print($0-"'${cand[$i]}'")}')
            if [[ $(echo "$last_dif < $this_dif" | bc) -eq 1 ]]; then
               if [[ $(echo "$obsintvl == $last_can" | bc) -ne 1 ]]; then
                  >&2 echo -e "$MSGWAR singular observation interval, rounded to the nearest candidate: $obsintvl -> $last_can"
               fi
               obsintvl="$last_can" && break
            fi
        done
        interval="$obsintvl"
    fi

    if [[ $(echo "0.02 > $interval" | bc) -eq 1 ]]; then
       >&2 echo -e "$MSGWAR observation interval is too small, rounded to the nearest candidate: $interval -> 0.02"
       interval="0.02"
    fi

    if [[ $(echo "$interval > 30.0" | bc) -eq 1 ]]; then
       >&2 echo -e "$MSGWAR observation interval is too large, rounded to the nearest candidate: $interval -> 30.0"
       interval="30.0"
    fi

    sed -i "/^Interval/s/ = .*/ = $interval/" "$ctrl_file"

    # Editing mode
    [ -n "$edt_opt" ] || edt_opt=$(get_ctrl "$ctrl_file" "Strict editing")
    [ "$edt_opt" == "Default" ] && edt_opt="YES"
    sed -i "/^Strict editing/s/ = .*/ = $edt_opt/" "$ctrl_file"

    [ "$edt_opt" == "YES" ] && min_sspan="600.0" || min_sspan="120.0"
    if [[ $(echo "$sspan < $min_sspan" | bc) -eq 1 ]]; then
        >&2 echo -e "$MSGERR observation period is too short: $sspan < $min_sspan"
        exit 1
    fi

    # ZTD model
    [ -n "$ztd_opt" ] || ztd_opt=$(get_ctrl "$ctrl_file" "ZTD model")
    [ "$ztd_opt" == "Default" ] && ztd_opt="STO"

    sed -i "/^ZTD model/s/ = .*/ = $ztd_opt/" "$ctrl_file"

    if [ -z "$ztdp" ]; then
        local ztdp=$(echo "$opt_lin" | awk '{print($7)}')
        if [[ ! $ztgp =~ $PNUM_REGEX ]]; then
            case ${ztd_opt:0:3} in
            "STO" ) ztdp=".0004" ;;
            "PWC" ) ztdp="0.020" ;;
              *   ) ztdp="0.020" ;;
            esac
        fi
    fi

    ztdp=$(printf "%5s" $ztdp)

    # HTG model
    [ -n "$htg_opt" ] || htg_opt=$(get_ctrl "$ctrl_file" "HTG model")
    if [ "$htg_opt" == "Default" ]; then
        [ "$mode" == "F" -o $mode == "S" ] && htg_opt="PWC:720" || htg_opt="NON"
    fi

    sed -i "/^HTG model/s/ = .*/ = $htg_opt/" "$ctrl_file"

    if [ -z "$htgp" ]; then
        local htgp=$(echo "$opt_lin" | awk '{print($9)}')
        [[ $htgp =~ $PNUM_REGEX ]] || htgp=".002"
    fi

    htgp=$(printf "%4s" $htgp)

    # High-order ionospheric delay model
    [ -n "$ion_opt" ] || ion_opt=$(get_ctrl "$ctrl_file" "Iono 2nd")
    [ "$ion_opt" == "Default" ] && ion_opt="NO"
    sed -i "/^Iono 2nd/s/ = .*/ = $ion_opt/" "$ctrl_file"

    # Tide correction model
    local tide_mode
    if [ -z "$tide_mask" ]; then
        tide_mode=$(get_ctrl "$ctrl_file" "Tides")
        [ "$tide_mode" == "Default" ] && tide_mode="SOLID/OCEAN/POLE"
    else
        tide_mode=("SOLID" "OCEAN" "POLE")
        for t in ${tide_mask[@]}; do
            t="${t^^}"
            [ "$t" == "S" ] && tide_mode=("${tide_mode[@]/SOLID}")
            [ "$t" == "O" ] && tide_mode=("${tide_mode[@]/OCEAN}")
            [ "$t" == "P" ] && tide_mode=("${tide_mode[@]/POLE}")
        done
        tide_mode=$(echo "${tide_mode[@]}" | sed "s/^ *//; s/ *$//; s/  */\//g")
        [ -n "$tide_mode" ] || tide_mode="NON"
    fi

    sed -i "/^Tides/s/ = .*/ = ${tide_mode//\//\\/}/" "$ctrl_file"

    # Ambiguity resolution
    [ -n "$AR" ] || AR="A"

    [ -n "$lam_opt" ] || lam_opt=$(get_ctrl "$ctrl_file" "Ambiguity co-var")
    if [ "$lam_opt" == "Default" ]; then
        ## max observation time set for LAMBDA is 6 hours
        [[ $(echo "$sspan <= 21600.0" | bc) -eq 1 ]] && lam_opt="YES" || lam_opt="NO"
    fi

    sed -i "/^Ambiguity co-var/s/ = .*/ = $lam_opt/" "$ctrl_file"

    # PCO on wide-lane
    [ -n "$pco_opt" ] || pco_opt=$(get_ctrl "$ctrl_file" "PCO on wide-lane")
    sed -i "/^PCO on wide-lane/s/ = .*/ = $pco_opt/" "$ctrl_file"

    # GNSS
    for s in ${gnss_mask[@]}; do
        s="${s^^}"
        case $s in
        "2" ) prn_mask=($(seq -f  "C%02g"  1 16)) ;;
        "3" ) prn_mask=($(seq -f  "C%02g" 17 99)) ;;
         *  ) prn_mask=($(seq -f "$s%02g"  1 99)) ;;
        esac
        for prn in ${prn_mask[@]}; do
            sed -i "/^ $prn /s/^ /#/" "$ctrl_file"
        done
    done

    # Disable ambiguity resolution when process with GLONASS only
    grep -q "^ [GECJ][0-9][0-9] " "$ctrl_file" || AR="N"

    # Mapping function
    [ -n "$map_opt" ] || map_opt=$(echo "$opt_lin" | awk '{print($3)}')
    [ "$map_opt" == "XXX" ] && map_opt="GMF"

    # Cutoff elevation
    [ -n "$eloff" ] || eloff=$(echo "$opt_lin" | awk '{print($5)}')
    [[ $eloff =~ $PNUM_REGEX ]] || eloff="7"

    eloff=$(echo "$eloff" | awk '{printf("%2d",$0)}')

    # Modify option line
    local clkm=$(echo "$opt_lin" | awk '{print($4)}')
    local ztdm=$(echo "$opt_lin" | awk '{print($6)}')
    local htgm=$(echo "$opt_lin" | awk '{print($8)}')
    local ragm=$(echo "$opt_lin" | awk '{print($10)}')
    local phsc=$(echo "$opt_lin" | awk '{print($11)}')
    local poxm=$(echo "$opt_lin" | awk '{print($12)}')
    local poym=$(echo "$opt_lin" | awk '{print($13)}')
    local pozm=$(echo "$opt_lin" | awk '{print($14)}')

    opt_lin=" $site $mode  $map_opt $clkm $eloff $ztdm $ztdp $htgm $htgp $ragm $phsc $poxm $poym $pozm"
    sed -i "s/^ .... [KSFX] .*/$opt_lin/" "$ctrl_file"

    # Return
    echo "$rnxo_file"
    echo "$ctrl_path"
    echo "$ctrl_file"
    echo "$ymd_s"
    echo "$hms_s"
    echo "$ymd_e"
    echo "$hms_e"
    echo "$AR"
}

check_optional_arg(){ # purpose : check if optional argument is existing
                      # usage   : check_optional_arg this_arg last_arg
    local this_arg=$1
    local last_arg=$2

    [[ -z $this_arg ]] && return 1
    [[ $this_arg =~ ^-{1,2}   ]] && return 1
    [[ $this_arg == $last_arg ]] && return 1
    return 0
}

throw_conflict_opt(){ # purpose : throw exception message and exit when option conflicts with a previous option
                      # usage   : throw_invalid_arg opt
    local opt=$1

    >&2 echo "$SCRIPT_NAME: conflicting option '$opt'"
    >&2 echo "Try '$SCRIPT_NAME --help' for more information."
    return 1
}

throw_invalid_arg(){ # purpose : throw exception message and exit when option got an invalid argument
                     # usage   : throw_invalid_arg optlable argument
    local optlable=$1
    local argument=$2

    >&2 echo "$SCRIPT_NAME: invalid $optlable: ‘$argument’"
    >&2 echo "Try '$SCRIPT_NAME --help' for more information."
    exit 1
}

throw_invalid_opt(){ # purpose : throw exception message and exit when an invalid option occurs
                     # usage   : throw_invalid_opt opt
    local opt=$1

    case $opt in
    --+([-[:alnum:]_]) ) local detail="unrecognized option '${opt}'" ;;
     -+([-[:alnum:]_]) ) local detail="invalid option -- '${opt:1}'" ;;
      * )                local detail="invalid argument -- '${opt}'" ;;
    esac

    >&2 echo "$SCRIPT_NAME: $detail"
    >&2 echo "Try '$SCRIPT_NAME --help' for more information."
    exit 1
}

throw_require_arg(){ # purpose : throw exception message and exit when option did not get its argument
                     # usage   : throw_require_arg opt
    local opt=$1

    case $opt in
    --+([-[:alnum:]_]) ) local detail="option '${opt:0}' requires an argument"    ;;
     -+([-[:alnum:]_]) ) local detail="option requires an argument -- '${opt:1}'" ;;
      * )                local detail="invalid argument -- '${opt:0}'"            ;;
    esac

    >&2 echo "$SCRIPT_NAME: $detail"
    >&2 echo "Try '$SCRIPT_NAME --help' for more information."
    exit 1
}

CheckExecutables() { # purpose : check whether all needed executables are callable
                     # usage   : CheckExecutables
    echo -e "$MSGSTA CheckExecutables ..."
    for exceu in "arsig" "get_ctrl" "lsq" "redig" "sp3orb" "spp" "tedit"; do
        if ! which $exceu > /dev/null 2>&1; then
            echo -e "$MSGERR PRIDE PPP-AR executable file $exceu not found"
            return 1
        fi
    done
    for exceu in "merge2brdm.py" "pbopos" "xyz2enu"; do
        if ! which $exceu > /dev/null 2>&1; then
            echo -e "$MSGWAR PRIDE PPP-AR executable file $exceu not found"
        fi
    done
    for exceu in "awk" "diff" "readlink" "sed"; do
        if ! which $exceu > /dev/null 2>&1; then
            echo -e "$MSGERR system tool $exceu not found"
            return 1
        fi
    done
    for exceu in "curl" "gunzip" "wget"; do
        if ! which $exceu > /dev/null 2>&1; then
            echo -e "$MSGWAR system tool $exceu not found"
        fi
    done
    echo -e "$MSGSTA CheckExecutables done"
}

PRIDE_PPPAR_INFO() { # purpose : print information for PRIDE PPP-AR
                     # usage   : PRIDE_PPPAR_INFO
    >&2 echo "© GNSS Research Center of Wuhan University, 2022"
    >&2 echo "  GNSS PPP&PPP-AR data processing with PRIDE PPP-AR version $VERSION_NUM"
}

PRIDE_PPPAR_HELP() { # purpose : print usage for PRIDE PPP-AR
                     # usage   : PRIDE_PPPAR_HELP
    >&2 echo "Usage: $SCRIPT_NAME [options] <obs-file>"
    >&2 echo ""
    >&2 echo "  All char type arguments could be either upper-case or lower-case"
    >&2 echo ""
    >&2 echo "Start up:"
    >&2 echo ""
    >&2 echo "  -V, --version                              display version of this script"
    >&2 echo ""
    >&2 echo "  -H, --help                                 print this help"
    >&2 echo ""
    >&2 echo "Common options:"
    >&2 echo ""
    >&2 echo "  -cfg <file>, --config <file>               configuration file for PRIDE PPP-AR 2"
    >&2 echo ""
    >&2 echo "  -sys <char>, --system <char>               GNSS to be processed, select one or more from \"GREC23J\":"
    >&2 echo "                                             -----+------------------------+-----+-------------------------"
    >&2 echo "                                               G  |  GPS                   |  R  |  GLONASS                "
    >&2 echo "                                               E  |  Galileo               |  C  |  BeiDou-2 and BeiDou-3  "
    >&2 echo "                                               2  |  BeiDou-2 only         |  3  |  BeiDou-3 only          "
    >&2 echo "                                               J  |  QZSS                  |     |                         "
    >&2 echo "                                             -----+------------------------+-----+-------------------------"
    >&2 echo "                                               * default: all GNSS"
    >&2 echo ""
    >&2 echo "  -m <char>, --mode <char>                   positioning mode, select one from \"K/S/F\":"
    >&2 echo "                                             -----+--------------+-----+--------------+-----+--------------"
    >&2 echo "                                               S  |  static      |  K  | kinematic    |  F  |  fixed       "
    >&2 echo "                                             -----+--------------+-----+--------------+-----+--------------"
    >&2 echo ""
    >&2 echo "  -s <date [time]>, --start <date [time]>    start date (and time) for processing, format:"
    >&2 echo "                                             --------+--------------------------+--------+-----------------"
    >&2 echo "                                               date  |  yyyy/mm/dd or yyyy/doy  |  time  |  hh:mm:ss       "
    >&2 echo "                                             --------+--------------------------+--------+-----------------"
    >&2 echo "                                               * default: the first observation epoch in obs-file"
    >&2 echo ""
    >&2 echo "  -e <date [time]>, --end <date [time]>      end date (and time) for processing, format:"
    >&2 echo "                                             --------+--------------------------+--------+-----------------"
    >&2 echo "                                               date  |  yyyy/mm/dd or yyyy/doy  |  time  |  hh:mm:ss       "
    >&2 echo "                                             --------+--------------------------+--------+-----------------"
    >&2 echo "                                               * default: the last observation epoch in obs-file"
    >&2 echo ""
    >&2 echo "  -n <char>, --site <char>                   site name for processing, format: NNNN"
    >&2 echo "                                               * default: the MARKER NAME in obs-file, or the first four"
    >&2 echo "                                                   characters of the filename in RINEX naming convention"
    >&2 echo ""
    >&2 echo "  -i <num>,  --interval <num>                processing interval in seconds, 0.02 <= interval <= 30"
    >&2 echo "                                               * default: the minimal observation interval in obs-file"
    >&2 echo ""
    >&2 echo "Advanced options:"
    >&2 echo ""
    >&2 echo "  -aoff, --wapc-off                          disable APC correction on the Melbourne-Wubbena combination"
    >&2 echo ""
    >&2 echo "  -c <num>,  --cutoff-elev <num>             cutoff elevation in degrees, 0 <= elevation <=60 "
    >&2 echo "                                               * default: 7 degrees"
    >&2 echo ""
    >&2 echo "  -f, --float                                disable ambiguity resolution"
    >&2 echo ""
    >&2 echo "  -hion, --high-ion                          use 2nd ionospheric delay model with CODE's GIM products"
    >&2 echo ""
    >&2 echo "  -hoff, --htg-off                           disable horizontal tropospheric gradient (HTG) estimation"
    >&2 echo "                                               * HTG is applied for static and fixed mode by default"
    >&2 echo ""
    >&2 echo "  -l, --loose-edit                           disable strict editing"
    >&2 echo ""
    >&2 echo "  -p <char>, --mapping-func <char>           mapping function (MF), select one from \"G/N/V1/V3\""
    >&2 echo "                                             -------+-----------------------+------+-----------------------"
    >&2 echo "                                                G   |  Global MF            |  V1  |  Vienna MF 1          "
    >&2 echo "                                                N   |  Niell MF             |  V3  |  Vienna MF 3          "
    >&2 echo "                                             -------+-----------------------+------+-----------------------"
    >&2 echo "                                               * default: global mapping function (G)"
    >&2 echo ""
    >&2 echo "  -toff <char>, --tide-off <char>            disable tide correction, select one or more from \"SOP\":"
    >&2 echo "                                             -----+--------------+-----+--------------+-----+--------------"
    >&2 echo "                                               S  |  solid       |  O  | ocean        |  P  |  pole        "
    >&2 echo "                                             -----+--------------+-----+--------------+-----+--------------"
    >&2 echo "                                               * default: apply all tide corrections"
    >&2 echo ""
    >&2 echo "  -x <num>, --fix-method <num>               ambiguity fixing method, choose 1 or 2:"
    >&2 echo "                                             -----+------------------------+-----+-------------------------"
    >&2 echo "                                               1  |  rounding              |  2  |  LAMBDA                 "
    >&2 echo "                                             -----+------------------------+-----+-------------------------"
    >&2 echo "                                               * default: rounding for long observation time (> 6 h)"
    >&2 echo "                                                          LAMBDA for short observation time (<= 6 h)"
    >&2 echo ""
    >&2 echo "  -z <char[length] [num]>, --ztd <char[length] [num]>"
    >&2 echo "                                             ZTD model, piece length and process noise:"
    >&2 echo "                                                  input      model     length          process noise       "
    >&2 echo "                                             --------------+-------+-----------+---------------------------"
    >&2 echo "                                               S    .0010  |  STO  |           |      0.0010 m/sqrt(s)     "
    >&2 echo "                                               S           |  STO  |           |      0.0004 m/sqrt(s)     "
    >&2 echo "                                               P720        |  PWC  |  720 min  |      0.02   m/sqrt(h)     "
    >&2 echo "                                               P60  0.040  |  PWC  |   60 min  |      0.04   m/sqrt(h)     "
    >&2 echo "                                               P           |  PWC  |   60 min  |      0.02   m/sqrt(h)     "
    >&2 echo "                                             --------------+-------+-----------+---------------------------"
    >&2 echo "                                               * ZTD - zenith total delay of troposphere"
    >&2 echo "                                               * STO - stochastic walk"
    >&2 echo "                                               * PWC - piece-wise constant"
    >&2 echo "                                               * default: STO model with process noise as .0004 m/sqrt(s)"
    >&2 echo ""
    >&2 echo "Examples:"
    >&2 echo ""
    >&2 echo "  pdp3 abmf0010.20o                          single-day processing"
    >&2 echo ""
    >&2 echo "  pdp3 -s 2020/1 -e 2020/3 abmf0010.20o      multi-day processing from 2020/001 to 2020/003"
    >&2 echo ""
    >&2 echo "  For more detailed information, refer to the PRIDE PPP-AR manual and repository"
    >&2 echo "    https://github.com/PrideLab/PRIDE-PPPAR/"
}

ProcessSingleDay() { # purpose : process data of single day
                     # usage   : ProcessSingleDay rnxo_file ctrl_file ymd_s hms_s ymd_e hms_e AR(A/Y/N)
    local rnxo_file="$1"
    local ctrl_file="$2"
    local ymd_s="$3"
    local hms_s="$4"
    local ymd_e="$5"
    local hms_e="$6"
    local AR="$7"

    local interval=$(get_ctrl "$ctrl_file" "Interval")
    local site=$(grep "^ .... [KSF]" "$ctrl_file" | cut -c 2-5)
    local mode=$(grep "^ .... [KSF]" "$ctrl_file" | cut -c 7-7)

    local rinex_dir=$(dirname  "$rnxo_file")
    local rnxo_name=$(basename "$rnxo_file")

    local doy=$(date -d "$ymd_s" +"%j")
    local ymd=($(echo "$ymd_s" | tr '-' ' '))
    local mon=${ymd[1]}
    local day=${ymd[2]}
    local mjd=$(ymd2mjd ${ymd[*]})

    echo -e "$MSGSTA ProcessSingleDay $ymd $doy ..."

    CleanAll "$ymd" "$doy"

    # Prepare config
    mv -f "$ctrl_file" . && ctrl_file=$(basename "$ctrl_file")
    if [ $? -ne 0 ]; then
        echo -e "$MSGERR temporary config file doesn't exist: $ctrl_file"
        return 1
    fi

    # Prepare tables
    local table_dir=$(get_ctrl "$ctrl_file" "Table directory" | sed "s/^[ \t]*//; s/[ \t]*$//; s#^~#$HOME#")
    PrepareTables "$mjd" "$mjd" "$table_dir"
    if [ $? -ne 0 ]; then
        echo -e "$MSGERR PrepareTables failed"
        return 1
    fi

    # RINEX-OBS check
    local rinexobs="$rinex_dir/$rnxo_name"
    [ ! -f "$rinexobs" ] && echo -e "$MSGERR $rinexobs doesn't exist" && return 1

    local rinexver=$(head -1 "$rinexobs" | cut -c 6-6)
    if [ "$rinexver" != "2" -a "$rinexver" != "3" ]; then
        echo -e "$MSGERR unsupported RINEX version (not 2 or 3): $rinexobs"
        return 1
    fi

    # Prepare RINEX-NAV
    PrepareRinexNav "$mjd" "$mjd" "$rinex_dir" "$ctrl_file"
    if [ $? -ne 0 ]; then
        echo -e "$MSGERR PrepareRinexNav failed"
        return 1
    fi

    # RINEX-NAV check
    local rinexnav="$rinex_dir/brdm${doy}0.${ymd:2:2}p"
    [ ! -f "$rinexnav" ] && echo -e "$MSGERR $rinexnav doesn't exist" && return 1

    local rinexver=$(head -1 "$rinexnav" | cut -c 6-6)
    if [ "$rinexver" != "2" -a "$rinexver" != "3" ]; then
        echo -e "$MSGERR unsupported RINEX version (not 2 or 3): $rinexnav"
        return 1
    fi

    # Prepare products
    local product_dir=$(get_ctrl "$ctrl_file" "Product directory" | sed "s/^[ \t]*//; s/[ \t]*$//; s#^~#$HOME#")
    PrepareProducts "$mjd" "$mjd" "$product_dir" "$ctrl_file" "$AR"
    if [ $? -ne 0 ]; then
        echo -e "$MSGERR PrepareProducts failed"
        return 1
    fi

    # Generate binary sp3
    local sp3=$(get_ctrl "$ctrl_file" "Satellite orbit")
    [ $(echo "$sp3" | wc -w) -gt 1 ] && sp3="mersp3_$ymd$doy"
    cmd="sp3orb $sp3 -cfg $ctrl_file"
    ExecuteWithoutOutput "$cmd"
    if [ $? -ne 0 ]; then
        echo -e "${RED}($time)${NC} ${CYAN}$cmd${NC} executed failed"
        return 1
    fi

    # Process single site
    ProcessSingleSite "$rinexobs" "$rinexnav" "$ctrl_file" "$mjd" "$hms_s" "$mjd" "$hms_e" "$site" "$AR"
    if [ $? -ne 0 ]; then
        echo -e "$MSGERR ProcessSingleDay: processing $ymd $doy $site failed"
        [ ${DEBUG} == "NO" ] && CleanMid "$ymd" "$doy"
    else
        echo -e "$MSGSTA ProcessSingleDay $ymd $doy done"
    fi
}

ProcessMultiDays() { # purpose : process data of single day
                     # usage   : ProcessMultiDays rnxo_file ctrl_file ymd_s hms_s ymd_e hms_e AR(A/Y/N)
    local rnxo_file="$1"
    local ctrl_file="$2"
    local ymd_s="$3"
    local hms_s="$4"
    local ymd_e="$5"
    local hms_e="$6"
    local AR="$7"

    local interval=$(get_ctrl "$ctrl_file" "Interval")
    local site=$(grep "^ .... [KSF]" "$ctrl_file" | cut -c 2-5)
    local mode=$(grep "^ .... [KSF]" "$ctrl_file" | cut -c 7-7)

    local rinex_dir=$(dirname  "$rnxo_file")
    local rnxo_name=$(basename "$rnxo_file")

    local doy_s=$(date -d "$ymd_s" +"%j")
    local doy_e=$(date -d "$ymd_e" +"%j")
    local ymd_s=($(echo "$ymd_s" | tr '-' ' '))
    local ymd_e=($(echo "$ymd_e" | tr '-' ' '))
    local mon_s=${ymd_s[1]}
    local mon_e=${ymd_e[1]}
    local day_s=${ymd_s[2]}
    local day_e=${ymd_e[2]}
    local mjd_s=$(ymd2mjd ${ymd_s[*]})
    local mjd_e=$(ymd2mjd ${ymd_e[*]})

    echo -e "$MSGSTA ProcessMultiDays from $ymd_s $doy_s to $ymd_e $doy_e ..."

    CleanAll "$ymd_s" "$doy_s"

    # Prepare config
    mv -f "$ctrl_file" . && ctrl_file=$(basename "$ctrl_file")
    if [ $? -ne 0 ]; then
        echo -e "$MSGERR temporary config file doesn't exist: $ctrl_file"
        return 1
    fi

    # Prepare tables
    local table_dir=$(get_ctrl "$ctrl_file" "Table directory" | sed "s/^[ \t]*//; s/[ \t]*$//; s#^~#$HOME#")
    PrepareTables "$mjd_s" "$mjd_e" "$table_dir" || return 1
    if [ $? -ne 0 ]; then
        echo -e "$MSGERR PrepareTables failed"
        return 1
    fi

    # RINEX-OBS check
    readonly local RNXO2_GLOB="${rnxo_name:0:4}${doy_s}0.${ymd_s:2:2}@(o|O)"
    readonly local RNXO3_GLOB="${rnxo_name:0:9}_?_${ymd_s}${doy_s}0000_01D_30S_MO.@(rnx|RNX)"

    local rinexobs 
    for mjd in $(seq $mjd_s $mjd_e); do
        local ydoy=($(mjd2ydoy $mjd))
        case "$rnxo_name" in
        $RNXO2_GLOB )
            rinexobs="${rnxo_name:0:4}${ydoy[1]}0.${ydoy[0]:2:2}${rnxo_name:11}" ;;
        $RNXO3_GLOB )
            rinexobs="${rnxo_name:0:12}${ydoy[0]}${ydoy[1]}${rnxo_name:19}"      ;;
        * )
            echo -e "$MSGWAR unrecognized naming convention of RINEX observation file: $rnxo_name"
            echo -e "$MSGINF error may occur if not enough observation data is contained in this single file"
            break ;;
        esac
        [ -f "$rinex_dir/$rinexobs" ] || echo -e "$MSGWAR $rinex_dir/$rinexobs doesn't exist"
    done

    rinexobs="$rinex_dir/$rnxo_name"
    [ -f "$rinexobs" ] || echo -e "$MSGWAR $rinexobs doesn't exist"

    local rinexver=$(head -1 "$rinexobs" | cut -c 6-6)
    if [ "$rinexver" != "2" -a "$rinexver" != "3" ]; then
        echo -e "$MSGERR unsupported RINEX version (not 2 or 3): $rinexobs"
        return 1
    fi

    # Prepare RINEX-NAV
    PrepareRinexNav "$mjd_s" "$mjd_e" "$rinex_dir" "$ctrl_file"
    if [ $? -ne 0 ]; then
        echo -e "$MSGERR PrepareRinexNav failed"
        return 1
    fi

    # RINEX-NAV check
    local rinexnav="$rinex_dir/brdm${doy_s}0.${ymd_s:2:2}p"
    [ ! -f "$rinexnav" ] && echo -e "$MSGWAR $rinexnav doesn't exist" && return 1

    local rinexver=$(head -1 "$rinexnav" | cut -c 6-6)
    if [ "$rinexver" != "2" -a "$rinexver" != "3" ]; then
        echo -e "$MSGERR unsupported RINEX version (not 2 or 3): $rinexnav"
        return 1
    fi

    # Prepare products
    local product_dir=$(get_ctrl "$ctrl_file" "Product directory" | sed "s/^[ \t]*//; s/[ \t]*$//; s#^~#$HOME#")
    PrepareProducts "$mjd_s" "$mjd_e" "$product_dir" "$ctrl_file" "$AR"
    if [ $? -ne 0 ]; then
        echo -e "$MSGERR PrepareProducts failed"
        return 1
    fi

    # Generate binary sp3
    local sp3=$(get_ctrl "$ctrl_file" "Satellite orbit")
    [ $(echo "$sp3" | wc -w) -gt 1 ] && sp3="mersp3_$ymd_s$doy_s"
    cmd="sp3orb $sp3 -cfg $ctrl_file"
    ExecuteWithoutOutput "$cmd"
    if [ $? -ne 0 ]; then
        echo -e "${RED}($time)${NC} ${CYAN}$cmd${NC} executed failed"
        return 1
    fi

    # Process single site
    ProcessSingleSite "$rinexobs" "$rinexnav" "$ctrl_file" "$mjd_s" "$hms_s" "$mjd_e" "$hms_e" "$site" "$AR"
    if [ $? -ne 0 ]; then
        echo -e "$MSGERR ProcessMultiDays: processing from $ymd_s $doy_s to $ymd_e $doy_e $site failed"
        [ ${DEBUG} == "NO" ] && CleanMid "$ymd_s" "$doy_s"
    else
        echo -e "$MSGSTA ProcessMultiDays from $ymd_s $doy_s to $ymd_e $doy_e done"
    fi
}

ProcessSingleSite() { # purpose : process data of single site
                      # usage   : ProcessSingleSite rinexobs rinexnav config mjd_s hms_s mjd_e hms_e site AR(A/Y/N)
    local rinexobs="$1"
    local rinexnav="$2"
    local config="$3"
    local mjd_s="$4"
    local hms_s="$5"
    local mjd_e="$6"
    local hms_e="$7"
    local site="$8"
    local AR="$9"

    local ydoy_s=($(mjd2ydoy $mjd_s))
    local ydoy_e=($(mjd2ydoy $mjd_e))
    local ymd_s=($(ydoy2ymd ${ydoy_s[*]}))
    local ymd_e=($(ydoy2ymd ${ydoy_s[*]}))

    local year=${ydoy_s[0]}
    local doy=${ydoy_s[1]}
    local ymd=(${ymd_s[@]})

    local position_mode=$(grep "^ $site [KSF]" "$config" | awk '{print $2}') # Static/Kinematic
    local cutoff_elev=$(grep "^ $site [KSF]" "$config" | awk '{print $5}')   # int, degree

    echo -e "$MSGSTA ProcessSingleSite ${site} from ${ydoy_s[@]} to ${ydoy_e[@]} ..."

    # Compute a priori positions
    echo -e "$MSGSTA Prepare initial position ${site} ..."
    local interval=$(get_ctrl "$config" "Interval")
    ComputeInitialPos "$rinexobs" "$rinexnav" "$mjd_s" "$hms_s" "$mjd_e" "$hms_e" "$site" "$interval" "$mode"
    awk -v sit=$site '/^Position/{printf(" %s%16.4f%16.4f%16.4f\n",sit,$3,$4,$5)}' tmp_ComputeInitialPos > sit.xyz
    local session_time=($(awk '/^Duration/{print $3,$4,$5,$6,$7,$8,$9}' tmp_ComputeInitialPos))
    rm -f tmp_ComputeInitialPos
    if [ ${mode} == "F" ]; then
        local initial_pos=($(snx2sit $site $mjd))
        if [ ${#initial_pos[@]} -ne 6 ]; then
            echo -e "$MSGERR ProcessSingleDay: no position or sigma: $site"
            return 1
        fi
        printf " %s%16.4f%16.4f%16.4f%10.6f%10.6f%10.6f\n" ${site} ${initial_pos[*]} > sit.xyz
    fi
    echo -e "$MSGSTA Prepare initial position ${site} done"

    # Check priori positions
    local xyz=($(awk -v sit=$site '{if($1==sit){print $2,$3,$4}}' sit.xyz))
    if [ -n "$xyz" ]; then
        local blh=($(xyz2blh "${xyz[@]}"))
        if [[ $(echo "${blh[2]} <= -4000" | bc) -eq 1 ]] || \
           [[ $(echo "${blh[2]} >= 20000" | bc) -eq 1 ]]; then
            local blh=$(echo "${blh[2]}/1000" | bc)
            echo -e "$MSGERR ProcessSingleSite: invalid site elevation (out of range from -4 km to +20 km): $site $blh km"
            return 1
        fi
    fi

    # Fill in session time
    if [ ${#session_time[@]} -ne 7 ]; then
        echo -e "$MSGERR ProcessSingleSite: no session time"
        return 1
    fi

    session_time="${session_time[@]}"
    sed -i "/^Session time/s/ = .*/ = $session_time/" "$ctrl_file"

    # Create kin file for K mode for spp
    local editing=$(get_ctrl "$config" "Strict editing")
    if [ "$editing" == "YES" ]; then
        local editing_mode="YES"
    elif [ "$editing" == "NO" ]; then
        local editing_mode="NO"
    else
        echo -e "$MSGERR ProcessSingleSite: unknown editing mode: $editing"
        return 1
    fi

    # Data preprocess
    echo -e "$MSGSTA Data pre-processing ..."
    local session=$(grep "^Session time" "${config}" | awk '{print $10}')
    local hms=($(grep "^Session time" "${config}" | awk '{print $7,$8,$9}'))
    local rhd_file="log_${year}${doy}_${site}"
    xyz=($(awk -v sit=$site '{if($1==sit){print $2,$3,$4}}' sit.xyz))
    local cmd=""
    if [ "$position_mode" == S -o "$position_mode" == F ]; then
        cmd="tedit \"${rinexobs}\" -time ${ymd[*]} ${hms[*]} -len ${session} -int ${interval} \
            -xyz ${xyz[*]} -short 1200 -lc_check only -rhd ${rhd_file} -pc_check 300 \
            -elev ${cutoff_elev} -rnxn \"${rinexnav}\""
        local mjd=$(ymd2mjd ${ymd[*]})
        if [ $mjd_s -le 51666 ]; then
            cmd="tedit \"${rinexobs}\" -time ${ymd[*]} ${hms[*]} -len ${session} -int ${interval} \
                -xyz ${xyz[*]} -short 1200 -lc_check no -rhd ${rhd_file} -pc_check 0 \
                -elev ${cutoff_elev} -rnxn \"${rinexnav}\""
        fi
    elif [ "$position_mode" == K ]; then
        cmd="tedit \"${rinexobs}\" -time ${ymd[*]} ${hms[*]} -len ${session} -int ${interval} \
              -xyz kin_${year}${doy}_${site} -short 120 -lc_check no \
             -elev ${cutoff_elev} -rhd ${rhd_file} -rnxn \"${rinexnav}\""
        if [ $mjd_s -le 51666 ]; then
            cmd="tedit \"${rinexobs}\" -time ${ymd[*]} ${hms[*]} -len ${session} -int ${interval} \
                 -xyz kin_${year}${doy}${site} -short 120 -lc_check no \
                 -pc_check 0 -elev ${cutoff_elev} -rhd ${rhd_file} -rnxn \"${rinexnav}\""
        fi
    else
        echo -e "$MSGERR ProcessSingleSite: unknown position mode: $site $position_mode"
        return 1
    fi
    cmd=$(tr -s " " <<< "$cmd")
    ExecuteWithoutOutput "$cmd" || return 1
    echo -e "$MSGSTA Data pre-processing done"

    # Data clean (iteration)
    echo -e "$MSGSTA Data cleaning ..."
    if [ "$editing_mode" == YES ]; then
        local short=$(echo $interval | awk '{printf("%.0f\n", 600/$1)}')
        local jumps=(400 200 100 50)
        local jump_end=50
    else
        local short=$(echo $interval | awk '{printf("%.0f\n", 120/$1)}')
        local jumps=(400 200 100)
        local jump_end=100
    fi
    local new_rem=100
    local new_amb=100
    for jump in ${jumps[*]}; do
        if [ $new_rem != 0 -o $new_amb != 0 ]; then
          cmd="lsq ${config} \"${rinexobs}\""
          ExecuteWithoutOutput "$cmd" || return 1
        fi
        cmd="redig res_${year}${doy} -jmp $jump -sht $short"
        local time=`date +'%Y-%m-%d %H:%M:%S'`
        $cmd > tempout 2>&1
        if [ $? -eq 0 ]; then
            echo -e "${GREEN}($time)${NC} ${CYAN}$cmd${NC} executed ok"
        else
            echo -e "${RED}($time)${NC} ${CYAN}$cmd${NC} executed failed"
            return 1
        fi
        awk '/%%%\+RMS OF RESIDUALS---PHASE\(MM\)/,/%%%\-RMS OF RESIDUALS---PHASE\(MM\)/{print}' tempout
        new_rem=`awk '/NEWLY REMOVED:/{print $3}' tempout`
        new_amb=`awk '/NEWLY AMBIGUT:/{print $3}' tempout`
        if [ $new_rem == '' -o $new_amb == '' ]; then
            echo -e "${RED}($time)${NC} ${CYAN}$cmd${NC} executed failed"
            return 1
        fi
        awk '/NEWLY REMOVED:/{printf "\033[1;34mNewly removed observations\033[0m: %10d%8.2f%%\n",$3,$4}' tempout
        awk '/NEWLY AMBIGUT:/{printf "\033[1;34mNewly inserted ambiguities\033[0m: %10d%8.2f%%\n",$3,$4}' tempout
    done
    niter=0
    while [ $new_rem != 0 -o $new_amb != 0 ]; do
        [ $niter -gt 100 ] && break
        ((niter=niter+1))
        cmd="lsq ${config} \"${rinexobs}\""
        ExecuteWithoutOutput "$cmd" || return 1
        cmd="redig res_${year}${doy} -jmp $jump_end -sht $short"
        local time=`date +'%Y-%m-%d %H:%M:%S'`
        $cmd > tempout 2>&1
        if [ $? -eq 0 ]; then
            echo -e "${GREEN}($time)${NC} ${CYAN}$cmd${NC} executed ok"
        else
            echo -e "${RED}($time)${NC} ${CYAN}$cmd${NC} executed failed"
            return 1
        fi
        new_rem=`awk '/NEWLY REMOVED:/{print $3}' tempout`
        new_amb=`awk '/NEWLY AMBIGUT:/{print $3}' tempout`
        if [ $new_rem == '' -o $new_amb == '' ]; then
            echo -e "${RED}($time)${NC} ${CYAN}$cmd${NC} executed failed"
            return 1
        fi
        awk '/%%%\+RMS OF RESIDUALS---PHASE\(MM\)/,/%%%\-RMS OF RESIDUALS---PHASE\(MM\)/{print}' tempout
        awk '/NEWLY REMOVED:/{printf "\033[1;34mNewly removed observations\033[0m: %10d%8.2f%%\n",$3,$4}' tempout
        awk '/NEWLY AMBIGUT:/{printf "\033[1;34mNewly inserted ambiguities\033[0m: %10d%8.2f%%\n",$3,$4}' tempout
    done
    rm -f tempout
    echo -e "$MSGSTA Data cleaning done"

    # Ambiguity fixing
    if [ "$AR" == "Y" ] || [ "$AR" == "A" -a -f fcb_${year}${doy} ]; then
        cmd="arsig ${config}"
        Execute "$cmd" || return 1
        cmd="lsq ${config} \"${rinexobs}\""
        Execute "$cmd" || return 1
    fi
    echo -e "$MSGSTA Final processing done"

    # Rename result files
    local fn typ types=(rck ztd htg amb res stt cst) fn
    for typ in ${types[*]}; do
        fn=${typ}_${year}${doy}
        [ -f ${fn} ] && mv -f ${fn} ${fn}_${site}
    done

    echo -e "$MSGSTA ProcessSingleSite ${site} from ${ydoy_s[@]} to ${ydoy_e[@]} done"
}

ComputeInitialPos() { # purpose : compute intial postion with spp
                      # usage   : ComputeInitialPos rinexobs rinexnav mjd_s hms_start mjd_e hms_end site interval mode(S/K/F)
    local rinexobs="$1"
    local rinexnav="$2"
    local mjd_s="$3"
    local hms_s="$4"
    local mjd_e="$5"
    local hms_e="$6"
    local site="$7"
    local interval="$8"
    local mode="$9"

    local ydoy_s=($(mjd2ydoy ${mjd_s}))
    local ymd_s=($(ydoy2ymd ${ydoy_s[*]}))
    local ydoy_e=($(mjd2ydoy ${mjd_e}))
    local ymd_e=($(ydoy2ymd ${ydoy_e[*]}))

    local ts="${ymd_s[0]}/${ymd_s[1]}/${ymd_s[2]} $hms_s"
    local te="${ymd_e[0]}/${ymd_e[1]}/${ymd_e[2]} $hms_e"

    local cmd=""
    if [ "$mode" == "K" ]; then
        cmd="spp -trop saas -ts $ts -te $te -ti $interval -o kin_${ydoy_s[0]}${ydoy_s[1]}_${site} \"$rinexobs\" \"$rinexnav\""
    else
        cmd="spp -trop saas -ts $ts -te $te -ti $interval \"$rinexobs\" \"$rinexnav\""
    fi

    Execute "$cmd" tmp_ComputeInitialPos || return 1
}

PrepareTables() { # purpose: prepare PRIDE-PPPAR needed tables in working directory
                  # usage  : PrepareTables mjd_s mjd_e table_dir
    local mjd_s="$1"
    local mjd_e="$2"
    local table_dir="$3"

    echo -e "$MSGSTA PrepareTables ..."

    if ! ls $table_dir &>/dev/null; then
        echo -e "$MSGERR PrepareTables: table directory doesn't exist: $table_dir"
        [ "$table_dir" == "Default" ] && echo -e "$MSGINF please define your table directory in configuration file"
        return 1
    fi

    local tables=(file_name oceanload orography_ell orography_ell_1x1 gpt3_1.grd)
    for table in ${tables[*]}; do
        if [ ! -f "$table_dir/$table" ]; then
             echo -e "$MSGERR PrepareTables: no such file: $table_dir/$table"
             return 1
        fi
        ln -sf "$table_dir/$table" ./
    done

    # Check leap.sec
    local leapsec="leap.sec"
    local leapsec_ftp="0"
    local leapsec_exi="0"
    local leapsec_url="ftp://igs.gnsswhu.cn/pub/whu/phasebias/table/$leapsec"
    if [ -f "$leapsec" ]; then
        sed -n "1p;q" "$leapsec" | grep -q "*" || leapsec_ftp="1"
        grep -q "\-leap sec" "$leapsec"        || leapsec_ftp="1"
    else
        leapsec_exi=$?
    fi
    if [ "$leapsec_ftp" != 0 -o "$leapsec_exi" != 0 ]; then
        rm -f "$leapsec"
        WgetDownload "$leapsec_url"
        if [ ! -f "$leapsec" ]; then
            cp -f "$table_dir/$leapsec" .
        else
            if ! grep -q "\-leap sec" "$leapsec"; then
                echo -e "$MSGWAR PrepareTables: failed to download $leapsec, use default instead"
                cp -f "$table_dir/$leapsec" .
            fi
            local diff=$(diff "$leapsec" "$table_dir/$leapsec")
            [[ -n "$diff" ]] && cp -f "$leapsec" "$table_dir/"
        fi
    fi
    if ! grep -q "\-leap sec" "$leapsec"; then
        echo -e "$MSGERR PrepareTables: no available $leapsec"
        echo -e "$MSGINF please download this file from $leapsrc_url"
        return 1
    fi

    # Check sat_parameters
    local satpara="sat_parameters"
    local satpara_ftp="0"
    local satpara_exi="0"
    local satpara_url="ftp://igs.gnsswhu.cn/pub/whu/phasebias/table/$satpara"
    if [ -f "$satpara" ]; then
        local tmpymd=($(sed -n "1p;q" "$satpara" | awk '{print(substr($0,56,4),substr($0,61,2),substr($0,64,2))}'))
        local tmpmjd=$(ymd2mjd ${tmpymd[@]})
        [ $? -ne 0 -o "$tmpmjd" -lt "$mjd_e" ] && satpara_ftp="1"
        grep -q "\-prn_indexed" "$satpara"     || satpara_ftp="1"
    else
        satpara_exi=$?
    fi
    if [ "$satpara_ftp" != 0 -o "$satpara_exi" != 0 ]; then
        rm -f "$satpara"
        WgetDownload "$satpara_url"
        if [ ! -f "$satpara" ]; then
            cp -f "$table_dir/$satpara" .
        else
            if ! grep -q "\-prn_indexed" "$satpara"; then
                echo -e "$MSGWAR PrepareTables: failed to download $satpara, use default instead"
                cp -f "$table_dir/$satpara" .
            fi
            local diff=$(diff "$satpara" "$table_dir/$satpara")
            [[ -n "$diff" ]] && cp -f "$satpara" "$table_dir/"
        fi
    fi
    if ! grep -q "\-prn_indexed" "$satpara"; then
        echo -e "$MSGERR PrepareTables: no available $satpara"
        echo -e "$MSGINF please download this file from $satpara_url"
        return 1
    else
        local tmpymd=($(sed -n "1p;q" "$satpara" | awk '{print(substr($0,56,4),substr($0,61,2),substr($0,64,2))}'))
        local tmpmjd=$(ymd2mjd ${tmpymd[@]})
        if [ $? -ne 0 -o "$tmpmjd" -lt "$mjd_e" ]; then
            echo -e "$MSGWAR PrepareTables: outdated $satpara"
            echo -e "$MSGINF please update this file from $satpara_url"
        fi
    fi

    echo -e "$MSGSTA PrepareTables done"
}

PrepareRinexNav() { # purpose : prepare RINEX multi-systems broadcast ephemerides
                    # usage   : PrepareRinexNav mjd_s mjd_e rinex_dir config
    local mjd_s="$1"
    local mjd_e="$2"
    local rinex_dir="$3"
    local config="$4"

    echo -e "$MSGSTA PrepareRinexNav ..."

    for mjd in $(seq $mjd_s $mjd_e); do
        local ydoy=($(mjd2ydoy $mjd))
        local year=${ydoy[0]}
        local doy=${ydoy[1]}
        local rinexnav="brdm${doy}0.${year:2:2}p"

        # Try downloading hourly navigation file when processing current day's data
        if [ $(date -u +"%Y%j") -eq "$year$doy" ]; then
            local navgps="hour${doy}0.${year:2:2}n" && rm -f "$navgps"
            local urlnav="ftp://igs.gnsswhu.cn/pub/gps/data/hourly/${year}/${doy}/${navgps}.gz"
            WgetDownload "$urlnav"
            if [ $? -eq 0 ]; then
                gunzip -f ${navgps}.gz
            else
                echo -e "$MSGWAR download hourly rinexnav failed: $navgps"
            fi
            local navglo="hour${doy}0.${year:2:2}g" && rm -f "$navglo"
            local urlnav="ftp://igs.gnsswhu.cn/pub/gps/data/hourly/${year}/${doy}/${navglo}.gz"
            WgetDownload "$urlnav"
            if [ $? -eq 0 ]; then
                gunzip -f ${navglo}.gz
            else
                echo -e "$MSGWAR download hourly rinexnav failed: $navglo"
            fi
            if [ -f "$navgps" -a -f "$navglo" ]; then
                echo -e "$MSGSTA Merging $rinexnav ..."
                merge2brdm.py "$navgps" "$navglo" && mv -f "$rinexnav" "$rinex_dir"
                if [ $? -ne 0 -o ! -f "$rinex_dir/$rinexnav" ]; then
                    echo -e "$MSGERR merging hourly rinexnav failed: $navgps $navglo -> $rinexnav"
                    return 1
                fi
            else
                [ -f "$navglo" ] && mv -f "$navglo" "$rinex_dir/$rinexnav"
                [ -f "$navgps" ] && mv -f "$navgps" "$rinex_dir/$rinexnav"
                if [ ! -f "$rinex_dir/$rinexnav" ]; then
                    echo -e "$MSGERR download hourly rinexnav failed: $rinex_dir/$rinexnav"
                    return 1
                fi
            fi
        fi

        # Try finding brdm from RINEX directory
        if [ ! -f "$rinex_dir/$rinexnav" ]; then
            local tmpnav="BRDC00IGS_R_${year}${doy}0000_01D_MN.rnx"
            [ -f "$rinex_dir/$tmpnav" -a ! -f "$rinex_dir/$rinexnav" ] && mv -f "$rinex_dir/$tmpnav" "$rinex_dir/$rinexnav"
            local tmpnav="BRDC00IGN_R_${year}${doy}0000_01D_MN.rnx"
            [ -f "$rinex_dir/$tmpnav" -a ! -f "$rinex_dir/$rinexnav" ] && mv -f "$rinex_dir/$tmpnav" "$rinex_dir/$rinexnav"
            local tmpnav="BRDM00DLR_S_${year}${doy}0000_01D_MN.rnx"
            [ -f "$rinex_dir/$tmpnav" -a ! -f "$rinex_dir/$rinexnav" ] && mv -f "$rinex_dir/$tmpnav" "$rinex_dir/$rinexnav"
        fi

        # Try downloading brdm
        if [ ! -f "$rinex_dir/$rinexnav" ]; then
            if [ $year -ge 2016 ]; then
                local tmpnav="BRDC00IGS_R_${year}${doy}0000_01D_MN.rnx"
                local urlnav="ftp://igs.gnsswhu.cn/pub/gps/data/daily/${year}/${doy}/${year:2:2}p/${tmpnav}.gz"
                WgetDownload "$urlnav"
                if [ $? -eq 0 ]; then
                    gunzip -f ${tmpnav}.gz && mv -f "$tmpnav" "$rinex_dir/$rinexnav"
                else
                    tmpnav="BRDC00IGN_R_${year}${doy}0000_01D_MN.rnx"
                    urlnav="ftp://igs.ign.fr/pub/igs/data/${year}/${doy}/${tmpnav}.gz"
                    WgetDownload "$urlnav"
                    if [ $? -eq 0 ]; then
                        gunzip -f ${tmpnav}.gz && mv -f "$tmpnav" "$rinex_dir/$rinexnav"
                    else
                        echo -e "$MSGWAR download rinexnav failed: $tmpnav"
                    fi
                fi
            fi
        fi

        # Try downloading GPS and GLONASS brdc
        if [ ! -f "$rinex_dir/$rinexnav" ]; then
            local navgps="brdc${doy}0.${year:2:2}n"
            if [ ! -f "$navgps" ]; then
                local urlnav="ftp://igs.gnsswhu.cn/pub/gps/data/daily/${year}/${doy}/${year:2:2}n/${navgps}.Z"
                CopyOrDownloadProduct "$rinex_dir/$navgps" "$navgps"
                if [ $? -ne 0 ]; then
                    WgetDownload "$urlnav" && gunzip -f "${navgps}.Z"
                    if [ $? -ne 0 ]; then
                        echo -e "$MSGWAR download rinexnav failed: $navgps"
                    fi
                fi
            fi
            local navglo="brdc${doy}0.${year:2:2}g"
            if [ ! -f "$navglo" ]; then
                local urlnav="ftp://igs.gnsswhu.cn/pub/gps/data/daily/${year}/${doy}/${year:2:2}g/${navglo}.Z"
                CopyOrDownloadProduct "$rinex_dir/$navglo" "$navglo"
                if [ $? -ne 0 ]; then
                    WgetDownload "$urlnav" && gunzip -f "${navglo}.Z"
                    if [ $? -ne 0 ]; then
                        echo -e "$MSGWAR download rinexnav failed: $navglo"
                    fi
                fi
            fi
            if [ -f "$navgps" -a -f "$navglo" ]; then
                merge2brdm.py "$navgps" "$navglo" && mv -f "$rinexnav" "$rinex_dir"
                if [ $? -ne 0 -o ! -f "$rinex_dir/$rinexnav" ]; then
                    echo -e "$MSGERR merging rinexnav failed: $navgps $navglo -> $rinexnav"
                    return 1
                fi
            else
                [ -f "$navglo" ] && mv -f "$navglo" "$rinex_dir/$rinexnav"
                [ -f "$navgps" ] && mv -f "$navgps" "$rinex_dir/$rinexnav"
                if [ ! -f "$rinex_dir/$rinexnav" ]; then
                    echo -e "$MSGERR download rinexnav failed: $rinex_dir/$rinexnav"
                    return 1
                fi
            fi
        fi

        # Check brdm for each GNSS
        local sys="G" nsys="0"
        local rinexver=$(head -1 "$rinex_dir/$rinexnav" | cut -c 6-6)
        case "$rinexver" in
        "2" )
            head -1 "$rinex_dir/$rinexnav" | grep -Eq "GLO"       && sys="R"
            head -1 "$rinex_dir/$rinexnav" | grep -Eq "GAL"       && sys="E"
            head -1 "$rinex_dir/$rinexnav" | grep -Eq "(COM|BEI)" && sys="C"
            head -1 "$rinex_dir/$rinexnav" | grep -Eq "QZS"       && sys="J"
            grep -q "^ $sys[0-9][0-9] " "$config" && nsys=$[$nsys+1]
            echo -e "$MSGWAR using single-GNSS($sys) RINEX navigation file: $rinexnav"
            ;;
        "3" )
            local avail_sys=("G" "R" "E" "C" "J")
            for sys in ${avail_sys[@]}; do
               grep -Eq "^ $sys[0-9][0-9] " "$config" || continue
               grep -Eq "^$sys[ 0-9][0-9] " "$rinex_dir/$rinexnav" && nsys=$[$nsys+1]
               if [ $? -ne 0 ]; then
                   echo -e "$MSGWAR no $sys satellite in RINEX navigation file: $rinexnav"
               fi
            done
            ;;
        esac
        if [ "$nsys" -eq 0 ]; then
            echo -e "$MSGERR all GNSS in RINEX navigation file have been disabled: $rinexnav"
            exit 1
        fi
    done

    echo -e "$MSGSTA PrepareRinexNav done"
}

PrepareProducts() { # purpose : prepare PRIDE-PPPAR needed products in working directory
                    # usage   : PrepareProducts mjd_s mjd_e product_dir config AR(A/Y/N)
    local mjd_s="$1"
    local mjd_e="$2"
    local product_dir="$3"
    local config="$4"
    local AR="$5"

    local ydoy_s=($(mjd2ydoy $mjd_s))
    local ymd_s=($(ydoy2ymd ${ydoy_s[*]}))
    local doy_s=${ydoy_s[1]}

    echo -e "$MSGSTA PrepareProducts ..."

    if [ "$product_dir" == "Default" ]; then
       product_dir="$(readlink -f ..)/product/"
       sed -i "/^Product directory/s/ = .*/ = ${product_dir//\//\\/}/" "$config"
    fi

    product_cmn_dir="$product_dir/common"
    product_ion_dir="$product_dir/ion"
    product_vmf_dir="$product_dir/vmf"
    product_ssc_dir="$product_dir/ssc"

    mkdir -p "$product_cmn_dir"

    # Satellite orbit
    local custom_pro_sp3=$(get_ctrl "$config" "Satellite orbit")
    if [ "$custom_pro_sp3" != Default ]; then
        local sp3="$custom_pro_sp3"
        for sp3 in $custom_pro_sp3; do
            local sp3_url="$sp3"
            CopyOrDownloadProduct "$product_cmn_dir/$sp3" "$sp3_url"
            if [ $? -ne 0 ]; then
                CopyOrDownloadProduct "$product_dir/$sp3" "$sp3_url"
                if [ $? -ne 0 ]; then
                    echo -e "$MSGERR PrepareProducts: no such file: $sp3"
                    return 1
                fi
            fi          
        done
        local argnum=$(echo "$custom_pro_sp3" | wc -w)
        if [ $argnum -gt 1 ]; then    
            sp3="mersp3_${ymd_s}${doy_s}"
            MergeFiles "$(pwd)" "$custom_pro_sp3" "$sp3"
            if [ $? -ne 0 ]; then
                echo -e "$MSGERR PrepareProducts: $sp3 merge failed"
                return 1
            fi
            rm -f $custom_pro_sp3
        fi
    else
        local custom_pro_sp3=""
        for mjd in $(seq $mjd_s $mjd_e); do
            local ydoy=($(mjd2ydoy $mjd))
            local wkdow=($(mjd2wkdow $mjd))
            if [ $mjd_s -ge 58849 ]; then
                local sp3="WUM0MGXRAP_${ydoy[0]}${ydoy[1]}0000_01D_01M_ORB.SP3"
                local sp3_cmp="${sp3}.gz"
                local sp3_url="ftp://igs.gnsswhu.cn/pub/whu/phasebias/${ydoy[0]}/orbit/${sp3_cmp}"
            elif [ $mjd_s -ge 56658 ]; then
                local sp3="COM${wkdow[0]}${wkdow[1]}.EPH"
                local sp3_cmp="${sp3}.Z"
                local sp3_url="ftp://ftp.aiub.unibe.ch/CODE_MGEX/CODE/${ydoy[0]}/${sp3_cmp}"
            elif [ $mjd_s -ge 52581 ]; then
                local sp3="COD${wkdow[0]}${wkdow[1]}.EPH"
                local sp3_cmp="${sp3}.Z"
                local sp3_url="ftp://ftp.aiub.unibe.ch/CODE/${ydoy[0]}/${sp3_cmp}"
            else
                echo -e "$MSGERR no available ephemeris product before MJD 52581" && return 1
            fi
            CopyOrDownloadProduct "$product_cmn_dir/$sp3" "$sp3"
            if [ $? -ne 0 ]; then
                CopyOrDownloadProduct "$product_cmn_dir/$sp3_cmp" "$sp3_url"
                if [ $? -ne 0 ] && [[ "$sp3" == WUM0MGXRAP* ]]; then
                    echo -e "$MSGWAR PrepareProducts: $sp3_cmp download failed, try using RTS product"
                    sp3="WUM0MGXRTS_${ydoy[0]}${ydoy[1]}0000_01D_01M_ORB.SP3"
                    sp3_cmp="${sp3}.gz"
                    sp3_url="ftp://igs.gnsswhu.cn/pub/whu/phasebias/${ydoy[0]}/orbit/${sp3_cmp}"
                    if [ -f "$product_cmn_dir/$sp3_cmp" ]; then
                        size_last=$(ls -l "$product_cmn_dir/$sp3_cmp" | awk '{print($5)}')
                        size_next=$(curl "$(dirname $sp3_url)/" | grep "$sp3" | awk '{print($5)}')
                        if [ $? -eq 0 ]; then
                           if [ "$size_next" -gt "$size_last" ]; then
                               rm -f "$sp3"* "$product_cmn_dir/$sp3"*
                           fi
                        fi
                    fi
                    CopyOrDownloadProduct "$product_cmn_dir/$sp3" "$sp3"
                    if [ $? -ne 0 ]; then
                        CopyOrDownloadProduct "$product_cmn_dir/$sp3_cmp" "$sp3_url"
                        if [ $? -ne 0 ]; then
                            echo -e "$MSGERR PrepareProducts: $sp3_cmp download failed"
                            return 1
                        fi
                    fi
                   custom_pro_att="None"
                   local att="$custom_pro_att"
                   sed -i "/Quaternions/s/Default/$att/g" "$config"
                   custom_pro_fcb="None"
                   local fcb="$custom_pro_fcb"
                   sed -i "/Code\/phase bias/s/Default/$fcb/g" "$config"
                fi
            fi
            [ -f "$sp3_cmp" ] && gunzip -f "$sp3_cmp"
            sed -i "/Satellite orbit/s/Default/$sp3 &/" "$config"
            custom_pro_sp3="$custom_pro_sp3 $sp3"
        done
        sed -i "/Satellite orbit/s/Default//g" "$config"
        local argnum=$(echo "$custom_pro_sp3" | wc -w)
        if [ $argnum -gt 1 ]; then    
            sp3="mersp3_${ymd_s}${doy_s}"
            MergeFiles "$(pwd)" "$custom_pro_sp3" "$sp3"
            if [ $? -ne 0 ]; then
                echo -e "$MSGERR PrepareProducts: $sp3 merge failed"
                return 1
            fi
            rm -f $custom_pro_sp3
        fi        
    fi

    # Satellite clock
    local custom_pro_clk=$(get_ctrl "$config" "Satellite clock")
    if [ "$custom_pro_clk" != Default ]; then        
        local clk="$custom_pro_clk"
        for clk in $custom_pro_clk; do
            local clk_url="$clk"
            CopyOrDownloadProduct "$product_cmn_dir/$clk" "$clk_url"
            if [ $? -ne 0 ]; then
                CopyOrDownloadProduct "$product_dir/$clk" "$clk_url"
                if [ $? -ne 0 ]; then
                    echo -e "$MSGERR PrepareProducts: no such file: $clk"
                    return 1
                fi
            fi          
        done
        local argnum=$(echo "$custom_pro_clk" | wc -w)
        if [ $argnum -gt 1 ]; then    
            clk="mersck_${ymd_s}${doy_s}"
            MergeFiles "$(pwd)" "$custom_pro_clk" "$clk"
            if [ $? -ne 0 ]; then
                echo -e "$MSGERR PrepareProducts: $clk merge failed"
                return 1
            fi
            rm -f $custom_pro_clk
        fi        
    else
        local custom_pro_clk=""
        for mjd in $(seq $mjd_s $mjd_e); do
            local ydoy=($(mjd2ydoy $mjd))
            local wkdow=($(mjd2wkdow $mjd))
            if [ $mjd_s -ge 58849 ]; then
                local clk="WUM0MGXRAP_${ydoy[0]}${ydoy[1]}0000_01D_30S_CLK.CLK"
                local clk_cmp="${clk}.gz"
                local clk_url="ftp://igs.gnsswhu.cn/pub/whu/phasebias/${ydoy[0]}/clock/${clk_cmp}"
            elif [ $mjd_s -ge 56658 ]; then
                local clk="COM${wkdow[0]}${wkdow[1]}.CLK"
                local clk_cmp="${clk}.Z"
                local clk_url="ftp://ftp.aiub.unibe.ch/CODE_MGEX/CODE/${ydoy[0]}/${clk_cmp}"
            elif [ $mjd_s -ge 51601 ]; then
                local clk="COD${wkdow[0]}${wkdow[1]}.CLK"
                local clk_cmp="${clk}.Z"
                local clk_url="ftp://ftp.aiub.unibe.ch/CODE/${ydoy[0]}/${clk_cmp}"
            else
                echo -e "$MSGERR no available clock product before MJD 51601" && return 1
            fi
            CopyOrDownloadProduct "$product_cmn_dir/$clk" "$clk"
            if [ $? -ne 0 ]; then
                CopyOrDownloadProduct "$product_cmn_dir/$clk_cmp" "$clk_url"
                if [ $? -ne 0 ] && [[ $clk == WUM0MGXRAP* ]]; then
                    echo -e "$MSGWAR PrepareProducts: $clk_cmp download failed, try using RTS product"
                    clk="WUM0MGXRTS_${ydoy[0]}${ydoy[1]}0000_01D_05S_CLK.CLK"
                    clk_cmp="${clk}.gz"
                    clk_url="ftp://igs.gnsswhu.cn/pub/whu/phasebias/${ydoy[0]}/clock/${clk_cmp}"
                    if [ -f "$product_cmn_dir/$clk_cmp" ]; then
                        size_last=$(ls -l "$product_cmn_dir/$clk_cmp" | awk '{print($5)}')
                        size_next=$(curl "$(dirname $clk_url)/" | grep "$clk" | awk '{print($5)}')
                        if [ $? -eq 0 ]; then
                           if [ "$size_next" -gt "$size_last" ]; then
                               rm -f "$clk"* "$product_cmn_dir/$clk"*
                           fi
                        fi
                    fi
                    CopyOrDownloadProduct "$product_cmn_dir/$clk" "$clk"
                    if [ $? -ne 0 ]; then
                        CopyOrDownloadProduct "$product_cmn_dir/$clk_cmp" "$clk_url"
                        if [ $? -ne 0 ]; then
                            echo -e "$MSGERR PrepareProducts: $clk_cmp download failed"
                            return 1
                        fi
                    fi
                fi
            fi
            [ -f "$clk_cmp" ] && gunzip -f "$clk_cmp"
            sed -i "/Satellite clock/s/Default/$clk &/" "$config"
            custom_pro_clk="$custom_pro_clk $clk"
        done
        sed -i "/Satellite clock/s/Default//g" "$config"
        local argnum=$(echo "$custom_pro_clk" | wc -w)
        if [ $argnum -gt 1 ]; then    
            clk="mersck_${ymd_s}${doy_s}"
            MergeFiles "$(pwd)" "$custom_pro_clk" "$clk"
            if [ $? -ne 0 ]; then
                echo -e "$MSGERR PrepareProducts: $clk merge failed"
                return 1
            fi
            rm -f $custom_pro_clk
        fi        
    fi

    # Earth rotation parameters
    local custom_pro_erp=$(get_ctrl "$config" "ERP")
    if [ "$custom_pro_erp" != Default ]; then
        local erp="$custom_pro_erp"
        for erp in $custom_pro_erp; do
            local erp_url="$erp"
            CopyOrDownloadProduct "$product_cmn_dir/$erp" "$erp_url"
            if [ $? -ne 0 ]; then
                CopyOrDownloadProduct "$product_dir/$erp" "$erp_url"
                if [ $? -ne 0 ]; then
                    echo -e "$MSGERR PrepareProducts: no such file: $erp"
                    return 1
                fi
            fi          
        done
        local argnum=$(echo "$custom_pro_erp" | wc -w)
        if [ $argnum -gt 1 ]; then    
            erp="mererp_${ymd_s}${doy_s}"
            MergeFiles "$(pwd)" "$custom_pro_erp" "$erp"
            if [ $? -ne 0 ]; then
                echo -e "$MSGERR PrepareProducts: $erp merge failed"
                return 1
            fi
            rm -f $custom_pro_erp
        fi
    else
        local custom_pro_erp=""
        for mjd in $(seq $mjd_s $mjd_e); do
            local ydoy=($(mjd2ydoy $mjd))
            local wkdow=($(mjd2wkdow $mjd))
            if [ $mjd_s -ge 58849 ]; then
                local erp="WUM0MGXRAP_${ydoy[0]}${ydoy[1]}0000_01D_01D_ERP.ERP"
                local erp_cmp="${erp}.gz"
                local erp_url="ftp://igs.gnsswhu.cn/pub/whu/phasebias/${ydoy[0]}/orbit/${erp_cmp}"
            elif [ $mjd_s -ge 56658 ]; then
                local erp="COM${wkdow[0]}${wkdow[1]}.ERP"
                local erp_cmp="${erp}.Z"
                local erp_url="ftp://ftp.aiub.unibe.ch/CODE_MGEX/CODE/${ydoy[0]}/${erp_cmp}"
            elif [ $mjd_s -ge 56187 ]; then
                local erp="COD${wkdow[0]}${wkdow[1]}.ERP"
                local erp_cmp="${erp}.Z"
                local erp_url="ftp://ftp.aiub.unibe.ch/CODE/${ydoy[0]}/${erp_cmp}"
            elif [ $mjd_s -ge 48792 ]; then
                local erp="COD${wkdow[0]}7.ERP"
                local erp_cmp="${erp}.Z"
                local erp_url="ftp://ftp.aiub.unibe.ch/CODE/${ydoy[0]}/${erp_cmp}"
            else
                echo -e "$MSGERR no available ERP product before MJD 48792" && return 1
            fi
            CopyOrDownloadProduct "$product_cmn_dir/$erp" "$erp"
            if [ $? -ne 0 ]; then
                CopyOrDownloadProduct "$product_cmn_dir/$erp_cmp" "$erp_url"
                if [ $? -ne 0 ] && [[ $erp == WUM0MGXRAP* ]]; then
                    echo -e "$MSGWAR PrepareProducts: $erp_cmp download failed, try using RTS product"
                    erp="WUM0MGXRTS_${ydoy[0]}${ydoy[1]}0000_01D_01D_ERP.ERP"
                    erp_cmp="${erp}.gz"
                    erp_url="ftp://igs.gnsswhu.cn/pub/whu/phasebias/${ydoy[0]}/orbit/${erp_cmp}"
                    if [ -f "$product_cmn_dir/$erp_cmp" ]; then
                        size_last=$(ls -l "$product_cmn_dir/$erp_cmp" | awk '{print($5)}')
                        size_next=$(curl "$(dirname $erp_url)/" | grep "$erp" | awk '{print($5)}')
                        if [ $? -eq 0 ]; then
                           if [ "$size_next" -gt "$size_last" ]; then
                               rm -f "$erp"* "$product_cmn_dir/$erp"*
                           fi
                        fi
                    fi
                    CopyOrDownloadProduct "$product_cmn_dir/$erp" "$erp"
                    if [ $? -ne 0 ]; then
                        CopyOrDownloadProduct "$product_cmn_dir/$erp_cmp" "$erp_url"
                        if [ $? -ne 0 ]; then
                            echo -e "$MSGERR PrepareProducts: $erp_cmp download failed"
                            return 1
                        fi
                    fi
                fi
            fi
            [ -f "$erp_cmp" ] && gunzip -f "$erp_cmp"
            sed -i "/ERP/s/Default/$erp &/" "$config"
            custom_pro_erp="$custom_pro_erp $erp"
        done
        sed -i "/ERP/s/Default//g" "$config"
        local argnum=$(echo "$custom_pro_erp" | wc -w)
        if [ $argnum -gt 1 ]; then    
            erp="mererp_${ymd_s}${doy_s}"
            MergeFiles "$(pwd)" "$custom_pro_erp" "$erp"
            if [ $? -ne 0 ]; then
                echo -e "$MSGERR PrepareProducts: $erp merge failed"
                return 1
            fi
            rm -f $custom_pro_erp
        fi
    fi

    # Quaternions
    local custom_pro_att=$(get_ctrl "$config" "Quaternions")
    if [ "$custom_pro_att" != Default ]; then
        local att="${custom_pro_att}"
        if [ "$(echo "$custom_pro_att" | tr 'a-z' 'A-Z')" != NONE ]; then
            for att in $custom_pro_att; do
                local att_url="$att"
                CopyOrDownloadProduct "$product_cmn_dir/$att" "$att_url"
                if [ $? -ne 0 ]; then
                    CopyOrDownloadProduct "$product_dir/$att" "$att_url"
                    if [ $? -ne 0 ]; then
                        echo -e "$MSGERR PrepareProducts: no such file: $att"
                        return 1
                    fi
                fi          
            done
            local argnum=$(echo "$custom_pro_att" | wc -w)
            if [ $argnum -gt 1 ]; then    
                att="meratt_${ymd_s}${doy_s}"
                MergeFiles "$(pwd)" "$custom_pro_att" "$att"
                if [ $? -ne 0 ]; then
                    echo -e "$MSGERR PrepareProducts: $att merge failed"
                    return 1
                fi
                rm -f $custom_pro_att
            fi
        fi
    else
        local custom_pro_att=""
        for mjd in $(seq $mjd_s $mjd_e); do
            local ydoy=($(mjd2ydoy $mjd))
            if [ $mjd_s -ge 58849 ]; then
                local att="WUM0MGXRAP_${ydoy[0]}${ydoy[1]}0000_01D_30S_ATT.OBX"
                local att_cmp="${att}.gz"
                local att_url="ftp://igs.gnsswhu.cn/pub/whu/phasebias/${ydoy[0]}/orbit/${att_cmp}"
            else
                custom_pro_att="None"
                local att="${custom_pro_att}"
                sed -i "/Quaternions/s/Default/$att/g" "$config"
                break
            fi
            CopyOrDownloadProduct "$product_cmn_dir/$att" "$att"
            if [ $? -ne 0 ]; then
                CopyOrDownloadProduct "$product_cmn_dir/$att_cmp" "$att_url"
                if [ $? -ne 0 ]; then
                    echo -e "$MSGWAR PrepareProducts: $att_cmp download failed"
                fi
            fi
            [ -f "$att_cmp" ] && gunzip -f "$att_cmp"
            sed -i "/Quaternions/s/Default/$att &/" "$config"
            custom_pro_att="$custom_pro_att $att"
        done
        sed -i "/Quaternions/s/Default//g" "$config"
        local argnum=$(echo "$custom_pro_att" | wc -w)
        if [ $argnum -gt 1 ]; then    
            att="meratt_${ymd_s}${doy_s}"
            MergeFiles "$(pwd)" "$custom_pro_att" "$att"
            if [ $? -ne 0 ]; then
                echo -e "$MSGERR PrepareProducts: $att merge failed"
                return 1
            fi
            rm -f $custom_pro_att
        fi
    fi

    # Code/phase bias
    local custom_pro_fcb=$(get_ctrl "$config" "Code/phase bias")
    if [ "$custom_pro_fcb" != Default ]; then
        local fcb="$custom_pro_fcb"
        if [ "$(echo "$custom_pro_fcb" | tr 'a-z' 'A-Z')" != NONE ]; then
            for fcb in $custom_pro_fcb; do
                local fcb_url="$fcb"
                CopyOrDownloadProduct "$product_cmn_dir/$fcb" "$fcb_url"
                if [ $? -ne 0 ]; then
                    CopyOrDownloadProduct "$product_dir/$fcb" "$fcb_url"
                    if [ $? -ne 0 ]; then
                        echo -e "$MSGWAR PrepareProducts: no such file: $fcb"
                        [ $AR == Y ] && echo -e "$MSGERR no phase bias product: $fcb" && return 1
                    fi
                fi
            done
            local argnum=$(echo "$custom_pro_fcb" | wc -w)
            if [ $argnum -gt 1 ]; then    
                fcb="merfcb_${ymd_s}${doy_s}"
                MergeFiles "$(pwd)" "$custom_pro_fcb" "$fcb"
                if [ $? -ne 0 ]; then
                    echo -e "$MSGERR PrepareProducts: $fcb merge failed"
                    return 1
                fi
                rm -f $custom_pro_fcb
            fi
        fi
    else
        local custom_pro_fcb=""
        for mjd in $(seq $mjd_s $mjd_e); do
            local ydoy=($(mjd2ydoy $mjd))
            local wkdow=($(mjd2wkdow $mjd))
            if [ $mjd_s -ge 58849 ]; then
                local fcb="WUM0MGXRAP_${ydoy[0]}${ydoy[1]}0000_01D_01D_ABS.BIA"
                local fcb_cmp="${fcb}.gz"
                local fcb_url="ftp://igs.gnsswhu.cn/pub/whu/phasebias/${ydoy[0]}/bias/${fcb_cmp}"
            elif [ $mjd_s -ge 58300 ]; then
                local fcb="COM${wkdow[0]}${wkdow[1]}.BIA"
                local fcb_cmp="${fcb}.Z"
                local fcb_url="ftp://ftp.aiub.unibe.ch/CODE_MGEX/CODE/${ydoy[0]}/${fcb_cmp}"
            else
                [ $AR == Y ] && echo -e "$MSGERR no available phase bias product before MJD 58300" && return 1
                custom_pro_fcb="None"
                local fcb="$custom_pro_fcb"
                sed -i "/Code\/phase bias/s/Default/$fcb/g" "$config"
                break
            fi
            CopyOrDownloadProduct "$product_cmn_dir/$fcb" "$fcb"
            if [ $? -ne 0 ]; then
                CopyOrDownloadProduct "$product_cmn_dir/$fcb_cmp" "$fcb_url"
                if [ $? -ne 0 ]; then
                    echo -e "$MSGWAR PrepareProducts: $fcb_cmp download failed"
                    [ $AR == Y ] && echo -e "$MSGERR no phase bias product: $fcb" && return 1
                fi
            fi
            [ -f "$fcb_cmp" ] && gunzip -f "$fcb_cmp"
            sed -i "/Code\/phase bias/s/Default/$fcb &/" "$config"
            custom_pro_fcb="$custom_pro_fcb $fcb"
        done
        sed -i "/Code\/phase bias/s/Default//g" "$config"
        local argnum="$(echo $custom_pro_fcb | wc -w)"
        if [ $argnum -gt 1 ]; then    
            fcb="merfcb_${ymd_s}${doy_s}"
            MergeFiles "$(pwd)" "$custom_pro_fcb" "$fcb"
            if [ $? -ne 0 ]; then
                echo -e "$MSGERR PrepareProducts: $fcb merge failed"
                return 1
            fi
            rm -f $custom_pro_fcb
        fi        
    fi

    # Check version of ephemeris
    if [ -f "$sp3" ]; then
        grep -q "#a" "$sp3"
        if [ $? -eq 0 ]; then
            echo -e "$MSGERR unsupproted ephemeris version (#a): $custom_pro_sp3" && return 1
        fi
    fi 

    # Check type of bias product
    if [ -f "$fcb" ]; then
        grep -q "^ OSB " "$fcb"
        if [ $? -ne 0 ]; then
            if [ $AR == Y ]; then
                 echo -e "$MSGERR unsupported phase bias type (not OSB): $custom_pro_fcb" && return 1
            else
                 echo -e "$MSGWAR unsupported phase bias type (not OSB): $custom_pro_fcb"
                 rm -f "$fcb"
            fi
        fi
    fi
    
    # IGS ANTEX
    local abs_atx abs_url
    abs_atx="$(grep "SYS / PCVS APPLIED" $clk | head -1 | cut -c21-34 | tr 'A-Z' 'a-z' | sed 's/r3/R3/; s/ //g')"
    echo "$custom_pro_clk" | grep -qE "^ *(COD0MGX|COM)"
    if [[ $? -eq 0 ]] && [[ $abs_atx == "igs14" ]]; then
        [[ "$mjd_s" -le 59336 ]] && abs_atx="M14.ATX" || abs_atx="M20.ATX"
        atx_url="ftp://ftp.aiub.unibe.ch/CODE_MGEX/CODE/$abs_atx"
    fi

    if [ -n "$abs_atx" ]; then
        [[ "$abs_atx" =~ \.(ATX|atx)$ ]] || abs_atx="${abs_atx}.atx"
        echo -e "$MSGINF Prepare IGS ANTEX product: $abs_atx ..."
    else
        abs_atx="igs14_2196.atx"
        echo -e "$MSGINF Prepare IGS ANTEX product: $abs_atx ..."
        echo -e "$MSGWAR no PCO/PCV model defined in $clk, use default instead"
    fi

    if [ -f "$table_dir/$abs_atx" ]; then
        ln -sf "$table_dir/$abs_atx" abs_igs.atx
    else
        if [ -n "$atx_url" ]; then
            WgetDownload "$atx_url"
            if [ $? -ne 0 ]; then
                echo -e "$MSGERR PrepareProducts: failed to download $abs_atx"
                echo -e "$MSGINF please download this file from $atx_url"
                return 1
            fi
        elif [[ $abs_atx =~ ^igs(05|08|14) ]]; then
            atx_url="https://files.igs.org/pub/station/general/$abs_atx"
            WgetDownload "$atx_url"
            if [ $? -ne 0 ]; then
                atx_url="https://files.igs.org/pub/station/general/pcv_archive/$abs_atx"
                WgetDownload "$atx_url"
                if [ $? -ne 0 ]; then
                    echo -e "$MSGERR PrepareProducts: failed to download $abs_atx"
                    return 1
                fi
            fi
        elif [[ $abs_atx =~ ^igsR3 ]]; then
            atx_url="ftp://igs-rf.ign.fr/pub/IGSR3/$abs_atx"
            WgetDownload "$atx_url"
            if [ $? -ne 0 ]; then
                atx_url="ftp.aiub.unibe.ch/users/villiger/$abs_atx"
                WgetDownload "$atx_url"
                if [ $? -ne 0 ]; then
                    echo -e "$MSGERR PrepareProducts: failed to download $abs_atx"
                    return 1
                fi
            fi
        fi
        if [ -f "$abs_atx" ]; then
            [ -f "$table_dir/$abs_atx" ] || cp -f "$abs_atx" "$table_dir/"
            mv -f "$abs_atx" abs_igs.atx
        else
            echo -e "$MSGERR PrepareProducts: no IGS ANTEX file: $table_dir/$abs_atx"
            return 1
        fi
    fi

    echo -e "$MSGINF Prepare IGS ANTEX product: $abs_atx done"

    # Precise station coordinate
    local mode=$(grep "^ .... [KSF]" "$config" | cut -c 7)
    if [ "$mode" == "F" ]; then
        mkdir -p "$product_ssc_dir"
        local wkdow=($(mjd2wkdow $mjd_s))
        local ssc="igs${ymd_s:2:2}P${wkdow[0]}${wkdow[1]}.ssc"
        local ssc_cmp="${ssc}.Z"
        CopyOrDownloadProduct "$product_ssc_dir/$ssc" "$ssc"
        if [ $? -ne 0 ]; then
            for ssc_url in "ftp://igs.gnsswhu.cn/pub/gps/products/$wkdow" \
                           "ftp://nfs.kasi.re.kr/gps/products/$wkdow"     \
                           "ftp://gssc.esa.int/cddis/gnss/products/$wkdow"; do
                CopyOrDownloadProduct "$product_ssc_dir/$ssc_cmp" "$ssc_url/$ssc_cmp"
                [ $? -eq 0 ] && break
            done
            if [ ! -f "$ssc_cmp" ]; then
                echo -e "$MSGWAR PrepareProducts: $ssc_cmp download failed"
                echo -e "$MSGERR no station coordinate product: $ssc"
                return 1
            fi
        fi
        [ -f "$ssc_cmp" ] && gunzip -f "$ssc_cmp"
    fi

    # High-order ionospheric grid
    local ion tec num
    if [ "$(get_ctrl "$config" "Iono 2nd")" == "YES" ]; then
        echo -e "$MSGSTA Downloading High-order Ion Grid ..."
        mkdir -p "$product_ion_dir"
        for mjd in $(seq $mjd_s $mjd_e); do
            local ydoy=($(mjd2ydoy $mjd))
            local ion_tmp="CODG${ydoy[1]}0.${ydoy[0]:2:2}I"
            local ion_cmp="${ion_tmp}.Z"
            local ion_url="ftp://ftp.aiub.unibe.ch/CODE/${ydoy[0]}/${ion_cmp}"
            CopyOrDownloadProduct "$product_ion_dir/$ion_tmp" "$ion_tmp"
            if [ $? -ne 0 ]; then
                CopyOrDownloadProduct "$product_ion_dir/$ion_cmp" "$ion_url"
                if [ $? -ne 0 ]; then
                    echo -e "$MSGERR PrepareProducts: $ion_cmp download failed"
                    return 1
                fi
            fi
            [ -f "$ion_cmp" ] && gunzip -f "$ion_cmp"
            ion="$ion $ion_tmp"
        done
        echo -e "$MSGSTA Downloading High-order Ion Grid done"
        tec="tec_${ymd_s}${doy_s}"
        num="$(echo $ion | wc -w)"
        if [ $num -gt 1 ]; then    
            MergeFiles "$(pwd)" "$ion" "$tec"
            if [ $? -ne 0 ]; then
                echo -e "$MSGERR PrepareProducts: $tec merge failed"
                return 1
            fi
            rm -f "$ion"
        else
            mv -f "$ion_tmp" "$tec"
            if [ $? -ne 0 ]; then
                echo -e "$MSGERR PrepareProducts: $tec rename failed"
                return 1
            fi
        fi
    fi

    # Vienna mapping function grid
    local tmpy mjd hour

    grep '^ [0-9a-zA-Z]\{4\} .*VM1' "$config" &>/dev/null
    if [ $? -eq 0 ]; then
        echo -e "$MSGSTA Downloading VMF1 Grid ..."
        mkdir -p "$product_vmf_dir"

        # Previous Day (for interpolation)
        tmpy=($(mjd2ydoy $((mjd_s-1))))
        tmpy=($(ydoy2ymd ${tmpy[*]}))
        local vmf="VMFG_${tmpy[0]}${tmpy[1]}${tmpy[2]}.H18"
        local vmf_url="http://vmf.geo.tuwien.ac.at/trop_products/GRID/2.5x2/VMF1/VMF1_OP/${tmpy[0]}/${vmf}"
        CopyOrDownloadProduct "$product_vmf_dir/$vmf" "$vmf"
        if [ $? -ne 0 ]; then
            CopyOrDownloadProduct "$product_vmf_dir/$vmf" "$vmf_url"
            if [ $? -ne 0 ]; then
                echo -e "$MSGERR PrepareProducts: $vmf download failed"
                return 1
            fi
        fi

        # Current Day (for interpolation)
        for mjd in $(seq $mjd_s $mjd_e); do
            tmpy=($(mjd2ydoy $((mjd))))
            tmpy=($(ydoy2ymd ${tmpy[*]}))
            for hour in $(seq -w 00 06 18); do
                vmf="VMFG_${tmpy[0]}${tmpy[1]}${tmpy[2]}.H${hour}"
                vmf_url="http://vmf.geo.tuwien.ac.at/trop_products/GRID/2.5x2/VMF1/VMF1_OP/${tmpy[0]}/${vmf}"
                CopyOrDownloadProduct "$product_vmf_dir/$vmf" "$vmf"
                if [ $? -ne 0 ]; then
                    CopyOrDownloadProduct "$product_vmf_dir/$vmf" "$vmf_url"
                    if [ $? -ne 0 ]; then
                        echo -e "$MSGERR PrepareProducts: $vmf download failed"
                        return 1
                    fi
                fi
            done
        done

        # Next Day (for interpolation)
        tmpy=($(mjd2ydoy $((mjd_e+1))))
        tmpy=($(ydoy2ymd ${tmpy[*]}))
        vmf="VMFG_${tmpy[0]}${tmpy[1]}${tmpy[2]}.H00"
        vmf_url="http://vmf.geo.tuwien.ac.at/trop_products/GRID/2.5x2/VMF1/VMF1_OP/${tmpy[0]}/${vmf}"
        CopyOrDownloadProduct "$product_vmf_dir/$vmf" "$vmf"
        if [ $? -ne 0 ]; then
            CopyOrDownloadProduct "$product_vmf_dir/$vmf" "$vmf_url"
            if [ $? -ne 0 ]; then
                echo -e "$MSGERR PrepareProducts: $vmf download failed"
                return 1
            fi
        fi

        cat VMFG_* > vmf_${ymd_s}${doy_s} || return 1
        echo -e "$MSGSTA Downloading VMF1 Grid done"
    fi

    grep '^ [0-9a-zA-Z]\{4\} .*VM3' "$config" &>/dev/null
    if [ $? -eq 0 ]; then
        echo -e "$MSGSTA Downloading VMF3 Grid ..."
        mkdir -p "$product_vmf_dir"

        # Previous Day (for interpolation)
        tmpy=($(mjd2ydoy $((mjd_s-1))))
        tmpy=($(ydoy2ymd ${tmpy[*]}))
        local vmf="VMF3_${tmpy[0]}${tmpy[1]}${tmpy[2]}.H18"
        local vmf_url="http://vmf.geo.tuwien.ac.at/trop_products/GRID/1x1/VMF3/VMF3_OP/${tmpy[0]}/${vmf}"
        CopyOrDownloadProduct "$product_vmf_dir/$vmf" "$vmf"
        if [ $? -ne 0 ]; then
            CopyOrDownloadProduct "$product_vmf_dir/$vmf" "$vmf_url"
            if [ $? -ne 0 ]; then
                echo -e "$MSGERR PrepareProducts: $vmf download failed"
                return 1
            fi
        fi

        # Current Day (for interpolation)
        for mjd in $(seq $mjd_s $mjd_e); do
            tmpy=($(mjd2ydoy $((mjd))))
            tmpy=($(ydoy2ymd ${tmpy[*]}))
            for hour in $(seq -w 00 06 18); do
                vmf="VMF3_${tmpy[0]}${tmpy[1]}${tmpy[2]}.H${hour}"
                vmf_url="http://vmf.geo.tuwien.ac.at/trop_products/GRID/1x1/VMF3/VMF3_OP/${tmpy[0]}/${vmf}"
                CopyOrDownloadProduct "$product_vmf_dir/$vmf" "$vmf"
                if [ $? -ne 0 ]; then
                    CopyOrDownloadProduct "$product_vmf_dir/$vmf" "$vmf_url"
                    if [ $? -ne 0 ]; then
                        echo -e "$MSGERR PrepareProducts: $vmf download failed"
                        return 1
                    fi
                fi
            done
        done

        # Next Day (for interpolation)
        tmpy=($(mjd2ydoy $((mjd_e+1))))
        tmpy=($(ydoy2ymd ${tmpy[*]}))
        vmf="VMF3_${tmpy[0]}${tmpy[1]}${tmpy[2]}.H00"
        vmf_url="http://vmf.geo.tuwien.ac.at/trop_products/GRID/1x1/VMF3/VMF3_OP/${tmpy[0]}/${vmf}"
        CopyOrDownloadProduct "$product_vmf_dir/$vmf" "$vmf"
        if [ $? -ne 0 ]; then
            CopyOrDownloadProduct "$product_vmf_dir/$vmf" "$vmf_url"
            if [ $? -ne 0 ]; then
                echo -e "$MSGERR PrepareProducts: $vmf download failed"
                return 1
            fi
        fi

        cat VMF3_* > vmf_${ymd_s}${doy_s} || return 1
        echo -e "$MSGSTA Downloading VMF3 Grid done"
    fi

    # Rename products
    mv -f ${clk} sck_${ymd_s}${doy_s} || return 1
    [ -e ${fcb} ] && mv -f ${fcb} fcb_${ymd_s}${doy_s}
    [ -e ${att} ] && mv -f ${att} att_${ymd_s}${doy_s}

    # Generate igserp
    mv -f ${erp} igserp || return 1

    echo -e "$MSGSTA PrepareProducts done"
}

MergeFiles() { # purpose : merge multiple files into a single one
               # usage   : MergeFiles dir infile outfile
    local dir="$1"
    local infile="$2"
    local outfile="$3"
    rm -f "$outfile"
    for f in $infile; do
        cat "$dir/$f" >> "$outfile"
    done
    [ -f "$outfile" ] && return 0 || return 1
}

CopyOrDownloadProduct() { # purpose : copy or download a product
                          # usage   : CopyOrDownloadProduct copy url
    local copy="$1"
    local url="$2"
    local file=$(basename "$copy")

    # Try using cache from path "copy"
    if [ "$OFFLINE" = "YES" ] || [ "$USECACHE" = "YES" ]; then
        if [ -f "$copy" ]; then
            cp -f "$copy" .
        elif [ -f "$copy".gz ]; then
            cp -f "$copy".gz . && gunzip -f "$file".gz
        elif [ -f "$copy".Z ]; then
            cp -f "$copy".Z  . && gunzip -f "$file".Z
        fi
    fi

    # Try downloading file from "url"
    if [ ! -f "$file" ]; then
        WgetDownload "$url" || return 1
        if [ "$OFFLINE" = "YES" ] || [ "$USECACHE" = "YES" ]; then
            ls "$copy".@(gz|Z) &>/dev/null || cp -f "$(basename "$url")" "$copy"
        fi
    fi

    [ -f "$file" ] && return 0 || return 1
}

WgetDownload() { # purpose : download a file with wget
                 # usage   : WgetDownload url
    local url="$1"
    local arg="-q -nv -nc -c -t 3 --connect-timeout=10 --read-timeout=60"
    [ "$OFFLINE" = "YES" ] && return 1
    wget --help | grep -q "\-\-show\-progress" && arg="$arg --show-progress"
    local cmd="wget $arg $url"
    echo "$cmd" | bash
    [ -e $(basename "$url") ] && return 0 || return 1
}

LastYearMonth() { # purpose : get last year-month
                  # usage   : LastYearMonth year month
    local year=$1
    local mon=$((10#$2))
    [ $((mon-1)) -lt 1  ] && mon=12 && year=$((year-1)) || mon=$((mon-1))
    printf "%4d %02d\n" $year $mon
}

CleanAll() { # purpose : clean all files generated by PRIDE-PPPAR in the work directory
             # usage   : CleanAll year doy
    local year=$1
    local doy=$2
    local types typ
    rm -f sit.xyz igserp config\.*
    types=(rck ztd htg amb res stt cst neq att fcb orb sck)
    for typ in ${types[*]}; do
        rm -f ${typ}_${year}${doy}
    done
    types=(log pos kin)
    for typ in ${types[*]}; do
        rm -f ${typ}_${year}${doy}_${site}
    done
}

CleanMid() { # purpose : clean the intermediate files generated by PRIDE-PPPAR in the work directory
             # usage   : CleanMid year doy
    local year=$1
    local doy=$2
    local types typ
    types=(rck ztd htg amb res stt cst neq)
    for typ in ${types[*]}; do
        rm -f ${typ}_${year}${doy}
    done
    types=(log pos kin)
    for typ in ${types[*]}; do
        rm -f ${typ}_${year}${doy}_${site}
    done
}

Execute() {
    local cmd="$1"
    if [ $# -gt 1 ]; then
        local outp="$2"
    fi
    time=$(date +'%Y-%m-%d %H:%M:%S')
    if [ $# -gt 1 ]; then
        echo "$cmd" | bash > "$outp"
    else
        echo "$cmd" | bash
    fi
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}($time)${NC} ${CYAN}$cmd${NC} executed ok"
        return 0
    else
        echo -e "${RED}($time)${NC} ${CYAN}$cmd${NC} executed failed"
        return 1
    fi
}

ExecuteWithoutOutput() {
    local cmd="$1"
    time=$(date +'%Y-%m-%d %H:%M:%S')
    echo "$cmd" | bash &>/dev/null
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}($time)${NC} ${CYAN}$cmd${NC} executed ok"
        return 0
    else
        echo -e "${RED}($time)${NC} ${CYAN}$cmd${NC} executed failed"
        echo -e "$MSGINF Here is the output:\n"
        echo "$cmd" | bash
        return 1
    fi
}

snx2sit() {
    local site="$1"
    local mjd="$2"
    local wkdow=($(mjd2wkdow $mjd))
    local ydoy=($(mjd2ydoy $mjd))
    local igsssc="igs${ydoy:2:2}P${wkdow[0]}${wkdow[1]}.ssc"
    awk -v sit=${site^^} 'BEGIN{fg=0;x=0.0;y=0.0;z=0.0;sigx=0.0;sigy=0.0;sigz=0.0;snam=" "}\
         {\
           if($1=="+SOLUTION/ESTIMATE"){fg=1};if($1=="-SOLUTION/ESTIMATE"){fg=0};\
           if(fg==1)\
           {\
             if($2=="STAX"){snam=$3;x=$9;sigx=$10};\
             if($2=="STAY"){y=$9;sigy=$10};\
             if($2=="STAZ"&&$3==sit)\
             {\
               z=$9;sigz=$10;printf(" %25.6f %25.6f %25.6f %25.6f %25.6f %25.6f\n",x,y,z,sigx,sigy,sigz);\
               snam=" ";x=0.0;y=0.0;z=0.0;sigx=0.0;sigy=0.0;sigz=0.0;\
             };\
           }\
         }' $igsssc
}

ymd2mjd() {
    local year=$1
    local mon=$((10#$2))
    local day=$((10#$3))
    [ $year -lt 100 ] && year=$((year+2000))
    if [ $mon -le 2 ];then
        mon=$(($mon+12))
        year=$(($year-1))
    fi
    local mjd=`echo $year | awk '{print $1*365.25-$1*365.25%1-679006}'`
    mjd=`echo $mjd $year $mon $day | awk '{print $1+int(30.6001*($3+1))+2-int($2/100)+int($2/400)+$4}'`
    echo $mjd
}

mjd2ydoy() {
    local mjd=$1
    local year=$((($mjd + 678940)/365))
    local mjd0=$(ymd2mjd $year 1 1)
    local doy=$(($mjd-$mjd0))
    while [ $doy -le 0 ];do
        year=$(($year-1))
        mjd0=$(ymd2mjd $year 1 1)
        doy=$(($mjd-$mjd0+1))
    done
    printf "%d %03d\n" $year $doy
}

ymd2wkdow() {
    local year=$1
    local mon=$2
    local day=$3
    local mjd0=44243
    local mjd=$(ymd2mjd $year $mon $day)
    local difmjd=$(($mjd-$mjd0-1))
    local week=$(($difmjd/7))
    local dow=$(($difmjd%7))
    printf "%04d %d\n" $week $dow
}

mjd2wkdow() {
    local mjd=$1
    local mjd0=44243
    local difmjd=$(($mjd-$mjd0-1))
    local week=$(($difmjd/7))
    local dow=$(($difmjd%7))
    printf "%04d %d\n" $week $dow
}

ydoy2ymd() {
    local iyear=$1
    local idoy=$((10#$2))
    local days_in_month=(31 28 31 30 31 30 31 31 30 31 30 31)
    local iday=0
    [ $iyear -lt 100 ] && iyear=$((iyear+2000))
    local tmp1=$(($iyear%4))
    local tmp2=$(($iyear%100))
    local tmp3=$(($iyear%400))
    if [ $tmp1 -eq 0 -a $tmp2 -ne 0 ] || [ $tmp3 -eq 0 ]; then
       days_in_month[1]=29
    fi
    local id=$idoy
    local imon=0
    local days
    for days in ${days_in_month[*]}
    do
        id=$(($id-$days))
        imon=$(($imon+1))
        if [ $id -gt 0 ]; then
            continue
        fi
        iday=$(($id + $days))
        break
    done
    printf "%d %02d %02d\n" $iyear $imon $iday
}

xyz2blh(){
    local x=$1
    local y=$2
    local z=$3
    echo "$x $y $z" | awk 'BEGIN{
            F = 298.257223563;
            A = 6378137.0;
            B = A - A/F;
            E = 1 - (B/A)^2;
         }{
            x=$1; y=$2; z=$3;
            d = sqrt(x^2+y^2);
            h0 = sqrt(d^2+z^2) - A;
            b0 = z/d/(1-E*A/(A+h));
            while (i++ < 5) {
                n = A/sqrt(1-E*(1/(1+1/b0^2)));
                h = d/(1/sqrt(1+b0^2)) - n;
                b = z/d + n/(n+h) * E * b0;
                h0 = h;
                b0 = b;
            }
         }END{
            b = atan2(b, 1) * 180/atan2(0, -1);
            l = atan2(y, x) * 180/atan2(0, -1);
            if (l < 0) l += 360;
            printf("%15.7f%15.7f%15.4f\n", b, l, h)
         }'
}

######################################################################
##                               Entry                              ##
######################################################################

main "$@"
