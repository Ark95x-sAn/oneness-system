# REMEDIATION: System reboot required
# REVIEW BEFORE RUNNING — this will restart the computer
# Save all work before proceeding!

Write-Host '=== Reboot Remediation ==='
Write-Host 'A system reboot is pending to complete Windows updates.'
Write-Host 'Save all work, then run:'
Write-Host '  shutdown /r /t 30  # 30-second countdown'
Write-Host 'Or cancel with: shutdown /a'

# Finding: System reboot pending
# Severity: warning
# Risk score: 0.5
# Generated: 20260810-164207