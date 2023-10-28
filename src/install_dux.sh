#!/bin/bash
set +H
# "|| return" is used as an error handler.
# NOTE: set -e has to be present in the scripts executed here for this to work.
set -eo pipefail

# Prevent installation issues arising from an inaccurate system time.
timedatectl set-ntp true
wait
systemctl restart systemd-timesyncd.service
wait

SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SRC_DIR}/GLOBAL_IMPORTS.sh"
source "${SRC_DIR}/Configs/settings.sh"

if ! grep -q "'archiso'" /etc/mkinitcpio.d/linux.preset; then
	echo -e "\nERROR: Do not run this script outside of the Arch Linux ISO!\n"
	exit 1
fi

if cryptsetup status "root" | grep -q "inactive"; then
	echo -e "\nERROR: Forgot to mount the LUKS2 partition under the name 'root'?\n"
	exit 1
fi

mkdir -p "${SRC_DIR}/logs"
# Makes scripts below executable.
chmod +x -R "${SRC_DIR}"

clear


SetPasswordPrompt() {
	read -rp "Enter a new password for the username \"${YOUR_USER}\": " DESIREDPW
	if [[ -z ${DESIREDPW} ]]; then
		echo -e "\nNo password was entered, please try again.\n"
		SetPasswordPrompt
	fi

	read -rp $'\nPlease repeat your password: ' PWCODE
	if [[ ${DESIREDPW} == "${PWCODE}" ]]; then
		export PWCODE
	else
		echo -e "\nPasswords do not match, please try again.\n"
		SetPasswordPrompt
	fi
}
SetPasswordPrompt

_01() {
	("${SRC_DIR}/src/01-pre_chroot.sh") |& tee "${SRC_DIR}/logs/01-pre_chroot.log" || return
}
_01

# /mnt needs access to Dux's contents.
[[ -d "/mnt/root/dux" ]] &&
	rm -rf "/mnt/root/dux"
\cp -f -R "${SRC_DIR}" "/mnt/root"

_02() {
	(arch-chroot /mnt "${SRC_DIR}/src/02-post_chroot_root.sh") |& tee "${SRC_DIR}/logs/02-post_chroot_root.log" || return
}
_02

_03() {
	(arch-chroot /mnt sudo -u "${YOUR_USER}" bash "/home/${YOUR_USER}/dux/src/03-post_chroot_user.sh") |& tee "${SRC_DIR}/logs/03-post_chroot_user.log" || return
}
_03

_gpu() {
    (arch-chroot /mnt "${SRC_DIR}/src/GPU.sh") |& tee "${SRC_DIR}/logs/GPU.log" || return
}
[[ ${disable_gpu} -ne 1 ]] && _gpu

SetupAudio() {
	(arch-chroot /mnt "${SRC_DIR}/src/Pipewire.sh") |& tee "${SRC_DIR}/logs/Pipewire.log" || return
}
SetupAudio

SetupDesktopEnvironment() {
	(arch-chroot /mnt "${SRC_DIR}/src/KDE.sh") |& tee "${SRC_DIR}/logs/KDE.log" || return
}
SetupDesktopEnvironment

_04() {
	(arch-chroot /mnt "${SRC_DIR}/src/04-finalize.sh") |& tee "${SRC_DIR}/logs/04-finalize.log" || return
}
_04

rm -rf "/mnt/root/dux/logs"
rm -rf "/mnt/home/${YOUR_USER:?}/dux/logs"

\cp -f -R "${SRC_DIR}/logs" "/mnt/root/dux"
\cp -f -R "${SRC_DIR}/logs" "/mnt/home/${YOUR_USER}/dux"

SetCorrectPermissions() {
	(arch-chroot /mnt "chown" -R "${YOUR_USER}:${YOUR_USER}" /home/"${YOUR_USER}"/{dux,dux_backups})
}
SetCorrectPermissions

reboot -f