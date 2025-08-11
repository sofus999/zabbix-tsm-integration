# IBM Storage Protect Zabbix Monitoring

A comprehensive Zabbix monitoring solution for IBM Storage Protect (TSM) instances, featuring automated discovery, scalable monitoring, and efficient data collection through dsmadmc CLI integration.

## Project Overview

This project provides a complete monitoring solution for IBM Storage Protect environments, designed to replace traditional Nagios monitoring with a modern, scalable Zabbix-based approach. The solution leverages Zabbix's Low-Level Discovery (LLD) capabilities and autoregistration features to dynamically monitor multiple TSM instances with minimal manual configuration.

### Key Features

- **Automated Discovery**: Automatically discover TSM instances across your network
- **Dynamic Monitoring**: Monitor storage pools, volumes, containers, and administrative tasks
- **Scalable Architecture**: Handle multiple TSM instances efficiently through Zabbix Proxies
- **Secure Implementation**: Secure credential handling and controlled system access
- **Real-time Alerting**: Comprehensive trigger definitions for critical TSM metrics
- **Operational Documentation**: Complete runbooks for operations teams

## Project Structure

```
IBM-Storage-Protect-Zabbix/
├── scripts/                          # Main monitoring scripts
│   ├── clean_storage_protect_temp.sh      # Cleanup script for temporary files
│   ├── storage_protect_backup.sh          # Backup status monitoring
│   ├── storage_protect_container_cron.sh  # Container status collection
│   ├── storage_protect_dsmadmc.sh         # Core dsmadmc wrapper
│   ├── storage_protect_get_instances.sh   # Instance discovery
│   ├── storage_protect_pool_collector.sh  # Storage pool monitoring
│   └── storage_protect_volume_cron.sh     # Volume status collection
├── templates/                        # Zabbix templates
│   ├── zbx_export_template_discovery.yaml # Discovery template
│   └── zbx_export_template_wrapper.yaml   # Main monitoring template
├── docs/                            # Documentation
│   ├── OPERATIONS.md                     # Operations runbook for Linux team
│   └── ibm_sp_zabbix_runbook.docx       # Original operations documentation
├── configure_environment.sh         # Automated configuration script
├── validate_configuration.sh        # Configuration validation script
├── INSTALL.md                       # Detailed installation instructions
├── SECURITY.md                      # Security considerations and placeholders
├── CONTRIBUTING.md                  # Contribution guidelines
├── LICENSE                          # MIT License
├── .gitignore                       # Git ignore rules
└── README.md                        # This file (main documentation)
```

## Components

### Core Scripts

#### 1. `storage_protect_dsmadmc.sh`
Central wrapper script for all dsmadmc operations:
- Handles timeouts and process termination
- Provides retry logic with configurable attempts
- Supports multiple output formats (default, raw, csv, json, zabbix)
- Implements secure credential handling

#### 2. `storage_protect_get_instances.sh`
Instance discovery script for Zabbix LLD:
- Discovers TSM instances using server queries
- Returns JSON-formatted data for automatic host creation
- Supports IP range filtering (<TSM_NETWORK_RANGE>)
- Deduplicates discovered instances

#### 3. `storage_protect_backup.sh`
Comprehensive backup monitoring:
- Database backup age verification
- Restore functionality testing
- Expiration process monitoring
- Database and log space utilization

#### 4. Data Collection Scripts
- `storage_protect_pool_collector.sh`: Storage pool metrics
- `storage_protect_container_cron.sh`: Container status monitoring
- `storage_protect_volume_cron.sh`: Volume state tracking

#### 5. `clean_storage_protect_temp.sh`
Critical maintenance script for production stability:
- Removing stale lock files (60+ minutes old)
- Cleaning temporary files created by zabbix user
- Terminating hanging dsmadmc processes (60+ minutes old)
- **MUST be run hourly via root cron** for system stability

**Deployment Note**: This script should also be deployed to `/root/bin/clean_storage_protect_temp` for operational access.

### Zabbix Templates

