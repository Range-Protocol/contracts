//SPDX-License-Identifier: MIT
pragma solidity 0.8.4;

library VaultErrors {
    error MintNotStarted();
    error NotAllowedToUpdateTicks();
    error InvalidManagingFee();
    error InvalidPerformanceFee();
    error OnlyPoolAllowed();
    error InvalidMintAmount();
    error InvalidBurnAmount();
    error MintNotAllowed();
    error ZeroMintAmount();
    error ZeroUnderlyingBalance();
    error TicksOutOfRange();
    error InvalidTicksSpacing();
    error OnlyFactoryAllowed();
    error LiquidityAlreadyAdded();
    error ZeroManagerAddress();
    error SlippageExceedThreshold();
}
