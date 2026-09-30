#!/bin/bash

# ArkOS4Clone 设备端升级脚本(累积式) - 提交到 lcdyk0517/arkos4clone-updates 仓库的 update_files/ 目录
# 维护方式: pack_update.sh 打包时从仓库复制本文件, 把新日期块追加到最后,
#           重写 UPDATE_DATE 并重新生成文末收尾段; 测试通过后替换回仓库提交。
# 手工新增日期块也可以, 只要保持"块在收尾标记之前"的结构即可。
# 设备端约定: 每个日期块应用成功后在 /home/ark/.update/ 下touch .<日期> 标记;
#             成功走完收尾段 exit 187, 中途失败 exit 1 (错误弹窗只弹一次)。

UPDATE_DATE=""
MODDER="kk&lcdyk"   # 开机画面标题署名, 与制版脚本一致: 系统名 (日期)(MODDER)
LOG_FILE="/home/ark/esupdate.log"
LOCATION="https://raw.githubusercontent.com/lcdyk0517/arkos4clone-updates/master/update_files"
TMP_DIR="/home/ark/.update_tmp"

# ---- 升级包是 zip, 设备必须有 unzip ----
if ! command -v unzip >/dev/null 2>&1; then
  sudo msgbox "unzip was not found on this system.  The update packages are zip archives and need unzip installed.  Update aborted."
  exit 1
fi

UPDATE_DONE="/home/ark/.update/.${UPDATE_DATE}"

# ---- 没有可用更新(从未打包过, 或设备已是最新) ----
if [ -z "$UPDATE_DATE" ] || [ -f "$UPDATE_DONE" ]; then
  sudo msgbox "No more updates available.  Check back later."
  rm -f -- "$0"
  exit 187
fi

# ---- 识别系统类型, 决定要同步的文件夹和顺序 ----
# dArkOS4Clone: 只同步 dArkOS 文件夹
# ArkOS4Clone:  先同步 dArkOS 文件夹, 再同步 ArkOS 文件夹
SYSTEM_TYPE="$(/usr/local/bin/console_detect -V 2>/dev/null | tr -d '[:space:]')"
case "$SYSTEM_TYPE" in
  ArkOS4Clone)  SYNC_FOLDERS="dArkOS ArkOS" ;;
  dArkOS4Clone) SYNC_FOLDERS="dArkOS" ;;
  *)
    sudo msgbox "console_detect -V did not report ArkOS4Clone or dArkOS4Clone (got: ${SYSTEM_TYPE:-nothing}).  Update aborted."
    exit 1
    ;;
esac

rm -f "$LOG_FILE"
touch "$LOG_FILE"
rm -rf "$TMP_DIR"
mkdir -p "$TMP_DIR"

# ==== 升级块从这个注释行之后追加 ====



# ==== ARKOS4CLONE_PACKER_FOOTER (打包时自动重写, 请勿手工编辑这一段) ====

echo "$UPDATE_DATE" > /home/ark/.config/.VERSION
if [ -f /usr/share/plymouth/themes/text.plymouth ]; then
  sudo sed -i "/title\=/c\title=${SYSTEM_TYPE} (${UPDATE_DATE})(${MODDER})" /usr/share/plymouth/themes/text.plymouth
fi
sudo rm -rf "$TMP_DIR"
rm -f -- "$0"

msgbox "${SYSTEM_TYPE} updates applied through ${UPDATE_DATE}.  The system will now restart."
sudo reboot
exit 187
