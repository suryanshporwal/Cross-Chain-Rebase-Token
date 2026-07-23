# Cross-Chain Rebase Token

A cross-chain rebasing ERC20 token system built with Solidity, Foundry, Chainlink CCIP v2, and OpenZeppelin.

This project implements a vault-based yield mechanism where users deposit ETH and receive a rebasing token that increases in balance over time. The token can be transferred across chains using Chainlink CCIP with custom token pools.

## Features

- ERC20 rebasing token
- Time-based interest accrual
- Vault-based ETH deposits
- Chainlink CCIP v2 cross-chain transfers
- Custom CCIP TokenPool implementation
- Burn/Mint based bridging
- Foundry fork testing
- Multi-chain configuration scripts

## Architecture

```
User
 |
 | Deposit ETH
 v
Vault
 |
 | mint()
 v
RebaseToken
 |
 +----------------+
 |                |
 v                v
TokenPool      Remote Pool
 |
 |---- CCIP -----|
 |
 v
Remote Token
```

## Rebase Token

The RebaseToken dynamically calculates user balances based on:

- Principal balance
- User interest rate
- Time elapsed

Balance growth:

```
Current Balance =
Principal Balance * (1 + Interest Rate * Time Passed)
```

Interest is materialized during:

- mint
- burn
- transfer
- transferFrom

## Vault

Users deposit ETH into the Vault and receive Rebase Tokens.

Flow:

```
User -> Vault -> RebaseToken
```

The Vault is granted minting permissions.

## Cross Chain Architecture

The project uses Chainlink CCIP v2.

### Source Chain

```
User
 |
Router
 |
TokenPool
 |
Burn Token
```

### Destination Chain

```
Router
 |
TokenPool
 |
Mint Token
 |
Receiver
```

## RebaseTokenPool

A custom Chainlink TokenPool implementation.

Responsibilities:

- Burn tokens on the source chain
- Mint tokens on the destination chain

The pool requires mint/burn permissions from the RebaseToken contract.

## Deployment Scripts

### TokenAndPoolDeployer

Deploys:

- RebaseToken
- RebaseTokenPool

Configures:

- Mint/Burn roles
- TokenAdminRegistry
- Token pool mapping

### VaultDeployer

Deploys the Vault and grants mint permissions.

### ConfigurePoolScript

Configures remote chains with:

- Chain selectors
- Remote pools
- Remote tokens
- Rate limiter configuration

### BridgeTokensScript

Creates CCIP messages and performs token bridging.

Steps:

1. Build CCIP message
2. Calculate fees
3. Approve LINK
4. Approve token
5. Call `ccipSend`

## Testing

Foundry fork tests validate:

- Vault deposits
- Token minting
- Cross-chain transfers
- Burn/mint flow
- Destination balance updates
- Interest rate consistency

## Tech Stack

| Technology | Usage |
|---|---|
| Solidity | Smart contracts |
| Foundry | Development and testing |
| OpenZeppelin | ERC20 and access control |
| Chainlink CCIP v2 | Cross-chain messaging |
| Chainlink Local | CCIP fork testing |

## Security Considerations

Implemented:

- Access controlled mint/burn operations
- Owner controlled interest rate updates
- CCIP TokenPool validation
- Registry based pool management

Future improvements:

- More invariant testing
- Emergency pause mechanism
- Security review
- Production hardening

## Learning Outcomes

This project explores:

- ERC20 internals
- Rebasing mechanics
- Chainlink CCIP architecture
- Cross-chain token standards
- Foundry fork testing
- Multi-chain state management

## Author

**Suryansh Porwal**

Focused on Solidity, smart contract security, DeFi protocols, and blockchain infrastructure.
