# HostsManager.ps1
# 交互式 Hosts 文件管理工具

# 检查管理员权限，如果不是管理员则重新以管理员身份运行
function Check-Admin {
    $currentUser = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($currentUser)
    $adminRole = [Security.Principal.WindowsBuiltInRole]::Administrator
    
    if (-not $principal.IsInRole($adminRole)) {
        Write-Host "需要管理员权限，正在重新以管理员身份运行..." -ForegroundColor Yellow
        Start-Process PowerShell -Verb RunAs -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`""
        exit
    }
}

# 备份 Hosts 文件
function Backup-Hosts {
    $hostsPath = "$env:windir\System32\drivers\etc\hosts"
    $backupDir = Join-Path $PSScriptRoot "hosts_backups"
    
    # 创建备份目录
    if (-not (Test-Path $backupDir)) {
        New-Item -ItemType Directory -Path $backupDir -Force | Out-Null
    }
    
    # 生成备份文件名（带时间戳）
    $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $backupFile = Join-Path $backupDir "hosts_backup_$timestamp.txt"
    
    # 复制当前 Hosts 文件
    Copy-Item -Path $hostsPath -Destination $backupFile -Force
    
    # 清理旧的备份文件（只保留最近3个）
    $backupFiles = Get-ChildItem -Path $backupDir -Filter "hosts_backup_*.txt" | 
                   Sort-Object LastWriteTime -Descending
    if ($backupFiles.Count -gt 3) {
        $backupFiles | Select-Object -Skip 3 | Remove-Item -Force
    }
    
    return $backupFile
}

# 读取并解析 Hosts 文件
function Read-HostsFile {
    $hostsPath = "$env:windir\System32\drivers\etc\hosts"
    $entries = @()
    $lineNumber = 0
    
    if (Test-Path $hostsPath) {
        $content = Get-Content $hostsPath -Encoding UTF8
        
        foreach ($line in $content) {
            $lineNumber++
            $trimmedLine = $line.Trim()
            
            # 跳过空行和注释行
            if ([string]::IsNullOrWhiteSpace($trimmedLine) -or $trimmedLine.StartsWith('#')) {
                continue
            }
            
            # 解析行内容
            $parts = $trimmedLine -split '\s+', 2
            
            if ($parts.Count -eq 2) {
                $ip = $parts[0].Trim()
                $domain = $parts[1].Trim()
                
                # 移除可能的尾随注释
                if ($domain.Contains('#')) {
                    $domain = $domain.Substring(0, $domain.IndexOf('#')).Trim()
                }
                
                # 验证IP和域名
                if ($ip -match '^\d{1,3}(\.\d{1,3}){3}$' -and -not [string]::IsNullOrWhiteSpace($domain)) {
                    $entries += [PSCustomObject]@{
                        LineNumber = $lineNumber
                        OriginalLine = $line
                        IP = $ip
                        Domain = $domain
                        IsValid = $true
                    }
                }
            }
        }
    }
    
    return $entries
}

# 显示 Hosts 文件内容
function Show-Hosts {
    param(
        [switch]$ShowAll = $false
    )
    
    Clear-Host
    Write-Host "=== Hosts 文件内容 ===" -ForegroundColor Cyan
    Write-Host ""
    
    if ($ShowAll) {
        # 显示所有行（包括注释和空行）
        $hostsPath = "$env:windir\System32\drivers\etc\hosts"
        if (Test-Path $hostsPath) {
            $content = Get-Content $hostsPath -Encoding UTF8
            
            for ($i = 0; $i -lt $content.Count; $i++) {
                $line = $content[$i]
                $lineNum = $i + 1
                
                if ([string]::IsNullOrWhiteSpace($line)) {
                    Write-Host "$lineNum : [空行]" -ForegroundColor Gray
                } elseif ($line.Trim().StartsWith('#')) {
                    Write-Host "$lineNum : $line" -ForegroundColor DarkGray
                } else {
                    Write-Host "$lineNum : $line" -ForegroundColor Green
                }
            }
        }
    } else {
        # 只显示有效条目
        $entries = Read-HostsFile
        
        if ($entries.Count -eq 0) {
            Write-Host "没有找到有效的 hosts 条目。" -ForegroundColor Yellow
        } else {
            Write-Host "序号 | IP地址         | 域名" -ForegroundColor White
            Write-Host "----|----------------|--------------------------------"
            
            foreach ($entry in $entries) {
                Write-Host ("{0,4} | {1,-15} | {2}" -f 
                    $entry.LineNumber, $entry.IP, $entry.Domain) -ForegroundColor Green
            }
        }
    }
    
    Write-Host ""
    Write-Host "总计: $($entries.Count) 个有效条目" -ForegroundColor Cyan
}

# 解析 hosts.txt 文件
function Parse-HostsTextFile {
    param(
        [string]$FilePath
    )
    
    $entries = @()
    
    if (Test-Path $FilePath) {
        $content = Get-Content $FilePath -Encoding UTF8
        
        foreach ($line in $content) {
            $trimmedLine = $line.Trim()
            
            # 跳过空行和注释行
            if ([string]::IsNullOrWhiteSpace($trimmedLine) -or $trimmedLine.StartsWith('#')) {
                continue
            }
            
            # 使用正则表达式匹配 IP 和域名（支持多种分隔符）
            if ($trimmedLine -match '^(?:(?<ip>\d{1,3}(\.\d{1,3}){3})\s+(?<domain>[^\s#]+)|(?<domain2>[^\s#]+)\s+(?<ip2>\d{1,3}(\.\d{1,3}){3}))') {
                if ($Matches['ip']) {
                    $ip = $Matches['ip']
                    $domain = $Matches['domain']
                } else {
                    $ip = $Matches['ip2']
                    $domain = $Matches['domain2']
                }
                
                # 移除尾随注释
                $domain = $domain.TrimEnd('#').Trim()
                
                $entries += [PSCustomObject]@{
                    IP = $ip
                    Domain = $domain
                    OriginalLine = $line
                }
            } else {
                Write-Host "警告: 无法解析行: $line" -ForegroundColor Yellow
            }
        }
    } else {
        Write-Host "错误: 找不到文件 $FilePath" -ForegroundColor Red
    }
    
    return $entries
}

# 添加 Hosts 条目
function Add-HostsEntries {
    $hostsTextFile = Join-Path $PSScriptRoot "hosts.txt"
    
    if (-not (Test-Path $hostsTextFile)) {
        Write-Host "错误: 找不到 hosts.txt 文件" -ForegroundColor Red
        return
    }
    
    # 备份原始文件
    $backupFile = Backup-Hosts
    Write-Host "已创建备份: $backupFile" -ForegroundColor Green
    
    # 解析 hosts.txt
    $newEntries = Parse-HostsTextFile -FilePath $hostsTextFile
    
    if ($newEntries.Count -eq 0) {
        Write-Host "hosts.txt 中没有找到有效的条目。" -ForegroundColor Yellow
        return
    }
    
    # 读取现有 Hosts 条目
    $existingEntries = Read-HostsFile
    $hostsPath = "$env:windir\System32\drivers\etc\hosts"
    
    # 准备要添加的条目
    $entriesToAdd = @()
    $duplicateCount = 0
    
    foreach ($newEntry in $newEntries) {
        $isDuplicate = $false
        
        # 检查是否已存在相同的 IP+域名
        foreach ($existingEntry in $existingEntries) {
            if ($existingEntry.IP -eq $newEntry.IP -and 
                $existingEntry.Domain -eq $newEntry.Domain) {
                $isDuplicate = $true
                $duplicateCount++
                Write-Host "跳过重复项: $($newEntry.IP) $($newEntry.Domain)" -ForegroundColor Yellow
                break
            }
        }
        
        if (-not $isDuplicate) {
            $entriesToAdd += $newEntry
        }
    }
    
    # 添加新条目
    if ($entriesToAdd.Count -gt 0) {
        # 读取原始文件内容（保持注释和格式）
        $originalContent = Get-Content $hostsPath -Encoding UTF8
        
        # 添加新条目
        foreach ($entry in $entriesToAdd) {
            $newLine = "$($entry.IP)`t$($entry.Domain)"
            $originalContent += $newLine
            Write-Host "添加: $newLine" -ForegroundColor Green
        }
        
        # 写入文件
        $originalContent | Out-File $hostsPath -Encoding UTF8 -Force
        
        Write-Host ""
        Write-Host "成功添加了 $($entriesToAdd.Count) 个条目。" -ForegroundColor Green
        if ($duplicateCount -gt 0) {
            Write-Host "跳过了 $duplicateCount 个重复条目。" -ForegroundColor Yellow
        }
    } else {
        Write-Host "没有需要添加的新条目。" -ForegroundColor Yellow
    }
}

