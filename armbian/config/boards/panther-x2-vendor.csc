# Rockchip RK3566 quad core 4GB RAM SoC WIFI/BT eMMC USB2
BOARD_NAME="Panther X2 BSP 6.1"
BOARD_VENDOR="panther"
BOARDFAMILY="rk35xx"
BOARD_MAINTAINER=""
INTRODUCED="2023"
BOOTCONFIG="rock-3c-rk3566_defconfig"
KERNEL_TARGET="vendor"
KERNEL_TEST_TARGET="vendor"
FULL_DESKTOP="yes"
BOOT_LOGO="desktop"
BOOT_FDT_FILE="rockchip/rk3566-panther-x2.dtb"
IMAGE_PARTITION_TABLE="gpt"
BOOT_SCENARIO="spl-blobs"
BOOTFS_TYPE="fat"

function post_family_config__use_radxa_rock3_uboot() {
	display_alert "Overriding U-Boot source" "Using Radxa stable-4.19-rock3" "info"

	KERNELBRANCH="commit:5280f9b4336199c4025c8eed894d2b4e2268dcc6"
	BOOTSOURCE="https://github.com/radxa/u-boot.git"
	BOOTBRANCH="commit:c55987146f4f9b20f7cb2f917ca88300419afe8d"
	BOOTPATCHDIR="u-boot-panther-x2-radxa"
	BOOTPATCHES="none"
	SKIP_BOOTSPLASH_PATCHES="yes"
}
