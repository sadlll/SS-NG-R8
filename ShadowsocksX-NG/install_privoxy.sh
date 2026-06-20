#!/bin/sh

#  install_privoxy.sh
#  ShadowsocksX-NG
#
#  Created by 王晨 on 16/10/7.
#  Copyright © 2016年 zhfish. All rights reserved.


cd "$(dirname "${BASH_SOURCE[0]}")"
privoxyVersion=4.2.0.arm64
installDir="$HOME/Library/Application Support/ShadowsocksX-NG-R8/privoxy-$privoxyVersion"
mkdir -p "$installDir"
cp -f privoxy "$installDir/"
cp -f libpcre2-8.0.dylib "$installDir/"
cp -f libpcre2-posix.3.dylib "$installDir/"
rm -f "$HOME/Library/Application Support/ShadowsocksX-NG-R8/privoxy"
ln -s "$installDir/privoxy" "$HOME/Library/Application Support/ShadowsocksX-NG-R8/privoxy"
echo done
