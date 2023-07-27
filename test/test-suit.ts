import { ethers } from "hardhat";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/dist/src/signer-with-address";
import {
  IERC20,
  IPancakeV3Factory,
  IPancakeV3Pool,
  RangeProtocolVault,
  RangeProtocolFactory,
  // NativeTokenSupport,
  IWETH9,
  LogicLib,
} from "../typechain";
import {
  bn,
  encodePriceSqrt,
  getInitializeData,
  parseEther,
  position,
  setStorageAt,
} from "./common";
import { expect } from "chai";

let user: SignerWithAddress;
let factory: RangeProtocolFactory;
let vault: RangeProtocolVault;
let token0: IERC20;
let token1: IERC20;
let logicLib: LogicLib;
const WETH9 = "0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c";
const poolFee = 10000;
let isToken0Native: boolean;

describe.only("RangeProtocolVault", () => {
  before(async () => {
    [user] = await ethers.getSigners();
    const pancakeFactory = (await ethers.getContractAt(
      "IPancakeV3Factory",
      "0x0BFbCF9fa4f9C56B0F40a671Ad40E0805A091865"
    )) as IPancakeV3Factory;
    const factory = (await (
      await ethers.getContractFactory("RangeProtocolFactory")
    ).deploy(pancakeFactory.address)) as RangeProtocolFactory;
    const MockERC20 = await ethers.getContractFactory("MockERC20");
    token0 = (await ethers.getContractAt("IWETH9", WETH9)) as IWETH9;
    token1 = (await (
      await ethers.getContractFactory("MockERC20")
    ).deploy()) as IERC20;
    setStorageAt(
      token0.address,
      ethers.utils.keccak256(
        ethers.utils.defaultAbiCoder.encode(
          ["address", "uint256"],
          [user.address, 3]
        )
      ),
      ethers.utils.hexlify(ethers.utils.zeroPad("0x152D02C7E14AF6800000", 32))
    );
    if (bn(token0.address).gt(bn(token1.address)))
      [token0, token1] = [token1, token0];
    await pancakeFactory.createPool(token0.address, token1.address, poolFee);
    const pool = (await ethers.getContractAt(
      "IPancakeV3Pool",
      await pancakeFactory.getPool(token0.address, token1.address, poolFee)
    )) as IPancakeV3Pool;
    await pool.initialize(encodePriceSqrt("1", "1"));
    await pool.increaseObservationCardinalityNext("15");
    logicLib = (await (
      await ethers.getContractFactory("LogicLib")
    ).deploy()) as LogicLib;
    const vaultImpl = await (
      await ethers.getContractFactory("RangeProtocolVault", {
        libraries: {
          LogicLib: logicLib.address,
        },
      })
    ).deploy();
    const initializeData = getInitializeData({
      managerAddress: user.address,
      name: "TEST",
      symbol: "TEST Token",
      WETH9: WETH9,
    });
    await factory.createVault(
      token0.address,
      token1.address,
      poolFee,
      vaultImpl.address,
      initializeData
    );
    vault = (await ethers.getContractAt(
      "RangeProtocolVault",
      (
        await factory.getVaultAddresses(0, 0)
      )[0]
    )) as RangeProtocolVault;
    isToken0Native = (await vault.token0()) === WETH9;
    await vault.updateTicks(-200, 200);
  });

  it("should mint with ERC20 tokens", async () => {
    const maxAmount0 = ethers.utils.parseEther("2000");
    const maxAmount1 = ethers.utils.parseEther("3000");
    const { amount0, amount1, mintAmount } = await vault.getMintAmounts(
      maxAmount0,
      maxAmount1
    );
    await token0.approve(vault.address, amount0);
    await token1.approve(vault.address, amount1);

    console.log("*** BEFORE ***");
    console.log(
      "token0: ",
      ethers.utils.formatEther(await token0.balanceOf(user.address))
    );
    console.log(
      "token1: ",
      ethers.utils.formatEther(await token1.balanceOf(user.address))
    );
    console.log(
      "balance: ",
      ethers.utils.formatEther(await vault.balanceOf(user.address))
    );
    await vault.mint(mintAmount, false);
    console.log("*** AFTER ***");
    console.log(
      "token0: ",
      ethers.utils.formatEther(await token0.balanceOf(user.address))
    );
    console.log(
      "token1: ",
      ethers.utils.formatEther(await token1.balanceOf(user.address))
    );
    console.log(
      "balance: ",
      ethers.utils.formatEther(await vault.balanceOf(user.address))
    );
  });

  it.skip("should revert sending native asset when minting with ERC20 tokens", async () => {
    const maxAmount0 = ethers.utils.parseEther("2000");
    const maxAmount1 = ethers.utils.parseEther("3000");
    const { amount0, amount1, mintAmount } = await vault.getMintAmounts(
      maxAmount0,
      maxAmount1
    );
    await expect(
      vault.mint(mintAmount, false, {
        value: ethers.utils.parseEther("1"),
      })
    ).to.be.revertedWithCustomError(logicLib, "NativeTokenSent");
  });

  it("should mint with native asset", async () => {
    const maxAmount0 = ethers.utils.parseEther("1");
    const maxAmount1 = ethers.utils.parseEther("2");
    const { amount0, amount1, mintAmount } = await vault.getMintAmounts(
      maxAmount0,
      maxAmount1
    );
    isToken0Native
      ? await token1.approve(vault.address, amount1)
      : await token0.approve(vault.address, amount0);
    console.log("*** BEFORE ***");
    console.log(
      "token0: ",
      ethers.utils.formatEther(await token0.balanceOf(user.address))
    );
    console.log(
      "token1: ",
      ethers.utils.formatEther(await token1.balanceOf(user.address))
    );
    console.log(
      "balance: ",
      ethers.utils.formatEther(await vault.balanceOf(user.address))
    );
    console.log(
      "native asset: ",
      ethers.utils.formatEther(await ethers.provider.getBalance(user.address))
    );
    console.log("*** DATA ***");
    const nativeAmount = isToken0Native ? amount0 : amount1;
    console.log("native amount: ", ethers.utils.formatEther(nativeAmount));
    const { cumulativeGasUsed, effectiveGasPrice } = await (
      await vault.mint(mintAmount, true, {
        value: nativeAmount,
      })
    ).wait();
    console.log(
      "native amount consumed in gas: ",
      ethers.utils.formatEther(bn(cumulativeGasUsed).mul(bn(effectiveGasPrice)))
    );
    console.log("*** AFTER ***");
    console.log(
      "token0: ",
      ethers.utils.formatEther(await token0.balanceOf(user.address))
    );
    console.log(
      "token1: ",
      ethers.utils.formatEther(await token1.balanceOf(user.address))
    );
    console.log(
      "balance: ",
      ethers.utils.formatEther(await vault.balanceOf(user.address))
    );
    console.log(
      "native asset: ",
      ethers.utils.formatEther(await ethers.provider.getBalance(user.address))
    );
  });
});
