//SPDX-License-Identifier: MIT
pragma solidity 0.8.4;

import {IERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import {IiZiSwapCallback, IiZiSwapMintCallback} from "../iZiSwap/interfaces/IiZiSwapCallback.sol";
import {IiZiSwapPool} from "../iZiSwap/interfaces/IiZiSwapPool.sol";
import {DataTypes} from "../libraries/DataTypes.sol";

interface IRangeProtocolVault is IERC20Upgradeable, IiZiSwapCallback, IiZiSwapMintCallback {
    event Minted(
        address indexed receiver,
        uint256 mintAmount,
        uint256 amountXIn,
        uint256 amountYIn
    );
    event Burned(
        address indexed receiver,
        uint256 burnAmount,
        uint256 amountXOut,
        uint256 amountYOut
    );
    event LiquidityAdded(
        uint256 liquidityMinted,
        int24 tickLower,
        int24 tickUpper,
        uint256 amountXIn,
        uint256 amountYIn
    );
    event LiquidityRemoved(
        uint256 liquidityRemoved,
        int24 tickLower,
        int24 tickUpper,
        uint256 amountXOut,
        uint256 amountYOut
    );
    event FeesEarned(uint256 feesEarned0, uint256 feesEarned1);
    event FeesUpdated(uint16 managingFee, uint16 performanceFee);
    event InThePositionStatusSet(bool inThePosition);
    event Swapped(bool zeroForOne, uint256 amountX, uint256 amountY);
    event PointsSet(int24 lowerTick, int24 upperTick);
    event MintStarted();

    // @return lower tick of the position.
    function leftPoint() external view returns (int24);

    // @return upper tick of the position.
    function rightPoint() external view returns (int24);

    // @return space between two ticks of the pool.
    function pointDelta() external view returns (int24);

    // @return address of the pool.
    function pool() external view returns (IiZiSwapPool);

    // @return address of tokenX
    function tokenX() external view returns (IERC20Upgradeable);

    // @return address of tokenY
    function tokenY() external view returns (IERC20Upgradeable);

    // @return if the vault has an opened position in the AMM pool.
    function inThePosition() external view returns (bool);

    // @return if the mint has started.
    function mintStarted() external view returns (bool);

    // @return the range protocol's factory address.
    function factory() external view returns (address);

    // @return managing fee percentage.
    function managingFee() external view returns (uint16);

    // @return performance fee percentage.
    function performanceFee() external view returns (uint16);

    // @return balance of manager in tokenX.
    function managerBalanceX() external view returns (uint256);

    // @return balance of manager in tokenY.
    function managerBalanceY() external view returns (uint256);

    // @return The user's vault exposure in tokenX and tokenY.
    function userVaults(address user) external view returns (DataTypes.UserVault memory);

    // @return the address of user at index {idx} in users array.
    function users(uint256 idx) external view returns (address);

    // initializes the vault contract.
    function initialize(address _pool, int24 _tickDelta, bytes memory data) external;

    // @notice updates the left and right points of the vault.
    function updatePoints(int24 _leftPoint, int24 _rightPoint) external;

    // @notice mints the vault shares to users. Intended to be called by the vault contract itself through library.
    function mintTo(address to, uint256 amount) external;

    // @notice mints the vaults shares for users based on the accepted collateral in tokenX and tokenY.
    function mint(
        uint256 mintAmount,
        uint256[2] calldata maxAmounts
    ) external returns (uint256 amountX, uint256 amountY);

    // @notice burns vault shares by the users and returns tokenX and tokenY to the users based on the vault shares burned.
    function burn(
        uint256 burnAmount,
        uint256[2] calldata minAmounts
    ) external returns (uint256 amountX, uint256 amountY);

    // @notice burns vaults by the user. Intended to be called by the vault contract itself through library.
    function burnFrom(address from, uint256 burnAmount) external;

    // @notice removes liquidity from the AMM pool. Only callable by the vault manager.
    function removeLiquidity(uint256[2] calldata minAmounts) external;

    // @notice swap tokenX to tokenY based on the passed parameters. Only callable by the vault manager.
    function swap(
        bool zeroForOne,
        uint128 swapAmount,
        int24 pointLimit,
        uint256 minAmountIn
    ) external returns (uint256 amountX, uint256 amountY);

    // @notice add liquidity to the AMM pool based on newer points range.
    function addLiquidity(
        int24 newLowerTick,
        int24 newUpperTick,
        uint128 amountX,
        uint128 amountY,
        uint256[2] calldata maxAmounts
    ) external returns (uint256 remainingAmountX, uint256 remainingAmountY);

    // @notice collects manager fee by the manager.
    function collectManager() external;

    // @notice updates the fee percentages. Only callable by the vault manager.
    function updateFees(uint16 newManagingFee, uint16 newPerformanceFee) external;

    // @return returns the mint amounts based on the amountX and amountY provided.
    function getMintAmounts(
        uint128 amountXMax,
        uint128 amountYMax
    ) external view returns (uint256 amountX, uint256 amountY, uint256 mintAmount);

    // @return returns the underlying balance of the vault in tokenX and tokenY.
    function getUnderlyingBalances()
        external
        view
        returns (uint256 amountXCurrent, uint256 amountYCurrent);

    // @return returns the underlying balance based on the shares provided.
    function getUnderlyingBalancesByShare(
        uint256 shares
    ) external view returns (uint256 amountX, uint256 amountY);

    // @returns returns currently unclaimed fee of the vault in AMM pool.
    function getCurrentFees() external view returns (uint256 fee0, uint256 fee1);

    // @return returns current position id of the vault in the AMM pool.
    function getPositionID() external view returns (bytes32 positionID);

    // @return the list of user vaults based on the given indexes.
    function getUserVaults(
        uint256 fromIdx,
        uint256 toIdx
    ) external view returns (DataTypes.UserVaultInfo[] memory);

    // @return returns total count of the users.
    function userCount() external view returns (uint256);
}
