 # 全局快捷键

ClashX Meta的全局快捷键是通过支持 AppleScript，并以系统的 Automator 程序或者Alfred Workflow调用 AppleScript 来完成全局快捷键的实现。

ClashX Meta目前仅支持以下功能的AppleScript

1.  打开（关闭）系统代理
2.  切换出站模式
3.  打开（关闭）Tun模式
4.  更新配置

## 通过 Automator 创建全局快捷键

[Mac新建全局快捷键](https://www.jianshu.com/p/afee9aeb41a8)

## 使用Alfred Workflow

[Alfred-Workflow-for-ClashX-Meta](https://github.com/hbsgithub/Alfred-Workflow-for-ClashX-Meta)

## 可用的 AppleScript

你可以在这里选择你需要的 AppleScript 代码，以此创建你需要的快捷键。

**以下示例代码为ClashX Meta程序。如果你正在用ClashX或ClashX Pro，那么请将ClashX Meta替换为 ClashX或ClashX Pro**

---

打开（关闭）系统代理

`tell application "ClashX Meta" to toggleProxy`

切换出站模式为全局代理

`tell application "ClashX Meta" to proxyMode 'global'`

切换出站模式为直连

`tell application "ClashX Meta" to proxyMode 'direct'`

切换出站模式为规则代理

`tell application "ClashX Meta" to proxyMode 'rule'`

打开（关闭）Tun模式

`tell application "ClashX Meta" to TunMode`

更新配置

`tell application "ClashX Meta" to updateConfig`

## 已知缺陷

1. 通过 Automator 创建全局快捷键的方式无法直接在桌面使用快捷键，你需要进入任意程序中才能启动快捷键

2. 在任何程序中第一次启用该快捷键都要点击一次确认授权才能启动快捷键