#### Discovery Template (`zbx_export_template_discovery.yaml`)
- Automatic TSM instance discovery
- Host prototype creation
- Template assignment automation
- IP range filtering capabilities

#### Main Monitoring Template (`zbx_export_template_wrapper.yaml`)
- Comprehensive item definitions
- Advanced trigger configurations
- Data visualization dashboards
- Error handling and alerting

## Prerequisites

### System Requirements
- Red Hat Linux Zabbix Proxy servers
- IBM Storage Protect Client with dsmadmc CLI access
- Zabbix 7.0 or higher (Timeout=20 minimum, recommended 90)
- Bash 4.0 or higher
- Network access to TSM instances on ports 1500-1699 range

### Network Access
- **TSM Data Ports**: TCP 15NN (where NN = instance number, e.g., <TSM_INSTANCE> = port <TSM_DATA_PORT>)
- **TSM Admin Ports**: TCP 16NN (where NN = instance number, e.g., <TSM_INSTANCE> = port <TSM_ADMIN_PORT>)
- **IP Range**: <TSM_NETWORK_RANGE> (<TSM_INSTANCE_PATTERN>00 = <TSM_BASE_IP>, <TSM_INSTANCE_PATTERN>01 = <TSM_BASE_IP+1>, etc.)
- Zabbix Proxy to Zabbix Server communication
- ICMP ping access for health checks

### Credentials
- TSM administrative account for monitoring
- Zabbix external script execution permissions
- File system access for temporary files and logs

## Quick Start

### IMPORTANT: Pre-Deployment Configuration Required

**This repository uses placeholders for security.** Follow these simple steps:

### Three Simple Steps

