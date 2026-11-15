# desktop-control-kit

讓 Claude Code 在 Windows 上操作桌面應用程式的外掛：先用 **agent-desktop**（快、不靠截圖），不行再換 **Orca**。

## 內容

| 檔案 | 作用 |
|---|---|
| `plugins/desktop-control/skills/driving-desktop-apps/` | 教 Claude 什麼時候用哪個工具，以及實測踩過的坑 |
| `plugins/desktop-control/skills/setup/` | `/desktop-control:setup`：檢查並安裝兩個工具 |
| `plugins/desktop-control/scripts/setup.ps1` | 實際做檢查和安裝的腳本 |

## 在另一台電腦上安裝

需求：Windows 10 1809 以上、已安裝 Claude Code 和 Node.js。

1. 這是私人 repo，所以那台電腦要先登入 GitHub（已登入可跳過）：
   ```
   gh auth login
   ```
2. 在 Claude Code 裡加入這個 repo 並安裝外掛：
   ```
   /plugin marketplace add Ta30678/desktop-control-kit
   /plugin install desktop-control@desktop-control-kit
   ```
   不想用 GitHub 的話，也可以把整個資料夾複製過去，把第一行換成資料夾路徑：
   `/plugin marketplace add C:\放置的路徑\desktop-control-kit`
3. 執行設定：
   ```
   /desktop-control:setup
   ```
   Claude 會先檢查，告訴你缺什麼，確認後才安裝。

也可以不透過 Claude，直接執行腳本：

```powershell
# 只檢查，不改任何東西
powershell -NoProfile -ExecutionPolicy Bypass -File .\plugins\desktop-control\scripts\setup.ps1 -Check
# 安裝
powershell -NoProfile -ExecutionPolicy Bypass -File .\plugins\desktop-control\scripts\setup.ps1
# 只裝 agent-desktop，不裝 Orca
powershell -NoProfile -ExecutionPolicy Bypass -File .\plugins\desktop-control\scripts\setup.ps1 -SkipOrca
```

之後更新外掛：`/plugin marketplace update desktop-control-kit`。

## 安裝腳本會做的事

全部都在使用者層級，不需要系統管理員權限：

1. `npm install -g agent-desktop`
2. 從 Orca 的 GitHub releases 下載 Windows 安裝檔（約 215 MB），確認數位簽章有效且簽署者是 SignPath Foundation 後，才靜默安裝
3. 啟動 Orca app，等它的 runtime 就緒
4. 安裝 Orca 的 `orca-cli` 和 `orchestration` 技能
5. 把 `%LOCALAPPDATA%\Programs\orca\resources\bin` 加進使用者 PATH

## 需要自己做的事

- 登入 Claude（在 Orca app 裡，或在終端機執行一次 `claude`）
- 想混用 Codex 的話：`codex login --device-auth`
- 想用手機監看的話：在 Orca 側邊欄的「Orca Mobile」配對

## 要知道的事

- Orca 第一次啟動時，會自己在 `~/.claude/settings.json` 加入狀態 hook，也可能改掉 Claude Code 的主題。`orca agent hooks off` 可以移除 hook。
- Orca 啟動的 agent 預設是 bypass permissions 模式，執行指令不會先詢問。
- Orca 設定頁的「Computer Use 技能」會顯示未安裝，這是刻意的：它會和 `driving-desktop-apps` 搶同一類任務。
- 技能裡的數字（速度、token）是在 Windows 11 25H2、agent-desktop 1.3.1、Orca 1.4.259 上量到的。
