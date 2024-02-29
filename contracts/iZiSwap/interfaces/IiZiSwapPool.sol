// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.4;

import {IiZiSwapMintCallback, IiZiSwapCallback} from "./IiZiSwapCallback.sol";

interface IiZiSwapPool is IiZiSwapMintCallback, IiZiSwapCallback {
    struct LiquidityData {
        uint128 liquidity;
        uint256 lastFeeScaleX_128;
        uint256 lastFeeScaleY_128;
        uint256 tokenOwedX;
        uint256 tokenOwedY;
    }

    function liquidity(bytes32 liquidityId) external view returns (LiquidityData memory);

    struct PointData {
        uint128 liquidSum;
        // value to add when pass this slot from left to right
        // value to dec when pass this slot from right to left
        int128 liquidDelta;
        // if pointPrice < currPrice
        //    value = sigma(feeScaleX(p)), which p < pointPrice
        // if pointPrice >= currPrice
        //    value = sigma(feeScaleX(p)), which p >= pointPrice
        uint256 accFeeXOut_128;
        // similar to accFeeXOut_128
        uint256 accFeeYOut_128;
        // whether the point is endpoint of a liquid segment
        bool isEndpt;
    }

    function points(int24 point) external view returns (PointData memory);

    function totalFeeXCharged() external view returns (uint256);

    function totalFeeYCharged() external view returns (uint256);

    function tokenX() external view returns (address);

    function tokenY() external view returns (address);

    /// @notice fee amount of this swap pool, 3000 means 0.3%
    function fee() external view returns (uint24);

    /// @notice minimum number of distance between initialized or limitorder points
    function pointDelta() external view returns (int24);

    /// @notice the fee growth as a 128-bit fixpoing fees of tokenX collected per 1 liquidity of the pool
    function feeScaleX_128() external view returns (uint256);

    /// @notice the fee growth as a 128-bit fixpoing fees of tokenY collected per 1 liquidity of the pool
    function feeScaleY_128() external view returns (uint256);

    /// @notice Add liquidity to the pool.
    /// @param recipient newly created liquidity will belong to this address
    /// @param leftPt left endpoint of the liquidity, be sure to be times of pointDelta
    /// @param rightPt right endpoint of the liquidity, be sure to be times of pointDelta
    /// @param liquidDelta amount of liquidity to add
    /// @param data any data that should be passed through to the callback
    /// @return amountX The amount of tokenX that was paid for the liquidity. Matches the value in the callback
    /// @return amountY The amount of tokenY that was paid for the liquidity. Matches the value in the callback
    function mint(
        address recipient,
        int24 leftPt,
        int24 rightPt,
        uint128 liquidDelta,
        bytes calldata data
    ) external returns (uint256 amountX, uint256 amountY);

    /// @notice Decrease a given amount of liquidity from msg.sender's liquidities.
    /// @param leftPt left endpoint of the liquidity
    /// @param rightPt right endpoint of the liquidity
    /// @param liquidDelta amount of liquidity to burn
    /// @return amountX The amount of tokenX should be refund after burn
    /// @return amountY The amount of tokenY should be refund after burn
    function burn(
        int24 leftPt,
        int24 rightPt,
        uint128 liquidDelta
    ) external returns (uint256 amountX, uint256 amountY);

    /// @notice Collect tokens (fee or refunded after burn) from a liquidity.
    /// @param recipient the address which should receive the collected tokens
    /// @param leftPt left endpoint of the liquidity
    /// @param rightPt right endpoint of the liquidity
    /// @param amountXLim max amount of tokenX the owner wants to collect
    /// @param amountYLim max amount of tokenY the owner wants to collect
    /// @return actualAmountX the amount tokenX collected
    /// @return actualAmountY the amount tokenY collected
    function collect(
        address recipient,
        int24 leftPt,
        int24 rightPt,
        uint256 amountXLim,
        uint256 amountYLim
    ) external returns (uint256 actualAmountX, uint256 actualAmountY);

    /// @notice Swap tokenY for tokenX, given max amount of tokenY user willing to pay.
    /// @param recipient the address to receive tokenX
    /// @param amount the max amount of tokenY user willing to pay
    /// @param highPt the highest point(price) of x/y during swap
    /// @param data any data to be passed through to the callback
    /// @return amountX amount of tokenX payed
    /// @return amountY amount of tokenY acquired
    function swapY2X(
        address recipient,
        uint128 amount,
        int24 highPt,
        bytes calldata data
    ) external returns (uint256 amountX, uint256 amountY);

    /// @notice Swap tokenX for tokenY, given max amount of tokenX user willing to pay.
    /// @param recipient the address to receive tokenY
    /// @param amount the max amount of tokenX user willing to pay
    /// @param lowPt the lowest point(price) of x/y during swap
    /// @param data any data to be passed through to the callback
    /// @return amountX amount of tokenX acquired
    /// @return amountY amount of tokenY payed
    function swapX2Y(
        address recipient,
        uint128 amount,
        int24 lowPt,
        bytes calldata data
    ) external returns (uint256 amountX, uint256 amountY);

    /// @notice Returns sqrt(1.0001), in 96 bit fixpoint number.
    function sqrtRate_96() external view returns (uint160);

    /// @notice State values of pool.
    /// @return sqrtPrice_96 a 96 fixpoing number describe the sqrt value of current price(tokenX/tokenY)
    /// @return currentPoint the current point of the pool, 1.0001 ^ currentPoint = price
    /// @return observationCurrentIndex the index of the last oracle observation that was written,
    /// @return observationQueueLen the current maximum number of observations stored in the pool,
    /// @return observationNextQueueLen the next maximum number of observations, to be updated when the observation.
    /// @return locked whether the pool is locked (only used for checking reentrance)
    /// @return liquidity liquidity on the currentPoint (currX * sqrtPrice + currY / sqrtPrice)
    /// @return liquidityX liquidity of tokenX
    function state()
        external
        view
        returns (
            uint160 sqrtPrice_96,
            int24 currentPoint,
            uint16 observationCurrentIndex,
            uint16 observationQueueLen,
            uint16 observationNextQueueLen,
            bool locked,
            uint128 liquidity,
            uint128 liquidityX
        );
}
