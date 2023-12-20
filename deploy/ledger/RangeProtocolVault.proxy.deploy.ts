import { ethers } from "hardhat";
import { LedgerSigner } from "@anders-t/ethers-ledger";
import { getInitializeData } from "../test/common";

async function main() {
  const provider = ethers.getDefaultProvider(""); // To be updated.
  const ledger = await new LedgerSigner(provider, ""); // To be updated.
  const managerAddress = "0x84b43ce5fB1FAF013181FEA96ffA4af6179e396a"; // To be updated.
  const rangeProtocolFactoryAddress =
    "0x4bF9CDcCE12924B559928623a5d23598ca19367B"; // To be updated.
  const vaultImplAddress = ""; // to be updated.
  const token0 = "0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2";
  const token1 = "0xc944E90C64B2c07662A292be6244BDf05Cda44a7";
  const fee = 3000; // To be updated.
  const name = ""; // To be updated.
  const symbol = ""; // To be updated.

  let factory = await ethers.getContractAt(
    "RangeProtocolFactory",
    rangeProtocolFactoryAddress
  );
  factory = await factory.connect(ledger);
  const data = getInitializeData({
    managerAddress,
    name,
    symbol,
  });

  const tx = await factory.createVault(token0, token1, fee, vaultImplAddress, data);
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
