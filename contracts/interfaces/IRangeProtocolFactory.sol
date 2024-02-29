//SPDX-License-Identifier: MIT
pragma solidity 0.8.4;

error ZeroPoolAddress();
error VaultAlreadyExists();

interface IRangeProtocolFactory {
    event VaultCreated(
        address indexed uniPool,
        address indexed manager,
        address indexed vault
    );

    function createVault(
        address tokenA,
        address tokenB,
        uint24 fee,
        address treasury,
        address manager,
        uint16 managerFee,
        string memory name,
        string memory symbol
    ) external;
}