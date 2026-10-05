#!/bin/bash
# pack_update.sh - arkos4clone 更新包打包脚本(累积式, zip 分卷)
#
# 用法: ./pack_update.sh [payload目录] [repo目录]
#   payload 目录默认 ./payload, repo 目录默认 . (本工作区就是 arkos4clone-updates 仓库)
#   环境变量 PACK_DATE=YYYYMMDD 可覆盖日期(补打历史包时用), 默认取今天
#
# 每次打包:
#   1. 从 repo 的 update_files/ 复制 ArkOS4CloneUpdate.sh (包含之前所有日期块)
#   2. 截掉旧的收尾段, 把新日期的升级块追加到最后, 重新生成收尾段
#   3. payload 打成 zip 后按 45MB 切成 ArkOS4CloneUpdate-<日期>.zip.001 .002 ...
#      (每块都小于 GitHub 50MB 单文件上限; 设备端用 cat 拼回完整 zip 再 unzip)
# 产出在 dist/ (不提交): 脚本在 dist 根(它不属于任何日期, 控制所有升级包), 分卷在 dist/<日期>/
# 本地测试通过后, 脚本挪进 update_files/, 分卷挪进 update_files/<日期>/, 再提交推送
#
# payload 目录结构(升级内容按目标系统分文件夹):
#   payload/ArkOS/   <- ArkOS4Clone 机型收到的文件(按根目录相对路径存放)
#   payload/dArkOS/  <- dArkOS4Clone 机型收到的文件

set -euo pipefail

PAYLOAD_DIR="${1:-payload}"
REPO_DIR="${2:-.}"
DATE="${PACK_DATE:-$(date +%Y%m%d)}"
DIST_DIR="dist"
ZIP_NAME="ArkOS4CloneUpdate-${DATE}.zip"
SCRIPT_NAME="ArkOS4CloneUpdate.sh"
UPDATE_FILES_DIR="update_files"
FOOTER_MARK='^# ==== ARKOS4CLONE_PACKER_FOOTER'
MAX_BYTES=$((50 * 1000 * 1000))   # GitHub raw 单文件上限

command -v zip >/dev/null 2>&1 || { echo "错误: 缺少 zip 命令 (apt install zip)"; exit 1; }
command -v unzip >/dev/null 2>&1 || { echo "错误: 缺少 unzip 命令 (apt install unzip)"; exit 1; }
command -v split >/dev/null 2>&1 || { echo "错误: 缺少 split 命令 (coreutils)"; exit 1; }
[[ "$DATE" =~ ^[0-9]{8}$ ]] || { echo "错误: PACK_DATE 必须是 8 位日期, 如 20260930"; exit 1; }

# ---- 检查 payload ----
if [ ! -d "$PAYLOAD_DIR/ArkOS" ] || [ ! -d "$PAYLOAD_DIR/dArkOS" ]; then
  echo "错误: $PAYLOAD_DIR 下必须同时存在 ArkOS/ 和 dArkOS/ 两个文件夹"
  exit 1
fi
if [ -z "$(find "$PAYLOAD_DIR/ArkOS" -type f -print -quit)" ]; then
  if [ -z "$(find "$PAYLOAD_DIR/dArkOS" -type f -print -quit)" ]; then
    echo "错误: ArkOS/ 和 dArkOS/ 都是空的, 至少一个要有内容"
    exit 1
  fi
  echo "警告: payload/ArkOS 本次没有文件(该系统只会收到 uboot 更新, 如有)"
fi
if [ -z "$(find "$PAYLOAD_DIR/dArkOS" -type f -print -quit)" ]; then
  echo "警告: payload/dArkOS 本次没有文件(该系统只会收到 uboot 更新, 如有)"
fi

# ---- 检查 repo 里的升级脚本 (在 update_files/ 下) ----
REPO_SCRIPT="$REPO_DIR/$UPDATE_FILES_DIR/$SCRIPT_NAME"
if [ ! -f "$REPO_SCRIPT" ]; then
  echo "错误: $REPO_SCRIPT 不存在。默认从当前目录的 update_files/ 读取, 也可用第二个参数指定仓库目录"
  exit 1