# 删除 Hosts 条目
function Remove-HostsEntries {
    Show-Hosts
    
    Write-Host ""
    Write-Host "=== 删除选项 ===" -ForegroundColor Cyan
    Write-Host "1. 根据行号删除（支持单个、多个、范围）"
    Write-Host "2. 根据 IP 地址删除"
    Write-Host "3. 根据域名（模糊匹配）删除"
    Write-Host "4. 返回主菜单"
    Write-Host ""
    
    $choice = Read-Host "请选择删除方式 (1-4)"
    
    switch ($choice) {
        '1' { Remove-ByLineNumber }
        '2' { Remove-ByIP }
        '3' { Remove-ByDomain }
        '4' { return }
        default {
            Write-Host "无效的选择，请重试。" -ForegroundColor Red
            Remove-HostsEntries
        }
    }
}

# 根据行号删除 - 增强版（支持范围删除）
function Remove-ByLineNumber {
    Write-Host "输入格式说明：" -ForegroundColor Yellow
    Write-Host "- 单个行号: 53" -ForegroundColor Cyan
    Write-Host "- 多个行号: 53,54,55" -ForegroundColor Cyan
    Write-Host "- 范围删除: 53-63" -ForegroundColor Cyan
    Write-Host "- 混合格式: 53,55-60,62" -ForegroundColor Cyan
    Write-Host ""
    
    $lineInput = Read-Host "请输入要删除的行号"
    
    if ([string]::IsNullOrWhiteSpace($lineInput)) {
        Write-Host "操作已取消。" -ForegroundColor Yellow
        return
    }
    
    # 解析行号（支持范围和逗号分隔）
    $lineNumbers = @()
    
    # 按逗号分割
    $parts = $lineInput.Split(',')
    
    foreach ($part in $parts) {
        $trimmedPart = $part.Trim()
        
        # 检查是否是范围格式（如53-63）
        if ($trimmedPart -match '^(\d+)-(\d+)$') {
            $start = [int]$Matches[1]
            $end = [int]$Matches[2]
            
            # 确保范围有效
            if ($start -le $end) {
                for ($i = $start; $i -le $end; $i++) {
                    $lineNumbers += $i
                }
            } else {
                Write-Host "警告: 无效的范围 $trimmedPart，起始行号不能大于结束行号" -ForegroundColor Yellow
            }
        }
        # 检查是否是单个数字
        elseif ($trimmedPart -match '^\d+$') {
            $lineNumbers += [int]$trimmedPart
        }
        else {
            Write-Host "警告: 忽略无效的输入 '$trimmedPart'" -ForegroundColor Yellow
        }
    }
    
    # 去重并排序
    $lineNumbers = $lineNumbers | Sort-Object -Unique
    
    if ($lineNumbers.Count -eq 0) {
        Write-Host "无效的行号格式。" -ForegroundColor Red
        return
    }
    
    Write-Host ""
    Write-Host "准备删除以下行号：" -ForegroundColor Cyan
    Write-Host ($lineNumbers -join ', ')
    Write-Host ""
    
    $confirm = Read-Host "确认删除以上 $($lineNumbers.Count) 行？(Y/N)"
    
    if ($confirm -ne 'Y' -and $confirm -ne 'y') {
        Write-Host "操作已取消。" -ForegroundColor Yellow
        return
    }
    
    # 备份
    $backupFile = Backup-Hosts
    Write-Host "已创建备份: $backupFile" -ForegroundColor Green
    
    $hostsPath = "$env:windir\System32\drivers\etc\hosts"
    
    # 使用 ArrayList 替代固定数组
    $content = [System.Collections.ArrayList](Get-Content $hostsPath -Encoding UTF8)
    
    # 从后往前删除（避免索引变化）
    $removedCount = 0
    $lineNumbers = $lineNumbers | Sort-Object -Descending
    
    foreach ($lineNum in $lineNumbers) {
        $index = $lineNum - 1
        if ($index -ge 0 -and $index -lt $content.Count) {
            $removedLine = $content[$index]
            # 现在可以使用 RemoveAt，因为 $content 是 ArrayList
            $content.RemoveAt($index)
            $removedCount++
            Write-Host "已删除第 $lineNum 行: $removedLine" -ForegroundColor Green
        } else {
            Write-Host "警告: 第 $lineNum 行不存在" -ForegroundColor Yellow
        }
    }
    
    # 写入文件
    $content | Out-File $hostsPath -Encoding UTF8 -Force
    
    Write-Host ""
    Write-Host "成功删除了 $removedCount 行。" -ForegroundColor Green
    Pause
}

