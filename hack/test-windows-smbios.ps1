# SPDX-FileCopyrightText: © 2026 VEXXHOST, Inc.
# SPDX-License-Identifier: GPL-3.0-or-later

# Run inside the Windows guest before and after the qualified lifecycle actions.
param(
    [Parameter(Mandatory = $true)]
    [Guid]$ExpectedUuid,
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$ExpectedVendor,
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$ExpectedProduct,
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$ExpectedSerial
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$products = @(Get-CimInstance -ClassName Win32_ComputerSystemProduct)
if ($products.Count -ne 1) {
    throw "Expected one Win32_ComputerSystemProduct instance, got $($products.Count)"
}
$product = $products[0]
$actualUuid = [Guid]::Parse($product.UUID)
if ($actualUuid -ne $ExpectedUuid) {
    throw "SMBIOS UUID mismatch: expected $ExpectedUuid, got $actualUuid"
}
$expected = [ordered]@{
    Vendor = $ExpectedVendor
    Name = $ExpectedProduct
    IdentifyingNumber = $ExpectedSerial
}
foreach ($field in $expected.Keys) {
    if ($product.$field -cne $expected[$field]) {
        throw "SMBIOS $field mismatch: expected '$($expected[$field])', got '$($product.$field)'"
    }
}

[pscustomobject]@{
    Result = 'PASS'
    UUID = $actualUuid
    Vendor = $product.Vendor
    Product = $product.Name
    Serial = $product.IdentifyingNumber
}
