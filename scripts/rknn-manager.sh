#!/usr/bin/env bash

set -Eeuo pipefail

readonly RKNN_VERSION="2.3.2"
readonly RKNN_TAG="v${RKNN_VERSION}"
readonly RAW_ROOT="https://raw.githubusercontent.com/airockchip/rknn-toolkit2/${RKNN_TAG}"

readonly MANAGED_ROOT="/opt/panther-rknn"
readonly MANAGED_MARKER=".managed-by-panther-rknn-manager"

readonly RUNTIME_DIR="${MANAGED_ROOT}/runtime-${RKNN_VERSION}"
readonly RUNTIME_FILE="${RUNTIME_DIR}/librknnrt.so"
readonly RUNTIME_LINK="/usr/local/lib/librknnrt.so"
readonly RUNTIME_SHA256="d31fc19c85b85f6091b2bd0f6af9d962d5264a4e410bfb536402ec92bac738e8"
readonly RUNTIME_URL="${RAW_ROOT}/rknpu2/runtime/Linux/librknn_api/aarch64/librknnrt.so"

readonly PYTHON_ABI="cp312"
readonly PYTHON_PLATFORM="manylinux_2_17_aarch64.manylinux2014_aarch64"

readonly LITE_DIR="${MANAGED_ROOT}/toolkit-lite2-${RKNN_VERSION}-py312"
readonly LITE_LINK="/usr/local/bin/rknn-lite2-python"
readonly LITE_WHEEL="rknn_toolkit_lite2-${RKNN_VERSION}-${PYTHON_ABI}-${PYTHON_ABI}-${PYTHON_PLATFORM}.whl"
readonly LITE_URL="${RAW_ROOT}/rknn-toolkit-lite2/packages/${LITE_WHEEL}"
readonly LITE_SHA256="e1e4ec691fed900c0e6fde5e7d8eeba17f806aa45092b63b361ee775e2c1b50e"

readonly TOOLKIT_DIR="${MANAGED_ROOT}/toolkit2-${RKNN_VERSION}-py312"
readonly TOOLKIT_LINK="/usr/local/bin/rknn-toolkit2-python"
readonly TOOLKIT_WHEEL="rknn_toolkit2-${RKNN_VERSION}-${PYTHON_ABI}-${PYTHON_ABI}-${PYTHON_PLATFORM}.whl"
readonly TOOLKIT_URL="${RAW_ROOT}/rknn-toolkit2/packages/arm64/${TOOLKIT_WHEEL}"
readonly TOOLKIT_SHA256="6fe85905d5d339b6c6fea224599df001089438443be43f56a3cc32b77ab14b1c"

SCRIPT_DIRECTORY="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly SCRIPT_DIRECTORY
SCRIPT_PATH="${SCRIPT_DIRECTORY}/$(basename -- "${BASH_SOURCE[0]}")"
readonly SCRIPT_PATH
ASSUME_YES=0

info() {
	printf '[信息] %s\n' "$*"
}

success() {
	printf '[完成] %s\n' "$*"
}

warning() {
	printf '[注意] %s\n' "$*" >&2
}

die() {
	printf '[错误] %s\n' "$*" >&2
	exit 1
}

usage() {
	cat <<'EOF'
Panther X2 RKNN 组件管理器

用法：
  rknn-manager.sh                         打开交互菜单
  rknn-manager.sh status                  检测当前状态
  rknn-manager.sh install runtime         安装最小 C/C++ Runtime
  rknn-manager.sh install lite            安装 Runtime + Python Lite2
  rknn-manager.sh install toolkit         安装完整 RKNN-Toolkit2
  rknn-manager.sh install all             安装全部三个组件
  rknn-manager.sh remove runtime          删除脚本管理的 Runtime
  rknn-manager.sh remove lite             删除脚本管理的 Lite2
  rknn-manager.sh remove toolkit          删除脚本管理的 Toolkit2
  rknn-manager.sh remove all              删除脚本管理的全部组件

选项：
  -y, --yes                               不再询问确认
  -h, --help                              显示帮助

说明：
  Runtime      板端 C/C++ 推理，只负责运行已经转换好的 .rknn 模型。
  Lite2        板端 Python 推理接口，依赖 Runtime，不负责完整模型转换。
  Toolkit2     模型转换、量化、优化和导出工具，依赖多、占用空间最大。

安全策略：脚本只自动删除 /opt/panther-rknn 下由它创建的安装。检测到的
系统包、其他虚拟环境或用户手工安装只会报告，不会擅自删除。
EOF
}

