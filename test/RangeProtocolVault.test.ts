import { ethers } from "hardhat";
import { expect } from "chai";
import { anyValue } from "@nomicfoundation/hardhat-chai-matchers/withArgs";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/dist/src/signer-with-address";
import {
  IERC20,
  IAlgebraFactory,
  IAlgebraPool,
  RangeProtocolVault,
  RangeProtocolFactory,
} from "../typechain";
import { bn, encodePriceSqrt, getInitializeData, parseEther } from "./common";
import { beforeEach } from "mocha";
import { BigNumber } from "ethers";

let factory: RangeProtocolFactory;
let vaultImpl: RangeProtocolVault;
let vault: RangeProtocolVault;
let algebraFactory: IAlgebraFactory;
let algebraPool: IAlgebraPool;
let token0: IERC20;
let token1: IERC20;
let manager: SignerWithAddress;
let nonManager: SignerWithAddress;
let newManager: SignerWithAddress;
let user2: SignerWithAddress;
const name = "Test Token";
const symbol = "TT";
const amount0: BigNumber = parseEther("2");
const amount1: BigNumber = parseEther("3");
let initializeData: any;
const bottomTick = -887040;
const topTick = 887040;

describe("RangeProtocolVault", () => {
  before(async () => {
    [manager, nonManager, user2, newManager] = await ethers.getSigners();
    // eslint-disable-next-line @typescript-eslint/naming-convention
    const MockERC20 = await ethers.getContractFactory("MockERC20");
    token0 = (await MockERC20.deploy()) as IERC20;
    token1 = (await MockERC20.deploy()) as IERC20;

    if (bn(token0.address).gt(token1.address)) {
      const tmp = token0;
      token0 = token1;
      token1 = tmp;
    }

    // eslint-disable-next-line @typescript-eslint/naming-convention
    const RangeProtocolFactory = await ethers.getContractFactory(
      "RangeProtocolFactory"
    );
    algebraFactory = (await ethers.getContractAt(
      "IAlgebraFactory",
      "0x411b0fAcC3489691f28ad58c47006AF5E3Ab3A28"
    )) as IAlgebraFactory;
    await algebraFactory.createPool(token0.address, token1.address);

    factory = (await RangeProtocolFactory.deploy(
      algebraFactory.address
    )) as RangeProtocolFactory;

    algebraPool = (await ethers.getContractAt(
      "IAlgebraPool",
      await algebraFactory.poolByPair(token0.address, token1.address)
    )) as IAlgebraPool;

    await algebraPool.initialize(encodePriceSqrt("1", "1"));

    // eslint-disable-next-line @typescript-eslint/naming-convention
    const RangeProtocolVault = await ethers.getContractFactory(
      "RangeProtocolVault"
    );
    vaultImpl = (await RangeProtocolVault.deploy()) as RangeProtocolVault;

    initializeData = getInitializeData({
      managerAddress: manager.address,
      name,
      symbol,
    });

    await factory.createVault(
      token0.address,
      token1.address,
      vaultImpl.address,
      initializeData
    );

    const vaultAddress = await factory.getVaultAddresses(0, 0);
    vault = (await ethers.getContractAt(
      "RangeProtocolVault",
      vaultAddress[0]
    )) as RangeProtocolVault;
  });

  beforeEach(async () => {
    await token0.approve(vault.address, amount0.mul(bn(2)));
    await token1.approve(vault.address, amount1.mul(bn(2)));
  });

  it("should not mint when vault is not initialized", async () => {
    await expect(vault.mint(amount0)).to.be.revertedWithCustomError(
      vault,
      "MintNotStarted"
    );
  });

  it("non-manager should not be able to updateTicks", async () => {
    expect(await vault.mintStarted()).to.be.equal(false);
    await expect(
      vault.connect(nonManager).updateTicks(bottomTick, topTick)
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
    await expect(vault.connect(manager).updateTicks(bottomTick, topTick))
      .to.emit(vault, "MintStarted")
      .to.emit(vault, "TicksSet")
      .withArgs(bottomTick, topTick);

    expect(await vault.mintStarted()).to.be.equal(true);
    expect(await vault.bottomTick()).to.be.equal(bottomTick);
    expect(await vault.topTick()).to.be.equal(topTick);
  });

  it("should not allow minting with zero mint amount", async () => {
    const mintAmount = 0;
    await expect(vault.mint(mintAmount)).to.be.revertedWithCustomError(
      vault,
      "InvalidMintAmount"
    );
  });

  it("should not mint when contract is paused", async () => {
    expect(await vault.paused()).to.be.equal(false);
    await expect(vault.pause())
      .to.emit(vault, "Paused")
      .withArgs(manager.address);
    expect(await vault.paused()).to.be.equal(true);

    const { mintAmount } = await vault.getMintAmounts(amount0, amount1);

    await expect(vault.mint(mintAmount)).to.be.revertedWith("Pausable: paused");
    await expect(vault.unpause())
      .to.emit(vault, "Unpaused")
      .withArgs(manager.address);
  });

  it("should mint with zero totalSupply of vault shares", async () => {
    const {
      mintAmount,
      // eslint-disable-next-line @typescript-eslint/naming-convention
      amount0: _amount0,
      // eslint-disable-next-line @typescript-eslint/naming-convention
      amount1: _amount1,
    } = await vault.getMintAmounts(amount0, amount1);
    // console.log(ethers.utils.formatEther(_amount0), ethers.utils.formatEther(_amount1))
    // 1.999999999999999999 1.999999999999999999

    expect(await vault.totalSupply()).to.be.equal(0);
    expect(await token0.balanceOf(algebraPool.address)).to.be.equal(0);
    expect(await token1.balanceOf(algebraPool.address)).to.be.equal(0);

    await expect(vault.mint(mintAmount))
      .to.emit(vault, "Minted")
      .withArgs(manager.address, mintAmount, _amount0, _amount1);

    expect(await vault.totalSupply()).to.be.equal(mintAmount);
    expect(await token0.balanceOf(algebraPool.address)).to.be.equal(_amount0);
    expect(await token1.balanceOf(algebraPool.address)).to.be.equal(_amount1);
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
    expect(await vault.userCount()).to.be.equal(1);
  });

  it("should mint with non zero totalSupply", async () => {
    const {
      mintAmount,
      // eslint-disable-next-line @typescript-eslint/naming-convention
      amount0: _amount0,
      // eslint-disable-next-line @typescript-eslint/naming-convention
      amount1: _amount1,
    } = await vault.getMintAmounts(amount0, amount1);
    // console.log(ethers.utils.formatEther(_amount0), ethers.utils.formatEther(_amount1))
    // 2.0 2.0

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
    expect(await vault.userCount()).to.be.equal(1);
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
    const { fee0, fee1 } = await vault.getCurrentFees();

    await expect(vault.burn(burnAmount))
      .to.emit(vault, "FeesEarned")
      .withArgs(fee0, fee1);
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
      userVault0Before.mul(vaultShares.sub(burnAmount)).div(vaultShares)
    );
    expect((await vault.userVaults(manager.address)).token1).to.be.equal(
      userVault1Before.mul(vaultShares.sub(burnAmount)).div(vaultShares)
    );

    expect(await vault.managerBalance0()).to.be.equal(managingFee0);
    expect(await vault.managerBalance1()).to.be.equal(managingFee1);
    // console.log(ethers.utils.formatEther(managingFee0), ethers.utils.formatEther(managingFee1))
    // 0.019999999999999999 0.019999999999999999
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
      await vault.updateTicks(bottomTick, topTick);
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
      expect(await vault.bottomTick()).to.not.be.equal(await vault.topTick());
      expect(await vault.inThePosition()).to.be.equal(true);
      const { liquidityAmount: liquidityBefore } = await algebraPool.positions(
        await vault.getPositionID()
      );
      expect(liquidityBefore).not.to.be.equal(0);

      const { fee0, fee1 } = await vault.getCurrentFees();
      await expect(vault.removeLiquidity())
        .to.emit(vault, "InThePositionStatusSet")
        .withArgs(false)
        .to.emit(vault, "FeesEarned")
        .withArgs(fee0, fee1);

      expect(await vault.bottomTick()).to.be.equal(await vault.topTick());
      expect(await vault.inThePosition()).to.be.equal(false);
      const { liquidityAmount: liquidityAfter } = await algebraPool.positions(
        await vault.getPositionID()
      );
      expect(liquidityAfter).to.be.equal(0);
    });

    it("should burn vault shares when liquidity is removed", async () => {
      const { liquidityAmount: liquidity } = await algebraPool.positions(
        await vault.getPositionID()
      );

      expect(liquidity).to.be.equal(0);
      await expect(vault.removeLiquidity())
        .to.be.emit(vault, "InThePositionStatusSet")
        .withArgs(false)
        .not.to.emit(vault, "FeesEarned");

      const userBalance0Before = await token0.balanceOf(manager.address);
      const userBalance1Before = await token1.balanceOf(manager.address);
      const [amount0Current, amount1Current] =
        await vault.getUnderlyingBalances();
      const totalSupply = await vault.totalSupply();
      const vaultShares = await vault.balanceOf(manager.address);
      const managerBalance0Before = await vault.managerBalance0();
      const managerBalance1Before = await vault.managerBalance1();

      const managingFee = await vault.managingFee();
      const userBalance0 = amount0Current.mul(vaultShares).div(totalSupply);
      const managingFee0 = userBalance0.mul(managingFee).div(10_000);

      const userBalance1 = amount1Current.mul(vaultShares).div(totalSupply);
      const managingFee1 = userBalance1.mul(managingFee).div(10_000);

      await expect(vault.burn(vaultShares)).not.to.emit(vault, "FeesEarned");
      expect(await token0.balanceOf(manager.address)).to.be.equal(
        userBalance0Before.add(userBalance0).sub(managingFee0)
      );
      expect(await token1.balanceOf(manager.address)).to.be.equal(
        userBalance1Before.add(userBalance1).sub(managingFee1)
      );
      expect(await vault.managerBalance0()).to.be.equal(
        managerBalance0Before.add(managingFee0)
      );
      expect(await vault.managerBalance1()).to.be.equal(
        managerBalance1Before.add(managingFee1)
      );

      // console.log(ethers.utils.formatEther(await vault.managerBalance0()), ethers.utils.formatEther(await vault.managerBalance1()))
      // 0.089999999999999997 0.089999999999999997
    });
  });

  describe("Add Liquidity", () => {
    before(async () => {
      await vault.updateTicks(bottomTick, topTick);
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
          .addLiquidity(bottomTick, topTick, amount0, amount1)
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

      const { price } = await algebraPool.globalState();
      const liquidity = mockLiquidityAmounts.getLiquidityForAmounts(
        price,
        bottomTick,
        topTick,
        amount0Current,
        amount1Current
      );

      await expect(
        vault.addLiquidity(bottomTick, topTick, amount0Current, amount1Current)
      )
        .to.emit(vault, "LiquidityAdded")
        .withArgs(liquidity, bottomTick, topTick, anyValue, anyValue)
        .to.emit(vault, "InThePositionStatusSet")
        .withArgs(true);
    });
  });

  describe("Fee collection", () => {
    it("non-manager should not collect fee", async () => {
      const { price } = await algebraPool.globalState();
      const liquidity = await algebraPool.liquidity();
      await token1.transfer(vault.address, amount1);
      const priceNext = amount1.mul(bn(2).pow(96)).div(liquidity);
      await vault.swap(false, amount1, price.add(priceNext));

      const { fee0, fee1 } = await vault.getCurrentFees();
      await expect(vault.pullFeeFromPool())
        .to.emit(vault, "FeesEarned")
        .withArgs(fee0, fee1);

      await expect(
        vault.connect(nonManager).collectManager()
      ).to.be.revertedWith("Ownable: caller is not the manager");
    });

    it("should manager collect fee", async () => {
      const { price } = await algebraPool.globalState();
      const liquidity = await algebraPool.liquidity();
      await token1.transfer(vault.address, amount1);
      const priceNext = amount1.mul(bn(2).pow(96)).div(liquidity);
      await vault.swap(false, amount1, price.add(priceNext));

      const { fee0, fee1 } = await vault.getCurrentFees();
      await expect(vault.pullFeeFromPool())
        .to.emit(vault, "FeesEarned")
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
      ).to.be.revertedWith("Ownable: caller is not the owner");

      await expect(
        factory
          .connect(nonManager)
          .upgradeVaults([vault.address], [newVaultImpl.address])
      ).to.be.revertedWith("Ownable: caller is not the owner");
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
        await ethers.provider.getStorageAt(vault.address, implSlot)
      ).to.be.equal(
        ethers.utils.hexZeroPad(vaultImpl.address.toLowerCase(), 32)
      );
      await expect(factory.upgradeVault(vault.address, newVaultImpl.address))
        .to.emit(factory, "VaultImplUpgraded")
        .withArgs(vault.address, newVaultImpl.address);

      expect(
        await ethers.provider.getStorageAt(vault.address, implSlot)
      ).to.be.equal(
        ethers.utils.hexZeroPad(newVaultImpl.address.toLowerCase(), 32)
      );

      const newVaultImpl1 =
        (await RangeProtocolVault.deploy()) as RangeProtocolVault;

      expect(
        await ethers.provider.getStorageAt(vault.address, implSlot)
      ).to.be.equal(
        ethers.utils.hexZeroPad(newVaultImpl.address.toLowerCase(), 32)
      );
      await expect(
        factory.upgradeVaults([vault.address], [newVaultImpl1.address])
      )
        .to.emit(factory, "VaultImplUpgraded")
        .withArgs(vault.address, newVaultImpl1.address);

      expect(
        await ethers.provider.getStorageAt(vault.address, implSlot)
      ).to.be.equal(
        ethers.utils.hexZeroPad(newVaultImpl1.address.toLowerCase(), 32)
      );

      vaultImpl = newVaultImpl1;
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
