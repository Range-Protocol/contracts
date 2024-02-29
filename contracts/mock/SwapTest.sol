//SPDX-License-Identifier: MIT
pragma solidity 0.8.4;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../fusionX/interfaces/IFusionXV3Pool.sol";
import "../fusionX/interfaces/callback/IFusionXV3SwapCallback.sol";

contract SwapTest is IFusionXV3SwapCallback {
    function swapZeroForOne(address pool, int256 amountSpecified) external {
        (uint160 sqrtRatio, , , , , , ) = IFusionXV3Pool(pool).slot0();
        uint160 nextSqrtRatio = sqrtRatio +
            uint160(uint160(uint256(amountSpecified) * 2 ** 96) / IFusionXV3Pool(pool).liquidity());

        IFusionXV3Pool(pool).swap(
            address(msg.sender),
            false,
            amountSpecified,
            nextSqrtRatio,
            abi.encode(msg.sender)
        );
    }

    function washTrade(
        address pool,
        int256 amountSpecified,
        uint256 numTrades,
        uint256 ratio
    ) external {
        for (uint256 i = 0; i < numTrades; i++) {
            bool zeroForOne = i % ratio > 0;
            (uint160 sqrtRatio, , , , , , ) = IFusionXV3Pool(pool).slot0();
            IFusionXV3Pool(pool).swap(
                address(msg.sender),
                zeroForOne,
                amountSpecified,
                zeroForOne ? sqrtRatio - 1000 : sqrtRatio + 1000,
                abi.encode(msg.sender)
            );
        }
    }

    function getSwapResult(
        address pool,
        bool zeroForOne,
        int256 amountSpecified,
        uint160 sqrtPriceLimitX96
    ) external returns (int256 amount0Delta, int256 amount1Delta, uint160 nextSqrtRatio) {
        (amount0Delta, amount1Delta) = IFusionXV3Pool(pool).swap(
            address(msg.sender),
            zeroForOne,
            amountSpecified,
            sqrtPriceLimitX96,
            abi.encode(msg.sender)
        );

        (nextSqrtRatio, , , , , , ) = IFusionXV3Pool(pool).slot0();
    }

    function fusionXV3SwapCallback(
        int256 amount0Delta,
        int256 amount1Delta,
        bytes calldata data
    ) external override {
        address sender = abi.decode(data, (address));

        if (amount0Delta > 0) {
            IERC20(IFusionXV3Pool(msg.sender).token0()).transferFrom(
                sender,
                msg.sender,
                uint256(amount0Delta)
            );
        } else if (amount1Delta > 0) {
            IERC20(IFusionXV3Pool(msg.sender).token1()).transferFrom(
                sender,
                msg.sender,
                uint256(amount1Delta)
            );
        }
    }
}