1. **Configure**: `./configure_environment.sh` - Automated setup with validation
2. **Validate**: `./validate_configuration.sh` - Verify everything is correct  
3. **Install**: Follow [Installation Guide](#installation) below

```bash
# 1. Configure your environment (REQUIRED)
./configure_environment.sh

# 2. Validate configuration  
./validate_configuration.sh

# 3. Install (see Installation section below)
sudo cp scripts/* /usr/lib/zabbix/externalscripts/
sudo chown zabbix:zabbix /usr/lib/zabbix/externalscripts/*
sudo chmod +x /usr/lib/zabbix/externalscripts/*

# 4. Import templates in Zabbix UI
# (Import both .yaml files from templates/ directory)
```

**Need detailed guidance?** See [Additional Documentation](#additional-documentation) section.

**Estimated time:** 2.5 hours for complete deployment

### Implementation Difficulty Assessment

| **Experience Level** | **Estimated Time** | **Recommended Approach** |
|---------------------|-------------------|--------------------------|
| **Experienced Zabbix Admin** | 1.5-2 hours | Use `configure_environment.sh` + INSTALL.md |
| **Intermediate Admin** | 2-3 hours | Follow DEPLOYMENT.md step-by-step |
| **New to Zabbix/TSM** | 3-4 hours | Read all docs + get assistance |

**Prerequisites for implementation:**
- Basic Linux system administration
- Zabbix template import/configuration experience  
- TSM administrative access and knowledge
- Understanding of cron jobs and scripts

**Critical Format Requirements:**
- TSM Username: UPPERCASE letters, numbers, hyphens, underscores only
- TSM Instance Names: lowercase letters and numbers (script requirement)
- Password: No spaces, quotes, or shell special characters ($, \`, \, ")
- Network addresses: Standard IPv4/CIDR notation

## Installation

### 1. Deploy Scripts

```bash
# Create directory structure
sudo mkdir -p /usr/lib/zabbix/externalscripts
sudo mkdir -p /var/log/zabbix

# Copy scripts to external scripts directory
sudo cp scripts/* /usr/lib/zabbix/externalscripts/

# Set proper permissions
sudo chmod +x /usr/lib/zabbix/externalscripts/*.sh
sudo chown zabbix:zabbix /usr/lib/zabbix/externalscripts/*.sh

# Set up log directory
sudo chown zabbix:zabbix /var/log/zabbix
```

### 2. Configure TSM Client

Ensure the TSM client is properly configured on your Zabbix Proxy:

```bash
# Verify TSM client installation
ls -la /opt/tivoli/tsm/client/ba/bin/dsmadmc

# Test basic connectivity
/opt/tivoli/tsm/client/ba/bin/dsmadmc -se=<instance> -id=<user> -password=<pass> "q status"
```

### 3. Import Zabbix Templates

1. Import the discovery template:
   - Navigate to Configuration → Templates
   - Click Import
   - Upload `templates/zbx_export_template_discovery.yaml`

2. Import the main monitoring template:
   - Upload `templates/zbx_export_template_wrapper.yaml`

3. Configure macros:
   - `{$TSM_HOST}`: Primary TSM instance for discovery
   - `{$TSM_USER}`: TSM monitoring username
   - `{$TSM_PASS}`: TSM monitoring password

### 4. Set Up Cron Jobs

```bash
# Add to zabbix user crontab
sudo -u zabbix crontab -e

# Add these entries:
# Container status check every 10 minutes
*/10 * * * * /usr/lib/zabbix/externalscripts/storage_protect_container_cron.sh

# Volume status check every 10 minutes  
*/10 * * * * /usr/lib/zabbix/externalscripts/storage_protect_volume_cron.sh

# Cleanup temporary files hourly
0 * * * * /usr/lib/zabbix/externalscripts/clean_storage_protect_temp.sh
```

## Configuration

### Macro Configuration

| Macro | Description | Default Value |
|-------|-------------|---------------|
| `{$TSM_HOST}` | Primary TSM instance for discovery | `<TSM_INSTANCE>` |
| `{$TSM_USER}` | TSM monitoring username | `<TSM_MONITORING_USER>` |
| `{$TSM_PASS}` | TSM monitoring password | `<TSM_MONITORING_PASSWORD>` |

### Script Parameters

The main wrapper script (`storage_protect_dsmadmc.sh`) supports various parameters:

```bash
# Basic usage
./storage_protect_dsmadmc.sh -i <instance> -u <user> -p <pass> -q "<query>"

# With timeout and retries
./storage_protect_dsmadmc.sh -i <TSM_INSTANCE> -u <TSM_MONITORING_USER> -p <password> -q "q status" -t 60 -r 2

# Different output formats
./storage_protect_dsmadmc.sh -i <TSM_INSTANCE> -u <TSM_MONITORING_USER> -p <password> -q "q sessions" -f json
```

## Monitored Metrics

### Storage Pools
- Pool utilization percentage
- Capacity information
- Pool access status
- Device class and type

### Volumes
- Volume states (READONLY, OFFSITE, DESTROYED, UNAVAILABLE)
- Volume counts by state
- Access status monitoring

### Containers
- Container availability status
- Non-available container counts
- State change detection

### Administrative Tasks
- Database backup age
- Restore test results
- Expiration process status
- Database space utilization
- Log space utilization

### Sessions and Connectivity
- Active session monitoring
- Connection health checks
- Process timeout detection

## Alerting

### Critical Triggers
- Container unavailability
- Database backup age exceeding thresholds
- Failed restore tests
- High space utilization (>85%)

### Warning Triggers
- Communication timeouts
- Minor configuration issues
- Performance degradation

### Information Triggers
- Successful operations
- Status changes
- Discovery events

## Security Considerations

### Credential Management
- Use dedicated monitoring accounts with minimal privileges
- Store passwords in Zabbix macros with appropriate access controls
- Implement credential rotation procedures

### System Access
- Scripts run under zabbix user context
- Limited file system access for temporary files
- Process isolation and cleanup

### Network Security
- Restrict TSM administrative connections
- Use encrypted communications where possible
- Monitor access logs regularly

## Scaling

### Adding New Instances
1. Instances are automatically discovered within the configured IP range
2. New hosts are created using host prototypes
3. Templates are automatically assigned
4. No manual configuration required

### Performance Optimization
- Adjust polling intervals based on environment size
- Configure proxy capacity appropriately
- Monitor script execution times
- Implement queue management for large environments

## Troubleshooting

### Critical Production Issues

#### Process Chain Management and File Descriptor Limits
**Issue**: Zabbix agent triggers can create cascading file descriptor usage when the dsmadmc wrapper script spawns multiple child processes. This can lead to:
- Soft file limit exhaustion on the Zabbix proxy
- Hanging process chains when script execution is interrupted
- Memory utilization buildup leading to proxy instability
- Orphaned dsmadmc processes consuming resources

**Solutions Implemented**:
```bash
# Monitor file descriptor usage
lsof | grep zabbix | wc -l
ulimit -n  # Check current soft limit

# Check for hanging process chains
ps aux | grep dsmadmc | grep -v grep
pstree -p $(pgrep zabbix)

# Emergency cleanup of hanging processes
pkill -f "dsmadmc.*"
```

**Prevention**:
- All scripts implement comprehensive cleanup functions
- Process termination cascades to kill entire process trees
- Lock files prevent concurrent script execution
- Timeout controls limit maximum execution time

#### Memory Exhaustion from Hanging Processes (Critical Production Issue)
**Issue**: The Zabbix→wrapper→dsmadmc process chain can timeout, leaving orphaned dsmadmc processes running indefinitely. This leads to memory exhaustion and potential proxy crashes.

**Root Cause**: When the Zabbix proxy timeout (default 20s, recommended 90s) is shorter than the dsmadmc operation time, the process chain gets interrupted but child processes remain running.

**Detection Commands**:
```bash
# Monitor memory usage by TSM processes
ps aux | grep dsmadmc | awk '{sum+=$6} END {print "Total Memory (KB):", sum}'

# Check for long-running processes (over 1 hour)
ps -eo pid,etimes,cmd | awk '$2 > 3600 && $3 ~ /dsmadmc/'

# Monitor Zabbix proxy memory usage
ps aux | grep zabbix-proxy | awk '{print $6}'

# Check for large numbers of dsmadmc processes (indication of problem)
ps aux | grep dsmadmc | grep -v grep | wc -l
```

**Emergency Cleanup**:
```bash
# Kill all dsmadmc processes (emergency only)
pkill -f dsmadmc

# More targeted cleanup (recommended)
ps -eo pid,etimes,cmd | awk '$2 > 3600 && $3 ~ /dsmadmc/ {print $1}' | xargs -r kill -9
```

### Common Issues

#### Script Timeouts and Process Cleanup
```bash
# Check for hanging processes with detailed info
ps aux | grep dsmadmc
ps -eo pid,ppid,etimes,cmd | grep dsmadmc

# Force cleanup all TSM-related processes
for pid in $(pgrep -f dsmadmc); do kill -9 $pid; done

# Review timeout logs
tail -f /var/log/zabbix/sp_*_check.log
```

#### File Descriptor Exhaustion
```bash
# Check current limits and usage
ulimit -n
cat /proc/sys/fs/file-nr

# Monitor file descriptors per process
for pid in $(pgrep zabbix); do 
    echo "PID $pid: $(ls /proc/$pid/fd 2>/dev/null | wc -l) files"
done

# Increase soft limits if needed (add to /etc/security/limits.conf)
zabbix soft nofile 8192
zabbix hard nofile 16384
```

#### Authentication Failures
```bash
# Test credentials manually
/opt/tivoli/tsm/client/ba/bin/dsmadmc -se=<TSM_INSTANCE> -id=<TSM_MONITORING_USER> -password=<password> "q status"

# Check for account lockouts in TSM logs
```

#### Discovery Problems
```bash
# Test discovery script manually
./storage_protect_get_instances.sh -i <TSM_INSTANCE> -u <TSM_MONITORING_USER> -p <password>

# Verify JSON output format
./storage_protect_get_instances.sh -i <TSM_INSTANCE> -u <TSM_MONITORING_USER> -p <password> | python -m json.tool
```

#### Concurrent Execution Issues
```bash
# Check for multiple script instances
ps aux | grep storage_protect | grep -v grep

# Verify lock files are working
ls -la /tmp/*.lock

# Manual lock cleanup if needed
rm -f /tmp/sp_*.lock /tmp/dsmadmc_*.lock
```

### Log Files and Monitoring
- Container monitoring: `/var/log/zabbix/sp_container_check.log`
- Volume monitoring: `/var/log/zabbix/sp_volume_check.log`
- Cleanup operations: `/var/log/zabbix/tsm_cleanup.log`
- Process monitoring: Monitor with `journalctl -u zabbix-proxy -f`

### Debug Mode
Enable debug mode for detailed troubleshooting:
```bash
./storage_protect_dsmadmc.sh -i <TSM_INSTANCE> -u <TSM_MONITORING_USER> -p <password> -q "q status" -d

# Monitor real-time process creation
watch -n 1 'ps aux | grep dsmadmc | grep -v grep'
```

### Performance Tuning
```bash
# Adjust system limits for production
echo "zabbix soft nofile 8192" >> /etc/security/limits.conf
echo "zabbix hard nofile 16384" >> /etc/security/limits.conf

# Monitor script execution times
time ./storage_protect_dsmadmc.sh -i <TSM_INSTANCE> -u <TSM_MONITORING_USER> -p <password> -q "q status"

# Optimize polling intervals based on environment size
# Reduce from 10 minutes to 15-30 minutes for large environments
```

## Additional Documentation

If you need more detailed information or encounter issues:

| **Document** | **Purpose** | **When to Use** |
|--------------|-------------|-----------------|
| [SECURITY.md](SECURITY.md) | Complete placeholder reference | Security review or troubleshooting placeholders |
| [INSTALL.md](INSTALL.md) | Detailed installation steps | Step-by-step installation guidance |
| [docs/OPERATIONS.md](docs/OPERATIONS.md) | Operations runbook | For Linux operations team |
| [CONTRIBUTING.md](CONTRIBUTING.md) | Development guidelines | If contributing to the project |

**Most users only need the Quick Start section above!**

## Security Notice

**Important**: This repository contains placeholder values for all sensitive information. Before deployment:

1. **Run the configuration script**: `./configure_environment.sh` (handles all replacements)
2. **Never commit real credentials** to version control
3. **Use Zabbix macros** for secure credential storage

Common placeholders used:
- `<TSM_INSTANCE>` - Your TSM instance names (e.g., rb58)
- `<TSM_MONITORING_USER>` - Your monitoring username (e.g., DMS-ZABBIX)
- `<TSM_MONITORING_PASSWORD>` - Your secure password
- `<TSM_NETWORK_RANGE>` - Your network configuration (e.g., 192.168.100.0/24)

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Test thoroughly in a lab environment
5. Submit a pull request with detailed description

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Support

### Documentation
- Review the included operations runbook (`docs/ibm_sp_zabbix_runbook.docx`)
- Check IBM Storage Protect documentation: https://www.ibm.com/docs/en/storage-protect/8.1.24

### Community
- Create issues for bug reports and feature requests
- Share your experiences and improvements
- Contribute to documentation updates

## Migration from Nagios

This solution is specifically designed to replace Nagios monitoring for IBM Storage Protect environments. Key advantages:

### Improved Automation
- Automatic discovery vs. manual configuration
- Dynamic scaling vs. static definitions
- Centralized management vs. distributed configs

### Enhanced Monitoring
- JSON-structured data vs. simple status checks
- Historical data retention vs. current state only
- Advanced visualization vs. basic status pages

### Better Alerting
- Context-aware triggers vs. simple thresholds
- Dependency management vs. independent checks
- Escalation procedures vs. basic notifications

## Version History

### v1.0.0 (Current)
- Initial release with core monitoring capabilities
- Full Zabbix 7.0 template support
- Comprehensive script collection
- Operations documentation

---

**Note**: This monitoring solution is designed for production environments and has been tested with IBM Storage Protect 8.1.24 and Zabbix 7.0. Always test in a lab environment before deploying to production.
