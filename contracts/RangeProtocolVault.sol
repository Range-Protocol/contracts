//SPDX-License-Identifier: MIT
pragma solidity 0.8.4;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {ERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {SafeCastUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/math/SafeCastUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import {SafeERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import {IERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import {IPancakeV3Pool} from "./pancake/interfaces/IPancakeV3Pool.sol";

import {TickMath} from "./pancake/TickMath.sol";
import {LiquidityAmounts} from "./pancake/LiquidityAmounts.sol";
import {FullMath} from "./pancake/FullMath.sol";
import {IRangeProtocolVault} from "./interfaces/IRangeProtocolVault.sol";
import {RangeProtocolVaultStorage} from "./RangeProtocolVaultStorage.sol";
import {OwnableUpgradeable} from "./access/OwnableUpgradeable.sol";
import {NativeTokenSupport} from "./libraries/NativeTokenSupport.sol";
import {VaultErrors} from "./errors/VaultErrors.sol";

/**
 * @dev Mars@RangeProtocol
 * @notice RangeProtocolVault is fungible vault shares contract that accepts pancake pool tokens for liquidity
 * provision to the corresponding pancake v3 pool. This contract is configurable to work with any pancake v3
 * pool and is initialized through RangeProtocolFactory contract's createVault function which determines
 * the pool address based provided tokens addresses and fee tier.
 *
 * The contract allows minting and burning of vault shares where minting involves providing token0 and/or token1
 * for the current set ticks (or based on ratio of token0 and token1 amounts in the vault when vault does not have an
 * active position in the pancake v3 pool) and burning involves removing liquidity from the pancake v3 pool along with
 * the vault's fee.
 *
 * The manager of the contract can remove liquidity from pancake v3 pool and deposit into a newer take range to maximise
 * the profit by keeping liquidity out of the pool under high volatility periods.
 *
 * Part of the fee earned from pancake v3 position is paid to manager as performance fee and fee is charged on the LP's
 * notional amount as managing fee.
 */
contract RangeProtocolVault is
    Initializable,
    UUPSUpgradeable,
    ReentrancyGuardUpgradeable,
    OwnableUpgradeable,
    ERC20Upgradeable,
    PausableUpgradeable,
    IRangeProtocolVault,
    RangeProtocolVaultStorage
{
    using SafeERC20Upgradeable for IERC20Upgradeable;
    using TickMath for int24;

    /// Performance fee cannot be set more than 20% of the fee earned from pancake v3 pool.
    uint16 public constant MAX_PERFORMANCE_FEE_BPS = 2000;
    /// Managing fee cannot be set more than 1% of the total fee earned.
    uint16 public constant MAX_MANAGING_FEE_BPS = 100;

    constructor() {
        _disableInitializers();
    }

    receive() external payable {
        require(msg.sender == WETH9);
    }

    /**
     * @notice initialize initializes the vault contract and is called right after proxy deployment
     * by the factory contract.
     * @param _pool address of the pancake v3 pool associated with vault
     * @param _tickSpacing tick spacing of the pancake pool
     * @param data additional config data associated with the implementation. The data type chosen is bytes
     * to keep the initialize function implementation contract generic to be compatible with factory contract
     */
    function initialize(
        address _pool,
        int24 _tickSpacing,
        bytes memory data
    ) external override initializer {
        (address manager, string memory _name, string memory _symbol, address _WETH9) = abi.decode(
            data,
            (address, string, string, address)
        );

        // reverts if manager address provided is zero.
        if (manager == address(0x0)) revert VaultErrors.ZeroManagerAddress();
        __UUPSUpgradeable_init();
        __ReentrancyGuard_init();
        __Ownable_init();
        __ERC20_init(_name, _symbol);
        __Pausable_init();

        _transferOwnership(manager);

        pool = IPancakeV3Pool(_pool);
        token0 = IERC20Upgradeable(pool.token0());
        token1 = IERC20Upgradeable(pool.token1());
        tickSpacing = _tickSpacing;
        factory = msg.sender;

        WETH9 = _WETH9;

        // Managing fee is 0% and performanceFee is 10% at the time vault initialization.
        _updateFees(0, 1000);
    }

    /**
     * @notice updateTicks it is called by the contract manager to update the ticks.
     * It can only be called once total supply is zero and the vault has not active position
     * in the pancake pool
     * @param _lowerTick lowerTick to set
     * @param _upperTick upperTick to set
     */
    function updateTicks(int24 _lowerTick, int24 _upperTick) external override onlyManager {
        if (totalSupply() != 0 || inThePosition) revert VaultErrors.NotAllowedToUpdateTicks();
        _updateTicks(_lowerTick, _upperTick);

        if (!mintStarted) {
            mintStarted = true;
            emit MintStarted();
        }
    }

    /**
     * @notice allows pausing of minting and burning features of the contract in the event
     * any security risk is seen in the vault.
     */
    function pause() external onlyManager {
        _pause();
    }

    /**
     * @notice allows unpausing of minting and burning features of the contract if they paused.
     */
    function unpause() external onlyManager {
        _unpause();
    }

    /// @notice pancakeV3MintCallback Pancake V3 callback fn, called back on pool.mint
    function pancakeV3MintCallback(
        uint256 amount0Owed,
        uint256 amount1Owed,
        bytes calldata
    ) external override {
        if (msg.sender != address(pool)) revert VaultErrors.OnlyPoolAllowed();

        if (amount0Owed > 0) {
            token0.safeTransfer(msg.sender, amount0Owed);
        }

        if (amount1Owed > 0) {
            token1.safeTransfer(msg.sender, amount1Owed);
        }
    }

    /// @notice pancakeV3SwapCallback Pancake v3 callback fn, called back on pool.swap
    function pancakeV3SwapCallback(
        int256 amount0Delta,
        int256 amount1Delta,
        bytes calldata
    ) external override {
        if (msg.sender != address(pool)) revert VaultErrors.OnlyPoolAllowed();

        if (amount0Delta > 0) {
            token0.safeTransfer(msg.sender, uint256(amount0Delta));
        } else if (amount1Delta > 0) {
            token1.safeTransfer(msg.sender, uint256(amount1Delta));
        }
    }

    /**
     * @notice mint mints range vault shares, fractional shares of a Pancake V3 position/strategy
     * to compute the amount of tokens necessary to mint `mintAmount` see getMintAmounts
     * @param mintAmount The number of shares to mint
     * @param maxAmounts max amounts to add in token0 and token1.
     * @return amount0 amount of token0 transferred from msg.sender to mint `mintAmount`
     * @return amount1 amount of token1 transferred from msg.sender to mint `mintAmount`
     */
    function mint(
        uint256 mintAmount,
        bool depositNative,
        uint256[2] calldata maxAmounts
    )
        external
        payable
        override
        nonReentrant
        whenNotPaused
        returns (uint256 amount0, uint256 amount1)
    {
        if (!mintStarted) revert VaultErrors.MintNotStarted();
        if (mintAmount == 0) revert VaultErrors.InvalidMintAmount();
        uint256 totalSupply = totalSupply();
        bool _inThePosition = inThePosition;
        (uint160 sqrtRatioX96, , , , , , ) = pool.slot0();

        if (totalSupply > 0) {
            (uint256 amount0Current, uint256 amount1Current) = getUnderlyingBalances();
            amount0 = FullMath.mulDivRoundingUp(amount0Current, mintAmount, totalSupply);
            amount1 = FullMath.mulDivRoundingUp(amount1Current, mintAmount, totalSupply);
        } else if (_inThePosition) {
            // If total supply is zero then inThePosition must be set to accept token0 and token1 based on currently set ticks.
            // This branch will be executed for the first mint and as well as each time total supply is to be changed from zero to non-zero.
            (amount0, amount1) = LiquidityAmounts.getAmountsForLiquidity(
                sqrtRatioX96,
                lowerTick.getSqrtRatioAtTick(),
                upperTick.getSqrtRatioAtTick(),
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

        if (amount0 > maxAmounts[0] || amount1 > maxAmounts[1])
            revert VaultErrors.SlippageExceedThreshold();

        NativeTokenSupport.processDeposit(
            userVaults[msg.sender],
            users,
            depositNative,
            token0,
            token1,
            amount0,
            amount1,
            WETH9
        );

        _mint(msg.sender, mintAmount);
        if (_inThePosition) {
            uint128 liquidityMinted = LiquidityAmounts.getLiquidityForAmounts(
                sqrtRatioX96,
                lowerTick.getSqrtRatioAtTick(),
                upperTick.getSqrtRatioAtTick(),
                amount0,
                amount1
            );
            pool.mint(address(this), lowerTick, upperTick, liquidityMinted, "");
        }
        emit Minted(msg.sender, mintAmount, amount0, amount1);

        if (address(this).balance != 0) msg.sender.call{value: address(this).balance}("");
    }

    /**
     * @notice burn burns range vault shares (shares of a Pancake V3 position) and receive underlying
     * @param burnAmount The number of shares to burn
     * @return amount0 amount of token0 transferred to msg.sender for burning {burnAmount}
     * @return amount1 amount of token1 transferred to msg.sender for burning {burnAmount}
     */
    function burn(
        uint256 burnAmount,
        bool withdrawNative,
        uint256[2] calldata minAmounts
    ) external override nonReentrant returns (uint256 amount0, uint256 amount1) {
        if (burnAmount == 0) revert VaultErrors.InvalidBurnAmount();
        (amount0, amount1) = getRawWithdrawAmounts(burnAmount);

        if (amount0 < minAmounts[0] || amount1 < minAmounts[1])
            revert VaultErrors.SlippageExceedThreshold();

        uint256 balanceBefore = balanceOf(msg.sender);
        _burn(msg.sender, burnAmount);

        _applyManagingFee(amount0, amount1);
        (amount0, amount1) = _netManagingFees(amount0, amount1);
        NativeTokenSupport.processWithdraw(
            userVaults[msg.sender],
            withdrawNative,
            burnAmount,
            balanceBefore,
            token0,
            token1,
            amount0,
            amount1,
            WETH9
        );

        emit Burned(msg.sender, burnAmount, amount0, amount1);
    }

    function getRawWithdrawAmounts(
        uint256 burnAmount
    ) private returns (uint256 amount0, uint256 amount1) {
        uint256 totalSupply = totalSupply();
        if (inThePosition) {
            (uint128 liquidity, , , , ) = pool.positions(getPositionID());
            uint256 liquidityBurned_ = FullMath.mulDiv(burnAmount, liquidity, totalSupply);
            uint128 liquidityBurned = SafeCastUpgradeable.toUint128(liquidityBurned_);
            (uint256 burn0, uint256 burn1, uint256 fee0, uint256 fee1) = _withdraw(liquidityBurned);

            _applyPerformanceFee(fee0, fee1);
            (fee0, fee1) = _netPerformanceFees(fee0, fee1);
            emit FeesEarned(fee0, fee1);

            uint256 passiveBalance0 = token0.balanceOf(address(this)) - burn0;
            uint256 passiveBalance1 = token1.balanceOf(address(this)) - burn1;
            if (passiveBalance0 > managerBalance0) passiveBalance0 -= managerBalance0;
            if (passiveBalance1 > managerBalance1) passiveBalance1 -= managerBalance1;

            amount0 = burn0 + FullMath.mulDiv(passiveBalance0, burnAmount, totalSupply);
            amount1 = burn1 + FullMath.mulDiv(passiveBalance1, burnAmount, totalSupply);
        } else {
            (uint256 amount0Current, uint256 amount1Current) = getUnderlyingBalances();
            amount0 = FullMath.mulDiv(amount0Current, burnAmount, totalSupply);
            amount1 = FullMath.mulDiv(amount1Current, burnAmount, totalSupply);
        }
    }

    /**
     * @notice removeLiquidity removes liquidity from pancake pool and receives underlying tokens
     * in the vault contract.
     */
    function removeLiquidity(uint256[2] calldata minAmounts) external override onlyManager {
        (uint128 liquidity, , , , ) = pool.positions(getPositionID());

        if (liquidity > 0) {
            int24 _lowerTick = lowerTick;
            int24 _upperTick = upperTick;
            (uint256 amount0, uint256 amount1, uint256 fee0, uint256 fee1) = _withdraw(liquidity);

            if (amount0 < minAmounts[0] || amount1 < minAmounts[1])
                revert VaultErrors.SlippageExceedThreshold();

            emit LiquidityRemoved(liquidity, _lowerTick, _upperTick, amount0, amount1);

            _applyPerformanceFee(fee0, fee1);
            (fee0, fee1) = _netPerformanceFees(fee0, fee1);
            emit FeesEarned(fee0, fee1);
        }

        // TicksSet event is not emitted here since the emitting would create a new position on subgraph but
        // the following statement is to only disallow any liquidity provision through the vault unless done
        // by manager (taking into account any features added in future).
        lowerTick = upperTick;
        inThePosition = false;
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
     * @param minAmountIn minimum amount to protect against slippage.
     * @return amount0 If positive represents exact input token0 amount after this swap, msg.sender paid amount,
     * or exact output token0 amount (negative), msg.sender received amount
     * @return amount1 If positive represents exact input token1 amount after this swap, msg.sender paid amount,
     * or exact output token1 amount (negative), msg.sender received amount
     */
    function swap(
        bool zeroForOne,
        int256 swapAmount,
        uint160 sqrtPriceLimitX96,
        uint256 minAmountIn
    ) external override onlyManager returns (int256 amount0, int256 amount1) {
        (amount0, amount1) = pool.swap(
            address(this),
            zeroForOne,
            swapAmount,
            sqrtPriceLimitX96,
            ""
        );
        if (
            (zeroForOne && uint256(-amount1) < minAmountIn) ||
            (!zeroForOne && uint256(-amount0) < minAmountIn)
        ) revert VaultErrors.SlippageExceedThreshold();

        emit Swapped(zeroForOne, amount0, amount1);
    }

    /**
     * @dev Mars@RangeProtocol
     * @notice addLiquidity allows manager to add liquidity into pancake pool into newer tick ranges.
     * @param newLowerTick new lower tick to deposit liquidity into
     * @param newUpperTick new upper tick to deposit liquidity into
     * @param amount0 max amount of amount0 to use
     * @param amount1 max amount of amount1 to use
     * @param maxAmounts max amounts to add for slippage protection
     */
    function addLiquidity(
        int24 newLowerTick,
        int24 newUpperTick,
        uint256 amount0,
        uint256 amount1,
        uint256[2] calldata maxAmounts
    ) external override onlyManager returns (uint256 remainingAmount0, uint256 remainingAmount1) {
        if (inThePosition) revert VaultErrors.LiquidityAlreadyAdded();

        (uint160 sqrtRatioX96, , , , , , ) = pool.slot0();
        uint128 baseLiquidity = LiquidityAmounts.getLiquidityForAmounts(
            sqrtRatioX96,
            newLowerTick.getSqrtRatioAtTick(),
            newUpperTick.getSqrtRatioAtTick(),
            amount0,
            amount1
        );

        if (baseLiquidity > 0) {
            (uint256 amountDeposited0, uint256 amountDeposited1) = pool.mint(
                address(this),
                newLowerTick,
                newUpperTick,
                baseLiquidity,
                ""
            );
            if (amountDeposited0 > maxAmounts[0] || amountDeposited1 > maxAmounts[1])
                revert VaultErrors.SlippageExceedThreshold();

            _updateTicks(newLowerTick, newUpperTick);
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
        }
    }

    /**
     * @dev pullFeeFromPool pulls accrued fee from pancake v3 pool that position has accrued since
     * last collection.
     */
    function pullFeeFromPool() external onlyManager {
        _pullFeeFromPool();
    }

    /// @notice collectManager collects manager fees accrued
    function collectManager() external override onlyManager {
        uint256 amount0 = managerBalance0;
        uint256 amount1 = managerBalance1;
        managerBalance0 = 0;
        managerBalance1 = 0;

        if (amount0 > 0) {
            token0.safeTransfer(manager(), amount0);
        }
        if (amount1 > 0) {
            token1.safeTransfer(manager(), amount1);
        }
    }

    /**
     * @notice updateFees allows updating of managing and performance fees
     */
    function updateFees(
        uint16 newManagingFee,
        uint16 newPerformanceFee
    ) external override onlyManager {
        _updateFees(newManagingFee, newPerformanceFee);
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
        uint256 amount0Max,
        uint256 amount1Max
    ) external view override returns (uint256 amount0, uint256 amount1, uint256 mintAmount) {
        if (!mintStarted) revert VaultErrors.MintNotStarted();
        uint256 totalSupply = totalSupply();
        if (totalSupply > 0) {
            (amount0, amount1, mintAmount) = _calcMintAmounts(totalSupply, amount0Max, amount1Max);
        } else if (inThePosition) {
            (uint160 sqrtRatioX96, , , , , , ) = pool.slot0();
            uint128 newLiquidity = LiquidityAmounts.getLiquidityForAmounts(
                sqrtRatioX96,
                lowerTick.getSqrtRatioAtTick(),
                upperTick.getSqrtRatioAtTick(),
                amount0Max,
                amount1Max
            );
            mintAmount = uint256(newLiquidity);
            (amount0, amount1) = LiquidityAmounts.getAmountsForLiquidity(
                sqrtRatioX96,
                lowerTick.getSqrtRatioAtTick(),
                upperTick.getSqrtRatioAtTick(),
                newLiquidity
            );
        }
    }

    /**
     * @notice getCurrentFees returns the current uncollected fees
     * @return fee0 uncollected fee in token0
     * @return fee1 uncollected fee in token1
     */
    function getCurrentFees() external view override returns (uint256 fee0, uint256 fee1) {
        (, int24 tick, , , , , ) = pool.slot0();
        (
            uint128 liquidity,
            uint256 feeGrowthInside0Last,
            uint256 feeGrowthInside1Last,
            uint128 tokensOwed0,
            uint128 tokensOwed1
        ) = pool.positions(getPositionID());
        fee0 = _feesEarned(true, feeGrowthInside0Last, tick, liquidity) + uint256(tokensOwed0);
        fee1 = _feesEarned(false, feeGrowthInside1Last, tick, liquidity) + uint256(tokensOwed1);
        (fee0, fee1) = _netPerformanceFees(fee0, fee1);
    }

    /**
     * @notice returns array of current user vaults. This function is only intended to be called off-chain.
     * @param fromIdx start index to fetch the user vaults info from.
     * @param toIdx end index to fetch the user vault to.
     */
    function getUserVaults(
        uint256 fromIdx,
        uint256 toIdx
    ) external view override returns (UserVaultInfo[] memory) {
        if (fromIdx == 0 && toIdx == 0) {
            toIdx = users.length;
        }
        UserVaultInfo[] memory usersVaultInfo = new UserVaultInfo[](toIdx - fromIdx);
        uint256 count;
        for (uint256 i = fromIdx; i < toIdx; i++) {
            UserVault memory userVault = userVaults[users[i]];
            usersVaultInfo[count++] = UserVaultInfo({
                user: users[i],
                token0: userVault.token0,
                token1: userVault.token1
            });
        }
        return usersVaultInfo;
    }

    /**
     * @dev returns the length of users array.
     */
    function userCount() external view returns (uint256) {
        return users.length;
    }

    /**
     * @notice getPositionID returns the position id of the vault in pancake pool
     * @return positionID position id of the vault in pancake pool
     */
    function getPositionID() public view override returns (bytes32 positionID) {
        return keccak256(abi.encodePacked(address(this), lowerTick, upperTick));
    }

    /**
     * @notice compute total underlying token0 and token1 token supply at current price
     * includes current liquidity invested in pancake position, current fees earned
     * and any uninvested leftover (but does not include manager fees accrued)
     * @return amount0Current current total underlying balance of token0
     * @return amount1Current current total underlying balance of token1
     */
    function getUnderlyingBalances()
        public
        view
        override
        returns (uint256 amount0Current, uint256 amount1Current)
    {
        (uint160 sqrtRatioX96, int24 tick, , , , , ) = pool.slot0();
        return _getUnderlyingBalances(sqrtRatioX96, tick);
    }

    function getUnderlyingBalancesByShare(
        uint256 shares
    ) external view returns (uint256 amount0, uint256 amount1) {
        uint256 _totalSupply = totalSupply();
        if (_totalSupply != 0) {
            // getUnderlyingBalances already applies performanceFee
            (uint256 amount0Current, uint256 amount1Current) = getUnderlyingBalances();
            amount0 = (shares * amount0Current) / _totalSupply;
            amount1 = (shares * amount1Current) / _totalSupply;
            // apply managing fee
            (amount0, amount1) = _netManagingFees(amount0, amount1);
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
        uint160 sqrtRatioX96,
        int24 tick
    ) internal view returns (uint256 amount0Current, uint256 amount1Current) {
        (
            uint128 liquidity,
            uint256 feeGrowthInside0Last,
            uint256 feeGrowthInside1Last,
            uint128 tokensOwed0,
            uint128 tokensOwed1
        ) = pool.positions(getPositionID());

        uint256 fee0;
        uint256 fee1;
        if (liquidity != 0) {
            (amount0Current, amount1Current) = LiquidityAmounts.getAmountsForLiquidity(
                sqrtRatioX96,
                lowerTick.getSqrtRatioAtTick(),
                upperTick.getSqrtRatioAtTick(),
                liquidity
            );
            fee0 = _feesEarned(true, feeGrowthInside0Last, tick, liquidity) + uint256(tokensOwed0);
            fee1 = _feesEarned(false, feeGrowthInside1Last, tick, liquidity) + uint256(tokensOwed1);
            (fee0, fee1) = _netPerformanceFees(fee0, fee1);
            amount0Current += fee0;
            amount1Current += fee1;
        }

        uint256 passiveBalance0 = token0.balanceOf(address(this));
        uint256 passiveBalance1 = token1.balanceOf(address(this));
        amount0Current += passiveBalance0 > managerBalance0
            ? passiveBalance0 - managerBalance0
            : passiveBalance0;
        amount1Current += passiveBalance1 > managerBalance1
            ? passiveBalance1 - managerBalance1
            : passiveBalance1;
    }

    /**
     * @notice _authorizeUpgrade internally called by UUPS contract to validate the upgrading operation of
     * the contract.
     */
    function _authorizeUpgrade(address) internal override {
        if (msg.sender != factory) revert VaultErrors.OnlyFactoryAllowed();
    }

    /**
     * @notice The userVault mapping is updated before the vault share tokens are transferred between the users.
     * The data from this mapping is used by off-chain strategy manager. The data in this mapping does not impact
     * the on-chain behaviour of vault or users' funds.
     * @dev transfers userVault amounts based on the transferring user vault shares
     * @param from address to transfer userVault amount from
     * @param to address to transfer userVault amount to
     */
    function _beforeTokenTransfer(address from, address to, uint256 amount) internal override {
        super._beforeTokenTransfer(from, to, amount);

        // for mint and burn the user vaults adjustment are handled in the respective functions
        if (from == address(0x0) || to == address(0x0)) return;
        if (!userVaults[to].exists) {
            userVaults[to].exists = true;
            users.push(to);
        }
        uint256 senderBalance = balanceOf(from);
        uint256 token0Amount = userVaults[from].token0 -
            (userVaults[from].token0 * (senderBalance - amount)) /
            senderBalance;

        uint256 token1Amount = userVaults[from].token1 -
            (userVaults[from].token1 * (senderBalance - amount)) /
            senderBalance;

        userVaults[from].token0 -= token0Amount;
        userVaults[from].token1 -= token1Amount;

        userVaults[to].token0 += token0Amount;
        userVaults[to].token1 += token1Amount;
    }

    /**
     * @notice _withdraw internal function to withdraw liquidity from uniswap pool
     * @param liquidity liquidity to remove from the uniswap pool
     */
    function _withdraw(
        uint128 liquidity
    ) private returns (uint256 burn0, uint256 burn1, uint256 fee0, uint256 fee1) {
        int24 _lowerTick = lowerTick;
        int24 _upperTick = upperTick;
        uint256 preBalance0 = token0.balanceOf(address(this));
        uint256 preBalance1 = token1.balanceOf(address(this));
        (burn0, burn1) = pool.burn(_lowerTick, _upperTick, liquidity);
        pool.collect(address(this), _lowerTick, _upperTick, type(uint128).max, type(uint128).max);
        fee0 = token0.balanceOf(address(this)) - preBalance0 - burn0;
        fee1 = token1.balanceOf(address(this)) - preBalance1 - burn1;
    }

    /**
     * @notice _calcMintAmounts internal function to calculate the amount based on the max supply of token0 and token1
     * and current supply of RangeVault shares.
     * @param totalSupply current total supply of range vault shares
     * @param amount0Max max amount of token0 to compute mint amount
     * @param amount1Max max amount of token1 to compute mint amount
     */
    function _calcMintAmounts(
        uint256 totalSupply,
        uint256 amount0Max,
        uint256 amount1Max
    ) private view returns (uint256 amount0, uint256 amount1, uint256 mintAmount) {
        (uint256 amount0Current, uint256 amount1Current) = getUnderlyingBalances();
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
        bool isZero,
        uint256 feeGrowthInsideLast,
        int24 tick,
        uint128 liquidity
    ) private view returns (uint256 fee) {
        uint256 feeGrowthOutsideLower;
        uint256 feeGrowthOutsideUpper;
        uint256 feeGrowthGlobal;
        if (isZero) {
            feeGrowthGlobal = pool.feeGrowthGlobal0X128();
            (, , feeGrowthOutsideLower, , , , , ) = pool.ticks(lowerTick);
            (, , feeGrowthOutsideUpper, , , , , ) = pool.ticks(upperTick);
        } else {
            feeGrowthGlobal = pool.feeGrowthGlobal1X128();
            (, , , feeGrowthOutsideLower, , , , ) = pool.ticks(lowerTick);
            (, , , feeGrowthOutsideUpper, , , , ) = pool.ticks(upperTick);
        }

        unchecked {
            uint256 feeGrowthBelow;
            if (tick >= lowerTick) {
                feeGrowthBelow = feeGrowthOutsideLower;
            } else {
                feeGrowthBelow = feeGrowthGlobal - feeGrowthOutsideLower;
            }

            uint256 feeGrowthAbove;
            if (tick < upperTick) {
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
    function _applyManagingFee(uint256 amount0, uint256 amount1) private {
        uint256 _managingFee = managingFee;
        managerBalance0 += (amount0 * _managingFee) / 10_000;
        managerBalance1 += (amount1 * _managingFee) / 10_000;
    }

    /**
     * @notice _applyPerformanceFee applies the performance fee to the fees earned from pancake v3 pool.
     * @param fee0 fee earned in token0
     * @param fee1 fee earned in token1
     */
    function _applyPerformanceFee(uint256 fee0, uint256 fee1) private {
        uint256 _performanceFee = performanceFee;
        managerBalance0 += (fee0 * _performanceFee) / 10_000;
        managerBalance1 += (fee1 * _performanceFee) / 10_000;
    }

    /**
     * @notice _netManagingFees computes the fee share for manager from notional value of the redeeming user.
     * @param amount0 user's notional value in token0
     * @param amount1 user's notional value in token1
     * @return amount0AfterFee user's notional value in token0 after managing fee deduction
     * @return amount1AfterFee user's notional value in token1 after managing fee deduction
     */
    function _netManagingFees(
        uint256 amount0,
        uint256 amount1
    ) private view returns (uint256 amount0AfterFee, uint256 amount1AfterFee) {
        uint256 _managingFee = managingFee;
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
        uint256 rawFee0,
        uint256 rawFee1
    ) private view returns (uint256 fee0AfterDeduction, uint256 fee1AfterDeduction) {
        uint256 _performanceFee = performanceFee;
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
    function _updateTicks(int24 _lowerTick, int24 _upperTick) private {
        _validateTicks(_lowerTick, _upperTick);
        lowerTick = _lowerTick;
        upperTick = _upperTick;

        // Upon updating ticks inThePosition status is set to true.
        inThePosition = true;
        emit InThePositionStatusSet(true);
        emit TicksSet(_lowerTick, _upperTick);
    }

    /**
     * @notice _validateTicks validates the upper and lower ticks
     * @param _lowerTick lower tick to validate
     * @param _upperTick upper tick to validate
     */
    function _validateTicks(int24 _lowerTick, int24 _upperTick) private view {
        if (_lowerTick < TickMath.MIN_TICK || _upperTick > TickMath.MAX_TICK)
            revert VaultErrors.TicksOutOfRange();

        if (
            _lowerTick >= _upperTick ||
            _lowerTick % tickSpacing != 0 ||
            _upperTick % tickSpacing != 0
        ) revert VaultErrors.InvalidTicksSpacing();
    }

    /**
     * @notice internal function that pulls fee from the pool
     */
    function _pullFeeFromPool() private {
        (, , uint256 fee0, uint256 fee1) = _withdraw(0);
        _applyPerformanceFee(fee0, fee1);
        (fee0, fee1) = _netPerformanceFees(fee0, fee1);
        emit FeesEarned(fee0, fee1);
    }

    /**
     * @notice internal function that updates the fee percentages for both performance
     * and managing fee.
     * @param newManagingFee new managing fee to set.
     * @param newPerformanceFee new performance fee to set.
     */
    function _updateFees(uint16 newManagingFee, uint16 newPerformanceFee) private {
        if (newManagingFee > MAX_MANAGING_FEE_BPS) revert VaultErrors.InvalidManagingFee();
        if (newPerformanceFee > MAX_PERFORMANCE_FEE_BPS) revert VaultErrors.InvalidPerformanceFee();

        if (inThePosition) _pullFeeFromPool();
        managingFee = newManagingFee;
        performanceFee = newPerformanceFee;
        emit FeesUpdated(newManagingFee, newPerformanceFee);
    }
}
