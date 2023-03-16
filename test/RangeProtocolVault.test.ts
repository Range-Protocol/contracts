import { ethers } from "hardhat";
import { expect } from "chai";
import { anyValue } from "@nomicfoundation/hardhat-chai-matchers/withArgs";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/dist/src/signer-with-address";
import {
  IERC20,
  IUniswapV3Factory,
  IUniswapV3Pool,
  RangeProtocolVault,
  RangeProtocolFactory,
} from "../typechain";
import {
  bn,
  encodePriceSqrt,
  getInitializeData,
  parseEther,
  position,
} from "./common";
import { beforeEach } from "mocha";
import { BigNumber } from "ethers";

let factory: RangeProtocolFactory;
let vaultImpl: RangeProtocolVault;
let vault: RangeProtocolVault;
let uniV3Factory: IUniswapV3Factory;
let univ3Pool: IUniswapV3Pool;
let token0: IERC20;
let token1: IERC20;
let manager: SignerWithAddress;
let treasury: SignerWithAddress;
let nonManager: SignerWithAddress;
let user2: SignerWithAddress;
const managerFee = 500;
const poolFee = 3000;
const name = "Test Token";
const symbol = "TT";
const amount0: BigNumber = parseEther("2");
const amount1: BigNumber = parseEther("3");
let initializeData: any;
const lowerTick = -887220;
const upperTick = 887220;
8388607;

