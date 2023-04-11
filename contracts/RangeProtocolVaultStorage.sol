//SPDX-License-Identifier: MIT
pragma solidity 0.8.4;

import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";

/**
 * @notice RangeProtocolVaultStorage a storage contract for RangeProtocolVault
 */
abstract contract RangeProtocolVaultStorage {
    int24 public lowerTick;
    int24 public upperTick;

    uint16 public managingFee;
    uint256 public managerBalance0;
    uint256 public managerBalance1;

    IUniswapV3Pool public pool;
    IERC20Upgradeable public token0;
    IERC20Upgradeable public token1;
    int24 public tickSpacing;

    /// @notice Unused slots
    address public unusedSlot0;
    uint256 public unusedSlot1;
    uint256 public unusedSlot2;

    bool public inThePosition;
    bool public mintStarted;

    address public factory;

    struct UserVault {
        bool exists;
        uint256 token0;
        uint256 token1;
    }
    mapping(address => UserVault) public userVaults;
    address[] public users;

    uint16 public performanceFee;
    // NOTE: Only add more state variable below it and do not change the order of above state variables.
}
