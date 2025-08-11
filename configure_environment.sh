#!/bin/bash
# IBM Storage Protect Zabbix Monitoring - Environment Configuration Script
# 
# This script replaces all placeholders with your environment-specific values
# Run this script BEFORE following the installation guide

set -e

echo "============================================="
echo "IBM Storage Protect Zabbix Configuration"
echo "============================================="
echo

# Validation functions based on actual TSM/Zabbix requirements
validate_username() {
    local username="$1"
    # TSM username format: letters, numbers, hyphens, underscores (TSM NODENAME standard)
    # Must match dsmadmc -id parameter expectations
    if [[ ! "$username" =~ ^[A-Z0-9_-]+$ ]]; then
        echo "❌ Invalid TSM username format. TSM usernames must be UPPERCASE letters, numbers, hyphens, and underscores only."
        echo "   Examples: DMS-ZABBIX, ZABBIX_MONITOR, MONITORING_USER"
        return 1
    fi
    if [ ${#username} -lt 3 ]; then
        echo "❌ TSM username too short. Must be at least 3 characters."
        return 1
    fi
    if [ ${#username} -gt 64 ]; then
        echo "❌ TSM username too long. TSM usernames must be 64 characters or less."
        return 1
    fi
    # Check for TSM reserved names/patterns
    if [[ "$username" =~ ^(ADMIN|ROOT|SYSTEM|GUEST)$ ]]; then
        echo "❌ Username '$username' is a reserved TSM system name. Use a different name."
        return 1
    fi
    return 0
}

validate_password() {
    local password="$1"
    # TSM password requirements based on dsmadmc expectations
    if [ ${#password} -lt 8 ]; then
        echo "❌ TSM password too short. Must be at least 8 characters for security."
        return 1
    fi
    if [ ${#password} -gt 63 ]; then
        echo "❌ TSM password too long. TSM passwords must be 63 characters or less."
        return 1
    fi
    # Check for shell-breaking characters that would break sed/bash
    if [[ "$password" =~ [\'\"\\$\`] ]]; then
        echo "❌ Password contains shell special characters (' \" \\ $ \`)"
        echo "   These characters will break the script configuration."
        echo "   Use alphanumeric characters, hyphens, underscores, @, #, %, &, !, + instead."
        return 1
    fi
    # Check for characters that might break dsmadmc
    if [[ "$password" =~ [[:space:]] ]]; then
        echo "❌ Password contains spaces. TSM passwords cannot contain spaces."
        return 1
    fi
    # Recommend strong password
    if [[ ! "$password" =~ [0-9] ]] || [[ ! "$password" =~ [A-Za-z] ]]; then
        echo "⚠️  Warning: Password should contain both letters and numbers for security."
        echo "   Continue anyway? (y/N): "
        read -n 1 confirm
        echo
        if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
            return 1
        fi
    fi
    return 0
}

validate_instance_name() {
    local instance="$1"
    # TSM server name format: matches the pattern used in discovery query and scripts
    # Must be lowercase to match rb0, rb01-rb99 pattern used in scripts
    if [[ ! "$instance" =~ ^[a-z][a-z0-9]*$ ]]; then
        echo "❌ Invalid TSM instance name format. Must be lowercase letters and numbers, starting with a letter."
        echo "   Examples: rb58, rb01, tsm1, sp2"
        echo "   Required: Lowercase only (matches script expectations)"
        return 1
    fi
    if [ ${#instance} -lt 2 ]; then
        echo "❌ TSM instance name too short. Must be at least 2 characters."
        return 1
    fi
    if [ ${#instance} -gt 16 ]; then
        echo "❌ TSM instance name too long. Must be 16 characters or less (TSM server name limit)."
        return 1
    fi
    # Validate against the pattern used in the discovery query
    if [[ "$instance" =~ ^rb[0-9]+$ ]] && [[ ${instance#rb} =~ ^0[0-9]+$ ]] && [[ ${#instance} -ne 4 ]]; then
        echo "❌ RB instance names must be exactly 4 characters (rb + 2 digits): rb01, rb58, rb99"
        echo "   Use rb0 for rb00, or rb01-rb99 format"
        return 1
    fi
    return 0
}

validate_instance_pattern() {
    local pattern="$1"
    # Pattern used in discovery query and scripts: lowercase letters only
    # Must match the pattern used in "SERVER_NAME like 'RB__'" -> lowercase for script consistency
    if [[ ! "$pattern" =~ ^[a-z]+$ ]]; then
        echo "❌ Invalid instance pattern. Must be lowercase letters only."
        echo "   Examples: rb, tsm, sp"
        echo "   Required: Lowercase only (matches script and template expectations)"
        return 1
    fi
    if [ ${#pattern} -lt 1 ]; then
        echo "❌ Instance pattern too short. Must be at least 1 character."
        return 1
    fi
    if [ ${#pattern} -gt 8 ]; then
        echo "❌ Instance pattern too long. Must be 8 characters or less (practical TSM naming limit)."
        return 1
    fi
    # Validate pattern makes sense with primary instance
    # This will be checked later when we have both values
    return 0
}

validate_network_range() {
    local network="$1"
    # Check basic CIDR format
    if [[ ! "$network" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}/[0-9]{1,2}$ ]]; then
        echo "❌ Invalid network range format. Use CIDR notation (e.g., 192.168.100.0/24)."
        return 1
    fi
    
    # Extract and validate IP components
    local ip_part="${network%/*}"
    local cidr_part="${network#*/}"
    
    IFS='.' read -ra ip_octets <<< "$ip_part"
    for octet in "${ip_octets[@]}"; do
        if [ "$octet" -gt 255 ] || [ "$octet" -lt 0 ]; then
            echo "❌ Invalid IP address in network range. Octets must be 0-255."
            return 1
        fi
    done
    
    if [ "$cidr_part" -gt 32 ] || [ "$cidr_part" -lt 8 ]; then
        echo "❌ Invalid CIDR prefix. Must be between 8 and 32."
        return 1
    fi
    
    return 0
}

validate_ip_address() {
    local ip="$1"
    # Check basic IP format
    if [[ ! "$ip" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        echo "❌ Invalid IP address format. Use dotted decimal notation (e.g., 192.168.100.100)."
        return 1
    fi
    
    IFS='.' read -ra ip_octets <<< "$ip"
    for octet in "${ip_octets[@]}"; do
        if [ "$octet" -gt 255 ] || [ "$octet" -lt 0 ]; then
            echo "❌ Invalid IP address. Octets must be 0-255."
            return 1
        fi
    done
    return 0
}

validate_organization() {
    local org="$1"
    # Check organization name: alphanumeric, spaces, hyphens, underscores
    if [[ ! "$org" =~ ^[a-zA-Z0-9\ _-]+$ ]]; then
        echo "❌ Invalid organization name. Use only letters, numbers, spaces, hyphens, and underscores."
        return 1
    fi
    if [ ${#org} -lt 2 ]; then
        echo "❌ Organization name too short. Must be at least 2 characters."
        return 1
    fi
    if [ ${#org} -gt 50 ]; then
        echo "❌ Organization name too long. Must be 50 characters or less."
        return 1
    fi
    return 0
}

# Function to prompt and validate input
prompt_and_validate() {
    local prompt="$1"
    local validator="$2"
    local is_password="$3"
    local example="$4"
    local value=""
    
    while true; do
        # Print the formatted prompt
        echo -e "$prompt"
        
        if [ "$is_password" = "true" ]; then
            read -s -p "> " value
            echo
        else
            if [ -n "$example" ]; then
                read -p "> " value
            else
                read -p "> " value
            fi
        fi
        
        if [ -z "$value" ]; then
            echo "❌ Value cannot be empty. Please try again."
            echo
            continue
        fi
        
        if $validator "$value"; then
            echo "$value"
            return 0
        fi
        echo "Please try again."
        echo
    done
}

echo "This script will gather your environment information and validate it before configuration."
echo "All inputs will be validated to prevent configuration errors."
echo

# Prompt for environment values with validation
echo "📝 Gathering Environment Information:"
echo "===================================="
echo "Please provide the following information. Each field will be validated for correct format."
echo

echo "🔑 TSM Authentication:"
echo "----------------------"
TSM_USER=$(prompt_and_validate "Enter your TSM monitoring username\n   Format: UPPERCASE letters, numbers, hyphens, underscores (3-64 chars)\n   Enter username" "validate_username" "false" "DMS-ZABBIX")
echo "✅ TSM username validated: $TSM_USER"
echo

TSM_PASS=$(prompt_and_validate "Enter your TSM monitoring password\n   Format: 8-63 characters, no spaces or quotes\n   Enter password" "validate_password" "true" "")
echo "✅ TSM password validated (length: ${#TSM_PASS} characters)"
echo

echo "🏷️  TSM Instance Configuration:"
echo "--------------------------------"
TSM_INSTANCE=$(prompt_and_validate "Enter your primary TSM instance name (used for discovery)\n   Format: Lowercase letters and numbers, starting with letter (2-16 chars)\n   Examples: rb58, rb01, tsm1\n   Enter instance name" "validate_instance_name" "false" "rb58")
echo "✅ Primary instance validated: $TSM_INSTANCE"
echo

TSM_PATTERN=$(prompt_and_validate "Enter your TSM instance pattern (common prefix)\n   Format: Lowercase letters only (1-8 chars)\n   Examples: rb (for rb01, rb02...), tsm (for tsm1, tsm2...)\n   Enter pattern" "validate_instance_pattern" "false" "rb")
echo "✅ Instance pattern validated: $TSM_PATTERN"

# Cross-validate pattern with instance
if [[ ! "$TSM_INSTANCE" =~ ^${TSM_PATTERN}[0-9]*$ ]]; then
    echo "⚠️  Warning: Instance '$TSM_INSTANCE' doesn't match pattern '$TSM_PATTERN'"
    echo "   This may cause discovery issues. Instance should start with the pattern."
    read -p "   Continue anyway? (y/N): " pattern_confirm
    if [[ ! "$pattern_confirm" =~ ^[Yy]$ ]]; then
        echo "Please restart and ensure instance name matches the pattern."
        exit 1
    fi
fi
echo

echo "🌐 Network Configuration (for documentation):"
echo "----------------------------------------------"
TSM_NETWORK=$(prompt_and_validate "Enter your TSM network range\n   Format: CIDR notation (e.g., 192.168.100.0/24)\n   This is used in documentation only\n   Enter network range" "validate_network_range" "false" "192.168.100.0/24")
echo "✅ Network range validated: $TSM_NETWORK"
echo

TSM_BASE_IP=$(prompt_and_validate "Enter your TSM base IP (first instance IP)\n   Format: IPv4 address (e.g., 192.168.100.100)\n   This is used in documentation only\n   Enter base IP" "validate_ip_address" "false" "192.168.100.100")
echo "✅ Base IP validated: $TSM_BASE_IP"
echo

echo "🏢 Organization:"
echo "----------------"
ORGANIZATION=$(prompt_and_validate "Enter your organization name (for log paths)\n   Format: Letters, numbers, spaces, hyphens, underscores (2-50 chars)\n   Enter organization name" "validate_organization" "false" "YourOrg")
echo "✅ Organization validated: $ORGANIZATION"
echo

echo
echo "Configuration Summary:"
echo "====================="
echo "TSM User: $TSM_USER"
echo "TSM Password: [HIDDEN]"
echo "Primary Instance: $TSM_INSTANCE"
echo "Instance Pattern: $TSM_PATTERN"
echo "Network Range: $TSM_NETWORK"
echo "Base IP: $TSM_BASE_IP"
echo "Organization: $ORGANIZATION"
echo

read -p "Continue with configuration? (y/N): " CONFIRM
if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
    echo "Configuration cancelled."
    exit 0
fi

# Additional validation checks
echo "🔍 Pre-Configuration Validation:"
echo "==============================="

# Check if required directories exist
if [ ! -d "scripts" ]; then
    echo "❌ Error: 'scripts' directory not found. Are you in the correct directory?"
    exit 1
fi

if [ ! -d "templates" ]; then
    echo "❌ Error: 'templates' directory not found. Are you in the correct directory?"
    exit 1
fi

# Check if critical files exist
critical_files=(
    "scripts/storage_protect_container_cron.sh"
    "scripts/storage_protect_volume_cron.sh"
    "templates/zbx_export_templates_discovery.yaml.yaml"
    "templates/zbx_export_template_wrapper.yaml.yaml"
)

missing_files=()
for file in "${critical_files[@]}"; do
    if [ ! -f "$file" ]; then
        missing_files+=("$file")
    fi
done

if [ ${#missing_files[@]} -gt 0 ]; then
    echo "❌ Error: Critical files missing:"
    printf '   - %s\n' "${missing_files[@]}"
    echo "Please ensure you have the complete project files."
    exit 1
fi

# Check if files still contain placeholders (not already configured)
already_configured=0
for file in "${critical_files[@]}"; do
    if ! grep -q "<TSM_" "$file" 2>/dev/null; then
        echo "⚠️  Warning: $file appears already configured (no placeholders found)"
        ((already_configured++))
    fi
done

if [ $already_configured -gt 0 ]; then
    echo
    read -p "⚠️  Some files appear already configured. Continue anyway? (y/N): " OVERWRITE_CONFIRM
    if [[ ! "$OVERWRITE_CONFIRM" =~ ^[Yy]$ ]]; then
        echo "Configuration cancelled. Use a fresh copy of the project if you need to reconfigure."
        exit 0
    fi
fi

echo "✅ All validation checks passed!"
echo

echo "🔧 Starting Configuration Process:"
echo "================================="

# Backup original files with timestamp
BACKUP_DIR="backup_$(date +%Y%m%d_%H%M%S)"
echo "Creating backup in $BACKUP_DIR..."
mkdir -p "$BACKUP_DIR"

# Backup critical files individually for better error handling
for file in "${critical_files[@]}"; do
    backup_path="$BACKUP_DIR/$file"
    mkdir -p "$(dirname "$backup_path")"
    if cp "$file" "$backup_path"; then
        echo "✅ Backed up: $file"
    else
        echo "❌ Failed to backup: $file"
        exit 1
    fi
done

# Escape special characters for sed
escape_for_sed() {
    echo "$1" | sed 's/[[\.*^$()+?{|]/\\&/g'
}

# Configure critical scripts (REQUIRED)
echo
echo "📝 Configuring critical scripts..."
script_files=(
    "scripts/storage_protect_container_cron.sh"
    "scripts/storage_protect_volume_cron.sh"
)

TSM_USER_ESCAPED=$(escape_for_sed "$TSM_USER")
TSM_PASS_ESCAPED=$(escape_for_sed "$TSM_PASS")

for script in "${script_files[@]}"; do
    echo "   Configuring: $script"
    
    # Use more robust sed commands with explicit delimiters
    if sed -i.tmp "s|<TSM_MONITORING_USER>|$TSM_USER_ESCAPED|g" "$script" && \
       sed -i.tmp "s|<TSM_MONITORING_PASSWORD>|$TSM_PASS_ESCAPED|g" "$script"; then
        rm -f "$script.tmp"
        echo "   ✅ Success"
    else
        echo "   ❌ Failed to configure $script"
        echo "   Restoring from backup..."
        cp "$BACKUP_DIR/$script" "$script"
        exit 1
    fi
done

# Configure templates (REQUIRED)
echo
echo "📋 Configuring Zabbix templates..."
template_files=(
    "templates/zbx_export_templates_discovery.yaml.yaml"
    "templates/zbx_export_template_wrapper.yaml.yaml"
)

TSM_INSTANCE_ESCAPED=$(escape_for_sed "$TSM_INSTANCE")
TSM_PATTERN_ESCAPED=$(escape_for_sed "$TSM_PATTERN")

for template in "${template_files[@]}"; do
    echo "   Configuring: $template"
    
    if sed -i.tmp "s|<TSM_MONITORING_USER>|$TSM_USER_ESCAPED|g" "$template" && \
       sed -i.tmp "s|<TSM_INSTANCE>|$TSM_INSTANCE_ESCAPED|g" "$template" && \
       sed -i.tmp "s|<TSM_INSTANCE_PATTERN>|$TSM_PATTERN_ESCAPED|g" "$template"; then
        rm -f "$template.tmp"
        echo "   ✅ Success"
    else
        echo "   ❌ Failed to configure $template"
        echo "   Restoring from backup..."
        cp "$BACKUP_DIR/$template" "$template"
        exit 1
    fi
done

# Configure documentation (OPTIONAL but recommended)
echo
echo "📚 Configuring documentation (optional)..."

doc_files=(
    "docs/OPERATIONS.md"
    "README.md"
    "INSTALL.md"
)

TSM_NETWORK_ESCAPED=$(escape_for_sed "$TSM_NETWORK")
TSM_BASE_IP_ESCAPED=$(escape_for_sed "$TSM_BASE_IP")
ORGANIZATION_ESCAPED=$(escape_for_sed "$ORGANIZATION")

for doc_file in "${doc_files[@]}"; do
    if [ -f "$doc_file" ]; then
        echo "   Configuring: $doc_file"
        
        # Apply all substitutions, continue even if some fail
        sed -i.tmp "s|<TSM_MONITORING_USER>|$TSM_USER_ESCAPED|g" "$doc_file" 2>/dev/null || true
        sed -i.tmp "s|<TSM_MONITORING_PASSWORD>|$TSM_PASS_ESCAPED|g" "$doc_file" 2>/dev/null || true
        sed -i.tmp "s|<TSM_INSTANCE>|$TSM_INSTANCE_ESCAPED|g" "$doc_file" 2>/dev/null || true
        sed -i.tmp "s|<TSM_INSTANCE_PATTERN>|$TSM_PATTERN_ESCAPED|g" "$doc_file" 2>/dev/null || true
        sed -i.tmp "s|<TSM_NETWORK_RANGE>|$TSM_NETWORK_ESCAPED|g" "$doc_file" 2>/dev/null || true
        sed -i.tmp "s|<TSM_BASE_IP>|$TSM_BASE_IP_ESCAPED|g" "$doc_file" 2>/dev/null || true
        sed -i.tmp "s|<organization>|$ORGANIZATION_ESCAPED|g" "$doc_file" 2>/dev/null || true
        
        rm -f "$doc_file.tmp" 2>/dev/null || true
        echo "   ✅ Configured (best effort)"
    else
        echo "   ⚠️  $doc_file not found, skipping"
    fi
done

echo
echo "🔍 Final Verification:"
echo "====================="

# Comprehensive verification of critical files
verification_passed=true

echo "Checking critical files for remaining placeholders..."
for file in "${critical_files[@]}"; do
    remaining_placeholders=$(grep -o "<TSM_[^>]*>" "$file" 2>/dev/null | wc -l)
    if [ "$remaining_placeholders" -eq 0 ]; then
        echo "   ✅ $file: All placeholders replaced"
    else
        echo "   ❌ $file: $remaining_placeholders placeholders remaining"
        grep -n "<TSM_[^>]*>" "$file" 2>/dev/null | sed 's/^/      /' || true
        verification_passed=false
    fi
done

echo
echo "Checking credential configuration..."
for script in "${script_files[@]}"; do
    user_configured=$(grep "TSM_USER=" "$script" | grep -v "<TSM_MONITORING_USER>" | wc -l)
    pass_configured=$(grep "TSM_PASS=" "$script" | grep -v "<TSM_MONITORING_PASSWORD>" | wc -l)
    
    if [ "$user_configured" -gt 0 ] && [ "$pass_configured" -gt 0 ]; then
        echo "   ✅ $script: Credentials properly configured"
    else
        echo "   ❌ $script: Credential configuration failed"
        verification_passed=false
    fi
done

echo
echo "============================================="
if [ "$verification_passed" = true ]; then
    echo "🎉 CONFIGURATION SUCCESSFUL!"
    echo "============================================="
    echo
    echo "✅ All critical files have been properly configured"
    echo "✅ No placeholders remain in scripts or templates"
    echo "✅ Credentials have been set correctly"
    echo "✅ Backup created in: $BACKUP_DIR"
    echo
    echo "📋 Configuration Summary:"
    echo "========================"
    echo "   TSM Username: $TSM_USER"
    echo "   Primary Instance: $TSM_INSTANCE"
    echo "   Instance Pattern: $TSM_PATTERN"
    echo "   Network Range: $TSM_NETWORK"
    echo "   Base IP: $TSM_BASE_IP"
    echo "   Organization: $ORGANIZATION"
    echo "   Backup Location: $BACKUP_DIR"
    echo
    echo "🚀 Next Steps:"
    echo "=============="
    echo "1. Run validation: ./validate_configuration.sh"
    echo "2. Follow installation guide: INSTALL.md"
    echo "3. Import templates into Zabbix:"
    echo "   • templates/zbx_export_templates_discovery.yaml.yaml"
    echo "   • templates/zbx_export_template_wrapper.yaml.yaml"
    echo "4. Configure Zabbix macros:"
    echo "   • {$TSM_HOST} = $TSM_INSTANCE"
    echo "   • {$TSM_USER} = $TSM_USER"
    echo "   • {$TSM_PASS} = [your secure password]"
    echo
    echo "📖 Documentation:"
    echo "   • Installation: INSTALL.md"
    echo "   • Deployment: DEPLOYMENT.md"
    echo "   • Operations: docs/OPERATIONS.md"
    echo
else
    echo "❌ CONFIGURATION FAILED!"
    echo "============================================="
    echo
    echo "Some critical issues were found during verification."
    echo "Please review the errors above and try again."
    echo
    echo "💡 Troubleshooting:"
    echo "   • Restore from backup: $BACKUP_DIR"
    echo "   • Check file permissions"
    echo "   • Verify you're in the correct directory"
    echo "   • Contact support if issues persist"
    echo
    exit 1
fi

echo "Configuration script completed successfully!"
