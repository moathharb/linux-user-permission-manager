# Linux User & Permission Security Manager - Phase 1

Group 1, Topic 1. University of Petra, instructor Dr. Mohammed Aladaileh.

## Contents

| Path | Purpose |
|---|---|
| `user_manager.sh` | Module 1: creates users and groups from a CSV file with strong passwords, password expiry, home-directory permissions (700/750) and umask |
| `users.csv` | Sample input with four valid users and five invalid lines used for testing |
| `baseline/collect_baseline.sh` | Read-only script that collects the security baseline of the target VM |
| `scripts/create-hyperv-vms.ps1` | Creates the two Ubuntu VMs and the private lab network on Hyper-V |
| `report/Phase1_Report.docx` | Phase 1 report |

## Lab

Two Ubuntu Server 24.04.5 LTS virtual machines on Hyper-V: `target-moath` (192.168.100.10) and `client-moath` (192.168.100.11), connected through the private switch `labnet` (192.168.100.0/24).

## Usage

```bash
sudo ./user_manager.sh -f users.csv        # create the users
sudo ./user_manager.sh -f users.csv -n     # dry run, changes nothing
sudo ./user_manager.sh -h                  # help
```

CSV columns: `username,primary_group,home_mode,shell[,password]`. `home_mode` must be 700 or 750. If no password is given, a random one is generated and saved to a mode-600 credentials file.
