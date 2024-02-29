//SPDX-License-Identifier: MIT
pragma solidity 0.8.4;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IAlgebraPool} from "../algebra/core/contracts/interfaces/IAlgebraPool.sol";
import {IAlgebraSwapCallback} from "../algebra/core/contracts/interfaces/callback/IAlgebraSwapCallback.sol";

contract SwapTest is IAlgebraSwapCallback {
    function swapZeroForOne(address pool, int256 amountSpecified) external {
        (uint160 price, , , , , ) = IAlgebraPool(pool).globalState();
        uint160 nextPrice = price +
            uint160(uint160(uint256(amountSpecified) * 2 ** 96) / IAlgebraPool(pool).liquidity());

        IAlgebraPool(pool).swap(
            address(msg.sender),
            false,
            amountSpecified,
            nextPrice,
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
            (uint160 price, , , , , ) = IAlgebraPool(pool).globalState();
            IAlgebraPool(pool).swap(
                address(msg.sender),
                zeroForOne,
                amountSpecified,
                zeroForOne ? price - 1000 : price + 1000,
                abi.encode(msg.sender)
            );
        }
    }

    function getSwapResult(
        address pool,
        bool zeroForOne,
        int256 amountSpecified,
        uint160 sqrtPriceLimitX96
    ) external returns (int256 amount0Delta, int256 amount1Delta, uint160 nextPrice) {
        (amount0Delta, amount1Delta) = IAlgebraPool(pool).swap(
            address(msg.sender),
            zeroForOne,
            amountSpecified,
            sqrtPriceLimitX96,
            abi.encode(msg.sender)
        );

        (nextPrice, , , , , ) = IAlgebraPool(pool).globalState();
    }

    function algebraSwapCallback(
        int256 amount0Delta,
        int256 amount1Delta,
        bytes calldata data
    ) external override {
        address sender = abi.decode(data, (address));

        if (amount0Delta > 0) {
            IERC20(IAlgebraPool(msg.sender).token0()).transferFrom(
                sender,
                msg.sender,
                uint256(amount0Delta)
            );
        } else if (amount1Delta > 0) {
            IERC20(IAlgebraPool(msg.sender).token1()).transferFrom(
                sender,
                msg.sender,
                uint256(amount1Delta)
            );
        }
    }
}