# 根据 IP 地址删除 - 修复版本
function Remove-ByIP {
    $ipToRemove = Read-Host "请输入要删除的 IP 地址"
    
    if ([string]::IsNullOrWhiteSpace($ipToRemove)) {
        Write-Host "操作已取消。" -ForegroundColor Yellow
        return
    }
    
    # 查找匹配的条目
    $entries = Read-HostsFile
    $matchingEntries = $entries | Where-Object { $_.IP -eq $ipToRemove }
    
    if ($matchingEntries.Count -eq 0) {
        Write-Host "未找到匹配的 IP 地址: $ipToRemove" -ForegroundColor Yellow
        return
    }
    
    Write-Host ""
    Write-Host "找到 $($matchingEntries.Count) 个匹配的条目:" -ForegroundColor Cyan
    Write-Host "序号 | IP地址         | 域名"
    Write-Host "----|----------------|--------------------------------"
    
    foreach ($entry in $matchingEntries) {
        Write-Host ("{0,4} | {1,-15} | {2}" -f 
            $entry.LineNumber, $entry.IP, $entry.Domain) -ForegroundColor Green
    }
    
    Write-Host ""
    $confirm = Read-Host "确认删除以上所有条目？(Y/N)"
    
    if ($confirm -eq 'Y' -or $confirm -eq 'y') {
        # 备份
        $backupFile = Backup-Hosts
        Write-Host "已创建备份: $backupFile" -ForegroundColor Green
        
        $hostsPath = "$env:windir\System32\drivers\etc\hosts"
        # 使用 ArrayList 替代固定数组
        $content = [System.Collections.ArrayList](Get-Content $hostsPath -Encoding UTF8)
        
        # 从后往前删除
        $removedCount = 0
        $matchingEntries = $matchingEntries | Sort-Object LineNumber -Descending
        
        foreach ($entry in $matchingEntries) {
            $index = $entry.LineNumber - 1
            if ($index -ge 0 -and $index -lt $content.Count) {
                $content.RemoveAt($index)
                $removedCount++
            }
        }
        
        # 写入文件
        $content | Out-File $hostsPath -Encoding UTF8 -Force
        
        Write-Host "成功删除了 $removedCount 个条目。" -ForegroundColor Green
    } else {
        Write-Host "操作已取消。" -ForegroundColor Yellow
    }
    
    Pause
}

