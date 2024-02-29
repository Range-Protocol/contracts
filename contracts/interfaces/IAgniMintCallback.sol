// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.5.0;

interface IAgniMintCallback {
    function agniMintCallback(
        uint256 amount0Owed,
        uint256 amount1Owed,
        bytes calldata data
    ) external;
}
