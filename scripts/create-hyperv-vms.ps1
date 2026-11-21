#Requires -RunAsAdministrator
# Creates the Phase 1 lab: two Ubuntu VMs on a private lab network (Hyper-V).
#   labnet          = internal switch (VM <-> VM <-> your Windows host), 192.168.100.0/24
#   Default Switch  = Hyper-V NAT switch, gives the VMs internet for apt
$ErrorActionPreference = 'Stop'

$iso     = 'D:\Linux_Moath\iso\ubuntu-24.04.5-live-server-amd64.iso'
$vmRoot  = 'D:\HyperV'
$vms     = 'target-moath', 'client-moath'
$labSw   = 'labnet'

if (-not (Test-Path $iso)) { throw "ISO not found: $iso" }
New-Item -ItemType Directory -Force $vmRoot | Out-Null

# --- private lab network -------------------------------------------------
if (-not (Get-VMSwitch -Name $labSw -ErrorAction SilentlyContinue)) {
    New-VMSwitch -Name $labSw -SwitchType Internal | Out-Null
}
$ifAlias = "vEthernet ($labSw)"
if (-not (Get-NetIPAddress -InterfaceAlias $ifAlias -IPAddress 192.168.100.1 -ErrorAction SilentlyContinue)) {
    New-NetIPAddress -InterfaceAlias $ifAlias -IPAddress 192.168.100.1 -PrefixLength 24 | Out-Null
}

# --- VMs -----------------------------------------------------------------
foreach ($n in $vms) {
    if (Get-VM -Name $n -ErrorAction SilentlyContinue) { Write-Host "$n already exists, skipping"; continue }

    $vhd = "$vmRoot\$n\$n.vhdx"
    New-Item -ItemType Directory -Force "$vmRoot\$n" | Out-Null
    New-VM -Name $n -Generation 2 -MemoryStartupBytes 2GB -Path $vmRoot `
           -NewVHDPath $vhd -NewVHDSizeBytes 25GB -SwitchName 'Default Switch' | Out-Null
    Set-VM -Name $n -ProcessorCount 2 -DynamicMemory:$false -AutomaticCheckpointsEnabled $false
    Add-VMNetworkAdapter -VMName $n -SwitchName $labSw

    # Ubuntu needs the "Microsoft UEFI Certificate Authority" Secure Boot template
    Set-VMFirmware -VMName $n -SecureBootTemplate 'MicrosoftUEFICertificateAuthority'

    Add-VMDvdDrive -VMName $n -Path $iso
    $dvd = Get-VMDvdDrive -VMName $n
    Set-VMFirmware -VMName $n -FirstBootDevice $dvd
}

Get-VM | Where-Object Name -in $vms | Format-Table Name, State, MemoryStartup, ProcessorCount -AutoSize
Write-Host "`nDone. Open 'Hyper-V Manager', or run:  vmconnect localhost target-moath" -ForegroundColor Green
