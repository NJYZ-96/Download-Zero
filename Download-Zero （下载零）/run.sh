#!/bin/sh
# Download-Zero 核心运行脚本 (微信兼容版)

# --- 环境参数处理 ---
MIN_SLEEP_SECONDS=$(echo "${MIN_SLEEP_MINUTES:-10} * 60 / 1" | bc)
MAX_SLEEP_SECONDS=$(echo "${MAX_SLEEP_MINUTES:-30} * 60 / 1" | bc)
MIN_LOOP_BYTES=$(echo "${MIN_LOOP_GB:-1} * 1073741824 / 1" | bc)
MAX_LOOP_BYTES=$(echo "${MAX_LOOP_GB:-5} * 1073741824 / 1" | bc)
DAILY_LIMIT_BYTES=$(echo "${DAILY_LIMIT_GB:-150} * 1073741824 / 1" | bc)
SPEED_LIMIT_ARG=${SPEED_LIMIT:-"10M"}
FAIL_THRESHOLD=${FAIL_THRESHOLD:-3}
WEBHOOK_URL=${WECHAT_WEBHOOK:-""}

URL_LIST=$(echo "$URLS" | tr ',' '\n')
URL_COUNT=$(echo "$URL_LIST" | wc -l)

# --- 内部状态变量 ---
today=$(date +%Y-%m-%d)
daily_bytes_downloaded=0
daily_total_duration="0"
notified_today=false

SOURCE_STATS_DIR="/tmp/stats"
mkdir -p $SOURCE_STATS_DIR

init_stats() {
    for i in $(seq 1 $URL_COUNT); do
        echo "0" > "$SOURCE_STATS_DIR/bytes_$i"
        echo "0" > "$SOURCE_STATS_DIR/fails_$i"
        rm -f "$SOURCE_STATS_DIR/disabled_$i"
    done
}
init_stats

# --- 工具函数 ---

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1"
}

format_bytes() {
    val=$(echo "$1 / 1" | bc)
    if [ "$val" -ge 1073741824 ]; then
        printf "%.2f GB" $(echo "scale=2; $1 / 1073741824" | bc)
    elif [ "$val" -ge 1048576 ]; then
        printf "%.2f MB" $(echo "scale=2; $1 / 1048576" | bc)
    elif [ "$val" -ge 1024 ]; then
        printf "%.2f KB" $(echo "scale=2; $1 / 1024" | bc)
    else
        printf "%d Bytes" "$val"
    fi
}

# 时间人性化转换函数
format_time() {
    total_seconds=$(echo "$1 / 1" | bc)
    if [ "$total_seconds" -lt 60 ]; then
        echo "${total_seconds}秒"
    elif [ "$total_seconds" -lt 3600 ]; then
        m=$((total_seconds / 60))
        s=$((total_seconds % 60))
        echo "${m}分${s}秒"
    else
        h=$((total_seconds / 3600))
        m=$(((total_seconds % 3600) / 60))
        s=$((total_seconds % 60))
        echo "${h}小时${m}分${s}秒"
    fi
}

get_random() {
    awk -v min=$1 -v max=$2 'BEGIN{srand(); print int(min+rand()*(max-min+1))}'
}

send_wechat_notification() {
    if [ -z "$WEBHOOK_URL" ]; then return; fi
    
    source_summary=""
    disabled_list=""
    for i in $(seq 1 $URL_COUNT); do
        b=$(cat "$SOURCE_STATS_DIR/bytes_$i")
        source_summary="${source_summary}· 下载源${i}: $(format_bytes $b)\n"
        if [ -f "$SOURCE_STATS_DIR/disabled_$i" ]; then
            disabled_list="${disabled_list}${i} "
        fi
    done
    [ -z "$disabled_list" ] && disabled_list="无"

    if [ "$(echo "$daily_total_duration > 0" | bc)" -eq 1 ]; then
        avg_speed=$(echo "scale=2; $daily_bytes_downloaded / $daily_total_duration" | bc)
    else
        avg_speed=0
    fi
    
    # 构建纯文本内容，移除 Markdown 语法，改用简单的换行和符号
    # 注意：纯文本中 \n 需要在 JSON 中转义为 \\n
    msg_content="📊 Download-Zero 今日下载汇总\n\n今日总下载量: $(format_bytes $daily_bytes_downloaded)\n今日总耗时: $(format_time $daily_total_duration)\n今日平均速度: $(format_bytes $avg_speed)/s\n\n🌐 各下载源明细:\n${source_summary}\n⚠️ 失效源编号: ${disabled_list}"

    # 封装为 text 类型 JSON
    cat <<EOF > /tmp/wechat_payload.json
{
    "msgtype": "text",
    "text": {
        "content": "$msg_content"
    }
}
EOF

    curl -s -X POST "$WEBHOOK_URL" \
        -H 'Content-Type: application/json' \
        -d @/tmp/wechat_payload.json > /tmp/wechat_res.log
    
    log "已尝试发送企业微信纯文本通知。"
}