# 根据域名删除（模糊匹配）
function Remove-ByDomain {
    $domainPattern = Read-Host "请输入要删除的域名（支持模糊匹配，如输入 'test1' 匹配 'test1.yuque.com'）"
    
    if ([string]::IsNullOrWhiteSpace($domainPattern)) {
        Write-Host "操作已取消。" -ForegroundColor Yellow
        return
    }
    
    # 查找匹配的条目
    $entries = Read-HostsFile
    $matchingEntries = $entries | Where-Object { $_.Domain -like "*$domainPattern*" }
    
    if ($matchingEntries.Count -eq 0) {
        Write-Host "未找到匹配的域名模式: $domainPattern" -ForegroundColor Yellow
        return
    }
    
    Write-Host ""
    Write-Host "找到 $($matchingEntries.Count) 个匹配的条目:" -ForegroundColor Cyan
    Write-Host "序号 | IP地址         | 域名"
    Write-Host "----|----------------|--------------------------------"
    
    foreach ($entry in $matchingEntries) {
        Write-Host ("{0,4} | {1,-15} | {2}" -f 
            $entry.LineNumber, $entry.IP, $entry.Domain) -ForegroundColor Green
    }
    
    Write-Host ""
    Write-Host "删除选项:" -ForegroundColor Cyan
    Write-Host "1. 删除所有匹配的条目"
    Write-Host "2. 选择特定行号删除"
    Write-Host "3. 取消操作"
    Write-Host ""
    
    $choice = Read-Host "请选择 (1-3)"
    
    switch ($choice) {
        '1' {
            $confirm = Read-Host "确认删除所有 $($matchingEntries.Count) 个条目？(Y/N)"
            if ($confirm -eq 'Y' -or $confirm -eq 'y') {
                Remove-SelectedEntries $matchingEntries
            } else {
                Write-Host "操作已取消。" -ForegroundColor Yellow
            }
        }
        '2' {
            Write-Host "输入格式说明：" -ForegroundColor Yellow
            Write-Host "- 单个行号: 53" -ForegroundColor Cyan
            Write-Host "- 多个行号: 53,54,55" -ForegroundColor Cyan
            Write-Host "- 范围删除: 53-63" -ForegroundColor Cyan
            Write-Host ""
            
            $lineNums = Read-Host "请输入要删除的行号"
            if (-not [string]::IsNullOrWhiteSpace($lineNums)) {
                $selectedEntries = @()
                $lineNumbers = ParseLineNumberInput $lineNums
                
                foreach ($lineNum in $lineNumbers) {
                    $entry = $matchingEntries | Where-Object { $_.LineNumber -eq $lineNum }
                    if ($entry) {
                        $selectedEntries += $entry
                    }
                }
                
                if ($selectedEntries.Count -gt 0) {
                    Remove-SelectedEntries $selectedEntries
                } else {
                    Write-Host "未找到指定的行号。" -ForegroundColor Yellow
                }
            }
        }
        '3' {
            Write-Host "操作已取消。" -ForegroundColor Yellow
        }
    }
    
    Pause
}

