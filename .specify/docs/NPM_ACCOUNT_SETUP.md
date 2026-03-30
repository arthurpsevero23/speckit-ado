# NPM Account Setup Guide

## Overview

Before publishing `@arthurpsevero23/spec-kit` to NPM, you need to:
1. Create or verify your NPM account
2. Set up the `@arthurpsevero23` scope
3. Generate an authentication token
4. Configure GitHub secrets for automated publishing

## Step 1: Verify NPM Account

### Create a new NPM account (if needed)
```bash
npm adduser
# Follow prompts to create account
# Username: (use your username, e.g., arthurpsevero23)
# Email: (your email)
# Password: (secure password)
```

### Or login to existing account
```bash
npm login
# Follow prompts with your NPM credentials
```

### Verify login
```bash
npm whoami
# Should output your username
```

## Step 2: Create or Verify Scope

### Check if scope exists
```bash
npm org ls @arthurpsevero23
```

### Create scope (if it doesn't exist)
Most scopes are automatically created when you first publish a package with that scope. If you want to create it ahead of time:

1. Go to https://www.npmjs.com
2. Click your profile icon (top right)
3. Select "Packages"
4. Look for an option to create a new organization/scope

## Step 3: Generate NPM Authentication Token

### Via NPM CLI (Recommended for Automation)
```bash
npm token create --read-only
# This creates a read-only token suitable for CI/CD
# For publishing, you need a "publish" token:

npm token create
# This creates a full-access token for publishing
# Select "Publish" when prompted for token type
```

### Via npmjs.com Web Interface
1. Go to https://www.npmjs.com
2. Click your profile icon → "Access Tokens"
3. Click "Generate New Token"
4. Select "Publish" (to publish packages)
5. Name the token (e.g., "github-actions-publish")
6. Copy the token immediately (you won't see it again)

## Step 4: Configure GitHub Secrets

### Add NPM_TOKEN to GitHub Repository

1. Go to your GitHub repository: https://github.com/arthurpsevero23/spec-kit-poc
2. Click "Settings" (top right)
3. In left sidebar, click "Secrets and variables" → "Actions"
4. Click "New repository secret"
5. Create secret named: `NPM_TOKEN`
6. Paste your NPM token value
7. Click "Add secret"

### Verify GitHub Secret
- In GitHub Settings → Secrets, you should see `NPM_TOKEN` listed
- The token value is hidden and masked for security

## Step 5: Test the Configuration

### Manual Publishing Test (Optional)

Before relying on automation, you can test publishing manually:

```bash
# Ensure you're logged in
npm whoami

# Build/prepare package
npm ci

# Test publish to npm
npm publish --access public

# This will publish to: https://www.npmjs.com/package/@arthurpsevero23/spec-kit
```

### Verify on npmjs.com
Visit: https://www.npmjs.com/package/@arthurpsevero23/spec-kit

## Step 6: Enable Automated Publishing

Once your NPM token is configured as a GitHub secret, the GitHub Actions workflow will automatically:

1. **Trigger on git tag push** - When you push a tag like `v0.5.0`
2. **Verify version match** - Ensures tag version matches package.json
3. **Run tests** - If tests are configured
4. **Publish to NPM** - Using the NPM_TOKEN secret
5. **Create GitHub Release** - Automatically documented with the published version

### Publish a New Version

```bash
# 1. Update version in package.json
nano package.json  # Change "version": "0.5.0" to "0.5.1"

# 2. Commit changes
git add package.json
git commit -m "Bump version to 0.5.1"

# 3. Create and push tag (this triggers the workflow)
git tag v0.5.1
git push origin main
git push origin v0.5.1

# 4. Watch the workflow
# Go to GitHub → Actions tab → "Publish to NPM"
# Should complete in 1-2 minutes
```

## Troubleshooting

### Error: "npm ERR! code E401 Unauthorized"
- **Cause**: NPM token is invalid or expired
- **Solution**: 
  1. Regenerate token on npmjs.com
  2. Update GitHub secret with new token
  3. Test login with `npm login`

### Error: "You do not have permission to publish to [@arthurpsevero23/spec-kit]"
- **Cause**: Scope ownership issue
- **Solution**:
  1. Verify scope is owned by your account at npmjs.com
  2. Ensure you're publishing with correct scope name (must match package.json)
  3. Contact npm support if scope is unavailable

### Error: "Version in package.json does not match the tag"
- **Cause**: Version mismatch between tag and package.json
- **Solution**:
  1. Update package.json version to match tag (v0.5.1 → 0.5.1)
  2. Commit the change
  3. Create the tag again
  4. Push both commit and tag

### Workflow appears stuck
- **Cause**: GitHub Actions might be disabled or waiting for approval
- **Solution**:
  1. Go to repository Settings → Actions → General
  2. Ensure "Actions permissions" is set to "Allow all actions"
  3. Check workflow file for any approval steps

## Next Steps

1. ✅ Create NPM account (if not done)
2. ✅ Generate NPM token
3. ✅ Add NPM_TOKEN to GitHub secrets
4. ✅ Test manual publish (optional but recommended)
5. ✅ Push first tag to trigger workflow: `git tag v0.5.0 && git push origin v0.5.0`
6. ✅ Verify package on https://www.npmjs.com/package/@arthurpsevero23/spec-kit
7. ✅ Create installation guide for other repositories

## Useful Commands

```bash
# Check current NPM version
npm --version

# List your NPM tokens
npm token list

# Revoke a token (if compromised)
npm token revoke <token-id>

# View package info
npm info @arthurpsevero23/spec-kit

# Install in another project
npm install @arthurpsevero23/spec-kit

# Update to latest version
npm update @arthurpsevero23/spec-kit
```

## Security Best Practices

1. **Use automation tokens**: Prefer "publish" or "read-only" tokens over full profiles
2. **Rotate tokens regularly**: Generate new tokens every 3-6 months
3. **Limit token scope**: Use least-privileged tokens
4. **Secure GitHub secrets**: Never share token values; use GitHub's secret management
5. **Monitor deployments**: Check GitHub Actions logs for unexpected publishes
6. **Use branch protection**: Require reviews before pushing tags to main

## Resources

- NPM Official Docs: https://docs.npmjs.com/
- Creating Access Tokens: https://docs.npmjs.com/creating-and-viewing-access-tokens
- GitHub Secrets: https://docs.github.com/en/actions/security-guides/encrypted-secrets
- Scoped Packages: https://docs.npmjs.com/about/scopes