# --- 主逻辑 ---
log "=== Download-Zero 应用启动 ==="
log "配置: 每日上限 $(format_bytes $DAILY_LIMIT_BYTES), 速度限制 $SPEED_LIMIT_ARG"

current_source_idx=1

while true; do
    now=$(date +%Y-%m-%d)
    if [ "$now" != "$today" ]; then
        log "新的一天，重置统计数据。"
        today=$now
        daily_bytes_downloaded=0
        daily_total_duration="0"
        notified_today=false
        init_stats
    fi

    if [ "$(echo "$daily_bytes_downloaded >= $DAILY_LIMIT_BYTES" | bc)" -eq 1 ]; then
        if [ "$notified_today" = false ]; then
            send_wechat_notification
            notified_today=true
        fi
        log "已达到每日上限，等待中..."
        sleep 600
        continue
    fi

    loop_target=$(get_random $MIN_LOOP_BYTES $MAX_LOOP_BYTES)
    loop_downloaded=0
    loop_start=$(date +%s)
    log "--- 循环开始: 目标 $(format_bytes $loop_target) ---"

    while [ "$(echo "$loop_downloaded < $loop_target" | bc)" -eq 1 ]; do
        attempts=0
        while [ $attempts -lt $URL_COUNT ]; do
            if [ ! -f "$SOURCE_STATS_DIR/disabled_$current_source_idx" ]; then
                break
            fi
            current_source_idx=$(( (current_source_idx % URL_COUNT) + 1 ))
            attempts=$((attempts + 1))
        done

        if [ $attempts -eq $URL_COUNT ]; then
            log "所有下载源均不可用！等待一小时..."
            sleep 3600
            break
        fi

        url=$(echo "$URLS" | tr ',' '\n' | sed -n "${current_source_idx}p")
        remain=$(echo "$loop_target - $loop_downloaded" | bc)
        
        if [ "$(echo "$daily_bytes_downloaded + $remain > $DAILY_LIMIT_BYTES" | bc)" -eq 1 ]; then
            remain=$(echo "$DAILY_LIMIT_BYTES - $daily_bytes_downloaded" | bc)
        fi
        
        if [ "$(echo "$remain < 1024" | bc)" -eq 1 ]; then break; fi

        log "使用下载源${current_source_idx}，计划下载 $(format_bytes $remain)..."
        
        remain_int=$(echo "$remain / 1" | bc)
        stats=$(curl -sS -L --connect-timeout 10 -m 3600 \
            --limit-rate "$SPEED_LIMIT_ARG" \
            -w "%{size_download}:%{time_total}" \
            -r 0-$((remain_int - 1)) \
            "$url" -o /dev/null || echo "FAIL:0")

        sz=$(echo "$stats" | cut -d':' -f1)
        tm=$(echo "$stats" | cut -d':' -f2)

        if [ "$stats" = "FAIL:0" ] || [ "$sz" -eq 0 ]; then
            log "下载源${current_source_idx} 失败。"
            f_count=$(cat "$SOURCE_STATS_DIR/fails_$current_source_idx")
            f_count=$((f_count + 1))
            echo "$f_count" > "$SOURCE_STATS_DIR/fails_$current_source_idx"
            if [ "$f_count" -ge "$FAIL_THRESHOLD" ]; then
                log "下载源${current_source_idx} 连续失败 $f_count 次，已禁用。"
                touch "$SOURCE_STATS_DIR/disabled_$current_source_idx"
            fi
        else
            echo "0" > "$SOURCE_STATS_DIR/fails_$current_source_idx"
            loop_downloaded=$(echo "$loop_downloaded + $sz" | bc)
            daily_bytes_downloaded=$(echo "$daily_bytes_downloaded + $sz" | bc)
            daily_total_duration=$(echo "$daily_total_duration + $tm" | bc)
            
            old_b=$(cat "$SOURCE_STATS_DIR/bytes_$current_source_idx")
            echo "$(echo "$old_b + $sz" | bc)" > "$SOURCE_STATS_DIR/bytes_$current_source_idx"
            
            log "下载源${current_source_idx} 下载完成: $(format_bytes $sz)"
        fi

        current_source_idx=$(( (current_source_idx % URL_COUNT) + 1 ))
        if [ "$(echo "$daily_bytes_downloaded >= $DAILY_LIMIT_BYTES" | bc)" -eq 1 ]; then break; fi
    done

    loop_end=$(date +%s)
    loop_dur=$((loop_end - loop_start))
    [ $loop_dur -le 0 ] && loop_dur=1
    loop_spd=$(echo "scale=2; $loop_downloaded / $loop_dur" | bc)
    
    log "--- 循环结束统计 ---"
    log "本次用时: $(format_time $loop_dur), 下载量: $(format_bytes $loop_downloaded), 平均速度: $(format_bytes $loop_spd)/s"
    log "今日累计: $(format_bytes $daily_bytes_downloaded), 总耗时: $(format_time $daily_total_duration)"
    
    st=$(get_random $MIN_SLEEP_SECONDS $MAX_SLEEP_SECONDS)
    log "休息 $(format_time $st)..."
    sleep $st
done
