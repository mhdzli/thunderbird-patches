#!/bin/sh

if [ "$#" -ne 1 ] ; then
  echo "Usage: $0 VERSION" >&2
  exit 1
fi

if ! [ -d thunderbird-patches ]; then
  echo "No clone of https://github.com/Betterbird/thunderbird-patches.git" >&2
  echo "How did you get this build script in the first place?" >&2
  exit 1
fi

echo
echo "======================================================="
echo "Updating Betterbird patches"
cd thunderbird-patches
git pull
cd ..

DIFF=$(diff -q build.sh thunderbird-patches/build/build.sh)
if [ "|$DIFF|" != "||" ]; then
  echo "Newer version of build script available."
  echo "Please |cp thunderbird-patches/build/build.sh .| and restart"
  exit 1
fi

if ! [ -d thunderbird-patches/"$1" ]; then
  echo "No such version" >&2
  exit 1
fi

VERSION="$1"
UNAME=$(uname)
UNAME_ARCH=$(uname -i)

. ./thunderbird-patches/$VERSION/$VERSION.sh

echo
echo "======================================================="
echo "Preparing Mozilla repo"
echo "  for $mozilla_repo"
echo "  at $mozilla_rev"

MOZILLA_DIR="$(basename $mozilla_repo)"

if [ -d $MOZILLA_DIR ]; then
  cd $MOZILLA_DIR
else
  echo "Mozilla directory $MOZILLA_DIR not found"
  echo "Do you want to clone the Mozilla repo."
  echo "This will take 30 minutes or more and will pull 2 GB of data."
  read -p "Proceed? (Y/N) " ANSWER
  if [ "$ANSWER" != "Y" ]; then
    echo "Y not received, exiting"
    exit 1
  fi
  echo
  echo "======================================================="
  echo "Cloning $mozilla_repo"
  hg clone $mozilla_repo
  echo
  echo "======================================================="
  echo "Cloning $comm_repo"
  cd $MOZILLA_DIR
  hg clone $comm_repo comm
fi

if [ "$UNAME" = "Linux" ]; then
  if [ "$UNAME_ARCH" = "x86_64" ]; then
    echo
    echo "======================================================="
    echo "Copying mozconfig-Linux"
    cp ../thunderbird-patches/$VERSION/mozconfig-Linux mozconfig
  elif [ "$UNAME_ARCH" = "aarch64" ]; then
    echo
    echo "======================================================="
    echo "Copying mozconfig-Linux-aarch64"
    cp ../thunderbird-patches/$VERSION/mozconfig-Linux-aarch64 mozconfig
  fi
elif [ "$UNAME" = "Darwin" ]; then
  echo
  echo "======================================================="
  echo "Copying mozconfig-Mac"
  cp ../thunderbird-patches/$VERSION/mozconfig-Mac mozconfig
fi

MQ=$(grep "mq =" .hg/hgrc)
if [ "|$MQ|" = "||" ]; then
  echo "[extensions]" >> .hg/hgrc
  echo "mq =" >> .hg/hgrc
fi
MQ=$(grep "mq =" comm/.hg/hgrc)
if [ "|$MQ|" = "||" ]; then
  echo "[extensions]" >> comm/.hg/hgrc
  echo "mq =" >> comm/.hg/hgrc
fi

if [ -f ../mach_bootstrap_was_run_$VERSION ]; then
  echo
  echo "======================================================="
  echo "NOT running ./mach bootstrap since ./mach_bootstrap_was_run_$VERSION is present."
