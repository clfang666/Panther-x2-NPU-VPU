#!/usr/bin/env bash

# The pinned Armbian framework creates its repository configuration before
# invoking this hook. Remove the invalid legacy source from the finished rootfs.
function post_repo_customize_image__remove_invalid_armbian_list() {
	local armbian_list="${SDCARD}/etc/apt/sources.list.d/armbian.list"

	display_alert "Removing invalid Armbian APT source" "/etc/apt/sources.list.d/armbian.list" "info"
	rm -f -- "${armbian_list}"

	if [[ -e "${armbian_list}" || -L "${armbian_list}" ]]; then
		exit_with_error "Failed to remove invalid Armbian APT source" "${armbian_list}"
	fi
}
