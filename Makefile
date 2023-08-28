top_srcdir ?= .

PROJECT := opt-toolchain-gcc

srcdir = $(top_srcdir)/src
objdir = $(top_srcdir)/obj.$(target_triplet)
prefix = /opt/toolchain/gcc-$(v_gcc_branch)

# Determine the host operating system variant
dist_release := $(shell lsb_release -cs 2>/dev/null)

# Filter out -Werror and -Werror=* from compilation flags (CFLAGS, CXXFLAGS)
# ... and use memory for temporaries, not disk files
CFLAGS   := $(filter-out -Werror%, $(CFLAGS)) -pipe
CXXFLAGS := $(filter-out -Werror%, $(CXXFLAGS)) -pipe

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

# UNIX timestamp of the last git commit
project_timestamp = $(shell cat $(top_srcdir)/.timestamp 2>/dev/null)

# Toplevel git submodules directory
git_submodulesdir = $(top_srcdir)/ext

# The list of git submodules to use, with GCC first -- others are prerequisites
git_submodules = gcc
git_submodules += binutils
git_submodules += gmp mpc mpfr
git_submodules += cloog isl

# List of submodules dependencies that need to be fixed-up or generated
fixup_git_submodules_deps = $(git_submodules:%=$(git_submodulesdir)/%/configure)
fixup_git_submodules_deps += $(git_submodulesdir)/gmp/doc/version.texi

# Linker options. Flag: do we use DT_GNU_HASH style by default?
ld_hash_style = gnu
ifneq (,$(filter $(dist_release),squeeze wheezy))
ld_hash_style = both
endif

# GCC configure flags (default: build C & C++ support only)
gcc_confflags = \
	--prefix=$(prefix) \
	--host=$(host_triplet) \
	--build=$(build_triplet) \
	--target=$(target_triplet) \
	--enable-languages=c,c++ \
	--disable-multilib \
	--disable-werror \
	--with-linker-hash-style=$(ld_hash_style) \
	--with-system-zlib
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

# The GNU Binary Utilities (binutils)
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

print.versions: fetch.git.submodules $(top_srcdir)/.timestamp
	@echo "#"
	@echo "# GCC toolchain versions"
	@echo "#"
	@printf "%-20s : %s\n" $(PROJECT) $(project_timestamp)
	@$(foreach repo, $(git_submodules), \
		printf "%-20s : %s\n" $(repo) $(v_$(repo));)

print.%.version: $(git_submodulesdir)/%/configure.ac
	@echo $(v_$(*F))

print.$(PROJECT).version: $(top_srcdir)/.timestamp
	@echo $(project_timestamp)
$(top_srcdir)/.timestamp: $(wildcard $(top_srcdir)/.git/index)
	@(cd $(top_srcdir) && $(GIT) log -1 --oneline --format=format:%ct) >$@

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
		case $$f in (gdb) continue;; esac; \
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

fetch.git.submodules: $(git_submodules:%=$(git_submodulesdir)/%/configure.ac)
$(git_submodulesdir)/%/configure.ac:
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
$(git_submodulesdir)/%/configure: $(git_submodulesdir)/%/configure.ac
	repo="$(*F)" dir="$(git_submodulesdir)/$$repo" ;	\
	case $$repo in						\
	  (binutils)		autoreconf=autoreconf2.64;;	\
	  (*)			autoreconf=autoreconf2.69;;	\
	esac;							\
	(cd $$dir && $$autoreconf -vif) &&			\
	  find $$dir -name configure -exec touch {} \;

$(git_submodulesdir)/gmp/doc/version.texi:
	@echo "@set UPDATED `LC_ALL=C date +'%d %B %Y' -d $(v_gmp_date)`" > $@
	@echo "@set UPDATED-MONTH `LC_ALL=C date +'%B %Y' -d $(v_gmp_date)`" >> $@
	@echo "@set EDITION $(v_gmp)" >> $@
	@echo "@set VERSION $(v_gmp)" >> $@


# -----------------------------------------------------------------------------
# --- Rules for generating a tarball                                        ---
# -----------------------------------------------------------------------------

distdir	 = $(top_srcdir)/dist
distname = $(PROJECT)-$(v_gcc_branch)-$(v_gcc)~$(project_timestamp)
distfile = $(distname).tar.gz

AUTORECONF_GENERATED_FILES := \
	Makefile.in \
	aclocal.m4 \
	ar-lib \
	compile \
	config.guess \
	config.h.in \
	config.in \
	config.sub \
	configure \
	depcomp \
	doc/mdate.sh \
	doc/texinfo.tex \
	install-sh \
	isl_config.h.in \
	ltmain.sh \
	missing \
	test-driver \
	ylwrap

dist.list.deps: fixup.git.submodules $(top_srcdir)/.timestamp
dist.list: dist.list.deps
	@echo .timestamp ;						    \
	for d in . `$(GIT) submodule foreach --quiet 'echo $$path')`; do    \
	  (cd $$d && git ls-tree -r --name-only HEAD) | while read -r f; do \
	    case $$f in (\"*\") f=$$(eval printf "$$f");; esac;		    \
	    case $$f in							    \
	      (*.git*|*.cvs*) continue;;				    \
	      (\"*\") f=$$(eval printf "$ff");;				    \
	    esac;							    \
	    [ -d "$$d/$$f" ] && [ -n "`ls -A $$d/$$f`" ] && continue;	    \
	    echo "$$d/$$f";						    \
	    case "$$f" in						    \
	      (*/Makefile.am|Makefile.am)				    \
		gd="$$d/`dirname $$f`";					    \
		$(foreach gf, $(AUTORECONF_GENERATED_FILES),		    \
		  [ -f "$$gd/$(gf)" ] && echo "$$gd/$(gf)";)		    \
		[ -d "$$gd/m4" ] && ls -1 "$$gd/m4"/*.m4;		    \
		;;							    \
	    esac;							    \
	  done;								    \
	done

dist.file: dist.dirs dist.list.deps
	$(MAKE) -s dist.list | tar zcf $(distdir)/$(distfile) \
	  --no-recursion --transform 's|^|$(distname)/|' -T -

dist.dirs: $(distdir)
$(distdir):
	@mkdir -p $@


# -----------------------------------------------------------------------------
# --- Rules for .deb packaging                                              ---
# -----------------------------------------------------------------------------

DEB_GENERATED_FILES := \
	debian/opt-toolchain-gcc-$(v_gcc_branch).install \
	debian/lintian-overrides \
	debian/changelog \
	debian/control

debsrc_dir  = $(top_srcdir)/..
debsrc_name = $(PROJECT)-$(v_gcc_branch)_$(v_gcc)~$(project_timestamp).orig
debsrc_file = $(debsrc_name).tar.gz

deb.files: $(DEB_GENERATED_FILES)
deb: deb.files $(debsrc_dir)/$(debsrc_file)
	debuild -b -uc -us

debsrc.file.orig: $(debsrc_dir)/$(debsrc_file)
$(debsrc_dir)/$(debsrc_file): dist.dirs dist.list.deps
	$(MAKE) -s dist.list | tar zcf $(debsrc_dir)/$(debsrc_file) \
	  --no-recursion --transform 's|^|$(debsrc_name)/|' -T - \
	  --exclude "*/debian/*"

debian/%: debian/%.in debian/rules
	./debian/rules $@
debian/$(PROJECT)-$(v_gcc_branch).%: debian/$(PROJECT).%.in debian/rules
	./debian/rules $@
