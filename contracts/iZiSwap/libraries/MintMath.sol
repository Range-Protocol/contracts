// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.4;

import {TwoPower} from "./TwoPower.sol";
import {LogPowMath} from "./LogPowMath.sol";
import {MulDivMath} from "./MulDivMath.sol";
import {IiZiSwapPool} from "../interfaces/IiZiSwapPool.sol";

library MintMath {
    function getLiquidityForAmounts(
        int24 pl,
        int24 pr,
        uint128 xLim,
        uint128 yLim,
        int24 currPt,
        uint160 sqrtPrice_96,
        uint160 sqrtRate_96
    ) internal pure returns (uint128 liquidity) {
        liquidity = type(uint128).max / 2;
        (uint256 x, uint256 y) = _computeDepositXYPerUnit(
            pl,
            pr,
            currPt,
            sqrtPrice_96,
            sqrtRate_96
        );
        if (x > 0) {
            uint256 xl = (uint256(xLim) * TwoPower.Pow96) / x;
            if (liquidity > xl) {
                liquidity = uint128(xl);
            }
        }
        if (y > 0) {
            // we take yLim - 1, because in the core, the amountY to deposit is
            // calculated by range [left, pc) and point at pc respectively
            uint256 yl = (uint256(yLim - 1) * TwoPower.Pow96) / y;
            if (liquidity > yl) {
                liquidity = uint128(yl);
            }
        }
    }

    /// @dev [leftPoint, rightPoint)
    function getAmountsForLiquidity(
        uint160 sqrtPrice_96,
        uint160 sqrtRate_96,
        int24 currentPoint,
        uint128 liquidDelta,
        int24 leftPoint,
        int24 rightPoint
    ) internal pure returns (uint128 x, uint128 y) {
        uint256 amountY;
        uint160 sqrtPriceR_96 = LogPowMath.getSqrtPrice(rightPoint);
        if (leftPoint < currentPoint) {
            uint160 sqrtPriceL_96 = LogPowMath.getSqrtPrice(leftPoint);
            uint256 yl;
            if (rightPoint < currentPoint) {
                yl = getAmountY(liquidDelta, sqrtPriceL_96, sqrtPriceR_96, sqrtRate_96, true);
            } else {
                yl = getAmountY(liquidDelta, sqrtPriceL_96, sqrtPrice_96, sqrtRate_96, true);
            }
            amountY += yl;
        }
        if (rightPoint > currentPoint) {
            // we need compute XR
            uint256 xr = getAmountX(
                liquidDelta,
                (leftPoint > currentPoint) ? leftPoint : currentPoint + 1,
                rightPoint,
                sqrtPriceR_96,
                sqrtRate_96,
                true
            );
            x = uint128(xr);
            require(x == xr, "XOFL");
        }
        if (leftPoint <= currentPoint && rightPoint > currentPoint) {
            // we need compute yc at point of current price
            amountY += _computeDepositYc(liquidDelta, sqrtPrice_96);
        }
        y = uint128(amountY);
        require(y == amountY, "YOFL");
    }

    function getAmountY(
        uint128 liquidity,
        uint160 sqrtPriceL_96,
        uint160 sqrtPriceR_96,
        uint160 sqrtRate_96,
        bool upper
    ) internal pure returns (uint256 amount) {
        uint160 numerator = sqrtPriceR_96 - sqrtPriceL_96;
        uint160 denominator = sqrtRate_96 - uint160(TwoPower.Pow96);
        if (!upper) {
            amount = MulDivMath.mulDivFloor(liquidity, numerator, denominator);
        } else {
            amount = MulDivMath.mulDivCeil(liquidity, numerator, denominator);
        }
    }

    function getAmountX(
        uint128 liquidity,
        int24 leftPt,
        int24 rightPt,
        uint160 sqrtPriceR_96,
        uint160 sqrtRate_96,
        bool upper
    ) internal pure returns (uint256 amount) {
        // rightPt - (leftPt - 1), pc = leftPt - 1
        uint160 sqrtPricePrPl_96 = LogPowMath.getSqrtPrice(rightPt - leftPt);
        // 1. sqrtPriceR_96 * 2^96 < 2^256
        // 2. sqrtRate_96 > 2^96, so sqrtPricePrM1_96 < sqrtPriceR_96 < 2^160
        uint160 sqrtPricePrM1_96 = uint160((uint256(sqrtPriceR_96) * TwoPower.Pow96) / sqrtRate_96);

        uint160 numerator = sqrtPricePrPl_96 - uint160(TwoPower.Pow96);
        uint160 denominator = sqrtPriceR_96 - sqrtPricePrM1_96;
        if (!upper) {
            amount = MulDivMath.mulDivFloor(liquidity, numerator, denominator);
        } else {
            amount = MulDivMath.mulDivCeil(liquidity, numerator, denominator);
        }
    }

    function getAmountYUnitLiquidity_96(
        uint160 sqrtPriceL_96,
        uint160 sqrtPriceR_96,
        uint160 sqrtRate_96
    ) internal pure returns (uint256 amount_96) {
        uint160 numerator = sqrtPriceR_96 - sqrtPriceL_96;
        uint160 denominator = sqrtRate_96 - uint160(TwoPower.Pow96);
        amount_96 = MulDivMath.mulDivCeil(TwoPower.Pow96, numerator, denominator);
    }

    function getAmountXUnitLiquidity_96(
        int24 leftPt,
        int24 rightPt,
        uint160 sqrtPriceR_96,
        uint160 sqrtRate_96
    ) internal pure returns (uint256 amount_96) {
        // rightPt - (leftPt - 1), pc = leftPt - 1
        uint160 sqrtPricePrPc_96 = LogPowMath.getSqrtPrice(rightPt - leftPt + 1);
        uint160 sqrtPricePrPd_96 = LogPowMath.getSqrtPrice(rightPt + 1);

        uint160 numerator = sqrtPricePrPc_96 - sqrtRate_96;
        uint160 denominator = sqrtPricePrPd_96 - sqrtPriceR_96;
        amount_96 = MulDivMath.mulDivCeil(TwoPower.Pow96, numerator, denominator);
    }

    /// @dev [pl, pr)
    function _computeDepositXYPerUnit(
        int24 pl,
        int24 pr,
        int24 pc,
        uint160 sqrtPrice_96,
        uint160 sqrtRate_96
    ) private pure returns (uint256 x, uint256 y) {
        x = 0;
        y = 0;
        uint160 sqrtPriceR_96 = LogPowMath.getSqrtPrice(pr);
        if (pl < pc) {
            uint160 sqrtPriceL_96 = LogPowMath.getSqrtPrice(pl);
            if (pr < pc) {
                y += getAmountYUnitLiquidity_96(sqrtPriceL_96, sqrtPriceR_96, sqrtRate_96);
            } else {
                y += getAmountYUnitLiquidity_96(sqrtPriceL_96, sqrtPrice_96, sqrtRate_96);
            }
        }
        if (pr > pc) {
            // we need compute XR
            int24 xrLeft = (pl > pc) ? pl : pc + 1;
            x = getAmountXUnitLiquidity_96(xrLeft, pr, sqrtPriceR_96, sqrtRate_96);
        }
        if (pl <= pc && pr > pc) {
            // we nned compute yc at point of current price
            y += sqrtPrice_96;
        }
    }

    function _computeDepositYc(
        uint128 liquidDelta,
        uint160 sqrtPrice_96
    ) private pure returns (uint128 y) {
        // to simplify computation,
        // minter is required to deposit only token y in point of current price
        uint256 amount = MulDivMath.mulDivCeil(liquidDelta, sqrtPrice_96, TwoPower.Pow96);
        y = uint128(amount);
        require(y == amount, "YC OFL");
    }
}
