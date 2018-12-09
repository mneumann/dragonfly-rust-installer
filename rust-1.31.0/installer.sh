#!/bin/sh

RUST_VERSION=1.31.0
CARGO_VERSION=0.32.0
RUSTFMT_VERSION=1.0.0
RLS_VERSION=1.31.6
CLIPPY_VERSION=0.0.212

ARCH=x86_64-unknown-dragonfly
DEFAULT_DESTDIR=$HOME/usr/rust-${RUST_VERSION}
DEFAULT_DOWNLOAD_SITE=https://www.ntecs.de/downloads/rust/${RUST_VERSION}

write_available_components() {
cat >> $1 <<EOF
	rust-${RUST_VERSION}-${ARCH}		  "Rust - includes components marked with (*)" on
	clippy-${CLIPPY_VERSION}-${ARCH}	  "Clippy - Source code hints (recommended)"   on
	rust-src-${RUST_VERSION}			  "Rust stdlib sources (small)"               off
	rustc-${RUST_VERSION}-src			  "Rust compiler sources (not recommended)"   off
	rustc-${RUST_VERSION}-${ARCH}		  "Rust compiler (*)"						  off
	cargo-${CARGO_VERSION}-${ARCH}		  "Cargo (*)"								  off
	rust-std-${RUST_VERSION}-${ARCH}	  "Rust stdlib (*)"							  off
	rustfmt-${RUSTFMT_VERSION}-${ARCH}	  "rustfmt (*)"								  off
	rls-${RLS_VERSION}-${ARCH}			  "rls (*)"									  off
	rust-analysis-${RUST_VERSION}-${ARCH} "Rust analysis (*)"						  off
	rust-docs-${RUST_VERSION}-${ARCH}     "Documentation (*)"                         off
	llvm-tools-${RUST_VERSION}-${ARCH}    "LLVM tools (recommended for embedded)"     off
EOF
}

#####

trap HUP  quit

TMPDIR=`mktemp -d`
echo "Making temporary direction: $TMPDIR"

cleanup() {
	if [ -d $TMPDIR ]; then
		echo "Cleaning up tempdir $TMPDIR"
		rm -rf $TMPDIR
	fi
}

quit() {
	echo "Premature exit"
	dialog --msgbox "Something went wrong. Rust not installed" 10 50
	cleanup
	exit 1
}

###

txt="This installer will download and install Rust ${RUST_VERSION} on your system."
dialog --yesno "$txt" 10 50 || quit

###

if [ ! -x /usr/local/bin/bash ]; then
	dialog --yesno "Please install bash. Aborting" 10 50
	quit
fi

###

txt="Please enter directory where we will install Rust into. Please make
sure you have permissions to install into this 
directory (might want to run this installer as root)"
dialog --inputbox "$txt" 20 50 $DEFAULT_DESTDIR 2> $TMPDIR/var.destdir || quit
DESTDIR=`cat $TMPDIR/var.destdir`

###

txt="Please select the components of Rust to install:"
cat > $TMPDIR/cmd.components <<EOF
--no-tags --checklist "$txt" 20 75 14
EOF
write_available_components "$TMPDIR/cmd.components"

dialog --file $TMPDIR/cmd.components 2> $TMPDIR/var.components || quit
COMPONENTS=`cat $TMPDIR/var.components`

###

txt="Please enter the download site from where we fetch the Rust components:"
dialog --inputbox "$txt" 20 75 $DEFAULT_DOWNLOAD_SITE 2> $TMPDIR/var.download_site || quit
DOWNLOAD_SITE=`cat $TMPDIR/var.download_site`

###

fetch_progress() {
    file=$1
	url=$2
	fetch -v -o $file $url &
	p=$!
	while true; do
		kill -INFO $p || break
		sleep 5
	done
	wait $p
	return $?
}

download() {
    file=$1
	url=$2

	file_proto=`echo "$url" | cut -c 1-7 -`
	if [ "${file_proto}" = "file://" ]; then
		local_file=`echo "$url" | cut -c 8- -`
		echo "URL is local file: ${local_file}"
		cp $local_file $file || return 1
	else
		if [ -x /usr/local/bin/wget ]; then
			/usr/local/bin/wget -O $file $url || return 1
		else
			fetch -v -o $file $url || return 1
		fi
	fi
}

download_components() {
	for comp in $COMPONENTS; do
		for suff in tar.xz tar.xz.asc; do
			echo "Fetching $fullcomp.$suff"
			download $TMPDIR/downloads/$comp.$suff $DOWNLOAD_SITE/$comp.$suff || return 1
		done
	done
	return 0
}

mkdir -p $TMPDIR/downloads
txt="Downloading components..."
(download_components 2>&1; echo $? > $TMPDIR/es.download) | dialog --progressbox "$txt" 20 75

if [ `cat $TMPDIR/es.download` != "0" ]; then
	quit
fi

####

verify_components() {
	if  [ ! -x /usr/local/bin/gpg ]; then
		echo "WARN: GPG is not install (security/gnupg). Cannot verify downloads."
		return 1
	fi
	for comp in $COMPONENTS; do
		echo "Verify $comp.tar.xz"
		/usr/local/bin/gpg --verify $TMPDIR/downloads/$comp.tar.xz.asc $TMPDIR/downloads/$comp.tar.xz || return  1
	done
	echo "All components verified"
	return 0
}

while :
do
  txt="Verifying downloaded components..."
  (verify_components > $TMPDIR/log.verify 2>&1; echo $? > $TMPDIR/es.verify)
  dialog --title "$txt" --exit-label Continue --tailbox $TMPDIR/log.verify 40 75 || quit
  #(verify_components 2>&1; echo $? > $TMPDIR/es.verify) | dialog --progressbox "$txt" 20 75

  if [ `cat $TMPDIR/es.verify` != "0" ]; then
	txt="Failed to verify download(s). Please add my GPG key (https://www.ntecs.de/contact/pgp-public-key.asc).      Do you still want to continue installation?"
	dialog --default-button extra --extra-button --extra-label Retry --cancel-label Abort --ok-label Continue --yesno "$txt" 20 75
	rc=$?
	if [ "${rc}" = 0 ]; then
		# Continue
		break
	elif [ "${rc}" = 1 ]; then
		# Abort
		quit
	elif [ "${rc}" = 3 ]; then
		# Retry
	fi
  else
	dialog --msgbox "All downloads verified." 20 75
	break
  fi
done

###

extract_components() {
	cd $TMPDIR/downloads
	for comp in $COMPONENTS; do
		echo "Extract $comp"
		tar xvyf $comp.tar.xz || exit 1
	done
}

txt="Extracting components..."
(extract_components 2>&1; echo $? > $TMPDIR/es.extract) | dialog --progressbox "$txt" 20 75

if [ `cat $TMPDIR/es.extract` != "0" ]; then
	quit
fi


###

install_components() {
	for comp in $COMPONENTS; do
		echo "Install $comp"
		/usr/local/bin/bash $TMPDIR/downloads/$comp/install.sh --verbose --prefix=$DESTDIR || exit 1
	done
}

txt="Install components to $DESTDIR..."
(install_components 2>&1; echo $? > $TMPDIR/es.install) | dialog --progressbox "$txt" 20 75

if [ `cat $TMPDIR/es.install` != "0" ]; then
	quit
fi


###


txt="The Rust components were successfully installed into $DESTDIR. Make
sure to put $DESTDIR/bin into your PATH, and $DESTDIR/lib into
LD_LIBRARY_PATH."
dialog --msgbox "$txt" 20 75 || quit

cleanup
