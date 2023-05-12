while ($true) {
    $result = redis-cli -h 192.168.1.2 BLPOP upload-list 0
    $value = $result[1]
    if ($result -eq "") {
        Write-Output "No value found in render-list"
        continue
    }
    biliup append -l qn --limit 6 --vid BVidxxxxxxxxx $value
}