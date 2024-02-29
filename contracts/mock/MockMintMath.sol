// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.5.0;

import "../iZiSwap/libraries/MintMath.sol";

contract MockMintMath {
    function getLiquidityForAmounts(
        int24 pl,
        int24 pr,
        uint128 xLim,
        uint128 yLim,
        int24 currPt,
        uint160 sqrtPrice_96,
        uint160 sqrtRate_96
    ) public pure returns (uint128 liquidity) {
        return
            MintMath.getLiquidityForAmounts(pl, pr, xLim, yLim, currPt, sqrtPrice_96, sqrtRate_96);
    }

    /// @dev [leftPoint, rightPoint)
    function getAmountsForLiquidity(
        uint160 sqrtPrice_96,
        uint160 sqrtRate_96,
        int24 currentPoint,
        uint128 liquidDelta,
        int24 leftPoint,
        int24 rightPoint
    ) public pure returns (uint128 x, uint128 y) {
        return
            MintMath.getAmountsForLiquidity(
                sqrtPrice_96,
                sqrtRate_96,
                currentPoint,
                liquidDelta,
                leftPoint,
                rightPoint
            );
    }

    function getAmountY(
        uint128 liquidity,
        uint160 sqrtPriceL_96,
        uint160 sqrtPriceR_96,
        uint160 sqrtRate_96,
        bool upper
    ) public pure returns (uint256 amount) {
        return MintMath.getAmountY(liquidity, sqrtPriceL_96, sqrtPriceR_96, sqrtRate_96, upper);
    }

    function getAmountX(
        uint128 liquidity,
        int24 leftPt,
        int24 rightPt,
        uint160 sqrtPriceR_96,
        uint160 sqrtRate_96,
        bool upper
    ) public pure returns (uint256 amount) {
        return MintMath.getAmountX(liquidity, leftPt, rightPt, sqrtPriceR_96, sqrtRate_96, upper);
    }

    function getAmountYUnitLiquidity_96(
        uint160 sqrtPriceL_96,
        uint160 sqrtPriceR_96,
        uint160 sqrtRate_96
    ) public pure returns (uint256 amount_96) {
        return MintMath.getAmountYUnitLiquidity_96(sqrtPriceL_96, sqrtPriceR_96, sqrtRate_96);
    }

    function getAmountXUnitLiquidity_96(
        int24 leftPt,
        int24 rightPt,
        uint160 sqrtPriceR_96,
        uint160 sqrtRate_96
    ) public pure returns (uint256 amount_96) {
        return MintMath.getAmountXUnitLiquidity_96(leftPt, rightPt, sqrtPriceR_96, sqrtRate_96);
    }
}
