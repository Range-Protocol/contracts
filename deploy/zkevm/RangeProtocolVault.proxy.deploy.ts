import { ethers } from "hardhat";
import { LedgerSigner } from "@anders-t/ethers-ledger";
import { getInitializeData } from "../test/common";

async function main() {
  const provider = ethers.getDefaultProvider(""); // To be updated.
  const ledger = await new LedgerSigner(provider, ""); // To be updated.
  const managerAddress = ""; // To be updated.
  const rangeProtocolFactoryAddress = ""; // To be updated.
  const vaultImplAddress = ""; // to be updated.
  const token0 = "";
  const token1 = "";
  const fee = 0; // To be updated.
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
    // to be updated for pancakeswap
    WETH9: "0x4F9A0e7FD2Bf6067db6994CF12E4495Df938E6e9",
  });

  const tx = await factory.createVault(
    token0,
    token1,
    fee,
    vaultImplAddress,
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
