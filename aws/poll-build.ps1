# Poll CodeBuild status and print URLs when done
param([string]$BuildId)

$REGION = "ap-southeast-2"

if (-not $BuildId) {
    $BuildId = (aws codebuild list-builds-for-project --project-name "voting-app-build" --region $REGION --query "ids[0]" --output text)
    Write-Host "Polling latest build: $BuildId"
}

$maxAttempts = 40
$attempt = 1
while ($attempt -le $maxAttempts) {
    $status = (aws codebuild batch-get-builds --ids $BuildId --region $REGION --query "builds[0].buildStatus" --output text)
    $phase = (aws codebuild batch-get-builds --ids $BuildId --region $REGION --query "builds[0].currentPhase" --output text)
    Write-Host "[$attempt/$maxAttempts] $((Get-Date).ToString('HH:mm:ss')) Status: $status | Phase: $phase"
    if ($status -eq "SUCCEEDED") {
        Write-Host "BUILD SUCCEEDED!" -ForegroundColor Green
        Write-Host "Check build logs for Vote and Result URLs."
        Write-Host "https://$REGION.console.aws.amazon.com/codesuite/codebuild/projects/voting-app-build/history"
        break
    } elseif ($status -eq "FAILED" -or $status -eq "STOPPED") {
        Write-Host "BUILD $status -- check logs:" -ForegroundColor Red
        Write-Host "https://$REGION.console.aws.amazon.com/codesuite/codebuild/projects/voting-app-build/history"
        break
    }
    $attempt++
    Start-Sleep -Seconds 30
}