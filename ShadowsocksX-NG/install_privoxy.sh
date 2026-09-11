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

# Install Privoxy templates so it can render its error pages (e.g. no-server-data).
# Without them an upstream failure turns into a hard "500 Internal Privoxy Error"
# instead of the proper "502 No server or forwarder data received".
templatesDir="$HOME/Library/Application Support/ShadowsocksX-NG-R8/templates"
mkdir -p "$templatesDir"
cp -Rf privoxy-templates/. "$templatesDir/"

echo done
