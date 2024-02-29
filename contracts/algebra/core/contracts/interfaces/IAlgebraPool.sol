// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.4;

interface IAlgebraPool {
    /// @notice Sets the initial price for the pool
    /// @dev Price is represented as a sqrt(amountToken1/amountToken0) Q64.96 value
    /// @dev Initialization should be done in one transaction with pool creation to avoid front-running
    /// @param initialPrice The initial sqrt price of the pool as a Q64.96
    function initialize(uint160 initialPrice) external;

    /// @notice Adds liquidity for the given recipient/bottomTick/topTick position
    /// @dev The caller of this method receives a callback in the form of IAlgebraMintCallback# AlgebraMintCallback
    /// in which they must pay any token0 or token1 owed for the liquidity. The amount of token0/token1 due depends
    /// on bottomTick, topTick, the amount of liquidity, and the current price.
    /// @param leftoversRecipient The address which will receive potential surplus of paid tokens
    /// @param recipient The address for which the liquidity will be created
    /// @param bottomTick The lower tick of the position in which to add liquidity
    /// @param topTick The upper tick of the position in which to add liquidity
    /// @param liquidityDesired The desired amount of liquidity to mint
    /// @param data Any data that should be passed through to the callback
    /// @return amount0 The amount of token0 that was paid to mint the given amount of liquidity. Matches the value in the callback
    /// @return amount1 The amount of token1 that was paid to mint the given amount of liquidity. Matches the value in the callback
    /// @return liquidityActual The actual minted amount of liquidity
    function mint(
        address leftoversRecipient,
        address recipient,
        int24 bottomTick,
        int24 topTick,
        uint128 liquidityDesired,
        bytes calldata data
    ) external returns (uint256 amount0, uint256 amount1, uint128 liquidityActual);

    /// @notice Collects tokens owed to a position
    /// @dev Does not recompute fees earned, which must be done either via mint or burn of any amount of liquidity.
    /// Collect must be called by the position owner. To withdraw only token0 or only token1, amount0Requested or
    /// amount1Requested may be set to zero. To withdraw all tokens owed, caller may pass any value greater than the
    /// actual tokens owed, e.g. type(uint128).max. Tokens owed may be from accumulated swap fees or burned liquidity.
    /// @param recipient The address which should receive the fees collected
    /// @param bottomTick The lower tick of the position for which to collect fees
    /// @param topTick The upper tick of the position for which to collect fees
    /// @param amount0Requested How much token0 should be withdrawn from the fees owed
    /// @param amount1Requested How much token1 should be withdrawn from the fees owed
    /// @return amount0 The amount of fees collected in token0
    /// @return amount1 The amount of fees collected in token1
    function collect(
        address recipient,
        int24 bottomTick,
        int24 topTick,
        uint128 amount0Requested,
        uint128 amount1Requested
    ) external returns (uint128 amount0, uint128 amount1);

    /// @notice Burn liquidity from the sender and account tokens owed for the liquidity to the position
    /// @dev Can be used to trigger a recalculation of fees owed to a position by calling with an amount of 0
    /// @dev Fees must be collected separately via a call to #collect
    /// @param bottomTick The lower tick of the position for which to burn liquidity
    /// @param topTick The upper tick of the position for which to burn liquidity
    /// @param amount How much liquidity to burn
    /// @param data Any data that should be passed through to the plugin
    /// @return amount0 The amount of token0 sent to the recipient
    /// @return amount1 The amount of token1 sent to the recipient
    function burn(
        int24 bottomTick,
        int24 topTick,
        uint128 amount,
        bytes calldata data
    ) external returns (uint256 amount0, uint256 amount1);

