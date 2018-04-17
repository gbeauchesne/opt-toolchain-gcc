top_srcdir ?= .

srcdir = $(top_srcdir)/src
objdir = $(top_srcdir)/obj.$(target_triplet)
prefix = /opt/toolchain/gcc-$(v_gcc_branch)

# The build architecture (default: native ARCH)
BUILD_ARCH = $(shell uname -m)

# The build vendor (default: "pc" if `lsb_release' is not available)
BUILD_VENDOR = $(shell lsb_release -is 2>/dev/null | tr '[:upper:]' '[:lower:]')
ifeq ($(BUILD_VENDOR),)
BUILD_VENDOR = pc
endif

# The build operating system (default: native OS)
BUILD_OS = $(shell uname -s | tr '[:upper:]' '[:lower:]')

# The build configure triplet
# XXX: use ext/gcc/config.guess for defaults?
build_triplet = $(BUILD_ARCH)-$(BUILD_VENDOR)-$(BUILD_OS)

# The host triplet (default: build triplet)
HOST_ARCH = $(BUILD_ARCH)
HOST_VENDOR = $(BUILD_VENDOR)
HOST_OS = $(BUILD_OS)
host_triplet = $(HOST_ARCH)-$(HOST_VENDOR)-$(HOST_OS)

# The target triplet (default: build triplet)
TARGET_ARCH = $(BUILD_ARCH)
TARGET_VENDOR = $(BUILD_VENDOR)
TARGET_OS = $(BUILD_OS)
target_triplet = $(TARGET_ARCH)-$(TARGET_VENDOR)-$(TARGET_OS)

# The `git' program
GIT = git

# The `autoreconf' program
AUTORECONF = autoreconf

# Program for creating symbolic links
LN_S = ln -s

# Toplevel git submodules directory
git_submodulesdir = $(top_srcdir)/ext

# The list of git submodules to use, with GCC first -- others are prerequisites
git_submodules = gcc binutils
git_submodules += gmp mpc mpfr
git_submodules += cloog isl

# List of submodules dependencies that need to be fixed-up or generated
fixup_git_submodules_deps = $(git_submodules:%=$(git_submodulesdir)/%/configure)
fixup_git_submodules_deps += $(git_submodulesdir)/gmp/doc/version.texi

# GCC configure flags (default: build C & C++ support only)
gcc_confflags = \
	--prefix=$(prefix) \
	--host=$(host_triplet) \
	--build=$(build_triplet) \
	--target=$(target_triplet) \
	--enable-languages=c,c++ \
	--disable-multilib
gcc_confflags += $(EXTRA_CONFIGURE_FLAGS)

# The number of allowed parallel jobs
PARALLEL_JOBS ?= $(shell getconf _NPROCESSORS_ONLN)

# GCC make flags (default: make -j<N> / <N> is the number of logical threads)
gcc_makeflags = -j$(PARALLEL_JOBS)
gcc_makeflags += $(EXTRA_MAKE_FLAGS)


# -----------------------------------------------------------------------------
# --- Rules for extracting versions for thirdparty components (submodules)  ---
# -----------------------------------------------------------------------------

# Pattern for matching version nubmers
p_version = \([0-9][0-9.]*\)

# Plain characters (comma, space)
c_comma := ,
c_empty :=
c_space := $(c_empty) $(c_empty)

# The GNU Compiler Collection (GCC)
v_gcc = $(shell cat $(firstword $(wildcard \
		$(git_submodulesdir)/gcc/gcc/FULL-VER \
		$(git_submodulesdir)/gcc/gcc/BASE-VER)))

# ... the corresponding GCC branch
v_gcc_branch = $(subst $(c_space),.,$(wordlist 1, 2, $(subst ., ,$(v_gcc))))

# The GNU Binary Utilities (GMP)
v_binutils = $(shell sed -n '/^PACKAGE_VERSION=.$(p_version)./s//\1/p' \
	$(git_submodulesdir)/binutils/binutils/configure)

# The GNU Multi-Precision arithmetic library (GMP)
v_gmp_mj = $(shell sed -n '/.*_VERSION  *$(p_version)/s//\1/p' \
	$(git_submodulesdir)/gmp/gmp-h.in)
v_gmp_mn = $(shell sed -n '/.*_VERSION_MINOR  *$(p_version)/s//\1/p' \
	$(git_submodulesdir)/gmp/gmp-h.in)
v_gmp_mc = $(shell sed -n '/.*_VERSION_PATCHLEVEL  *$(p_version)/s//\1/p' \
	$(git_submodulesdir)/gmp/gmp-h.in)
v_gmp = $(v_gmp_mj).$(v_gmp_mn).$(v_gmp_mc)

# ... the corresponding last change date
v_gmp_date = $(word 1,$(shell head -n1 $(git_submodulesdir)/gmp/ChangeLog))

