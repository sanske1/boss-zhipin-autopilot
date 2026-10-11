param([string]$XmlPath, [string]$OutPath)
[Console]::OutputEncoding = [Text.Encoding]::UTF8
[xml]$x = Get-Content -Raw -Encoding UTF8 $XmlPath
$ids = @(
  'tv_job_name','tv_job_salary','tv_required_location',
  'tv_required_work_exp','tv_required_degree',
  'tv_boss_name','tv_boss_title','boss_label_tv','tv_description'
)
$sb = New-Object System.Text.StringBuilder
foreach ($id in $ids) {
  $n = $x.SelectSingleNode("//node[contains(@resource-id,'$id')]")
  if ($n -ne $null) {
    [void]$sb.AppendLine("### $id")
    [void]$sb.AppendLine($n.Attributes['text'].Value)
    [void]$sb.AppendLine("")
  }
}
Set-Content -Path $OutPath -Value $sb.ToString() -Encoding UTF8
Write-Output "written: $OutPath"