    /// @notice Swap token0 for token1, or token1 for token0
    /// @dev The caller of this method receives a callback in the form of IAlgebraSwapCallback#AlgebraSwapCallback
    /// @param recipient The address to receive the output of the swap
    /// @param zeroToOne The direction of the swap, true for token0 to token1, false for token1 to token0
    /// @param amountRequired The amount of the swap, which implicitly configures the swap as exact input (positive), or exact output (negative)
    /// @param limitSqrtPrice The Q64.96 sqrt price limit. If zero for one, the price cannot be less than this
    /// value after the swap. If one for zero, the price cannot be greater than this value after the swap
    /// @param data Any data to be passed through to the callback. If using the Router it should contain SwapRouter#SwapCallbackData
    /// @return amount0 The delta of the balance of token0 of the pool, exact when negative, minimum when positive
    /// @return amount1 The delta of the balance of token1 of the pool, exact when negative, minimum when positive
    function swap(
        address recipient,
        bool zeroToOne,
        int256 amountRequired,
        uint160 limitSqrtPrice,
        bytes calldata data
    ) external returns (int256 amount0, int256 amount1);

    /// @notice Swap token0 for token1, or token1 for token0 with prepayment
    /// @dev The caller of this method receives a callback in the form of IAlgebraSwapCallback#AlgebraSwapCallback
    /// caller must send tokens in callback before swap calculation
    /// the actually sent amount of tokens is used for further calculations
    /// @param leftoversRecipient The address which will receive potential surplus of paid tokens
    /// @param recipient The address to receive the output of the swap
    /// @param zeroToOne The direction of the swap, true for token0 to token1, false for token1 to token0
    /// @param amountToSell The amount of the swap, only positive (exact input) amount allowed
    /// @param limitSqrtPrice The Q64.96 sqrt price limit. If zero for one, the price cannot be less than this
    /// value after the swap. If one for zero, the price cannot be greater than this value after the swap
    /// @param data Any data to be passed through to the callback. If using the Router it should contain SwapRouter#SwapCallbackData
    /// @return amount0 The delta of the balance of token0 of the pool, exact when negative, minimum when positive
    /// @return amount1 The delta of the balance of token1 of the pool, exact when negative, minimum when positive
    function swapWithPaymentInAdvance(
        address leftoversRecipient,
        address recipient,
        bool zeroToOne,
        int256 amountToSell,
        uint160 limitSqrtPrice,
        bytes calldata data
    ) external returns (int256 amount0, int256 amount1);

    /// @notice Receive token0 and/or token1 and pay it back, plus a fee, in the callback
    /// @dev The caller of this method receives a callback in the form of IAlgebraFlashCallback#AlgebraFlashCallback
    /// @dev All excess tokens paid in the callback are distributed to currently in-range liquidity providers as an additional fee.
    /// If there are no in-range liquidity providers, the fee will be transferred to the first active provider in the future
    /// @param recipient The address which will receive the token0 and token1 amounts
    /// @param amount0 The amount of token0 to send
    /// @param amount1 The amount of token1 to send
    /// @param data Any data to be passed through to the callback
    function flash(
        address recipient,
        uint256 amount0,
        uint256 amount1,
        bytes calldata data
    ) external;

    // ####  pool errors  ####

    /// @notice Emitted by the reentrancy guard
    error locked();

    /// @notice Emitted if arithmetic error occurred
    error arithmeticError();

    /// @notice Emitted if an attempt is made to initialize the pool twice
    error alreadyInitialized();

    /// @notice Emitted if an attempt is made to mint or swap in uninitialized pool
    error notInitialized();

    /// @notice Emitted if 0 is passed as amountRequired to swap function
    error zeroAmountRequired();

    /// @notice Emitted if invalid amount is passed as amountRequired to swap function
    error invalidAmountRequired();

    /// @notice Emitted if the pool received fewer tokens than it should have
    error insufficientInputAmount();

    /// @notice Emitted if there was an attempt to mint zero liquidity
    error zeroLiquidityDesired();
    /// @notice Emitted if actual amount of liquidity is zero (due to insufficient amount of tokens received)
    error zeroLiquidityActual();

    /// @notice Emitted if the pool received fewer tokens{0,1} after flash than it should have
    error flashInsufficientPaid0();
    error flashInsufficientPaid1();

    /// @notice Emitted if limitSqrtPrice param is incorrect
    error invalidLimitSqrtPrice();

    /// @notice Tick must be divisible by tickspacing
    error tickIsNotSpaced();

