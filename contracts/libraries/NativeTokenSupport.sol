//SPDX-License-Identifier: MIT
pragma solidity 0.8.4;

import {RangeProtocolVaultStorage} from "../RangeProtocolVaultStorage.sol";
import {SafeERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import {IERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import {IWBNB} from "../interfaces/IWBNB.sol";
import {NativeTokenSupportErrors} from "../errors/NativeTokenSupportErrors.sol";

library NativeTokenSupport {
    using SafeERC20Upgradeable for IERC20Upgradeable;

    IWBNB public constant WBNB = IWBNB(0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c);

    function acceptUserDeposit(
        RangeProtocolVaultStorage.UserVault storage userVault,
        address[] storage users,
        bool depositNative,
        IERC20Upgradeable token0,
        IERC20Upgradeable token1,
        uint256 amount0,
        uint256 amount1
    ) external {
        if (!depositNative && msg.value != 0) revert NativeTokenSupportErrors.NativeTokenSent();

        if (!userVault.exists) {
            userVault.exists = true;
            users.push(msg.sender);
        }

        bool isToken0Native = address(token0) == address(WBNB);
        if (amount0 != 0) {
            userVault.token0 += amount0;
            if (depositNative && isToken0Native) {
                if (msg.value < amount0) {
                    revert NativeTokenSupportErrors.InsufficientNativeTokenAmount(msg.value);
                }
                WBNB.deposit{value: amount0}();
            } else {
                token0.safeTransferFrom(msg.sender, address(this), amount0);
            }
        }

        if (amount1 != 0) {
            userVault.token1 += amount0;
            if (depositNative && !isToken0Native) {
                if (msg.value < amount1) {
                    revert NativeTokenSupportErrors.InsufficientNativeTokenAmount(msg.value);
                }
                WBNB.deposit{value: amount1}();
            } else {
                token1.safeTransferFrom(msg.sender, address(this), amount1);
            }
        }

        if (depositNative) {
            uint256 nativeAmount = isToken0Native ? amount0 : amount1;
            if (msg.value > nativeAmount) {
                msg.sender.call{value: msg.value - nativeAmount}("");
            }
        }
    }

    function redeemUserDeposit(
        RangeProtocolVaultStorage.UserVault storage userVault,
        bool withdrawNative,
        uint256 burnAmount,
        uint256 balanceBefore,
        IERC20Upgradeable token0,
        IERC20Upgradeable token1,
        uint256 amount0,
        uint256 amount1
    ) external {
        bool isToken0Native = address(token0) == address(WBNB);
        uint256 bnbAmount;
        if (amount0 != 0) {
            userVault.token0 = (userVault.token0 * (balanceBefore - burnAmount)) / balanceBefore;
            if (withdrawNative && isToken0Native) {
                WBNB.withdraw(amount0);
                bnbAmount = amount0;
            } else {
                token0.safeTransfer(msg.sender, amount0);
            }
        }
        if (amount1 != 0) {
            userVault.token1 = (userVault.token1 * (balanceBefore - burnAmount)) / balanceBefore;
            if (withdrawNative && !isToken0Native) {
                WBNB.withdraw(amount1);
                bnbAmount = amount1;
            } else {
                token1.safeTransfer(msg.sender, amount1);
            }
        }

        if (bnbAmount != 0) {
            msg.sender.call{value: bnbAmount}("");
        }
    }
}
