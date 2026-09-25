Option Explicit

Dim shell, fso, root, scriptPath, command
Set shell = CreateObject("WScript.Shell")
Set fso = CreateObject("Scripting.FileSystemObject")
root = fso.GetParentFolderName(WScript.ScriptFullName)
scriptPath = fso.BuildPath(root, "shell\ARKO95.MissionControl.ps1")
command = "pwsh.exe -NoLogo -NoProfile -STA -ExecutionPolicy Bypass -File """ & scriptPath & """ -ProjectRoot """ & root & """"
shell.Run command, 0, False
