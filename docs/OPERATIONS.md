# IBM Storage Protect Zabbix Monitoring - Operations Runbook

**Prepared for Linux Operations Team**

## Quick Reference

### Key File Locations

| Component | Location |
|-----------|----------|
| External Scripts | `/usr/lib/zabbix/externalscripts/` |
| Cleanup Helper | `/root/bin/clean_storage_protect_temp` |
| Zabbix Proxy Config | `/etc/zabbix/zabbix_proxy.conf` |
| Log Files | `/var/log/zabbix/sp_*.log` |
| Logrotate Config | `/etc/logrotate.d/storage-protect` |
| TSM Client Binaries | `/opt/tivoli/tsm/client/ba/bin/` |

### Critical Settings

| Setting | Value | Notes |
|---------|-------|-------|
| Zabbix Proxy Timeout | 90 | **CRITICAL**: Default 20 causes hanging processes |
| External Scripts Path | `/usr/lib/zabbix/externalscripts` | Must be configured in proxy |
| Cleanup Frequency | Hourly (root cron) | **REQUIRED** for system stability |
| Log Rotation | Weekly | Prevents disk space issues |

### Network Configuration

| Instance Pattern | IP Address | Data Port | Admin Port |
|------------------|------------|-----------|------------|
| <TSM_INSTANCE_PATTERN>00 | <TSM_BASE_IP> | <TSM_DATA_PORT> | <TSM_ADMIN_PORT> |
| <TSM_INSTANCE_PATTERN>01 | <TSM_BASE_IP+1> | <TSM_DATA_PORT+1> | <TSM_ADMIN_PORT+1> |
| <TSM_INSTANCE_PATTERN>NN | <TSM_BASE_IP_PREFIX>.1NN | 15NN | 16NN |
| <TSM_INSTANCE_PATTERN>99 | <TSM_BASE_IP+99> | <TSM_DATA_PORT+99> | <TSM_ADMIN_PORT+99> |

## Critical Production Issues

### Process Hanging (HIGH PRIORITY)

**Symptoms**:
- High memory usage on Zabbix proxy
- Large number of dsmadmc processes
- Zabbix proxy performance degradation

**Detection**:
```bash
# Check for hanging processes
ps aux | grep dsmadmc | grep -v grep | wc -l

# Check memory usage
ps aux | grep dsmadmc | awk '{sum+=$6} END {print "Total Memory (KB):", sum}'

# Check long-running processes (over 1 hour)
ps -eo pid,etimes,cmd | awk '$2 > 3600 && $3 ~ /dsmadmc/'
```

**Emergency Response**:
```bash
# Kill all hanging dsmadmc processes
for pid in $(pgrep -f dsmadmc); do kill -9 $pid; done

# Run cleanup manually
sudo /root/bin/clean_storage_protect_temp

# Check proxy status
systemctl status zabbix-proxy
```

### File Descriptor Exhaustion

**Detection**:
```bash
# Check current usage
lsof | grep zabbix | wc -l

# Check limits
sudo -u zabbix bash -c 'ulimit -n'

# Monitor per-process
for pid in $(pgrep zabbix); do 
    echo "PID $pid: $(ls /proc/$pid/fd 2>/dev/null | wc -l) files"
done
```

**Resolution**:
- Verify system limits are configured (see installation guide)
- Run cleanup script manually
- Restart zabbix-proxy if needed

## Daily Operations

### Health Check Procedure

```bash
# 1. Check Zabbix proxy status
systemctl status zabbix-proxy

# 2. Check for hanging processes
ps aux | grep dsmadmc | grep -v grep

# 3. Review recent logs
tail -n 50 /var/log/zabbix/sp_volume_check.log
tail -n 50 /var/log/zabbix/sp_container_check.log

# 4. Check memory usage
ps aux | grep zabbix-proxy | awk '{print $6}'

# 5. Verify cron jobs are running
sudo -u zabbix crontab -l
sudo crontab -l | grep clean_storage_protect
```

### Log Monitoring

**Key log files to monitor**:
- `/var/log/zabbix/sp_volume_check.log`
- `/var/log/zabbix/sp_container_check.log`
- `/var/log/zabbix/zabbix_proxy.log`

**Important log patterns**:
```bash
# Check for authentication failures
grep -i "auth" /var/log/zabbix/sp_*.log

# Check for timeout issues
grep -i "timeout" /var/log/zabbix/sp_*.log

# Check for process cleanup
grep -i "cleanup" /var/log/zabbix/sp_*.log
```

## Troubleshooting Guide

### No Data in Zabbix

**Steps**:
1. Check if scripts are executable:
   ```bash
   ls -la /usr/lib/zabbix/externalscripts/storage_protect_*
   ```

2. Test manual execution:
   ```bash
   sudo -u zabbix /usr/lib/zabbix/externalscripts/storage_protect_dsmadmc.sh \
     -i <TSM_INSTANCE> -u "<TSM_MONITORING_USER>" -p "<TSM_MONITORING_PASSWORD>" -q "q status" -t 45
   ```

3. Check network connectivity:
   ```bash
   telnet <TSM_INSTANCE_IP> <TSM_DATA_PORT>  # Test data port
telnet <TSM_INSTANCE_IP> <TSM_ADMIN_PORT>  # Test admin port
   ```

4. Review proxy logs:
   ```bash
   tail -f /var/log/zabbix/zabbix_proxy.log
   ```

### Script Timeouts