fi
if ! grep -q '^UPDATE_DATE=' "$REPO_SCRIPT"; then
  echo "错误: $REPO_SCRIPT 里找不到 UPDATE_DATE= 行, 不是打包器认识的脚本"
  exit 1
fi
if grep -q "ArkOS4CloneUpdate-${DATE}.zip" "$REPO_SCRIPT"; then
  echo "错误: update_files 里的脚本已包含 ${DATE} 的升级块。如需重打请先换日期, 或手工处理该块"
  exit 1
fi
[ "$(grep -c "$FOOTER_MARK" "$REPO_SCRIPT" || true)" -le 1 ] || {
  echo "错误: $REPO_SCRIPT 里收尾标记出现了多次, 请手工检查"
  exit 1
}

# ---- 防止上次打包没回写 update_files, 导致日期块从链上丢失 ----
# 升级脚本不属于任何日期(它控制所有日期的包), 固定放在 dist 根下; 分卷才按日期分文件夹
DIST_SCRIPT="$DIST_DIR/$SCRIPT_NAME"
DIST_DATE=""
if [ -f "$DIST_SCRIPT" ]; then
  DIST_DATE="$(sed -n 's/^UPDATE_DATE="*\([0-9]\{8\}\)"*/\1/p' "$DIST_SCRIPT" | head -n1)"
fi
REPO_DATE="$(sed -n 's/^UPDATE_DATE="*\([0-9]\{8\}\)"*/\1/p' "$REPO_SCRIPT" | head -n1)"
if [ -n "$DIST_DATE" ] && [ "${REPO_DATE:-00000000}" -lt "$DIST_DATE" ]; then
  echo "错误: dist/$SCRIPT_NAME 是未回写的升级脚本(日期 $DIST_DATE), 比 update_files 里的(${REPO_DATE:-无})新,"
  echo "  直接打包会丢掉那个日期块。"
  echo "  请先测试并把它挪进 $REPO_DIR/$UPDATE_FILES_DIR/, 分卷挪进 $UPDATE_FILES_DIR/$DIST_DATE/ 再打包;"
  echo "  确认放弃上次产物则执行: rm $DIST_SCRIPT"
  exit 1
fi

# ---- 打 zip 并切分卷 (脚本放 dist 根, 分卷放 dist/<日期>/) ----
DIST_ABS="$(cd "$DIST_DIR" && pwd)"
OUT_DIR="$DIST_ABS/$DATE"
mkdir -p "$OUT_DIR"
rm -f "$OUT_DIR/$ZIP_NAME" "$OUT_DIR/$ZIP_NAME".[0-9][0-9][0-9]

echo "==> 打包 $ZIP_NAME ..."
# 可选的 uboot 共享文件夹: 顶层允许 ArkOS、dArkOS 和 uboot; 排除 Windows 下载残留
(cd "$PAYLOAD_DIR" && zip -r -X -q "$OUT_DIR/$ZIP_NAME" ArkOS dArkOS uboot -x "*:Zone.Identifier")

# 校验完整 zip 顶层只有 ArkOS 和 dArkOS, 可选 uboot
TOP_ENTRIES="$(unzip -Z1 "$OUT_DIR/$ZIP_NAME" | sed '/^$/d' | cut -d/ -f1 | sort -u | paste -sd, -)"
case "$TOP_ENTRIES" in
  "ArkOS,dArkOS"|"ArkOS,dArkOS,uboot") ;;
  *)
    echo "错误: 压缩包顶层内容异常: $TOP_ENTRIES (应只有 ArkOS、dArkOS, 可选 uboot)"
    exit 1
    ;;
esac

