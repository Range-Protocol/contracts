import { ethers } from "hardhat";
import { LedgerSigner } from "@anders-t/ethers-ledger";
import { getInitializeData } from "../test/common";

async function main() {
  const provider = ethers.getDefaultProvider(""); // To be updated.
  const ledger = await new LedgerSigner(provider, ""); // To be updated.
  const manager = ""; // To be updated.
  const treasuryAddress = manager; // To be updated.
  const managerAddress = manager; // To be updated.
  const RangeProtocolFactoryAddress = "0x773330693cb7d5D233348E25809770A32483A940"; // To be updated.
  const token0 = "0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2";
  const token1 = "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48";
  const fee = 10000; // To be updated.
  const managerFee = 500; // To be updated.
  const name = "Test Token"; // To be updated.
  const symbol = "TT"; // To be updated.

  const factory = await ethers.getContractAt(
    "RangeProtocolFactory",
    RangeProtocolFactoryAddress
  );

  let RangeProtocolVault = await ethers.getContractFactory(
    "RangeProtocolVault"
  );
  RangeProtocolVault = await RangeProtocolVault.connect(ledger);
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