# 解析行号输入（支持范围和逗号分隔）
function ParseLineNumberInput {
    param(
        [string]$InputText
    )
    
    $lineNumbers = @()
    
    # 按逗号分割
    $parts = $InputText.Split(',')
    
    foreach ($part in $parts) {
        $trimmedPart = $part.Trim()
        
        # 检查是否是范围格式（如53-63）
        if ($trimmedPart -match '^(\d+)-(\d+)$') {
            $start = [int]$Matches[1]
            $end = [int]$Matches[2]
            
            # 确保范围有效
            if ($start -le $end) {
                for ($i = $start; $i -le $end; $i++) {
                    $lineNumbers += $i
                }
            } else {
                Write-Host "警告: 无效的范围 $trimmedPart" -ForegroundColor Yellow
            }
        }
        # 检查是否是单个数字
        elseif ($trimmedPart -match '^\d+$') {
            $lineNumbers += [int]$trimmedPart
        }
    }
    
    return $lineNumbers | Sort-Object -Unique
}

# 删除选定的条目 - 修复版本
function Remove-SelectedEntries {
    param(
        [array]$Entries
    )
    
    # 备份
    $backupFile = Backup-Hosts
    Write-Host "已创建备份: $backupFile" -ForegroundColor Green
    
    $hostsPath = "$env:windir\System32\drivers\etc\hosts"
    # 使用 ArrayList 替代固定数组
    $content = [System.Collections.ArrayList](Get-Content $hostsPath -Encoding UTF8)
    
    # 从后往前删除
    $removedCount = 0
    $Entries = $Entries | Sort-Object LineNumber -Descending
    
    foreach ($entry in $Entries) {
        $index = $entry.LineNumber - 1
        if ($index -ge 0 -and $index -lt $content.Count) {
            $content.RemoveAt($index)
            $removedCount++
            Write-Host "已删除: $($entry.IP) $($entry.Domain)" -ForegroundColor Green
        }
    }
    
    # 写入文件
    $content | Out-File $hostsPath -Encoding UTF8 -Force
    
    Write-Host "成功删除了 $removedCount 个条目。" -ForegroundColor Green
}

