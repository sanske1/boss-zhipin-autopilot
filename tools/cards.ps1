param([string]$XmlPath)
# 从列表页 UI dump 中,按 XML 层级取出每张卡:公司名 \t 卡片bounds
[Console]::OutputEncoding = [Text.Encoding]::UTF8
[xml]$x = Get-Content -Raw -Encoding UTF8 $XmlPath

$out = New-Object System.Collections.ArrayList

function Walk($node) {
  foreach ($child in $node.ChildNodes) {
    if ($child.NodeType -ne 'Element') { continue }
    if ($child.Name -eq 'node') {
      $rid = $child.GetAttribute('resource-id')
      if ($rid -like '*tv_company_name') {
        $p = $child.ParentNode
        while ($p -ne $null -and $p.Name -eq 'node' -and $p.GetAttribute('clickable') -ne 'true') {
          $p = $p.ParentNode
        }
        if ($p -ne $null -and $p.Name -eq 'node') {
          [void]$out.Add(($child.GetAttribute('text') + "`t" + $p.GetAttribute('bounds')))
        }
      }
    }
    Walk $child
  }
}

Walk $x.DocumentElement
$out | ForEach-Object { $_ }
