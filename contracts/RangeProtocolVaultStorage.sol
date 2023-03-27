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

    uint16 public managerFee;
    uint256 public managerBalance0;
    uint256 public managerBalance1;

    IUniswapV3Pool public pool;
    IERC20Upgradeable public token0;
    IERC20Upgradeable public token1;
    int24 public tickSpacing;

    /// @notice RangeProtocol treasury
    address public treasury;
    uint256 public treasuryBalance0;
    uint256 public treasuryBalance1;

    bool public inThePosition;
    bool public mintStarted;

    address public factory;

    uint256 public token0Supplied;
    uint256 public token1Supplied;

    // NOTE: Only add more state variable below it and do not change the order of above state variables.
}