confirm() {
	local prompt="$1"
	local answer

	if (( ASSUME_YES )); then
		return 0
	fi

	read -r -p "${prompt} [y/N] " answer
	[[ "${answer}" == "y" || "${answer}" == "Y" ]]
}

require_root() {
	if (( EUID == 0 )); then
		return 0
	fi
	command -v sudo >/dev/null 2>&1 || die "安装和删除需要 root 权限，但系统没有 sudo。"

	local sudo_args=()
	(( ASSUME_YES )) && sudo_args+=(--yes)
	exec sudo -- "${SCRIPT_PATH}" "${sudo_args[@]}" "$@"
}

run_menu_action() {
	local action="$1"
	local component="$2"
	local sudo_args=()

	(( ASSUME_YES )) && sudo_args+=(--yes)
	if (( EUID == 0 )); then
		"${SCRIPT_PATH}" "${sudo_args[@]}" "${action}" "${component}"
	else
		command -v sudo >/dev/null 2>&1 || die "安装和删除需要 root 权限，但系统没有 sudo。"
		sudo -- "${SCRIPT_PATH}" "${sudo_args[@]}" "${action}" "${component}"
	fi
}

require_arm64() {
	local machine

	machine="$(uname -m)"
	[[ "${machine}" == "aarch64" ]] || die "此安装器仅支持 ARM64/aarch64，当前架构：${machine}。"
}

require_python312() {
	local python_version

	command -v python3 >/dev/null 2>&1 || die "未找到 python3。Ubuntu 24.04 请先安装 python3。"
	python_version="$(python3 -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")')"
	[[ "${python_version}" == "3.12" ]] || die "固定包需要 Python 3.12，当前版本：${python_version}。"
}

install_download_tools() {
	local missing=0

	command -v curl >/dev/null 2>&1 || missing=1
	command -v file >/dev/null 2>&1 || missing=1
	command -v sha256sum >/dev/null 2>&1 || missing=1
	(( missing == 0 )) && return 0

	info "安装下载和校验工具……"
	apt-get update
	apt-get install --yes ca-certificates coreutils curl file
}

install_python_tools() {
	require_arm64
	info "确认 Python 虚拟环境组件……"
	apt-get update
	apt-get install --yes ca-certificates curl libgl1 libgomp1 python3 python3-venv
	require_python312
}

download_and_verify() {
	local url="$1"
	local destination="$2"
	local expected_sha256="$3"

	curl -fL --retry 3 --connect-timeout 20 "${url}" -o "${destination}"
	printf '%s  %s\n' "${expected_sha256}" "${destination}" | sha256sum --check --status || {
		printf '[错误] SHA-256 校验失败：%s\n' "${destination}" >&2
		return 1
	}
}

managed_dir_valid() {
	local directory="$1"
	[[ -f "${directory}/${MANAGED_MARKER}" ]]
}

runtime_candidates() {
	local path
	local -a candidates=(
		"${RUNTIME_LINK}"
		"/usr/lib/aarch64-linux-gnu/librknnrt.so"
		"/usr/lib/librknnrt.so"
		"/lib/aarch64-linux-gnu/librknnrt.so"
	)

	if command -v ldconfig >/dev/null 2>&1; then
		while IFS= read -r path; do
			[[ -n "${path}" ]] && candidates+=("${path}")
		done < <(ldconfig -p 2>/dev/null | awk '$1 ~ /^librknnrt\.so/ {print $NF}')
	fi

	printf '%s\n' "${candidates[@]}" | awk 'NF && !seen[$0]++' | while IFS= read -r path; do
		[[ -e "${path}" ]] && printf '%s\n' "${path}"
	done
}

