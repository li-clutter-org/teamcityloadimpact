<#
Copyright 2016 Load Impact
Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0
    
Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
#>

<# Run Load Impact test from Powershell #>

<# Load Impact test id #>
$testId = YOUR_TEST_ID_HERE
<# API_KEY from your Load Impact account #>
$API_KEY = "YOUR_API_KEY_HERE" + ":"

$auth = 'Basic ' + [System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($API_KEY))

$uri = "https://api.loadimpact.com/v2/test-configs/" + $testId + "/start"

Write-Host "##teamcity[testStarted name='Load Impact performance test']"
Write-Host "##teamcity[progressMessage 'Kickoff performance test']"

<# try-catch because PS considers all 400+ codes to be errors and will exit if returned #>
$resp = $null
try {
  $resp = Invoke-WebRequest -uri $uri -Method Post -Headers @{'Authorization'=$auth}
} catch {}

<# Status 201 expected, 200 is just a current running test id #>

if ($resp.StatusCode -ne 201) {
  $perc = "Could not start test " + $testId + ": " + $resp.StatusCode + "`n" + $resp.Content
  Write-Host "##teamcity[buildProblem description='$perc']" 
  return
}

$js = ConvertFrom-Json -InputObject $resp.Content

$tid = $js.id

<# Until 5 minutes timout or status is running   #> 

$t = 0
$uri = "https://api.loadimpact.com/v2/tests/" + $tid + "/"
do {
  Start-Sleep -Seconds 10
  $resp = Invoke-WebRequest -uri $uri -Method Get -Headers @{'Authorization'=$auth}
  $j = ConvertFrom-Json -InputObject $resp.Content
  $status_text = $j.status_text
  $t = $t + 10

  if ($t -gt 300) {
    Write-Host "##teamcity[buildProblem description='Timeout - test start > 5 min']" 
    return
  }
} until ($status_text -eq "Running")

Write-Host "##teamcity[progressMessage 'Performance test running']"

<# wait until completed #>

$maxVULoadTime = 0.0
$percentage = 0.0
$uri = "https://api.loadimpact.com/v2/tests/" + $tid + "/results?ids=__li_progress_percent_total"
$uril = "https://api.loadimpact.com/v2/tests/" + $tid + "/results?ids=__li_user_load_time"
do {
  Start-Sleep -Seconds 30

  <# Get percent completed #>
  $resp = Invoke-WebRequest -uri $uri -Method Get -Headers @{'Authorization'=$auth}
  $j = ConvertFrom-Json -InputObject $resp.Content

  <# Since -Last 1 will get TWO on occassion we sort and get the first which will always get 1 #>
  $percentage = ($j.__li_progress_percent_total | Sort value -Descending | Select-Object -First 1).value

  Write-Host "##teamcity[progressMessage 'Percentage completed $percentage']"

  <# Get VU Load Time #>
  $resp = Invoke-WebRequest -uri $uril -Method Get -Headers @{'Authorization'=$auth}
  $j = ConvertFrom-Json -InputObject $resp.Content

  <# Sort and get the highest value #>
  $maxVULoadTime = ($j.__li_user_load_time | Sort value -Descending | Select-Object -First 1).value

  if ($maxVULoadTime -gt 1000) {
    $perc = "VU Load Time exceeded limit of 1 sec: " + $maxVULoadTime
    Write-Host "##teamcity[buildStatisticValue key='maxVULoadTime' value='$maxVULoadTime']"
    Write-Host "##teamcity[buildProblem description='$perc']"
    return
  }


} until ([double]$percentage -eq 100.0)

<# show results #>
Write-Host "##teamcity[progressMessage 'Show results']"
Write-Host "##teamcity[buildStatisticValue key='maxVULoadTime' value='$maxVULoadTime']"
"Max VU Load Time: " + $maxVULoadTime
"Full results at https://app.loadimpact.com/test-runs/" + $tid

Write-Host "##teamcity[testFinished name='Load Impact performance test']"