else
  echo
  echo "======================================================="
  echo "Running ./mach bootstrap ONCE. This is controlled by ./mach_bootstrap_was_run_$VERSION."
  echo "Note that this may require a restart of the shell."
  touch ../mach_bootstrap_was_run_$VERSION
  ./mach --no-interactive bootstrap --application-choice "Firefox for Desktop"
  if [ "$UNAME" = "Linux" ] && [ "$UNAME_ARCH" = "aarch64" ]; then
    echo
    echo "======================================================="
    echo "./mach bootstrap on Linux/aarch64 likely failed to complete."
    echo "Please try the following before restarting the script:"
    echo "(This is known to work on a Ubuntu 20.04 aarch64 machine.)"
    echo "sudo apt install nano watchman \ "
    echo "  python3-setuptools python3-wheel default-jre default-jdk \ "
    echo "  gcc g++ binutils libc6 libc6-dev libgcc-9-dev libstdc++-9-dev \ "
    echo "  libstdc++6 linux-libc-dev libstdc++6 libstdc++-9-dev \ "
    echo "  libx11-dev libxext-dev libxt-dev libxcb1-dev libxcb-shm0-dev libx11-xcb-dev \ "
    echo "  clang clang-tools clang-format clangd clang-tidy-10 \ "
    echo "  libclang-10-dev libclang-common-10-dev libclang-cpp10 libclang1-10 libclang-dev libclang-cpp10-dev \ "
    echo "  llvm llvm-runtime libllvm11 llvm-dev \ "
    echo "  libc++1-11 libc++abi1-11 libc++-11-dev libgtk-3-dev libdbus-glib-1-dev"
    echo "Rust should already be installed if you followed the instructions, otherwise turn to https://rust-lang.github.io/rustup/installation/other.html."
    echo "Issue command: cargo install cbindgen"
    echo "Install node and npm using the nvm script (instructions and script are from: https://github.com/nvm-sh/nvm)."
    echo "You only need to do all of these steps once or whenever the Betterbird build requires updated software versions."
    exit 1
  elif [ "$UNAME" = "Darwin" ]; then
    echo
    echo "======================================================="
    echo "./mach bootstrap can fail on Mac. It should be safe to ignore the errors."
  fi
fi

echo
echo "======================================================="
echo "Removing old patches from $MOZILLA_DIR and updating"
hg revert --all
hg qpop --all
hg pull
hg update -r $mozilla_rev

echo
echo "======================================================="
echo "Preparing comm repo"
echo "  for $comm_repo"
echo "  at $comm_rev"

cd comm
echo
echo "======================================================="
echo "Removing old patches from $MOZILLA_DIR/comm and updating"
hg revert --all
hg qpop --all
hg pull
hg update -r $comm_rev
cd ..

echo
echo "======================================================="
echo "Copying patches and series file from thunderbird-patches"
if ! [ -d .hg/patches ]; then
  mkdir .hg/patches
fi
if ! [ -d comm/.hg/patches ]; then
  mkdir comm/.hg/patches
fi
cp ../thunderbird-patches/$VERSION/series-M-C            .hg/patches/series
cp ../thunderbird-patches/$VERSION/series           comm/.hg/patches/series
cp ../thunderbird-patches/$VERSION/branding/*.patch comm/.hg/patches/
cp ../thunderbird-patches/$VERSION/bugs/*.patch     comm/.hg/patches/
cp ../thunderbird-patches/$VERSION/features/*.patch comm/.hg/patches/
cp ../thunderbird-patches/$VERSION/misc/*.patch     comm/.hg/patches/
mv comm/.hg/patches/*-m-c.patch .hg/patches/

echo
echo "======================================================="
echo "Retrieving external patches for Mozilla repo"
echo "#!/bin/sh" > external.sh
grep " # " .hg/patches/series >> external.sh
sed -i -e 's/\/rev\//\/raw-rev\//' external.sh
sed -i -e 's/\(.*\) # \(.*\)/wget -nc \2 -O .hg\/patches\/\1/' external.sh
chmod 700 external.sh
. ./external.sh
rm external.sh

echo
echo "======================================================="
echo "Retrieving external patches for comm repo"
cd comm
echo "#!/bin/sh" > external.sh
grep " # " .hg/patches/series >> external.sh
sed -i -e 's/\/rev\//\/raw-rev\//' external.sh
sed -i -e 's/\(.*\) # \(.*\)/wget -nc \2 -O .hg\/patches\/\1/' external.sh
chmod 700 external.sh
. ./external.sh
rm external.sh
cd ..

echo
echo "======================================================="
echo "Pushing all patches"
hg qpush -all
hg qseries
cd comm
hg qpush -all
hg qseries
cd ..

echo
echo "======================================================="
echo "Starting the build"
./mach clobber
./mach build

echo
echo "======================================================="
echo "Packaging"
./mach package

cd ..
if [ "$UNAME" = "Linux" ]; then
  if [ "$UNAME_ARCH" = "x86_64" ]; then
    echo
    echo "======================================================="
    echo "Find your archive here"
    ls  $MOZILLA_DIR/obj-x86_64-pc-linux-gnu/dist/*.tar.bz2
  elif [ "$UNAME_ARCH" = "aarch64" ]; then
    echo
    echo "======================================================="
    echo "Find your archive here"
    ls  $MOZILLA_DIR/obj-aarch64-unknown-linux-gnu/dist/*.tar.bz2
  fi
elif [ "$UNAME" = "Darwin" ]; then
  echo
  echo "======================================================="
  echo "Find you disk image here"
  ls  $MOZILLA_DIR/obj-x86_64-apple-darwin/dist/*.mac.dmg
fi
