# Performance verification

The inventory format is disk-backed and the comparison engine loads one matching bucket pair at a time. This bounds comparison memory by the largest bucket pair rather than the complete inventory.

Run the synthetic scale check with:

```powershell
./scripts/Test-InventoryScale.ps1 -RecordCount 100000 -BucketCount 256
```

The check generates two equivalent redacted inventories in the operating-system temporary directory, compares all records, asserts that every record is unchanged, prints elapsed time, and removes its temporary artifacts. It uses no cloud resources or client data.

Elapsed time is environment-dependent and is not a product guarantee. Performance evidence should record the command, toolkit commit, PowerShell version, operating system, record count, bucket count, and observed duration.
