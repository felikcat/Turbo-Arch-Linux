#!/bin/bash
# shellcheck disable=SC2034
set +H
set -e

[[ ${KEEP_GOING} -eq 1 ]] &&
	set +e

LOGIN_USER="$(stat -c %U "$(readlink /proc/self/fd/0)")"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# SCRIPT_DIR is used to make GIT_DIR reliable
cd "${SCRIPT_DIR}" && GIT_DIR=$(git rev-parse --show-toplevel)
source "${GIT_DIR}/configs/settings.sh"

# DEBUG=1 bash ~/dux/scripts/example.sh
if [[ ${DEBUG} -eq 1 ]]; then
	set -x
	cp_flags="-fv"
	mkdir_flags="-pv"
	mv_flags="-fv"
else
	cp_flags="-f"
	mkdir_flags="-p"
	mv_flags="-f"
fi

[[ -z ${DATE:-} ]] &&
	DATE=$(date +"%d-%m-%Y_%H-%M-%S") && export DATE

BOOT_CONF="/boot/refind_linux.conf" && export BOOT_CONF

[[ -z ${SYSTEMD_USER_ENV:-} ]] &&
	SYSTEMD_USER_ENV="DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus XDG_RUNTIME_DIR=/run/user/1000" &&
	export SYSTEMD_USER_ENV

if systemd-detect-virt --chroot >&/dev/null; then
	IS_CHROOT=1
fi

# INITIAL_USER = running from arch-chroot
# LOGIN_USER = not a chroot or permission denied (DENY_SUPERUSER=1)
if [[ ${IS_CHROOT} -eq 1 ]]; then
	WHICH_USER="${INITIAL_USER}" && export WHICH_USER
elif [[ ${IS_CHROOT} -eq 0 ]]; then
	WHICH_USER="${LOGIN_USER}" && export WHICH_USER
fi

BACKUPS="/home/${WHICH_USER}/dux_backups" && export BACKUPS

# NOTES:
# trap's EXIT signal is for the Bash instance as a whole, not per "source"d script
_flatpak_silent() {
	flatpak "$@" >&/dev/null
}
_flatpaks_add() {
	[[ -n ${FLATPAKS} ]] &&
		flatpak install --noninteractive flathub ${FLATPAKS}
}
_fix_services_syntax() {
	systemctl daemon-reload
	# "systemctl enable/disable" will fail if trailing whitespace is not removed
	SERVICES=$(echo ${SERVICES} | xargs) && export SERVICES
}
# Use this '_systemctl' function instead of the 'systemctl' command if reading from ${SERVICES}
_systemctl() {
	if [[ -n ${SERVICES} ]]; then
		_fix_services_syntax
		systemctl "$@"
	fi
}
_move2bkup() {
	local target
	for target in "$@"; do
		if [[ -f ${target} ]]; then
			local parent_dir
			parent_dir=$(dirname "${target}")
			mkdir "${mkdir_flags}" ${BACKUPS}${parent_dir}
			mv "${mv_flags}" "${target}" "${BACKUPS}${target}_${DATE}" || :

		elif [[ -d ${target} ]]; then
			mv "${mv_flags}" "${target}" "${BACKUPS}${target}_${DATE}" || :
		fi
	done
}
_pkgs_aur_add() {
	[[ -n ${PKGS_AUR} ]] &&
		# Use -Syu instead of -Syuu for paru.
		# NoProgressBar: the TTY framebuffer is likely not GPU accelerated while booted into the Arch Linux ISO; making rendering less text = Dux installs faster.
		sudo -H -u "${WHICH_USER}" bash -c "${SYSTEMD_USER_ENV} DENY_SUPERUSER=1 paru -Syu --aur --quiet --noprogressbar --noconfirm --useask --needed --skipreview ${PKGS_AUR}"
}

if [[ ${DENY_SUPERUSER:-} -eq 1 && $(id -u) -ne 1000 ]]; then
	echo -e "\e[1m\nNormal privileges required; don't use sudo or doas!\e[0m\nCurrently affected scripts: \"${BASH_SOURCE[*]}\"\n" >&2
	exit 1
fi

if [[ ${DENY_SUPERUSER:-} -ne 1 && $(id -u) -ne 0 ]]; then
	echo -e "\e[1m\nSuperuser required, prompting if needed...\e[0m\nCurrently affected scripts: \"${BASH_SOURCE[*]}\"\n" >&2
	if hash sudo >&/dev/null; then
		sudo bash "${0}"
		exit $?
	elif hash doas >&/dev/null; then
		doas bash "${0}"
		exit $?
	fi
fi

# Functions requiring superuser
if [[ ${DENY_SUPERUSER:-} -ne 1 && $(id -u) -eq 0 ]]; then
	_pkgs_add() {
		# If ${PKGS} is empty, don't bother doing anything.
		[[ -n ${PKGS} ]] &&
			# Word splitting is a non-issue for both Pacman and Paru, so using arrays[@] will reduce performance needlessly.
			pacman -Syu --quiet --noprogressbar --noconfirm --ask=4 --needed ${PKGS}
	}
	_modify_kernel_parameters() {
		if ! grep -q "${KERNEL_PARAMS}" "${BOOT_CONF}"; then
            sed -i -e "s/standard options\"[ ]*\"[^\"]*/& ${KERNEL_PARAMS}/" \
                -e "s/user mode\"[ ]*\"[^\"]*/& ${KERNEL_PARAMS}/" "${BOOT_CONF}"
		fi
	}
fi
