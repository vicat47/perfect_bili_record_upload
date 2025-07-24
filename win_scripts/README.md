# 命令
```shell
# 显卡硬件编码
ffmpeg -f concat -safe 0 -i .\day2.txt -c:v h264_nvenc -profile:v main -b:v 19000k -profile:v main -s 3840x2160 -c:a aac -b:a 320k -x264opts crf=12 -maxrate:v 24000k -bufsize 24000k -pix_fmt yuv420p day2.mp4

# 软件编码
ffmpeg -f concat -safe 0 -i .\day2.txt -c:v libx264 -profile:v main -b:v 19000k -profile:v main -preset veryslow -s 3840x2160 -c:a aac -b:a 320k -x264opts crf=12 -maxrate:v 24000k -bufsize 24000k -pix_fmt yuv420p day2.mp4

# 视频剪切
ffmpeg -ss xx:xx:xx -to xx:xx:xx -i .\day9.mp4 -c:v copy -c:a copy day9_p1.mp4

ffmpeg -i long.mp4 -acodec copy -vn -f segment -segment_time 3000 -segment_start_number 1 day28_%d.mp4
ffmpeg -i xxx.mp4 -c:v h264_nvenc -profile:v main -b:v 19000k -profile:v main -s 3840x2160 -c:a aac -b:a 320k -x264opts crf=12 -maxrate:v 24000k -bufsize 24000k -pix_fmt yuv420p -f segment -segment_time 3000 -segment_start_number 1 day28_%d.mp4
使用-reset_timestamps 1 设置每一个切片的时间戳都从0开始
segment_start_number number
Set the sequence number of the first segment. Defaults to 0.

# 视频追加
$APPEND_AVID=254353157
$OUT_DAY=36
$OUT_NAME="继续死磕女武神"
$INPUT_FILE="..\2022-04-10_21-18-44.mkv"
Start-Transcript -Append "day$OUT_DAY.log"; `
ffmpeg -i $INPUT_FILE -c:v h264_nvenc -profile:v main -b:v 19000k -profile:v main -s 3840x2160 -c:a aac -b:a 320k -x264opts crf=12 -maxrate:v 24000k -bufsize 24000k -pix_fmt yuv420p "..\day$OUT_DAY.mp4"; `
ffmpeg -i "..\day$OUT_DAY.mp4" -c:v copy -c:a copy -f segment -segment_time 3000 -segment_start_number 1 "day$OUT_DAY`_p%d$OUT_NAME.mp4"; `
@(Get-ChildItem -Recurse -Filter "day$OUT_DAY`_p*.mp4") | %{& .\biliup.exe append -l qn --limit 6 -a $APPEND_AVID $_}; `
Stop-Transcript; `
shutdown -s -t 0

sudo docker run --rm \
	--device /dev/dri:/dev/dri \
	-v /volume1/record/OBS:/record/obs \
	jrottenberg/ffmpeg:vaapi \
	-hwaccel vaapi -hwaccel_output_format vaapi \
	-i /record/obs/2022-04-11_21-39-12.mkv -c:v h264_vaapi -profile:v main -b:v 19000k -c:a aac -b:a 320k -maxrate:v 24000k -bufsize 24000k -pix_fmt yuv420p /record/obs/test.mp4
	
$APPEND_AVID=254353157
# 发送消息
function Send-WechatMessage {
	param (
        $Content
    )
    $BODY = @{
        para = @{
            id = (([DateTime]::Now.ToUniversalTime().Ticks - 621355968000000000)/10000).tostring().Substring(0,13)
            type = 555
            roomid = "null"
            # wxid = "xxxxxxxxxxxxxx@chatroom"
            wxid = "wxid_xxxxxxxxxxxxxxxxx"
            content = [System.Text.Encoding]::UTF8.GetString([System.Text.Encoding]::UTF8.GetBytes($Content))
            nickname = "null"
            ext = "null"
        }
    }
    Invoke-WebRequest -Uri "http://192.168.31.20:5555/api/getcontactlist" -Method Post -ContentType "application/json; charset=utf-8" -Body ($BODY | ConvertTo-Json)
}