# 清理 Hosts 文件
function Clean-HostsFile {
    Write-Host "正在清理 Hosts 文件..." -ForegroundColor Cyan
    
    # 备份
    $backupFile = Backup-Hosts
    Write-Host "已创建备份: $backupFile" -ForegroundColor Green
    
    $hostsPath = "$env:windir\System32\drivers\etc\hosts"
    $content = Get-Content $hostsPath -Encoding UTF8
    
    # 清理空行和尾随空格
    $cleanedContent = @()
    $emptyLineCount = 0
    $whitespaceLineCount = 0
    
    foreach ($line in $content) {
        $trimmedLine = $line.Trim()
        
        # 跳过空行
        if ([string]::IsNullOrWhiteSpace($trimmedLine)) {
            $emptyLineCount++
            continue
        }
        
        # 保留注释行，但清理尾随空格
        if ($trimmedLine.StartsWith('#')) {
            $cleanedContent += $trimmedLine
        } else {
            # 清理数据行的尾随空格
            $cleanedContent += $trimmedLine
        }
    }
    
    # 写入清理后的内容
    $cleanedContent | Out-File $hostsPath -Encoding UTF8 -Force
    
    Write-Host "清理完成：" -ForegroundColor Green
    Write-Host "- 移除了 $emptyLineCount 个空行" -ForegroundColor Green
    Write-Host "- 清理了 $whitespaceLineCount 行的尾随空格" -ForegroundColor Green
    Write-Host "- 总行数: $($cleanedContent.Count)" -ForegroundColor Green
    
    Pause
}

# 查看备份文件
function Show-Backups {
    $backupDir = Join-Path $PSScriptRoot "hosts_backups"
    
    if (-not (Test-Path $backupDir)) {
        Write-Host "没有找到备份目录。" -ForegroundColor Yellow
        return
    }
    
    $backupFiles = Get-ChildItem -Path $backupDir -Filter "hosts_backup_*.txt" | 
                   Sort-Object LastWriteTime -Descending
    
    if ($backupFiles.Count -eq 0) {
        Write-Host "没有找到备份文件。" -ForegroundColor Yellow
        return
    }
    
    Write-Host "=== 备份文件列表 ===" -ForegroundColor Cyan
    Write-Host ""
    
    $count = 1
    foreach ($file in $backupFiles) {
        Write-Host "$count. $($file.Name)" -ForegroundColor Green
        Write-Host "   创建时间: $($file.LastWriteTime)" -ForegroundColor Gray
        Write-Host "   大小: $([math]::Round($file.Length/1KB, 2)) KB" -ForegroundColor Gray
        Write-Host "   路径: $($file.FullName)" -ForegroundColor DarkGray
        Write-Host ""
        $count++
    }
    
    Write-Host "总计: $($backupFiles.Count) 个备份文件" -ForegroundColor Cyan
    
    # 询问是否要还原
    Write-Host ""
    Write-Host "选项:" -ForegroundColor Cyan
    Write-Host "1. 选择备份文件还原"
    Write-Host "2. 返回主菜单"
    Write-Host ""
    
    $choice = Read-Host "请选择 (1-2)"
    
    switch ($choice) {
        '1' {
            RestoreFromBackup
        }
        '2' {
            return
        }
        default {
            Write-Host "无效的选择。" -ForegroundColor Red
        }
    }
}

