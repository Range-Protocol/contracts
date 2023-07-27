// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.4;

import {IWETH9} from "../interfaces/IWETH9.sol";
import {TransferHelper} from "../libraries/TransferHelper.sol";
import "hardhat/console.sol";

library PeripheryPaymentsLib {
    function unwrapWETH9(address WETH9, uint256 amount, address recipient) internal {
        IWETH9(WETH9).withdraw(amount);
        TransferHelper.safeTransferETH(recipient, amount);
    }

    function pay(
        address WETH9,
        address token,
        address payer,
        address recipient,
        uint256 value,
        bool depositNative
    ) internal {
        if (depositNative) {
            if (address(this).balance < value) revert("Incorrect native token deposit");
            IWETH9(WETH9).deposit{value: value}();
            IWETH9(WETH9).transfer(recipient, value);
        } else if (payer == address(this)) {
            TransferHelper.safeTransfer(token, recipient, value);
        } else {
            TransferHelper.safeTransferFrom(token, payer, recipient, value);
        }
    }

    function refundETH() internal {
        if (address(this).balance > 0)
            TransferHelper.safeTransferETH(msg.sender, address(this).balance);
    }
}
