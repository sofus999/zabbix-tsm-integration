#!/bin/bash
# IBM Storage Protect Zabbix Monitoring - Configuration Validation Script
# 
# This script checks if all required placeholders have been replaced
# Run this script AFTER configuring your environment

echo "============================================="
echo "IBM Storage Protect Configuration Validator"
echo "============================================="
echo

# Function to check file for placeholders
check_file() {
    local file="$1"
    local description="$2"
    local is_critical="$3"
    
    if [ ! -f "$file" ]; then
        echo "⚠️  File not found: $file"
        return 1
    fi
    
    local placeholders=$(grep -o '<TSM_[^>]*>' "$file" 2>/dev/null | sort | uniq)
    local count=$(echo "$placeholders" | grep -c '<TSM_' 2>/dev/null || echo "0")
    
    if [ "$count" -eq 0 ]; then
        echo "✅ $description: OK"
        return 0
    else
        if [ "$is_critical" = "true" ]; then
            echo "❌ $description: CRITICAL - $count placeholders remaining"
        else
            echo "⚠️  $description: $count placeholders remaining (optional)"
        fi
        echo "   Remaining placeholders:"
        echo "$placeholders" | sed 's/^/   - /'
        echo
        return 1
    fi
}

# Function to check credentials in scripts
check_credentials() {
    local file="$1"
    
    if [ ! -f "$file" ]; then
        echo "⚠️  File not found: $file"
        return 1
    fi
    
    local user_line=$(grep "TSM_USER=" "$file" 2>/dev/null)
    local pass_line=$(grep "TSM_PASS=" "$file" 2>/dev/null)
    
    if [[ "$user_line" == *"<TSM_MONITORING_USER>"* ]] || [[ "$pass_line" == *"<TSM_MONITORING_PASSWORD>"* ]]; then
        echo "❌ $file: CRITICAL - Contains placeholder credentials"
        return 1
    elif [[ -n "$user_line" ]] && [[ -n "$pass_line" ]]; then
        echo "✅ $file: Credentials configured"
        return 0
    else
        echo "❌ $file: CRITICAL - Missing credential configuration"
        return 1
    fi
}

echo "Checking critical files for deployment readiness..."
echo

# Check critical scripts
critical_errors=0

echo "CRITICAL SCRIPTS (Required for operation):"
echo "===========================================" 
check_credentials "scripts/storage_protect_container_cron.sh" || ((critical_errors++))
check_credentials "scripts/storage_protect_volume_cron.sh" || ((critical_errors++))

# Check templates
echo
echo "ZABBIX TEMPLATES (Required for monitoring):"
echo "==========================================="
check_file "templates/zbx_export_templates_discovery.yaml.yaml" "Discovery Template" "true" || ((critical_errors++))
check_file "templates/zbx_export_template_wrapper.yaml.yaml" "Main Template" "true" || ((critical_errors++))

# Check optional documentation files
echo
echo "DOCUMENTATION (Optional but recommended):"
echo "========================================"
check_file "README.md" "README" "false"
check_file "INSTALL.md" "Installation Guide" "false"
check_file "docs/OPERATIONS.md" "Operations Guide" "false"

echo
echo "============================================="
echo "VALIDATION SUMMARY"
echo "============================================="

if [ $critical_errors -eq 0 ]; then
    echo "🎉 SUCCESS: Configuration is ready for deployment!"
    echo
    echo "✅ All critical files are properly configured"
    echo "✅ No placeholders remain in scripts or templates"
    echo "✅ System is ready for installation"
    echo
    echo "🚀 Next Steps:"
    echo "=============="
    echo "1. Follow the installation guide: INSTALL.md"
    echo "2. Import templates into Zabbix:"
    echo "   • templates/zbx_export_templates_discovery.yaml.yaml"
    echo "   • templates/zbx_export_template_wrapper.yaml.yaml"
    echo "3. Configure Zabbix macros in web interface"
    echo "4. Set up cron jobs as per INSTALL.md"
    echo "5. Test the monitoring setup"
    echo
    echo "📖 Documentation:"
    echo "   • Installation: INSTALL.md"
    echo "   • Deployment: DEPLOYMENT.md"
    echo "   • Operations: docs/OPERATIONS.md"
    echo
else
    echo "❌ CONFIGURATION INCOMPLETE: $critical_errors critical issues found"
    echo
    echo "🔧 Required Actions:"
    echo "==================="
    echo "1. Fix the critical issues listed above"
    echo "2. Use the automated configuration script:"
    echo "   ./configure_environment.sh"
    echo "3. Run this validation script again"
    echo
    echo "💡 Need Help?"
    echo "   • Review: DEPLOYMENT.md for step-by-step guidance"
    echo "   • Use: configure_environment.sh for automated setup"
    echo "   • Check: File permissions and directory structure"
    echo
    exit 1
fi

echo
echo "✅ Configuration validation completed successfully!"
