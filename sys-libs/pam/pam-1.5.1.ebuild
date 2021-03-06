# Copyright 1999-2020 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

# Flatcar: Based on pam-1.5.1.ebuild from commit
# 6acd106320ca6adf73a4a6607e4daa2b5cea8e30 in gentoo repo (see
# https://gitweb.gentoo.org/repo/gentoo.git/plain/sys-libs/pam/pam-1.5.1.ebuild?id=6acd106320ca6adf73a4a6607e4daa2b5cea8e30).

EAPI=7

MY_P="Linux-${PN^^}-${PV}"

inherit autotools db-use toolchain-funcs multilib-minimal

DESCRIPTION="Linux-PAM (Pluggable Authentication Modules)"
HOMEPAGE="https://github.com/linux-pam/linux-pam"

SRC_URI="https://github.com/linux-pam/linux-pam/releases/download/v${PV}/${MY_P}.tar.xz
	https://github.com/linux-pam/linux-pam/releases/download/v${PV}/${MY_P}-docs.tar.xz"

LICENSE="|| ( BSD GPL-2 )"
SLOT="0"
KEYWORDS="~alpha amd64 arm arm64 hppa ~ia64 ~m68k ~mips ppc ppc64 ~riscv s390 sparc x86 ~amd64-linux ~x86-linux"
IUSE="audit berkdb debug nis +pie selinux"

BDEPEND="
	dev-libs/libxslt
	sys-devel/flex
	sys-devel/gettext
	virtual/pkgconfig
	virtual/yacc
"

DEPEND="
	virtual/libcrypt:=[${MULTILIB_USEDEP}]
	>=virtual/libintl-0-r1[${MULTILIB_USEDEP}]
	audit? ( >=sys-process/audit-2.2.2[${MULTILIB_USEDEP}] )
	berkdb? ( >=sys-libs/db-4.8.30-r1:=[${MULTILIB_USEDEP}] )
	selinux? ( >=sys-libs/libselinux-2.2.2-r4[${MULTILIB_USEDEP}] )
	nis? ( net-libs/libnsl[${MULTILIB_USEDEP}]
	>=net-libs/libtirpc-0.2.4-r2[${MULTILIB_USEDEP}] )"

RDEPEND="${DEPEND}"

PDEPEND=">=sys-auth/pambase-20200616"

PATCHES=(
	"${FILESDIR}"/pam-1.5.0-locked-accounts.patch
)

S="${WORKDIR}/${MY_P}"

src_prepare() {
	default
	touch ChangeLog || die
	eautoreconf
}

multilib_src_configure() {
	# Do not let user's BROWSER setting mess us up. #549684
	unset BROWSER

	# Disable automatic detection of libxcrypt; we _don't_ want the
	# user to link libxcrypt in by default, since we won't track the
	# dependency and allow to break PAM this way.

	export ac_cv_header_xcrypt_h=no

	local myconf=(
		CC_FOR_BUILD="$(tc-getBUILD_CC)"
		--with-db-uniquename=-$(db_findver sys-libs/db)
		--with-xml-catalog="${EPREFIX}"/etc/xml/catalog
		--enable-securedir="${EPREFIX}"/$(get_libdir)/security
		--includedir="${EPREFIX}"/usr/include/security
		--libdir="${EPREFIX}"/usr/$(get_libdir)
		--exec-prefix="${EPREFIX}"
		--enable-unix
		--disable-prelude
		--disable-doc
		--disable-regenerate-docu
		--disable-static
		--disable-Werror
		$(use_enable audit)
		$(use_enable berkdb db)
		$(use_enable debug)
		$(use_enable nis)
		$(use_enable pie)
		$(use_enable selinux)
		--enable-isadir='.' #464016
		--enable-sconfigdir="/usr/lib/pam/"
		)
	ECONF_SOURCE="${S}" econf "${myconf[@]}"
}

multilib_src_compile() {
	emake sepermitlockdir="${EPREFIX}/run/sepermit"
}

multilib_src_install() {
	emake DESTDIR="${D}" install \
		sepermitlockdir="${EPREFIX}/run/sepermit"
}

multilib_src_install_all() {
	find "${ED}" -type f -name '*.la' -delete || die

	# Flatcar: The pam_unix module needs to check the password of
	# the user which requires read access to /etc/shadow
	# only. Make it suid instead of using CAP_DAC_OVERRIDE to
	# avoid a pam -> libcap -> pam dependency loop.
	fperms 4711 /sbin/unix_chkpwd

	# tmpfiles.eclass is impossible to use because
	# there is the pam -> tmpfiles -> systemd -> pam dependency loop

	dodir /usr/lib/tmpfiles.d

	rm "${D}/etc/environment"
	cp "${FILESDIR}/tmpfiles.d/pam.conf" "${D}"/usr/lib/tmpfiles.d/${CATEGORY}-${PN}-config.conf
	cat ->>  "${D}"/usr/lib/tmpfiles.d/${CATEGORY}-${PN}.conf <<-_EOF_
		d /run/faillock 0755 root root
	_EOF_
	use selinux && cat ->>  "${D}"/usr/lib/tmpfiles.d/${CATEGORY}-${PN}-selinux.conf <<-_EOF_
		d /run/sepermit 0755 root root
	_EOF_

	local page

	for page in doc/man/*.{3,5,8} modules/*/*.{5,8} ; do
		doman ${page}
	done
}

pkg_postinst() {
	ewarn "Some software with pre-loaded PAM libraries might experience"
	ewarn "warnings or failures related to missing symbols and/or versions"
	ewarn "after any update. While unfortunate this is a limit of the"
	ewarn "implementation of PAM and the software, and it requires you to"
	ewarn "restart the software manually after the update."
	ewarn ""
	ewarn "You can get a list of such software running a command like"
	ewarn "  lsof / | egrep -i 'del.*libpam\\.so'"
	ewarn ""
	ewarn "Alternatively, simply reboot your system."
}
