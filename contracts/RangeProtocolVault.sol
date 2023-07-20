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

import {DataTypesLib} from "./libraries/DataTypesLib.sol";
import {LogicLib} from "./libraries/LogicLib.sol";
import {IPancakeV3Pool} from "./pancake/interfaces/IPancakeV3Pool.sol";
import {IRangeProtocolVault} from "./interfaces/IRangeProtocolVault.sol";
import {OwnableUpgradeable} from "./access/OwnableUpgradeable.sol";
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
    IRangeProtocolVault
{
    DataTypesLib.State private state;

    modifier onlyVault() {
        require(msg.sender == address(this));
        _;
    }

    constructor() {
        _disableInitializers();
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
        (address manager, string memory _name, string memory _symbol) = abi.decode(
            data,
            (address, string, string)
        );

        __UUPSUpgradeable_init();
        __ReentrancyGuard_init();
        __Ownable_init();
        __ERC20_init(_name, _symbol);
        __Pausable_init();

        _transferOwnership(manager);

        state.poolData.pool = IPancakeV3Pool(_pool);
        state.poolData.token0 = IERC20Upgradeable(state.poolData.pool.token0());
        state.poolData.token1 = IERC20Upgradeable(state.poolData.pool.token1());
        state.poolData.tickSpacing = _tickSpacing;
        state.poolData.factory = msg.sender;

        state.feeData.performanceFee = 250;
        state.feeData.managingFee = 0;
        // Managing fee is 0% at the time vault initialization.
        emit FeesUpdated(0, state.feeData.performanceFee);
    }

    /**
     * @notice updateTicks it is called by the contract manager to update the ticks.
     * It can only be called once total supply is zero and the vault has not active position
     * in the pancake pool
     * @param _lowerTick lowerTick to set
     * @param _upperTick upperTick to set
     */
    function updateTicks(int24 _lowerTick, int24 _upperTick) external override onlyManager {
        LogicLib.updateTicks(state.poolData, _lowerTick, _upperTick);
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
        LogicLib.pancakeV3MintCallback(state.poolData, amount0Owed, amount1Owed, "");
    }

    /// @notice pancakeV3SwapCallback Pancake v3 callback fn, called back on pool.swap
    function pancakeV3SwapCallback(
        int256 amount0Delta,
        int256 amount1Delta,
        bytes calldata
    ) external override {
        LogicLib.pancakeV3SwapCallback(state.poolData, amount0Delta, amount1Delta, "");
    }

    /**
     * @notice mint mints range vault shares, fractional shares of a Pancake V3 position/strategy
     * to compute the amount of tokens necessary to mint `mintAmount` see getMintAmounts
     * @param mintAmount The number of shares to mint
     * @return amount0 amount of token0 transferred from msg.sender to mint `mintAmount`
     * @return amount1 amount of token1 transferred from msg.sender to mint `mintAmount`
     */
    function mint(
        uint256 mintAmount
    )
        external
        payable
        override
        nonReentrant
        whenNotPaused
        returns (uint256 amount0, uint256 amount1)
    {
        return LogicLib.mint(state.poolData, state.userData, state.feeData, mintAmount);
    }

    /**
     * @notice burn burns range vault shares (shares of a Pancake V3 position) and receive underlying
     * @param burnAmount The number of shares to burn
     * @return amount0 amount of token0 transferred to msg.sender for burning {burnAmount}
     * @return amount1 amount of token1 transferred to msg.sender for burning {burnAmount}
     */
    function burn(
        uint256 burnAmount,
        bool withdrawNative
    ) external override nonReentrant whenNotPaused returns (uint256 amount0, uint256 amount1) {
        return
            LogicLib.burn(
                state.poolData,
                state.userData,
                state.feeData,
                burnAmount,
                withdrawNative
            );
    }

    function mintShares(address to, uint256 shareAmount) external override onlyVault {
        _mint(to, shareAmount);
    }

    function burnShares(address from, uint256 shareAmount) external override onlyVault {
        _burn(from, shareAmount);
    }

    /**
     * @notice removeLiquidity removes liquidity from pancake pool and receives underlying tokens
     * in the vault contract.
     */
    function removeLiquidity() external override onlyManager {
        LogicLib.removeLiquidity(state.poolData, state.feeData);
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
        return LogicLib.swap(state.poolData, zeroForOne, swapAmount, sqrtPriceLimitX96);
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
        int24 newLowerTick,
        int24 newUpperTick,
        uint256 amount0,
        uint256 amount1
    ) external override onlyManager returns (uint256 remainingAmount0, uint256 remainingAmount1) {
        return LogicLib.addLiquidity(state.poolData, newUpperTick, newLowerTick, amount0, amount1);
    }

    /**
     * @dev pullFeeFromPool pulls accrued fee from pancake v3 pool that position has accrued since
     * last collection.
     */
    function pullFeeFromPool() external onlyManager {
        LogicLib.pullFeeFromPool(state.poolData, state.feeData);
    }

    /// @notice collectManager collects manager fees accrued
    function collectManager() external override onlyManager {
        LogicLib.collectManager(state.poolData, state.feeData, manager());
    }

    /**
     * @notice updateFees allows updating of managing and performance fees
     */
    function updateFees(
        uint16 newManagingFee,
        uint16 newPerformanceFee
    ) external override onlyManager {
        LogicLib.updateFees(state.feeData, newManagingFee, newPerformanceFee);
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
        return LogicLib.getMintAmounts(state.poolData, state.feeData, amount0Max, amount1Max);
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
        uint160 sqrtRatioX96
    ) external view override returns (uint256 amount0Current, uint256 amount1Current) {
        return LogicLib.getUnderlyingBalancesAtPrice(state.poolData, state.feeData, sqrtRatioX96);
    }

    /**
     * @notice getCurrentFees returns the current uncollected fees
     * @return fee0 uncollected fee in token0
     * @return fee1 uncollected fee in token1
     */
    function getCurrentFees() external view override returns (uint256 fee0, uint256 fee1) {
        return LogicLib.getCurrentFees(state.poolData, state.feeData);
    }

    /**
     * @notice returns array of current user vaults. This function is only intended to be called off-chain.
     * @param fromIdx start index to fetch the user vaults info from.
     * @param toIdx end index to fetch the user vault to.
     */
    function getUserVaults(
        uint256 fromIdx,
        uint256 toIdx
    ) external view override returns (DataTypesLib.UserVaultInfo[] memory) {
        return LogicLib.getUserVaults(state.userData, fromIdx, toIdx);
    }

    /**
     * @dev returns the length of users array.
     */
    function userCount() external view returns (uint256) {
        return LogicLib.userCount(state.userData);
    }

    /**
     * @notice getPositionID returns the position id of the vault in pancake pool
     * @return positionID position id of the vault in pancake pool
     */
    function getPositionID() public view override returns (bytes32 positionID) {
        return LogicLib.getPositionID(state.poolData);
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
        return LogicLib.getUnderlyingBalances(state.poolData, state.feeData);
    }

    function getUnderlyingBalancesByShare(
        uint256 shares
    ) external view returns (uint256 amount0, uint256 amount1) {
        return LogicLib.getUnderlyingBalancesByShare(state.poolData, state.feeData, shares);
    }

    /**
     * @notice _authorizeUpgrade internally called by UUPS contract to validate the upgrading operation of
     * the contract.
     */
    function _authorizeUpgrade(address) internal override {
        if (msg.sender != state.poolData.factory) revert VaultErrors.OnlyFactoryAllowed();
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
        LogicLib.beforeTokenTransfer(state.userData, from, to, amount);
    }
}
