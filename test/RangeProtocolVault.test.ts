import {ethers} from "hardhat";
import {expect} from "chai";
import {anyValue} from "@nomicfoundation/hardhat-chai-matchers/withArgs";
import {SignerWithAddress} from "@nomiclabs/hardhat-ethers/dist/src/signer-with-address";
import {
    IERC20,
    IUniswapV3Factory,
    IUniswapV3Pool,
    RangeProtocolVault,
    RangeProtocolFactory,
} from "../typechain";
import {bn, encodePriceSqrt, parseEther, ZERO_ADDRESS} from "./common";
import {beforeEach} from "mocha";
import {BigNumber} from "bignumber.js";
import {BigNumberish} from "ethers";

let factory: RangeProtocolFactory;
let vault: RangeProtocolVault;
let uniV3Factory: IUniswapV3Factory;
let univ3Pool: IUniswapV3Pool;
let token0: IERC20;
let token1: IERC20;
let manager: SignerWithAddress;
let treasury: SignerWithAddress;
let nonManager: SignerWithAddress;
const managerFee = 500;
const poolFee = 3000;
const tickSpacing = 60;
const name = "Test Token";
const symbol = "TT";
const amount0: BigNumberish = parseEther("2");
const amount1: BigNumberish = parseEther("3");

BigNumber.config({ EXPONENTIAL_AT: 999999, DECIMAL_PLACES: 40 });

describe("RangeProtocolVault", () => {
    before(async () => {
        [manager, nonManager, treasury] = await ethers.getSigners();
        const UniswapV3Factory = await ethers.getContractFactory("UniswapV3Factory");
        uniV3Factory = await UniswapV3Factory.deploy() as IUniswapV3Factory;

        const RangeProtocolFactory = await ethers.getContractFactory("RangeProtocolFactory");
        factory = await RangeProtocolFactory.deploy(uniV3Factory.address) as RangeProtocolFactory;

        const MockERC20 = await ethers.getContractFactory("MockERC20");
        token0 = await MockERC20.deploy() as IERC20;
        token1 = await MockERC20.deploy() as IERC20;

        if (bn(token0.address).gt(token1.address)) {
            const tmp = token0;
            token0 = token1;
            token1 = tmp;
        }

        await uniV3Factory.createPool(token0.address, token1.address, poolFee);
        univ3Pool = await ethers.getContractAt(
            "IUniswapV3Pool",
            await uniV3Factory.getPool(token0.address, token1.address, poolFee)
        ) as IUniswapV3Pool;

        await univ3Pool.initialize(encodePriceSqrt("1", "1"));
        await univ3Pool.increaseObservationCardinalityNext("15");

        await factory.createVault(
            token0.address,
            token1.address,
            poolFee,
            treasury.address,
            manager.address,
            managerFee,
            name,
            symbol
        );

        const vaultAddress = await factory.vaults(token0.address, token1.address, poolFee);
        vault = await ethers.getContractAt("RangeProtocolVault", vaultAddress) as RangeProtocolVault;
    });

    beforeEach(async () => {
        await token0.approve(vault.address, amount0);
        await token1.approve(vault.address, amount1);
    });

    it("should not mint when vault is not initialized", async () => {
        await expect(vault.mint(amount0)).to.be.revertedWith("NotInitialized");
    });

    it("non-manager should not be able to initialize vault", async () => {
        const lowerTick = -60;
        const upperTick = 60;
        expect(await vault.initialized()).to.be.equal(false);
        await expect(vault.connect(nonManager).initialize(lowerTick, upperTick))
            .to.be.revertedWith("Ownable: caller is not the manager");
    });

    it("should not initialize vault with out of range ticks", async () => {
        await expect(vault.connect(manager).initialize(-887273, 0))
            .to.be.revertedWithCustomError(vault,"TicksOutOfRange");

        await expect(vault.connect(manager).initialize(0, 887273))
            .to.be.revertedWithCustomError(vault,"TicksOutOfRange");
    });

    it("should not initialize vault with ticks not following tick spacing", async () => {
        await expect(vault.connect(manager).initialize(0, 1))
            .to.be.revertedWithCustomError(vault,"InvalidTicksSpacing");

        await expect(vault.connect(manager).initialize(1, 0))
            .to.be.revertedWithCustomError(vault,"InvalidTicksSpacing");
    });

    it("manager should be able to initialize vault", async () => {
        const lowerTick = 0;
        const upperTick = 60;
        expect(await vault.initialized()).to.be.equal(false);
        await expect(vault.connect(manager).initialize(lowerTick, upperTick))
            .to.emit(vault, "Initialized");

        expect(await vault.initialized()).to.be.equal(true);
        expect(await vault.lowerTick()).to.be.equal(lowerTick);
        expect(await vault.upperTick()).to.be.equal(upperTick);
    });

    it("should not allow minting with zero mint amount", async () => {
        const mintAmount = 0;
        await expect(vault.mint(mintAmount))
            .to.be.revertedWithCustomError(vault, "InvalidMintAmount");
    });

    it("should mint with zero totalSupply", async () => {
        const {
            mintAmount,
            amount0: _amount0,
            amount1: _amount1
        } = await vault.getMintAmounts(amount0, amount1);

        expect(await vault.totalSupply()).to.be.equal(0);
        expect(await token0.balanceOf(univ3Pool.address)).to.be.equal(0);
        expect(await token1.balanceOf(univ3Pool.address)).to.be.equal(0);

        await expect(vault.mint(mintAmount))
            .to.emit(vault, "Minted")
            .withArgs(
                manager.address,
                mintAmount,
                _amount0,
                _amount1
            );

        expect(await vault.totalSupply()).to.be.equal(mintAmount);
        expect(await token0.balanceOf(univ3Pool.address)).to.be.equal(_amount0);
        expect(await token1.balanceOf(univ3Pool.address)).to.be.equal(_amount1);
    });

    it("should mint with non zero totalSupply", async () => {
        const {
            mintAmount,
            amount0: _amount0,
            amount1: _amount1
        } = await vault.getMintAmounts(amount0, amount1);

        expect(await vault.totalSupply()).to.not.be.equal(0);
        await expect(vault.mint(mintAmount))
            .to.emit(vault, "Minted")
            .withArgs(
                manager.address,
                mintAmount,
                _amount0,
                _amount1
            );
    });
});















