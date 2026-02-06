# khaaliSplit

A censorship resistant way to split payments with friends and strangers!

## Repo Structure

- [`.plans`](./.plans) Plans created by Claude for executions
- `app` The Django PWA
- `contracts` Contracts deployed on EVM networks
- `indexer` Envio HyperIndex related code

## Agent Skills Used

### Application

```bash
# Python
npx skills add https://github.com/wshobson/agents --skill python-anti-patterns -a claude-code -y
npx skills add https://github.com/wshobson/agents --skill python-design-patterns -a claude-code -y
npx skills add https://github.com/wshobson/agents --skill python-testing-patterns -a claude-code -y
npx skills add https://github.com/wshobson/agents --skill python-error-handling -a claude-code -y

# Django
npx skills add https://github.com/affaan-m/everything-claude-code --skill django-security -a claude-code -y

# Postgres
npx skills add https://github.com/wshobson/agents --skill postgresql-table-design -a claude-code -y

# HTMX
npx skills add https://github.com/mindrally/skills --skill htmx -a claude-code -y
npx skills add https://github.com/oimiragieo/agent-studio --skill htmx-expert -a claude-code -y
npx skills add https://github.com/ecelayes/roots-skills --skill htmx-universal-patterns -a claude-code -y

# TailwindCSS
npx skills add https://github.com/wshobson/agents --skill design-system-patterns  -a claude-code -y
npx skills add https://github.com/jezweb/claude-skills --skill tailwind-patterns -a claude-code -y
npx skills add https://github.com/wshobson/agents --skill tailwind-design-system -a claude-code -y
npx skills add https://github.com/josiahsiegel/claude-plugin-marketplace --skill tailwindcss-animations -a claude-code -y

# DevOps
npx skills add https://github.com/sickn33/antigravity-awesome-skills --skill docker-expert -a claude-code -y

# Web3
npx skills add https://github.com/pluginagentmarketplace/custom-plugin-blockchain --skill blockchain-basics -a claude-code -y
```

### Contracts

```bash
npx skills add https://github.com/pluginagentmarketplace/custom-plugin-blockchain --skill smart-contract-security -a claude-code -y
npx skills add https://github.com/pluginagentmarketplace/custom-plugin-blockchain --skill solidity-development -a claude-code -y
npx skills add https://github.com/pseudoyu/agent-skills --skill solidity-gas-optimization -a claude-code -y
npx skills add https://github.com/wshobson/agents --skill solidity-security -a claude-code -y
npx skills add https://github.com/wshobson/agents --skill web3-testing -a claude-code -y
```