FULL_BYTES="$(stat -c %s "$OUT_DIR/$ZIP_NAME")"
ZIP_MB="$(( FULL_BYTES / 1048576 )).$(( (FULL_BYTES % 1048576) * 10 / 1048576 ))"
echo "==> 切分卷 (每块 45MB)..."
split -b 45M --numeric-suffixes=1 -a 3 "$OUT_DIR/$ZIP_NAME" "$OUT_DIR/$ZIP_NAME."
rm -f "$OUT_DIR/$ZIP_NAME"

CHUNKS=("$OUT_DIR/$ZIP_NAME".[0-9][0-9][0-9])
SCRIPT_OUT="$DIST_ABS/$SCRIPT_NAME"
VOL_COUNT="${#CHUNKS[@]}"
[ -s "${CHUNKS[0]}" ] || { echo "错误: 分卷生成失败"; exit 1; }
if [ "$VOL_COUNT" -gt 999 ]; then
  echo "错误: 分卷超过 999 块, 请减小 payload"; exit 1
fi
for c in "${CHUNKS[@]}"; do
  CB="$(stat -c %s "$c")"
  if [ "$CB" -ge "$MAX_BYTES" ]; then
    echo "错误: $(basename "$c") $(printf '%d' "$CB") 字节, 超过 GitHub 50MB 上限"
    exit 1
  fi
done

