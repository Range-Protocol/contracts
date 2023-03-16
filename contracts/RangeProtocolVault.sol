//SPDX-License-Identifier: MIT
pragma solidity 0.8.4;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/math/SafeCastUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";

import "./uniswap/TickMath.sol";
import "./uniswap/LiquidityAmounts.sol";
import "./interfaces/IRangeProtocolVault.sol";
import "./RangeProtocolVaultStorage.sol";
import "./abstract/Ownable.sol";

/**
 * @dev Mars@RangeProtocol
 * @notice RangeProtocolVault is fungible vault shares contract that accepts uniswap pool tokens for liquidity
 * provision to the corresponding uniswap v3 pool. This contract is configurable to work with any uniswap v3
 * pool and is initialized through RangeProtocolFactory contract's createVault function which determines
 * the pool address based provided tokens addresses and fee tier.
 *
 * The contract allows minting and burning of vault shares where minting involves providing token0 and/or token1
 * for the current set ticks (or based on ratio of token0 and token1 amounts in the vault when vault does not have an
 * active position in the uniswap v3 pool) and burning involves removing liquidity from the uniswap v3 pool along with
 * the vault's fee.
 *
 * The manager of the contract can remove liquidity from uniswap v3 pool and deposit into a newer take range to maximise
 * the profit by keeping liquidity out of the pool under high volatility periods.
 *
 * Part of the fee earned from uniswap v3 position is paid to treasury and manager.
 */