# 转码视频
function Encode-BiliBiliVideo {
	param (
		$INPUT_FILE,
		$OUT_DAY,
		$OUT_NAME,
		$APPEND_AVID,
		[PSDefaultValue(Help = '1')]
		$SEGMENT_START_NUMBER = 1
	)
	$OUT_DAY_NAME = "day$OUT_DAY.mp4"
	if ( 1 -ne $SEGMENT_START_NUMBER ) {
		$OUT_DAY_NAME = "day$OUT_DAY`_$SEGMENT_START_NUMBER"
	}
	ffmpeg -i $INPUT_FILE -c:v h264_nvenc -profile:v main -b:v 19000k -profile:v main -s 3840x2160 -c:a aac -b:a 320k -x264opts crf=12 -maxrate:v 24000k -bufsize 24000k -pix_fmt yuv420p "..\$OUT_DAY_NAME"; `
    ffmpeg -i "..\$OUT_DAY_NAME" -c:v copy -c:a copy -f segment -segment_time 3000 -segment_start_number $SEGMENT_START_NUMBER "day$OUT_DAY`_p%d$OUT_NAME.mp4"; `
    Send-WechatMessage "$INPUT_FILE 转码完成"; `
#    ,@(Get-ChildItem -Recurse -Filter "day$OUT_DAY`_p*.mp4") | %{& .\biliup.exe append -l qn --limit 6 -a $APPEND_AVID $_}
#    Send-WechatMessage "第 $OUT_DAY 天 $OUT_NAME 上传完成"
}

# b站新的伪4k命令
ffmpeg -i .\2023-03-03_22-29-03.mkv -c:v libx264 -profile:v main -b:v 20000k -profile:v main -preset veryslow -s 2844x1600 -c:a aac -b:a 320k -x264opts crf=12 -maxrate:v 60000k -bufsize 60000k -pix_fmt yuv420p ./输出/057_就这？脚劲大又如何？踩不到不就被我白打！.mp4
ffmpeg -i .\2023-03-04_22-47-36.mkv -c:v libx264 -profile:v main -b:v 20000k -profile:v main -preset veryslow -s 2844x1600 -c:a aac -b:a 320k -x264opts crf=8 -maxrate:v 30000k -bufsize 30000k -pix_fmt yuv420p .\输出\058_火山摸剑，本以为百人斩已经是最难.mp4;


# 渲染端
while ($true) {
    $result = redis-cli -h 192.168.31.15 BLPOP render-list 5
    if ($result -eq "") {
        Write-Output "No value found in render-list"
        break
    }
    $value = $result[1]
    ffmpeg -i $value -c:v libx264 -profile:v main -b:v 20000k -profile:v main -preset veryslow -s 2844x1600 -c:a aac -b:a 320k -x264opts crf=12 -maxrate:v 60000k -bufsize 60000k -pix_fmt yuv420p "R:\OBS\输出\$($value)"
    Send-WechatMessage "$($value)渲染完毕"
    redis-cli -h 192.168.31.15 RPUSH upload-list $value
}

