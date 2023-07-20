//SPDX-License-Identifier: MIT
pragma solidity 0.8.4;

import {IERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import {IPancakeV3MintCallback} from "../pancake/interfaces/callback/IPancakeV3MintCallback.sol";
import {IPancakeV3SwapCallback} from "../pancake/interfaces/callback/IPancakeV3SwapCallback.sol";
import {DataTypesLib} from "../libraries/DataTypesLib.sol";

interface IRangeProtocolVault is IERC20Upgradeable, IPancakeV3MintCallback, IPancakeV3SwapCallback {
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

    function initialize(address _pool, int24 _tickSpacing, bytes memory data) external;

    function updateTicks(int24 _lowerTick, int24 _upperTick) external;

    function mint(uint256 mintAmount) external payable returns (uint256 amount0, uint256 amount1);

    function mintShares(address to, uint256 shareAmount) external;

    function burn(
        uint256 burnAmount,
        bool withdrawNative
    ) external returns (uint256 amount0, uint256 amount1);

    function burnShares(address from, uint256 shareAmount) external;

    function removeLiquidity() external;

    function swap(
        bool zeroForOne,
        int256 swapAmount,
        uint160 sqrtPriceLimitX96
    ) external returns (int256 amount0, int256 amount1);

    function addLiquidity(
        int24 newLowerTick,
        int24 newUpperTick,
        uint256 amount0,
        uint256 amount1
    ) external returns (uint256 remainingAmount0, uint256 remainingAmount1);

    function collectManager() external;

    function updateFees(uint16 newManagingFee, uint16 newPerformanceFee) external;

    function getMintAmounts(
        uint256 amount0Max,
        uint256 amount1Max
    ) external view returns (uint256 amount0, uint256 amount1, uint256 mintAmount);

    function getUnderlyingBalances()
        external
        view
        returns (uint256 amount0Current, uint256 amount1Current);

    function getUnderlyingBalancesAtPrice(
        uint160 sqrtRatioX96
    ) external view returns (uint256 amount0Current, uint256 amount1Current);

    function getCurrentFees() external view returns (uint256 fee0, uint256 fee1);

    function getPositionID() external view returns (bytes32 positionID);

    function getUserVaults(
        uint256 fromIdx,
        uint256 toIdx
    ) external view returns (DataTypesLib.UserVaultInfo[] memory);
}
