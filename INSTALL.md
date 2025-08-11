# Installation Guide

This guide provides detailed step-by-step instructions for installing and configuring the IBM Storage Protect Zabbix monitoring solution.

## Prerequisites Checklist

Before beginning the installation, ensure you have:

- [ ] Red Hat Linux Zabbix Proxy server(s) with administrative access
- [ ] IBM Storage Protect Client installed with dsmadmc CLI access
- [ ] Zabbix 7.0 or higher
- [ ] Network connectivity to TSM instances (typically ports 1500-1600)
- [ ] TSM administrative credentials for monitoring
- [ ] Sudo access for installation

## System Requirements

### Hardware Requirements
- **CPU**: 2+ cores recommended for proxy servers
- **RAM**: 4GB+ recommended
- **Disk**: 10GB+ free space for logs and temporary files
- **Network**: Stable connectivity to both TSM instances and Zabbix server

### Software Requirements
- **OS**: Red Hat Enterprise Linux 7/8/9 or compatible
- **Zabbix Proxy**: Version 7.0 or higher
- **TSM Client**: IBM Storage Protect Client 8.1.x
- **Bash**: Version 4.0 or higher
- **Utilities**: ping, ps, grep, awk, sed

## Step 1: Verify Prerequisites

### 1.1 Check TSM Client Installation

```bash
# Verify dsmadmc is installed and accessible
which dsmadmc
/opt/tivoli/tsm/client/ba/bin/dsmadmc

# Check version
/opt/tivoli/tsm/client/ba/bin/dsmadmc -help | head -5
```

### 1.2 Test TSM Connectivity

```bash
# Test connection to a known TSM instance
/opt/tivoli/tsm/client/ba/bin/dsmadmc -se=<TSM_INSTANCE> -id=<TSM_MONITORING_USER> -password=<password> "q status"
```

### 1.3 Verify Zabbix Proxy

```bash
# Check Zabbix Proxy service
systemctl status zabbix-proxy

# Verify external scripts directory
ls -la /usr/lib/zabbix/externalscripts/
```

## Step 2: Download and Prepare Files

### 2.1 Clone Repository

```bash
# Clone the repository
git clone https://github.com/your-org/ibm-storage-protect-zabbix.git
cd ibm-storage-protect-zabbix
```

### 2.2 Verify File Structure

```bash
# Check that all required files are present
tree
# Expected structure:
# ├── scripts/
# │   ├── clean_storage_protect_temp.sh
# │   ├── storage_protect_backup.sh
# │   ├── storage_protect_container_cron.sh
# │   ├── storage_protect_dsmadmc.sh
# │   ├── storage_protect_get_instances.sh
# │   ├── storage_protect_pool_collector.sh
# │   └── storage_protect_volume_cron.sh
# ├── templates/
# │   ├── zbx_export_template_discovery.yaml
# │   └── zbx_export_template_wrapper.yaml
# └── docs/
```

## Step 3: System Configuration for Production

### 3.1 Configure System Limits (CRITICAL)

**IMPORTANT**: Before installing scripts, configure system limits to prevent file descriptor exhaustion and process hanging issues that can crash the Zabbix proxy.

```bash
# Edit system limits configuration
sudo nano /etc/security/limits.conf

# Add the following lines (critical for production stability):
zabbix soft nofile 8192
zabbix hard nofile 16384
zabbix soft nproc 4096
zabbix hard nproc 8192

# Verify current limits
sudo -u zabbix bash -c 'ulimit -n'
sudo -u zabbix bash -c 'ulimit -u'

# Apply limits immediately (requires zabbix service restart)
sudo systemctl restart zabbix-proxy
```

### 3.2 Configure Zabbix Proxy Timeout (CRITICAL)

**IMPORTANT**: The default Zabbix proxy timeout of 20 seconds is insufficient for TSM operations and will cause hanging processes.

```bash
# Edit Zabbix proxy configuration
sudo nano /etc/zabbix/zabbix_proxy.conf

# Find and update the Timeout setting:
Timeout=90

# Restart Zabbix proxy to apply changes
sudo systemctl restart zabbix-proxy

# Verify the service restarted successfully
sudo systemctl status zabbix-proxy
```

### 3.3 Create Required Directories

```bash
# Create external scripts directory if it doesn't exist
sudo mkdir -p /usr/lib/zabbix/externalscripts

# Create log directory
sudo mkdir -p /var/log/zabbix

# Create operational scripts directory
sudo mkdir -p /root/bin

# Set proper ownership
sudo chown zabbix:zabbix /var/log/zabbix
sudo chmod 755 /var/log/zabbix
```

### 3.4 Copy Scripts