contract RangeProtocolVault is
    Initializable,
    UUPSUpgradeable,
    ReentrancyGuardUpgradeable,
    Ownable,
    ERC20Upgradeable,
    IRangeProtocolVault,
    RangeProtocolVaultStorage
{
    using SafeERC20Upgradeable for IERC20Upgradeable;
    using TickMath for int24;

    uint16 public constant TREASURY_FEE_BPS = 250;
    /// Set the CAP on manager fee as 10%.
    /// Manager fee cannot be set more than 10% of the total fee earned.
    uint16 public constant MAX_MANAGER_FEE_BPS = 1000;

    constructor() {
        _disableInitializers();
    }

    /**
     * @notice initialize initializes the vault contract and is called right after proxy deployment
     * by the factory contract.
     * @param _pool address of the uniswap v3 pool associated with vault
     * @param _tickSpacing tick spacing of the uniswap pool
     * @param data additional config data associated with the implementation. The data type chosen is bytes
     * to keep the initialize function implementation contract generic to be compatible with factory contract
     */
    function initialize(
        address _pool,
        int24 _tickSpacing,
        bytes memory data
    ) external override initializer {
        (
            address _treasury,
            address manager,
            uint16 _managerFee,
            string memory _name,
            string memory _symbol
        ) = abi.decode(data, (address, address, uint16, string, string));

        __UUPSUpgradeable_init();
        __ReentrancyGuard_init();
        __ERC20_init(_name, _symbol);

        pool = IUniswapV3Pool(_pool);
        token0 = IERC20Upgradeable(pool.token0());
        token1 = IERC20Upgradeable(pool.token1());
        tickSpacing = _tickSpacing;
        factory = msg.sender;

        if (_treasury == address(0x0)) revert ZeroTreasuryAddress();
        treasury = _treasury;

        if (_managerFee > MAX_MANAGER_FEE_BPS) revert InvalidManagerFee();
        managerFee = _managerFee;
        _manager = manager;
        emit ManagerFeeUpdated(_managerFee);
    }

    /**
     * @notice updateTicks it is called by the contract manager to update the ticks.
     * It can only be called once total supply is zero and the vault has not active position
     * in the uniswap pool
     * @param _lowerTick lowerTick to set
     * @param _upperTick upperTick to set
     */
    function updateTicks(int24 _lowerTick, int24 _upperTick) external override onlyManager {
        if (totalSupply() != 0 || inThePosition) revert NotAllowedToUpdateTicks();
        _updateTicks(_lowerTick, _upperTick);

        if (!mintStarted) {
            mintStarted = true;
            emit MintStarted();
        }
    }

    /// @notice uniswapV3MintCallback Uniswap V3 callback fn, called back on pool.mint
    function uniswapV3MintCallback(
        uint256 amount0Owed,
        uint256 amount1Owed,
        bytes calldata
    ) external override {
        if (msg.sender != address(pool)) revert OnlyPoolAllowed();

        if (amount0Owed > 0) {
            token0.safeTransfer(msg.sender, amount0Owed);
        }

        if (amount1Owed > 0) {
            token1.safeTransfer(msg.sender, amount1Owed);
        }
    }

    /// @notice uniswapV3SwapCallback Uniswap v3 callback fn, called back on pool.swap
    function uniswapV3SwapCallback(
        int256 amount0Delta,
        int256 amount1Delta,
        bytes calldata
    ) external override {
        if (msg.sender != address(pool)) revert OnlyPoolAllowed();

        if (amount0Delta > 0) {
            token0.safeTransfer(msg.sender, uint256(amount0Delta));
        } else if (amount1Delta > 0) {
            token1.safeTransfer(msg.sender, uint256(amount1Delta));
        }
    }

    /**
     * @notice mint mints range vault shares, fractional shares of a Uniswap V3 position/strategy
     * to compute the amount of tokens necessary to mint `mintAmount` see getMintAmounts
     * @param mintAmount The number of shares to mint
     * @return amount0 amount of token0 transferred from msg.sender to mint `mintAmount`
     * @return amount1 amount of token1 transferred from msg.sender to mint `mintAmount`
     */
    function mint(
        uint256 mintAmount
    ) external override nonReentrant returns (uint256 amount0, uint256 amount1) {
        if (!mintStarted) revert MintNotStarted();
        if (mintAmount == 0) revert InvalidMintAmount();
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
            revert MintNotAllowed();
        }

        if (amount0 > 0) {
            token0.safeTransferFrom(msg.sender, address(this), amount0);
        }
        if (amount1 > 0) {
            token1.safeTransferFrom(msg.sender, address(this), amount1);
        }

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
    }

    /**
     * @notice burn burns range vault shares (shares of a Uniswap V3 position) and receive underlying
     * @param burnAmount The number of shares to burn
     * @return amount0 amount of token0 transferred to msg.sender for burning {burnAmount}
     * @return amount1 amount of token1 transferred to msg.sender for burning {burnAmount}
     */
    function burn(
        uint256 burnAmount
    ) external override nonReentrant returns (uint256 amount0, uint256 amount1) {
        if (burnAmount == 0) revert InvalidBurnAmount();
        uint256 totalSupply = totalSupply();
        _burn(msg.sender, burnAmount);

        if (inThePosition) {
            (uint128 liquidity, , , , ) = pool.positions(getPositionID());
            uint256 liquidityBurned_ = FullMath.mulDiv(burnAmount, liquidity, totalSupply);
            uint128 liquidityBurned = SafeCastUpgradeable.toUint128(liquidityBurned_);
            (uint256 burn0, uint256 burn1, uint256 fee0, uint256 fee1) = _withdraw(liquidityBurned);

            _applyFees(fee0, fee1);
            (fee0, fee1) = _netFees(fee0, fee1);
            emit FeesEarned(fee0, fee1);

            amount0 =
                burn0 +
                FullMath.mulDiv(
                    token0.balanceOf(address(this)) - burn0 - managerBalance0 - treasuryBalance0,
                    burnAmount,
                    totalSupply
                );

            amount1 =
                burn1 +
                FullMath.mulDiv(
                    token1.balanceOf(address(this)) - burn1 - managerBalance1 - treasuryBalance1,
                    burnAmount,
                    totalSupply
                );
        } else {
            (uint256 amount0Current, uint256 amount1Current) = getUnderlyingBalances();
            amount0 = FullMath.mulDiv(amount0Current, burnAmount, totalSupply);
            amount1 = FullMath.mulDiv(amount1Current, burnAmount, totalSupply);
        }

        if (amount0 > 0) {
            token0.safeTransfer(msg.sender, amount0);
        }
        if (amount1 > 0) {
            token1.safeTransfer(msg.sender, amount1);
        }

        emit Burned(msg.sender, burnAmount, amount0, amount1);
    }

    /**
     * @notice removeLiquidity removes liquidity from uniswap pool and receives underlying tokens
     * in the vault contract.
     */
    function removeLiquidity() external override onlyManager {
        (uint128 liquidity, , , , ) = pool.positions(getPositionID());

        if (liquidity > 0) {
            int24 _lowerTick = lowerTick;
            int24 _upperTick = upperTick;
            (uint256 amount0, uint256 amount1, uint256 fee0, uint256 fee1) = _withdraw(liquidity);

            emit LiquidityRemoved(liquidity, _lowerTick, _upperTick, amount0, amount1);

            _applyFees(fee0, fee1);
            (fee0, fee1) = _netFees(fee0, fee1);
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
     * @return amount0 If positive represents exact input token0 amount after this swap, msg.sender paid amount,
     * or exact output token0 amount (negative), msg.sender received amount
     * @return amount1 If positive represents exact input token1 amount after this swap, msg.sender paid amount,
     * or exact output token1 amount (negative), msg.sender received amount
     */
    function swap(
        bool zeroForOne,
        int256 swapAmount,
        uint160 sqrtPriceLimitX96
    ) external override onlyManager returns (int256 amount0, int256 amount1) {
        (amount0, amount1) = pool.swap(
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
     * @notice addLiquidity allows manager to add liquidity into uniswap pool into newer tick ranges.
     * @param newLowerTick new lower tick to deposit liquidity into
     * @param newUpperTick new upper tick to deposit liquidity into
     * @param amount0 max amount of amount0 to use
     * @param amount1 max amount of amount1 to use
     * @return remainingAmount0 remaining amount from amount0
     * @return remainingAmount1 remaining amount from amount1
     */
    function addLiquidity(
        int24 newLowerTick,
        int24 newUpperTick,
        uint256 amount0,
        uint256 amount1
    ) external override onlyManager returns (uint256 remainingAmount0, uint256 remainingAmount1) {
        _validateTicks(newLowerTick, newUpperTick);
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
            // Should return remaining token number for swap
            remainingAmount0 = amount0 - amountDeposited0;
            remainingAmount1 = amount1 - amountDeposited1;
            if (lowerTick != newLowerTick || upperTick != newUpperTick) {
                lowerTick = newLowerTick;
                upperTick = newUpperTick;
                emit TicksSet(newLowerTick, newUpperTick);
            }

            emit LiquidityAdded(
                baseLiquidity,
                newLowerTick,
                newUpperTick,
                amountDeposited0,
                amountDeposited1
            );
        }
        // This check is added to not update inThePosition state in case manager decides to add liquidity in smaller chunks.
        if (!inThePosition) {
            inThePosition = true;
            emit InThePositionStatusSet(true);
        }
    }

    /**
     * @dev pullFeeFromPool pulls accrued fee from uniswap v3 pool that position has accrued since
     * last collection.
     */
    function pullFeeFromPool() external onlyManager {
        (, , uint256 fee0, uint256 fee1) = _withdraw(0);
        _applyFees(fee0, fee1);
        (fee0, fee1) = _netFees(fee0, fee1);
        emit FeesEarned(fee0, fee1);
    }

    /// @notice collectManager collects manager fees accrued
    function collectManager() external override {
        uint256 amount0 = managerBalance0;
        uint256 amount1 = managerBalance1;
        managerBalance0 = 0;
        managerBalance1 = 0;

        if (amount0 > 0) {
            token0.safeTransfer(_manager, amount0);
        }
        if (amount1 > 0) {
            token1.safeTransfer(_manager, amount1);
        }
    }

    /// @notice collectTreasury collect range-protocol fees accrued
    function collectTreasury() external override {
        uint256 amount0 = treasuryBalance0;
        uint256 amount1 = treasuryBalance1;
        treasuryBalance0 = 0;
        treasuryBalance1 = 0;

        if (amount0 > 0) {
            token0.safeTransfer(treasury, amount0);
        }
        if (amount1 > 0) {
            token1.safeTransfer(treasury, amount1);
        }
    }

    /**
     * @notice updateManagerParams allows updating of manager params by the manager
     * @param newManagerFee Basis Points of fees earned credited to manager (negative to ignore)
     */
    function updateManagerFee(uint16 newManagerFee) external override onlyManager {
        if (newManagerFee > MAX_MANAGER_FEE_BPS) revert InvalidManagerFee();

        if (newManagerFee >= 0) {
            managerFee = newManagerFee;
        }

        emit ManagerFeeUpdated(newManagerFee);
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
        if (!mintStarted) revert MintNotStarted();
        uint256 totalSupply = totalSupply();
        if (totalSupply > 0) {
            (amount0, amount1, mintAmount) = _calcMintAmounts(totalSupply, amount0Max, amount1Max);
        } else {
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
     * @notice compute total underlying token0 and token1 token supply at provided price
     * includes current liquidity invested in uniswap position, current fees earned
     * and any uninvested leftover (but does not include manager or treasury fees accrued)
     * @param sqrtRatioX96 price to computer underlying balances at
     * @return amount0Current current total underlying balance of token0
     * @return amount1Current current total underlying balance of token1
     */
    function getUnderlyingBalancesAtPrice(
        uint160 sqrtRatioX96
    ) external view override returns (uint256 amount0Current, uint256 amount1Current) {
        (, int24 tick, , , , , ) = pool.slot0();
        return _getUnderlyingBalances(sqrtRatioX96, tick);
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
        (fee0, fee1) = _netFees(fee0, fee1);
    }

    /**
     * @notice getPositionID returns the position id of the vault in uniswap pool
     * @return positionID position id of the vault in uniswap pool
     */
    function getPositionID() public view override returns (bytes32 positionID) {
        return keccak256(abi.encodePacked(address(this), lowerTick, upperTick));
    }

    /**
     * @notice compute total underlying token0 and token1 token supply at current price
     * includes current liquidity invested in uniswap position, current fees earned
     * and any uninvested leftover (but does not include manager or treasury fees accrued)
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
            (fee0, fee1) = _netFees(fee0, fee1);
        }

        amount0Current +=
            fee0 +
            token0.balanceOf(address(this)) -
            managerBalance0 -
            treasuryBalance0;
        amount1Current +=
            fee1 +
            token1.balanceOf(address(this)) -
            managerBalance1 -
            treasuryBalance1;
    }

    /**
     * @notice _authorizeUpgrade internally called by UUPS contract to validate the upgrading operation of
     * the contract.
     */
    function _authorizeUpgrade(address) internal override {
        if (msg.sender != factory) revert OnlyFactoryAllowed();
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
            revert ZeroUnderlyingBalance();
        } else {
            uint256 amount0Mint = FullMath.mulDiv(amount0Max, totalSupply, amount0Current);
            uint256 amount1Mint = FullMath.mulDiv(amount1Max, totalSupply, amount1Current);
            if (amount0Mint == 0 || amount1Mint == 0) revert ZeroMintAmount();
            mintAmount = amount0Mint < amount1Mint ? amount0Mint : amount1Mint;
        }

        amount0 = FullMath.mulDivRoundingUp(mintAmount, amount0Current, totalSupply);
        amount1 = FullMath.mulDivRoundingUp(mintAmount, amount1Current, totalSupply);
    }

    /**
     * @notice _feesEarned internal function to return the fees accrued
     * @param isZero true to compute fee for token0 and false to compute fee for token1
     * @param feeGrowthInsideLast last time the fee was realized for the vault in uniswap pool
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
     * @notice _applyFees applies the manager and treasury fee the global balance tracking variables
     * @param _fee0 fee to apply in token0
     * @param _fee1 fee to apply in token1
     */
    function _applyFees(uint256 _fee0, uint256 _fee1) private {
        treasuryBalance0 += (_fee0 * TREASURY_FEE_BPS) / 10_000;
        treasuryBalance1 += (_fee1 * TREASURY_FEE_BPS) / 10_000;
        // managerFee is read from storage, so storing in a local variable saves gas cost.
        uint16 _managerFee = managerFee;
        managerBalance0 += (_fee0 * _managerFee) / 10_000;
        managerBalance1 += (_fee1 * _managerFee) / 10_000;
    }

    /**
     * @notice _netFees computes the fee share for manager and treasury from collected raw fee
     * @param rawFee0 fee collected in token0
     * @param rawFee1 fee collected in token1
     * @param fee0 fee in token0 after manager and treasury shares are deducted
     * @param fee1 fee in token1 after manager and treasury shares are deducted
     */
    function _netFees(
        uint256 rawFee0,
        uint256 rawFee1
    ) private view returns (uint256 fee0, uint256 fee1) {
        // managerFee is read from storage, so storing in a local variable saves gas cost.
        uint16 _managerFee = managerFee;
        uint256 deduct0 = (rawFee0 * (TREASURY_FEE_BPS + _managerFee)) / 10_000;
        uint256 deduct1 = (rawFee1 * (TREASURY_FEE_BPS + _managerFee)) / 10_000;
        fee0 = rawFee0 - deduct0;
        fee1 = rawFee1 - deduct1;
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
            revert TicksOutOfRange();

        if (
            _lowerTick >= _upperTick ||
            _lowerTick % tickSpacing != 0 ||
            _upperTick % tickSpacing != 0
        ) revert InvalidTicksSpacing();
    }
}
