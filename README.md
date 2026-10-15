# 山东理工大学移动校园网一键登录

适用于山东理工大学（SDUT、山理工）中国移动校园网。
在 Windows 上双击运行，自动打开认证页面并完成登录，
省去每次开机手动打开网页登录的步骤。

个人维护的非官方项目，非学校或运营商发布的工具。
## 怎么用

电脑需要 Windows 10/11 和 Edge 浏览器。

1. 下载 [校园网助手.cmd](./校园网助手.cmd)。打开文件页面后，点 **Download raw file**；也可以在项目首页点 **Code → Download ZIP**，解压后取出这个文件。
2. 连上校园 Wi-Fi 或插好网线。这时没有互联网是正常的。
3. 双击脚本，第一次填自己的账号密码。以后双击就会自动尝试登录。

要换账号或修改密码，按住 **Shift** 双击，保持片刻，等设置窗口出来再松手。

脚本会在后台用 Edge 操作原来的登录页，不需要另外装软件。它只负责网页登录，不负责连接 Wi-Fi。目前适配的是 <http://111.17.200.130/a79.htm>，其他登录页不一定能用。

## 账号存在哪

账号文件在自己电脑的这个位置，按 Win+R 粘贴路径就能打开：

```text
%LOCALAPPDATA%\CampusLogin-11117200130\credential.xml
```

密码由 Windows 加密保存，账号名称是明文。它们不会写进 CMD 文件，所以把脚本发给别人不会带上自己的账号。删除 `credential.xml` 就能清除保存的账号。

分享时只发 CMD 文件，不要发这个账号文件。

## 连不上怎么办

先试试在[原登录页](http://111.17.200.130/a79.htm)手动登录。如果手动能登、脚本不行，可以按住 Shift 双击重新填一次账号密码。

还是不行的话，看看弹窗里的网页提示。完整记录在：

```text
%LOCALAPPDATA%\CampusLogin-11117200130\diagnostic.txt
```

反馈问题时附上报错文字，发之前检查一下有没有个人信息。目前有部分电脑的登录问题还没解决，不能保证所有人都能直接用。

## 想自己改

PowerShell 源码在 `src/CampusLogin.ps1`，网页操作代码在 `src/PortalAutomation.js`。CMD 里的 Base64 只是为了把代码装进一个文件，可读源码都在这里。

修改后，在项目目录打开 PowerShell，运行下面的命令重新生成 CMD：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\Build.ps1
```

在末尾加 `-Check` 可以核对 CMD 是否与源码一致，不会执行登录。
