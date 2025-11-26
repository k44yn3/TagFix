#!/bin/bash


set -e


OS="$(uname -s)"

mkdir -p assets/ffmpeg/linux
mkdir -p assets/ffmpeg/windows
mkdir -p assets/ffmpeg/macos
cd assets/ffmpeg

case "$OS" in
    Linux*)
        PLATFORM="linux"
        ;;
    Darwin*)
        PLATFORM="macos"
        ;;
    MINGW*|MSYS*|CYGWIN*)
        PLATFORM="windows"
        ;;
    *)
        exit 1
        ;;
esac

mkdir -p "$PLATFORM"
cd "$PLATFORM"


if [ "$PLATFORM" = "linux" ]; then

    curl -L -o ffmpeg-release-amd64-static.tar.xz https://johnvansickle.com/ffmpeg/releases/ffmpeg-release-amd64-static.tar.xz

    mkdir temp_extract
    tar -xf ffmpeg-release-amd64-static.tar.xz -C temp_extract

    FOUND_FFMPEG=$(find temp_extract -type f -name ffmpeg | head -n 1)
    if [ -z "$FOUND_FFMPEG" ]; then
        exit 1
    fi

    mv "$FOUND_FFMPEG" ./ffmpeg
    chmod +x ffmpeg

    rm -rf temp_extract ffmpeg-release-amd64-static.tar.xz
fi


if [ "$PLATFORM" = "windows" ]; then

    curl -L -o ffmpeg-master-latest-win64-gpl.zip https://github.com/BtbN/FFmpeg-Builds/releases/download/latest/ffmpeg-master-latest-win64-gpl.zip

    unzip -q -j ffmpeg-master-latest-win64-gpl.zip "*/bin/ffmpeg.exe"
    rm -f ffmpeg-master-latest-win64-gpl.zip

fi


if [ "$PLATFORM" = "macos" ]; then

    curl -L -o ffmpeg.zip https://evermeet.cx/ffmpeg/getrelease/ffmpeg/zip
    unzip -q ffmpeg.zip

    rm -f ffmpeg.zip
    chmod +x ffmpeg

fi


ls -lh ffmpeg* || true
