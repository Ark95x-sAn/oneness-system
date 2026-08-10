# REMEDIATION: Restart stopped critical services
# REVIEW BEFORE RUNNING — this script starts Windows services

Write-Host '=== Service Remediation ==='
Write-Host 'Stopped critical services (review before starting):'

Write-Host '  BITS: Start-Service -Name BITS (check if safe first)'
Write-Host '  MapsBroker: Start-Service -Name MapsBroker (check if safe first)'
Write-Host '  sppsvc: Start-Service -Name sppsvc (check if safe first)'
Write-Host '  WinDefend: Start-Service -Name WinDefend (check if safe first)'
Write-Host ''
Write-Host 'Start services individually after review:'
# Start-Service -Name 'BITS'
# Start-Service -Name 'MapsBroker'
# Start-Service -Name 'sppsvc'
# Start-Service -Name 'WinDefend'

# Finding: 4 critical service(s) not running
# Severity: critical
# Risk score: 0.6
# Generated: 20260810-165514