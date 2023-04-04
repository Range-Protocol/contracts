// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.4;

import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";

contract MockERC20 is ERC20Upgradeable {
    constructor() initializer {
        __ERC20_init("", "TOKEN");
        _mint(msg.sender, 100000e18);
    }

    function mint() external {
        _mint(msg.sender, 10000e18);
    }
}
