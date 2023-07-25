//SPDX-License-Identifier: MIT
pragma solidity 0.8.4;

import {IERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import {IPancakeV3Pool} from "../pancake/interfaces/IPancakeV3Pool.sol";

library DataTypesLib {
    struct PoolData {
        address factory;
        IPancakeV3Pool pool;
        IERC20Upgradeable token0;
        IERC20Upgradeable token1;
        int24 lowerTick;
        int24 upperTick;
        int24 tickSpacing;
        bool inThePosition;
        bool mintStarted;
        address WETH9;
    }

    struct FeeData {
        uint16 managingFee;
        uint16 performanceFee;
        uint256 managerBalance0;
        uint256 managerBalance1;
    }

    struct UserData {
        mapping(address => UserVault) vaults;
        address[] users;
    }

    struct UserVault {
        bool exists;
        uint256 token0;
        uint256 token1;
    }

    struct UserVaultInfo {
        address user;
        uint256 token0;
        uint256 token1;
    }
}
