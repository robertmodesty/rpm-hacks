#!/usr/bin/bash
# ar2spec
# MIT License by Wei-Lun Chao <bluebat@member.fsf.org>, 2022.

while [ -n "$1" ] ; do
    if [ "$1" = '-p' -o "$1" = '--packager' ] ; then
        shift
        _PACKAGER="$1"
    elif [ "$1" = '-l' -o "$1" = '--log' ] ; then
        shift
        _LOG="$1"
    elif [ -z "${_FILE}"] ; then
        _FILE="$1"
    else
        _FILE=""
    fi
    shift
done
if [ -z "${_FILE}" ] ; then
    echo "AR2SPEC: Generating .spec file from software archive" >&2
    echo 'Usage: '$(basename $0)' [-p|--packager "NAME <EMAIL>"] [-l|--log LOG] ARCHIVE' >&2
    exit 1
fi

# initial variables
USER=$(whoami)
HOSTNAME=$(hostname)
_TEMPDIR=$(mktemp -d)
_SUMMARY="No summary"
_NAME="foobar"
_VERSION="0"
_LICENSE="Free Software"
_GROUP="Applications"
_SOURCE="${_FILE}"
_URL=""
_BUILDREQUIRES=""
_BUILDARCH=""
_DESCRIPTION="No description."
_SETUP="-q"
_TOOLCHAIN=""
_BUILD="No build"
_INSTALL=""
_DOCS=""
_DATE=$(LC_ALL=C date '+%a %b %d %Y')
[ -z "${_PACKAGER}" ] && _PACKAGER="$(getent passwd ${USER}|cut -d: -f5|cut -d, -f1) <${USER}@${HOSTNAME}>"
[ -z "${_LOG}" ] && _LOG="spec generated by ar2spec"

# unpack archive
_FILEEXT="${_FILE##*.}"
if [ "${_FILEEXT}" = gz -o "${_FILEEXT}" = bz2 -o "${_FILEEXT}" = xz ] ; then
    tar xf "${_FILE}" -C "${_TEMPDIR}"
    _BASENAME=${_FILE%.tar.*}
    _URLSITE="github"
elif [ "${_FILEEXT}" = tgz -o "${_FILEEXT}" = tbz2 -o "${_FILEEXT}" = txz ] ; then
    tar xf "${_FILE}" -C "${_TEMPDIR}"
    _BASENAME=${_FILE%.t*z*}
    _URLSITE="sourceforge"
elif [ "${_FILEEXT}" = tar ] ; then
    tar xf "${_FILE}" -C "${_TEMPDIR}"
    _BASENAME=${_FILE%.tar}
    _URLSITE="sourceforge"
elif [ "${_FILEEXT}" = zip ] ; then
    unzip -qq "${_FILE}" -d "${_TEMPDIR}"
    _BASENAME=${_FILE%.zip}
    _URLSITE="github"
elif [ "${_FILEEXT}" = 7z ] ; then
    7za x "${_FILE}" -o"${_TEMPDIR}" > /dev/null
    _BASENAME=${_FILE%.7z}
    _URLSITE="sourceforge"
    _BUILDREQUIRES=" p7zip"
else
    echo "ERROR! Unrecognized archive: ${_FILE}" >&2
    exit 1
fi
_BASENAME="${_BASENAME/[_-][Ss]ourcecode/}"
_BASENAME="${_BASENAME/[_-][Ss]ource/}"
_BASENAME="${_BASENAME/[_-][Ss]rc/}"
_BASENAME="${_BASENAME/[_-][Rr]elease/}"
_BASENAME="${_BASENAME/[_-][Ll]inux/}"
_BASENAME="${_BASENAME/[_-][Aa]ll/}"
_BASENAME="${_BASENAME/.orig/}"
_NAME="${_BASENAME%%-[0-9]*}"
[ "${_NAME}" = "${_BASENAME}" ] && _NAME="${_BASENAME%%_[0-9]*}"
[ "${_NAME}" = "${_BASENAME}" ] && _NAME="${_BASENAME%-*}"
[ "${_NAME}" = "${_BASENAME}" ] && _NAME="${_BASENAME%_*}"
_VERSION="${_BASENAME#${_NAME}}"
_VERSION="${_VERSION#[-_]}"
_VERSION="${_VERSION#v}"
[ -z "${_VERSION}" ] && _VERSION="0"
_NAME=${_NAME,,}
if [ "${_URLSITE}" = github ] ; then
    _URL=$(curl -s 'https://github.com/search?q='${_NAME}'&type=repositories'|grep -im1 'https://github.com/[0-9A-Za-z]*/'${_NAME}'&quot;'|sed 's|.*\(https://github.com/[-0-9A-Za-z]*/'${_NAME}'\).*|\1|i')
    if [ -n "${_URL}" ] ; then
        _SUMMARY=$(curl -s "${_URL}"|grep -im1 '<title>GitHub'|sed 's|.*<title>GitHub - .*/'${_NAME}': \(.*\)</title>|\1|i')
        if [ "${_VERSION}" = master -o "${_VERSION}" = main ] ; then
            _SOURCE="${_URL}"'/archive/refs/heads/'${_VERSION}'.zip#/%{name}-'${_VERSION}'.zip'
        else
            _SOURCE="${_URL}"'/archive/%{version}.tar.gz#/%{name}-%{version}.tar.gz'
        fi
    else
        _URLSITE="sourceforge"
    fi