runtime_status() {
	local found=0
	local path
	local actual_sha

	while IFS= read -r path; do
		[[ -n "${path}" ]] || continue
		found=1
		if command -v sha256sum >/dev/null 2>&1; then
			actual_sha="$(sha256sum "${path}" 2>/dev/null | awk '{print $1}')"
		else
			actual_sha=""
		fi
		if [[ "${actual_sha}" == "${RUNTIME_SHA256}" ]]; then
			printf '已安装 v%s：%s' "${RKNN_VERSION}" "${path}"
		else
			printf '已安装，版本未知：%s' "${path}"
		fi
		if [[ "$(readlink -f "${path}" 2>/dev/null || true)" == "${RUNTIME_FILE}" ]]; then
			printf '（本脚本管理）'
		else
			printf '（外部安装）'
		fi
		printf '\n'
	done < <(runtime_candidates)

	(( found )) || printf '未安装\n'
}

python_distribution_version() {
	local interpreter="$1"
	local distribution="$2"

	[[ -x "${interpreter}" ]] || return 1
	"${interpreter}" -c \
		'import importlib.metadata as m, sys; print(m.version(sys.argv[1]))' \
		"${distribution}" 2>/dev/null
}

python_component_status() {
	local label="$1"
	local directory="$2"
	local distribution="$3"
	local version
	local external_version

	if managed_dir_valid "${directory}" && version="$(python_distribution_version "${directory}/bin/python" "${distribution}")"; then
		printf '已安装 v%s：%s（本脚本管理）\n' "${version}" "${directory}"
	else
		printf '未发现脚本管理的 %s' "${label}"
		if command -v python3 >/dev/null 2>&1 && external_version="$(python_distribution_version "$(command -v python3)" "${distribution}")"; then
			printf '；默认 python3 中发现 v%s（外部安装）' "${external_version}"
		fi
		printf '\n'
	fi
}

kernel_driver_status() {
	local config

	config="/boot/config-$(uname -r)"

	if [[ -r "${config}" ]] && grep -q '^CONFIG_ROCKCHIP_RKNPU=y$' "${config}"; then
		printf '已启用：CONFIG_ROCKCHIP_RKNPU=y\n'
	elif [[ -d /sys/module/rknpu ]]; then
		printf '已加载：/sys/module/rknpu\n'
	else
		printf '未确认；请检查内核配置和 dmesg\n'
	fi
}

show_status() {
	printf '\n=== Panther X2 RKNN 状态 ===\n'
	printf '系统：%s / %s / Python %s\n' \
		"$(uname -s)" \
		"$(uname -m)" \
		"$(python3 -c 'import platform; print(platform.python_version())' 2>/dev/null || printf '未安装')"
	printf 'RKNPU 内核驱动：'
	kernel_driver_status

	printf '\n[1] RKNN Runtime\n'
	printf '    板端 C/C++ 推理，只运行已经转换好的 .rknn 模型。\n'
	printf '    状态：'
	runtime_status

	printf '\n[2] RKNN-Toolkit-Lite2\n'
	printf '    板端 Python 推理接口，依赖 Runtime，不负责完整模型转换。\n'
	printf '    状态：'
	python_component_status "Lite2" "${LITE_DIR}" "rknn-toolkit-lite2"

	printf '\n[3] 完整 RKNN-Toolkit2\n'
	printf '    转换、量化、优化和导出模型；依赖多、占用空间最大。\n'
	printf '    状态：'
	python_component_status "Toolkit2" "${TOOLKIT_DIR}" "rknn-toolkit2"
	printf '\n'
}

