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
let owner: SignerWithAddress;
let nonOwner: SignerWithAddress;
let newOwner: SignerWithAddress;
const poolFee = 10000;
const name = "Test Token";
const symbol = "TT";
let initializeData: any;

describe("RangeProtocolFactory", () => {
  before(async function () {
    [owner, nonOwner, newOwner] = await ethers.getSigners();
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
      managerAddress: owner.address,
      name,
      symbol,
    });
  });

  it("should deploy RangeProtocolFactory", async function () {
    expect(await factory.factory()).to.be.equal(uniV3Factory.address);
    expect(await factory.owner()).to.be.equal(owner.address);
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

  it("should not deploy a vault with both tokens being the same", async function () {
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

  it("should not deploy vault with zero manager address", async function () {
    await expect(
      factory.createVault(
        token0.address,
        token1.address,
        poolFee,
        vaultImpl.address,
        getInitializeData({
          managerAddress: ZERO_ADDRESS,
          name,
          symbol,
        })
      )
    ).to.be.revertedWith("ZeroManagerAddress()");
  });

  it("non-owner should not be able to deploy vault", async function () {
    await expect(
      factory
        .connect(nonOwner)
        .createVault(
          token0.address,
          token1.address,
          poolFee,
          vaultImpl.address,
          initializeData
        )
    ).to.be.revertedWith("Ownable: caller is not the owner");
  });

  it("owner should be able to deploy vault", async function () {
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

    expect(await factory.vaultCount()).to.be.equal(1);
    expect((await factory.getVaultAddresses(0, 0))[0]).to.not.be.equal(
      ethers.constants.AddressZero
    );
  });

  it("should allow deploying vault with duplicate pairs", async function () {
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

    expect(await factory.vaultCount()).to.be.equal(2);
    const vault0Address = (await factory.getVaultAddresses(0, 0))[0];
    const vault1Address = (await factory.getVaultAddresses(1, 1))[0];

    expect(vault0Address).to.not.be.equal(ethers.constants.AddressZero);
    expect(vault1Address).to.not.be.equal(ethers.constants.AddressZero);

    const dataABI = new ethers.utils.Interface([
      "function token0() returns (address)",
      "function token1() returns (address)",
    ]);

    expect(vault0Address).to.be.not.equal(vault1Address);
    expect(
      await ethers.provider.call({
        to: vault0Address,
        data: dataABI.encodeFunctionData("token0"),
      })
    ).to.be.equal(
      await ethers.provider.call({
        to: vault1Address,
        data: dataABI.encodeFunctionData("token0"),
      })
    );

    expect(
      await ethers.provider.call({
        to: vault0Address,
        data: dataABI.encodeFunctionData("token1"),
      })
    ).to.be.equal(
      await ethers.provider.call({
        to: vault1Address,
        data: dataABI.encodeFunctionData("token1"),
      })
    );
  });

  describe("transferOwnership", () => {
    it("should not be able to transferOwnership by non owner", async () => {
      await expect(
        factory.connect(nonOwner).transferOwnership(newOwner.address)
      ).to.be.revertedWith("Ownable: caller is not the owner");
    });

    it("should be able to transferOwnership by owner", async () => {
      await expect(factory.transferOwnership(newOwner.address))
        .to.emit(factory, "OwnershipTransferred")
        .withArgs(owner.address, newOwner.address);
      expect(await factory.owner()).to.be.equal(newOwner.address);

      await factory.connect(newOwner).transferOwnership(owner.address);
      expect(await factory.owner()).to.be.equal(owner.address);
    });
  });
});
