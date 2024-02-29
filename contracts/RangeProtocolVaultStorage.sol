//SPDX-License-Identifier: MIT
pragma solidity 0.8.4;

import {IERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import {IPancakeV3Pool} from "./pancake/interfaces/IPancakeV3Pool.sol";
import {DataTypesLib} from "./libraries/DataTypesLib.sol";

abstract contract RangeProtocolVaultStorage {
    struct State {
        DataTypesLib.PoolData poolData;
        uint256[50] _emptySlots1;
        DataTypesLib.FeeData feeData;
        uint256[50] _emptySlots2;
        DataTypesLib.UserData userData;
        uint256[50] _emptySlots3;
    }

    State internal state;

    function factory() external view returns (address) {
        return state.poolData.factory;
    }

    function pool() external view returns (IPancakeV3Pool) {
        return state.poolData.pool;
    }

    function token0() external view returns (IERC20Upgradeable) {
        return state.poolData.token0;
    }

    function token1() external view returns (IERC20Upgradeable) {
        return state.poolData.token1;
    }

    function lowerTick() external view returns (int24) {
        return state.poolData.lowerTick;
    }

    function upperTick() external view returns (int24) {
        return state.poolData.upperTick;
    }

    function tickSpacing() external view returns (int24) {
        return state.poolData.tickSpacing;
    }

    function inThePosition() external view returns (bool) {
        return state.poolData.inThePosition;
    }

    function mintStarted() external view returns (bool) {
        return state.poolData.mintStarted;
    }

    function WETH9() external view returns (address) {
        return state.poolData.WETH9;
    }

    function managingFee() external view returns (uint16) {
        return state.feeData.managingFee;
    }

    function performanceFee() external view returns (uint16) {
        return state.feeData.performanceFee;
    }

    function managerBalance0() external view returns (uint256) {
        return state.feeData.managerBalance0;
    }

    function managerBalance1() external view returns (uint256) {
        return state.feeData.managerBalance1;
    }

    function userVaults(address user) external view returns (DataTypesLib.UserVault memory) {
        return state.userData.vaults[user];
    }

    function users(uint256 index) external view returns (address) {
        return state.userData.users[index];
    }

    function userCount() external view returns (uint256) {
        return state.userData.users.length;
    }
}
