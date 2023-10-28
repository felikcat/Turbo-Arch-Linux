#!/bin/bash
set +H
set -e

SRC_DIR="$(realpath .)"
source "${SRC_DIR}/GLOBAL_IMPORTS.sh"
source "${SRC_DIR}/Configs/settings.sh"

PKGS+=(lib32-mesa lib32-ocl-icd lib32-vulkan-icd-loader mesa ocl-icd vulkan-icd-loader)

NvidiaGPUSetup() {
	(bash "${SRC_DIR}/_NVIDIA.sh") |& tee "${SRC_DIR}/logs/_NVIDIA.log" || return
}

IntelGPUSetup() {
	PKGS+=(vulkan-intel)

	[[ ${intel_video_accel} -eq 1 ]] &&
		PKGS+=(libva-intel-driver lib32-libva-intel-driver)
	[[ ${intel_video_accel} -eq 2 ]] &&
		PKGS+=(intel-media-driver intel-media-sdk)

	# Early load KMS driver
	if ! grep -q "i915" /etc/mkinitcpio.conf; then
		echo -e "\nMODULES+=(i915)" >>/etc/mkinitcpio.conf
	fi

	REGENERATE_INITRAMFS=1
}

# grep: -P/--perl-regexp benched faster than -E/--extended-regexp
# shellcheck disable=SC2249
case $(lspci | grep -P "VGA|3D|Display" | grep -Po "NVIDIA|Intel|VMware SVGA|Red Hat") in
*"NVIDIA"*)
	NvidiaGPUSetup
	;;&
*"Intel"*)
	IntelGPUSetup
	;;&
*"VMware"*)
	PKGS+=(xf86-video-vmware)
	;;&
*"Red Hat"*)
	PKGS+=(xf86-video-qxl spice-vdagent qemu-guest-agent)
	;;
esac

_pkgs_add
_pkgs_aur_add
_flatpaks_add

if [[ ${IS_CHROOT} -eq 0 ]] && [[ ${REGENERATE_INITRAMFS} -eq 1 ]]; then
    mkinitcpio -P
fi

cleanup() {
	mkdir "${mkdir_flags}" "${BACKUPS}/etc/modprobe.d"
	chown -R "${WHICH_USER}:${WHICH_USER}" "${BACKUPS}/etc/modprobe.d"
}
trap cleanup EXIT
