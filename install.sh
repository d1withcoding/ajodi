#!/bin/sh
#
# Ajodi bootstrap.
#
# Thin entrypoint for `curl -fsSL .../install.sh | bash`. It does the bare
# minimum to get the real installer running on a fresh machine: detect the
# distro family (so it knows the package manager), make sure git and python3
# are present, fetch the rice, then hand the whole flow to the Python installer.
# The wizard, the package logic and the config deploy all live in
# installer/ajodi_install.py, not here.

set -e

REPO_URL="https://github.com/d1withcoding/ajodi.git"
DIR="${XDG_DATA_HOME:-$HOME/.local/share}/ajodi"

# os-release ID / ID_LIKE tokens per family, mirroring installer/distro.py so the
# bootstrap picks the same package manager the Python installer expects.
ARCH_IDS="arch cachyos endeavouros manjaro garuda artix arcolinux archcraft rebornos athena blackarch archbang crystal snigdha parabola obarun arch32 hyperbola steamos omarchy xerolinux archman biglinux ctlos tromjaro bluestar arkane blendos acreetionos mabox"
DEBIAN_IDS="debian ubuntu linuxmint pop elementary zorin raspbian"
FEDORA_IDS="fedora nobara rhel centos rocky almalinux"
SUSE_IDS="suse opensuse sles sled tumbleweed leap"
GENTOO_IDS="gentoo funtoo calculate pentoo redcore"

say()  { printf '%s\n' "$*"; }
step() { printf '\n:: %s\n' "$*"; }
die()  { printf 'ajodi: %s\n' "$*" >&2; exit 1; }
have() { command -v "$1" >/dev/null 2>&1; }

in_list() {
	case " $2 " in
	*" $1 "*) return 0 ;;
	esac
	return 1
}

detect_family() {
	[ -r /etc/os-release ] || { echo unknown; return 0; }
	# shellcheck disable=SC1091
	. /etc/os-release 2>/dev/null || true
	for tok in $(printf '%s %s' "${ID:-}" "${ID_LIKE:-}" | tr '[:upper:]' '[:lower:]'); do
		in_list "$tok" "$ARCH_IDS" && { echo arch; return 0; }
		in_list "$tok" "$DEBIAN_IDS" && { echo debian; return 0; }
		in_list "$tok" "$FEDORA_IDS" && { echo fedora; return 0; }
		in_list "$tok" "$SUSE_IDS" && { echo suse; return 0; }
		in_list "$tok" "$GENTOO_IDS" && { echo gentoo; return 0; }
	done
	echo unknown
}

run_root() {
	if [ "$(id -u)" -eq 0 ]; then
		"$@"
		return
	fi
	for su in sudo doas; do
		have "$su" || continue
		if [ -e /dev/tty ]; then "$su" "$@" </dev/tty; else "$su" "$@"; fi
		return
	done
	die "need root to install packages; run as root or install sudo or doas first"
}

ensure_deps() {
	have git && have python3 && return 0
	step "Installing git and python3"
	case "$1" in
	arch) run_root pacman -Syu --needed --noconfirm git python ;;
	debian) run_root apt-get update || true; run_root apt-get install -y git python3 ;;
	fedora) run_root dnf makecache || true; run_root dnf install -y git python3 ;;
	suse) run_root zypper --non-interactive refresh || true; run_root zypper --non-interactive install git python3 ;;
	gentoo) run_root emerge --noreplace dev-vcs/git ;;
	*) die "no supported package manager (arch/debian/fedora/suse/gentoo); install git and python3 yourself, then re-run" ;;
	esac
	if ! have git || ! have python3; then
		die "git and python3 are still missing after the install step"
	fi
}

fetch() {
	mkdir -p "$(dirname "$DIR")"
	if [ -d "$DIR/.git" ]; then
		step "Updating Ajodi in $DIR"
		git -C "$DIR" pull --ff-only || say "  could not fast-forward, using the current checkout"
	else
		step "Cloning Ajodi into $DIR"
		git clone --depth 1 "$REPO_URL" "$DIR"
	fi
}

has_flag() {
	flag="$1"; shift
	case " $* " in
	*" $flag "*) return 0 ;;
	esac
	return 1
}

main() {
	say "Preparing installer interface..."
	[ "$(uname -s)" = Linux ] || die "Ajodi only installs on Linux"

	if [ -f "${XDG_CONFIG_HOME:-$HOME/.config}/niri/.ajodi-managed" ] \
		&& ! has_flag --reinstall "$@" && ! has_flag --uninstall "$@"; then
		say "Ajodi is already installed."
		say "  Update:       open Settings > Updates in the pill, or run: ajodi update"
		say "  Re-install:   curl -fsSL https://raw.githubusercontent.com/Gakuseei/Ajodi/main/install.sh | sh -s -- --reinstall"
		say "  Uninstall:    ajodi uninstall"
		exit 0
	fi

	fam="$(detect_family)"
	if [ "$fam" = unknown ]; then
		say "Note: this distro is not a supported family (arch/debian/fedora/suse/gentoo)."
		say "No packages will be installed; configs deploy at your own risk."
	fi

	ensure_deps "$fam"
	fetch

	exec python3 "$DIR/installer/ajodi_install.py" --source "$DIR/configs" "$@"
}

main "$@"
