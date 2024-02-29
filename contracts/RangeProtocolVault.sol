//SPDX-License-Identifier: MIT
pragma solidity 0.8.4;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeCast.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";

import "./abstract/Ownable.sol";
import "./uniswap/TickMath.sol";
import "./uniswap/LiquidityAmounts.sol";
import "./interfaces/IRangeProtocolVault.sol";


/// @dev Mars@RangeProtocol
contract RangeProtocolVault is
    Ownable,
    ERC20,
    ReentrancyGuard,
    IRangeProtocolVault
{
    using SafeERC20 for IERC20;
    using TickMath for int24;

    IUniswapV3Pool public pool;
    IERC20 public immutable token0;
    IERC20 public immutable token1;

    int24 public lowerTick;
    int24 public upperTick;
    int24 public immutable tickSpacing;

    /// @notice RangeProtocol treasury
    address public immutable treasury;
    address public managerTreasury;
    uint16 public managerFee;
    uint16 public constant treasuryFee = 250;
    /// Tentatively set the CAP on manager fee as 10%. Manager fee cannot be set more than 10% of the total fee earned.
    uint16 public constant MAX_MANAGER_FEE = 1000;

    uint256 public treasury0;
    uint256 public treasury1;
    uint256 public managerBalance0;
    uint256 public managerBalance1;

    bool public inThePosition;
    bool public initialized;

    constructor(
        address _pool,
        int24 _tickSpacing,
        address _treasury,
        address _manager_,
        uint16 _managerFee,
        string memory _name,
        string memory _symbol
    )
        Ownable(_manager_)
        ERC20(_name, _symbol)
    {
        if (_managerFee > MAX_MANAGER_FEE) revert InvalidManagerFee();

        tickSpacing = _tickSpacing;
        managerFee = _managerFee;
        treasury = _treasury;
        managerTreasury = _manager_;

        pool = IUniswapV3Pool(_pool);
        token0 = IERC20(pool.token0());
        token1 = IERC20(pool.token1());
    }

    /**
     * @dev Allows initializing ticks once after the contract deployment and later when total supply goes to zero.
     */
    function initialize(int24 _lowerTick, int24 _upperTick)
        external
        override
        onlyManager
    {
        if (initialized && totalSupply() != 0) revert CannotInitialize();

        if (!initialized) {
            initialized = true;
            emit Initialized();
        }
        _validateTicks(_lowerTick, _upperTick);
        lowerTick = _lowerTick;
        upperTick = _upperTick;

        // Upon initialization inThePosition status is true.
        inThePosition = true;
        emit InThePositionStatusSet(true);
        emit TicksSet(_lowerTick, _upperTick);
    }

    function getPositionID()
        public
        view
        override
        returns (bytes32 positionID)
    {
        return keccak256(
            abi.encodePacked(
                address(this),
                lowerTick,
                upperTick
            )
        );
    }

    /// @notice Uniswap V3 callback fn, called back on pool.mint
    function uniswapV3MintCallback(
        uint256 amount0Owed,
        uint256 amount1Owed,
        bytes calldata
    ) external override {
        if (msg.sender != address(pool)) revert OnlyPoolAllowed();

        if (amount0Owed > 0) token0.safeTransfer(msg.sender, amount0Owed);
        if (amount1Owed > 0) token1.safeTransfer(msg.sender, amount1Owed);
    }

    /// @notice Uniswap v3 callback fn, called back on pool.swap
    function uniswapV3SwapCallback(
        int256 amount0Delta,
        int256 amount1Delta,
        bytes calldata
    ) external override {
        if (msg.sender != address(pool)) revert OnlyPoolAllowed();

        if (amount0Delta > 0) token0.safeTransfer(msg.sender, uint256(amount0Delta));
        else if (amount1Delta > 0) token1.safeTransfer(msg.sender, uint256(amount1Delta));
    }

    // User functions => Should be called via a Router

    /// @notice mint RangeVault Shares, fractional shares of a Uniswap V3 position/strategy
    /// @dev to compute the amount of tokens necessary to mint `mintAmount` see getMintAmounts
    /// @param mintAmount The number of shares to mint
    /// @return amount0 amount of token0 transferred from msg.sender to mint `mintAmount`
    /// @return amount1 amount of token1 transferred from msg.sender to mint `mintAmount`
    function mint(uint256 mintAmount)
        external
        override
        nonReentrant
        returns (
            uint256 amount0,
            uint256 amount1
        )
    {
        if (!initialized) revert NotInitialized();
        if (mintAmount == 0) revert InvalidMintAmount();
        uint256 totalSupply = totalSupply();
        bool _inThePosition = inThePosition;
        (uint160 sqrtRatioX96, , , , , , ) = pool.slot0();

        if (totalSupply > 0) {
            (
                uint256 amount0Current,
                uint256 amount1Current
            ) = getUnderlyingBalances();
            amount0 = FullMath.mulDivRoundingUp(
                amount0Current,
                mintAmount,
                totalSupply
            );
            amount1 = FullMath.mulDivRoundingUp(
                amount1Current,
                mintAmount,
                totalSupply
            );
        } else if (_inThePosition) {
            // If total supply is zero then inThePosition must be set to accept token0 and token1 based on currently set ticks.
            // This branch will be executed for the first mint and as well as each time total supply is to be changed from zero to non-zero.
            (amount0, amount1) = LiquidityAmounts.getAmountsForLiquidity(
                sqrtRatioX96,
                lowerTick.getSqrtRatioAtTick(),
                upperTick.getSqrtRatioAtTick(),
                SafeCast.toUint128(mintAmount)
            );
        } else {
            // If total supply is zero and the vault is not in the position then mint cannot be accepted based on the assumptions
            // that being out of the pool renders currently set ticks unusable and totalSupply being zero does not allow
            // calculating correct amounts of amount0 and amount1 to be accepted from the user.
            // This branch will be executed if all users remove their liquidity from the vault i.e. total supply is zero from non-zero and
            // the vault is out of the position i.e. no valid tick range to calculate the vault's mint shares.
            // Manager must call initialize function with valid tick ranges to enable the minting again.
            revert  MintNotAllowed();
        }

        if (amount0 > 0) {
            token0.safeTransferFrom(
                msg.sender,
                address(this),
                amount0
            );
        }
        if (amount1 > 0) {
            token1.safeTransferFrom(
                msg.sender,
                address(this),
                amount1
            );
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
            pool.mint(
                address(this),
                lowerTick,
                upperTick,
                liquidityMinted,
                ""
            );
        }

        emit Minted(
            msg.sender,
            mintAmount,
            amount0,
            amount1
        );
    }

    /// @notice burn RangeVaul Shares (shares of a Uniswap V3 position) and receive underlying
    /// @param burnAmount The number of shares to burn
    /// @return amount0 amount of token0 transferred to msg.sender for burning `burnAmount`
    /// @return amount1 amount of token1 transferred to msg.sender for burning `burnAmount`
    function burn(uint256 burnAmount)
        external
        override
        nonReentrant
        returns (
            uint256 amount0,
            uint256 amount1
        )
    {
        if (burnAmount == 0) revert InvalidBurnAmount();
        uint256 totalSupply = totalSupply();
        _burn(msg.sender, burnAmount);

        if (inThePosition) {
            (uint128 liquidity, , , , ) = pool.positions(getPositionID());
            uint256 liquidityBurned_ = FullMath.mulDiv(
                burnAmount,
                liquidity,
                totalSupply
            );
            uint128 liquidityBurned = SafeCast.toUint128(liquidityBurned_);
            (
                uint256 burn0,
                uint256 burn1,
                uint256 fee0,
                uint256 fee1
            ) = _withdraw(
                lowerTick,
                upperTick,
                liquidityBurned
            );

            _applyFees(fee0, fee1);
            (fee0, fee1) = _netFees(fee0, fee1);
            emit FeesEarned(fee0, fee1);

            amount0 =
                burn0 +
                FullMath.mulDiv(
                    token0.balanceOf(address(this)) - burn0 - managerBalance0 - treasury0,
                    burnAmount,
                    totalSupply
                );

            amount1 =
                burn1 +
                FullMath.mulDiv(
                    token1.balanceOf(address(this)) - burn1 - managerBalance1 - treasury1,
                    burnAmount,
                    totalSupply
                );
        } else {
            (
                uint256 amount0Current,
                uint256 amount1Current
            ) = getUnderlyingBalances();
            amount0 = FullMath.mulDiv(
                amount0Current,
                burnAmount,
                totalSupply
            );
            amount1 = FullMath.mulDiv(
                amount1Current,
                burnAmount,
                totalSupply)
            ;
        }

        if (amount0 > 0) token0.safeTransfer(msg.sender, amount0);
        if (amount1 > 0) token1.safeTransfer(msg.sender, amount1);

        emit Burned(
            msg.sender,
            burnAmount,
            amount0,
            amount1
        );
    }

    /// @dev Mars@RangeProtocol
    function removeLiquidity()
        external
        override
        onlyManager
    {
        (uint128 liquidity, , , , ) = pool.positions(getPositionID());

        if (liquidity > 0) {
            int24 _lowerTick = lowerTick;
            int24 _upperTick = upperTick;
            (
                uint256 amount0,
                uint256 amount1,
                uint256 fee0,
                uint256 fee1
            ) = _withdraw(
                _lowerTick,
                _upperTick,
                liquidity
            );

            emit LiquidityRemoved(
                liquidity,
                _lowerTick,
                _upperTick,
                amount0,
                amount1
            );

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

    /// @dev Mars@RangeProtocol
    /// @notice Swap token0 for token1 (token0 in, token1 out), or token1 for token0 (token1 in token0 out)
    /// @notice Zero for one will cause the price: amount1 / amount0 lower, otherwise it will cause the price higher
    /// @param zeroForOne The direction of the swap, true is swap token0 for token1, false is swap token1 to token0
    /// @param swapAmount The exact input token amount of the swap
    /// @param sqrtPriceLimitX96 threshold price ratio after the swap.
    /// If zero for one, the price cannot be lower (swap make price lower) than this threshold value after the swap
    /// If one for zero, the price cannot be greater (swap make price higher) than this threshold value after the swap
    /// @return amount0 If positive represents exact input token0 amount after this swap, msg.sender paid amount,
    /// or exact output token0 amount (negative), msg.sender received amount
    /// @return amount1 If positive represents exact input token1 amount after this swap, msg.sender paid amount,
    /// or exact output token1 amount (negative), msg.sender received amount
    function swap(
        bool zeroForOne,
        int256 swapAmount,
        uint160 sqrtPriceLimitX96
    )
        external
        override
        onlyManager
        returns (int256 amount0, int256 amount1)
    {
        (amount0, amount1) = pool.swap(
            address(this),
            zeroForOne,
            swapAmount,
            sqrtPriceLimitX96,
            ""
        );

        emit Swapped(
            zeroForOne,
            amount0,
            amount1
        );
    }

    /// @dev Mars@RangeProtocol
    /// @notice return remaining token0 and token1 amount
    function addLiquidity(
        int24 newLowerTick,
        int24 newUpperTick,
        uint256 amount0,
        uint256 amount1
    )
        external
        override
        onlyManager
        returns (uint256 remainingAmount0, uint256 remainingAmount1)
    {
        _validateTicks(newLowerTick, newUpperTick);
        (uint160 sqrtRatioX96, , , , , , ) = pool.slot0();
        uint128 baseLiquidity =
            LiquidityAmounts.getLiquidityForAmounts(
                sqrtRatioX96,
                newLowerTick.getSqrtRatioAtTick(),
                newUpperTick.getSqrtRatioAtTick(),
                amount0,
                amount1
            );

        if (baseLiquidity > 0) {
            (
                uint256 amountDeposited0,
                uint256 amountDeposited1
            ) = pool.mint(
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

    /// @notice collect manager fees accrued
    function collectManager() external override {
        uint256 amount0 = managerBalance0;
        uint256 amount1 = managerBalance1;
        managerBalance0 = 0;
        managerBalance1 = 0;

        if (amount0 > 0) token0.safeTransfer(managerTreasury, amount0);
        if (amount1 > 0) token1.safeTransfer(managerTreasury, amount1);
    }

    /// @notice collect range-protocol fees accrued
    function collectTreasury() external override {
        uint256 amount0 = treasury0;
        uint256 amount1 = treasury1;
        treasury0 = 0;
        treasury1 = 0;

        if (amount0 > 0) token0.safeTransfer(treasury, amount0);
        if (amount1 > 0) token1.safeTransfer(treasury, amount1);
    }

    /// @param newManagerFee Basis Points of fees earned credited to manager (negative to ignore)
    /// @param newManagerTreasury address that collects manager fees (Zero address to ignore)
    function updateManagerParams(int16 newManagerFee, address newManagerTreasury)
        external
        override
        onlyManager
    {
        if (newManagerFee > int16(MAX_MANAGER_FEE)) revert InvalidManagerFee();

        if (newManagerFee >= 0) managerFee = uint16(newManagerFee);
        if (newManagerTreasury != address(0)) managerTreasury = newManagerTreasury;

        emit UpdateManagerParams(managerFee, managerTreasury);
    }

    /// @notice compute maximum shares that can be minted from `amount0Max` and `amount1Max`
    /// @param amount0Max The maximum amount of token0 to forward on mint
    /// @param amount1Max The maximum amount of token1 to forward on mint
    /// @return amount0 actual amount of token0 to forward when minting `mintAmount`
    /// @return amount1 actual amount of token1 to forward when minting `mintAmount`
    /// @return mintAmount maximum number of shares mintable
    function getMintAmounts(uint256 amount0Max, uint256 amount1Max)
        external
        view
        override
        returns (
            uint256 amount0,
            uint256 amount1,
            uint256 mintAmount
        )
    {
        if (!initialized) revert NotInitialized();
        uint256 totalSupply = totalSupply();
        if (totalSupply > 0) {
            (
                amount0,
                amount1,
                mintAmount
            ) = _calcMintAmounts(
                totalSupply,
                amount0Max,
                amount1Max
            );
        } else {
            (uint160 sqrtRatioX96, , , , , , ) = pool.slot0();
            uint128 newLiquidity =
                LiquidityAmounts.getLiquidityForAmounts(
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

    /// @notice compute total underlying holdings of the G-UNI token supply
    /// includes current liquidity invested in uniswap position, current fees earned
    /// and any uninvested leftover (but does not include manager or gelato fees accrued)
    /// @return amount0Current current total underlying balance of token0
    /// @return amount1Current current total underlying balance of token1
    function getUnderlyingBalances()
        public
        view
        override
        returns (uint256 amount0Current, uint256 amount1Current)
    {
        (uint160 sqrtRatioX96, int24 tick, , , , , ) = pool.slot0();
        return _getUnderlyingBalances(sqrtRatioX96, tick);
    }

    function getUnderlyingBalancesAtPrice(uint160 sqrtRatioX96)
        external
        view
        override
        returns (uint256 amount0Current, uint256 amount1Current)
    {
        (, int24 tick, , , , , ) = pool.slot0();
        return _getUnderlyingBalances(sqrtRatioX96, tick);
    }

    function getCurrentFees()
        external
        view
        override
        returns (uint256 fee0, uint256 fee1)
    {
        (, int24 tick, , , , , ) = pool.slot0();
        (
            uint128 liquidity,
            uint256 feeGrowthInside0Last,
            uint256 feeGrowthInside1Last,
            uint128 tokensOwed0,
            uint128 tokensOwed1
        ) = pool.positions(getPositionID());
        fee0 = _feesEarned(
            true,
            feeGrowthInside0Last,
            tick,
            liquidity
        ) + uint256(tokensOwed0);
        fee1 = _feesEarned(
            false,
            feeGrowthInside1Last,
            tick,
            liquidity
        ) + uint256(tokensOwed1);
        (fee0, fee1) = _netFees(fee0, fee1);
    }

    function _getUnderlyingBalances(uint160 sqrtRatioX96, int24 tick)
        internal
        view
        returns (uint256 amount0Current, uint256 amount1Current)
    {
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
            (
                amount0Current,
                amount1Current
            ) = LiquidityAmounts.getAmountsForLiquidity(
                sqrtRatioX96,
                lowerTick.getSqrtRatioAtTick(),
                upperTick.getSqrtRatioAtTick(),
                liquidity
            );
            fee0 = _feesEarned(
                true,
                feeGrowthInside0Last,
                tick,
                liquidity
            ) + uint256(tokensOwed0);
            fee1 = _feesEarned(
                false,
                feeGrowthInside1Last,
                tick,
                liquidity
            ) + uint256(tokensOwed1);
            (fee0, fee1) = _netFees(fee0, fee1);
        }

        amount0Current += fee0
            + token0.balanceOf(address(this))
            - managerBalance0
            - treasury0;
        amount1Current += fee1
            + token1.balanceOf(address(this))
            - managerBalance1
            - treasury1;
    }

    function _withdraw(
        int24 lowerTick_,
        int24 upperTick_,
        uint128 liquidity
    )
        private
        returns (
            uint256 burn0,
            uint256 burn1,
            uint256 fee0,
            uint256 fee1
        )
    {
        uint256 preBalance0 = token0.balanceOf(address(this));
        uint256 preBalance1 = token1.balanceOf(address(this));
        (burn0, burn1) = pool.burn(
            lowerTick_,
            upperTick_,
            liquidity
        );
        pool.collect(
            address(this),
            lowerTick_,
            upperTick_,
            type(uint128).max,
            type(uint128).max
        );
        fee0 = token0.balanceOf(address(this))
            - preBalance0
            - burn0;
        fee1 = token1.balanceOf(address(this))
            - preBalance1
            - burn1;
    }

    function _calcMintAmounts(
        uint256 totalSupply,
        uint256 amount0Max,
        uint256 amount1Max
    )
        private
        view
        returns (
            uint256 amount0,
            uint256 amount1,
            uint256 mintAmount
        )
    {
        (
            uint256 amount0Current,
            uint256 amount1Current
        ) = getUnderlyingBalances();
        if (amount0Current == 0 && amount1Current > 0) {
            mintAmount = FullMath.mulDiv(
                amount1Max,
                totalSupply,
                amount1Current
            );
        } else if (amount1Current == 0 && amount0Current > 0) {
            mintAmount = FullMath.mulDiv(
                amount0Max,
                totalSupply,
                amount0Current
            );
        } else if (amount0Current == 0 && amount1Current == 0) {
            revert ZeroUnderlyingBalance();
        } else {
            uint256 amount0Mint = FullMath.mulDiv(
                amount0Max,
                totalSupply,
                amount0Current
            );
            uint256 amount1Mint = FullMath.mulDiv(
                amount1Max,
                totalSupply,
                amount1Current
            );
            if (amount0Mint == 0 || amount1Mint == 0) revert ZeroMintAmount();
            mintAmount = amount0Mint < amount1Mint
                ? amount0Mint
                : amount1Mint;
        }

        amount0 = FullMath.mulDivRoundingUp(
            mintAmount,
            amount0Current,
            totalSupply
        );
        amount1 = FullMath.mulDivRoundingUp(
            mintAmount,
            amount1Current,
            totalSupply
        );
    }

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
            if (tick >= lowerTick) feeGrowthBelow = feeGrowthOutsideLower;
            else feeGrowthBelow = feeGrowthGlobal - feeGrowthOutsideLower;

            uint256 feeGrowthAbove;
            if (tick < upperTick) feeGrowthAbove = feeGrowthOutsideUpper;
            else feeGrowthAbove = feeGrowthGlobal - feeGrowthOutsideUpper;

            uint256 feeGrowthInside = feeGrowthGlobal
                - feeGrowthBelow
                - feeGrowthAbove;

            fee = FullMath.mulDiv(
                liquidity,
                feeGrowthInside - feeGrowthInsideLast,
                0x100000000000000000000000000000000
            );
        }
    }

    function _applyFees(uint256 _fee0, uint256 _fee1) private {
        treasury0 += (_fee0 * treasuryFee) / 10_000;
        treasury1 += (_fee1 * treasuryFee) / 10_000;
        // managerFee is read from storage, so storing in a local variable saves gas cost.
        uint16 _managerFee = managerFee;
        managerBalance0 += (_fee0 * _managerFee) / 10_000;
        managerBalance1 += (_fee1 * _managerFee) / 10_000;
    }

    function _netFees(uint256 rawFee0, uint256 rawFee1) private view returns (uint256 fee0, uint256 fee1) {
        // managerFee is read from storage, so storing in a local variable saves gas cost.
        uint16 _managerFee = managerFee;
        uint256 deduct0 = (rawFee0 * (treasuryFee + _managerFee)) / 10_000;
        uint256 deduct1 = (rawFee1 * (treasuryFee + _managerFee)) / 10_000;
        fee0 = rawFee0 - deduct0;
        fee1 = rawFee1 - deduct1;
    }

    function _validateTicks(int24 _lowerTick, int24 _upperTick) private view {
        if (_lowerTick < TickMath.MIN_TICK || _upperTick > TickMath.MAX_TICK)
            revert TicksOutOfRange();

        if (
            _lowerTick >= _upperTick
            || _lowerTick % tickSpacing != 0
            || _upperTick % tickSpacing != 0
        ) revert InvalidTicksSpacing();
    }
}
