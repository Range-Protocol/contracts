// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.5.0;

interface IAgniSwapCallback {
    function agniSwapCallback(int256 amount0Delta, int256 amount1Delta, bytes calldata) external;
}