# 上传端
while ($true) {
    $result = redis-cli -h 192.168.31.15 BLPOP upload-list 0
    $value = $result[1]
    if ($result -eq "") {
        Write-Output "No value found in render-list"
        continue
    }
    biliup append -l qn --limit 6 --vid BV1ub411o7Xj $value
    Send-WechatMessage "$($value)上传完毕"
}
```



# 分割输出

1. 打开 PR
2. 视频用刀片切割
3. 右键每一段，嵌套
4. 选中所有序列，输出
5. 进入队列


ffmpeg -i "./bayonetta3/2022-11-10 22-20-35.mkv" -c:v h264_nvenc -profile:v main -b:v 19000k -profile:v main -s 1920x1080 -c:a aac -b:a 320k -x264opts crf=12 -maxrate:v 24000k -bufsize 24000k -pix_fmt yuv420p ./bayonetta3/day2_1.mp4; `
ffmpeg -i "./bayonetta3/2022-11-10 22-53-31.mkv" -c:v h264_nvenc -profile:v main -b:v 19000k -profile:v main -s 1920x1080 -c:a aac -b:a 320k -x264opts crf=12 -maxrate:v 24000k -bufsize 24000k -pix_fmt yuv420p ./bayonetta3/day2_2.mp4; `
ffmpeg -i "./Splatoon3/2022-09-11 23-35-20.mkv" -c:v h264_nvenc -profile:v main -b:v 19000k -profile:v main -s 1920x1080 -c:a aac -b:a 320k -x264opts crf=12 -maxrate:v 24000k -bufsize 24000k -pix_fmt yuv420p ./Splatoon3/day1.mp4; `
ffmpeg -i "./Splatoon3/2022-11-10 21-53-51.mkv" -c:v h264_nvenc -profile:v main -b:v 19000k -profile:v main -s 1920x1080 -c:a aac -b:a 320k -x264opts crf=12 -maxrate:v 24000k -bufsize 24000k -pix_fmt yuv420p ./Splatoon3/day2.mp4













## 切片

```powershell
ffmpeg -to 00:47:31 -i .\day14.mp4 -c:v copy -c:a copy day14_p1.mp4; `
ffmpeg -ss 00:47:31 -i .\day14.mp4 -c:v copy -c:a copy day14_p2.mp4; `
ffmpeg -to 00:45:38 -i .\day16.mp4 -c:v copy -c:a copy day16_p1.mp4; `
ffmpeg -ss 00:47:31 -to 01:28:31 -i .\day16.mp4 -c:v copy -c:a copy day16_p2.mp4; `
ffmpeg -ss 01:28:31 -to 02:11:07 -i .\day16.mp4 -c:v copy -c:a copy day16_p3.mp4; `
ffmpeg -ss 02:11:07 -to 02:54:27  -i .\day16.mp4 -c:v copy -c:a copy day16_p4.mp4; `
ffmpeg -ss 02:54:27 -to 03:22:36  -i .\day16.mp4 -c:v copy -c:a copy day16_p5.mp4

# day17
ffmpeg -to 00:54:23  -i .\day17.mp4 -c:v copy -c:a copy day17_p1.mp4; `
ffmpeg -ss 00:54:23 -to 01:41:44 -i .\day17.mp4 -c:v copy -c:a copy day17_p2.mp4; `
ffmpeg -ss 01:41:44 -to 02:27:49 -i .\day17.mp4 -c:v copy -c:a copy day17_p3.mp4; `
ffmpeg -ss 02:27:49 -i .\day17.mp4 -c:v copy -c:a copy day17_p4.mp4

# day18
ffmpeg -to 00:57:18  -i .\day18.mp4 -c:v copy -c:a copy day18_p1.mp4; `
ffmpeg -ss 00:57:18 -to 01:52:31  -i .\day18.mp4 -c:v copy -c:a copy day18_p2.mp4; `
ffmpeg -ss 01:52:31 -to 02:47:17 -i .\day18.mp4 -c:v copy -c:a copy day18_p3.mp4; `
ffmpeg -ss 02:47:17 -to 03:41:15 -i .\day18.mp4 -c:v copy -c:a copy day18_p4.mp4; `
ffmpeg -ss 03:41:15 -i .\day18.mp4 -c:v copy -c:a copy day18_p5.mp4; `
ffmpeg -to 00:52:06 -i .\day19.mp4 -c:v copy -c:a copy day19_p1.mp4; `
ffmpeg -ss 00:52:06 -to 01:43:57 -i .\day19.mp4 -c:v copy -c:a copy day19_p2.mp4; `
ffmpeg -ss 01:43:57 -to 02:31:46 -i .\day19.mp4 -c:v copy -c:a copy day19_p3.mp4; `
ffmpeg -ss 02:31:46 -i .\day19.mp4 -c:v copy -c:a copy day19_p4.mp4; `
```

 
