#!/bin/bash
#set -x
set -e

echo "This script will alter your system heavily, I recommend you start it inside a chroot!"
echo "To continue edit this script / remove the exit statement."
exit 0

# Prepare chroot to run this script in.
prepare_env() {
	sudo apt-get install -y \
		gcc \
		cpp \
		g++ \
		build-essential \
		ca-certificates \
		libfreetype6-dev \
		libpangocairo-1.0-0 \
		libfreetype6 \
		libjpeg62-turbo \
		libpcre3 \
		whiptail \
		gettext-base \
		devscripts \
		libsdl2-dev \
		libgit2-dev \
		libssh2-1-dev \
		libssl-dev \
		openssl
}

##
# Fixes wrong include locations
install_include_path_workarounds() {
	# hack/fix : https://github.com/OpenSmalltalk/opensmalltalk-vm/search?q=PangoCairo&unscoped_q=PangoCairo
	#
	# /usr/lib/glib-2.0/include does not exist on debian systems
	sudo mkdir -p /usr/lib/glib-2.0/
	sudo ln -s /usr/include/glib-2.0/ /usr/lib/glib-2.0/include || true

	# We are building on 64
	sudo mkdir -p /usr/lib/i386-linux-gnu/glib-2.0/
	sudo ln -s /usr/lib/x86_64-linux-gnu/glib-2.0/include /usr/lib/i386-linux-gnu/glib-2.0/ || true
}

##
# Fixes magic commit
clone_vm() {
	git clone --depth 50 -b  Cog https://github.com/OpenSmalltalk/opensmalltalk-vm.git
	# See build log on https://travis-ci.org/OpenSmalltalk/opensmalltalk-vm
	cd opensmalltalk-vm
	git checkout -qf 0e3761c888d2545c9846f360f99dcfa25317aff5
}

##
# Fixes configuration - done in travis script
plugin_configuration_hack() {
	# See build log on https://travis-ci.org/OpenSmalltalk/opensmalltalk-vm
	# https://github.com/OpenSmalltalk/opensmalltalk-vm/blob/Cog/scripts/ci/travis_build.sh
	# line 66
	cd "${BUILD_DIR}/opensmalltalk-vm/platforms/unix/config/"
	make configure
}

##
# Fixes library dependencies leading to segfaults if SqueakSSL, libgit2 and libssh2 dont
# use the same ssl version
# On Linux systems these dependencies can easily be installed using a package manager.
disable_3pardy_libs() {
	cd "${MVM_DIR}"
	sed -i 's/THIRDPARTYLIBS=.*/THIRDPARTYLIBS=""/g' mvm
}

##
# Pharos git implementation requires exactly this version of libgit2
build_libgit2() {
	sudo apt-get -y install cmake
	mkdir -p "${LIBGIT2_DIR}"
	cd "${LIBGIT2_DIR}"
	tar -xzf "${DATA_DIR}/3rdparty/libgit2-v0.25.1.tar.gz"
	cmake libgit2-0.25.1
	cmake --build .
	cp libgit2.so "${PHARO_LIB_DIR}/"
}

##
# Fixes broken UI if compiled with gcc6
patch_mvm_for_gcc6() {
	cd "${MVM_DIR}"
	sed -i 's/O2/O1/g' mvm
}

build_vm() {
	# Dont know if this has any influence/benefit. Copied from build log on https://travis-ci.org/OpenSmalltalk/opensmalltalk-vm
	export ARCH="linux64x64"
	export FLAVOR="pharo.cog.spur"
	export HEARTBEAT="threaded"
	export TRAVIS_COMPILER=gcc
	export CC=gcc
	export CC_FOR_BUILD=gcc

	##
	# Some magic to have a valid version string inside the vm

	# opensmalltalk-vm/scripts/ci/travis_build.sh : 36
	cd "${BUILD_DIR}"
	cd opensmalltalk-vm/
	echo "$(cat platforms/Cross/vm/sqSCCSVersion.h | .git_filters/RevDateURL.smudge)" > platforms/Cross/vm/sqSCCSVersion.h
	echo "$(cat platforms/Cross/plugins/sqPluginsSCCSVersion.h | .git_filters/RevDateURL.smudge)" > platforms/Cross/plugins/sqPluginsSCCSVersion.h

	# opensmalltalk-vm/scripts/ci/travis_build.sh : 45
	export COGVREV="$(git describe --tags --always)"
	export COGVDATE="$(git show -s --format=%cd HEAD)"
	export COGVURL="$(git config --get remote.origin.url)"
	export COGVOPTS="-DCOGVREV=\"${COGVREV}\" -DCOGVDATE=\"${COGVDATE// /_}\" -DCOGVURL=\"${COGVURL//\//\\\/}\""

	# Build
	cd "${MVM_DIR}"
	./mvm
}


# Directories
CUR_DIR="$(pwd)"
BUILD_DIR="${CURDIR}/build-pharo-cog-spur"

# Download libgit2-v0.25.1.tar.gz to this directory
DATA_DIR="${CURDIR}/data/pharo-cog-spur"
MVM_DIR="${BUILD_DIR}/opensmalltalk-vm/build.linux64x64/pharo.cog.spur/build"
LIBGIT2_DIR="${BUILD_DIR}/libgit2"

# Start building
prepare_env
install_include_path_workarounds
clone_vm
build_libgit2
plugin_configuration_hack
disable_3pardy_libs
patch_mvm_for_gcc6
build_vm


# Create a tarball of the build
cd "${BUILD_DIR}/opensmalltalk-vm/products"
tar -czf pharo.tar.gz *
