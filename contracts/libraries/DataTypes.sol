//SPDX-License-Identifier: MIT
pragma solidity 0.8.4;

import {IERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import {IiZiSwapPool} from "../iZiSwap/interfaces/IiZiSwapPool.sol";

library DataTypes {
    struct UserVault {
        bool exists;
        uint256 tokenX;
        uint256 tokenY;
    }

    struct UserVaultInfo {
        address user;
        uint256 tokenX;
        uint256 tokenY;
    }

    struct State {
        int24 leftPoint;
        int24 rightPoint;
        int24 pointDelta;
        IiZiSwapPool pool;
        IERC20Upgradeable tokenX;
        IERC20Upgradeable tokenY;
        bool inThePosition;
        bool mintStarted;
        address factory;
        uint16 managingFee;
        uint16 performanceFee;
        uint256 managerBalanceX;
        uint256 managerBalanceY;
        mapping(address => UserVault) userVaults;
        address[] users;
    }
}
