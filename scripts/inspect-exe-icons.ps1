param(
    [Parameter(Mandatory = $true)]
    [string]$ExePath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
using System.Collections.Generic;

public static class ResEnum {
  public delegate bool EnumResNameProc(IntPtr hModule, IntPtr lpszType, IntPtr lpszName, IntPtr lParam);

  [DllImport("kernel32.dll", CharSet=CharSet.Unicode, SetLastError=true)]
  public static extern IntPtr LoadLibraryEx(string lpFileName, IntPtr hFile, uint dwFlags);

  [DllImport("kernel32.dll", SetLastError=true)]
  public static extern bool FreeLibrary(IntPtr hModule);

  [DllImport("kernel32.dll", CharSet=CharSet.Unicode, SetLastError=true)]
  public static extern bool EnumResourceNames(IntPtr hModule, IntPtr lpszType, EnumResNameProc lpEnumFunc, IntPtr lParam);
}
"@

$LOAD_LIBRARY_AS_DATAFILE = 0x00000002
$RT_ICON = [IntPtr]3
$RT_GROUP_ICON = [IntPtr]14

$module = [ResEnum]::LoadLibraryEx($ExePath, [IntPtr]::Zero, $LOAD_LIBRARY_AS_DATAFILE)
if ($module -eq [IntPtr]::Zero) {
    throw "Failed to load EXE as data file: $ExePath"
}

$groupIds = New-Object System.Collections.Generic.List[long]
$iconIds = New-Object System.Collections.Generic.List[long]

try {
    $groupCallback = [ResEnum+EnumResNameProc]{
        param($hModule, $type, $name, $lParam)
        $groupIds.Add($name.ToInt64()) | Out-Null
        return $true
    }

    $iconCallback = [ResEnum+EnumResNameProc]{
        param($hModule, $type, $name, $lParam)
        $iconIds.Add($name.ToInt64()) | Out-Null
        return $true
    }

    [void][ResEnum]::EnumResourceNames($module, $RT_GROUP_ICON, $groupCallback, [IntPtr]::Zero)
    [void][ResEnum]::EnumResourceNames($module, $RT_ICON, $iconCallback, [IntPtr]::Zero)
}
finally {
    [void][ResEnum]::FreeLibrary($module)
}

Write-Output "EXE: $ExePath"
Write-Output "RT_GROUP_ICON count: $($groupIds.Count)"
Write-Output "RT_GROUP_ICON ids: $($groupIds -join ', ')"
Write-Output "RT_ICON count: $($iconIds.Count)"