# 还原备份文件
function RestoreFromBackup {
    $backupDir = Join-Path $PSScriptRoot "hosts_backups"
    
    if (-not (Test-Path $backupDir)) {
        Write-Host "没有找到备份目录。" -ForegroundColor Yellow
        return
    }
    
    $backupFiles = Get-ChildItem -Path $backupDir -Filter "hosts_backup_*.txt" | 
                   Sort-Object LastWriteTime -Descending
    
    if ($backupFiles.Count -eq 0) {
        Write-Host "没有找到备份文件。" -ForegroundColor Yellow
        return
    }
    
    Write-Host "=== 选择要还原的备份文件 ===" -ForegroundColor Cyan
    Write-Host ""
    
    # 显示备份文件列表
    for ($i = 0; $i -lt $backupFiles.Count; $i++) {
        $file = $backupFiles[$i]
        Write-Host "$($i+1). $($file.Name)" -ForegroundColor Green
        Write-Host "   创建时间: $($file.LastWriteTime)" -ForegroundColor Gray
        Write-Host "   大小: $([math]::Round($file.Length/1KB, 2)) KB" -ForegroundColor Gray
        Write-Host ""
    }
    
    Write-Host "0. 取消"
    Write-Host ""
    
    $choice = Read-Host "请选择要还原的备份文件编号 (1-$($backupFiles.Count))"
    
    if ($choice -eq '0') {
        Write-Host "操作已取消。" -ForegroundColor Yellow
        return
    }
    
    if ($choice -match '^\d+$' -and [int]$choice -ge 1 -and [int]$choice -le $backupFiles.Count) {
        $selectedFile = $backupFiles[[int]$choice - 1]
        
        Write-Host ""
        Write-Host "您选择了: $($selectedFile.Name)" -ForegroundColor Yellow
        Write-Host "创建时间: $($selectedFile.LastWriteTime)" -ForegroundColor Yellow
        Write-Host ""
        
        # 显示备份文件内容预览
        Write-Host "备份文件内容预览（前10行）:" -ForegroundColor Cyan
        $previewLines = Get-Content $selectedFile.FullName -Encoding UTF8 | Select-Object -First 10
        foreach ($line in $previewLines) {
            Write-Host "  $line" -ForegroundColor Gray
        }
        Write-Host ""
        
        $confirm = Read-Host "确认还原此备份文件？这将覆盖当前的 hosts 文件。(Y/N)"
        
        if ($confirm -eq 'Y' -or $confirm -eq 'y') {
            # 先备份当前文件
            $currentBackup = Backup-Hosts
            Write-Host "已备份当前 hosts 文件: $currentBackup" -ForegroundColor Green
            
            # 还原选定的备份
            $hostsPath = "$env:windir\System32\drivers\etc\hosts"
            Copy-Item -Path $selectedFile.FullName -Destination $hostsPath -Force
            
            Write-Host "成功从备份还原: $($selectedFile.Name)" -ForegroundColor Green
            Write-Host "请刷新 DNS 缓存以使更改生效。" -ForegroundColor Yellow
            
            # 刷新 DNS 缓存的选项
            Write-Host ""
            $flushDNS = Read-Host "是否立即刷新 DNS 缓存？(Y/N)"
            
            if ($flushDNS -eq 'Y' -or $flushDNS -eq 'y') {
                Write-Host "正在刷新 DNS 缓存..." -ForegroundColor Cyan
                ipconfig /flushdns
                Write-Host "DNS 缓存已刷新。" -ForegroundColor Green
            }
        } else {
            Write-Host "操作已取消。" -ForegroundColor Yellow
        }
    } else {
        Write-Host "无效的选择。" -ForegroundColor Red
    }
    
    Pause
}