fi
if [ "${_URLSITE}" = sourceforge ] ; then
    _URL="http://sourceforge.net/projects/${_NAME}"
    _SUMMARY=$(curl -s "${_URL}/"|grep -im1 '<meta name="description" content="Download'|sed 's|<meta name="description" content="Download.*for free. \([^\.]*\)\..*|\1|i')
    _SOURCE="${_URL}/files/${_FILE/${_VERSION}/%\{version\}}"
fi
[ -z "${_SUMMARY}" ] && _SUMMARY="No summary"

# change directory
pushd "${_TEMPDIR}" > /dev/null
_DIRNUM=$(ls|wc -l)
if [ "${_DIRNUM}" -eq 0 ] ; then
    echo "ERROR! No files found." >&2
    exit 1
elif [ "${_DIRNUM}" -eq 1 ] ; then
    _DIRNAME=$(ls)
    cd "${_DIRNAME}"
    _DIRNAME="${_DIRNAME// /\\ }"
    if [ "${_DIRNAME}" != "${_NAME}-${_VERSION}" ] ; then
        _SETUP+=" -n ${_DIRNAME/${_VERSION}/%\{version\}}"
    fi
else
    _SETUP+=" -c"
fi
for f in *.md *.txt *.rst *.pdf COPYING COPYING.L* LICENSE AUTHORS NEWS CHANGELOG ChangeLog README TODO THANKS ; do
    [ -f "$f" ] && _DOCS+=" $f"
done
_DOCS="${_DOCS/ CMakeLists.txt/}"
if [ -n "${_DOCS}" ] ; then
    if grep -qi "GNU General Public License" ${_DOCS} ; then
        _LICENSE="GPL"
    elif grep -qi "GPL.*license" ${_DOCS} ; then
        _LICENSE="GPL"
    elif grep -qi "MIT.*license" ${_DOCS} ; then
        _LICENSE="MIT"
    elif grep -qi "Apache.*license" ${_DOCS} ; then
        _LICENSE="Apache"
    elif grep -qi "BSD.*license" ${_DOCS} ; then
        _LICENSE="BSD"
    elif grep -qi "AS IS" ${_DOCS} ; then
        _LICENSE="BSD"
    fi
fi
if [ -f bootstrap.sh ] ; then
    _TOOLCHAIN="bootstrap"
elif [ -f autogen.sh ] ; then
    _TOOLCHAIN="autogen"
elif [ -f configure ] ; then
    _TOOLCHAIN="configure"
elif [ -f Makefile -o -f makefile -o -f GNUmakefile ] ; then
    _TOOLCHAIN="make"
elif [ -f CMakeLists.txt ] ; then
    _TOOLCHAIN="cmake"
elif [ -f *.pro ] ; then
    _TOOLCHAIN="qmake"
elif [ -f Cargo.toml ] ; then
    _TOOLCHAIN="cargo"
elif [ -f go.mod ] ; then
    _TOOLCHAIN="go"
elif [ -f meson.build ] ; then
    _TOOLCHAIN="meson"
elif [ -f build.ninja ] ; then
    _TOOLCHAIN="ninja"
elif [ -f setup.py ] ; then
    _TOOLCHAIN="python"
elif [ -f SConstruct ] ; then
    _TOOLCHAIN="scons"
elif [ -f Imakefile ] ; then
    _TOOLCHAIN="imake"
elif [ -f Rakefile ] ; then
    _TOOLCHAIN="rake"
elif [ -f "${_NAME}.py" -o -f "${_NAME}.pl" -o -f "${_NAME}.lua" ] ; then
    _TOOLCHAIN="script"
elif [ -f build.xml ] ; then
    _TOOLCHAIN="java"
fi
popd > /dev/null
rm -rf "${_TEMPDIR}"

# post setting
if [ "${_TOOLCHAIN}" = bootstrap ] ; then
    _BUILDREQUIRES+=" automake"
    _BUILD="./bootstrap.sh\n%{configure}\n%{make_build}"
    _INSTALL="%{make_install}"
elif [ "${_TOOLCHAIN}" = autogen ] ; then
    _BUILDREQUIRES+=" automake"
    _BUILD="./autogen.sh\n%{configure}\n%{make_build}"
    _INSTALL="%{make_install}"
elif [ "${_TOOLCHAIN}" = configure ] ; then
    _BUILDREQUIRES+=" automake"
    _BUILD="%{configure}\n%{make_build}"
    _INSTALL="%{make_install}"
elif [ "${_TOOLCHAIN}" = make ] ; then
    _BUILD="%{make_build}"
    _INSTALL="%{make_install}"
elif [ "${_TOOLCHAIN}" = cmake ] ; then
    _BUILDREQUIRES+=" cmake"
    _BUILD="%{cmake}\n%{cmake_build}"
    _INSTALL="%{cmake_install}"