```bash
# Copy all scripts to external scripts directory
sudo cp scripts/*.sh /usr/lib/zabbix/externalscripts/

# Copy cleanup script to operational location (for root cron and manual access)
sudo cp scripts/clean_storage_protect_temp.sh /root/bin/clean_storage_protect_temp

# Set executable permissions
sudo chmod +x /usr/lib/zabbix/externalscripts/*.sh
sudo chmod 750 /root/bin/clean_storage_protect_temp

# Set proper ownership
sudo chown zabbix:zabbix /usr/lib/zabbix/externalscripts/*.sh
sudo chown root:root /root/bin/clean_storage_protect_temp
```

### 3.5 Verify Script Installation

```bash
# List installed scripts
ls -la /usr/lib/zabbix/externalscripts/storage_protect_*

# Test the main wrapper script
sudo -u zabbix /usr/lib/zabbix/externalscripts/storage_protect_dsmadmc.sh
# Should show usage information

# Verify cleanup script installation
ls -la /root/bin/clean_storage_protect_temp
sudo /root/bin/clean_storage_protect_temp  # Should run without errors
```

## Step 4: Configure Zabbix Templates

### 4.1 Import Discovery Template

1. Open Zabbix Web Interface
2. Navigate to **Configuration** → **Templates**
3. Click **Import**
4. Select `templates/zbx_export_template_discovery.yaml`
5. Click **Import**
6. Verify template "Discover IBM Storage Protect Instances" is created

### 4.2 Import Main Monitoring Template

1. In Zabbix Web Interface, go to **Configuration** → **Templates**
2. Click **Import**
3. Select `templates/zbx_export_template_wrapper.yaml`
4. Click **Import**
5. Verify template "Template IBM Storage Protect Wrapper" is created

### 4.3 Configure Global Macros

1. Navigate to **Administration** → **General** → **Macros**
2. Add the following macros:

| Macro | Value | Description |
|-------|-------|-------------|
| `{$TSM_HOST}` | `<TSM_INSTANCE>` | Primary TSM instance for discovery |
| `{$TSM_USER}` | `<TSM_MONITORING_USER>` | TSM monitoring username |
| `{$TSM_PASS}` | `<TSM_MONITORING_PASSWORD>` | TSM monitoring password |

**Important**: Use a dedicated TSM account with minimal required privileges.

## Step 5: Set Up Automated Data Collection

### 5.1 Configure Cron Jobs

```bash
# Edit zabbix user crontab
sudo -u zabbix crontab -e

# Add the following entries:
# Container status check every 10 minutes
*/10 * * * * /usr/lib/zabbix/externalscripts/storage_protect_container_cron.sh >> /var/log/zabbix/sp_container_check.log 2>&1

# Volume status check every 10 minutes  
*/10 * * * * /usr/lib/zabbix/externalscripts/storage_protect_volume_cron.sh >> /var/log/zabbix/sp_volume_check.log 2>&1
```

**Set up root cron for cleanup (CRITICAL for stability)**:
```bash
# Edit root crontab
sudo crontab -e

# Add this entry (REQUIRED for production stability):
0 * * * * /root/bin/clean_storage_protect_temp >/dev/null 2>&1
```

### 5.2 Verify Cron Configuration

```bash
# List zabbix user's cron jobs
sudo -u zabbix crontab -l

# Check if scripts can execute
sudo -u zabbix /usr/lib/zabbix/externalscripts/clean_storage_protect_temp.sh

# Test root cleanup script
sudo /root/bin/clean_storage_protect_temp
```

## Step 6: Test Installation

### 6.1 Test System Limits and Resource Management

```bash
# Verify system limits are applied
sudo -u zabbix bash -c 'ulimit -n'  # Should show 8192
sudo -u zabbix bash -c 'ulimit -u'  # Should show 4096

# Test file descriptor monitoring
sudo -u zabbix bash -c 'ls /proc/self/fd | wc -l'
```

### 6.2 Test Script Functionality

```bash
# Test the main wrapper script with timeout monitoring
sudo -u zabbix /usr/lib/zabbix/externalscripts/storage_protect_dsmadmc.sh \
  -i <TSM_INSTANCE> -u <TSM_MONITORING_USER> -p <TSM_MONITORING_PASSWORD> -q "q status" -t 30

# Monitor process creation during test
watch -n 1 'ps aux | grep dsmadmc | grep -v grep'

# Test discovery script
sudo -u zabbix /usr/lib/zabbix/externalscripts/storage_protect_get_instances.sh \
  -i <TSM_INSTANCE> -u <TSM_MONITORING_USER> -p <TSM_MONITORING_PASSWORD>

# Test process cleanup after script completion
ps aux | grep dsmadmc | grep -v grep  # Should show no hanging processes
```

### 6.3 Test Template Discovery

1. In Zabbix, create a new host or use existing proxy host
2. Assign template "Discover IBM Storage Protect Instances"
3. Wait for discovery to run (check in **Monitoring** → **Discovery**)
4. Verify new hosts are created for discovered TSM instances

### 6.4 Verify Data Collection and Process Management

1. Check that new hosts have the wrapper template assigned
2. Go to **Monitoring** → **Latest data**
3. Verify data is being collected for TSM metrics
4. Check log files for any errors:

```bash
# Check log files for errors
tail -f /var/log/zabbix/sp_container_check.log
tail -f /var/log/zabbix/sp_volume_check.log
tail -f /var/log/zabbix/tsm_cleanup.log

# Monitor for hanging processes (should be empty after data collection)
ps aux | grep dsmadmc | grep -v grep

# Check file descriptor usage during collection
lsof | grep zabbix | wc -l

# Monitor memory usage during collection cycles
watch -n 5 'ps aux | grep zabbix-proxy | awk "{print \$6}"'
```

## Step 7: Configure Log Rotation

Set up log rotation to prevent disk space issues:

```bash
# Create logrotate configuration
sudo nano /etc/logrotate.d/storage-protect

# Add the following content:
/var/log/zabbix/sp_volume_check.log /var/log/zabbix/sp_container_check.log {
    weekly
    rotate 1
    missingok
    notifempty
    create 0664 zabbix zabbix
}

# Test logrotate configuration
sudo logrotate -d /etc/logrotate.d/storage-protect
```

## Step 8: Configure Alerting

### 8.1 Set Up Action Rules

1. Navigate to **Configuration** → **Actions** → **Trigger actions**
2. Create new action for Storage Protect alerts
3. Configure conditions:
   - Trigger name contains "IBM SP:"
   - Host groups contains "Storage Protect Instances"
4. Set up operations for notifications

### 8.2 Customize Trigger Thresholds

Review and adjust trigger thresholds in the templates:
- Database backup age warnings
- Space utilization alerts
- Container availability thresholds

## Post-Installation Checklist

- [ ] All scripts installed with correct permissions
- [ ] Templates imported successfully
- [ ] Macros configured with correct credentials
- [ ] Cron jobs set up and running
- [ ] Discovery working and creating hosts
- [ ] Data collection functioning
- [ ] Log files show no critical errors
- [ ] Alerting configured and tested

## Troubleshooting

### Critical Production Issues

#### Process Hanging and Memory Exhaustion
```bash
# Emergency process cleanup
for pid in $(pgrep -f dsmadmc); do kill -9 $pid; done

# Check for process chains
pstree -p $(pgrep zabbix)

# Monitor memory usage trends
ps aux | grep dsmadmc | awk '{sum+=$6} END {print "Total TSM Memory (KB):", sum}'

# Check file descriptor usage
lsof | grep zabbix | wc -l
sudo -u zabbix bash -c 'ulimit -n'
```

#### File Descriptor Exhaustion
```bash
# Check current system-wide usage
cat /proc/sys/fs/file-nr

# Monitor per-process file descriptors
for pid in $(pgrep zabbix); do 
    echo "PID $pid: $(ls /proc/$pid/fd 2>/dev/null | wc -l) files"
done

# Check if limits need adjustment
sudo -u zabbix bash -c 'ulimit -n'  # Should be 8192
```

### Common Issues

#### Scripts Not Executing
```bash
# Check permissions
ls -la /usr/lib/zabbix/externalscripts/storage_protect_*

# Verify zabbix user can access TSM client
sudo -u zabbix /opt/tivoli/tsm/client/ba/bin/dsmadmc -help

# Check system limits
sudo -u zabbix bash -c 'ulimit -a'
```

#### No Data in Zabbix
```bash
# Check Zabbix agent/proxy logs
tail -f /var/log/zabbix/zabbix_proxy.log

# Test external script manually
sudo -u zabbix /usr/lib/zabbix/externalscripts/storage_protect_get_instances.sh -i <TSM_INSTANCE> -u <TSM_MONITORING_USER> -p <password>

# Monitor process creation during execution
watch -n 1 'ps aux | grep dsmadmc | grep -v grep'
```

#### Authentication Failures
- Verify TSM credentials
- Check TSM server connectivity
- Review TSM server logs for authentication attempts
- Check for account lockouts due to failed attempts

#### Timeout Issues and Hanging Processes
- Increase timeout values in scripts if needed
- Check network connectivity and latency
- Monitor TSM server performance and load
- Verify process cleanup is working correctly
- Check for file descriptor limits being reached

## Security Considerations

### Credential Security
- Use dedicated monitoring accounts
- Implement password rotation procedures
- Store passwords in Zabbix macros with restricted access
- Consider using Zabbix vault for credential storage

### System Security
- Scripts run under zabbix user context
- Limit file system access
- Monitor script execution logs
- Implement log rotation

### Network Security
- Restrict TSM administrative port access
- Use VPN or private networks where possible
- Monitor connection logs

## Next Steps

After successful installation:

1. **Performance Tuning**: Adjust polling intervals based on environment size
2. **Monitoring Optimization**: Fine-tune triggers and thresholds
3. **Documentation**: Create environment-specific runbooks
4. **Training**: Train operations staff on the new monitoring system
5. **Backup**: Implement configuration backup procedures

For additional support, consult the main [README.md](README.md) and the operations runbook in the `docs/` directory.