# The Multi-Precision Complex library (MPC)
v_mpc = $(shell sed -n '/.*MPC_VERSION_STRING  *"$(p_version).*"/s//\1/p' \
	$(git_submodulesdir)/mpc/src/mpc.h)

# The Multi-Precision floating-point computations library (MPFR)
v_mpfr = $(shell sed -n '/.*MPFR_VERSION_STRING  *"$(p_version).*"/s//\1/p' \
	$(git_submodulesdir)/mpfr/src/mpfr.h)

# The Chunk Loop Generator (CLooG)
v_cloog = $(shell sed -n '1s/version: $(p_version)/\1/p' \
	$(git_submodulesdir)/cloog/ChangeLog)

# The Integer Set Library (ISL)
v_isl = $(shell sed -n '1s/version: $(p_version)/\1/p' \
	$(git_submodulesdir)/isl/ChangeLog)


# -----------------------------------------------------------------------------
# --- Rules for configuring, building and installing the toolchain          ---
# -----------------------------------------------------------------------------

print.versions: fetch.git.submodules
	@echo "#"
	@echo "# GCC toolchain versions"
	@echo "#"
	@$(foreach repo, $(git_submodules), \
		printf "%-20s : %s\n" $(repo) $(v_$(repo));)

.NOTPARALLEL: prepare prepare.dirs prepare.srcs
prepare: prepare.dirs prepare.srcs

prepare.dirs: $(srcdir)
$(srcdir):
	mkdir -p $@

prepare.srcs: fixup.git.submodules $(git_submodules:%=$(srcdir)/%/configure)
$(srcdir)/gcc/configure: $(git_submodulesdir)/gcc/gcc/configure
	repo="gcc" ; \
	for f in $$(cd $(git_submodulesdir)/$$repo && ls); do \
		$(LN_S) -f ../$(git_submodulesdir)/$$repo/$$f $(srcdir)/ ; \
	done
$(srcdir)/binutils/configure: $(git_submodulesdir)/binutils/binutils/configure
	repo="binutils" ; \
	for f in $$(cd $(git_submodulesdir)/$$repo && ls); do \
		[ -e "$(srcdir)/$$f" ] || \
		$(LN_S) ../$(git_submodulesdir)/$$repo/$$f $(srcdir)/ ; \
	done
$(srcdir)/%/configure: $(git_submodulesdir)/%/configure
	repo="$(*F)" ; \
	$(LN_S) ../$(git_submodulesdir)/$$repo $(srcdir)/$$repo


.NOTPARALLEL: configure configure.dirs configure.objs
configure: configure.dirs configure.objs

configure.dirs: $(objdir)
$(objdir):
	mkdir -p $@

configure.objs: $(objdir)/Makefile
$(objdir)/Makefile: prepare
	cd $(objdir) && ../$(srcdir)/configure $(gcc_confflags)

build: configure
	$(MAKE) build.only
build.only:
	$(MAKE) -C $(objdir) $(gcc_makeflags)

install: build
	$(MAKE) install.only
install.only:
	$(MAKE) -C $(objdir) install DESTDIR=$(DESTDIR)


# -----------------------------------------------------------------------------
# --- Rules for preparing the git submodules                                ---
# -----------------------------------------------------------------------------

fetch.git.submodules: $(git_submodules:%=$(git_submodulesdir)/%/.git)
$(git_submodulesdir)/%/.git:
	repo="$(*F)" ; \
	(cd $(git_submodulesdir) && $(GIT) submodule update --init $$repo)

clean.git.submodules: $(git_submodules:%=clean.git.submodule.%)
clean.git.submodule.%:
	repo="$(*F)" dir="$(git_submodulesdir)/$$repo" ; \
	[ -d $$dir ] && (cd $$dir && $(GIT) clean -dfx)

reset.git.submodules: $(git_submodules:%=reset.git.submodule.%)
reset.git.submodule.%: clean.git.submodule.%
	repo="$(*F)" dir="$(git_submodulesdir)/$$repo" ; \
	[ -d $$dir ] && (cd $$dir && $(GIT) reset --hard)

fixup.git.submodules: $(fixup_git_submodules_deps)
$(git_submodulesdir)/%/configure: $(git_submodulesdir)/%/.git
	repo="$(*F)" dir="$(git_submodulesdir)/$$repo" ; \
	(cd $$dir && $(AUTORECONF) -vif)

$(git_submodulesdir)/gmp/doc/version.texi:
	@echo "@set UPDATED `LC_ALL=C date +'%d %B %Y' -d $(v_gmp_date)`" > $@
	@echo "@set UPDATED-MONTH `LC_ALL=C date +'%B %Y' -d $(v_gmp_date)`" >> $@
	@echo "@set EDITION $(v_gmp)" >> $@
	@echo "@set VERSION $(v_gmp)" >> $@