    /// @notice Emitted if a method is called that is accessible only to the factory owner or dedicated role
    error notAllowed();
    /// @notice Emitted if a method is called that is accessible only to the farming
    error onlyFarming();

    error invalidNewTickSpacing();
    error invalidNewCommunityFee();

    error dynamicFeeActive();
    error dynamicFeeDisabled();

    error pluginIsNotConnected();

    error invalidHookResponse(bytes4 selector);

    // ####  LiquidityMath errors  ####
    /// @notice Emitted if liquidity underflows
    error liquiditySub();
    /// @notice Emitted if liquidity overflows
    error liquidityAdd();

    // ####  TickManagement errors  ####
    error topTickLowerOrEqBottomTick();
    error bottomTickLowerThanMIN();
    error topTickAboveMAX();
    error liquidityOverflow();
    error tickIsNotInitialized();
    error tickInvalidLinks();

    // ####  SafeTransfer errors  ####
    error transferFailed();

    // ####  TickMath errors  ####
    error tickOutOfRange();
    error priceOutOfRange();

    /// @notice The Algebra factory contract, which must adhere to the IAlgebraFactory interface
    /// @return The contract address
    function factory() external view returns (address);

    /// @notice The first of the two tokens of the pool, sorted by address
    /// @return The token contract address
    function token0() external view returns (address);

    /// @notice The second of the two tokens of the pool, sorted by address
    /// @return The token contract address
    function token1() external view returns (address);

    /// @notice The contract to which community fees are transferred
    /// @return The communityVault address
    function communityVault() external view returns (address);

    /// @notice The maximum amount of position liquidity that can use any tick in the range
    /// @dev This parameter is enforced per tick to prevent liquidity from overflowing a uint128 at any point, and
    /// also prevents out-of-range liquidity from being used to prevent adding in-range liquidity to a pool
    /// @return The max amount of liquidity per tick
    function maxLiquidityPerTick() external view returns (uint128);

    /// @notice The globalState structure in the pool stores many values but requires only one slot
    /// and is exposed as a single method to save gas when accessed externally.
    /// @return price The current price of the pool as a sqrt(dToken1/dToken0) Q64.96 value
    /// @return tick The current tick of the pool, i.e. according to the last tick transition that was run
    /// This value may not always be equal to SqrtTickMath.getTickAtSqrtRatio(price) if the price is on a tick boundary
    /// @return fee The last known pool fee value in hundredths of a bip, i.e. 1e-6
    /// @return pluginConfig The current plugin config. Each bit of the config is responsible for enabling/disabling the hooks
    /// The last bit indicates whether the plugin contains dynamic fees logic
    /// @return communityFee The community fee percentage of the swap fee in thousandths (1e-3)
    /// @return unlocked Whether the pool is currently locked to reentrancy
    function globalState()
        external
        view
        returns (
            uint160 price,
            int24 tick,
            uint16 fee,
            uint8 pluginConfig,
            uint16 communityFee,
            bool unlocked
        );

    /// @notice Look up information about a specific tick in the pool
    /// @param tick The tick to look up
    /// @return liquidityTotal The total amount of position liquidity that uses the pool either as tick lower or tick upper
    /// @return liquidityDelta How much liquidity changes when the pool price crosses the tick
    /// @return prevTick The previous tick in tick list
    /// @return nextTick The next tick in tick list
    /// @return outerFeeGrowth0Token The fee growth on the other side of the tick from the current tick in token0
    /// @return outerFeeGrowth1Token The fee growth on the other side of the tick from the current tick in token1
    /// In addition, these values are only relative and must be used only in comparison to previous snapshots for
    /// a specific position.
    function ticks(
        int24 tick
    )
        external
        view
        returns (
            uint256 liquidityTotal,
            int128 liquidityDelta,
            int24 prevTick,
            int24 nextTick,
            uint256 outerFeeGrowth0Token,
            uint256 outerFeeGrowth1Token
        );

    /// @notice The timestamp of the last sending of tokens to community vault
    /// @return The timestamp truncated to 32 bits
    function communityFeeLastTimestamp() external view returns (uint32);

