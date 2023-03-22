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
import { bn, getInitializeData, ZERO_ADDRESS } from "./common";
import { Contract } from "ethers";

let factory: RangeProtocolFactory;
let vaultImpl: RangeProtocolVault;
let uniV3Factory: IUniswapV3Factory;
let univ3Pool: IUniswapV3Pool;
let token0: IERC20;
let token1: IERC20;
let manager: SignerWithAddress;
let treasury: SignerWithAddress;
let nonManager: SignerWithAddress;
let newManager: SignerWithAddress;
const managerFee = 500;
const poolFee = 10000;
const name = "Test Token";
const symbol = "TT";
let initializeData: any;

describe("RangeProtocolFactory", () => {
  before(async function () {
    [manager, nonManager, treasury, newManager] = await ethers.getSigners();
    // eslint-disable-next-line @typescript-eslint/naming-convention
    const UniswapV3Factory = await ethers.getContractFactory(
      "UniswapV3Factory"
    );
    uniV3Factory = (await UniswapV3Factory.deploy()) as IUniswapV3Factory;

    // eslint-disable-next-line @typescript-eslint/naming-convention
    const RangeProtocolFactory = await ethers.getContractFactory(
      "RangeProtocolFactory"
    );
    factory = (await RangeProtocolFactory.deploy(
      uniV3Factory.address
    )) as RangeProtocolFactory;

    // eslint-disable-next-line @typescript-eslint/naming-convention
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
      "IUniswapV3Pool",
      await uniV3Factory.getPool(token0.address, token1.address, poolFee)
    )) as IUniswapV3Pool;

    // eslint-disable-next-line @typescript-eslint/naming-convention
    const RangeProtocolVault = await ethers.getContractFactory(
      "RangeProtocolVault"
    );
    vaultImpl = (await RangeProtocolVault.deploy()) as RangeProtocolVault;

    initializeData = getInitializeData({
      treasuryAddress: treasury.address,
      managerAddress: manager.address,
      managerFee,
      name,
      symbol,
    });
  });

  it("should deploy RangeProtocolFactory", async function () {
    expect(await factory.factory()).to.be.equal(uniV3Factory.address);
    expect(await factory.manager()).to.be.equal(manager.address);
  });

  it("should not deploy a vault with one of the tokens being zero", async function () {
    await expect(
      factory.createVault(
        ZERO_ADDRESS,
        token1.address,
        poolFee,
        vaultImpl.address,
        initializeData
      )
    ).to.be.revertedWith("ZeroPoolAddress()");
  });

  it("should not deploy a vault both tokens being the same", async function () {
    await expect(
      factory.createVault(
        token0.address,
        token0.address,
        poolFee,
        vaultImpl.address,
        initializeData
      )
    ).to.be.revertedWith("ZeroPoolAddress()");
  });

  it("non-manager should not be able to deploy vault", async function () {
    await expect(
      factory
        .connect(nonManager)
        .createVault(
          token0.address,
          token1.address,
          poolFee,
          vaultImpl.address,
          initializeData
        )
    ).to.be.revertedWith("Ownable: caller is not the manager");
  });

  it("manager should be able to deploy vault", async function () {
    await expect(
      factory.createVault(
        token0.address,
        token1.address,
        poolFee,
        vaultImpl.address,
        initializeData
      )
    )
      .to.emit(factory, "VaultCreated")
      .withArgs((univ3Pool as Contract).address, anyValue);
  });

  it("should not redeploy a duplicate vault", async function () {
    await expect(
      factory.createVault(
        token0.address,
        token1.address,
        poolFee,
        vaultImpl.address,
        initializeData
      )
    ).to.be.revertedWith("VaultAlreadyExists()");
  });

  describe("transferOwnership", () => {
    it("should not be able to transferOwnership by non manager", async () => {
      await expect(
        factory.connect(nonManager).transferOwnership(newManager.address)
      ).to.be.revertedWith("Ownable: caller is not the manager");
    });

    it("should be able to transferOwnership by manager", async () => {
      await expect(factory.transferOwnership(newManager.address))
        .to.emit(factory, "OwnershipTransferred")
        .withArgs(manager.address, newManager.address);
      expect(await factory.manager()).to.be.equal(newManager.address);

      await factory.connect(newManager).transferOwnership(manager.address);
      expect(await factory.manager()).to.be.equal(manager.address);
    });
  });
});
