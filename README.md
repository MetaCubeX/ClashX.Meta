<h1 align="center">
  <img src="https://github.com/Dreamacro/clash/raw/master/docs/logo.png" alt="Clash" width="200">
  <br>
  ClashX
  <br>
</h1>


A rule based proxy For Mac base on [Clash](https://github.com/Dreamacro/clash).

ClashX 旨在提供一个简单轻量化的代理客户端，如果需要更多的定制化，可以考虑使用 [CFW Mac 版](https://github.com/Fndroid/clash_for_windows_pkg/releases) 


## 注意
- ClashX / ClashX Pro 只是一个代理工具，不提供任何代理服务器。如果服务器不可用或与服务器续费有关的问题，请与您的提供商联系。
- ClashX / ClashX Pro 目前并没有创建官网。凡是声称是 ClashX / ClashX Pro 官网的一定是骗子。

## Features

- HTTP/HTTPS and SOCKS protocol
- Surge like configuration
- GeoIP rule support
- Support Vmess/Shadowsocks/Socks5/Trojan
- Support for Netfilter TCP redirect

## Install

You can download from [Release](https://github.com/yichengchen/clashX/releases) page

**Download ClashX Pro With enhanced mode and other clash premium feature at [AppCenter](https://install.appcenter.ms/users/clashx/apps/clashx-pro/distribution_groups/public) for free permanently.**

**在 [AppCenter](https://install.appcenter.ms/users/clashx/apps/clashx-pro/distribution_groups/public) 免费下载ClashX Pro版本，支持增强模式以及更多Clash Premium Core特性。**

## Build
- Make sure have python3 and golang installed in your computer.

- Install Golang
  ```
  brew install golang

  or download from https://golang.org
  ```

- Download deps
  ```
  bash install_dependency.sh
  ```

- Build and run.

## Config


The default configuration directory is `$HOME/.config/clash`

The default name of the configuration file is `config.yaml`. You can use your custom config name and switch config in menu `Config` section.


Checkout [Clash](https://github.com/Dreamacro/clash) or [SS-Rule-Snippet for Clash](https://github.com/Hackl0us/SS-Rule-Snippet/blob/master/LAZY_RULES/clash.yaml) or [lancellc's gitbook](https://lancellc.gitbook.io/clash/) for more detail.

## Advance Config

### 修改代理端口号
1. 在菜单栏->配置->更多设置中修改对应端口号



### Change your status menu icon

  Place your icon file in the `~/.config/clash/menuImage.png`  then restart ClashX

### Change default system ignore list.

- Change by menu -> Config -> Setting -> Bypass proxy settings for these Hosts & Domains

### URL Schemes.

- Using url scheme to import remote config.

  ```
  clash://install-config?url=http%3A%2F%2Fexample.com&name=example
  ```
- Using url scheme to reload current config.

  ```
  clash://update-config
  ```

### Get process name

You can add the follow config in your config file, and set your proxy mode to rule. Then open the log via help menu in ClashX.
```
script:
  code: |
    def main(ctx, metadata):
      # Log ProcessName
      ctx.log('Process Name: ' + ctx.resolve_process_name(metadata))
      return 'DIRECT'
```

### FAQ

- Q: How to get shell command with external IP?  
  A: Click the clashX menu icon and then press `Option-Command-C`  

### 关闭ClashX的通知

1. 在系统设置中关闭 clashx 的推送权限
2. 在菜单栏->配置->更多设置中选中减少通知

Note：强烈不推荐这么做，这可能导致clashx的很多重要错误提醒无法显示。

### 全局快捷键
- 在菜单栏配置->更多配置中，自定义对应功能的快捷键。（需要1.116.1之后的版本）
- 使用AppleScript设置, 详情点击 [全局快捷键](Shortcuts.md)
