//SPDX-License-Identifier: MIT
pragma solidity 0.8.4;

import {SafeERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import {IERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import {SafeCastUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/math/SafeCastUpgradeable.sol";

import {IRangeProtocolVault} from "../interfaces/IRangeProtocolVault.sol";
import {TickMath} from "../pancake/TickMath.sol";
import {FullMath} from "../pancake/FullMath.sol";
import {LiquidityAmounts} from "../pancake/LiquidityAmounts.sol";

import {DataTypesLib} from "./DataTypesLib.sol";
import {PeripheryPaymentsLib} from "./PeripheryPaymentsLib.sol";
import {VaultErrors} from "../errors/VaultErrors.sol";

library LogicLib {
    using SafeERC20Upgradeable for IERC20Upgradeable;
    using TickMath for int24;

    /// Performance fee cannot be set more than 10% of the fee earned from pancake v3 pool.
    uint16 public constant MAX_PERFORMANCE_FEE_BPS = 1000;
    /// Managing fee cannot be set more than 1% of the total fee earned.
    uint16 public constant MAX_MANAGING_FEE_BPS = 100;

    event Minted(
        address indexed receiver,
        uint256 mintAmount,
        uint256 amount0In,
        uint256 amount1In
    );
    event Burned(
        address indexed receiver,
        uint256 burnAmount,
        uint256 amount0Out,
        uint256 amount1Out
    );
    event LiquidityAdded(
        uint256 liquidityMinted,
        int24 tickLower,
        int24 tickUpper,
        uint256 amount0In,
        uint256 amount1In
    );
    event LiquidityRemoved(
        uint256 liquidityRemoved,
        int24 tickLower,
        int24 tickUpper,
        uint256 amount0Out,
        uint256 amount1Out
    );
    event FeesEarned(uint256 feesEarned0, uint256 feesEarned1);
    event FeesUpdated(uint16 managingFee, uint16 performanceFee);
    event InThePositionStatusSet(bool inThePosition);
    event Swapped(bool zeroForOne, int256 amount0, int256 amount1);
    event TicksSet(int24 lowerTick, int24 upperTick);
    event MintStarted();

    /**
     * @notice updateTicks it is called by the contract manager to update the ticks.
     * It can only be called once total supply is zero and the vault has not active position
     * in the pancake pool
     * @param _lowerTick lowerTick to set
     * @param _upperTick upperTick to set
     */
    function updateTicks(
        DataTypesLib.PoolData storage poolData,
        int24 _lowerTick,
        int24 _upperTick
    ) external {
        if (IRangeProtocolVault(address(this)).totalSupply() != 0 || poolData.inThePosition)
            revert VaultErrors.NotAllowedToUpdateTicks();
        _updateTicks(poolData, _lowerTick, _upperTick);

        if (!poolData.mintStarted) {
            poolData.mintStarted = true;
            emit MintStarted();
        }
    }

    /// @notice pancakeV3MintCallback Pancake V3 callback fn, called back on pool.mint
    function pancakeV3MintCallback(
        DataTypesLib.PoolData storage poolData,
        uint256 amount0Owed,
        uint256 amount1Owed,
        bytes calldata
    ) external {
        if (msg.sender != address(poolData.pool)) revert VaultErrors.OnlyPoolAllowed();

        if (amount0Owed > 0) {
            PeripheryPaymentsLib.pay(poolData.WETH9, address(poolData.token0), address(this), msg.sender, amount0Owed);
        }

        if (amount1Owed > 0) {
            PeripheryPaymentsLib.pay(poolData.WETH9, address(poolData.token1), address(this), msg.sender, amount1Owed);
        }
    }

    /// @notice pancakeV3SwapCallback Pancake v3 callback fn, called back on pool.swap
    function pancakeV3SwapCallback(
        DataTypesLib.PoolData storage poolData,
        int256 amount0Delta,
        int256 amount1Delta,
        bytes calldata
    ) external {
        if (msg.sender != address(poolData.pool)) revert VaultErrors.OnlyPoolAllowed();

        if (amount0Delta > 0) {
            PeripheryPaymentsLib.pay(poolData.WETH9, address(poolData.token0), address(this), msg.sender, uint256(amount0Delta));
        } else if (amount1Delta > 0) {
            PeripheryPaymentsLib.pay(poolData.WETH9, address(poolData.token1), address(this), msg.sender, uint256(amount1Delta));
        }
    }

    /**
     * @notice mint mints range vault shares, fractional shares of a Pancake V3 position/strategy
     * to compute the amount of tokens necessary to mint `mintAmount` see getMintAmounts
     * @param mintAmount The number of shares to mint
     * @return amount0 amount of token0 transferred from msg.sender to mint `mintAmount`
     * @return amount1 amount of token1 transferred from msg.sender to mint `mintAmount`
     */
    function mint(
        DataTypesLib.PoolData storage poolData,
        DataTypesLib.UserData storage userData,
        DataTypesLib.FeeData storage feeData,
        uint256 mintAmount
    ) external returns (uint256 amount0, uint256 amount1) {
        if (!poolData.mintStarted) revert VaultErrors.MintNotStarted();
        if (mintAmount == 0) revert VaultErrors.InvalidMintAmount();
        IRangeProtocolVault vault = IRangeProtocolVault(address(this));
        uint256 totalSupply = vault.totalSupply();
        bool _inThePosition = poolData.inThePosition;
        (uint160 sqrtRatioX96, , , , , , ) = poolData.pool.slot0();

        if (totalSupply > 0) {
            (uint256 amount0Current, uint256 amount1Current) = getUnderlyingBalances(
                poolData,
                feeData
            );
            amount0 = FullMath.mulDivRoundingUp(amount0Current, mintAmount, totalSupply);
            amount1 = FullMath.mulDivRoundingUp(amount1Current, mintAmount, totalSupply);
        } else if (_inThePosition) {
            // If total supply is zero then inThePosition must be set to accept token0 and token1 based on currently set ticks.
            // This branch will be executed for the first mint and as well as each time total supply is to be changed from zero to non-zero.
            (amount0, amount1) = LiquidityAmounts.getAmountsForLiquidity(
                sqrtRatioX96,
                poolData.lowerTick.getSqrtRatioAtTick(),
                poolData.upperTick.getSqrtRatioAtTick(),
                SafeCastUpgradeable.toUint128(mintAmount)
            );
        } else {
            // If total supply is zero and the vault is not in the position then mint cannot be accepted based on the assumptions
            // that being out of the pool renders currently set ticks unusable and totalSupply being zero does not allow
            // calculating correct amounts of amount0 and amount1 to be accepted from the user.
            // This branch will be executed if all users remove their liquidity from the vault i.e. total supply is zero from non-zero and
            // the vault is out of the position i.e. no valid tick range to calculate the vault's mint shares.
            // Manager must call initialize function with valid tick ranges to enable the minting again.
            revert VaultErrors.MintNotAllowed();
        }

        if (!userData.vaults[msg.sender].exists) {
            userData.vaults[msg.sender].exists = true;
            userData.users.push(msg.sender);
        }
        if (amount0 > 0) {
            userData.vaults[msg.sender].token0 += amount0;
            poolData.token0.safeTransferFrom(msg.sender, address(this), amount0);
        }
        if (amount1 > 0) {
            userData.vaults[msg.sender].token1 += amount1;
            poolData.token1.safeTransferFrom(msg.sender, address(this), amount1);
        }

        vault.mintShares(msg.sender, mintAmount);
        if (_inThePosition) {
            uint128 liquidityMinted = LiquidityAmounts.getLiquidityForAmounts(
                sqrtRatioX96,
                poolData.lowerTick.getSqrtRatioAtTick(),
                poolData.upperTick.getSqrtRatioAtTick(),
                amount0,
                amount1
            );
            poolData.pool.mint(
                address(this),
                poolData.lowerTick,
                poolData.upperTick,
                liquidityMinted,
                ""
            );
        }

        emit Minted(msg.sender, mintAmount, amount0, amount1);
    }

    /**
     * @notice burn burns range vault shares (shares of a Pancake V3 position) and receive underlying
     * @param burnAmount The number of shares to burn
     * @return amount0 amount of token0 transferred to msg.sender for burning {burnAmount}
     * @return amount1 amount of token1 transferred to msg.sender for burning {burnAmount}
     */
    function burn(
        DataTypesLib.PoolData storage poolData,
        DataTypesLib.UserData storage userData,
        DataTypesLib.FeeData storage feeData,
        uint256 burnAmount,
        bool withdrawNative
    ) external returns (uint256 amount0, uint256 amount1) {
        if (burnAmount == 0) revert VaultErrors.InvalidBurnAmount();
        (amount0, amount1) = withdrawLiquidityForBurn(poolData, feeData, burnAmount);
        uint256 balanceBefore = IRangeProtocolVault(address(this)).balanceOf(msg.sender);
        IRangeProtocolVault(address(this)).burnShares(msg.sender, burnAmount);

        _applyManagingFee(feeData, amount0, amount1);
        (uint256 amount0AfterFee, uint256 amount1AfterFee) = _netManagingFees(
            feeData,
            amount0,
            amount1
        );
        if (amount0AfterFee > 0) {
            userData.vaults[msg.sender].token0 =
                (userData.vaults[msg.sender].token0 * (balanceBefore - burnAmount)) /
                balanceBefore;
            if (withdrawNative && address(poolData.token0) == poolData.WETH9) {
                PeripheryPaymentsLib.unwrapWETH9(poolData.WETH9, amount0AfterFee, msg.sender);
            } else {
                poolData.token0.safeTransfer(msg.sender, amount0AfterFee);
            }
        }
        if (amount1AfterFee > 0) {
            userData.vaults[msg.sender].token1 =
                (userData.vaults[msg.sender].token1 * (balanceBefore - burnAmount)) /
                balanceBefore;

            if (withdrawNative && address(poolData.token1) == poolData.WETH9) {
                PeripheryPaymentsLib.unwrapWETH9(poolData.WETH9, amount1AfterFee, msg.sender);
            } else {
                poolData.token1.safeTransfer(msg.sender, amount1AfterFee);
            }
        }

        emit Burned(msg.sender, burnAmount, amount0AfterFee, amount1AfterFee);
    }

    function withdrawLiquidityForBurn(
        DataTypesLib.PoolData storage poolData,
        DataTypesLib.FeeData storage feeData,
        uint256 burnAmount
    ) private returns (uint256 amount0, uint256 amount1) {
        uint256 totalSupply = IRangeProtocolVault(address(this)).totalSupply();
        if (poolData.inThePosition) {
            (uint128 liquidity, , , , ) = poolData.pool.positions(getPositionID(poolData));
            uint256 liquidityBurned_ = FullMath.mulDiv(burnAmount, liquidity, totalSupply);
            uint128 liquidityBurned = SafeCastUpgradeable.toUint128(liquidityBurned_);
            (uint256 burn0, uint256 burn1, uint256 fee0, uint256 fee1) = _withdraw(
                poolData,
                liquidityBurned
            );

            _applyPerformanceFee(feeData, fee0, fee1);
            (fee0, fee1) = _netPerformanceFees(feeData, fee0, fee1);
            emit FeesEarned(fee0, fee1);

            uint256 passiveBalance0 = poolData.token0.balanceOf(address(this)) - burn0;
            uint256 passiveBalance1 = poolData.token1.balanceOf(address(this)) - burn1;
            if (passiveBalance0 > feeData.managerBalance0)
                passiveBalance0 -= feeData.managerBalance0;
            if (passiveBalance1 > feeData.managerBalance1)
                passiveBalance1 -= feeData.managerBalance1;

            amount0 = burn0 + FullMath.mulDiv(passiveBalance0, burnAmount, totalSupply);
            amount1 = burn1 + FullMath.mulDiv(passiveBalance1, burnAmount, totalSupply);
        } else {
            (uint256 amount0Current, uint256 amount1Current) = getUnderlyingBalances(
                poolData,
                feeData
            );
            amount0 = FullMath.mulDiv(amount0Current, burnAmount, totalSupply);
            amount1 = FullMath.mulDiv(amount1Current, burnAmount, totalSupply);
        }
    }

    /**
     * @notice removeLiquidity removes liquidity from pancake pool and receives underlying tokens
     * in the vault contract.
     */
    function removeLiquidity(
        DataTypesLib.PoolData storage poolData,
        DataTypesLib.FeeData storage feeData
    ) external {
        (uint128 liquidity, , , , ) = poolData.pool.positions(getPositionID(poolData));

        if (liquidity > 0) {
            int24 _lowerTick = poolData.lowerTick;
            int24 _upperTick = poolData.upperTick;
            (uint256 amount0, uint256 amount1, uint256 fee0, uint256 fee1) = _withdraw(
                poolData,
                liquidity
            );

            emit LiquidityRemoved(liquidity, _lowerTick, _upperTick, amount0, amount1);

            _applyPerformanceFee(feeData, fee0, fee1);
            (fee0, fee1) = _netPerformanceFees(feeData, fee0, fee1);
            emit FeesEarned(fee0, fee1);
        }

        // TicksSet event is not emitted here since the emitting would create a new position on subgraph but
        // the following statement is to only disallow any liquidity provision through the vault unless done
        // by manager (taking into account any features added in future).
        poolData.lowerTick = poolData.upperTick;
        poolData.inThePosition = false;
        emit InThePositionStatusSet(false);
    }

    /**
     * @dev Mars@RangeProtocol
     * @notice swap swaps token0 for token1 (token0 in, token1 out), or token1 for token0 (token1 in token0 out).
     * Zero for one will cause the price: amount1 / amount0 lower, otherwise it will cause the price higher
     * @param zeroForOne The direction of the swap, true is swap token0 for token1, false is swap token1 to token0
     * @param swapAmount The exact input token amount of the swap
     * @param sqrtPriceLimitX96 threshold price ratio after the swap.
     * If zero for one, the price cannot be lower (swap make price lower) than this threshold value after the swap
     * If one for zero, the price cannot be greater (swap make price higher) than this threshold value after the swap
     * @return amount0 If positive represents exact input token0 amount after this swap, msg.sender paid amount,
     * or exact output token0 amount (negative), msg.sender received amount
     * @return amount1 If positive represents exact input token1 amount after this swap, msg.sender paid amount,
     * or exact output token1 amount (negative), msg.sender received amount
     */
    function swap(
        DataTypesLib.PoolData storage poolData,
        bool zeroForOne,
        int256 swapAmount,
        uint160 sqrtPriceLimitX96
    ) external returns (int256 amount0, int256 amount1) {
        (amount0, amount1) = poolData.pool.swap(
            address(this),
            zeroForOne,
            swapAmount,
            sqrtPriceLimitX96,
            ""
        );

        emit Swapped(zeroForOne, amount0, amount1);
    }

    /**
     * @dev Mars@RangeProtocol
     * @notice addLiquidity allows manager to add liquidity into pancake pool into newer tick ranges.
     * @param newLowerTick new lower tick to deposit liquidity into
     * @param newUpperTick new upper tick to deposit liquidity into
     * @param amount0 max amount of amount0 to use
     * @param amount1 max amount of amount1 to use
     * @return remainingAmount0 remaining amount from amount0
     * @return remainingAmount1 remaining amount from amount1
     */
    function addLiquidity(
        DataTypesLib.PoolData storage poolData,
        int24 newLowerTick,
        int24 newUpperTick,
        uint256 amount0,
        uint256 amount1
    ) external returns (uint256 remainingAmount0, uint256 remainingAmount1) {
        _validateTicks(newLowerTick, newUpperTick, poolData.tickSpacing);
        if (poolData.inThePosition) revert VaultErrors.LiquidityAlreadyAdded();

        (uint160 sqrtRatioX96, , , , , , ) = poolData.pool.slot0();
        uint128 baseLiquidity = LiquidityAmounts.getLiquidityForAmounts(
            sqrtRatioX96,
            newLowerTick.getSqrtRatioAtTick(),
            newUpperTick.getSqrtRatioAtTick(),
            amount0,
            amount1
        );

        if (baseLiquidity > 0) {
            (uint256 amountDeposited0, uint256 amountDeposited1) = poolData.pool.mint(
                address(this),
                newLowerTick,
                newUpperTick,
                baseLiquidity,
                ""
            );

            emit LiquidityAdded(
                baseLiquidity,
                newLowerTick,
                newUpperTick,
                amountDeposited0,
                amountDeposited1
            );

            // Should return remaining token number for swap
            remainingAmount0 = amount0 - amountDeposited0;
            remainingAmount1 = amount1 - amountDeposited1;
            poolData.lowerTick = newLowerTick;
            poolData.upperTick = newUpperTick;
            emit TicksSet(newLowerTick, newUpperTick);

            poolData.inThePosition = true;
            emit InThePositionStatusSet(true);
        }
    }

    /**
     * @dev pullFeeFromPool pulls accrued fee from pancake v3 pool that position has accrued since
     * last collection.
     */
    function pullFeeFromPool(
        DataTypesLib.PoolData storage poolData,
        DataTypesLib.FeeData storage feeData
    ) external {
        (, , uint256 fee0, uint256 fee1) = _withdraw(poolData, 0);
        _applyPerformanceFee(feeData, fee0, fee1);
        (fee0, fee1) = _netPerformanceFees(feeData, fee0, fee1);
        emit FeesEarned(fee0, fee1);
    }

    /// @notice collectManager collects manager fees accrued
    function collectManager(
        DataTypesLib.PoolData storage poolData,
        DataTypesLib.FeeData storage feeData,
        address recipient
    ) external {
        uint256 amount0 = feeData.managerBalance0;
        uint256 amount1 = feeData.managerBalance1;
        feeData.managerBalance0 = 0;
        feeData.managerBalance1 = 0;

        if (amount0 > 0) {
            poolData.token0.safeTransfer(recipient, amount0);
        }
        if (amount1 > 0) {
            poolData.token1.safeTransfer(recipient, amount1);
        }
    }

    /**
     * @notice updateFees allows updating of managing and performance fees
     */
    function updateFees(
        DataTypesLib.FeeData storage feeData,
        uint16 newManagingFee,
        uint16 newPerformanceFee
    ) external {
        if (newManagingFee > MAX_MANAGING_FEE_BPS) revert VaultErrors.InvalidManagingFee();
        if (newPerformanceFee > MAX_PERFORMANCE_FEE_BPS) revert VaultErrors.InvalidPerformanceFee();

        feeData.managingFee = newManagingFee;
        feeData.performanceFee = newPerformanceFee;
        emit FeesUpdated(newManagingFee, newPerformanceFee);
    }

    /**
     * @notice compute maximum shares that can be minted from `amount0Max` and `amount1Max`
     * @param amount0Max The maximum amount of token0 to forward on mint
     * @param amount1Max The maximum amount of token1 to forward on mint
     * @return amount0 actual amount of token0 to forward when minting `mintAmount`
     * @return amount1 actual amount of token1 to forward when minting `mintAmount`
     * @return mintAmount maximum number of shares mintable
     */
    function getMintAmounts(
        DataTypesLib.PoolData storage poolData,
        DataTypesLib.FeeData storage feeData,
        uint256 amount0Max,
        uint256 amount1Max
    ) external view returns (uint256 amount0, uint256 amount1, uint256 mintAmount) {
        if (!poolData.mintStarted) revert VaultErrors.MintNotStarted();
        uint256 totalSupply = IRangeProtocolVault(address(this)).totalSupply();
        if (totalSupply > 0) {
            (amount0, amount1, mintAmount) = _calcMintAmounts(
                poolData,
                feeData,
                totalSupply,
                amount0Max,
                amount1Max
            );
        } else {
            (uint160 sqrtRatioX96, , , , , , ) = poolData.pool.slot0();
            uint128 newLiquidity = LiquidityAmounts.getLiquidityForAmounts(
                sqrtRatioX96,
                poolData.lowerTick.getSqrtRatioAtTick(),
                poolData.upperTick.getSqrtRatioAtTick(),
                amount0Max,
                amount1Max
            );
            mintAmount = uint256(newLiquidity);
            (amount0, amount1) = LiquidityAmounts.getAmountsForLiquidity(
                sqrtRatioX96,
                poolData.lowerTick.getSqrtRatioAtTick(),
                poolData.upperTick.getSqrtRatioAtTick(),
                newLiquidity
            );
        }
    }

    /**
     * @notice compute total underlying token0 and token1 token supply at provided price
     * includes current liquidity invested in pancake position, current fees earned
     * and any uninvested leftover (but does not include manager fees accrued)
     * @param sqrtRatioX96 price to computer underlying balances at
     * @return amount0Current current total underlying balance of token0
     * @return amount1Current current total underlying balance of token1
     */
    function getUnderlyingBalancesAtPrice(
        DataTypesLib.PoolData storage poolData,
        DataTypesLib.FeeData storage feeData,
        uint160 sqrtRatioX96
    ) external view returns (uint256 amount0Current, uint256 amount1Current) {
        (, int24 tick, , , , , ) = poolData.pool.slot0();
        return _getUnderlyingBalances(poolData, feeData, sqrtRatioX96, tick);
    }

    /**
     * @notice getCurrentFees returns the current uncollected fees
     * @return fee0 uncollected fee in token0
     * @return fee1 uncollected fee in token1
     */
    function getCurrentFees(
        DataTypesLib.PoolData storage poolData,
        DataTypesLib.FeeData storage feeData
    ) public view returns (uint256 fee0, uint256 fee1) {
        (, int24 tick, , , , , ) = poolData.pool.slot0();
        (
            uint128 liquidity,
            uint256 feeGrowthInside0Last,
            uint256 feeGrowthInside1Last,
            uint128 tokensOwed0,
            uint128 tokensOwed1
        ) = poolData.pool.positions(getPositionID(poolData));
        fee0 =
            _feesEarned(poolData, true, feeGrowthInside0Last, tick, liquidity) +
            uint256(tokensOwed0);
        fee1 =
            _feesEarned(poolData, false, feeGrowthInside1Last, tick, liquidity) +
            uint256(tokensOwed1);
        (fee0, fee1) = _netPerformanceFees(feeData, fee0, fee1);
    }

    /**
     * @notice returns array of current user vaults. This function is only intended to be called off-chain.
     * @param fromIdx start index to fetch the user vaults info from.
     * @param toIdx end index to fetch the user vault to.
     */
    function getUserVaults(
        DataTypesLib.UserData storage userData,
        uint256 fromIdx,
        uint256 toIdx
    ) external view returns (DataTypesLib.UserVaultInfo[] memory) {
        if (fromIdx == 0 && toIdx == 0) {
            toIdx = userData.users.length;
        }
        DataTypesLib.UserVaultInfo[] memory usersVaultInfo = new DataTypesLib.UserVaultInfo[](
            toIdx - fromIdx
        );
        uint256 count;
        for (uint256 i = fromIdx; i < toIdx; i++) {
            DataTypesLib.UserVault memory userVault = userData.vaults[userData.users[i]];
            usersVaultInfo[count++] = DataTypesLib.UserVaultInfo({
                user: userData.users[i],
                token0: userVault.token0,
                token1: userVault.token1
            });
        }
        return usersVaultInfo;
    }

    /**
     * @dev returns the length of users array.
     */
    function userCount(DataTypesLib.UserData storage userData) external view returns (uint256) {
        return userData.users.length;
    }

    /**
     * @notice getPositionID returns the position id of the vault in pancake pool
     * @return positionID position id of the vault in pancake pool
     */
    function getPositionID(
        DataTypesLib.PoolData storage poolData
    ) public view returns (bytes32 positionID) {
        return keccak256(abi.encodePacked(address(this), poolData.lowerTick, poolData.upperTick));
    }

    /**
     * @notice compute total underlying token0 and token1 token supply at current price
     * includes current liquidity invested in pancake position, current fees earned
     * and any uninvested leftover (but does not include manager fees accrued)
     * @return amount0Current current total underlying balance of token0
     * @return amount1Current current total underlying balance of token1
     */
    function getUnderlyingBalances(
        DataTypesLib.PoolData storage poolData,
        DataTypesLib.FeeData storage feeData
    ) public view returns (uint256 amount0Current, uint256 amount1Current) {
        (uint160 sqrtRatioX96, int24 tick, , , , , ) = poolData.pool.slot0();
        return _getUnderlyingBalances(poolData, feeData, sqrtRatioX96, tick);
    }

    function getUnderlyingBalancesByShare(
        DataTypesLib.PoolData storage poolData,
        DataTypesLib.FeeData storage feeData,
        uint256 shares
    ) external view returns (uint256 amount0, uint256 amount1) {
        uint256 _totalSupply = IRangeProtocolVault(address(this)).totalSupply();
        if (_totalSupply != 0) {
            // getUnderlyingBalances already applies performanceFee
            (uint256 amount0Current, uint256 amount1Current) = getUnderlyingBalances(
                poolData,
                feeData
            );
            amount0 = (shares * amount0Current) / _totalSupply;
            amount1 = (shares * amount1Current) / _totalSupply;
            // apply managing fee
            (amount0, amount1) = _netManagingFees(feeData, amount0, amount1);
        }
    }

    /**
     * @notice _getUnderlyingBalances internal function to calculate underlying balances
     * @param sqrtRatioX96 price to calculate underlying balances at
     * @param tick tick at the given price
     * @return amount0Current current amount of token0
     * @return amount1Current current amount of token1
     */
    function _getUnderlyingBalances(
        DataTypesLib.PoolData storage poolData,
        DataTypesLib.FeeData storage feeData,
        uint160 sqrtRatioX96,
        int24 tick
    ) internal view returns (uint256 amount0Current, uint256 amount1Current) {
        (amount0Current, amount1Current) = poolBalance(poolData, feeData, sqrtRatioX96, tick);
        (uint256 fee0, uint256 fee1) = getCurrentFees(poolData, feeData);
        (amount0Current, amount1Current) = adjustPassiveBalance(
            poolData,
            feeData,
            amount0Current,
            amount1Current,
            fee0,
            fee1
        );
    }

    function poolBalance(
        DataTypesLib.PoolData storage poolData,
        DataTypesLib.FeeData storage feeData,
        uint160 sqrtRatioX96,
        int24 tick
    ) private view returns (uint256 amount0Current, uint256 amount1Current) {
        (
            uint128 liquidity,
            uint256 feeGrowthInside0Last,
            uint256 feeGrowthInside1Last,
            uint128 tokensOwed0,
            uint128 tokensOwed1
        ) = poolData.pool.positions(getPositionID(poolData));

        if (liquidity != 0) {
            (amount0Current, amount1Current) = LiquidityAmounts.getAmountsForLiquidity(
                sqrtRatioX96,
                poolData.lowerTick.getSqrtRatioAtTick(),
                poolData.upperTick.getSqrtRatioAtTick(),
                liquidity
            );
        }
    }

    function adjustPassiveBalance(
        DataTypesLib.PoolData storage poolData,
        DataTypesLib.FeeData storage feeData,
        uint256 amount0Current,
        uint256 amount1Current,
        uint256 fee0,
        uint256 fee1
    ) private view returns (uint256, uint256) {
        uint256 passiveBalance0 = fee0 + poolData.token0.balanceOf(address(this));
        uint256 passiveBalance1 = fee1 + poolData.token1.balanceOf(address(this));
        amount0Current += passiveBalance0 > feeData.managerBalance0
            ? passiveBalance0 - feeData.managerBalance0
            : passiveBalance0;
        amount1Current += passiveBalance1 > feeData.managerBalance1
            ? passiveBalance1 - feeData.managerBalance1
            : passiveBalance1;

        return (amount0Current, amount1Current);
    }

    /**
     * @notice The userVault mapping is updated before the vault share tokens are transferred between the users.
     * The data from this mapping is used by off-chain strategy manager. The data in this mapping does not impact
     * the on-chain behaviour of vault or users' funds.
     * @dev transfers userVault amounts based on the transferring user vault shares
     * @param from address to transfer userVault amount from
     * @param to address to transfer userVault amount to
     */
    function beforeTokenTransfer(
        DataTypesLib.UserData storage userData,
        address from,
        address to,
        uint256 amount
    ) external {
        // for mint and burn the user vaults adjustment are handled in the respective functions
        if (from == address(0x0) || to == address(0x0)) return;
        if (!userData.vaults[to].exists) {
            userData.vaults[to].exists = true;
            userData.users.push(to);
        }
        uint256 senderBalance = IRangeProtocolVault(address(this)).balanceOf(from);
        uint256 token0Amount = userData.vaults[from].token0 -
            (userData.vaults[from].token0 * (senderBalance - amount)) /
            senderBalance;

        uint256 token1Amount = userData.vaults[from].token1 -
            (userData.vaults[from].token1 * (senderBalance - amount)) /
            senderBalance;

        userData.vaults[from].token0 -= token0Amount;
        userData.vaults[from].token1 -= token1Amount;

        userData.vaults[to].token0 += token0Amount;
        userData.vaults[to].token1 += token1Amount;
    }

    /**
     * @notice _withdraw internal function to withdraw liquidity from uniswap pool
     * @param liquidity liquidity to remove from the uniswap pool
     */
    function _withdraw(
        DataTypesLib.PoolData storage poolData,
        uint128 liquidity
    ) private returns (uint256 burn0, uint256 burn1, uint256 fee0, uint256 fee1) {
        int24 _lowerTick = poolData.lowerTick;
        int24 _upperTick = poolData.upperTick;
        uint256 preBalance0 = poolData.token0.balanceOf(address(this));
        uint256 preBalance1 = poolData.token1.balanceOf(address(this));
        (burn0, burn1) = poolData.pool.burn(_lowerTick, _upperTick, liquidity);
        poolData.pool.collect(
            address(this),
            _lowerTick,
            _upperTick,
            type(uint128).max,
            type(uint128).max
        );
        fee0 = poolData.token0.balanceOf(address(this)) - preBalance0 - burn0;
        fee1 = poolData.token1.balanceOf(address(this)) - preBalance1 - burn1;
    }

    /**
     * @notice _calcMintAmounts internal function to calculate the amount based on the max supply of token0 and token1
     * and current supply of RangeVault shares.
     * @param totalSupply current total supply of range vault shares
     * @param amount0Max max amount of token0 to compute mint amount
     * @param amount1Max max amount of token1 to compute mint amount
     */
    function _calcMintAmounts(
        DataTypesLib.PoolData storage poolData,
        DataTypesLib.FeeData storage feeData,
        uint256 totalSupply,
        uint256 amount0Max,
        uint256 amount1Max
    ) private view returns (uint256 amount0, uint256 amount1, uint256 mintAmount) {
        (uint256 amount0Current, uint256 amount1Current) = getUnderlyingBalances(poolData, feeData);
        if (amount0Current == 0 && amount1Current > 0) {
            mintAmount = FullMath.mulDiv(amount1Max, totalSupply, amount1Current);
        } else if (amount1Current == 0 && amount0Current > 0) {
            mintAmount = FullMath.mulDiv(amount0Max, totalSupply, amount0Current);
        } else if (amount0Current == 0 && amount1Current == 0) {
            revert VaultErrors.ZeroUnderlyingBalance();
        } else {
            uint256 amount0Mint = FullMath.mulDiv(amount0Max, totalSupply, amount0Current);
            uint256 amount1Mint = FullMath.mulDiv(amount1Max, totalSupply, amount1Current);
            if (amount0Mint == 0 || amount1Mint == 0) revert VaultErrors.ZeroMintAmount();
            mintAmount = amount0Mint < amount1Mint ? amount0Mint : amount1Mint;
        }

        amount0 = FullMath.mulDivRoundingUp(mintAmount, amount0Current, totalSupply);
        amount1 = FullMath.mulDivRoundingUp(mintAmount, amount1Current, totalSupply);
    }

    /**
     * @notice _feesEarned internal function to return the fees accrued
     * @param isZero true to compute fee for token0 and false to compute fee for token1
     * @param feeGrowthInsideLast last time the fee was realized for the vault in pancake pool
     */
    function _feesEarned(
        DataTypesLib.PoolData storage poolData,
        bool isZero,
        uint256 feeGrowthInsideLast,
        int24 tick,
        uint128 liquidity
    ) private view returns (uint256 fee) {
        uint256 feeGrowthOutsideLower;
        uint256 feeGrowthOutsideUpper;
        uint256 feeGrowthGlobal;
        if (isZero) {
            feeGrowthGlobal = poolData.pool.feeGrowthGlobal0X128();
            (, , feeGrowthOutsideLower, , , , , ) = poolData.pool.ticks(poolData.lowerTick);
            (, , feeGrowthOutsideUpper, , , , , ) = poolData.pool.ticks(poolData.upperTick);
        } else {
            feeGrowthGlobal = poolData.pool.feeGrowthGlobal1X128();
            (, , , feeGrowthOutsideLower, , , , ) = poolData.pool.ticks(poolData.lowerTick);
            (, , , feeGrowthOutsideUpper, , , , ) = poolData.pool.ticks(poolData.upperTick);
        }

        unchecked {
            uint256 feeGrowthBelow;
            if (tick >= poolData.lowerTick) {
                feeGrowthBelow = feeGrowthOutsideLower;
            } else {
                feeGrowthBelow = feeGrowthGlobal - feeGrowthOutsideLower;
            }

            uint256 feeGrowthAbove;
            if (tick < poolData.upperTick) {
                feeGrowthAbove = feeGrowthOutsideUpper;
            } else {
                feeGrowthAbove = feeGrowthGlobal - feeGrowthOutsideUpper;
            }
            uint256 feeGrowthInside = feeGrowthGlobal - feeGrowthBelow - feeGrowthAbove;

            fee = FullMath.mulDiv(
                liquidity,
                feeGrowthInside - feeGrowthInsideLast,
                0x100000000000000000000000000000000
            );
        }
    }

    /**
     * @notice _applyManagingFee applies the managing fee to the notional value of the redeeming user.
     * @param amount0 user's notional value in token0
     * @param amount1 user's notional value in token1
     */
    function _applyManagingFee(
        DataTypesLib.FeeData storage feeData,
        uint256 amount0,
        uint256 amount1
    ) private {
        uint256 _managingFee = feeData.managingFee;
        feeData.managerBalance0 += (amount0 * _managingFee) / 10_000;
        feeData.managerBalance1 += (amount1 * _managingFee) / 10_000;
    }

    /**
     * @notice _applyPerformanceFee applies the performance fee to the fees earned from pancake v3 pool.
     * @param fee0 fee earned in token0
     * @param fee1 fee earned in token1
     */
    function _applyPerformanceFee(
        DataTypesLib.FeeData storage feeData,
        uint256 fee0,
        uint256 fee1
    ) private {
        uint256 _performanceFee = feeData.performanceFee;
        feeData.managerBalance0 += (fee0 * _performanceFee) / 10_000;
        feeData.managerBalance1 += (fee1 * _performanceFee) / 10_000;
    }

    /**
     * @notice _netManagingFees computes the fee share for manager from notional value of the redeeming user.
     * @param amount0 user's notional value in token0
     * @param amount1 user's notional value in token1
     * @return amount0AfterFee user's notional value in token0 after managing fee deduction
     * @return amount1AfterFee user's notional value in token1 after managing fee deduction
     */
    function _netManagingFees(
        DataTypesLib.FeeData storage feeData,
        uint256 amount0,
        uint256 amount1
    ) private view returns (uint256 amount0AfterFee, uint256 amount1AfterFee) {
        uint256 _managingFee = feeData.managingFee;
        uint256 deduct0 = (amount0 * _managingFee) / 10_000;
        uint256 deduct1 = (amount1 * _managingFee) / 10_000;
        amount0AfterFee = amount0 - deduct0;
        amount1AfterFee = amount1 - deduct1;
    }

    /**
     * @notice _netPerformanceFees computes the fee share for manager as performance fee from the fee earned from pancake v3 pool.
     * @param rawFee0 fee earned in token0 from pancake v3 pool.
     * @param rawFee1 fee earned in token1 from pancake v3 pool.
     * @return fee0AfterDeduction fee in token0 earned after deducting performance fee from earned fee.
     * @return fee1AfterDeduction fee in token1 earned after deducting performance fee from earned fee.
     */
    function _netPerformanceFees(
        DataTypesLib.FeeData storage feeData,
        uint256 rawFee0,
        uint256 rawFee1
    ) private view returns (uint256 fee0AfterDeduction, uint256 fee1AfterDeduction) {
        uint256 _performanceFee = feeData.performanceFee;
        uint256 deduct0 = (rawFee0 * _performanceFee) / 10_000;
        uint256 deduct1 = (rawFee1 * _performanceFee) / 10_000;
        fee0AfterDeduction = rawFee0 - deduct0;
        fee1AfterDeduction = rawFee1 - deduct1;
    }

    /**
     * @notice _updateTicks internal function to validate and update ticks
     * _lowerTick lower tick to update
     * _upperTick upper tick to update
     */
    function _updateTicks(
        DataTypesLib.PoolData storage poolData,
        int24 _lowerTick,
        int24 _upperTick
    ) private {
        _validateTicks(_lowerTick, _upperTick, poolData.tickSpacing);
        poolData.lowerTick = _lowerTick;
        poolData.upperTick = _upperTick;

        // Upon updating ticks inThePosition status is set to true.
        poolData.inThePosition = true;
        emit InThePositionStatusSet(true);
        emit TicksSet(_lowerTick, _upperTick);
    }

    /**
     * @notice _validateTicks validates the upper and lower ticks
     * @param _lowerTick lower tick to validate
     * @param _upperTick upper tick to validate
     */
    function _validateTicks(int24 _lowerTick, int24 _upperTick, int24 _tickSpacing) private view {
        if (_lowerTick < TickMath.MIN_TICK || _upperTick > TickMath.MAX_TICK)
            revert VaultErrors.TicksOutOfRange();

        if (
            _lowerTick >= _upperTick ||
            _lowerTick % _tickSpacing != 0 ||
            _upperTick % _tickSpacing != 0
        ) revert VaultErrors.InvalidTicksSpacing();
    }
}
