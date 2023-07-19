// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.4;

import {IWETH9} from "../interfaces/IWETH9.sol";
import {TransferHelper} from "../libraries/TransferHelper.sol";

library PeripheryPaymentsLib {
    function unwrapWETH9(address WETH9, uint256 amount, address recipient) external {
        IWETH9(WETH9).withdraw(amount);
        TransferHelper.safeTransferETH(recipient, amount);
    }

    function pay(
        address WETH9,
        address token,
        address payer,
        address recipient,
        uint256 value
    ) external {
        if (token == WETH9 && address(this).balance >= value) {
            // pay with WETH9
            IWETH9(WETH9).deposit{value: value}(); // wrap only what is needed to pay
            IWETH9(WETH9).transfer(recipient, value);
        } else if (payer == address(this)) {
            // pay with tokens already in the contract (for the exact input multihop case)
            TransferHelper.safeTransfer(token, recipient, value);
        } else {
            // pull payment
            TransferHelper.safeTransferFrom(token, payer, recipient, value);
        }
    }

    function refundETH() external {
        if (address(this).balance > 0)
            TransferHelper.safeTransferETH(msg.sender, address(this).balance);
    }
}
