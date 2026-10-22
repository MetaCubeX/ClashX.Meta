#!/bin/bash
set -e

for cmd in git gh; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo "Error: $cmd is not installed."
        exit 1
    fi

    $cmd --version | head -n 1
done

download_and_gzip_rule() {
    local asset_name="$1"

    gh release download latest -R MetaCubeX/meta-rules-dat -p "$asset_name" -D "$tmp_rules_dir"
    gzip "$tmp_rules_dir/$asset_name"
    mv -f "$tmp_rules_dir/$asset_name.gz" "$rules_dir/$asset_name.gz"
}

mihomo_tag="${1:-${MIHOMO_TAG:-}}"
if [ -n "$mihomo_tag" ]; then
    echo "Using mihomo tag: $mihomo_tag"
else
    echo "Using mihomo tag: latest"
fi

echo "Downloading mihomo..."
rm -rf clash.meta
mkdir clash.meta
release_ref="$mihomo_tag"
if [ -z "$release_ref" ]; then
    release_ref=$(gh release list -R MetaCubeX/mihomo --exclude-pre-releases --limit 1 --json tagName -q '.[0].tagName')
fi

asset_tag="$release_ref"

if [ -z "$asset_tag" ]; then
    echo "Error: failed to resolve mihomo release tag."
    exit 1
fi

gh release download "$release_ref" -R MetaCubeX/mihomo -p "mihomo-darwin-arm64-${asset_tag}.gz" -D clash.meta
gh release download "$release_ref" -R MetaCubeX/mihomo -p "mihomo-darwin-amd64-${asset_tag}.gz" -D clash.meta

echo "Download complete."

echo "Unzip core files"
cd clash.meta
ls
gzip -d *.gz
echo "Create Universal core"
lipo -create -output com.metacubex.ClashX.ProxyConfigHelper.meta mihomo-darwin-amd64* mihomo-darwin-arm64*
chmod +x com.metacubex.ClashX.ProxyConfigHelper.meta

echo "Gzip Universal core"
gzip com.metacubex.ClashX.ProxyConfigHelper.meta
cp com.metacubex.ClashX.ProxyConfigHelper.meta.gz ../ClashX/Resources/
cd ..

echo "delete old files"
rm -rf ./ClashX/Resources/meta-rules-dat
rm -rf ./ClashX/Resources/dashboard
rm -f GeoLite2-Country.*

rules_dir="./ClashX/Resources/meta-rules-dat"
mkdir -p "$rules_dir"
tmp_rules_dir="clash.meta"

echo "install mmdb"
download_and_gzip_rule "country.mmdb"

echo "install geosite"
download_and_gzip_rule "geosite.dat"

echo "install geoip"
download_and_gzip_rule "geoip.dat"

echo "install BundleMRS"
download_and_gzip_rule "BundleMRS.7z"


echo "install yacd dashboard"
cd ClashX/Resources
git clone -b gh-pages https://github.com/MetaCubeX/Yacd-meta.git dashboard/yacd --depth=1
cd dashboard/yacd
rm -rf *.webmanifest *.js CNAME .git
cd ../../

echo "install XD dashboard"
git clone -b gh-pages https://github.com/metacubex/metacubexd.git dashboard/xd --depth=1
cd dashboard/xd
rm -rf *.webmanifest CNAME .git
cd ../../

echo "install zashboard"
git clone -b gh-pages https://github.com/Zephyruso/zashboard.git dashboard/zashboard --depth=1
cd dashboard/zashboard
rm -rf *.webmanifest CNAME .git
