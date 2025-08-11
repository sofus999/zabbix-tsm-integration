# Contributing to IBM Storage Protect Zabbix Monitoring

Thank you for your interest in contributing to this project! This document provides guidelines for contributing to the IBM Storage Protect Zabbix monitoring solution.

## How to Contribute

We welcome contributions in the following areas:
- Bug fixes and improvements
- New monitoring features
- Documentation enhancements
- Template optimizations
- Script performance improvements
- Security enhancements

## Getting Started

### Prerequisites for Development

1. **Testing Environment**
   - Access to IBM Storage Protect test instance
   - Zabbix development/test environment
   - Red Hat Linux or compatible OS for testing

2. **Required Knowledge**
   - Bash scripting
   - IBM Storage Protect (TSM) administration
   - Zabbix configuration and templating
   - JSON and YAML formats

### Setting Up Development Environment

1. Fork the repository
2. Clone your fork locally
3. Set up a test environment with:
   - Zabbix proxy/server
   - IBM Storage Protect client
   - Test TSM instance access

## 📝 Contribution Process

### 1. Before You Start

- Check existing [issues](../../issues) to avoid duplicate work
- Create an issue to discuss major changes before implementation
- Review the [project documentation](README.md) thoroughly

### 2. Making Changes

1. **Create a Feature Branch**
   ```bash
   git checkout -b feature/your-feature-name
   # or
   git checkout -b bugfix/issue-description
   ```

2. **Follow Coding Standards**
   - Use consistent indentation (4 spaces for shell scripts)
   - Add comments for complex logic
   - Follow existing naming conventions
   - Include error handling in scripts

3. **Test Your Changes**
   - Test scripts manually in your environment
   - Verify Zabbix template functionality
   - Check for performance impact
   - Ensure backward compatibility

### 3. Submitting Changes

1. **Commit Guidelines**
   ```bash
   # Use descriptive commit messages
   git commit -m "Add container monitoring timeout handling"
   
   # For bug fixes
   git commit -m "Fix authentication failure in discovery script"
   
   # For documentation
   git commit -m "Update installation guide for RHEL 9"
   ```

2. **Pull Request Process**
   - Create a pull request from your feature branch
   - Provide a clear description of changes
   - Reference any related issues
   - Include testing details

## 🧪 Testing Guidelines

### Script Testing

```bash
# Test basic functionality
./storage_protect_dsmadmc.sh -i test_instance -u user -p pass -q "q status"

# Test error handling
./storage_protect_dsmadmc.sh -i invalid_instance -u user -p pass -q "q status"

# Test timeout scenarios
./storage_protect_dsmadmc.sh -i slow_instance -u user -p pass -q "q sessions" -t 5
```

### Template Testing

1. Import templates in test Zabbix environment
2. Verify discovery rules work correctly
3. Check item collection and trigger functionality
4. Test with multiple TSM instances
5. Validate JSON output formats

### Performance Testing

- Monitor script execution times
- Check memory usage during execution
- Verify cleanup processes work correctly
- Test concurrent script execution

### Production-Critical Testing

Before contributing changes, test these critical scenarios:

```bash
# File descriptor exhaustion testing
# Monitor file descriptor usage during script execution
watch -n 1 'lsof | grep zabbix | wc -l'

# Process hanging simulation
# Kill scripts mid-execution and verify cleanup
kill -9 <script_pid>
ps aux | grep dsmadmc  # Should show no hanging processes

# Concurrent execution testing
# Run multiple scripts simultaneously and verify lock mechanisms
./script1.sh & ./script2.sh & ./script3.sh &

# Memory usage monitoring during extended runs
while true; do
    ps aux | grep dsmadmc | awk '{sum+=$6} END {print "Memory:", sum "KB"}'
    sleep 30
done
```

## 📋 Code Standards

### Shell Script Standards

