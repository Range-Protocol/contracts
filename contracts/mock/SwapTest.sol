//SPDX-License-Identifier: MIT
pragma solidity 0.8.4;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "contracts/iZiSwap/interfaces/IiZiSwapPool.sol";
import "contracts/iZiSwap/interfaces/IiZiSwapCallback.sol";

contract SwapTest is IiZiSwapCallback {
    function mint(address pool, uint128 mintAmount) external {
        IiZiSwapPool(pool).mint(address(this), -10000, 20000, mintAmount, "");
    }

    function mintDepositCallback(uint256 x, uint256 y, bytes calldata data) external {
        IERC20(IiZiSwapPool(msg.sender).tokenX()).transfer(msg.sender, x);
        IERC20(IiZiSwapPool(msg.sender).tokenY()).transfer(msg.sender, y);
    }

    function swapOneForZero(address pool, uint128 amountSpecified) external {
        (, int24 currentPoint, , , , , , ) = IiZiSwapPool(pool).state();

        IERC20(IiZiSwapPool(pool).tokenX()).transferFrom(
            msg.sender,
            address(this),
            uint256(amountSpecified)
        );

        IiZiSwapPool(pool).swapX2Y(
            address(msg.sender),
            amountSpecified,
            currentPoint - 200,
            abi.encode(msg.sender)
        );
    }

    function swapX2YCallback(uint256 tokenXAmount, uint256, bytes calldata) external override {
        if (tokenXAmount > 0)
            IERC20(IiZiSwapPool(msg.sender).tokenX()).transfer(msg.sender, tokenXAmount);
    }

    function swapY2XCallback(uint256 x, uint256 y, bytes calldata data) external override {}
}
