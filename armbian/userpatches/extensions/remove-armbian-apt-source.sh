#!/usr/bin/env bash

# Remove both the legacy one-line format and the current Deb822 format.
function remove_invalid_armbian_apt_sources() {
	local sources_dir="${SDCARD}/etc/apt/sources.list.d"
	local source
	local -a invalid_sources=(
		"${sources_dir}/armbian.list"
		"${sources_dir}/armbian.sources"
	)

	for source in "${invalid_sources[@]}"; do
		if [[ -e "${source}" || -L "${source}" ]]; then
			display_alert "Removing invalid Armbian APT source" "${source#${SDCARD}}" "info"
			rm -f -- "${source}"
		fi

		if [[ -e "${source}" || -L "${source}" ]]; then
			exit_with_error "Failed to remove invalid Armbian APT source" "${source}"
		fi
	done
}

# image-late runs after Armbian creates its source, but before post_repo_apt_update.
function custom_apt_repo__remove_invalid_armbian_sources() {
	[[ "${CUSTOM_REPO_WHEN:-}" == "image-late" ]] || return 0
	remove_invalid_armbian_apt_sources
}

# Defense in depth: make sure no later build step restored either source file.
function post_repo_customize_image__remove_invalid_armbian_sources() {
	remove_invalid_armbian_apt_sources
}