# 显示帮助信息
function Show-Help {
    Clear-Host
    Write-Host "=== Hosts 文件管理工具使用说明 ===" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "功能说明:" -ForegroundColor Green
    Write-Host "1. 显示 Hosts 文件 - 显示当前 hosts 文件的条目"
    Write-Host "2. 从 hosts.txt 添加条目 - 从脚本目录的 hosts.txt 文件中添加条目"
    Write-Host "   - 自动去重（IP+域名完全一致）"
    Write-Host "   - 支持 hosts.txt 中的多种格式（IP 域名 或 域名 IP）"
    Write-Host "3. 删除条目 - 支持多种删除方式"
    Write-Host "   - 根据行号删除（支持单个、多个、范围如53-63）"
    Write-Host "   - 根据 IP 地址删除"
    Write-Host "   - 根据域名模糊匹配删除（如输入 'test1' 匹配 'test1.example.com'）"
    Write-Host "4. 清理文件 - 移除空行和多余空格"
    Write-Host "5. 查看和还原备份 - 显示最近的备份文件并可选择还原"
    Write-Host "6. 显示使用帮助"
    Write-Host ""
    Write-Host "新功能说明:" -ForegroundColor Yellow
    Write-Host "- 批量删除: 支持范围删除，如 '53-63' 可删除53到63行"
    Write-Host "- 还原备份: 可从备份文件中选择并还原到任意备份点"
    Write-Host ""
    Write-Host "文件格式说明:" -ForegroundColor Green
    Write-Host "- hosts.txt 文件应放置在脚本同目录下"
    Write-Host "- 每行格式可以是: 'IP 域名' 或 '域名 IP'"
    Write-Host "- IP 和域名之间可以有多个空格"
    Write-Host "- 以 # 开头的行将被视为注释"
    Write-Host "- 空行将被忽略"
    Write-Host ""
    Write-Host "示例 hosts.txt 内容:" -ForegroundColor Yellow
    Write-Host "192.168.1.100    server1.example.com"
    Write-Host "server2.example.com     192.168.1.101"
    Write-Host "# 这是一个注释"
    Write-Host "192.168.1.102   server3.example.com   # 带尾随注释"
    Write-Host ""
    Pause
}

# 主菜单
function Show-MainMenu {
    Clear-Host
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "      Windows Hosts 文件管理工具" -ForegroundColor Yellow
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "当前主机: $env:COMPUTERNAME" -ForegroundColor Green
    Write-Host "脚本目录: $PSScriptRoot" -ForegroundColor Green
    Write-Host ""
    Write-Host "请选择操作：" -ForegroundColor White
    Write-Host ""
    Write-Host "1. 显示 Hosts 文件内容" -ForegroundColor Cyan
    Write-Host "2. 从 hosts.txt 添加条目" -ForegroundColor Cyan
    Write-Host "3. 删除 Hosts 条目" -ForegroundColor Cyan
    Write-Host "4. 清理 Hosts 文件（移除空行等）" -ForegroundColor Cyan
    Write-Host "5. 查看和还原备份" -ForegroundColor Cyan
    Write-Host "6. 显示使用帮助" -ForegroundColor Cyan
    Write-Host "7. 退出" -ForegroundColor Red
    Write-Host ""
    Write-Host "========================================" -ForegroundColor Cyan
}

# 主程序
function Main {
    # 检查管理员权限
    Check-Admin
    
    # 显示欢迎信息
    Write-Host "Hosts 文件管理工具已启动" -ForegroundColor Green
    Write-Host "当前备份保留策略: 保留最近 3 个备份文件" -ForegroundColor Yellow
    Write-Host "批量删除支持: 使用格式如 '53-63' 可删除范围行" -ForegroundColor Yellow
    Write-Host ""
    
    # 主循环
    while ($true) {
        Show-MainMenu
        $choice = Read-Host "请输入选项 (1-7)"
        
        switch ($choice) {
            '1' { 
                Show-Hosts 
                Pause
            }
            '2' { 
                Add-HostsEntries 
                Pause
            }
            '3' { 
                Remove-HostsEntries 
            }
            '4' { 
                Clean-HostsFile 
            }
            '5' { 
                Show-Backups 
            }
            '6' { 
                Show-Help 
            }
            '7' { 
                Write-Host "感谢使用，再见！" -ForegroundColor Green
                Start-Sleep -Seconds 1
                exit 
            }
            default {
                Write-Host "无效的选项，请重新输入。" -ForegroundColor Red
                Start-Sleep -Seconds 1
            }
        }
    }
}

# 运行主程序
Main