install_runtime() {
	local temp_dir
	local downloaded
	local existing_runtime

	require_arm64
	install_download_tools
	existing_runtime="$(runtime_candidates | head -n 1)"
	if [[ -n "${existing_runtime}" ]] && \
		[[ "$(readlink -f "${existing_runtime}" 2>/dev/null || true)" != "${RUNTIME_FILE}" ]]; then
		die "系统已经存在外部 RKNN Runtime：${existing_runtime}。为避免多个版本冲突，脚本不会并行安装。"
	fi

	if [[ -e "${RUNTIME_LINK}" || -L "${RUNTIME_LINK}" ]]; then
		if [[ "$(readlink -f "${RUNTIME_LINK}" 2>/dev/null || true)" != "${RUNTIME_FILE}" ]]; then
			die "${RUNTIME_LINK} 已由其他安装占用。为避免覆盖，脚本已停止。"
		fi
	fi

	if [[ -d "${RUNTIME_DIR}" ]] && ! managed_dir_valid "${RUNTIME_DIR}"; then
		die "${RUNTIME_DIR} 已存在但不是本脚本创建，拒绝覆盖。"
	fi

	if managed_dir_valid "${RUNTIME_DIR}" && [[ -f "${RUNTIME_FILE}" ]]; then
		if [[ "$(sha256sum "${RUNTIME_FILE}" | awk '{print $1}')" == "${RUNTIME_SHA256}" ]]; then
			ln -sfn "${RUNTIME_FILE}" "${RUNTIME_LINK}"
			ldconfig
			success "RKNN Runtime v${RKNN_VERSION} 已安装，无需重复下载。"
			return 0
		fi
		warning "检测到脚本管理的 Runtime 文件损坏，将重新安装。"
	fi

	temp_dir="$(mktemp -d)"
	downloaded="${temp_dir}/librknnrt.so"
	info "下载 RKNN Runtime v${RKNN_VERSION}……"
	download_and_verify "${RUNTIME_URL}" "${downloaded}" "${RUNTIME_SHA256}"
	file "${downloaded}" | grep -q 'ELF 64-bit.*ARM aarch64' || die "下载文件不是 ARM64 ELF 运行库。"

	install -d "${RUNTIME_DIR}" "$(dirname -- "${RUNTIME_LINK}")"
	printf 'RKNN Runtime %s\n' "${RKNN_VERSION}" > "${RUNTIME_DIR}/${MANAGED_MARKER}"
	install -m 0644 "${downloaded}" "${RUNTIME_FILE}"
	ln -sfn "${RUNTIME_FILE}" "${RUNTIME_LINK}"
	ldconfig
	rm -rf -- "${temp_dir}"

	success "RKNN Runtime v${RKNN_VERSION} 已安装到 ${RUNTIME_FILE}。"
}

prepare_venv_target() {
	local label="$1"
	local directory="$2"

	if [[ -d "${directory}" ]]; then
		if ! managed_dir_valid "${directory}"; then
			die "${directory} 已存在但不是本脚本创建，拒绝删除或覆盖。"
		fi
		if ! confirm "重新安装脚本管理的 ${label}？"; then
			info "已取消。"
			return 1
		fi
		rm -rf -- "${directory}"
	fi

	install -d "${MANAGED_ROOT}" "${directory}"
	printf '%s %s\n' "${label}" "${RKNN_VERSION}" > "${directory}/${MANAGED_MARKER}"
	python3 -m venv "${directory}"
	"${directory}/bin/python" -m pip install --upgrade pip setuptools wheel
}

create_python_link() {
	local link="$1"
	local target="$2"

	if [[ -e "${link}" || -L "${link}" ]]; then
		if [[ "$(readlink -f "${link}" 2>/dev/null || true)" != "${target}" ]]; then
			warning "${link} 已被其他程序占用，保留原文件；请直接使用 ${target}。"
			return 0
		fi
	fi
	install -d "$(dirname -- "${link}")"
	ln -sfn "${target}" "${link}"
}

