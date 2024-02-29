//SPDX-License-Identifier: MIT
pragma solidity 0.8.4;

/// @title Callback for IButterPoolActions#mint
/// @notice Any contract that calls IButterPoolActions#mint must implement this interface
interface IButterMintCallback {
    /// @notice Called to `msg.sender` after minting liquidity to a position from IButterPool#mint.
    /// @dev In the implementation you must pay the pool tokens owed for the minted liquidity.
    /// The caller of this method must be checked to be an ButterPool deployed by the canonical ButterFactory.
    /// @param amount0Owed The amount of token0 due to the pool for the minted liquidity
    /// @param amount1Owed The amount of token1 due to the pool for the minted liquidity
    /// @param data Any data passed through by the caller via the IButterPoolActions#mint call
    function butterMintCallback(
        uint256 amount0Owed,
        uint256 amount1Owed,
        bytes calldata data
    ) external;
}
