# 校园网助手

Windows 校园网一键登录工具。普通使用者只需要下载 **[校园网助手.cmd](./校园网助手.cmd)**，不需要安装程序、Python 或 Node.js。

适配登录页：<http://111.17.200.130/a79.htm>。需要 Windows 10/11 和已安装的 Microsoft Edge；其他学校或不同登录页不保证适用。

## 使用方法

1. 点击上面的 `校园网助手.cmd`，在 GitHub 文件页面选择 **Download raw file** 下载原始文件；如果找不到，也可从仓库首页选择 **Code → Download ZIP**，解压后取出该文件。
2. 接入校园 Wi-Fi 或插上校园网网线。此时可以没有互联网。
3. 双击 `校园网助手.cmd`，首次填写自己的校园网账号密码。
4. 以后双击即可尝试连接；需要更换账号时，按住 **Shift** 双击并保持片刻，直到账号设置窗口出现。

连接期间请等待结果窗口。脚本会启动独立的后台 Edge、加载原登录页面、填写账号密码、点击网页按钮，并检查认证结果及互联网是否可访问。它不会选择 Wi-Fi。

## 账号保存在什么地方

账号文件保存在每个人自己电脑的：

```text
%LOCALAPPDATA%\CampusLogin-11117200130\credential.xml
```

密码使用 Windows 当前用户的 DPAPI 加密；账号名称不是加密的。当前用户身份下运行的程序仍可能读取密码。脚本文件不会因使用而写入个人账号，转发 `校园网助手.cmd` 不会带上自己的凭据。删除 `credential.xml` 可清除本工具保存的账号。

本程序不读取日常 Edge 配置中保存的密码；登录使用校园网页本来的 HTTP 认证方式。检测联网时会向微软的网络连通性检测地址发送请求，不会向该地址发送账号密码。

## 连接失败时

先确认同一账号能在原网页登录。再按住 Shift 双击程序，重新填写账号密码。

最近一次诊断记录位于：

```text
%LOCALAPPDATA%\CampusLogin-11117200130\diagnostic.txt
```

按 Win+R 输入上面的路径即可打开。记录包含流程阶段、校园服务器响应状态及可识别的错误消息；不记录请求参数、请求体或页面全文，消息中的本次账号密码会被隐藏。分享诊断前仍请自行检查内容，**不要上传 `credential.xml` 或整个个人配置目录**。

## 项目结构与构建

```text
校园网助手.cmd             普通使用者下载的单文件程序
src/CampusLogin.ps1         PowerShell 登录流程与本机账号管理
src/PortalAutomation.js     网页表单识别与填写辅助程序
scripts/Build.ps1           生成并核对单文件程序
README.md                  使用说明
.gitignore                 忽略个人运行数据及临时文件
.gitattributes             文件编码对应的换行处理规则
```

在项目文件夹中打开 Windows PowerShell，执行：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\Build.ps1
```

修改源码后重新构建，再同时提交源码和生成的 CMD。核对命令如下；该检查不读取账号、不打开浏览器、不访问网络：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\Build.ps1 -Check
```

CMD 中的 Base64 用于将 PowerShell 和 JavaScript 放在一个文件内，**不是密码加密，也不是隐藏源码**。可读源代码保留在 `src` 中，构建结果可以本地核对。

## 版本和验证范围

当前版本为 1.1，基于已反馈可用的 Edge 登录方案，补充真实输入事件、网页内嵌错误提示及认证接口 JSON 消息识别。

已在 Windows Edge 与本机模拟登录页上验证完整成功流程、特殊字符密码、需真实输入事件的表单、登录拒绝及错误提示识别。部分用户的实际认证失败原因尚待确认，不能保证所有账号或所有页面版本都能登录。网页结构或学校认证规则变化后，可能需要调整源码。