install_lite() {
	local temp_dir
	local downloaded

	if [[ -z "$(runtime_candidates)" ]]; then
		install_runtime
	else
		info "已检测到 RKNN Runtime，Lite2 将复用现有运行库。"
	fi
	install_python_tools
	if ! prepare_venv_target "RKNN-Toolkit-Lite2" "${LITE_DIR}"; then
		return 0
	fi

	temp_dir="$(mktemp -d)"
	downloaded="${temp_dir}/${LITE_WHEEL}"
	info "下载并安装 RKNN-Toolkit-Lite2 v${RKNN_VERSION}……"
	download_and_verify "${LITE_URL}" "${downloaded}" "${LITE_SHA256}"
	"${LITE_DIR}/bin/python" -m pip install "${downloaded}"
	"${LITE_DIR}/bin/python" -c \
		'from rknnlite.api import RKNNLite; import importlib.metadata as m; print("Lite2", m.version("rknn-toolkit-lite2"), "导入成功")'
	create_python_link "${LITE_LINK}" "${LITE_DIR}/bin/python"
	rm -rf -- "${temp_dir}"

	success "Lite2 已安装。运行 Python：${LITE_LINK}"
}

install_toolkit() {
	local temp_dir
	local downloaded
	local available_kib

	install_python_tools
	available_kib="$(df -Pk /opt | awk 'NR == 2 {print $4}')"
	if [[ "${available_kib}" =~ ^[0-9]+$ ]] && (( available_kib < 3145728 )); then
		warning "完整 Toolkit2 的 Python、PyTorch、ONNX 和 OpenCV 依赖较大；/opt 当前可用空间少于 3 GiB。"
		if ! confirm "仍然继续安装完整 Toolkit2？"; then
			info "已取消。"
			return 0
		fi
	fi
	if ! prepare_venv_target "RKNN-Toolkit2" "${TOOLKIT_DIR}"; then
		return 0
	fi

	warning "完整 Toolkit2 会下载 ONNX、OpenCV、PyTorch 等依赖，安装时间和空间占用明显大于 Runtime。"
	temp_dir="$(mktemp -d)"
	downloaded="${temp_dir}/${TOOLKIT_WHEEL}"
	info "下载并安装完整 RKNN-Toolkit2 v${RKNN_VERSION}……"
	download_and_verify "${TOOLKIT_URL}" "${downloaded}" "${TOOLKIT_SHA256}"
	"${TOOLKIT_DIR}/bin/python" -m pip install "${downloaded}"
	"${TOOLKIT_DIR}/bin/python" -c \
		'from rknn.api import RKNN; import importlib.metadata as m; print("Toolkit2", m.version("rknn-toolkit2"), "导入成功")'
	create_python_link "${TOOLKIT_LINK}" "${TOOLKIT_DIR}/bin/python"
	rm -rf -- "${temp_dir}"

	success "完整 Toolkit2 已安装。运行 Python：${TOOLKIT_LINK}"
}

remove_managed_python() {
	local label="$1"
	local directory="$2"
	local link="$3"

	if ! managed_dir_valid "${directory}"; then
		warning "没有发现脚本管理的 ${label}，未删除外部安装。"
		return 0
	fi
	confirm "确定删除 ${label} 及其独立虚拟环境 ${directory}？" || {
		info "已取消。"
		return 0
	}

	if [[ -L "${link}" ]] && [[ "$(readlink -f "${link}" 2>/dev/null || true)" == "${directory}/bin/python" ]]; then
		rm -f -- "${link}"
	fi
	rm -rf -- "${directory}"
	success "已删除 ${label}。"
}

