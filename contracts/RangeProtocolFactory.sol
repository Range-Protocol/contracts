//SPDX-License-Identifier: MIT
pragma solidity 0.8.4;

import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import "@uniswap/v3-core/contracts/interfaces/pool/IUniswapV3PoolImmutables.sol";
import "./RangeProtocolVault.sol";
import "./interfaces/IRangeProtocolFactory.sol";


/// @dev Mars@RangeProtocol
contract RangeProtocolFactory is IRangeProtocolFactory, Ownable {
    /// @notice Uniswap v3 factory
    address public immutable factory;

    /// @notice all deployed vault instances
    address[] public allVaults;
    // toke0, token1, fee -> RangeProtocol vault address
    mapping(address => mapping(address => mapping(uint24 => address)))
        public vaults;

    constructor(address _uniswapV3Factory) Ownable(msg.sender) {
        factory = _uniswapV3Factory;
    }

    /// @notice deployVault creates a new instance of a Vault on a specified UniswapV3Pool
    /// @param tokenA one of the tokens in the uniswap pair
    /// @param tokenB the other token in the uniswap pair
    /// @param fee fee tier of the uniswap pair
    /// @param manager address of the managing account
    /// @param managerFee proportion of earned fees that go to pool manager in Basis Points
    /// @param name name of the range vault
    /// @param symbol symbol of the range vault
    function createVault(
        address tokenA,
        address tokenB,
        uint24 fee,
        address treasury,
        address manager,
        uint16 managerFee,
        string memory name,
        string memory symbol
    ) external override onlyManager {
        address pool = IUniswapV3Factory(factory).getPool(
            tokenA,
            tokenB,
            fee
        );
        if (pool == address(0x0)) revert ZeroPoolAddress();
        address vault = deploy(
            pool,
            tokenA,
            tokenB,
            fee,
            treasury,
            manager,
            managerFee,
            name,
            symbol
        );

        emit VaultCreated(
            pool,
            manager,
            vault
        );
    }

    function deploy(
        address pool,
        address tokenA,
        address tokenB,
        uint24 fee,
        address treasury,
        address manager,
        uint16 managerFee,
        string memory name,
        string memory symbol
    ) internal returns (address vault) {
        if (tokenA == tokenB) revert();
        (address token0, address token1) = tokenA < tokenB
            ? (tokenA, tokenB)
            : (tokenB, tokenA);

        if (token0 == address(0x0)) revert();
        if (vaults[token0][token1][fee] != address(0)) revert VaultAlreadyExists();

        int24 tickSpacing = IUniswapV3Factory(factory).feeAmountTickSpacing(fee);
        vault = address(
            new RangeProtocolVault{
                salt: keccak256(
                    abi.encodePacked(
                        token0,
                        token1,
                        fee,
                        manager,
                        name,
                        symbol
                    )
                )
            } (
                pool,
                tickSpacing,
                treasury,
                manager,
                managerFee,
                name,
                symbol
            )
        );

        vaults[token0][token1][fee] = vault;
        vaults[token1][token0][fee] = vault;
        allVaults.push(vault);
    }
}
