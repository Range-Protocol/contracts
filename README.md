# Range Protocol

# Overview

Range Protocol is a Uniswap V2-like interface which enables providing fungible liquidity to Uniswap V3 for arbitrary liquidity provision: one-sided, lop-sided, and balanced

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
- Part of collected fee from Uniswap V3 pool is provided to vault manager as performance fee and part of notional amount is deducted from redeeming user as managing fee.
- Vault manager can update the managing and performance fee, managing fee is capped at 1% and performance fee is capped at 20%.
- Vault manager can pause and unpause the mint and burn function of the vault contract.

### Fee Mechanism
There are two types of fees i.e. performance fee and managing fee. Performance fee will be capped at 10% (1000 BPS) and at the time of vault initialisation, it will be set to 250 BPS (2.5%). The managing fee at the time of vault initialisation will be set to 0%, but it can be set up to 1% (100 BPS). Both of these fees are credited to state variables of `managerBalance0` and `managerBalance1`.

The performance fee will be applied to directly all the fees collected from Uniswap v3 pool. For example, if 1000 of token0 and 500 of token1 are collected in fees and performance fee is 250 BPS (2.5%) then the fee credited to manager in token0 is 1000 * (250 / 10000) = 25 and in token1 is 500 * (250 / 1000) = 12.5.

The managing fee will be applied on the notional value of the equity tokens being burned. For example, after burning equity tokens the amount of token0 and token1 shares calculated for the exiting user is 2000 of token0 and 1500 of token1, and the managing fee is 0.5% (50 BPS) then the fee credited to manager in token0 is 2000 * (50 / 10000) = 10 and in token1 is 1500 * (50 / 10000) = 7.5

# Tests

To build the project from a fresh `git clone`, perform the following.
1. Install dependencies using `npm install`.
2. Run the test cases using `npx hardhat test`.