remove_runtime() {
	if ! managed_dir_valid "${RUNTIME_DIR}"; then
		warning "没有发现脚本管理的 RKNN Runtime，未删除外部安装。"
		return 0
	fi

	if managed_dir_valid "${LITE_DIR}"; then
		warning "Lite2 仍然存在，删除 Runtime 后 Lite2 将不能执行 NPU 推理。"
	fi
	confirm "确定删除脚本管理的 RKNN Runtime？" || {
		info "已取消。"
		return 0
	}

	if [[ -L "${RUNTIME_LINK}" ]] && [[ "$(readlink -f "${RUNTIME_LINK}" 2>/dev/null || true)" == "${RUNTIME_FILE}" ]]; then
		rm -f -- "${RUNTIME_LINK}"
	fi
	rm -rf -- "${RUNTIME_DIR}"
	ldconfig
	success "已删除脚本管理的 RKNN Runtime。"
}

install_component() {
	case "$1" in
		runtime)
			install_runtime
			;;
		lite)
			install_lite
			;;
		toolkit)
			install_toolkit
			;;
		all)
			install_runtime
			install_lite
			install_toolkit
			;;
		*)
			die "未知组件：$1。可选 runtime、lite、toolkit、all。"
			;;
	esac
}

remove_component() {
	case "$1" in
		runtime)
			remove_runtime
			;;
		lite)
			remove_managed_python "RKNN-Toolkit-Lite2" "${LITE_DIR}" "${LITE_LINK}"
			;;
		toolkit)
			remove_managed_python "RKNN-Toolkit2" "${TOOLKIT_DIR}" "${TOOLKIT_LINK}"
			;;
		all)
			remove_managed_python "RKNN-Toolkit2" "${TOOLKIT_DIR}" "${TOOLKIT_LINK}"
			remove_managed_python "RKNN-Toolkit-Lite2" "${LITE_DIR}" "${LITE_LINK}"
			remove_runtime
			;;
		*)
			die "未知组件：$1。可选 runtime、lite、toolkit、all。"
			;;
	esac
}

interactive_menu() {
	local choice

	while true; do
		show_status
		cat <<'EOF'
请选择操作：
  1) 安装最小 RKNN Runtime
  2) 安装 Runtime + RKNN-Toolkit-Lite2（板端 Python）
  3) 安装完整 RKNN-Toolkit2（模型转换/量化）
  4) 安装全部三个组件
  5) 删除脚本管理的 Runtime
  6) 删除脚本管理的 Lite2
  7) 删除脚本管理的 Toolkit2
  8) 删除脚本管理的全部组件
  9) 刷新状态
  0) 退出
EOF
		read -r -p '输入编号：' choice
		case "${choice}" in
			1) run_menu_action install runtime ;;
			2) run_menu_action install lite ;;
			3) run_menu_action install toolkit ;;
			4) run_menu_action install all ;;
			5) run_menu_action remove runtime ;;
			6) run_menu_action remove lite ;;
			7) run_menu_action remove toolkit ;;
			8) run_menu_action remove all ;;
			9) ;;
			0) return 0 ;;
			*) warning "无效选择：${choice}" ;;
		esac
	done
}

main() {
	local command_name
	local component

	while [[ "${1:-}" == "-y" || "${1:-}" == "--yes" ]]; do
		ASSUME_YES=1
		shift
	done

	case "${1:-}" in
		-h|--help)
			usage
			return 0
			;;
	esac

	command_name="${1:-menu}"
	component="${2:-}"
	case "${command_name}" in
		menu)
			interactive_menu
			;;
		status)
			show_status
			;;
		install)
			[[ -n "${component}" ]] || die "install 后必须指定组件。"
			require_root install "${component}"
			install_component "${component}"
			show_status
			;;
		remove)
			[[ -n "${component}" ]] || die "remove 后必须指定组件。"
			require_root remove "${component}"
			remove_component "${component}"
			show_status
			;;
		*)
			usage >&2
			die "未知命令：${command_name}"
			;;
	esac
}

main "$@"