    /// @notice The amounts of token0 and token1 that will be sent to the vault
    /// @dev Will be sent COMMUNITY_FEE_TRANSFER_FREQUENCY after communityFeeLastTimestamp
    /// @return communityFeePending0 The amount of token0 that will be sent to the vault
    /// @return communityFeePending1 The amount of token1 that will be sent to the vault
    function getCommunityFeePending()
        external
        view
        returns (uint128 communityFeePending0, uint128 communityFeePending1);

    /// @notice Returns the address of currently used plugin
    /// @dev The plugin is subject to change
    /// @return pluginAddress The address of currently used plugin
    function plugin() external view returns (address pluginAddress);

    /// @notice Returns 256 packed tick initialized boolean values. See TickTree for more information
    /// @param wordPosition Index of 256-bits word with ticks
    /// @return The 256-bits word with packed ticks info
    function tickTable(int16 wordPosition) external view returns (uint256);

    /// @notice The fee growth as a Q128.128 fees of token0 collected per unit of liquidity for the entire life of the pool
    /// @dev This value can overflow the uint256
    /// @return The fee growth accumulator for token0
    function totalFeeGrowth0Token() external view returns (uint256);

    /// @notice The fee growth as a Q128.128 fees of token1 collected per unit of liquidity for the entire life of the pool
    /// @dev This value can overflow the uint256
    /// @return The fee growth accumulator for token1
    function totalFeeGrowth1Token() external view returns (uint256);

    /// @notice The current pool fee value
    /// @dev In case dynamic fee is enabled in the pool, this method will call the plugin to get the current fee.
    /// If the plugin implements complex fee logic, this method may return an incorrect value or revert.
    /// In this case, see the plugin implementation and related documentation.
    /// @return currentFee The current pool fee value in hundredths of a bip, i.e. 1e-6
    function fee() external view returns (uint16 currentFee);

    /// @notice The tracked token0 and token1 reserves of pool
    /// @dev If at any time the real balance is larger, the excess will be transferred to liquidity providers as additional fee.
    /// If the balance exceeds uint128, the excess will be sent to the communityVault.
    /// @return reserve0 The last known reserve of token0
    /// @return reserve1 The last known reserve of token1
    function getReserves() external view returns (uint128 reserve0, uint128 reserve1);

    /// @notice Returns the information about a position by the position's key
    /// @param key The position's key is a packed concatenation of the owner address, bottomTick and topTick indexes
    /// @return liquidity The amount of liquidity in the position
    /// @return innerFeeGrowth0Token Fee growth of token0 inside the tick range as of the last mint/burn/poke
    /// @return innerFeeGrowth1Token Fee growth of token1 inside the tick range as of the last mint/burn/poke
    /// @return fees0 The computed amount of token0 owed to the position as of the last mint/burn/poke
    /// @return fees1 The computed amount of token1 owed to the position as of the last mint/burn/poke
    function positions(
        bytes32 key
    )
        external
        view
        returns (
            uint256 liquidity,
            uint256 innerFeeGrowth0Token,
            uint256 innerFeeGrowth1Token,
            uint128 fees0,
            uint128 fees1
        );

    /// @notice The currently in range liquidity available to the pool
    /// @dev This value has no relationship to the total liquidity across all ticks.
    /// Returned value cannot exceed type(uint128).max
    /// @return The current in range liquidity
    function liquidity() external view returns (uint128);

    /// @notice The current tick spacing
    /// @dev Ticks can only be initialized by new mints at multiples of this value
    /// e.g.: a tickSpacing of 60 means ticks can be initialized every 60th tick, i.e., ..., -120, -60, 0, 60, 120, ...
    /// However, tickspacing can be changed after the ticks have been initialized.
    /// This value is an int24 to avoid casting even though it is always positive.
    /// @return The current tick spacing
    function tickSpacing() external view returns (int24);

    /// @notice The previous initialized tick before (or at) current global tick
    /// @return The previous initialized tick
    function prevTickGlobal() external view returns (int24);

    /// @notice The next initialized tick after current global tick
    /// @return The next initialized tick
    function nextTickGlobal() external view returns (int24);
}
