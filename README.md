# Range Protocol
- Total Prize Pool: Sum of below awards

- Join [C4 Discord](https://discord.gg/code4rena) to register
- Submit findings [using the C4 form]()
- [Read our guidelines for more details](https://docs.code4rena.com/roles/wardens)
- Starts  March 08, 2023 20:00 UTC
- Ends March 15, 2023 20:00 UTC

## Automated Findings / Publicly Known Issues

Automated findings output for the contest can be found [here](https://gist.github.com/Picodes/01427c59b07c651699136589541159a7) within an hour of contest opening.

*Note for C4 wardens: Anything included in the automated findings output is considered a publicly known issue and is ineligible for awards.*

# Overview

Range Protocol is a Uniswap V2-like interface which enables providing fungible liquidity to Uniswap V3 for arbitrary liquidity provision: one-sided, lop-sided, and balanced

- Twitter [@Range_Protocol](https://t.co/MvReUgHkld)
- Discord (https://t.co/MvReUgHkld)

[Range Protocol](https://www.rangeprotocol.com/) is a Uniswap V3 liquidity provision system consisting of:
- [RangeProtocolFactory.sol](https://github.com/Range-Protocol/contracts/blob/master/contracts/RangeProtocolFactory.sol) contract that allows creating of Range Protocol vaults. It creates `ERC1967` proxies in front of provided implementation contracts.
- [RangeProtocolVault.sol](https://github.com/Range-Protocol/contracts/blob/master/contracts/RangeProtocolVault.sol) contract that allows Uniswap liquidity provision through `mint` and `addLiquidity` functions. It's an upgradeable contract and implements Openzeppelin's `UUPSUpgradeable` proxy pattern.
- [RangeProtocolVaultStorage.sol](https://github.com/Range-Protocol/contracts/blob/master/contracts/RangeProtocolVaultStorage.sol) contract for storing storage variables for `RangeProtocolVault` contract.
- [Ownable.sol](https://github.com/Range-Protocol/range-protocol-vault/blob/main/contracts/abstract/Ownable.sol) contract for managing the `manager` role.
The Range Protocol operates as follows:
- A factory contract is deployed by a factory manager.
- The factory manager creates a vault for Uniswap V3 pair providing `token0`, `token1` and `fee` for the pair along with the `implementation` and `initialize data` specific to implementation.
- The minting on the vault contract is not started until the vault manager calls `updateTicks` on the vault and provides the tick range for liquidity provision. Updating the ticks starts the minting process and changes pool status to `in the position`.
- Anyone wanting to mint calls `getMintAmounts` with `token0` and `token1` they want to provide liquidity with and the function returns the `mintAmount` to be provided to `mint` function for liquidity into the vault's current ticks. This mints fungible vault shares to mint representing their share of the vault.
- Anyone wanting to exit from vault can call `burn` function with the amount of owned vault shares they want to burn. This burns portion of active liquidity from Uniswap V3 pool equivalent to user's share of the pool and returns user the resulting token amounts along with the user's share from inactive liquidity (fees collected + unprovisioned liquidity) from the vault.
- At the times of high volatility, vault manager can remove liquidity from current tick range making all the vault liquidity inactive. The vault's status is changed to `out of the position` yet minting continues based on the `token0` and `token1` ratio in the pool and users are minted vault shares based on this ratio. If the total supply goes to zero while the pool is `out of the position` then minting is stopped since at that point there will be no reference ratio to mint vault shares based upon. The vault must update the ticks to start accepting liquidity into a newer tick range.
- Vault manager can perform swap between `token0` and `token1` to convert assets to a specific ratio using `swap` function for providing liquidity to newer tick range through `addLiquidity` function. 
- Part of collected fee from Uniswap V3 pool is provided to vault manager and treasury. Treasury fee is fixed at 2.5% while the manager fee is capped at 10% of the total accrued fee.
- Manager can update the manager fee which is maxed at 10%.

# Scope

The only contracts that are in scope for this contest are the four listed below, excluding any concerns regarding centralization or malicious administrator risk.

| Contract                                                                                                                        | SLOC | 
|---------------------------------------------------------------------------------------------------------------------------------|--| 
| [RangeProtocolFactory.sol](https://github.com/Range-Protocol/range-protocol-vault/blob/main/contracts/RangeProtocolFactory.sol) | 121 | 
| [RangeProtocolVault.sol](https://github.com/Range-Protocol/range-protocol-vault/blob/main/contracts/RangeProtocolVault.sol)     | 735 |
| [RangeProtocolVaultStorage.sol](https://github.com/Range-Protocol/range-protocol-vault/blob/main/contracts/RangeProtocolVaultStorage.sol) | 32 | 
| [Ownable.sol](https://github.com/Range-Protocol/range-protocol-vault/blob/main/contracts/abstract/Ownable.sol)                  | 60 |

## Out of scope

Every file and contract function **not explicitly listed above is considered out of scope** for this contest in terms of both security and gas optimization. Any changes to the smart contracts which are stylistic in nature are also out of scope.

This also includes the `IRangeProtocolFactory` and `IRangeProtocolVault` interface contracts, and `TickMath` and `LiquidityAmounts` Uniswap V3 contracts.

This also includes **any** OpenZeppelin dependencies being imported. We assume these contracts to be safe. We know there may exist more gas-optimized alternatives to these contracts but that consideration remains out of scope.

## Scoping Details
```
- If you have a public code repo, please share it here: This contest repo is the only public code repo at this time.
- How many contracts are in scope?: 4
- Total SLoC for these contracts?: 948
- How many external imports are there?: 12
- How many separate interfaces and struct definitions are there for the contracts within scope?: 2
- Does most of your code generally use composition or inheritance?: Inheritance
- How many external calls?: two contracts: uniswap pool and factory
- What is the overall line coverage percentage provided by your tests?: above 90%
- Is there a need to understand a separate part of the codebase / get context in order to audit this part of the protocol?: True
- Please describe required context: Range Protocol is a Uniswap V2-like interface which enables providing fungible liquidity to Uniswap V3 for arbitrary liquidity provision: one-sided, lop-sided, and balanced.
- Does it use an oracle?: No
- Does the token conform to the ERC20 standard?: True
- Are there any novel or unique curve logic or mathematical models?: No.
- Does it use a timelock function?: No
- Is it an NFT?: No
- Does it have an AMM?: True
- Is it a fork of a popular project?: No  
- Does it use rollups?: No
- Is it multi-chain?: No
- Does it use a side-chain?: No
- Describe any specific areas you would like addressed: We are most particularly concerned about ensuring that there is no attack vector that can mint the vault shares inaccurately and not based on tick range when vault is in the position and `token0` and `token1` ratio when vault is out of the position.
```

# Tests

To build the project from a fresh `git clone`, perform the following.
1. Install dependencies using `npm install`.
2. Run the test cases using `npx hardhat test`.