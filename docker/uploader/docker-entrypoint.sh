#!/bin/bash

REDIS_ADDR=${REDIS_ADDR?!redis address is not set...}
REDIS_PORT=${REDIS_PORT?-6379}
REDIS_DATABASE=${REDIS_DATABASE?-0}

# 定义发送微信消息的函数
send_wechat_message() {
    local content="$1"
    local timestamp=$(($(date +%s%N)/1000000))  # 生成13位毫秒级时间戳
    local id="${timestamp:0:13}"
    
    # 构造 JSON 请求体
    local json_body=$(jq -n \
        --arg id "$id" \
        --arg content "$content" \
        '{para: {
            id: $id,
            type: 555,
            roomid: "null",
            wxid: "wxid_xxxxxxxxxxxxxx",
            content: $content,
            nickname: "null",
            ext: "null"
        }}')
    
    # 发送请求
    curl -s -X POST "http://webhook_address" \
        -H "Content-Type: application/json; charset=utf-8" \
        -d "$json_body"
}

while true; do
    # 从 Redis 获取数据（保持阻塞）
    result=($(redis-cli -h $REDIS_ADDR -p $REDIS_PORT -n $REDIS_DATABASE BLPOP biliup:upload-list 0))
    
    # 检查是否获取到有效数据
    if [ -z "${result[1]}" ]; then
        echo "No value found in biliup:upload-list"
        continue
    fi
    
    json_str="${result[1]}"
    
    # 处理 JSON 数据
    filename=$(echo "$json_str" | jq -r .filename)
    bvid=$(echo "$json_str" | jq -r .bvid)
    
    # 存储处理中的任务（处理双引号转义）
    processed_str=$(echo "$json_str" | sed 's/"/\\"/g')
    redis-cli -h $REDIS_ADDR -p $REDIS_PORT -n $REDIS_DATABASE SET biliup:processing:uploading "$processed_str" > /dev/null
    
    # 执行上传命令
    biliup append -l qn --limit 6 --vid "$bvid" "$filename"
    
    # 发送微信通知
    # send_wechat_message "${filename} 上传完毕"
    
    # 清理处理中的任务
    redis-cli -h $REDIS_ADDR -p $REDIS_PORT -n $REDIS_DATABASE DEL biliup:processing:rendering > /dev/null
done