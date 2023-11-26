//SPDX-License-Identifier: MIT
pragma solidity 0.8.4;

import {RangeProtocolVaultStorage} from "../RangeProtocolVaultStorage.sol";
import {SafeERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import {IERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import {IWETH9} from "../interfaces/IWETH9.sol";
import {NativeTokenSupportErrors} from "../errors/NativeTokenSupportErrors.sol";

library NativeTokenSupport {
    using SafeERC20Upgradeable for IERC20Upgradeable;

    function processDeposit(
        RangeProtocolVaultStorage.UserVault storage userVault,
        address[] storage users,
        bool depositNative,
        IERC20Upgradeable token0,
        IERC20Upgradeable token1,
        uint256 amount0,
        uint256 amount1,
        address WETH9
    ) external {
        if (!userVault.exists) {
            userVault.exists = true;
            users.push(msg.sender);
        }

        (bool isToken0Native, bool isToken1Native) = (
            address(token0) == WETH9,
            address(token1) == WETH9
        );
        if (amount0 != 0) {
            userVault.token0 += amount0;
            if (isToken0Native && depositNative) {
                if (msg.value < amount0) {
                    revert NativeTokenSupportErrors.InsufficientNativeTokenAmount(msg.value);
                }
                IWETH9(WETH9).deposit{value: amount0}();
            } else {
                token0.safeTransferFrom(msg.sender, address(this), amount0);
            }
        }

        if (amount1 != 0) {
            userVault.token1 += amount1;
            if (isToken1Native && depositNative) {
                if (msg.value < amount1) {
                    revert NativeTokenSupportErrors.InsufficientNativeTokenAmount(msg.value);
                }
                IWETH9(WETH9).deposit{value: amount1}();
            } else {
                token1.safeTransferFrom(msg.sender, address(this), amount1);
            }
        }
    }

    function processWithdraw(
        RangeProtocolVaultStorage.UserVault storage userVault,
        bool withdrawNative,
        uint256 burnAmount,
        uint256 balanceBefore,
        IERC20Upgradeable token0,
        IERC20Upgradeable token1,
        uint256 amount0,
        uint256 amount1,
        address WETH9
    ) external {
        (bool isToken0Native, bool isToken1Native) = (
            address(token0) == WETH9,
            address(token1) == WETH9
        );
        uint256 weth9Amount = 0;
        userVault.token0 = (userVault.token0 * (balanceBefore - burnAmount)) / balanceBefore;
        if (amount0 != 0) {
            if (isToken0Native && withdrawNative) {
                IWETH9(WETH9).withdraw(amount0);
                weth9Amount = amount0;
            } else {
                token0.safeTransfer(msg.sender, amount0);
            }
        }

        userVault.token1 = (userVault.token1 * (balanceBefore - burnAmount)) / balanceBefore;
        if (amount1 != 0) {
            if (isToken1Native && withdrawNative) {
                IWETH9(WETH9).withdraw(amount1);
                weth9Amount = amount1;
            } else {
                token1.safeTransfer(msg.sender, amount1);
            }
        }

        if (weth9Amount != 0) {
            msg.sender.call{value: weth9Amount}("");
        }
    }
}
