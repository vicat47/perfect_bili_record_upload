while ($true) {
    $result = redis-cli -h 192.168.1.2 BLPOP upload-list 0
    if ($result -eq "") {
        Write-Output "No value found in render-list"
        continue
    }
    $json = ConvertFrom-Json $result[1]
    biliup append -l qn --limit 6 --vid $json.bvid $json.filename
}