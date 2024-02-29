//SPDX-License-Identifier: MIT
pragma solidity 0.8.4;

import {IERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import {IAlgebraPool} from "./algebra/core/contracts/interfaces/IAlgebraPool.sol";

/**
 * @notice RangeProtocolVaultStorage a storage contract for RangeProtocolVault
 */
abstract contract RangeProtocolVaultStorage {
    int24 public bottomTick;
    int24 public topTick;
    bool public inThePosition;
    bool public mintStarted;

    int24 public tickSpacing;
    IAlgebraPool public pool;
    IERC20Upgradeable public token0;
    IERC20Upgradeable public token1;

    address public factory;
    uint16 public managingFee;
    uint16 public performanceFee;
    uint256 public managerBalance0;
    uint256 public managerBalance1;

    struct UserVault {
        bool exists;
        uint256 token0;
        uint256 token1;
    }
    mapping(address => UserVault) public userVaults;
    address[] public users;
    // NOTE: Only add more state variable below it and do not change the order of above state variables.
}
