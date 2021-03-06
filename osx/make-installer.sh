#!/bin/bash

# abort script if any command fails
set -e

# extract program name for message
pgm=$(basename "$0")

release=""

# find out if we do a release build
while getopts ":r:" o; do
  if [ "${o}" = "r" ]; then
    release="${OPTARG}"
  else
    echo "Unknown option -${o}"
    exit 1
  fi
done
shift $((OPTIND-1))

# set path to find macdeployqt
PATH=/usr/local/opt/qt/bin:$PATH

cd source/build

# get the app to package
app=$(basename "${1}")

if [ -z "$app" ]; then
  echo "No Mudlet app folder to package given."
  echo "Usage: $pgm <Mudlet app folder to package>"
  exit 2
fi

# install installer dependencies
brew update
BREWS="sqlite3 lua@5.1 node wget"
for i in $BREWS; do
  brew outdated | grep -q "$i" && brew upgrade "$i"
done
for i in $BREWS; do
  brew list | grep -q "$i" || brew install "$i"
done
if [ ! -f "macdeployqtfix.py" ]; then
  wget https://raw.githubusercontent.com/aurelien-rainone/macdeployqtfix/master/macdeployqtfix.py
fi
luarocks-5.1 --local install LuaFileSystem
luarocks-5.1 --local install lrexlib-pcre
luarocks-5.1 --local install LuaSQL-SQLite3 SQLITE_DIR=/usr/local/opt/sqlite
luarocks-5.1 --local install luautf8

npm install -g ArmorText/node-appdmg#feature/background-hack

# Bundle in Qt libraries
macdeployqt "${app}"

# fix unfinished deployment of macdeployqt
python macdeployqtfix.py "${app}/Contents/MacOS/Mudlet" "/usr/local/opt/qt/bin"

# Bundle in dynamically loaded libraries
cp "${HOME}/.luarocks/lib/lua/5.1/lfs.so" "${app}/Contents/MacOS"
cp "${HOME}/.luarocks/lib/lua/5.1/rex_pcre.so" "${app}/Contents/MacOS"
# rex_pcre has to be adjusted to load libcpre from the same location
python macdeployqtfix.py "${app}/Contents/MacOS/rex_pcre.so" "/usr/local/opt/qt/bin"
cp -r "${HOME}/.luarocks/lib/lua/5.1/luasql" "${app}/Contents/MacOS"
cp "${HOME}/.luarocks/lib/lua/5.1/lua-utf8.so" "${app}/Contents/MacOS"

# Edit some nice plist entries, don't fail if entries already exist
/usr/libexec/PlistBuddy -c "Add CFBundleName string Mudlet" "${app}/Contents/Info.plist" || true
/usr/libexec/PlistBuddy -c "Add CFBundleDisplayName string Mudlet" "${app}/Contents/Info.plist" || true
if [ -z "${release}" ]; then
  stripped="${app#Mudlet-}"
  version="${stripped%.app}"
  shortVersion="${version%%-*}"
else
  version="${release}"
  shortVersion="${release}"
fi
/usr/libexec/PlistBuddy -c "Add CFBundleShortVersionString string ${shortVersion}" "${app}/Contents/Info.plist" || true
/usr/libexec/PlistBuddy -c "Add CFBundleVersion string ${version}" "${app}/Contents/Info.plist" || true

# Generate final .dmg
cd ../..
rm -f ~/Desktop/Mudlet*.dmg

# Modify appdmg config file according to the app file to package
perl -pi -e "s/Mudlet.*\\.app/${app}/" appdmg/mudlet-appdmg.json

# Last: build *.dmg file
appdmg appdmg/mudlet-appdmg.json "${HOME}/Desktop/${app%.*}.dmg"
