import { ethers } from "hardhat";
import { getInitializeData } from "../test/common";

async function main() {
  const [manager] = await ethers.getSigners();
  const RangeProtocolFactoryAddress = "0x773330693cb7d5D233348E25809770A32483A940";

  const token0 = "0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2";
  const token1 = "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48";
  const fee = 10000;
  const treasuryAddress = manager.address;
  const managerAddress = manager.address;
  const managerFee = 500;
  const lowerTick = -50000;
  const upperTick = -40000;
  const name = "Test Token";
  const symbol = "TT";

  const factory = await ethers.getContractAt("RangeProtocolFactory", RangeProtocolFactoryAddress);

  const RangeProtocolVault = await ethers.getContractFactory(
    "RangeProtocolVault"
  );
  const vaultImpl = await RangeProtocolVault.deploy();
  const data = getInitializeData({
    treasuryAddress,
    managerAddress,
    managerFee,
    name,
    symbol,
  });

  const tx = await factory.createVault(
    token0,
    token1,
    fee,
    vaultImpl.address,
    data
  );
  const txReceipt = await tx.wait();
  const [
    {
      args: { vault },
    },
  ] = txReceipt.events.filter(
    (event: { event: any }) => event.event === "VaultCreated"
  );
  console.log("Vault: ", vault);
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
