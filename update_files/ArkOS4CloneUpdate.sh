#!/bin/bash

# ArkOS4Clone 设备端升级脚本(累积式) - 提交到 lcdyk0517/arkos4clone-updates 仓库的 update_files/ 目录
# 维护方式: pack_update.sh 打包时从仓库复制本文件, 把新日期块追加到最后,
#           重写 UPDATE_DATE 并重新生成文末收尾段; 测试通过后替换回仓库提交。
# 手工新增日期块也可以, 只要保持"块在收尾标记之前"的结构即可。
# 设备端约定: 每个日期块应用成功后在 /home/ark/.update/ 下touch .<日期> 标记;
#             成功走完收尾段 exit 187, 中途失败 exit 1 (错误弹窗只弹一次)。

UPDATE_DATE="20261005"
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




# ================= UPDATE BLOCK: 20261005 =================
if [ ! -f "/home/ark/.update/.20261005" ]; then
  printf "\nApplying update 20261005..." | tee -a "$LOG_FILE"
  rm -rf "$TMP_DIR"
  mkdir -p "$TMP_DIR"
  BLOCK_ZIP="ArkOS4CloneUpdate-20261005.zip"
  VOL_COUNT="1"

  # 分卷目录: /roms/update/<日期> 优先(和离线包一致), 其次 /roms2/update/<日期>, 都没有就定 /roms/update/<日期>
  SRC_DIR=""
  for d in /roms/update /roms2/update; do
    if [ -s "$d/20261005/$BLOCK_ZIP.001" ]; then
      SRC_DIR="$d"
      break
    fi
  done
  [ -n "$SRC_DIR" ] || SRC_DIR="/roms/update"
  mkdir -p "$SRC_DIR/20261005"

  # 逐卷检查, 缺哪卷下载哪卷, 一律补到 $SRC_DIR/20261005
  i=1
  while [ $i -le $VOL_COUNT ]; do
    VOL="$(printf '%s.%03d' "$BLOCK_ZIP" "$i")"
    if [ ! -s "$SRC_DIR/20261005/$VOL" ]; then
      printf "\nDownloading ${VOL}..." | tee -a "$LOG_FILE"
      wget -t 3 -T 60 --no-check-certificate "$LOCATION/20261005/$VOL" -O "$SRC_DIR/20261005/$VOL" -a "$LOG_FILE"
      if [ $? -ne 0 ] || [ ! -s "$SRC_DIR/20261005/$VOL" ]; then
        sudo rm -f "$SRC_DIR/20261005/$VOL"
        sudo msgbox "Could not download ${VOL}.  Check your wifi and internet connection and try again.  You can also manually place all the .zip.00x volumes in /roms/update/20261005 and retry."
        exit 1
      fi
    fi
    i=$((i + 1))
  done

  # 把分卷按顺序拼回完整 zip (存到临时目录, 不占 /roms 的空间)
  i=1
  while [ $i -le $VOL_COUNT ]; do
    VOL="$(printf '%s.%03d' "$BLOCK_ZIP" "$i")"
    cat "$SRC_DIR/20261005/$VOL" >> "$TMP_DIR/full.zip"
    i=$((i + 1))
  done

  # 拼合结果先校验完整性
  unzip -t -qq "$TMP_DIR/full.zip" >> "$LOG_FILE" 2>&1
  if [ $? -gt 1 ]; then
    sudo rm -rf "$TMP_DIR"
    sudo msgbox "Package ${BLOCK_ZIP} failed the integrity check after joining volumes.  Update aborted, please retry."
    exit 1
  fi

  # 按当前系统定义的顺序逐个文件夹解压并同步
  # (dArkOS4Clone: 仅 dArkOS; ArkOS4Clone: 先 dArkOS 后 ArkOS)
  for FOLDER in $SYNC_FOLDERS; do
    # 先建目录: 该文件夹本次可能没有文件(空文件夹合法), unzip 会报 11(no match), 放行
    mkdir -p "$TMP_DIR/$FOLDER"
    unzip -X -o "$TMP_DIR/full.zip" "${FOLDER}/*" -d "$TMP_DIR" >> "$LOG_FILE" 2>&1
    UNZIP_RC=$?
    if [ $UNZIP_RC -gt 1 ] && [ $UNZIP_RC -ne 11 ]; then
      sudo rm -rf "$TMP_DIR"
      sudo msgbox "Package ${BLOCK_ZIP} is invalid: the ${FOLDER} folder is missing or corrupted.  Update aborted."
      exit 1
    fi

    # 同步到系统: 全部 ark:ark + 777
    sudo chown -R ark:ark "$TMP_DIR/$FOLDER"
    sudo chmod -R 777 "$TMP_DIR/$FOLDER"
    if ! sudo cp -af "$TMP_DIR/$FOLDER/." /; then
      sudo rm -rf "$TMP_DIR"
      sudo msgbox "Failed copying the ${FOLDER} folder of update 20261005 to the system.  Update aborted, please try again."
      exit 1
    fi
  done
  sync

  # 包里带 uboot 时, 按 Rockchip 标准偏移写入引导盘 (烧完删掉, 不拷进根文件系统)
  unzip -X -o "$TMP_DIR/full.zip" "uboot/*" -d "$TMP_DIR" >> "$LOG_FILE" 2>&1
  if [ -d "$TMP_DIR/uboot" ] && ls "$TMP_DIR/uboot"/*.img >/dev/null 2>&1; then
    ROOT_PART="$(df / 2>/dev/null | tail -n 1 | awk '{print $1}')"
    DISK=""
    case "$ROOT_PART" in
      /dev/mmcblk*p[0-9]) DISK="${ROOT_PART%p[0-9]}" ;;
      /dev/mmcblk[0-9])   DISK="$ROOT_PART" ;;
      /dev/sd[a-z][0-9]*) DISK="$(printf '%s' "$ROOT_PART" | sed 's/[0-9]*$//')" ;;
    esac
    if [ -n "$DISK" ] && [ -b "$DISK" ]; then
      FLASH_FAIL=0
      for MEMBER in idbloader.img:64 uboot.img:16384 trust.img:24576; do
        UB_F="${MEMBER%%:*}"
        UB_SEEK="${MEMBER##*:}"
        if [ -f "$TMP_DIR/uboot/$UB_F" ]; then
          printf "\nFlashing uboot/$UB_F to $DISK (seek=$UB_SEEK)..." | tee -a "$LOG_FILE"
          sudo dd if="$TMP_DIR/uboot/$UB_F" of="$DISK" conv=notrunc bs=512 seek="$UB_SEEK" >> "$LOG_FILE" 2>&1
          if [ $? -ne 0 ]; then
            FLASH_FAIL=1
            break
          fi
        fi
      done
      if [ "$FLASH_FAIL" -ne 0 ]; then
        sudo rm -rf "$TMP_DIR"
        sudo msgbox "Flashing uboot failed.  The system may not boot until uboot is flashed again.  Do NOT reboot if avoidable, and retry the update or flash uboot manually."
        exit 1
      fi
      sync
      printf "\nuboot flashed successfully." | tee -a "$LOG_FILE"
    else
      printf "\nSkipping uboot flash (boot disk not found from root mount: ${ROOT_PART:-none})." | tee -a "$LOG_FILE"
    fi
    # 顺带清掉设备上历史遗留的 /home/ark/uboot 文件夹
    sudo rm -rf /home/ark/uboot
  fi
  rm -rf "$TMP_DIR/uboot"

  sudo rm -rf "$TMP_DIR"
  mkdir -p /home/ark/.update
  touch "/home/ark/.update/.20261005"
  printf "\nUpdate 20261005 applied." | tee -a "$LOG_FILE"
fi
# ==== ARKOS4CLONE_PACKER_FOOTER (打包时自动重写, 请勿手工编辑这一段) ====

echo "$UPDATE_DATE" > /home/ark/.config/.VERSION
if [ -f /usr/share/plymouth/themes/text.plymouth ]; then
  sudo sed -i "/title\=/c\title=${SYSTEM_TYPE} (${UPDATE_DATE})(${MODDER})" /usr/share/plymouth/themes/text.plymouth
fi
sudo rm -rf "$TMP_DIR"
restore_screen
printf "\033c" >> /dev/tty1 2>/dev/null
rm -f -- "$0"

msgbox "${SYSTEM_TYPE} updates applied through ${UPDATE_DATE}.  The system will now restart."
sudo reboot
exit 187