**Common causes**:
- Zabbix proxy timeout too low (should be 90s)
- Network latency to TSM instances
- TSM server performance issues

**Resolution**:
1. Check proxy timeout setting:
   ```bash
   grep "^Timeout" /etc/zabbix/zabbix_proxy.conf
   ```

2. If not 90, update and restart:
   ```bash
   sudo sed -i 's/^Timeout=.*/Timeout=90/' /etc/zabbix/zabbix_proxy.conf
   sudo systemctl restart zabbix-proxy
   ```

3. Test individual instance:
   ```bash
   time sudo -u zabbix /usr/lib/zabbix/externalscripts/storage_protect_dsmadmc.sh \
     -i <TSM_INSTANCE> -u "<TSM_MONITORING_USER>" -p "<TSM_MONITORING_PASSWORD>" -q "q status" -t 45
   ```

### Authentication Issues

**Check TSM error logs**:
```bash
# Check for authentication errors
ls /var/log/<organization>/dsmerror_<TSM_INSTANCE_PATTERN>*.log
tail -f /var/log/<organization>/dsmerror_<TSM_INSTANCE>.log
```

**Test credentials manually**:
```bash
/opt/tivoli/tsm/client/ba/bin/dsmadmc -se=<TSM_INSTANCE> \
  -id="<TSM_MONITORING_USER>" -password="<TSM_MONITORING_PASSWORD>" "q status"
```

### Discovery Issues

**Test discovery manually**:
```bash
sudo -u zabbix /usr/lib/zabbix/externalscripts/storage_protect_get_instances.sh \
  -i <TSM_INSTANCE> -u "<TSM_MONITORING_USER>" -p "<TSM_MONITORING_PASSWORD>"
```

**Validate JSON output**:
```bash
sudo -u zabbix /usr/lib/zabbix/externalscripts/storage_protect_get_instances.sh \
  -i <TSM_INSTANCE> -u "<TSM_MONITORING_USER>" -p "<TSM_MONITORING_PASSWORD>" | python -m json.tool
```

## 📋 Maintenance Procedures

### Restart Procedure

```bash
# 1. Stop data collection
sudo -u zabbix crontab -r  # Remove cron jobs temporarily

# 2. Clean up processes
sudo /root/bin/clean_storage_protect_temp

# 3. Restart proxy
sudo systemctl restart zabbix-proxy

# 4. Verify startup
sudo systemctl status zabbix-proxy

# 5. Restore cron jobs
# Re-add the cron entries as per installation guide
```

### Script Updates

```bash
# 1. Backup current scripts
sudo cp -r /usr/lib/zabbix/externalscripts/ /root/backup-$(date +%Y%m%d)/

# 2. Install new scripts
sudo install -o zabbix -g zabbix -m 0750 new_scripts/*.sh /usr/lib/zabbix/externalscripts/
sudo install -o root -g root -m 0750 new_scripts/clean_storage_protect_temp /root/bin/

# 3. Test functionality
sudo -u zabbix /usr/lib/zabbix/externalscripts/storage_protect_dsmadmc.sh

# 4. Monitor logs for issues
tail -f /var/log/zabbix/sp_*.log
```

### Performance Optimization

**For large environments (>50 instances)**:
1. Adjust cron intervals from 10 to 15-30 minutes
2. Monitor system resource usage
3. Consider splitting across multiple proxies

```bash
# Monitor resource usage during peak collection
watch -n 5 'ps aux | grep -E "(zabbix|dsmadmc)" | head -20'
```

## Emergency Procedures

### Proxy Crash Recovery

```bash
# 1. Check system resources
free -h
df -h

# 2. Kill all TSM processes
pkill -f dsmadmc

# 3. Clean up files
sudo /root/bin/clean_storage_protect_temp

# 4. Check proxy configuration
sudo zabbix_proxy -c /etc/zabbix/zabbix_proxy.conf -t

# 5. Restart proxy
sudo systemctl restart zabbix-proxy

# 6. Monitor startup
journalctl -u zabbix-proxy -f
```

### Disk Space Issues

```bash
# Check log sizes
du -sh /var/log/zabbix/sp_*.log

# Force log rotation
sudo logrotate -f /etc/logrotate.d/storage-protect

# Clean old temp files
find /tmp -name "dsmadmc_*.lock" -mtime +1 -delete
find /tmp -name "tmp.*" -user zabbix -mtime +1 -delete
```

## 📞 Escalation

### When to Escalate

- Multiple proxy crashes within 24 hours
- Persistent authentication failures across multiple instances
- Network connectivity issues to TSM infrastructure
- Zabbix template or configuration issues

### Information to Collect

```bash
# System status
systemctl status zabbix-proxy
ps aux | grep dsmadmc | wc -l
free -h
df -h

# Recent logs
tail -n 100 /var/log/zabbix/sp_*.log
tail -n 100 /var/log/zabbix/zabbix_proxy.log

# Configuration
grep -E "^(Timeout|ExternalScripts)" /etc/zabbix/zabbix_proxy.conf
sudo -u zabbix bash -c 'ulimit -a'
```

## Additional Resources

- Main documentation: [README.md](../README.md)
- Installation guide: [INSTALL.md](../INSTALL.md)
- IBM Storage Protect documentation: https://www.ibm.com/docs/en/storage-protect/8.1.24
- Zabbix proxy documentation: https://www.zabbix.com/documentation/current/manual/concepts/proxy