# ---- 生成累积式升级脚本: repo脚本(截掉收尾) + 新日期块 + 新收尾 ----
echo "==> 生成 $SCRIPT_NAME (追加 ${DATE} 升级块, ${VOL_COUNT} 个分卷)..."
{
  # 头部 + 已有全部日期块(截掉旧收尾段), 并把 UPDATE_DATE 换成本次日期
  sed -e "/$FOOTER_MARK/,\$d" -e "s/^UPDATE_DATE=.*/UPDATE_DATE=\"${DATE}\"/" "$REPO_SCRIPT"

  # 本次日期块 (VOL_COUNT 由打包器按实际分卷数写入)
  cat <<BLOCK

# ================= UPDATE BLOCK: ${DATE} =================
if [ ! -f "/home/ark/.update/.${DATE}" ]; then
  printf "\nApplying update ${DATE}..." | tee -a "\$LOG_FILE"
  rm -rf "\$TMP_DIR"
  mkdir -p "\$TMP_DIR"
  BLOCK_ZIP="ArkOS4CloneUpdate-${DATE}.zip"
  VOL_COUNT="${VOL_COUNT}"

  # 分卷目录: /roms/update/<日期> 优先(和离线包一致), 其次 /roms2/update/<日期>, 都没有就定 /roms/update/<日期>
  SRC_DIR=""
  for d in /roms/update /roms2/update; do
    if [ -s "\$d/${DATE}/\$BLOCK_ZIP.001" ]; then
      SRC_DIR="\$d"
      break
    fi
  done
  [ -n "\$SRC_DIR" ] || SRC_DIR="/roms/update"
  mkdir -p "\$SRC_DIR/${DATE}"

  # 逐卷检查, 缺哪卷下载哪卷, 一律补到 \$SRC_DIR/${DATE}
  i=1
  while [ \$i -le \$VOL_COUNT ]; do
    VOL="\$(printf '%s.%03d' "\$BLOCK_ZIP" "\$i")"
    if [ ! -s "\$SRC_DIR/${DATE}/\$VOL" ]; then
      printf "\nDownloading \${VOL}..." | tee -a "\$LOG_FILE"
      wget -t 3 -T 60 --no-check-certificate "\$LOCATION/${DATE}/\$VOL" -O "\$SRC_DIR/${DATE}/\$VOL" -a "\$LOG_FILE"
      if [ \$? -ne 0 ] || [ ! -s "\$SRC_DIR/${DATE}/\$VOL" ]; then
        sudo rm -f "\$SRC_DIR/${DATE}/\$VOL"
        sudo msgbox "Could not download \${VOL}.  Check your wifi and internet connection and try again.  You can also manually place all the .zip.00x volumes in /roms/update/${DATE} and retry."
        exit 1
      fi
    fi
    i=\$((i + 1))
  done

  # 把分卷按顺序拼回完整 zip (存到临时目录, 不占 /roms 的空间)
  i=1
  while [ \$i -le \$VOL_COUNT ]; do
    VOL="\$(printf '%s.%03d' "\$BLOCK_ZIP" "\$i")"
    cat "\$SRC_DIR/${DATE}/\$VOL" >> "\$TMP_DIR/full.zip"
    i=\$((i + 1))
  done

  # 拼合结果先校验完整性
  unzip -t -qq "\$TMP_DIR/full.zip" >> "\$LOG_FILE" 2>&1
  if [ \$? -gt 1 ]; then
    sudo rm -rf "\$TMP_DIR"
    sudo msgbox "Package \${BLOCK_ZIP} failed the integrity check after joining volumes.  Update aborted, please retry."
    exit 1
  fi

  # 按当前系统定义的顺序逐个文件夹解压并同步
  # (dArkOS4Clone: 仅 dArkOS; ArkOS4Clone: 先 dArkOS 后 ArkOS)
  for FOLDER in \$SYNC_FOLDERS; do
    # 先建目录: 该文件夹本次可能没有文件(空文件夹合法), unzip 会报 11(no match), 放行
    mkdir -p "\$TMP_DIR/\$FOLDER"
    unzip -X -o "\$TMP_DIR/full.zip" "\${FOLDER}/*" -d "\$TMP_DIR" >> "\$LOG_FILE" 2>&1
    UNZIP_RC=\$?
    if [ \$UNZIP_RC -gt 1 ] && [ \$UNZIP_RC -ne 11 ]; then
      sudo rm -rf "\$TMP_DIR"
      sudo msgbox "Package \${BLOCK_ZIP} is invalid: the \${FOLDER} folder is missing or corrupted.  Update aborted."
      exit 1
    fi

    # 同步到系统: 全部 ark:ark + 777
    sudo chown -R ark:ark "\$TMP_DIR/\$FOLDER"
    sudo chmod -R 777 "\$TMP_DIR/\$FOLDER"
    if ! sudo cp -af "\$TMP_DIR/\$FOLDER/." /; then
      sudo rm -rf "\$TMP_DIR"
      sudo msgbox "Failed copying the \${FOLDER} folder of update ${DATE} to the system.  Update aborted, please try again."
      exit 1
    fi
  done
  sync

  # 包里带 uboot 时, 按 Rockchip 标准偏移写入引导盘 (烧完删掉, 不拷进根文件系统)
  unzip -X -o "\$TMP_DIR/full.zip" "uboot/*" -d "\$TMP_DIR" >> "\$LOG_FILE" 2>&1
  if [ -d "\$TMP_DIR/uboot" ] && ls "\$TMP_DIR/uboot"/*.img >/dev/null 2>&1; then
    ROOT_PART="\$(df / 2>/dev/null | tail -n 1 | awk '{print \$1}')"
    DISK=""
    case "\$ROOT_PART" in
      /dev/mmcblk*p[0-9]) DISK="\${ROOT_PART%p[0-9]}" ;;
      /dev/mmcblk[0-9])   DISK="\$ROOT_PART" ;;
      /dev/sd[a-z][0-9]*) DISK="\$(printf '%s' "\$ROOT_PART" | sed 's/[0-9]*\$//')" ;;
    esac
    if [ -n "\$DISK" ] && [ -b "\$DISK" ]; then
      FLASH_FAIL=0
      for MEMBER in idbloader.img:64 uboot.img:16384 trust.img:24576; do
        UB_F="\${MEMBER%%:*}"
        UB_SEEK="\${MEMBER##*:}"
        if [ -f "\$TMP_DIR/uboot/\$UB_F" ]; then
          printf "\nFlashing uboot/\$UB_F to \$DISK (seek=\$UB_SEEK)..." | tee -a "\$LOG_FILE"
          sudo dd if="\$TMP_DIR/uboot/\$UB_F" of="\$DISK" conv=notrunc bs=512 seek="\$UB_SEEK" >> "\$LOG_FILE" 2>&1
          if [ \$? -ne 0 ]; then
            FLASH_FAIL=1
            break
          fi
        fi
      done
      if [ "\$FLASH_FAIL" -ne 0 ]; then
        sudo rm -rf "\$TMP_DIR"
        sudo msgbox "Flashing uboot failed.  The system may not boot until uboot is flashed again.  Do NOT reboot if avoidable, and retry the update or flash uboot manually."
        exit 1
      fi
      sync
      printf "\nuboot flashed successfully." | tee -a "\$LOG_FILE"
    else
      printf "\nSkipping uboot flash (boot disk not found from root mount: \${ROOT_PART:-none})." | tee -a "\$LOG_FILE"
    fi
    # 顺带清掉设备上历史遗留的 /home/ark/uboot 文件夹
    sudo rm -rf /home/ark/uboot
  fi
  rm -rf "\$TMP_DIR/uboot"

  sudo rm -rf "\$TMP_DIR"
  mkdir -p /home/ark/.update
  touch "/home/ark/.update/.${DATE}"
  printf "\nUpdate ${DATE} applied." | tee -a "\$LOG_FILE"
fi
BLOCK

  # 收尾段(每次重新生成, 永远在所有块之后)
  cat <<FOOTER
# ==== ARKOS4CLONE_PACKER_FOOTER (打包时自动重写, 请勿手工编辑这一段) ====

echo "\$UPDATE_DATE" > /home/ark/.config/.VERSION
if [ -f /usr/share/plymouth/themes/text.plymouth ]; then
  sudo sed -i "/title\=/c\title=\${SYSTEM_TYPE} (\${UPDATE_DATE})(\${MODDER})" /usr/share/plymouth/themes/text.plymouth
fi
sudo rm -rf "\$TMP_DIR"
restore_screen
printf "\033c" >> /dev/tty1 2>/dev/null
rm -f -- "\$0"

msgbox "\${SYSTEM_TYPE} updates applied through \${UPDATE_DATE}.  The system will now restart."
sudo reboot
exit 187
FOOTER
} > "$SCRIPT_OUT"
chmod +x "$SCRIPT_OUT"
bash -n "$SCRIPT_OUT" || { echo "错误: 生成的脚本语法检查失败"; exit 1; }

TOTAL_MB=0
for c in "${CHUNKS[@]}"; do TOTAL_MB=$((TOTAL_MB + $(stat -c %s "$c") / 1048576)); done

echo
echo "打包完成 (${DATE}):"
echo "  $DIST_DIR/$SCRIPT_NAME      已追加 ${DATE} 块, UPDATE_DATE=$DATE, ${VOL_COUNT} 个分卷"
for c in "${CHUNKS[@]}"; do
  echo "  $(basename "$c")    $(stat -c %s "$c") 字节"
done
echo "  (完整 zip 约 ${ZIP_MB} MB, 分卷合计约 ${TOTAL_MB} MB, 在 $DIST_DIR/$DATE/ 下)"
echo
echo "下一步:"
echo "  1. 按设备上的实际位置测试 dist/$SCRIPT_NAME 与各分卷"
echo "     (离线测试可把脚本和全部分卷放到设备的 /roms/update 里)"
echo "  2. 测试通过后挪进仓库的 $UPDATE_FILES_DIR/ 并推送 (dist/ 本身不提交, 分卷放日期文件夹):"
echo "     cp $DIST_DIR/$SCRIPT_NAME $REPO_DIR/$UPDATE_FILES_DIR/"
echo "     mkdir -p $REPO_DIR/$UPDATE_FILES_DIR/$DATE"
echo "     cp $DIST_DIR/$DATE/$ZIP_NAME.* $REPO_DIR/$UPDATE_FILES_DIR/$DATE/"
echo "     cd $REPO_DIR && git add $UPDATE_FILES_DIR && git commit -m \"update $DATE\" && git push"
