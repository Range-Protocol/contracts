//SPDX-License-Identifier: MIT
pragma solidity 0.8.4;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {ERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import {SafeERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import {IERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import {OwnableUpgradeable} from "./access/OwnableUpgradeable.sol";
import {RangeProtocolVaultStorage} from "./RangeProtocolVaultStorage.sol";
import {IiZiSwapPool} from "./iZiSwap/interfaces/IiZiSwapPool.sol";
import {VaultLib} from "./libraries/VaultLib.sol";
import {VaultErrors} from "./errors/VaultErrors.sol";

/**
 * @notice RangeProtocolVault is a vault for AMM pools with a pair of tokens.
 * It has mint and burn functions for the users to provide liquidity in token0 and token1 and has
 * functions removeLiquidity, addLiquidity and swap for the manager to manage liquidity. Upon vault deployment, the
 * manager calls updateTicks function to start the minting process by users at a specified points range. Once the mint
 * has started, the liquidity provided by users directly go to the AMM pool. The manager can remove liquidity from
 * the AMM pool and for providing liquidity into a newer points range, manager will perform swap to have tokens in ratio
 * accordingly to the newer points range and call addLiquidity function to add to a newer points range.
 */
contract RangeProtocolVault is
    Initializable,
    UUPSUpgradeable,
    ReentrancyGuardUpgradeable,
    OwnableUpgradeable,
    ERC20Upgradeable,
    PausableUpgradeable,
    RangeProtocolVaultStorage
{
    using SafeERC20Upgradeable for IERC20Upgradeable;

    // @notice restricts the call by self. It used to restrict the allowed calls only from the VaultLib.
    modifier onlySelfCall() {
        if (msg.sender != address(this)) revert VaultErrors.OnlySelfCallAllowed();
        _;
    }

    constructor() {
        _disableInitializers();
    }

    /**
     * @notice initialised the vault's initial sate.
     * @param _pool address of pool with which the vault interacts.
     * @param _pointDelta tick spacing of the pool.
     * @param data additional data of the vault.
     */
    function initialize(
        address _pool,
        int24 _pointDelta,
        bytes memory data
    ) external override initializer {
        (address manager, string memory _name, string memory _symbol) = abi.decode(
            data,
            (address, string, string)
        );

        // reverts if manager address provided is zero.
        if (manager == address(0x0)) revert VaultErrors.ZeroManagerAddress();
        __UUPSUpgradeable_init();
        __ReentrancyGuard_init();
        __Ownable_init();
        __ERC20_init(_name, _symbol);
        __Pausable_init();

        state.pool = IiZiSwapPool(_pool);
        state.tokenX = IERC20Upgradeable(state.pool.tokenX());
        state.tokenY = IERC20Upgradeable(state.pool.tokenY());
        state.pointDelta = _pointDelta;
        state.factory = msg.sender;
        // Managing fee is 0% and performance is 10% at the time vault initialization.
        VaultLib.updateFees(state, 0, 1000);

        _transferOwnership(manager);
    }

    /**
     * @notice updates the points range upon vault deployment or when the vault is out of position and totalSupply is zero.
     * It can only be called by the manager. It calls updatePoints function on the VaultLib to execute logic.
     *  @param leftPoint lower tick of the position.
     * @param rightPoint upper tick of the position.
     */
    function updatePoints(int24 leftPoint, int24 rightPoint) external override onlyManager {
        VaultLib.updatePoints(state, leftPoint, rightPoint);
    }

    // @notice pauses the mint and burn functions. It can only be called by the vault manager.
    function pause() external onlyManager {
        _pause();
    }

    // @notice unpauses the mint and burn functions. It can only be called by the vault manager.
    function unpause() external onlyManager {
        _unpause();
    }

    /**
     * @notice mint callback implementation.
     * @param tokenXAmount amount in tokenX to transfer.
     * @param tokenYAmount amount in tokenY to transfer.
     */
    function mintDepositCallback(
        uint256 tokenXAmount,
        uint256 tokenYAmount,
        bytes calldata
    ) external override {
        if (msg.sender != address(state.pool)) revert VaultErrors.OnlyPoolAllowed();
        if (tokenXAmount > 0) state.tokenX.safeTransfer(msg.sender, tokenXAmount);
        if (tokenYAmount > 0) state.tokenY.safeTransfer(msg.sender, tokenYAmount);
    }

    /**
     * @notice swap callback implementation.
     * @param tokenXAmount amountX sent to the pool.
     */
    function swapX2YCallback(uint256 tokenXAmount, uint256, bytes calldata) external override {
        if (msg.sender != address(state.pool)) revert VaultErrors.OnlyPoolAllowed();
        if (tokenXAmount > 0) state.tokenX.safeTransfer(msg.sender, tokenXAmount);
    }

    /**
     * @notice swap callback implementation.
     * @param tokenYAmount amountY send to pool.
     */
    function swapY2XCallback(uint256, uint256 tokenYAmount, bytes calldata) external override {
        if (msg.sender != address(state.pool)) revert VaultErrors.OnlyPoolAllowed();
        if (tokenYAmount > 0) state.tokenY.safeTransfer(msg.sender, tokenYAmount);
    }

    /**
     * @notice mints shares to the provided address. Only the vault itself is allowed to call this function. The VaultLib
     * used by the vault calls to mint shares to an address.
     * @param to the address to mint shares to.
     * @param amount the amount of shares to mint.
     */
    function mintTo(address to, uint256 amount) external override onlySelfCall {
        _mint(to, amount);
    }

    /**
     * @notice burns shares from the provided address. Only the vault itself is allowed to call this function. The VaultLib
     *  used by the vault calls to burn shares from an address.
     * @notice from the address to burn shares from.
     * @notice amount the amount of shares to burn.
     */
    function burnFrom(address from, uint256 amount) external override onlySelfCall {
        _burn(from, amount);
    }

    /**
     * @notice called by the user with collateral amount to provide liquidity in collateral amount. Calls mint function
     * on the VaultLib to execute logic.
     * @param mintAmount the amount of shares to mint.
     * @param maxAmounts amount of tokenX and tokenY user desires to add.
     * @return amountX the amount of tokenX taken from the user.
     * @return amountY the amount of tokenY taken from the user.
     */
    function mint(
        uint256 mintAmount,
        uint256[2] calldata maxAmounts
    ) external override nonReentrant whenNotPaused returns (uint256 amountX, uint256 amountY) {
        return VaultLib.mint(state, mintAmount, maxAmounts);
    }

    /**
     * @notice called by the user with share amount to burn their vault shares and redeem their share of the asset. Calls
     * burn function on the VaultLib to execute logic.
     * @param burnAmount the amount of vault shares to burn.
     * @return amountX the amount of tokenX received by the user.
     * @return amountY the amount of tokenY received by the user.
     */
    function burn(
        uint256 burnAmount,
        uint256[2] calldata minAmounts
    ) external override nonReentrant returns (uint256 amountX, uint256 amountY) {
        return VaultLib.burn(state, burnAmount, minAmounts);
    }

    // @notice called by manager to remove liquidity from the pool. Calls removeLiquidity function on the VaultLib.
    function removeLiquidity(uint256[2] calldata minAmounts) external override onlyManager {
        VaultLib.removeLiquidity(state, minAmounts);
    }

    /**
     * @notice called by manager to perform swap from token0 to token1 and vice-versa. Calls swap function on the VaultLib.
     * @param zeroForOne swap direction (true -> x to y) or (false -> y to x)
     * @param swapAmount amount to swap.
     * @param pointLimit the limit pool tick can move when filling the order.
     * @param amountX amountX added to or taken from the vault.
     * @param amountY amountY added to or taken from the vault.
     */
    function swap(
        bool zeroForOne,
        uint128 swapAmount,
        int24 pointLimit,
        uint256 minAmountIn
    ) external override onlyManager returns (uint256 amountX, uint256 amountY) {
        return VaultLib.swap(state, zeroForOne, swapAmount, pointLimit, minAmountIn);
    }

    /**
     * @notice called by manager to provide liquidity to pool into a newer tick range. Calls addLiquidity function on
     * the VaultLib.
     * @param newLeftPoint lower tick of the position.
     * @param newRightPoint upper tick of the position.
     * @param amountX amount in token0 to add.
     * @param amountY amount in token1 to add.
     * @param maxAmounts max amounts to add for tokenX and tokenY.
     * @return remainingAmountX amount in token0 left passive in the vault.
     * @return remainingAmountY amount in token1 left passive in the vault.
     */
    function addLiquidity(
        int24 newLeftPoint,
        int24 newRightPoint,
        uint128 amountX,
        uint128 amountY,
        uint256[2] calldata maxAmounts
    ) external override onlyManager returns (uint256 remainingAmountX, uint256 remainingAmountY) {
        return
            VaultLib.addLiquidity(state, newLeftPoint, newRightPoint, amountX, amountY, maxAmounts);
    }

    /**
     * @notice called by manager to transfer the unclaimed fee from pool to the vault. Calls pullFeeFromPool function on
     * the VaultLib.
     */
    function pullFeeFromPool() external onlyManager {
        VaultLib.pullFeeFromPool(state);
    }

    // @notice called by manager to collect fee from the vault. Calls collectManager function on the VaultLib.
    function collectManager() external override onlyManager {
        VaultLib.collectManager(state, manager());
    }

    /**
     * @notice called by the manager to update the fees. Calls updateFees function on the VaultLib.
     * @param newManagingFee new managing fee percentage out of 10_000.
     * @param newPerformanceFee new performance fee percentage out of 10_000.
     */
    function updateFees(
        uint16 newManagingFee,
        uint16 newPerformanceFee
    ) external override onlyManager {
        VaultLib.updateFees(state, newManagingFee, newPerformanceFee);
    }

    /**
     * @notice returns the shares amount a user gets when they intend to provide liquidity in amountXMax and amountYMax.
     * @param amountXMax the maximum amount of tokenX to provide for mint.
     * @param amountYMax the maximum amount of tokenY to provide for mint.
     * @return amountX amountX needed for minting mintAmount.
     * @return amountY amountY needed for minting mintAmount.
     * @return mintAmount the amount of vault shares minted with amountX and amountY.
     */
    function getMintAmounts(
        uint128 amountXMax,
        uint128 amountYMax
    ) external view override returns (uint256 amountX, uint256 amountY, uint256 mintAmount) {
        return VaultLib.getMintAmounts(state, amountXMax, amountYMax);
    }

    /**
     * @notice returns current unclaimed fees from the pool. Calls getCurrentFees on the VaultLib.
     * @return fee0 fee in tokenX
     * @return fee1 fee in tokenY
     */
    function getCurrentFees() external view override returns (uint256 fee0, uint256 fee1) {
        return VaultLib.getCurrentFees(state);
    }

    /**
     * @notice returns position id of the vault in pool.
     * @return positionID the id of the position in pool.
     */
    function getPositionID() public view override returns (bytes32 positionID) {
        return VaultLib.getPositionID(state);
    }

    /**
     * @notice returns vault underlying balance in tokenX and tokenY.
     * @return amountXCurrent amount in tokenX held by the vault.
     * @return amountYCurrent amount in tokenY held by the vault.
     */
    function getUnderlyingBalances()
        external
        view
        override
        returns (uint256 amountXCurrent, uint256 amountYCurrent)
    {
        return VaultLib.getUnderlyingBalances(state);
    }

    /**
     * @notice returns underlying balances in tokenX and tokenY based on the shares amount passed.
     * @param shares amount of vault to calculate the redeemable tokenX and tokenY amounts against.
     * @return amountX the amount of tokenX redeemable against shares.
     * @return amountY the amount of tokenY redeemable against shares.
     */
    function getUnderlyingBalancesByShare(
        uint256 shares
    ) external view override returns (uint256 amountX, uint256 amountY) {
        return VaultLib.getUnderlyingBalancesByShare(state, shares);
    }

    // @notice restricts upgrading of vault to factory only.
    function _authorizeUpgrade(address) internal override {
        if (msg.sender != state.factory) revert VaultErrors.OnlyFactoryAllowed();
    }

    /**
     * @notice transfer hook to transfer the exposure from sender to recipient. Calls _beforeTokenTransfer on the VaultLib.
     * @param from the sender of vault shares.
     * @param to recipient of vault shares.
     * @param amount amount of vault shares to transfer.
     */
    function _beforeTokenTransfer(address from, address to, uint256 amount) internal override {
        super._beforeTokenTransfer(from, to, amount);
        VaultLib._beforeTokenTransfer(state, from, to, amount);
    }
}
