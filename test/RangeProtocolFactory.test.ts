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
import { bn, getInitializeData, ZERO_ADDRESS } from "./common";
import { Contract } from "ethers";

let factory: RangeProtocolFactory;
let vaultImpl: RangeProtocolVault;
let algebraFactory: IAlgebraFactory;
let algebraPool: IAlgebraPool;
let token0: IERC20;
let token1: IERC20;
let owner: SignerWithAddress;
let nonOwner: SignerWithAddress;
let newOwner: SignerWithAddress;
const name = "Test Token";
const symbol = "TT";
let initializeData: any;

describe("RangeProtocolFactory", () => {
  before(async function () {
    [owner, nonOwner, newOwner] = await ethers.getSigners();

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
    expect(await factory.factory()).to.be.equal(algebraFactory.address);
    expect(await factory.owner()).to.be.equal(owner.address);
  });

  it("should not deploy a vault with one of the tokens being zero", async function () {
    await expect(
      factory.createVault(
        ZERO_ADDRESS,
        token1.address,
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
          vaultImpl.address,
          initializeData
        )
    ).to.be.reverted;
  });

  it("owner should be able to deploy vault", async function () {
    await expect(
      factory.createVault(
        token0.address,
        token1.address,
        vaultImpl.address,
        initializeData
      )
    )
      .to.emit(factory, "VaultCreated")
      .withArgs((algebraPool as Contract).address, anyValue);

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
        vaultImpl.address,
        initializeData
      )
    )
      .to.emit(factory, "VaultCreated")
      .withArgs((algebraPool as Contract).address, anyValue);

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