```bash
#!/bin/bash
# Script description and purpose
# Author: Your Name
# Version: 1.0

set -o pipefail  # Use pipefail for better error handling

# Function naming: use lowercase with underscores
check_tsm_connectivity() {
    local instance="$1"
    local timeout="${2:-30}"
    
    # Always include parameter validation
    if [[ -z "$instance" ]]; then
        echo "Error: Instance parameter required" >&2
        return 1
    fi
    
    # Implementation here
}

# Variable naming: use uppercase for constants, lowercase for variables
readonly TSM_CLIENT_PATH="/opt/tivoli/tsm/client/ba/bin"
local result=""

# Error handling: always check return codes
if ! run_command; then
    echo "Error: Command failed" >&2
    exit 1
fi
```

### Zabbix Template Standards

- Use descriptive names for items, triggers, and discovery rules
- Include units for numeric values
- Set appropriate history and trend retention
- Use macros for configurable values
- Include proper trigger dependencies
- Add meaningful descriptions

### Documentation Standards

- Use clear, concise language
- Include practical examples
- Provide troubleshooting information
- Keep documentation up to date with code changes
- Use proper Markdown formatting

## 🐛 Bug Reports

When reporting bugs, please include:

### Bug Report Template

```
**Bug Description**
A clear description of the issue.

**Steps to Reproduce**
1. Step one
2. Step two
3. Step three

**Expected Behavior**
What should happen

**Actual Behavior**
What actually happens

**Environment**
- OS: Red Hat Enterprise Linux 8.5
- Zabbix Version: 7.0.1
- TSM Client Version: 8.1.24
- Script Version: [from git commit]

**Additional Context**
- Log outputs
- Error messages
- Configuration details
```

## 💡 Feature Requests

For feature requests, please provide:

- **Use Case**: Why is this feature needed?
- **Proposed Solution**: How should it work?
- **Alternatives**: What alternatives have you considered?
- **Implementation Ideas**: Any thoughts on implementation?

## Security Considerations

### Security Best Practices

- Never commit credentials or sensitive data
- Use parameterized queries to prevent injection
- Implement proper input validation
- Follow principle of least privilege
- Review security implications of changes

### Reporting Security Issues

For security vulnerabilities:
1. **Do not** create public issues
2. Email security concerns privately
3. Provide detailed information about the vulnerability
4. Allow time for assessment and fixing before disclosure

## Documentation Contributions

Documentation improvements are always welcome:

- Fix typos and grammatical errors
- Improve clarity and readability
- Add missing information
- Update outdated content
- Provide additional examples

### Documentation Style Guide

- Use active voice when possible
- Be concise but complete
- Include code examples for technical concepts
- Use consistent formatting
- Test all provided commands and examples

## 🏷️ Versioning and Releases

This project follows [Semantic Versioning](https://semver.org/):

- **MAJOR**: Incompatible API changes
- **MINOR**: New functionality (backward compatible)
- **PATCH**: Bug fixes (backward compatible)

### Release Process

1. Update version numbers in relevant files
2. Update CHANGELOG.md
3. Create release notes
4. Tag the release
5. Update documentation as needed

## 👥 Community Guidelines

### Code of Conduct

- Be respectful and inclusive
- Focus on constructive feedback
- Help others learn and improve
- Acknowledge contributions from others

### Communication

- Use clear, professional language
- Provide helpful feedback on pull requests
- Be patient with new contributors
- Share knowledge and best practices

## Development Tools

### Recommended Tools

- **IDE**: VS Code with Bash extensions
- **Linting**: ShellCheck for bash scripts
- **Testing**: Bats for bash script testing
- **Git**: Git with proper hooks for commit formatting

### Pre-commit Hooks

Consider setting up pre-commit hooks:

```bash
# Example pre-commit hook for shell script linting
#!/bin/bash
for file in $(git diff --cached --name-only | grep '\.sh$'); do
    shellcheck "$file" || exit 1
done
```

## 📞 Getting Help

If you need help with contributions:

1. Check the [documentation](README.md)
2. Review existing [issues](../../issues)
3. Create a new issue with your question
4. Join community discussions

## 🎉 Recognition

Contributors will be:
- Listed in the project contributors
- Mentioned in release notes for significant contributions
- Acknowledged in documentation for major improvements

Thank you for contributing to making IBM Storage Protect monitoring better for everyone!
