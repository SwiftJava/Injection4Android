#!/bin/bash -x

#  builder.sh
#  Injection4Android
#
#  Created by John Holdsworth on 15/09/2017.
#  Copyright © 2017 John Holdsworth. All rights reserved.

cd "$1" && time ~/.gradle/scripts/swift-build.sh || exit $?

LIBS_DIR="../jniLibs/armeabi-v7a"
OBJECT_FILE="$(find ".build" -name "$(basename "$2").o")"
LINK_WITH="$(perl -e 'print join " ", map "-l$_", grep $_ !~ /Onone|Mirror|scu/, map $_ =~ /lib(\w+)\.so/, @ARGV;' $LIBS_DIR/*.so)"

time ~/.gradle/scripts/swiftc-android.sh -g -emit-library $OBJECT_FILE -o "$3" -L $LIBS_DIR $LINK_WITH &&

if [[ "$4" != "" ]]; then "$4" push "$3" /data/local/tmp; fi