describe("RangeProtocolVault", () => {
  before(async () => {
    [manager, nonManager, treasury, user2] = await ethers.getSigners();
    const UniswapV3Factory = await ethers.getContractFactory(
      "UniswapV3Factory"
    );
    uniV3Factory = (await UniswapV3Factory.deploy()) as IUniswapV3Factory;

    const RangeProtocolFactory = await ethers.getContractFactory(
      "RangeProtocolFactory"
    );
    factory = (await RangeProtocolFactory.deploy(
      uniV3Factory.address
    )) as RangeProtocolFactory;

    const MockERC20 = await ethers.getContractFactory("MockERC20");
    token0 = (await MockERC20.deploy()) as IERC20;
    token1 = (await MockERC20.deploy()) as IERC20;

    if (bn(token0.address).gt(token1.address)) {
      const tmp = token0;
      token0 = token1;
      token1 = tmp;
    }

    await uniV3Factory.createPool(token0.address, token1.address, poolFee);
    univ3Pool = (await ethers.getContractAt(
      "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol:IUniswapV3Pool",
      await uniV3Factory.getPool(token0.address, token1.address, poolFee)
    )) as IUniswapV3Pool;

    await univ3Pool.initialize(encodePriceSqrt("1", "1"));
    await univ3Pool.increaseObservationCardinalityNext("15");

    initializeData = getInitializeData({
      treasuryAddress: treasury.address,
      managerAddress: manager.address,
      managerFee,
      name,
      symbol,
    });

    // eslint-disable-next-line @typescript-eslint/naming-convention
    const RangeProtocolVault = await ethers.getContractFactory(
      "RangeProtocolVault"
    );
    vaultImpl = (await RangeProtocolVault.deploy()) as RangeProtocolVault;

    await factory.createVault(
      token0.address,
      token1.address,
      poolFee,
      vaultImpl.address,
      initializeData
    );

    const vaultAddress = await factory.vaults(
      token0.address,
      token1.address,
      poolFee
    );
    vault = (await ethers.getContractAt(
      "RangeProtocolVault",
      vaultAddress
    )) as RangeProtocolVault;
  });

  beforeEach(async () => {
    await token0.approve(vault.address, amount0.mul(bn(2)));
    await token1.approve(vault.address, amount1.mul(bn(2)));
  });

  it("should not mint when vault is not initialized", async () => {
    await expect(vault.mint(amount0)).to.be.revertedWith("MintNotStarted");
  });

  it("non-manager should not be able to updateTicks", async () => {
    expect(await vault.mintStarted()).to.be.equal(false);
    await expect(
      vault.connect(nonManager).updateTicks(lowerTick, upperTick)
    ).to.be.revertedWith("Ownable: caller is not the manager");
  });

  it("should not updateTicks with out of range ticks", async () => {
    await expect(
      vault.connect(manager).updateTicks(-887273, 0)
    ).to.be.revertedWithCustomError(vault, "TicksOutOfRange");

    await expect(
      vault.connect(manager).updateTicks(0, 887273)
    ).to.be.revertedWithCustomError(vault, "TicksOutOfRange");
  });

  it("should not updateTicks with ticks not following tick spacing", async () => {
    await expect(
      vault.connect(manager).updateTicks(0, 1)
    ).to.be.revertedWithCustomError(vault, "InvalidTicksSpacing");

    await expect(
      vault.connect(manager).updateTicks(1, 0)
    ).to.be.revertedWithCustomError(vault, "InvalidTicksSpacing");
  });

  it("manager should be able to updateTicks", async () => {
    expect(await vault.mintStarted()).to.be.equal(false);
    await expect(vault.connect(manager).updateTicks(lowerTick, upperTick))
      .to.emit(vault, "MintStarted")
      .to.emit(vault, "TicksSet")
      .withArgs(lowerTick, upperTick);

    expect(await vault.mintStarted()).to.be.equal(true);
    expect(await vault.lowerTick()).to.be.equal(lowerTick);
    expect(await vault.upperTick()).to.be.equal(upperTick);
  });

  it("should not allow minting with zero mint amount", async () => {
    const mintAmount = 0;
    await expect(vault.mint(mintAmount)).to.be.revertedWithCustomError(
      vault,
      "InvalidMintAmount"
    );
  });

  it("should mint with zero totalSupply of vault shares", async () => {
    const {
      mintAmount,
      // eslint-disable-next-line @typescript-eslint/naming-convention
      amount0: _amount0,
      // eslint-disable-next-line @typescript-eslint/naming-convention
      amount1: _amount1,
    } = await vault.getMintAmounts(amount0, amount1);

    expect(await vault.totalSupply()).to.be.equal(0);
    expect(await token0.balanceOf(univ3Pool.address)).to.be.equal(0);
    expect(await token1.balanceOf(univ3Pool.address)).to.be.equal(0);

    await expect(vault.mint(mintAmount))
      .to.emit(vault, "Minted")
      .withArgs(manager.address, mintAmount, _amount0, _amount1);

    expect(await vault.totalSupply()).to.be.equal(mintAmount);
    expect(await token0.balanceOf(univ3Pool.address)).to.be.equal(_amount0);
    expect(await token1.balanceOf(univ3Pool.address)).to.be.equal(_amount1);
  });

  it("should mint with non zero totalSupply", async () => {
    const {
      mintAmount,
      // eslint-disable-next-line @typescript-eslint/naming-convention
      amount0: _amount0,
      // eslint-disable-next-line @typescript-eslint/naming-convention
      amount1: _amount1,
    } = await vault.getMintAmounts(amount0, amount1);

    expect(await vault.totalSupply()).to.not.be.equal(0);
    await expect(vault.mint(mintAmount))
      .to.emit(vault, "Minted")
      .withArgs(manager.address, mintAmount, _amount0, _amount1);
  });

  it("should not burn non existing vault shares", async () => {
    const burnAmount = parseEther("1");
    await expect(vault.connect(user2).burn(burnAmount)).to.be.revertedWith(
      "ERC20: burn amount exceeds balance"
    );
  });

  it("should burn vault shares", async () => {
    const burnAmount = await vault.balanceOf(manager.address);
    const totalSupplyBefore = await vault.totalSupply();
    const [amount0Current, amount1Current] =
      await vault.getUnderlyingBalances();
    const userBalance0Before = await token0.balanceOf(manager.address);
    const userBalance1Before = await token1.balanceOf(manager.address);

    await vault.burn(burnAmount);

    expect(await vault.totalSupply()).to.be.equal(
      totalSupplyBefore.sub(burnAmount)
    );
    expect(await token0.balanceOf(manager.address)).to.be.equal(
      userBalance0Before.add(
        amount0Current.mul(burnAmount).div(totalSupplyBefore)
      )
    );
    expect(await token1.balanceOf(manager.address)).to.be.equal(
      userBalance1Before.add(
        amount1Current.mul(burnAmount).div(totalSupplyBefore)
      )
    );
  });

  it("should not add liquidity when total supply is zero and vault is out of the pool", async () => {
    const { mintAmount } = await vault.getMintAmounts(amount0, amount1);
    await vault.mint(mintAmount);
    await vault.removeLiquidity();
    await vault.burn(await vault.balanceOf(manager.address));

    await expect(vault.mint(mintAmount)).to.be.revertedWithCustomError(
      vault,
      "MintNotAllowed"
    );
  });

  describe("Manager Fee", () => {
    it("should not update manager fee by non manager", async () => {
      await expect(
        vault.connect(nonManager).updateManagerFee(100)
      ).to.be.revertedWith("Ownable: caller is not the manager");
    });

    it("should not update manager fee above BPS", async () => {
      await expect(vault.updateManagerFee(2000)).to.be.revertedWithCustomError(
        vault,
        "InvalidManagerFee"
      );
    });

    it("should update manager fee by manager", async () => {
      await expect(vault.updateManagerFee(300))
        .to.emit(vault, "ManagerFeeUpdated")
        .withArgs(300);
    });
  });

  describe("Remove Liquidity", () => {
    before(async () => {
      await vault.updateTicks(lowerTick, upperTick);
    });

    beforeEach(async () => {
      await token0.approve(vault.address, amount0.mul(bn(2)));
      await token1.approve(vault.address, amount1.mul(bn(2)));
      const { mintAmount } = await vault.getMintAmounts(amount0, amount1);
      await vault.mint(mintAmount);
    });

    it("should not remove liquidity by non-manager", async () => {
      await expect(
        vault.connect(nonManager).removeLiquidity()
      ).to.be.revertedWith("Ownable: caller is not the manager");
    });

    it("should remove liquidity by manager", async () => {
      expect(await vault.lowerTick()).to.not.be.equal(await vault.upperTick());
      expect(await vault.inThePosition()).to.be.equal(true);
      const { _liquidity: liquidityBefore } = await univ3Pool.positions(
        position(vault.address, lowerTick, upperTick)
      );
      expect(liquidityBefore).not.to.be.equal(0);

      await expect(vault.removeLiquidity())
        .to.be.emit(vault, "InThePositionStatusSet")
        .withArgs(false);

      expect(await vault.lowerTick()).to.be.equal(await vault.upperTick());
      expect(await vault.inThePosition()).to.be.equal(false);
      const { _liquidity: liquidityAfter } = await univ3Pool.positions(
        position(vault.address, -60, 60)
      );
      expect(liquidityAfter).to.be.equal(0);
    });

    it("should burn vault shares when liquidity is removed", async () => {
      const { _liquidity: liquidity } = await univ3Pool.positions(
        position(vault.address, -60, 60)
      );
      expect(liquidity).to.be.equal(0);
      await expect(vault.removeLiquidity())
        .to.be.emit(vault, "InThePositionStatusSet")
        .withArgs(false);

      const userBalance0Before = await token0.balanceOf(manager.address);
      const userBalance1Before = await token1.balanceOf(manager.address);
      const [amount0Current, amount1Current] =
        await vault.getUnderlyingBalances();
      const totalSupply = await vault.totalSupply();
      const vaultShares = await vault.balanceOf(manager.address);

      await vault.burn(vaultShares);
      expect(await token0.balanceOf(manager.address)).to.be.equal(
        userBalance0Before.add(amount0Current.mul(vaultShares).div(totalSupply))
      );
      expect(await token1.balanceOf(manager.address)).to.be.equal(
        userBalance1Before.add(amount1Current.mul(vaultShares).div(totalSupply))
      );
    });
  });

  describe("Add Liquidity", () => {
    before(async () => {
      await vault.updateTicks(lowerTick, upperTick);
    });

    beforeEach(async () => {
      await token0.approve(vault.address, amount0.mul(bn(2)));
      await token1.approve(vault.address, amount1.mul(bn(2)));
      const { mintAmount } = await vault.getMintAmounts(amount0, amount1);
      await vault.mint(mintAmount);
      await vault.removeLiquidity();
    });

    it("should not add liquidity by non-manager", async () => {
      const amount0 = await token0.balanceOf(vault.address);
      const amount1 = await token1.balanceOf(vault.address);

      await expect(
        vault
          .connect(nonManager)
          .addLiquidity(lowerTick, upperTick, amount0, amount1)
      ).to.be.revertedWith("Ownable: caller is not the manager");
    });

    it("should add liquidity by manager", async () => {
      const amount0 = await token0.balanceOf(vault.address);
      const amount1 = await token1.balanceOf(vault.address);

      // eslint-disable-next-line @typescript-eslint/naming-convention
      const MockLiquidityAmounts = await ethers.getContractFactory(
        "MockLiquidityAmounts"
      );
      const mockLiquidityAmounts = await MockLiquidityAmounts.deploy();

      const { sqrtPriceX96 } = await univ3Pool.slot0();
      const liquidity = mockLiquidityAmounts.getLiquidityForAmounts(
        sqrtPriceX96,
        lowerTick,
        upperTick,
        amount0,
        amount1
      );

      await expect(vault.addLiquidity(lowerTick, upperTick, amount0, amount1))
        .to.emit(vault, "LiquidityAdded")
        .withArgs(liquidity, lowerTick, upperTick, anyValue, anyValue)
        .to.emit(vault, "InThePositionStatusSet")
        .withArgs(true);
    });
  });

  describe("Fee collection", () => {
    it("should manager and treasury collect fee", async () => {
      expect(await vault.managerBalance0()).to.be.equal(0);
      expect(await vault.managerBalance1()).to.be.equal(0);
      expect(await vault.treasuryBalance0()).to.be.equal(0);
      expect(await vault.treasuryBalance1()).to.be.equal(0);

      const { sqrtPriceX96 } = await univ3Pool.slot0();
      const liquidity = await univ3Pool.liquidity();
      await token1.transfer(vault.address, amount1);
      const priceNext = amount1.mul(bn(2).pow(96)).div(liquidity);
      await vault.swap(false, amount1, sqrtPriceX96.add(priceNext));

      const { fee0, fee1 } = await vault.getCurrentFees();
      await expect(vault.pullFeeFromPool())
        .to.emit(vault, "FeesEarned")
        .withArgs(fee0, fee1);

      const managerBalance0 = await vault.managerBalance0();
      const managerBalance1 = await vault.managerBalance1();
      const treasuryBalance0 = await vault.treasuryBalance0();
      const treasuryBalance1 = await vault.treasuryBalance1();

      const totalFee = {
        fee0: fee0.add(managerBalance0).add(treasuryBalance0),
        fee1: fee1.add(managerBalance1).add(treasuryBalance1),
      };
      expect(managerBalance0).to.be.equal(
        totalFee.fee0.mul(await vault.managerFee()).div(bn(10_000))
      );
      expect(managerBalance1).to.be.equal(
        totalFee.fee1.mul(await vault.managerFee()).div(bn(10_000))
      );
      expect(treasuryBalance0).to.be.equal(
        totalFee.fee0.mul(await vault.TREASURY_FEE_BPS()).div(bn(10_000))
      );
      expect(treasuryBalance1).to.be.equal(
        totalFee.fee1.mul(await vault.TREASURY_FEE_BPS()).div(bn(10_000))
      );

      const managerBalance0Before = await token0.balanceOf(manager.address);
      const managerBalance1Before = await token1.balanceOf(manager.address);
      const treasuryBalance0Before = await token0.balanceOf(treasury.address);
      const treasuryBalance1Before = await token1.balanceOf(treasury.address);

      await vault.connect(manager).collectManager();
      await vault.connect(treasury).collectTreasury();

      expect(await token0.balanceOf(manager.address)).to.be.gte(
        managerBalance0Before
      );
      expect(await token1.balanceOf(manager.address)).to.be.gte(
        managerBalance1Before
      );
      expect(await token0.balanceOf(treasury.address)).to.be.gte(
        treasuryBalance0Before
      );
      expect(await token1.balanceOf(manager.address)).to.be.gte(
        treasuryBalance1Before
      );

      expect(await vault.managerBalance0()).to.be.equal(0);
      expect(await vault.managerBalance1()).to.be.equal(0);
      expect(await vault.treasuryBalance0()).to.be.equal(0);
      expect(await vault.treasuryBalance1()).to.be.equal(0);
    });
  });

  describe("Test Upgradeability", () => {
    it("should not upgrade range vault implementation by non-manager of factory", async () => {
      // eslint-disable-next-line @typescript-eslint/naming-convention
      const RangeProtocolVault = await ethers.getContractFactory(
        "RangeProtocolVault"
      );
      const newVaultImpl =
        (await RangeProtocolVault.deploy()) as RangeProtocolVault;

      await expect(
        factory
          .connect(nonManager)
          .upgradeVault(vault.address, newVaultImpl.address)
      ).to.be.revertedWith("Ownable: caller is not the manager");

      await expect(
        factory
          .connect(nonManager)
          .upgradeVaults([vault.address], [newVaultImpl.address])
      ).to.be.revertedWith("Ownable: caller is not the manager");
    });

    it("should upgrade range vault implementation by factory manager", async () => {
      // eslint-disable-next-line @typescript-eslint/naming-convention
      const RangeProtocolVault = await ethers.getContractFactory(
        "RangeProtocolVault"
      );
      const newVaultImpl =
        (await RangeProtocolVault.deploy()) as RangeProtocolVault;

      const implSlot = await vaultImpl.proxiableUUID();
      expect(
        ethers.utils.hexStripZeros(
          await ethers.provider.getStorageAt(vault.address, implSlot)
        )
      ).to.be.equal(vaultImpl.address.toLowerCase());

      await expect(factory.upgradeVault(vault.address, newVaultImpl.address))
        .to.emit(factory, "VaultImplUpgraded")
        .withArgs(vault.address, newVaultImpl.address);

      expect(
        ethers.utils.hexStripZeros(
          await ethers.provider.getStorageAt(vault.address, implSlot)
        )
      ).to.be.equal(newVaultImpl.address.toLowerCase());

      const newVaultImpl1 =
        (await RangeProtocolVault.deploy()) as RangeProtocolVault;

      expect(
        ethers.utils.hexStripZeros(
          await ethers.provider.getStorageAt(vault.address, implSlot)
        )
      ).to.be.equal(newVaultImpl.address.toLowerCase());

      await expect(
        factory.upgradeVaults([vault.address], [newVaultImpl1.address])
      )
        .to.emit(factory, "VaultImplUpgraded")
        .withArgs(vault.address, newVaultImpl1.address);

      expect(
        ethers.utils.hexStripZeros(
          await ethers.provider.getStorageAt(vault.address, implSlot)
        )
      ).to.be.equal(newVaultImpl1.address.toLowerCase());
    });
  });
});
