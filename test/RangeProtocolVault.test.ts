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
let nonManager: SignerWithAddress;
let newManager: SignerWithAddress;
let user2: SignerWithAddress;
const poolFee = 3000;
const name = "Test Token";
const symbol = "TT";
const amount0: BigNumber = parseEther("2");
const amount1: BigNumber = parseEther("3");
let initializeData: any;
const lowerTick = -887220;
const upperTick = 887220;

describe("RangeProtocolVault", () => {
  before(async () => {
    [manager, nonManager, user2, newManager] = await ethers.getSigners();
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
      managerAddress: manager.address,
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
    expect(await vault.users(0)).to.be.equal(manager.address);
    expect((await vault.userVaults(manager.address)).exists).to.be.true;
    expect((await vault.userVaults(manager.address)).token0).to.be.equal(
      _amount0
    );
    expect((await vault.userVaults(manager.address)).token1).to.be.equal(
      _amount1
    );

    const userVault = (await vault.getUserVaults(0, 0))[0];
    expect(userVault.user).to.be.equal(manager.address);
    expect(userVault.token0).to.be.equal(_amount0);
    expect(userVault.token1).to.be.equal(_amount1);
  });

  it("should mint with non zero totalSupply", async () => {
    const {
      mintAmount,
      // eslint-disable-next-line @typescript-eslint/naming-convention
      amount0: _amount0,
      // eslint-disable-next-line @typescript-eslint/naming-convention
      amount1: _amount1,
    } = await vault.getMintAmounts(amount0, amount1);

    const userVault0Before = (await vault.userVaults(manager.address)).token0;
    const userVault1Before = (await vault.userVaults(manager.address)).token1;

    expect(await vault.totalSupply()).to.not.be.equal(0);
    await expect(vault.mint(mintAmount))
      .to.emit(vault, "Minted")
      .withArgs(manager.address, mintAmount, _amount0, _amount1);

    expect(await vault.users(0)).to.be.equal(manager.address);
    expect((await vault.userVaults(manager.address)).exists).to.be.true;
    expect((await vault.userVaults(manager.address)).token0).to.be.equal(
      userVault0Before.add(_amount0)
    );
    expect((await vault.userVaults(manager.address)).token1).to.be.equal(
      userVault1Before.add(_amount1)
    );

    const userVault = (await vault.getUserVaults(0, 0))[0];
    expect(userVault.user).to.be.equal(manager.address);
    expect(userVault.token0).to.be.equal(userVault0Before.add(_amount0));
    expect(userVault.token1).to.be.equal(userVault1Before.add(_amount1));
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

    const balanceBefore = await vault.balanceOf(manager.address);
    const userVault0Before = (await vault.userVaults(manager.address)).token0;
    const userVault1Before = (await vault.userVaults(manager.address)).token1;
    await vault.updateFees(50, 250);

    const managingFee = await vault.managingFee();
    const totalSupply = await vault.totalSupply();
    const vaultShares = await vault.balanceOf(manager.address);
    const userBalance0 = amount0Current.mul(vaultShares).div(totalSupply);
    const managingFee0 = userBalance0.mul(managingFee).div(10_000);

    const userBalance1 = amount1Current.mul(vaultShares).div(totalSupply);
    const managingFee1 = userBalance1.mul(managingFee).div(10_000);

    await expect(vault.burn(burnAmount))
      .to.emit(vault, "ManagingFeeEarned")
      .withArgs(managingFee0, managingFee1);
    expect(await vault.totalSupply()).to.be.equal(
      totalSupplyBefore.sub(burnAmount)
    );

    const amount0Got = amount0Current.mul(burnAmount).div(totalSupplyBefore);
    const amount1Got = amount1Current.mul(burnAmount).div(totalSupplyBefore);

    expect(await token0.balanceOf(manager.address)).to.be.equal(
      userBalance0Before.add(amount0Got).sub(managingFee0)
    );
    expect(await token1.balanceOf(manager.address)).to.be.equal(
      userBalance1Before.add(amount1Got).sub(managingFee1)
    );
    expect((await vault.userVaults(manager.address)).token0).to.be.equal(
      userVault0Before.mul(balanceBefore.sub(burnAmount)).div(balanceBefore)
    );
    expect((await vault.userVaults(manager.address)).token1).to.be.equal(
      userVault1Before.mul(balanceBefore.sub(burnAmount)).div(balanceBefore)
    );

    const userVault = (await vault.getUserVaults(0, 0))[0];
    expect(userVault.user).to.be.equal(manager.address);
    expect(userVault.token0).to.be.equal(
      userVault0Before.mul(balanceBefore.sub(burnAmount)).div(balanceBefore)
    );
    expect(userVault.token1).to.be.equal(
      userVault1Before.mul(balanceBefore.sub(burnAmount)).div(balanceBefore)
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
    it("should not update managing and performance fee by non manager", async () => {
      await expect(
        vault.connect(nonManager).updateFees(100, 1000)
      ).to.be.revertedWith("Ownable: caller is not the manager");
    });

    it("should not update managing fee above BPS", async () => {
      await expect(vault.updateFees(101, 100)).to.be.revertedWithCustomError(
        vault,
        "InvalidManagingFee"
      );
    });

    it("should not update performance fee above BPS", async () => {
      await expect(vault.updateFees(100, 10001)).to.be.revertedWithCustomError(
        vault,
        "InvalidPerformanceFee"
      );
    });

    it("should update manager and performance fee by manager", async () => {
      await expect(vault.updateFees(100, 300))
        .to.emit(vault, "FeesUpdated")
        .withArgs(100, 300);
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

      const managingFee = await vault.managingFee();
      const userBalance0 = amount0Current.mul(vaultShares).div(totalSupply);
      const managingFee0 = userBalance0.mul(managingFee).div(10_000);

      const userBalance1 = amount1Current.mul(vaultShares).div(totalSupply);
      const managingFee1 = userBalance1.mul(managingFee).div(10_000);

      await expect(vault.burn(vaultShares))
        .to.emit(vault, "ManagingFeeEarned")
        .withArgs(managingFee0, managingFee1);
      expect(await token0.balanceOf(manager.address)).to.be.equal(
        userBalance0Before.add(userBalance0).sub(managingFee0)
      );
      expect(await token1.balanceOf(manager.address)).to.be.equal(
        userBalance1Before.add(userBalance1).sub(managingFee1)
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
      const { amount0Current, amount1Current } =
        await vault.getUnderlyingBalances();

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
        amount0Current,
        amount1Current
      );

      await expect(
        vault.addLiquidity(lowerTick, upperTick, amount0Current, amount1Current)
      )
        .to.emit(vault, "LiquidityAdded")
        .withArgs(liquidity, lowerTick, upperTick, anyValue, anyValue)
        .to.emit(vault, "InThePositionStatusSet")
        .withArgs(true);
    });
  });

  describe("Fee collection", () => {
    it("should manager collect fee", async () => {
      const { sqrtPriceX96 } = await univ3Pool.slot0();
      const liquidity = await univ3Pool.liquidity();
      await token1.transfer(vault.address, amount1);
      const priceNext = amount1.mul(bn(2).pow(96)).div(liquidity);
      await vault.swap(false, amount1, sqrtPriceX96.add(priceNext));

      const { fee0, fee1 } = await vault.getCurrentFees();
      await expect(vault.pullFeeFromPool())
        .to.emit(vault, "PerformanceFeeEarned")
        .withArgs(fee0, fee1);

      const managerBalance0 = await vault.managerBalance0();
      const managerBalance1 = await vault.managerBalance1();

      const managerBalance0Before = await token0.balanceOf(manager.address);
      const managerBalance1Before = await token1.balanceOf(manager.address);
      await vault.connect(manager).collectManager();

      const performanceFee0 = fee0
        .mul(await vault.performanceFee())
        .div(10_000);
      const performanceFee1 = fee0
        .mul(await vault.performanceFee())
        .div(10_000);

      expect(await token0.balanceOf(manager.address)).to.be.equal(
        managerBalance0Before.add(managerBalance0).add(performanceFee0)
      );
      expect(await token1.balanceOf(manager.address)).to.be.equal(
        managerBalance1Before.add(managerBalance1).add(performanceFee1)
      );

      expect(await vault.managerBalance0()).to.be.equal(0);
      expect(await vault.managerBalance1()).to.be.equal(0);
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
        "0x" +
          (await ethers.provider.getStorageAt(vault.address, implSlot)).slice(
            26,
            66
          )
      ).to.be.equal(newVaultImpl.address.toLowerCase());

      await expect(
        factory.upgradeVaults([vault.address], [newVaultImpl1.address])
      )
        .to.emit(factory, "VaultImplUpgraded")
        .withArgs(vault.address, newVaultImpl1.address);

      expect(
        "0x" +
          (await ethers.provider.getStorageAt(vault.address, implSlot)).slice(
            26,
            66
          )
      ).to.be.equal(newVaultImpl1.address.toLowerCase());
    });
  });

  describe("transferOwnership", () => {
    it("should not be able to transferOwnership by non manager", async () => {
      await expect(
        vault.connect(nonManager).transferOwnership(newManager.address)
      ).to.be.revertedWith("Ownable: caller is not the manager");
    });

    it("should be able to transferOwnership by manager", async () => {
      await expect(vault.transferOwnership(newManager.address))
        .to.emit(vault, "OwnershipTransferred")
        .withArgs(manager.address, newManager.address);
      expect(await vault.manager()).to.be.equal(newManager.address);

      await vault.connect(newManager).transferOwnership(manager.address);
      expect(await vault.manager()).to.be.equal(manager.address);
    });
  });
});