elif [ "${_TOOLCHAIN}" = qmake ] ; then
    _BUILDREQUIRES+=" qt5-qtbase-devel"
    _BUILD="%{qmake_qt5}\n%{make_build}"
    _INSTALL="%{make_install}"
elif [ "${_TOOLCHAIN}" = cargo ] ; then
    _BUILDREQUIRES+=" cargo"
    _BUILD="#%{cargo_build}\ncargo build --release"
    _INSTALL="#%{cargo_install}\n#cargo install --root=%{buildroot}%{_prefix} --path=.\ninstall -Dm755 target/release/%{name} %{buildroot}%{_bindir}/%{name}"
elif [ "${_TOOLCHAIN}" = go ] ; then
    _BUILDREQUIRES+=" golang"
    _BUILD="go build"
    _INSTALL="install -Dm755 %{name} %{buildroot}%{_bindir}/%{name}"
elif [ "${_TOOLCHAIN}" = meson ] ; then
    _BUILDREQUIRES+=" meson"
    _BUILD="%{meson}\n%{meson_build}"
    _INSTALL="%{meson_install}"
elif [ "${_TOOLCHAIN}" = ninja ] ; then
    _BUILDREQUIRES+=" ninja-build"
    _BUILD="ninja -C build"
    _INSTALL="ninja install -C build"
elif [ "${_TOOLCHAIN}" = python ] ; then
    _BUILDREQUIRES+=" python3-devel"
    _BUILDARCH="noarch"
    _BUILD="%{py3_build}"
    _INSTALL="%{py3_install}"
elif [ "${_TOOLCHAIN}" = scons ] ; then
    _BUILDREQUIRES+=" python3-scons"
    _BUILDARCH="noarch"
    _BUILD="scons build perfix=/usr"
    _INSTALL="scons --install-sandbox=%{buildroot} install"
elif [ "${_TOOLCHAIN}" = imake ] ; then
    _BUILDREQUIRES+=" imake"
    _BUILD="xmkmf -a\n%{make_build}"
    _INSTALL="install -Dm755 %{name} %{buildroot}%{_bindir}/%{name}"
elif [ "${_TOOLCHAIN}" = rake ] ; then
    _BUILDREQUIRES+=" rubygem-rake"
    _BUILD="rake build"
    _INSTALL="rake install DESTDIR=%{buildroot}"
elif [ "${_TOOLCHAIN}" = script ] ; then
    _BUILDARCH="noarch"
    _INSTALL="for i in py pl lua;do\nif test -f %{name}.$i;then\ninstall -Dm755 %{name}.$i %{buildroot}%{_bindir}/%{name}\nfi\ndone"
elif [ "${_TOOLCHAIN}" = java ] ; then
    _BUILDREQUIRES+=" java-devel-openjdk"
    _BUILD="ant}"
    _INSTALL="install -d %{buildroot}%{_datadir}/%{name}\ninstall -m644 dist/* %{buildroot}%{_datadir}/%{name}"
fi

#output    
echo '%global __os_install_post %{nil}'
echo '%undefine _debugsource_packages'
echo '%undefine _missing_build_ids_terminate_build'
echo
echo 'Summary:' "${_SUMMARY}"
echo 'Name:' "${_NAME}"
echo 'Version:' "${_VERSION}"
echo 'Release: 1'
echo 'License:' "${_LICENSE}"
echo 'Group:' "${_GROUP}"
echo 'Source0:' "${_SOURCE}"
echo 'URL:' "${_URL}"
[ -n "${_BUILDREQUIRES}" ] && echo 'BuildRequires:'"${_BUILDREQUIRES}"
[ -n "${_BUILDARCH}" ] && echo '#BuildArch:' "${_BUILDARCH}"
echo
echo '%description'
echo -e "${_DESCRIPTION}"
echo
echo '%prep'
echo '%setup' "${_SETUP}"
echo
echo '%build'
[ -n "${_BUILD}" ] && echo -e "${_BUILD}"
echo
echo '%install'
echo -e "${_INSTALL}"
echo
echo '%files'
[ -n "${_DOCS}" ] && echo '%doc'"${_DOCS}"
echo '/'
echo '#{_bindir}/%{name}'
echo '#{_libdir}/%{name}'
echo '#{_includedir}/%{name}'
echo '#{_datadir}/%{name}'
echo '#{_datadir}/icons/hicolor/*/*/%{name}.*'
echo '#{_datadir}/locale/*/LC_MESSAGES/%{name}.mo'
echo '#{_datadir}/pixmaps/%{name}.*'
echo '#{_sysconfdir}/%{name}.*'
echo '#{python3_sitearch}/*'
echo '#{python3_sitelib}/*'
echo
echo '%changelog'
echo '*' "${_DATE}" "${_PACKAGER}" '-' "${_VERSION}"
echo '-' "${_LOG}"

if [ -z "${_TOOLCHAIN}" ] ; then
    echo "ERROR! Unrecognized toolchain in ${_FILE}" >&2
    exit 1
fi
