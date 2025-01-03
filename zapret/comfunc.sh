#!/bin/sh
# Copyright (c) 2024 remittor

EXEDIR=/opt/zapret
ZAPRET_BASE=/opt/zapret

ZAPRET_INITD=/etc/init.d/zapret
ZAPRET_ORIG_INITD="$ZAPRET_BASE/init.d/openwrt/zapret"

ZAPRET_CONFIG="$ZAPRET_BASE/config"
ZAPRET_CONFIG_NEW="$ZAPRET_BASE/config.new"
ZAPRET_CONFIG_DEF="$ZAPRET_BASE/config.default"

ZAPRET_CFG=/etc/config/zapret
ZAPRET_CFG_NAME=zapret
ZAPRET_CFG_SEC_NAME="$( uci -q get $ZAPRET_CFG_NAME.config )"

. $ZAPRET_BASE/def-cfg.sh

function adapt_for_sed
{
	local str=$( ( echo $1|sed -r 's/([\$\.\*\/\[\\^])/\\\1/g'|sed 's/[]]/\\]/g' )>&1 )
	echo "$str"
}

function is_valid_config
{
	local fname=${1:-$ZAPRET_CONFIG}
	sh -n "$fname" &>/dev/null
	return $?
}

function get_ppid_by_pid
{
	local pid=$1
	local ppid="$( cat /proc/$pid/status 2>/dev/null | grep '^PPid:' | awk '{print $2}' )"
	echo "$ppid"
}

function get_proc_path_by_pid
{
	local pid=$1
	local path=$( cat /proc/$pid/cmdline 2>/dev/null | tr '\0' '\n' | head -n1 )
	echo "$path"
}

function get_proc_cmd_by_pid
{
	local pid=$1
	local delim="$2"
	local cmdline
	if [ "$delim" = "" ]; then
		cmdline="$( cat /proc/$pid/cmdline 2>/dev/null | tr '\0' '\n' )"
	else
		cmdline="$( cat /proc/$pid/cmdline 2>/dev/null | tr '\0' "$delim" )"
	fi
	echo "$cmdline"
}

function is_run_via_procd
{
	local pname
	[ "$$" = "1" ] && return 0	
	pname="$( get_proc_path_by_pid $$ )"
	[ "$pname" = "/sbin/procd" ] && return 0
	[ "$PPID" = "1" ] && return 0
	pname="$( get_proc_path_by_pid $PPID )"
	[ "$pname" = "/sbin/procd" ] && return 0
	return 1
}

function is_run_on_boot
{
	local cmdline="$( get_proc_cmd_by_pid $$ ' ' )"
	if echo "$cmdline" | grep -q " /etc/rc.d/S" ; then
		if echo "$cmdline" | grep -q " boot $" ; then
			return 0
		fi
	fi
	return 1
}

function get_run_on_boot_option
{
	if [ "$( uci -q get $ZAPRET_CFG_NAME.config.run_on_boot )" = "1" ]; then
		echo 1
	else
		echo 0
	fi
}

function create_default_cfg
{
	local cfgname=${1:-$ZAPRET_CFG_NAME}
	local cfgfile=/etc/config/$cfgname
	rm -f $cfgfile
	touch $cfgfile
	uci set $cfgname.config=main
	set_cfg_default_values $cfgname
	return 0
}

function merge_cfg_with_def_values
{
	local cfgname=${1:-$ZAPRET_CFG_NAME}
	local force=$2
	local cfgfile=/etc/config/$cfgname
	local NEWCFGNAME="zapret-default"
	local NEWCFGFILE="/etc/config/$NEWCFGNAME"

	local cfg_sec_name="$( uci -q get $ZAPRET_CFG_NAME.config )"
	[ -z "$cfg_sec_name" ] && create_default_cfg

	create_default_cfg "$NEWCFGNAME"
	[ ! -f "$NEWCFGFILE" ] && return 1 

	uci -m -f $cfgfile import "$NEWCFGNAME"
	uci commit "$NEWCFGNAME"
	uci -m -f "$NEWCFGFILE" import $cfgname
	uci commit $cfgname
	rm -f "$NEWCFGFILE"	
	return 0
}
