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
import { Decimal } from "decimal.js";

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

  it("should not reinitialize the vault", async () => {
    await expect(
      vault.initialize(uniV3Factory.address, 1, "0x")
    ).to.be.revertedWith("Initializable: contract is already initialized");
  });

  it("should not mint when vault is not initialized", async () => {
    await expect(
      vault.mint(1111, [amount0, amount1])
    ).to.be.revertedWithCustomError(vault, "MintNotStarted");
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
    await expect(
      vault.mint(mintAmount, [amount0, amount1])
    ).to.be.revertedWithCustomError(vault, "InvalidMintAmount");
  });

  it("should not mint when contract is paused", async () => {
    expect(await vault.paused()).to.be.equal(false);
    await expect(vault.pause())
      .to.emit(vault, "Paused")
      .withArgs(manager.address);
    expect(await vault.paused()).to.be.equal(true);

    const {
      amount0: amount0ToAdd,
      amount1: amount1ToAdd,
      mintAmount,
    } = await vault.getMintAmounts(amount0, amount1);

    await expect(
      vault.mint(mintAmount, [amount0ToAdd, amount1ToAdd])
    ).to.be.revertedWith("Pausable: paused");
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
    expect(await token0.balanceOf(univ3Pool.address)).to.be.equal(0);
    expect(await token1.balanceOf(univ3Pool.address)).to.be.equal(0);

    await expect(vault.mint(mintAmount, [_amount0, _amount1]))
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
    expect(await vault.userCount()).to.be.equal(1);
  });

  it("should not mint when min amounts are not satisfied", async () => {
    const {
      mintAmount,
      // eslint-disable-next-line @typescript-eslint/naming-convention
      amount0: _amount0,
      // eslint-disable-next-line @typescript-eslint/naming-convention
      amount1: _amount1,
    } = await vault.getMintAmounts(amount0, amount1);

    await expect(
      vault.mint(mintAmount, [_amount0.div(2), _amount1.div(2)])
    ).to.be.revertedWithCustomError(vault, "SlippageExceedThreshold");
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
    await expect(vault.mint(mintAmount, [_amount0, _amount1]))
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

    const { amount0Current, amount1Current } =
      await vault.getUnderlyingBalances();
    const shares = await vault.balanceOf(manager.address);
    const totalShares = await vault.totalSupply();
    const expectedAmount0 = shares.mul(amount0Current).div(totalShares);
    const expectedAmount1 = shares.mul(amount1Current).div(totalShares);

    const { amount0: amount0Got, amount1: amount1Got } =
      await vault.getUnderlyingBalancesByShare(shares);

    expect(amount0Got).to.be.equal(expectedAmount0);
    expect(amount1Got).to.be.equal(expectedAmount1);
  });

  it("should transfer vault shares to user2", async () => {
    const userBalance = await vault.balanceOf(manager.address);
    const transferAmount = ethers.utils.parseEther("1");
    const userVault0 = (await vault.userVaults(manager.address)).token0;
    const userVault1 = (await vault.userVaults(manager.address)).token1;

    const vault0Moved = userVault0.sub(
      userVault0.mul(userBalance.sub(transferAmount)).div(userBalance)
    );
    const vault1Moved = userVault1.sub(
      userVault1.mul(userBalance.sub(transferAmount)).div(userBalance)
    );
    await vault.transfer(user2.address, transferAmount);

    let userVaults = await vault.getUserVaults(0, 2);
    expect(userVaults[0].user).to.be.equal(manager.address);
    expect(userVaults[0].token0).to.be.equal(userVault0.sub(vault0Moved));
    expect(userVaults[0].token1).to.be.equal(userVault1.sub(vault1Moved));
    expect(await vault.userCount()).to.be.equal(2);

    expect(userVaults[1].user).to.be.equal(user2.address);
    expect(userVaults[1].token0).to.be.equal(vault0Moved);
    expect(userVaults[1].token1).to.be.equal(vault1Moved);

    const user2Balance = await vault.balanceOf(user2.address);
    const user2Vault0 = (await vault.userVaults(user2.address)).token0;
    const user2Vault1 = (await vault.userVaults(user2.address)).token1;
    await vault.connect(user2).transfer(manager.address, user2Balance);

    userVaults = await vault.getUserVaults(0, 2);
    expect(userVaults[0].token0).to.be.equal(userVault0);
    expect(userVaults[0].token1).to.be.equal(userVault1);

    expect(userVaults[1].token0).to.be.equal(bn(0));
    expect(userVaults[1].token1).to.be.equal(bn(0));
  });

  it("should not burn non existing vault shares", async () => {
    const burnAmount = parseEther("1");
    await expect(
      vault.connect(user2).burn(burnAmount, [0, 0])
    ).to.be.revertedWith("ERC20: burn amount exceeds balance");
  });

  it("should not burn when min amounts are not satisfied", async () => {
    const burnAmount = await vault.balanceOf(manager.address);
    const { amount0: minAmount0Out, amount1: minAmount1Out } =
      await vault.getUnderlyingBalancesByShare(burnAmount);
    await expect(
      vault.burn(burnAmount, [minAmount0Out.mul(2), minAmount1Out.mul(2)])
    ).to.be.revertedWithCustomError(vault, "SlippageExceedThreshold");
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

    const { amount0: amount0Out, amount1: amount1Out } =
      await vault.getUnderlyingBalancesByShare(burnAmount);
    await expect(vault.burn(burnAmount, [amount0Out, amount1Out]))
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
    const {
      amount0: amount0ToAdd,
      amount1: amount1ToAdd,
      mintAmount,
    } = await vault.getMintAmounts(amount0, amount1);
    await vault.mint(mintAmount, [amount0ToAdd, amount1ToAdd]);

    await vault.removeLiquidity([0, 0]);
    const burnAmount = await vault.balanceOf(manager.address);
    const { amount0: amount0Out, amount1: amount1Out } =
      await vault.getUnderlyingBalancesByShare(burnAmount);
    await vault.burn(burnAmount, [amount0Out, amount1Out]);

    await expect(vault.mint(1, [0, 0])).to.be.revertedWithCustomError(
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
      const {
        amount0: amount0ToAdd,
        amount1: amount1ToAdd,
        mintAmount,
      } = await vault.getMintAmounts(amount0, amount1);
      await vault.mint(mintAmount, [amount0ToAdd, amount1ToAdd]);
    });

    it("should not remove liquidity by non-manager", async () => {
      await expect(
        vault.connect(nonManager).removeLiquidity([0, 0])
      ).to.be.revertedWith("Ownable: caller is not the manager");
    });

    it("should remove liquidity by manager", async () => {
      expect(await vault.lowerTick()).to.not.be.equal(await vault.upperTick());
      expect(await vault.inThePosition()).to.be.equal(true);
      const { _liquidity: liquidityBefore } = await univ3Pool.positions(
        position(vault.address, lowerTick, upperTick)
      );
      expect(liquidityBefore).not.to.be.equal(0);

      const { fee0, fee1 } = await vault.getCurrentFees();
      await expect(vault.removeLiquidity([0, 0]))
        .to.emit(vault, "InThePositionStatusSet")
        .withArgs(false)
        .to.emit(vault, "FeesEarned")
        .withArgs(fee0, fee1);

      expect(await vault.lowerTick()).to.be.equal(await vault.upperTick());
      expect(await vault.inThePosition()).to.be.equal(false);
      const { _liquidity: liquidityAfter } = await univ3Pool.positions(
        position(vault.address, lowerTick, upperTick)
      );
      expect(liquidityAfter).to.be.equal(0);
    });

    it("should burn vault shares when liquidity is removed", async () => {
      const { _liquidity: liquidity } = await univ3Pool.positions(
        position(vault.address, lowerTick, upperTick)
      );

      expect(liquidity).to.be.equal(0);
      await expect(vault.removeLiquidity([0, 0]))
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

      const { amount0: amount0Out, amount1: amount1Out } =
        await vault.getUnderlyingBalancesByShare(vaultShares);
      await expect(
        vault.burn(vaultShares, [amount0Out, amount1Out])
      ).not.to.emit(vault, "FeesEarned");
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
      await vault.updateTicks(lowerTick, upperTick);
    });

    beforeEach(async () => {
      await token0.approve(vault.address, amount0.mul(bn(2)));
      await token1.approve(vault.address, amount1.mul(bn(2)));
      const {
        amount0: amount0ToAdd,
        amount1: amount1ToAdd,
        mintAmount,
      } = await vault.getMintAmounts(amount0, amount1);
      await vault.mint(mintAmount, [amount0ToAdd, amount1ToAdd]);
      await vault.removeLiquidity([0, 0]);
    });

    it("should not add liquidity by non-manager", async () => {
      const amount0 = await token0.balanceOf(vault.address);
      const amount1 = await token1.balanceOf(vault.address);

      await expect(
        vault
          .connect(nonManager)
          .addLiquidity(lowerTick, upperTick, amount0, amount1, [0, 0])
      ).to.be.revertedWith("Ownable: caller is not the manager");
    });

    it("should not add liquidity when max amounts are not satisfied", async () => {
      const { amount0Current, amount1Current } =
        await vault.getUnderlyingBalances();

      await expect(
        vault.addLiquidity(
          lowerTick,
          upperTick,
          amount0Current,
          amount1Current,
          [amount0Current, amount1Current.div(2)]
        )
      ).to.be.revertedWithCustomError(vault, "SlippageExceedThreshold");
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
      const sqrtPriceA = new Decimal(1.0001)
        .pow(lowerTick)
        .sqrt()
        .mul(new Decimal(2).pow(96))
        .round()
        .toFixed();
      const sqrtPriceB = new Decimal(1.0001)
        .pow(upperTick)
        .sqrt()
        .mul(new Decimal(2).pow(96))
        .round()
        .toFixed();
      const liquidityToAdd = await mockLiquidityAmounts.getLiquidityForAmounts(
        sqrtPriceX96,
        sqrtPriceA,
        sqrtPriceB,
        await token0.balanceOf(vault.address),
        await token1.balanceOf(vault.address)
      );
      const { amount0: amount0ToAdd, amount1: amount1ToAdd } =
        await mockLiquidityAmounts.getAmountsForLiquidity(
          sqrtPriceX96,
          sqrtPriceA,
          sqrtPriceB,
          liquidityToAdd
        );
      await expect(
        vault.addLiquidity(lowerTick, upperTick, amount0ToAdd, amount1ToAdd, [
          amount0ToAdd.mul(10100).div(10000),
          amount1ToAdd.mul(10100).div(10000),
        ])
      )
        .to.emit(vault, "LiquidityAdded")
        .withArgs(liquidityToAdd, lowerTick, upperTick, anyValue, anyValue)
        .to.emit(vault, "InThePositionStatusSet")
        .withArgs(true);
    });

    it("should not add liquidity when in the position", async () => {
      const { amount0Current, amount1Current } =
        await vault.getUnderlyingBalances();

      await vault.addLiquidity(
        lowerTick,
        upperTick,
        amount0Current,
        amount1Current,
        [
          amount0Current.mul(10100).div(10000),
          amount1Current.mul(10100).div(10000),
        ]
      );
      await expect(
        vault.addLiquidity(
          lowerTick,
          upperTick,
          amount0Current,
          amount1Current,
          [0, 0]
        )
      ).to.be.revertedWithCustomError(vault, "LiquidityAlreadyAdded");
    });
  });

  describe("Swap", () => {
    it("should fail when minAmountIn is not satisfied", async () => {
      const { sqrtPriceX96 } = await univ3Pool.slot0();
      const liquidity = await univ3Pool.liquidity();
      await token1.transfer(vault.address, amount1);
      const priceDiff = amount1.mul(bn(2).pow(96)).div(liquidity);
      const priceNext = sqrtPriceX96.add(priceDiff);
      const ONE = bn(1).mul(bn(2).pow(96));
      const minAmountIn = ONE.mul(ONE)
        .div(priceNext)
        .sub(ONE.mul(ONE).div(sqrtPriceX96))
        .mul(liquidity)
        .div(bn(2).pow(96))
        .mul(2);

      await expect(
        vault.swap(false, amount1, priceNext, (-minAmountIn).toString())
      ).to.be.revertedWithCustomError(vault, "SlippageExceedThreshold");
    });
  });

  describe("Fee collection", () => {
    it("non-manager should not collect fee", async () => {
      const { sqrtPriceX96 } = await univ3Pool.slot0();
      const liquidity = await univ3Pool.liquidity();
      await token1.transfer(vault.address, amount1);
      const priceDiff = amount1.mul(bn(2).pow(96)).div(liquidity);
      const priceNext = sqrtPriceX96.add(priceDiff);
      const ONE = bn(1).mul(bn(2).pow(96));
      let minAmountIn = ONE.mul(ONE)
        .div(priceNext)
        .sub(ONE.mul(ONE).div(sqrtPriceX96))
        .mul(liquidity)
        .div(bn(2).pow(96));

      minAmountIn = minAmountIn.mul(bn(9_900)).div(bn(10_000));
      await vault.swap(false, amount1, priceNext, (-minAmountIn).toString());

      const { fee0, fee1 } = await vault.getCurrentFees();
      await expect(vault.pullFeeFromPool())
        .to.emit(vault, "FeesEarned")
        .withArgs(fee0, fee1);

      await expect(
        vault.connect(nonManager).collectManager()
      ).to.be.revertedWith("Ownable: caller is not the manager");
    });

    it("should manager collect fee", async () => {
      const { sqrtPriceX96 } = await univ3Pool.slot0();
      const liquidity = await univ3Pool.liquidity();
      await token1.transfer(vault.address, amount1);
      const priceDiff = amount1.mul(bn(2).pow(96)).div(liquidity);
      const priceNext = sqrtPriceX96.add(priceDiff);
      const ONE = bn(1).mul(bn(2).pow(96));
      let minAmountIn = ONE.mul(ONE)
        .div(priceNext)
        .sub(ONE.mul(ONE).div(sqrtPriceX96))
        .mul(liquidity)
        .div(bn(2).pow(bn(96)));
      minAmountIn = minAmountIn.mul(bn(9_900)).div(bn(10_000));
      await vault.swap(false, amount1, priceNext, (-minAmountIn).toString());

      const { fee0, fee1 } = await vault.getCurrentFees();
      await expect(vault.pullFeeFromPool())
        .to.emit(vault, "FeesEarned")
        .withArgs(fee0, fee1);

      const managerBalance0 = await vault.managerBalance0();
      const managerBalance1 = await vault.managerBalance1();

      const managerBalance0Before = await token0.balanceOf(manager.address);
      const managerBalance1Before = await token1.balanceOf(manager.address);
      await vault.connect(manager).collectManager();

      expect(await token0.balanceOf(manager.address)).to.be.equal(
        managerBalance0Before.add(managerBalance0)
      );
      expect(await token1.balanceOf(manager.address)).to.be.equal(
        managerBalance1Before.add(managerBalance1)
      );

      expect(await vault.managerBalance0()).to.be.equal(0);
      expect(await vault.managerBalance1()).to.be.equal(0);
    });

    it("pull fee using updateFee function", async () => {
      const { sqrtPriceX96 } = await univ3Pool.slot0();
      const liquidity = await univ3Pool.liquidity();
      await token1.transfer(vault.address, amount1);
      const priceDiff = amount1.mul(bn(2).pow(96)).div(liquidity);
      const priceNext = sqrtPriceX96.add(priceDiff);
      const ONE = bn(1).mul(bn(2).pow(96));
      let minAmountIn = ONE.mul(ONE)
        .div(priceNext)
        .sub(ONE.mul(ONE).div(sqrtPriceX96))
        .mul(liquidity)
        .div(bn(2).pow(bn(96)));

      minAmountIn = minAmountIn.mul(bn(9_900)).div(bn(10_000));

      await vault.swap(false, amount1, priceNext, (-minAmountIn).toString());
      const { fee0, fee1 } = await vault.getCurrentFees();
      await expect(vault.updateFees(0, 0))
        .to.emit(vault, "FeesEarned")
        .withArgs(fee0, fee1);

      const managerBalance0 = await vault.managerBalance0();
      const managerBalance1 = await vault.managerBalance1();
      const managerBalance0Before = await token0.balanceOf(manager.address);
      const managerBalance1Before = await token1.balanceOf(manager.address);
      await vault.connect(manager).collectManager();

      expect(await token0.balanceOf(manager.address)).to.be.equal(
        managerBalance0Before.add(managerBalance0)
      );
      expect(await token1.balanceOf(manager.address)).to.be.equal(
        managerBalance1Before.add(managerBalance1)
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

    it("an EOA address provided as implementation should not upgrade the contract", async () => {
      const newVaultImpl = manager.address;
      await expect(
        factory.upgradeVault(vault.address, newVaultImpl)
      ).to.be.revertedWithCustomError(factory, "ImplIsNotAContract");
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
