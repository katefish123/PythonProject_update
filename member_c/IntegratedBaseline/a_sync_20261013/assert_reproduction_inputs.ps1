function Assert-ReproductionInputs {
 param([string]$Root,[string]$ExpectedDigest='')
 $manifestPath=Join-Path $Root 'reproduction_manifest.json'
 $digest=(Get-FileHash -LiteralPath $manifestPath -Algorithm SHA256).Hash.ToLowerInvariant()
 if($ExpectedDigest -and $digest -ne $ExpectedDigest){throw 'Source manifest changed during qualification'}
 $manifest=Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
 if(@($manifest.files.PSObject.Properties).Count -lt 109){throw 'Incomplete input manifest'}
 foreach($file in $manifest.files.PSObject.Properties){
  $path=Join-Path $Root $file.Name
  if((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant() -ne $file.Value.local_sha256){
   throw "Input changed after reproduction preparation: $path"
  }
 }
 return [pscustomobject]@{digest=$digest;commit=$manifest.upstream_commit}
}
