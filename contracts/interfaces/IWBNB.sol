//SPDX-License-Identifier: MIT
pragma solidity 0.8.4;

import {IERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";

interface IWBNB is IERC20Upgradeable {
    function deposit() external payable;

    function withdraw(uint) external;
}
